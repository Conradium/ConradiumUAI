-- v3 runtime work bounds and tool continuations; no Roblox traffic is sent.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local luau = require("luau")
local passed, failed = 0, 0
local function check(label, value) assert(value, label); passed = passed + 1 end
local function scenario(name, fn)
	local ok, why = pcall(fn)
	if ok then print("  ok   " .. name) else failed = failed + 1; print("  FAIL " .. name .. ": " .. tostring(why)) end
end
local function fixture(overrides)
	local h = envMock.new()
	local env = { hs = h.services.HttpService, services = h.services, players = h.services.Players,
		plr = h.localPlayer, info = { folder = "UAI", version = "test" }, context = {} }
	local loaded = overrides or {}
	function env.require(id)
		if loaded[id] ~= nil then return loaded[id] end
		local file = assert(io.open("src/" .. id .. ".lua", "rb"))
		local source = file:read("*a"); file:close()
		local chunk = assert(luau.load(source, id)); setfenv(chunk, h.sandbox)
		loaded[id] = chunk()(env); return loaded[id]
	end
	return h, env, loaded
end

scenario("a debounce burst owns one wakeup and releases cancelled arguments", function()
	local h, env = fixture()
	local clock = env.require("runtime/clock")
	local calls, received = 0, nil
	local wrapped, cancel = clock.debounce(function(...)
		calls = calls + 1; received = { n = select("#", ...), ... }
	end, 0.1)
	for i = 1, 10000 do wrapped(i, nil, false, nil) end
	check("one timer for ten thousand updates", h.sched.pending() == 1)
	h.sched.advance(0.05); wrapped("latest", nil, false, nil)
	h.sched.advance(0.06)
	check("trailing edge waits after the latest update", calls == 0 and h.sched.pending() == 1)
	h.sched.advance(0.06)
	check("latest packed values survive", calls == 1 and received.n == 4 and received[1] == "latest" and received[3] == false)
	local weak = setmetatable({}, { __mode = "v" })
	do local payload = {}; weak[1] = payload; wrapped(payload) end
	cancel(); collectgarbage("collect")
	check("cancel releases payload before the timer fires", weak[1] == nil)
	wrapped("reused"); check("cancel and reuse share a pending wakeup", h.sched.pending() == 1)
	h.sched.advance(0.2)
	check("reuse fires exactly once", calls == 2 and received[1] == "reused" and h.sched.pending() == 0)
	check("scheduler remained healthy", #h.sched.errors == 0)
end)

scenario("debounce handlers can yield and schedule their next call", function()
	local h, env = fixture()
	local clock = env.require("runtime/clock")
	local calls, wrapped = {}, nil
	wrapped = clock.debounce(function(value)
		calls[#calls + 1] = value
		if value == 1 then wrapped(2); h.sandbox.task.wait(0.2) end
	end, 0.05)
	wrapped(1); h.sched.advance(0.4)
	check("a yielded handler does not swallow the next dispatch", #calls == 2 and calls[1] == 1 and calls[2] == 2)
	check("no pending workers or failures remain", h.sched.pending() == 0 and #h.sched.errors == 0)
end)

scenario("UTF-8 fast paths retain exact validation and repair behavior", function()
	local _, env = fixture()
	local util = env.require("runtime/util")
	local replacement = "\239\191\189"
	local valid = { "", "a\0b", "\194\128", "\223\191", "\224\160\128", "\237\159\191", "\238\128\128", "\240\144\128\128", "\244\143\191\191" }
	for _, value in ipairs(valid) do
		local fixed, changed = util.sanitise("prefix" .. value .. "suffix")
		check("valid boundaries remain byte exact", util.validUtf8(value) and fixed == "prefix" .. value .. "suffix" and not changed)
	end
	for _, bad in ipairs({ "\128", "\192\128", "\224\159\191", "\237\160\128", "\240\143\191\191", "\244\144\128\128", "\255", "\194" }) do
		local ok, at = util.validUtf8("abc" .. bad)
		local fixed, changed = util.sanitise("abc" .. bad .. "xyz")
		check("malformed ranges report the original byte", not ok and at == 4)
		check("malformed bytes are individually repaired", changed and fixed == "abc" .. replacement:rep(#bad) .. "xyz" and util.validUtf8(fixed))
	end
	local byte, byteReads = string.byte, 0
	string.byte = function(...) byteReads = byteReads + 1; return byte(...) end
	local ok, why = pcall(function()
		local source = ("local sum = 42\n"):rep(10000)
		check("large ASCII source remains valid", util.validUtf8(source))
		local fixed = util.sanitise("\255" .. source .. "\240\159\153\130")
		check("repair retains a long suffix and multibyte text", fixed == replacement .. source .. "\240\159\153\130")
		check("ASCII runs do not require a Lua byte read per character", byteReads < 20)
	end)
	string.byte = byte; assert(ok, why)
end)

scenario("prompt skill inventory caches bounded text while explicit reads stay fresh", function()
	local h, env = fixture()
	local skills, fs, config = env.require("runtime/skills"), env.require("runtime/fsx"), env.require("runtime/config")
	assert(skills.save("One", "first description", "first body"))
	local read, list, reads, lists = fs.read, fs.list, 0, 0
	fs.read = function(...) reads = reads + 1; return read(...) end
	fs.list = function(...) lists = lists + 1; return list(...) end
	local first = skills.indexBlock()
	for _ = 1, 30 do check("unchanged inventory is stable", skills.indexBlock() == first) end
	check("thirty prompt reads share one inventory read", reads == 1 and lists == 1)
	assert(fs.write("One.md", "---\nname: One\ndescription: external edit\n---\nnew body", { scope = "skills" }))
	check("external edit does not trigger per-prompt I/O", skills.indexBlock() == first and reads == 1)
	local body = skills.readBody("One.md")
	check("explicit body read sees external edits immediately", body == "new body")
	check("explicit inventory read invalidates the prompt cache", skills.indexBlock():find("external edit", 1, true))
	config.set("skills.disabled", { ["One.md"] = true }, { transient = true })
	check("direct policy changes invalidate enabled inventory", skills.indexBlock() == nil)
	config.set("skills.disabled", {}, { transient = true })
	assert(fs.write("Two.md", "second body", { scope = "skills" }))
	skills.indexBlock()
	assert(fs.write("Three.md", "third body", { scope = "skills" }))
	h.sched.advance(5.1)
	check("external additions appear after TTL", skills.indexBlock():find("Three.md", 1, true))
	assert(skills.save("Four", "new", "body"))
	check("managed writes invalidate immediately", skills.indexBlock():find("Four.md", 1, true))
	assert(skills.remove("Four.md"))
	check("managed deletion invalidates immediately", not skills.indexBlock():find("Four.md", 1, true))
end)

scenario("capture retention avoids FIFO shifts and preserves pins and cursors", function()
	local _, env = fixture()
	local records = env.require("runtime/remote_store")
	local values, refs = env.require("runtime/values"), env.require("runtime/instance_refs")
	local remoteId = refs.id(env.services.Workspace)
	local function add(outcome, value)
		return records.begin({ remoteId = remoteId, name = "Quiet", className = "RemoteEvent", method = "FireServer", direction = "outgoing", sessionId = "test", outcome = outcome }, values.pack(value))
	end
	local pinned = add("pending", "initial"); assert(records.pin(pinned.id))
	local remove, shifts = table.remove, 0
	table.remove = function(list, at) if at == 1 then shifts = shifts + 1 end; return remove(list, at) end
	local ok, why = pcall(function() for i = 1, 2400 do add("forwarded", i) end end)
	table.remove = remove; assert(ok, why)
	local state = records.state()
	check("retention never shifts one row per incoming call", shifts == 0)
	check("record and byte ceilings remain enforced", state.retained == 1000 and state.bytes <= records.limits.bytes and state.oldest == 1402 and state.newest == 2401)
	local page = assert(records.page({ after_sequence = 1, limit = 3 }))
	check("eviction gaps remain explicit", page.gap.first == 2 and page.gap.last == 1401)
	check("page ordering survives compaction", page.items[1].sequence == 1402 and page.items[3].sequence == 1404 and page.nextCursor)
	local nextPage = assert(records.page({ cursor = page.nextCursor, limit = 3 }))
	check("cursors continue contiguously", nextPage.items[1].sequence == 1405)
	local recent = records.latest({ limit = 3 })
	check("latest rows preserve chronological order", recent.items[1].sequence == 2399 and recent.items[3].sequence == 2401)
	records.finish(pinned, "returned", values.pack("late"))
	check("an evicted pinned call can finish", records.get(pinned.id).outcome == "returned" and records.state().pins == 1)
	local frozen = assert(records.freeze())
	check("export freezes only retained rows in order", #frozen.items == 1000 and frozen.items[1].sequence == 1402 and frozen.throughSequence == 2401)
	records.unpin(pinned.id); check("unpin releases the evicted call", records.get(pinned.id) == nil)
	records.clear(); check("clear resets the private queue", records.state().retained == 0 and records.state().bytes == 0)
	local new = add("pending", 1); records.stopPending()
	check("stop covers records after clear", records.get(new.id).outcome == "completion_unobserved")
end)

scenario("capture detail reads copy only the requested section", function()
	local _, env = fixture()
	local records, values = env.require("runtime/remote_store"), env.require("runtime/values")
	local util = env.require("runtime/util")
	local token = records.begin({ name = "Payload", method = "FireServer", direction = "outgoing", outcome = "forwarded", caller = { status = "known" } }, values.pack(("x"):rep(12000), { a = 1, b = 2 }))
	local copy, copies = util.deepCopy, 0
	util.deepCopy = function(...) copies = copies + 1; return copy(...) end
	local bytes = assert(records.readBytes({ record_id = token.id, section = "arguments", index = 1, byte_limit = 500 }))
	check("byte slices avoid copying the argument graph", #bytes.value == 500 and copies == 0 and bytes.nextByteOffset == 501)
	local summary = records.read(token.id, "summary")
	check("summary copies only bounded caller metadata", copies < 5)
	summary.caller.status = "changed"
	local arguments = records.read(token.id, "arguments")
	arguments.reasons[1] = "changed"
	util.deepCopy = copy
	check("public receipt edits cannot mutate storage", records.get(token.id).caller.status == "known" and records.get(token.id).arguments.reasons[1] == nil)
end)

scenario("official Gravity source pagination reuses bounded snapshots", function()
	local requests = 0
	local h, env = fixture({ ["runtime/gravity"] = { current = function() return nil end }, ["tools/execution"] = {},
		["net/http"] = { send = function() requests = requests + 1; return { status = 200, body = "source " .. requests } end } })
	local plugin = env.require("tools/gravity_plugins")
	local first = assert(plugin.read({ plugin = "Orbit" }))
	check("repeat official reads share one snapshot", plugin.read({ plugin = "Orbit" }) == first and requests == 1)
	check("refresh obtains new source", plugin.read({ plugin = "Orbit", refresh = true }) == "source 2" and requests == 2)
	assert(plugin.read({ plugin = "Spiral" })); assert(plugin.read({ plugin = "Wave" }))
	assert(plugin.read({ plugin = "Orbit" }))
	check("only two official sources remain cached", requests == 5)
	h.sched.advance(301); assert(plugin.read({ plugin = "Orbit" }))
	check("expired source is fetched again", requests == 6)
end)

scenario("IY discovery paginates and plugin authoring accepts saved source", function()
	local commands, saved = {}, nil
	for i = 1, 35 do commands[i] = { NAME = "command" .. i, ALIAS = {} } end
	local h, env = fixture({ ["runtime/iy"] = { ensure = function() return true end, cmdsTable = function() return commands end,
		descriptions = function() return {} end }, ["runtime/iy_store"] = {}, ["runtime/iy_control"] = {},
		["runtime/iy_plugins"] = { write = function(args) saved = args.source; return { plugin = args.plugin, validation = "syntax checked" } end } })
	local tools = {}; for _, tool in ipairs(env.require("tools/iy")) do tools[tool.name] = tool end
	env.require("runtime/config").set("agent.resultCap", 1000, { transient = true })
	local offset, count = 1, 0
	repeat
		local result = tools.iy_cmds.run({ offset = offset, limit = 20 })
		check("command pages fit the budget", result.ok ~= false and #result.text < 1000)
		count = count + result.data.count; offset = result.data.nextOffset
	until not offset
	check("all commands remain discoverable", count == #commands)
	local fs = env.require("runtime/fsx")
	assert(fs.write("source.lua", "return Plugin", { scope = "files" }))
	local args = { plugin = "MyPlugin.iy", path = "files/source.lua", load = false }
	local result = tools.iy_plugin_write.run(args, { aborted = function() return false end })
	check("saved source is passed exactly without modifying the request", result.ok ~= false and saved == "return Plugin" and args.source == nil)
	check("conflicting source forms are rejected", tools.iy_plugin_write.run({ plugin = "X", path = "source.lua", source = "other" }).ok == false)
	check("the authoring schema exposes a path without requiring inline source", tools.iy_plugin_write.parameters.properties.path ~= nil and #tools.iy_plugin_write.parameters.required == 1)
	check("no scheduler failures", #h.sched.errors == 0)
end)

scenario("chat history supports stable backward cursors within the result budget", function()
	local history = {}
	for i = 1, 40 do history[i] = { sequence = i, sender = "Player", channel = "General", text = "Message " .. i } end
	local _, env = fixture({ ["runtime/gamechat"] = { history = history, channel = function(name) return name end }, ["tools/chatloops"] = {} })
	local historyTool
	for _, tool in ipairs(env.require("tools/chat")) do if tool.name == "chat_history" then historyTool = tool end end
	local page = historyTool.run({ limit = 7 })
	check("latest messages remain chronological", page.text:find("Message 34", 1, true) < page.text:find("Message 40", 1, true) and page.data.nextBeforeSequence == 34)
	history[#history + 1] = { sequence = 41, sender = "Player", channel = "General", text = "new arrival" }
	local older = historyTool.run({ before_sequence = page.data.nextBeforeSequence, limit = 7 })
	check("new arrivals cannot shift a backward continuation", older.text:find("Message 27", 1, true) and older.text:find("Message 33", 1, true) and not older.text:find("Message 34", 1, true) and older.data.nextBeforeSequence == 27)
	env.require("runtime/config").set("agent.resultCap", 448, { transient = true })
	local small = historyTool.run({ limit = 50 })
	check("a small result budget produces a continuation instead of clipping", small.ok ~= false and #small.text <= 128 and small.data.nextBeforeSequence)
end)

scenario("IY store rejects unsafe filenames and verifies downloaded bytes", function()
	local registered, requests, destinationChanged = 0, 0, false
	local h, env = fixture({ ["runtime/iy"] = { ensure = function() return true end, getMode = function() return "hidden" end,
		value = function() return function() registered = registered + 1 end end } })
	local caps = env.require("runtime/caps")
	local store = env.require("runtime/iy_store")
	store.catalog = { plugins = { { id = "one", name = "Example", author = "test", files = { { filename = "Example.iy", url = "Example.iy", is_plugin = true } } } } }
	store.catalogAt = env.require("runtime/clock").ms()
	local http = env.require("net/http")
	http.send = function()
		requests = requests + 1
		if destinationChanged then caps.fn.writefile("Example.iy", "external edit") end
		return { status = 200, body = "return {}" }
	end
	store.catalog.plugins[1].files[1].filename = "../Example.iy"
	check("store paths cannot escape the plugin filename", not store.install("Example") and requests == 0)
	check("uninstall rejects paths before calling the remover", not store.uninstall("../Example.iy") and registered == 0)
	store.catalog.plugins[1].files[1].filename = "Example.iy"
	destinationChanged = true
	check("a destination created during download is preserved", not store.install("Example") and caps.fn.readfile("Example.iy") == "external edit" and registered == 0)
	caps.fn.delfile("Example.iy"); destinationChanged = false
	check("verified source may be registered", store.install("Example") and caps.fn.readfile("Example.iy") == "return {}" and registered == 1)
	check("no scheduler failures", #h.sched.errors == 0)
end)

print(string.format("release_runtime: %d checks passed; %d scenarios failed", passed, failed))
if failed > 0 then os.exit(1) end
