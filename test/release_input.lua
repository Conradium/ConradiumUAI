-- Focused input ownership and partial-outcome regressions. Native/executor APIs
-- are synthetic; these do not verify actual Roblox host input injection.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("v3 input ownership")
local check, case = suite.check, suite.case
local function fixture()
	local f = F.new()
	f.h.services.VirtualInputManager, f.h.services.VirtualUser = {}, {}
	f.tools({ "input" })
	return f, { session = {}, aborted = function() return false end }
end

case("accepted down with failed release never repeats through another provider", function()
	for _, name in ipairs({ "key_press", "mouse_click" }) do
		local f, ctx = fixture(); local downs, ups, fallback = 0, 0, 0
		local function send(down)
			if down then downs = downs + 1 else ups = ups + 1; return false end
		end
		f.h.services.VirtualInputManager.SendKeyEvent = function(_, down) return send(down) end
		f.h.services.VirtualInputManager.SendMouseButtonEvent = function(_, _, _, _, down) return send(down) end
		f.h.sandbox.keypress = function() fallback = fallback + 1 end
		f.h.sandbox.keyrelease = function() end
		f.h.sandbox.mouse1click = function() fallback = fallback + 1 end
		local result = f.dispatch(name, { key = "E" }, ctx)
		check("partial action remains owned and reports release failure", not result.ok and result.data.status == "release_failed" and result.data.held)
		check("accepted input is sent only once", downs == 1 and ups == 1 and fallback == 0)
		f.healthy(); f.close()
	end
end)

case("unknown down outcome attempts same-provider release without fallback", function()
	local f, ctx = fixture(); local releases, fallback = 0, 0
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down)
		if down then error("native outcome unknown") end
		releases = releases + 1
	end
	f.h.sandbox.keypress = function() fallback = fallback + 1 end
	f.h.sandbox.keyrelease = function() end
	local result = f.dispatch("key_press", { key = "E" }, ctx)
	check("uncertainty is explicit", not result.ok and result.data.status == "unknown" and not result.data.held)
	check("unknown input is not duplicated", releases == 1 and fallback == 0)
	f.healthy(); f.close()
end)

case("explicit provider refusal permits fallback", function()
	local f, ctx = fixture(); local refused, down, up = 0, 0, 0
	f.h.services.VirtualInputManager.SendKeyEvent = function() refused = refused + 1; return false end
	f.h.sandbox.keypress = function() down = down + 1 end
	f.h.sandbox.keyrelease = function() up = up + 1 end
	local result = f.dispatch("key_press", { key = "E" }, ctx)
	check("known refusal falls through exactly once", result.ok and result.data.provider == "executor" and refused == 1 and down == 1 and up == 1)
	f.healthy(); f.close()
end)

case("holds belong to the conversation and release through their original provider", function()
	local f, ctx = fixture(); local original, replacement = 0, 0
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down) if not down then original = original + 1 end end
	check("down creates a retained hold", f.dispatch("key_press", { key = "E", action = "down" }, ctx).data.held)
	check("duplicate down is rejected", not f.dispatch("key_press", { key = "E", action = "down" }, ctx).ok)
	check("other conversations cannot release the hold", not f.dispatch("key_press", { key = "E", action = "up" }).ok)
	f.h.services.VirtualInputManager = { SendKeyEvent = function() replacement = replacement + 1 end }
	local result = f.dispatch("key_press", { key = "E", action = "up" }, ctx)
	check("up preserves provider ownership across discovery changes", result.ok and not result.data.held and original == 1 and replacement == 0)
	f.healthy(); f.close()
end)

case("persistent holds clean up on Stop, epoch replacement, revocation and unload", function()
	for _, trigger in ipairs({ "stop", "epoch", "permission", "unload" }) do
		local f = fixture(); local releases = 0
		f.h.services.VirtualInputManager.SendKeyEvent = function(_, down) if not down then releases = releases + 1 end end
		local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
		check("owned down succeeds", f.dispatch("key_press", { key = "E", action = "down" }, session.toolContext()).ok)
		if trigger == "stop" then session.abort()
		elseif trigger == "epoch" then session.toolEpoch = {}
		elseif trigger == "permission" then f.env.require("agent/permissions").setRule("key_press", "deny")
		else f.close() end
		f.h.sched.advance(0.2)
		check(trigger .. " releases a completed down", releases == 1)
		f.healthy(); f.close()
	end
end)

case("a failed release remains retryable and Stop tries cleanup again", function()
	local f, ctx = fixture(); local releases, allow = 0, false
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down)
		if not down then releases = releases + 1; return allow end
	end
	check("failed release retains ownership", f.dispatch("key_press", { key = "E" }, ctx).data.held)
	allow = true
	check("explicit up can recover the retained hold", f.dispatch("key_press", { key = "E", action = "up" }, ctx).ok and releases == 2)
	allow = false
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	check("later failed release is also retained", f.dispatch("key_press", { key = "E" }, session.toolContext()).data.held)
	allow = true; session.abort(); f.h.sched.advance(0.2)
	check("Stop retries a prior unsuccessful cleanup", releases == 4)
	f.healthy(); f.close()
end)

case("Stop releases a press without waiting for its full duration", function()
	local f = fixture(); local down, up, result = 0, 0, nil
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, pressed) if pressed then down = down + 1 else up = up + 1 end end
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	f.h.sched.spawn(function()
		result = f.registry.dispatch({ name = "key_press", arguments = '{"key":"E","duration":2}' }, session.toolContext())
	end)
	f.h.sched.advance(0.1); session.abort(); f.h.sched.advance(0.2)
	check("cancelled press settles and releases promptly", result and not result.ok and down == 1 and up == 1)
	f.h.sched.advance(2)
	check("late timer cannot emit another release or down", down == 1 and up == 1)
	f.healthy(); f.close()
end)

case("late native down completion is released again after cancellation", function()
	local f = fixture(); local releases, completed, result = 0, false, nil
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down)
		if down then f.h.sched.wait(1); completed = true else releases = releases + 1 end
	end
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	f.h.sched.spawn(function()
		result = f.registry.dispatch({ name = "key_press", arguments = '{"key":"E","action":"down"}' }, session.toolContext())
	end)
	f.h.sched.advance(0.1); session.abort(); f.h.sched.advance(0.2)
	check("Stop attempts release before native down returns", result and not result.ok and not completed and releases == 1)
	session.abortFlag, session.toolEpoch = false, {}
	f.h.sched.advance(1)
	check("late down cannot revive a cancelled hold", completed and releases == 2)
	f.healthy(); f.close()
end)

case("cleanup up that yields across native down must send a later up", function()
	local f = fixture(); local releases, physicallyDown = 0, false
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down)
		if down then
			f.h.sched.wait(0.2); physicallyDown = true
		else
			releases = releases + 1; physicallyDown = false
			if releases == 1 then f.h.sched.wait(0.4) end
		end
	end
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	f.h.sched.spawn(function()
		f.registry.dispatch({ name = "key_press", arguments = '{"key":"E","action":"down"}' }, session.toolContext())
	end)
	f.h.sched.advance(0.05); session.abort(); f.h.sched.advance(0.25)
	check("the fixture exposes down completing after the first up effect", physicallyDown and releases == 1)
	f.h.sched.advance(0.3)
	check("ownership is cleared only after a release dispatched after down", not physicallyDown and releases == 2)
	f.healthy(); f.close()
end)

case("declined down retains ownership while its earlier release is pending", function()
	local f = fixture(); local downs, ups = 0, 0
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down)
		if down then
			downs = downs + 1
			if downs == 1 then f.h.sched.wait(0.2); return false end
		else
			ups = ups + 1
			if ups == 1 then f.h.sched.wait(0.4) end
		end
	end
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	f.h.sched.spawn(function()
		f.registry.dispatch({ name = "key_press", arguments = '{"key":"E","action":"down"}' }, session.toolContext())
	end)
	f.h.sched.advance(0.05); session.abort(); f.h.sched.advance(0.25)
	session.abortFlag, session.toolEpoch = false, {}
	check("new hold cannot start before the old cleanup finishes", not f.dispatch("key_press", { key = "E", action = "down" }, session.toolContext()).ok and downs == 1)
	f.h.sched.advance(0.2)
	check("a later hold starts after cleanup relinquishes ownership", f.dispatch("key_press", { key = "E", action = "down" }, session.toolContext()).ok and downs == 2 and ups == 2)
	f.healthy(); f.close()
end)

case("one yielding release cannot block cleanup of another held key", function()
	local f = fixture(); local released = {}
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down, key)
		if not down then
			released[key.Name] = true
			if key.Name == "E" then f.h.sched.wait(2) end
		end
	end
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	local ctx = session.toolContext()
	assert(f.dispatch("key_press", { key = "E", action = "down" }, ctx).ok)
	assert(f.dispatch("key_press", { key = "W", action = "down" }, ctx).ok)
	session.abort(); f.h.sched.advance(0.2)
	check("both releases dispatch before the slow one returns", released.E and released.W)
	f.h.sched.advance(2)
	f.healthy(); f.close()
end)

case("explicit up during native down also releases its late completion", function()
	local f, ctx = fixture(); local releases, completed = 0, false
	f.h.services.VirtualInputManager.SendKeyEvent = function(_, down)
		if down then f.h.sched.wait(1); completed = true else releases = releases + 1 end
	end
	f.h.sched.spawn(function()
		f.registry.dispatch({ name = "key_press", arguments = '{"key":"E","action":"down"}' }, ctx)
	end)
	f.h.sched.advance(0.1)
	check("explicit up attempts immediate cleanup", f.dispatch("key_press", { key = "E", action = "up" }, ctx).ok and releases == 1)
	f.h.sched.advance(1)
	check("pending down is cleaned up again", completed and releases == 2)
	f.healthy(); f.close()
end)

case("coordinates never fall back to a click at the wrong cursor position", function()
	local f, ctx = fixture(); local clicks, moved = 0, nil
	f.h.sandbox.mouse1click = function() clicks = clicks + 1 end
	check("executor without positioning cannot accept explicit coordinates", not f.dispatch("mouse_click", { x = 100, y = 200 }, ctx).ok and clicks == 0)
	f.h.sandbox.mousemoveabs = function(x, y) moved = { x, y } end
	local result = f.dispatch("mouse_click", { x = 100, y = 200 }, ctx)
	check("capable executor positions before clicking", result.ok and clicks == 1 and moved[1] == 100 and moved[2] == 200)
	check("executor can also move without clicking", f.dispatch("mouse_click", { action = "move", x = 25, y = 50 }, ctx).ok and clicks == 1 and moved[1] == 25)
	f.healthy(); f.close()
end)

case("cancellation during provider preparation prevents down", function()
	local f = fixture(); local cancelled, downs = false, 0
	f.h.services.VirtualUser.CaptureController = function() cancelled = true end
	f.h.services.VirtualUser.SetKeyDown = function() downs = downs + 1 end
	f.h.services.VirtualUser.SetKeyUp = function() end
	local result = f.dispatch("key_press", { key = "E" }, { session = {}, aborted = function() return cancelled end })
	check("preparation does not bypass cancellation", not result.ok and downs == 0)
	f.healthy(); f.close()
end)

suite.finish()
