-- Focused v3 tool contracts. Synthetic host observations, no network or native input/rendering.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Release tools")
local check = suite.check
local function contains(text, needle) return tostring(text):find(needle, 1, true) ~= nil end
local function fixture(groups)
	local f = F.new()
	f.ctx = { env = f.env, session = {}, aborted = function() return false end }
	if groups then f.tools(groups) end
	function f.call(name, args, seconds) return f.dispatch(name, args, f.ctx, seconds or 0.3) end
	return f
end

suite.case("HTTP status failures and exact JSON keys preserve false values", function()
	local f = fixture(); local sent = {}
	f.loaded["net/http"] = {
		send = function(options)
			sent[#sent + 1] = options
			return { ok = false, status = 503, body = "temporarily unavailable" }
		end,
		json = function(options)
			if contains(options.url, "error") then return nil, "server error", { ok = false, status = 500, body = "failed JSON request" } end
			return { enabled = false, ["a.b"] = { ["01"] = false, [1] = "numeric fallback" } }, nil, { ok = true, status = 200 }
		end,
	}
	f.tools({ "net" })
	check("GET errors are failed calls", not f.call("http_get", { url = "https://example.invalid/error" }).ok)
	check("write errors are failed calls", not f.call("http_request", { url = "https://example.invalid/error", method = "POST", body = "x" }).ok)
	check("write requests cannot silently retry", sent[2].attempts == 1 and sent[2].method == "POST")
	check("JSON HTTP errors cannot be reported as values", not f.call("json_api", { url = "https://example.invalid/error" }).ok)
	local scalar = f.call("json_api", { url = "https://example.invalid/json", path = "enabled" })
	check("false field is present", scalar.ok and scalar.data.value == false)
	local exact = f.call("json_api", { url = "https://example.invalid/json", keys = { "a.b", "01" } })
	check("exact dotted and numeric-looking keys win", exact.ok and exact.data.value == false)
	check("conflicting path selectors are rejected", not f.call("json_api", { url = "https://example.invalid/json", path = "enabled", keys = { "enabled" } }).ok)
	f.healthy(); f.close()
end)

suite.case("HTTP UTF-8 continuations reconstruct one immutable response", function()
	local f = fixture(); local requests = 0
	local body = string.rep("abc\226\128\148", 1400)
	f.loaded["net/http"] = { send = function() requests = requests + 1; return { ok = true, status = 200, body = body } end }
	f.tools({ "net" }); f.env.require("runtime/config").set("agent.resultCap", 4000)
	local first = f.call("http_get", { url = "https://example.invalid/body", limit = 257 })
	check("first page retains a continuation reference", first.ok and first.data.resultId and first.data.nextOffset)
	local resultId, offset = first.data.resultId, first.data.nextOffset
	local pieces, pageCount = { first.text:match("^[^\n]*\n(.*)$") }, 0
	while offset do
		local page = f.call("http_result_read", { result_id = resultId, section = "text", offset = offset })
		check("retained page is readable UTF-8", page.ok and type(page.data.value) == "string" and f.env.require("runtime/util").validUtf8(page.data.value))
		if pageCount == 0 then check("normal budget reads more than the old 600-byte cap", #page.data.value > 600) end
		check("continuation offset names the next exact byte", page.data.offset == offset and (not page.data.nextOffset or page.data.nextOffset == offset + #page.data.value))
		pieces[#pieces + 1], offset, pageCount = page.data.value, page.data.nextOffset, pageCount + 1
		assert(pageCount < 20, "retained text pagination did not advance")
	end
	check("all response bytes arrive without refetch", table.concat(pieces) == body and requests == 1)
	local tiny = f.call("http_result_read", { result_id = resultId, section = "text", offset = 4, limit = 1 })
	check("one-byte requests advance across a complete UTF-8 character", tiny.ok and tiny.data.value == "\226\128\148" and tiny.data.nextOffset == 7)
	check("nonexistent retained paths fail", not f.call("http_result_read", { result_id = resultId, path = { "missing" } }).ok)
	check("retained offsets past the fields fail", not f.call("http_result_read", { result_id = resultId, offset = 100 }).ok)
	local native = f.env.require("tools/native_helpers"); local retain = native.retain
	native.retain = function() return nil end
	local unavailable = f.call("http_get", { url = "https://example.invalid/body", limit = 257 })
	check("unretained bodies do not advertise an unavailable reader", unavailable.ok and unavailable.data.detailsUnavailable and not unavailable.data.resultId and not contains(unavailable.text, "use http_result_read"))
	native.retain = retain; f.healthy(); f.close()
end)

suite.case("retained field previews do not serialize the full large child again", function()
	local f = fixture(); local native, util = f.env.require("tools/native_helpers"), f.env.require("runtime/util")
	local large = string.rep("x", 20000)
	local resultId = assert(native.retain({ source = large, flag = false }, "Large field", "net"))
	local encode = util.encode
	util.encode = function(value)
		assert(value ~= large, "full large child was serialized for its preview")
		return encode(value)
	end
	local page = native.read({ result_id = resultId }, "net")
	util.encode = encode
	check("small fields and source paths remain available", page.ok and #page.data.items == 2 and page.data.items[1].value == false and page.data.items[2].value.bytes == #large)
	check("result references cannot cross groups", not native.read({ result_id = resultId }, "instance").ok)
	f.close()
end)

suite.case("property batches describe clamped writes and setter failures after effects", function()
	local f = fixture(); local H = f.env.require("tools/helpers")
	local values, writes = { Clamped = 1, Throws = 1, Clean = 1 }, 0
	local target = setmetatable({}, {
		__index = values,
		__newindex = function(_, key, value)
			writes = writes + 1
			values[key] = key == "Clamped" and 2 or value
			if key == "Throws" then error("setter failed after changing value") end
		end,
	})
	local result = H.writeProperties(target, { { property = "Clamped", value = 3 }, { property = "Throws", value = 4 }, { property = "Clean", value = 5 } }, "Synthetic fields", f.ctx)
	check("every observed effect is counted", not result.ok and result.data.status == "partial" and result.data.changed == 3 and result.data.failed == 2 and writes == 3)
	check("failed writes still report observed values", result.data.results[1].observed == "2" and result.data.results[2].observed == "4")
	local cancelled = H.writeProperties(target, { { property = "Clean", value = 9 } }, "Cancelled field", { aborted = function() error("lost owner") end })
	check("throwing cancellation prevents another write", not cancelled.ok and writes == 3 and values.Clean == 5)
	local effect, unreadable = 1, false
	local uncertain = setmetatable({}, { __index = function() if unreadable then error("readback denied") end; return effect end,
		__newindex = function(_, _, value) effect, unreadable = value, true end })
	local unknown = H.writeProperties(uncertain, { { property = "Value", value = 2 } }, "Uncertain field", f.ctx)
	check("unreadable effects are explicit partial outcomes", not unknown.ok and unknown.data.status == "partial" and unknown.data.uncertain == 1 and effect == 2)
	f.close()
end)

suite.case("player usernames outrank display names and duplicate display names fail", function()
	local f = fixture({ "players" })
	local players = {
		{ Name = "Earlier", DisplayName = "Alice", UserId = 1 },
		{ Name = "Alice", DisplayName = "Shared", UserId = 2 },
		{ Name = "Another", DisplayName = "Shared", UserId = 3 },
	}
	f.env.players = { GetPlayers = function() return players end }
	local exact = f.call("player_info", { player = "ALICE" })
	check("exact username wins even after an exact display match", exact.ok and contains(exact.text, "Name: Alice") and contains(exact.text, "UserId: 2"))
	local duplicate = f.call("player_info", { player = "Shared" })
	check("ambiguous display identity is never chosen silently", not duplicate.ok and contains(duplicate.text, "several players"))
	f.healthy(); f.close()
end)

suite.case("player list captures positions once before deterministic sorting", function()
	local f = fixture({ "players" }); local reads = {}
	local function player(name, distance)
		local root = setmetatable({}, { __index = function(_, key)
			if key == "Position" then reads[name] = (reads[name] or 0) + 1; return f.h.dt.Vector3.new(distance, 0, 0) end
		end })
		return { Name = name, DisplayName = name, Character = { FindFirstChild = function() return root end } }
	end
	local mine, far, nearB, nearA = player("Self", 0), player("Far", 100), player("NearB", 2), player("NearA", 2)
	f.env.plr = mine; f.env.players = { GetPlayers = function() return { far, nearB, nearA } end }
	local first = f.call("players_list", { limit = 2 })
	check("distance then username determine stable order", first.ok and contains(first.text, "1. NearA 2 studs") and contains(first.text, "2. NearB 2 studs") and first.data.nextOffset == 3)
	check("sort and formatting do not reread positions", reads.Self == 1 and reads.Far == 1 and reads.NearA == 1 and reads.NearB == 1)
	local tail = f.call("players_list", { offset = 3 })
	check("the next page reaches the remaining player", tail.ok and contains(tail.text, "3. Far 100 studs") and tail.data.eof)
	f.healthy(); f.close()
end)

suite.case("character health batches apply maximum before current health", function()
	local f = fixture({ "character" }); local state, writes = { MaxHealth = 100, Health = 90 }, {}
	local humanoid = setmetatable({}, { __index = state, __newindex = function(_, key, value) writes[#writes + 1] = key; state[key] = value end })
	f.env.plr = { Character = { FindFirstChildOfClass = function() return humanoid end, FindFirstChild = function() return nil end } }
	local result = f.call("character_set", { max_health = 200, health = 150 })
	check("dependent health fields have the correct order", result.ok and writes[1] == "MaxHealth" and writes[2] == "Health" and state.Health == 150 and result.data.changed == 2)
	f.healthy(); f.close()
end)

suite.case("camera validates every supplied field before mutating any field", function()
	local f = fixture({ "world" }); local writes = 0
	local state = { FieldOfView = 70, CameraType = f.h.sandbox.Enum.CameraType.Custom, CFrame = f.h.dt.CFrame.new(0, 0, 0) }
	local camera = setmetatable({}, { __index = state, __newindex = function(_, key, value) writes = writes + 1; state[key] = value end })
	f.env.services.Workspace = { CurrentCamera = camera }
	local invalid = f.call("camera_set", { field_of_view = 90, position = "invalid vector" })
	check("invalid later position leaves the earlier FOV untouched", not invalid.ok and writes == 0 and state.FieldOfView == 70)
	local valid = f.call("camera_set", { field_of_view = 90 })
	check("validated changes retain observed write evidence", valid.ok and writes == 1 and state.FieldOfView == 90 and valid.data.changed == 1)
	f.healthy(); f.close()
end)

suite.case("GUI text traversal observes hidden ancestors and includes a text root", function()
	local f = fixture({ "gui" }); local I = f.h.Instance
	local screen = I.new("ScreenGui", f.h.localPlayer:FindFirstChild("PlayerGui")); screen.Name, screen.Enabled = "Inspection", true
	local visible = I.new("TextLabel", screen); visible.Name, visible.Text, visible.Visible = "Visible", "visible label", true
	local hidden = I.new("Frame", screen); hidden.Name, hidden.Visible = "Hidden", false
	local nested = I.new("TextLabel", hidden); nested.Name, nested.Text, nested.Visible = "Nested", "hidden ancestor text", true
	local disabled = I.new("ScreenGui", f.h.localPlayer:FindFirstChild("PlayerGui")); disabled.Name, disabled.Enabled = "Disabled", false
	local off = I.new("TextLabel", disabled); off.Text, off.Visible = "disabled screen text", true
	local bulkReads = 0
	for _, node in ipairs({ screen, visible, hidden, nested, disabled, off, f.h.localPlayer:FindFirstChild("PlayerGui"), f.h.coreGui }) do
		rawset(node, "GetDescendants", function() bulkReads = bulkReads + 1; error("bulk descendant allocation is forbidden") end)
	end
	local page = f.call("gui_text", {})
	check("only effectively visible text is returned", page.ok and contains(page.text, "visible label") and not contains(page.text, "hidden ancestor text") and not contains(page.text, "disabled screen text") and page.data.complete)
	local all = f.call("gui_text", { include_hidden = true })
	check("hidden text is available only when explicitly requested", all.ok and contains(all.text, "hidden ancestor text") and contains(all.text, "disabled screen text"))
	local root = f.call("gui_text", { path = "PlayerGui.Inspection.Visible" })
	check("a selected TextLabel is itself inspected", root.ok and root.data.count == 1 and contains(root.text, "visible label") and bulkReads == 0)
	f.healthy(); f.close()
end)

suite.case("Explorer property and child pages honor useful page sizes", function()
	local f = fixture({ "instance" }); local I = f.h.Instance
	local folder = I.new("Folder", f.h.workspace); folder.Name = "PagedObjects"
	for i = 1, 12 do local child = I.new("Folder", folder); child.Name = string.format("Child%02d", i) end
	local id = f.env.require("runtime/instance_refs").id(folder)
	local children = f.call("explorer_children", { parent_id = id, limit = 9 })
	check("child page is not silently capped at five", children.ok and #children.data.items == 9 and children.data.nextCursor)
	local properties = f.call("explorer_properties", { instance_ids = { id }, fields = { "Name", "ClassName", "Archivable", "Parent" }, limit = 3 })
	check("property page is not silently capped at one", properties.ok and #properties.data.items > 1 and properties.data.nextCursor)
	local tail = f.call("explorer_properties", { cursor = properties.data.nextCursor, limit = 3 })
	check("property continuation keeps its immutable snapshot", tail.ok and tail.data.snapshotId == properties.data.snapshotId and not tail.data.nextCursor)
	check("changed property selectors reject a saved cursor", not f.call("explorer_properties", { cursor = properties.data.nextCursor, fields = { "Name" } }).ok)
	f.healthy(); f.close()
end)

suite.case("selected instance fields never fetch script source or unrelated metadata", function()
	local f = fixture({ "instance" }); local script = f.h.Instance.new("LocalScript", f.h.workspace); script.Name = "SensitiveSource"
	local original, meta, reads = getmetatable(script), {}, { source = 0, attributes = 0, tags = 0 }
	for key, value in pairs(original) do meta[key] = value end
	meta.__index = function(self, key)
		if key == "Source" then reads.source = reads.source + 1; error("source inspection was not requested") end
		return original.__index(self, key)
	end
	setmetatable(script, meta)
	rawset(script, "GetAttributes", function() reads.attributes = reads.attributes + 1; return {} end)
	rawset(script, "GetTags", function() reads.tags = reads.tags + 1; return {} end)
	local result = f.call("instance_get", { path = "Workspace.SensitiveSource", only_properties = true, properties = { "Name", "Source" }, attributes = false, tags = false })
	check("selected names are readable while source stays deferred", result.ok and contains(result.text, "SensitiveSource") and contains(result.text, "source was not read"))
	check("source, attributes and tags were never queried", reads.source == 0 and reads.attributes == 0 and reads.tags == 0)
	f.healthy(); f.close()
end)

suite.case("performance samples validate frame deltas and release their listener", function()
	local f = fixture({ "perf" }); local callback, connections, disconnections = nil, 0, 0
	f.env.run = { Heartbeat = { Connect = function(_, fn)
		callback, connections = fn, connections + 1
		return { Disconnect = function() callback = nil; disconnections = disconnections + 1 end }
	end } }
	f.h.sched.delay(0.01, function() callback(0); callback(-1); callback(0 / 0); callback(math.huge); callback(0.02); callback(0.04) end)
	local result = f.call("performance", { sample = 0.2 })
	check("invalid frame deltas cannot poison the sample", result.ok and result.data.frames == 2 and math.abs(result.data.elapsedSeconds - 0.06) < 1e-9 and result.data.minFrameMs == 20 and result.data.maxFrameMs == 40)
	check("completed sample releases its owned listener", connections == 1 and disconnections == 1 and callback == nil)
	local stopped = false
	f.h.sched.delay(0.05, function() stopped = true end)
	local cancelled = f.run(function() return f.registry.get("performance").run({ sample = 1 }, { aborted = function() return stopped end }) end, 0.2)
	check("cancelled sample also releases the listener", not cancelled.ok and cancelled.data.status == "aborted" and connections == 2 and disconnections == 2 and callback == nil)
	f.healthy(); f.close()
end)

suite.case("signal observation preserves nil positions and always disconnects", function()
	local f = fixture(); local callback, disconnected = nil, 0
	local signal = { Connect = function(_, fn) callback = fn; return { Disconnect = function() disconnected = disconnected + 1; callback = nil end } end }
	f.h.sched.delay(0.01, function() callback("first", nil, "third") end)
	local observed = f.run(function() return f.env.require("tools/helpers").watch(signal, 1, 1, f.ctx, "Synthetic signal") end)
	check("nil event arguments keep their index", observed.ok and contains(observed.text, "2: nil") and contains(observed.text, "3: third") and disconnected == 1)
	local clock = f.env.require("runtime/clock"); local wait = clock.wait
	clock.wait = function() error("synthetic wait failure") end
	local failed = f.env.require("tools/helpers").watch(signal, 1, 1, f.ctx, "Synthetic signal")
	clock.wait = wait
	check("wait failures still release the observer", not failed.ok and disconnected == 2 and callback == nil)
	f.close()
end)

suite.case("prompt cleanup owns begin effects before a host failure", function()
	local f = fixture({ "gui" }); local prompt = f.h.Instance.new("ProximityPrompt", f.h.workspace)
	prompt.Name, prompt.HoldDuration = "OwnedPrompt", 0
	local held, releases = false, 0
	rawset(prompt, "InputHoldBegin", function() held = true; error("failed after beginning") end)
	rawset(prompt, "InputHoldEnd", function() held = false; releases = releases + 1 end)
	local result = f.call("click_detector_fire", { path = "Workspace.OwnedPrompt" })
	check("an uncertain begin still receives matching cleanup", not result.ok and not held and releases == 1)
	f.close()
end)

suite.case("pending prompt begins receive a second end after overlapping cleanup", function()
	for _, mode in ipairs({ "cancel", "unload" }) do
		local f = fixture({ "gui" }); local prompt = f.h.Instance.new("ProximityPrompt", f.h.workspace)
		prompt.Name, prompt.HoldDuration = "PendingPrompt", 0
		local held, releases, cancelled, unrelatedReleased = false, 0, false, false
		f.env.require("runtime/dispose").add(function() unrelatedReleased = true end, "unrelated prompt resource")
		local events = {}
		rawset(prompt, "InputHoldBegin", function()
			f.h.sandbox.task.wait(0.10)
			held = true; events[#events + 1] = "begin"
		end)
		rawset(prompt, "InputHoldEnd", function()
			releases = releases + 1; held = false; events[#events + 1] = "end" .. releases
			if releases == 1 then f.h.sandbox.task.wait(0.20) end
		end)
		local ctx = { aborted = function() return cancelled end }
		f.h.sched.delay(0.01, function()
			if mode == "cancel" then cancelled = true else f.env.require("runtime/dispose").drain() end
		end)
		local result = f.run(function()
			return f.registry.get("click_detector_fire").run({ path = "Workspace.PendingPrompt" }, ctx)
		end, 0.12)
		check(mode .. " cannot report success while its begin completed after an earlier end", not result.ok and held and releases == 1)
		if mode == "unload" then check("yielding prompt cleanup cannot block unrelated unload work", unrelatedReleased) end
		f.h.sched.advance(0.30)
		check(mode .. " dispatches the final end after the late begin", not held and releases == 2 and table.concat(events, ",") == "end1,begin,end2")
		f.healthy(); f.close()
	end
end)

suite.finish()
