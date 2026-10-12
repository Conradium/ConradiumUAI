-- Focused audit regressions using the existing offline fixture. These simulate
-- host failures; they do not establish Roblox input or native rendering behavior.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("tools/runtime audit")
local check, case = suite.check, suite.case
local function contains(text, needle) return tostring(text):find(needle, 1, true) ~= nil end

case("typed legacy arguments preserve exponents and explicit string escapes", function()
	local f = F.new(); local values = f.env.require("runtime/legacy_values")
	local vector = assert(values.coerce("1e+10, -.25, +2.5e-3", f.h.dt.Vector3.new()))
	check("whole exponents are coordinates", vector.X == 1e10 and vector.Y == -0.25 and vector.Z == 0.0025)
	check("overflow is rejected", values.coerce("1e999, 2, 3", vector) == nil)
	check("extra coordinates are rejected", values.coerce("1, 2, 3, 4", vector) == nil)
	check("malformed exponent is rejected", values.coerce("1e+, 2, 3", vector) == nil)
	local range = assert(values.coerce("1.25..2.5", f.h.dt.NumberRange.new(0, 1)))
	check("range separator survives decimals", range.Min == 1.25 and range.Max == 2.5)
	local transport = f.env.require("tools/remote_transport")
	local args = assert(transport.arguments({ args = { "vec3:1e2, 2, 3", "vector3:4, 5, 6", "vec2:.5, -.25",
		"color3:255, 0, 0", "cframe:7, 8, 9", "string:instance:hello", "string:number:5", "unknown:keep" } }))
	check("numeric type names resolve", args[1].X == 100 and args[2].Z == 6 and args[3].X == 0.5)
	check("color and transform values resolve", args[4].R == 1 and args[5].Position.Y == 8)
	check("literal prefixes retain their text", args[6] == "instance:hello" and args[7] == "number:5" and args[8] == "unknown:keep")
	check("invalid scalar argument is rejected", transport.arguments({ args = { "number:1e999" } }) == nil)
	f.healthy(); f.close()
end)

case("input providers must actually accept each supported operation", function()
	local f = F.new(); local h = f.h
	h.services.VirtualInputManager, h.services.VirtualUser = {}, {}
	f.tools({ "input" })
	check("missing key APIs fail", not f.dispatch("key_press", { key = "E" }).ok)
	h.services.VirtualInputManager.SendKeyEvent = function() return false end
	h.sandbox.keypress, h.sandbox.keyrelease = function() return false end, function() return false end
	h.services.VirtualUser.CaptureController = function() end
	h.services.VirtualUser.SetKeyDown = function() error("denied") end
	h.services.VirtualUser.SetKeyUp = function() return false end
	check("refused providers fail", not f.dispatch("key_press", { key = "E" }).ok)
	local down, up = 0, 0
	h.services.VirtualUser.SetKeyDown = function() down = down + 1 end
	h.services.VirtualUser.SetKeyUp = function() up = up + 1 end
	check("working final fallback succeeds", f.dispatch("key_press", { key = "E", duration = 0.1 }).ok and down == 1 and up == 1)
	h.services.VirtualInputManager.SendMouseButtonEvent = function() return false end
	h.sandbox.mouse1click = function() error("denied") end
	check("failed executor mouse click fails", not f.dispatch("mouse_click", { button = "left" }).ok)
	check("missing movement API cannot report success", not f.dispatch("mouse_click", { action = "move" }).ok)
	local right = 0
	h.services.VirtualUser.Button2Down = function() right = right + 1 end
	check("right down uses the right native button", f.dispatch("mouse_click", { action = "down", button = "right" }).ok and right == 1)
	check("unsupported middle fallback fails", not f.dispatch("mouse_click", { action = "down", button = "middle" }).ok)
	h.services.VirtualInputManager.SendMouseMoveEvent = function() end
	check("void native success remains supported", f.dispatch("mouse_click", { action = "move" }).ok)
	f.healthy(); f.close()
end)

case("tool names are unique and mutation permissions remain explicit", function()
	local f = F.new(); local seen = {}
	for _, group in ipairs({ "agentself", "perf", "chatloops" }) do
		for _, tool in ipairs(f.env.require("tools/" .. group)) do
			check("unique tool " .. tool.name, seen[tool.name] == nil); seen[tool.name] = tool
		end
	end
	check("both status tools are available", seen.agent_status and seen.client_status)
	for _, name in ipairs({ "todo_write", "conversation_rename", "memory_write", "memory_forget", "chat_loop_stop" }) do
		check(name .. " requires write permission", seen[name].risk == "write")
	end
	f.healthy(); f.close()
end)

case("logs redact credentials from source, message and detail", function()
	local f = F.new(); local log = f.env.require("runtime/log")
	local secrets = {
		{ '"apiKey":"private-provider-value-tail"', "private-provider-value" },
		{ "https://service.test/?key=private-query-value-tail", "private-query-value" },
		{ "X-API-Key: private-header-value-tail", "private-header-value" },
		{ "Bearer private-bearer-value-tail", "private-bearer-value" },
		{ "ghp_privategithubvaluetail", "privategithubvalue" },
		{ "xoxb-private-slack-value-tail", "private-slack-value" },
		{ "AKIAPRIVATEAWSVALUETAIL", "PRIVATEAWSVALUE" },
		{ "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.privateSignatureTail", "eyJhbGciOiJIUzI1NiJ9" },
	}
	for _, item in ipairs(secrets) do
		local entry = log.info(item[1], item[1], item[1])
		check("credential redacted everywhere", not contains(entry.source, item[2]) and not contains(entry.message, item[2]) and not contains(entry.detail, item[2]))
	end
	check("ordinary messages remain readable", log.redact("request failed: status=429") == "request failed: status=429")
	log.mirror = true; f.h.sandbox.print = function() error("console denied") end
	check("console failure cannot break logging", log.info("audit", "still retained").message == "still retained")
	log.mirror = false; f.healthy(); f.close()
end)

case("world fallbacks scan children and disclose interrupted results", function()
	local f = F.new(); local h = f.h
	f.tools({ "world", "perf" })
	local part = h.Instance.new("Part", h.workspace); part.Name, part.Position = "AuditNearPart", h.dt.Vector3.new(1, 0, 0)
	h.workspace.GetPartBoundsInRadius = function() error("unsupported") end
	h.workspace.GetDescendants = function() error("whole-tree allocation must not be used") end
	local result = f.dispatch("parts_near", { position = "0, 0, 0", radius = 10 })
	check("incremental fallback finds nearby part", result.ok and contains(result.text, "AuditNearPart"))
	check("unreadable parts do not prevent later matches and remain disclosed", contains(result.text, "Scan incomplete: unreadable parts"))
	check("class counts also avoid whole-tree allocation", f.dispatch("class_counts", { root = "Workspace" }).ok)
	local tools = f.env.require("tools/world"); local near
	for _, tool in ipairs(tools) do if tool.name == "parts_near" then near = tool end end
	local cancelled = near.run({ position = "0, 0, 0" }, { aborted = function() return true end })
	check("incomplete empty scan never proves absence", contains(cancelled, "Scan incomplete") and contains(cancelled, "aborted"))
	f.healthy(); f.close()
end)

case("Gravity selection failure restores prior membership or reports incomplete recovery", function()
	local f = F.new(); local h = f.h
	local x6 = { a = {}, pc_selected = {}, pc_api_version = 1 }
	local context = { session_id = "audit", x1 = {}, x2 = {}, x4 = {}, x6 = x6, get_shape = function() end }
	f.env.context.gravity = context
	local parts = {}
	for index = 1, 3 do local part = h.Instance.new("Part", h.workspace); parts[index] = part; x6.a[part] = { id = index } end
	x6.pc_selected[parts[1]] = true
	x6.pc_clear = function() for part in pairs(x6.pc_selected) do x6.pc_selected[part] = nil end end
	x6.pc_select = function(part) if part == parts[3] then return false end; x6.pc_selected[part] = true end
	for _, name in ipairs({ "pc_assign", "pc_deselect", "pc_release_all", "pc_set_ride", "pc_set_phys" }) do x6[name] = function() end end
	local control = f.env.require("tools/gravity_parts")
	local result, why = control.control({ action = "select", ids = { "audit:2", "audit:3" } })
	check("failed selection reports restored state", not result and contains(why, "previous selection was restored"))
	check("prior membership survives failure", x6.pc_selected[parts[1]] and not x6.pc_selected[parts[2]] and not x6.pc_selected[parts[3]])
	x6.pc_select = function() return false end
	result, why = control.control({ action = "select", ids = { "audit:2" } })
	check("failed rollback is disclosed", not result and contains(why, "restoration was incomplete"))
	f.healthy(); f.close()
end)

case("stale proposals and stale clone targets fail before mutation", function()
	local f = F.new(); local store = f.env.require("runtime/code_store"); store.init()
	local doc = store.active(); local revision = doc.revision
	assert(store.update(doc.id, "return 5"))
	local proposal, why = store.propose(doc.id, revision, "return 6")
	check("already stale proposal is rejected", not proposal and contains(why, "stale_revision") and #store.proposals(doc.id) == 0)
	local part = f.h.Instance.new("Part", f.h.workspace)
	local refs = f.env.require("runtime/instance_refs"); local id = refs.id(part)
	local native = f.env.require("tools/instance_native"); local resolve = refs.resolve
	refs.resolve = function() return nil, "stale_handle: fixture invalidation" end
	local prepared, err = native.prepare.instance_clone({ path = "Workspace.Part" })
	check("stale clone binding is reported", not prepared and contains(err, "stale_handle"))
	refs.resolve = resolve
	check("ambiguous create parent is rejected", native.prepare.instance_create({ parent = "Workspace", parent_id = id }) == nil)
	f.healthy(); f.close()
end)

suite.finish()
