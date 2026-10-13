-- v3 scripting efficiency contracts. Synthetic sources, compiler/IO counters and no network.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Release scripting")
local check = suite.check
local function fixture(groups)
	local f = F.new()
	f.ctx = { env = f.env, session = {}, aborted = function() return false end }
	if groups then f.tools(groups) end
	function f.call(name, args) return f.dispatch(name, args, f.ctx, 1) end
	function f.write(path, text) assert(f.env.require("runtime/fsx").write(path, text, { scope = "files" })) end
	function f.read(path) return f.h.files["UAI/files/" .. path] end
	function f.project()
		f.write("P/uai.project.json", f.h.json.encode({ version = 1, entry = "main", modules = { main = "main.lua", settings = "settings.lua", tests = "tests.lua" }, tests = { "tests" } }))
		f.write("P/main.lua", 'return require("settings")')
		f.write("P/settings.lua", 'return { count = 1 }')
		f.write("P/tests.lua", 'return { selected = function(t) t.equal(require("settings").count, 1) end, unrelated = function() error("must be filtered") end }')
	end
	return f
end

suite.case("exact source cache avoids repeated lexing and isolates returned outlines", function()
	local f = fixture(); local source = f.env.require("runtime/project_source")
	local code = '-- ignored\n\t \nlocal item = require("settings")\nfunction item.run() return 1 end\n'
	local first = f.run(function() return assert(source.scan(code)) end)
	local afterFirst = source.cacheInfo()
	first.imports[1].id = "poisoned"; first.symbols[1].name = "poisoned"
	local again = assert(source.scan(code))
	check("cache hit skips another scan", source.cacheInfo().hits == 1 and source.cacheInfo().misses == afterFirst.misses)
	check("nested cached data is private", again.imports[1].id == "settings" and again.symbols[1].name == "item")
	check("whitespace runs preserve positions", again.imports[1].line == 3 and again.symbols[2].line == 4 and again.lines == 5)
	check("cancellation wins over cache reuse", source.scan(code, { aborted = function() return true end }) == nil)
	for i = 1, 140 do assert(source.scan("return " .. i)) end
	local stats = source.cacheInfo()
	check("retention is bounded", stats.entries <= stats.maxEntries and stats.bytes <= stats.maxBytes)
	f.close(); check("unload releases source cache", source.cacheInfo().entries == 0)
end)

suite.case("project analysis reuses compiler work while rechecking dependencies and saved bytes", function()
	local f = fixture({ "coding", "script" }); f.project()
	local project, caps = f.env.require("runtime/script_project"), f.env.require("runtime/caps")
	local compiler, count = caps.fn.loadstring, 0
	caps.fn.loadstring = function(...) count = count + 1; return compiler(...) end
	local function analyze()
		return f.run(function() return project.analyze(assert(project.load("P/uai.project.json", f.ctx)), f.ctx) end)
	end
	local first = analyze(); check("cold compiles all modules", first.ok and count == 3 and first.compiledModules == 3)
	local second = analyze(); check("warm compiles none", second.ok and count == 3 and second.reusedModules == 3)
	f.write("P/settings.lua", 'return { count = 2 }')
	local edited = analyze(); check("only changed source recompiles", edited.ok and count == 4 and edited.compiledModules == 1 and edited.reusedModules == 2)
	f.write("P/uai.project.json", f.h.json.encode({ version = 1, entry = "main", modules = { main = "main.lua" } }))
	local missing = analyze(); check("cached syntax cannot hide graph changes", not missing.ok and missing.diagnostics[1].code == "missing_module" and count == 4)
	caps.fn.loadstring = function(...) count = count + 1; return compiler(...) end
	analyze(); check("compiler identity invalidates cache", count == 5)
	local cancelled = f.run(function() return project.analyze(assert(project.load("P/uai.project.json")), { aborted = function() return true end }) end)
	check("cancelled analysis is incomplete", not cancelled.ok and cancelled.cancelled and not cancelled.complete and count == 5)
	f.healthy(); f.close()
end)

suite.case("syntax checks reuse successful source without retaining execution state", function()
	local f = fixture(); local execution, caps = f.env.require("tools/execution"), f.env.require("runtime/caps")
	local compiler, count = caps.fn.loadstring, 0
	caps.fn.loadstring = function(...) count = count + 1; return compiler(...) end
	check("initial syntax check compiles", execution.check("return 42").ok and count == 1)
	check("unchanged syntax is reused", execution.check("return 42").data.reused and count == 1)
	local run = f.run(function() return execution.run({ code = "return 42" }, f.ctx) end)
	check("running compiles only the fresh managed wrapper", run.ok and count == 2 and run.text:find("42", 1, true))
	caps.fn.loadstring = nil
	check("cached check cannot bypass missing compiler", not execution.check("return 42").ok)
	f.healthy(); f.close()
end)

suite.case("filename discovery pages without reading source", function()
	local f = fixture({ "fs" }); f.write("P/B.lua", "return 2"); f.write("P/A.lua", "return 1"); f.write("P/info.txt", "text")
	local caps = f.env.require("runtime/caps"); local reader, reads = caps.fn.readfile, 0
	caps.fn.readfile = function(...) reads = reads + 1; return reader(...) end
	local first = f.call("file_find", { path = "files/P", glob = "*.LUA", limit = 1 })
	check("discovery is sorted and does no content IO", first.ok and reads == 0 and first.data.paths[1] == "files/P/A.lua" and first.data.nextOffset == 2)
	local last = f.call("file_find", { path = "files/P", glob = "*.LUA", offset = first.data.nextOffset })
	check("cursor continues without duplicates", last.ok and reads == 0 and last.data.paths[1] == "files/P/B.lua" and last.data.complete)
	check("glob directory ambiguity fails", not f.call("file_find", { path = "P", glob = "P/*.lua" }).ok)
	f.healthy(); f.close()
end)

suite.case("skipped binary sources cannot prove search completeness", function()
	local f = fixture({ "fs" }); f.write("P/data.lua", "needle\0binary")
	local result = f.call("file_search", { path = "P", query = "needle" })
	check("omission remains explicit", result.ok and result.data.skipped == 1 and result.data.complete == false)
	f.close()
end)

suite.case("exact edits preserve literal metacharacters and verify host writes", function()
	local f = fixture({ "fs" }); f.write("edit.lua", 'before [%+.*$] after')
	local edit = f.call("file_edit", { path = "edit.lua", old_text = "[%+.*$]", new_text = "%replacement%" })
	check("unique literal edit is exact", edit.ok and f.read("edit.lua") == "before %replacement% after")
	local caps = f.env.require("runtime/caps"); local writer = caps.fn.writefile
	caps.fn.writefile = function(path) return writer(path, "partial") end
	local partial = f.call("file_edit", { path = "edit.lua", old_text = "%replacement%", new_text = "new" })
	check("silent host corruption is not reported as success", not partial.ok and partial.text:find("could not be verified", 1, true) and f.read("edit.lua") == "partial")
	caps.fn.writefile = writer; f.close()
end)

suite.case("project tests execute only requested cases and reject empty selections", function()
	local f = fixture({ "coding", "script" }); f.project()
	local chosen = f.call("script_test", { manifest = "P/uai.project.json", modules = { "tests" }, filter = "selected" })
	check("selected case succeeds without unrelated execution", chosen.ok and chosen.data.passed == 1 and chosen.data.failed == 0 and chosen.data.skipped == 1)
	local empty = f.call("script_test", { manifest = "P/uai.project.json", filter = "absent" })
	check("zero cases is not a passing suite", not empty.ok and empty.text:find("No test cases matched", 1, true))
	check("ordinary source cannot become a selected test module", not f.call("script_test", { manifest = "P/uai.project.json", modules = { "main" } }).ok)
	f.healthy(); f.close()
end)

suite.case("source line pages avoid full line materialization and reject conflicting identities", function()
	local f = fixture({ "coding" }); local store = f.env.require("runtime/code_store")
	local doc = assert(store.create("lines.lua", "one\na\nthree\n", {}))
	local lexer = f.env.require("runtime/code_lexer"); local original = lexer.lines
	lexer.lines = function() error("full line split should not run for a source page") end
	local page = f.call("code_read", { document_id = doc.id, start = 2, count = 1 })
	check("short requested line is read exactly", page.ok and page.text:match("\n(.*)$") == "a\n" and page.data.offset == 5)
	check("document and source snapshot selection is unambiguous", not f.call("code_read", { document_id = doc.id, source_id = "stale" }).ok)
	check("version and proposal selection is unambiguous", not f.call("code_read", { document_id = doc.id, version_id = "v", proposal_id = "p" }).ok)
	lexer.lines = original; f.healthy(); f.close()
end)

suite.case("web pages continue the same snapshot without another request", function()
	local f = fixture(); local calls = 0
	local body = "<TITLE>Guide</TITLE><SCRIPT>hidden_script</SCRIPT><STYLE>hidden_style</STYLE><p>" .. string.rep("hello \226\128\148 world ", 100) .. "</p>"
	f.loaded["net/http"] = { send = function() calls = calls + 1; return { ok = true, status = 200, body = body } end }
	f.tools({ "web" })
	local result = f.call("web_read", { url = "https://example.invalid/guide", limit = 257 })
	local parts, id = { result.text:match("\n(.*)$") }, result.data.pageId
	check("page retains title and source identity", result.ok and id and result.data.title == "Guide")
	while result.data.nextOffset do
		result = f.call("web_read", { page_id = id, offset = result.data.nextOffset, limit = 257 })
		check("continuation remains in the snapshot", result.ok and result.data.pageId == id)
		parts[#parts + 1] = result.text:match("\n(.*)$")
	end
	local text = table.concat(parts)
	check("all text is contiguous with one fetch", calls == 1 and #text == result.data.totalBytes and text:find("hello", 1, true) and not text:find("hidden_", 1, true))
	for i = 1, 4 do f.call("web_read", { url = "https://example.invalid/" .. i }) end
	check("old snapshots evict and never silently refetch", not f.call("web_read", { page_id = id }).ok and calls == 5)
	f.healthy(); f.close()
end)

suite.case("web search accepts attribute order and returns structured links", function()
	local f = fixture(); f.loaded["net/http"] = { send = function()
		return { ok = true, status = 200, body = '<a href="https://example.invalid/doc" class="result__a">Example</a><a class="result__snippet">Useful text</a>' }
	end }; f.tools({ "web" })
	local result = f.call("web_search", { query = "example" })
	check("link and snippet are retained", result.ok and result.data.results[1].url == "https://example.invalid/doc" and result.data.results[1].snippet == "Useful text")
	f.close()
end)

suite.case("template parameters are typed and unknown fields do not dispatch", function()
	local f = fixture({ "templates", "script" })
	check("unknown parameter is rejected", not f.call("template_run", { id = "json_roundtrip", values = { JSON = "{}", JOSN = "{}" } }).ok)
	check("numeric JSON does not masquerade as text", not f.call("template_run", { id = "json_roundtrip", values = { JSON = 12 } }).ok)
	local page = f.call("template_list", { id = "nearest_players", limit = 200 })
	check("template source is resumable", page.ok and page.data.nextOffset)
	f.healthy(); f.close()
end)

suite.case("chunked bytecode encoding preserves padding and cancellation", function()
	local f = fixture(); local bytefall = f.env.require("runtime/bytefall")
	check("known base64 vectors", bytefall.encode("f") == "Zg==" and bytefall.encode("fo") == "Zm8=" and bytefall.encode("foo") == "Zm9v")
	check("multiple chunks retain every byte", bytefall.encode(string.rep("abc", 5000)) == string.rep("YWJj", 5000))
	local checkpoints = 0
	local output = f.run(function() return bytefall.encode(string.rep("abc", 5000), { aborted = function() checkpoints = checkpoints + 1; return checkpoints > 1 end }) end)
	check("encoding stops at a cooperative checkpoint", output == nil and checkpoints == 2)
	f.healthy(); f.close()
end)

suite.finish()
