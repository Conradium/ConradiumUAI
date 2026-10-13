-- Provider request ownership through real controls and synthetic adapters.
-- This fixture does not perform inference or verify native Roblox rendering.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("v3 provider UI ownership")
local check, case = suite.check, suite.case
local function click(f, name)
	local node = assert(f.h.byName(name), "missing control: " .. name)
	f.h.click(node); return node
end
local function field(f, name, value)
	local row = assert(f.h.byName(name), "missing field: " .. name)
	f.h.type(assert(row:FindFirstChildOfClass("TextBox")), value)
end
local function fixture(editor)
	local f = F.ui(1000, 850)
	f.toasts = {}
	f.env.require("ui/overlay").toast = function(text) f.toasts[#f.toasts + 1] = text end
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl, record.apiKey = "Fixture provider", "https://ui.fixture/v1", "fixture-key"
	record.model, record.models = "one", { "one", "two" }
	f.record = record
	if editor then f.env.require("ui/panels/providers").editor(record) end
	f.h.settle(0.2)
	return f
end

case("closing a provider test cancels its request and ignores late completion", function()
	local f = fixture(true); local request
	f.env.require("provider/chat").complete = function(_, options)
		request = options; f.h.sched.wait(1); return { ms = 10 }
	end
	click(f, "TestConnection")
	check("test receives a live cancellation callback", request and type(request.aborted) == "function" and not request.aborted())
	f.h.press("Escape")
	check("closing the editor revokes the request", request.aborted())
	f.h.sched.advance(1.2)
	check("late completion cannot display success on a closed editor", #f.toasts == 0)
	f.healthy(); f.close()
end)

case("connection edits supersede old tests without unlocking the current one", function()
	local f = fixture(true); local requests = {}
	f.env.require("provider/chat").complete = function(candidate, options)
		local index = #requests + 1; requests[index] = { options = options, url = candidate.baseUrl }
		f.h.sched.wait(index == 1 and 1 or 2)
		if index == 1 then return nil, "old endpoint failed" end
		return { ms = 20 }
	end
	click(f, "TestConnection")
	field(f, "BaseUrl", "https://new.ui.fixture/v1")
	check("editing cancels the old test and permits testing the new draft", requests[1].options.aborted() and f.h.byName("TestConnection").Active)
	click(f, "TestConnection")
	f.h.sched.advance(1.1)
	check("old completion cannot unlock the new pending request", #requests == 2 and not requests[2].options.aborted() and not f.h.byName("TestConnection").Active)
	check("old failure is not painted against the new connection", not f.h.textOf():find("old endpoint failed", 1, true))
	f.h.sched.advance(1.2)
	check("current success is reported exactly once", #f.toasts == 1 and f.toasts[1]:find("Reached Fixture provider", 1, true)
		and f.h.byName("TestConnection").Active and requests[2].url == "https://new.ui.fixture/v1")
	f.healthy(); f.close()
end)

case("changing the selected model revokes a pending connection test", function()
	local f = fixture(true); local request, release, returned
	f.env.require("provider/chat").complete = function(_, options)
		request = options
		-- Each mock click settles 0.6 s; hold completion until model selection.
		while not release do f.h.sched.wait(0.05) end
		returned = true
		return { ms = 10 }
	end
	click(f, "TestConnection"); click(f, "ActiveModel"); click(f, "Option_model:two")
	check("changing model invalidates the old inference", not returned and request.aborted() and f.h.byName("TestConnection").Active)
	release = true; f.h.sched.advance(0.2)
	check("late model result does not produce a success toast", returned and #f.toasts == 0)
	f.healthy(); f.close()
end)

case("late detail discovery cannot switch back to a previously selected provider", function()
	local f = fixture(false); local registry = f.env.require("provider/registry")
	assert(registry.save(f.record))
	local other = registry.blank("custom")
	other.label, other.baseUrl, other.apiKey, other.model = "Second provider", "https://second.ui.fixture/v1", "fixture-key", "two"
	assert(registry.save(other))
	local request
	f.env.require("provider/models").discover = function(_, options)
		request = options; f.h.sched.wait(1); return { "late-model" }, "Old discovery completed"
	end
	local panel = f.env.require("ui/panels/providers").new(f.host)
	panel.select(f.record.id)
	click(f, "ManageModels"); click(f, "Option_fetch")
	panel.select(other.id)
	check("switching provider revokes the old discovery", request and request.aborted())
	f.h.sched.advance(1.2)
	check("late discovery preserves the current selection", f.h.byName("ProviderTitle").Text == "Second provider")
	check("superseded discovery does not report its stale result", #f.toasts == 1 and not f.toasts[1]:find("Old discovery completed", 1, true))
	panel.root:Destroy(); f.healthy(); f.close()
end)

suite.finish()
