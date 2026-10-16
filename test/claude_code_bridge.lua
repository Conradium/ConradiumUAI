-- Claude Code (local CLI) through the desktop bridge; no live server, CLI or key.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, json = require("env"), require("json")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local SENTINEL = "https://claude-code.invalid/v1/chat/completions"
local READY = { schema = 1, available = true, state = "ready", models = "/api/claudecode/models",
	aliases = { "sonnet", "opus", "haiku", "fable" }, version = "2.1.301", authMethod = "claude.ai", apiProvider = "firstParty" }
local status = READY
local h = envMock.new()
local jobs, modelRequests, direct = {}, 0, 0
local helloBroken, inboxBroken = false, false
h.http.handler = function(req)
	if req.url:find("claude-code.invalid", 1, true) then direct = direct + 1; return { StatusCode = 503, Body = "" } end
	if helloBroken and req.url:find("/api/hello", 1, true) then return { StatusCode = 500, Body = "" } end
	if inboxBroken and req.url:find("/api/agent/", 1, true) then return { StatusCode = 500, Body = "" } end
	if req.url:find("/api/hello", 1, true) then
		return { StatusCode = 200, Body = json.encode({ protocol = 2, instance = "fixture-instance", capabilities = { claudeCode = status } }) }
	end
	if req.url:find("/api/claudecode/models", 1, true) then
		modelRequests = modelRequests + 1
		check("model list uses bridge auth only", req.headers.Authorization == "Bearer fixture-token")
		return { StatusCode = 200, Body = json.encode({ object = "list", data = { { id = "sonnet" }, { id = "opus" }, { id = "haiku" }, { id = "fable" } } }) }
	end
	if req.url:find("/api/inference", 1, true) and req.method == "POST" then
		local input = json.decode(req.body)
		jobs[#jobs + 1] = input
		return { StatusCode = 202, Body = json.encode({ id = input.id, state = "completed", status = 200, headers = { ["content-type"] = "application/json" },
			body = json.encode({ id = "uai_fixture", object = "chat.completion", model = "sonnet",
				choices = { { index = 0, message = { role = "assistant", content = "PONG" }, finish_reason = "stop" } },
				usage = { prompt_tokens = 115, completion_tokens = 7, total_tokens = 122 } }) }) }
	end
	if req.url:find("/api/agent/inbox", 1, true) then return { StatusCode = 200, Body = '{"commands":[]}' } end
	return { StatusCode = 204, Body = "" }
end
local app = assert(h.boot()); h.settle(0.3)
app.config.set("bridge.token", "fixture-token")
app.config.set("bridge.enabled", true); h.settle(0.5)
local registry, bridge = app.providers, app.bridge
local function complete(record)
	local result, why
	h.sched.spawn(function()
		result, why = app.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "hello" } }, stream = false })
	end)
	h.settle(2)
	return result, why
end

check("authenticated hello advertises the signed-in CLI", bridge.claudeCodeStatus().state == "ready" and bridge.claudeCodeStatus().version == "2.1.301")
check("only display labels are kept", bridge.claudeCodeStatus().authMethod == "claude.ai" and bridge.status().claudeCode.available)
check("aliases and full model ids are served", bridge.claudeCodeHasModel("sonnet") and bridge.claudeCodeHasModel("claude-opus-5-5")
	and not bridge.claudeCodeHasModel("gpt-5") and not bridge.claudeCodeHasModel("--bare"))
local record = registry.blank("claude-code")
record.id = "claude-code-fixture"
check("preset uses the sentinel, Chat Completions and sonnet", record.baseUrl == "https://claude-code.invalid/v1" and (record.api or "openai") == "openai" and record.model == "sonnet")
check("this client never imitates Claude Code", registry.identityFor(record) == "none")
check("the key is provided by the user's own sign-in", registry.claudeCodeKeyOptional(record) and registry.validate(record))
local found, note
h.sched.spawn(function() found, note = app.env.require("provider/models").discover(record, { force = true }) end); h.settle(0.5)
check("discovery lists the bridge aliases: " .. tostring(note), type(found) == "table" and #found == 4 and modelRequests == 1 and tostring(note):find("Claude Code", 1, true))
check("usage bills the user's plan, not this client", app.env.require("agent/pricing").ratesFor("sonnet", record, 1000).input == 0)

local result, why = complete(record)
check("completion runs as one bridge job: " .. tostring(why), result and result.content == "PONG" and #jobs == 1)
local function header(input, name)
	for key, value in pairs(input.headers or {}) do if key:lower() == name then return value end end
end
check("the sentinel URL reaches the bridge unchanged", jobs[1].url == SENTINEL and jobs[1].timeout == nil)
check("no key and no Claude Code identity is sent", header(jobs[1], "authorization") == nil and header(jobs[1], "x-app") == nil
	and not tostring(header(jobs[1], "user-agent") or ""):find("claude-cli", 1, true))
check("the sentinel host was never dialled", direct == 0)

-- A busy executor can time out a status check or drop a poll mid-turn.
helloBroken = true; h.settle(9)
check("a failed status check keeps the last Claude Code answer", bridge.claudeCodeStatus().state == "ready")
helloBroken = false
result, why = complete(record)
check("the next request still reaches the bridge: " .. tostring(why), result and result.content == "PONG" and #jobs == 2)
inboxBroken = true; h.settle(1)
check("the dropped poll takes the client off Web runtime", not app.env.require("net/transport").coworkWeb())
local recovered, recoveredWhy
h.sched.spawn(function()
	recovered, recoveredWhy = app.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "hello" } }, stream = false })
end)
h.settle(0.5); inboxBroken = false; h.settle(14)
check("a request waits for the bridge to come back: " .. tostring(recoveredWhy), recovered and recovered.content == "PONG" and #jobs == 3 and direct == 0)

local relayed
h.sched.spawn(function()
	relayed = app.env.require("net/relay").request({ url = SENTINEL, body = "{}", relayEndpoint = { target = "companion",
		base = "http://127.0.0.1:8790", token = "companion-token", instance = "companion" } }, {}, function() error("the companion must not be called", 0) end)
end); h.settle(0.2)
check("the companion relay never receives Claude Code", relayed and relayed.status == 599 and relayed.terminal and relayed.body:find("Android companion", 1, true))

app.env.uis.TouchEnabled, app.env.uis.MouseEnabled = true, false
check("touch-only clients never waive the key", not registry.claudeCodeKeyOptional(record) and tostring(registry.claudeCodeProblem(record)):find("mobile", 1, true))
app.env.uis.TouchEnabled, app.env.uis.MouseEnabled = false, true

status = { schema = 1, available = true, state = "signed-out", models = "/api/claudecode/models",
	message = "Run `claude` in a terminal and sign in, then restart Cowork. Help and updates: https://discord.gg/9xYyyYuKap" }
h.settle(5)
check("a signed-out CLI is reported", bridge.claudeCodeStatus().state == "signed-out" and not registry.claudeCodeKeyOptional(record)
	and not bridge.claudeCodeHasModel("sonnet"))
local before = #jobs
result, why = complete(record)
check("a signed-out CLI explains sign-in and sends nothing", result == nil and tostring(why):find("sign in, then restart Cowork", 1, true) and #jobs == before and direct == 0)
local listed, listError
h.sched.spawn(function() listed, listError = bridge.claudeCodeModels() end); h.settle(0.2)
check("signed-out discovery makes no request", listed == nil and tostring(listError):find("sign in", 1, true) and modelRequests == 1)

app.bridge.stop()
check("disconnect clears the capability", bridge.claudeCodeStatus().state == "disconnected" and not bridge.claudeCodeHasModel("claude-opus-5-5"))
result, why = complete(record)
check("without the bridge nothing leaves the machine", result == nil and tostring(why):find("Project UAI Bridge", 1, true) and direct == 0 and #jobs == before)
app.destroy(); h.settle(1)
check("callbacks release without errors", #h.errors() == 0)
print("Claude Code bridge: " .. passed .. " assertions")
