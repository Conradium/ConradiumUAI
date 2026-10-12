-- The provider sees the same bounded evidence as the tool receipt, including IDs.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Structured tool results")
local case, check = suite.case, suite.check
local MARK = "\n\nResult data:\n"
local function has(text, value) return tostring(text):find(value, 1, true) ~= nil end
local function decode(f, text)
	local at = assert(text:find(MARK, 1, true), "model result has no structured evidence")
	return assert(f.h.json.decode(text:sub(at + #MARK))), text:sub(1, at - 1)
end
local function register(f, name, group, run)
	f.registry.register({ name = name, group = group, risk = "read", description = "Structured evidence fixture", run = run })
end

case("main and child loops discover script IDs and continue the same source snapshot", function()
	for _, headless in ipairs({ false, true }) do
		local f = F.new(); f.tools({ "script" })
		local config = f.env.require("runtime/config"); config.set("agent.resultCap", 6000)
		local source = string.rep("-- fixture source line\n", 25) .. "return 42\n"
		for index = 1, 6 do local object = f.h.Instance.new("LocalScript", f.h.workspace); object.Name, object.Source = "Evidence" .. index, source end
		local providers = f.env.require("provider/registry")
		local record = providers.blank("custom")
		record.model, record.models, record.baseUrl, record.apiKey = "structured-fixture", { "structured-fixture" }, "https://structured.test/v1", "fixture-key"
		assert(providers.save(record))
		local requests, firstSource, sourceId, nextOffset = 0
		local function call(name, args)
			return { model = record.model, content = "", reasoning = "", finish = "tool_calls",
				toolCalls = { { id = "evidence_" .. requests, ["function"] = { name = name, arguments = f.h.json.encode(args) } } } }
		end
		f.loaded["provider/chat"] = { contextOverflow = function() return false end, complete = function(_, request)
			requests = requests + 1
			if requests == 1 then return call("script_list", { root = "Workspace", limit = 5 }) end
			local message = request.messages[#request.messages]
			check("next request contains a model-visible tool receipt", message.role == "tool" and #message.content <= 6000)
			local data, text = decode(f, message.content)
			if requests == 2 then
				check("script listing exposes exact identities and cursor", #data.items == 5 and data.items[1].instanceId and data.nextCursor)
				return call("script_source", { instance_id = data.items[1].instanceId, limit = 200 })
			elseif requests == 3 then
				sourceId, nextOffset = data.sourceId, data.nextOffset
				firstSource = assert(text:match("^[^\n]*\n(.*)$"))
				check("source identity and page cursor reach the model", sourceId and nextOffset == #firstSource + 1)
				return call("script_source", { source_id = sourceId, offset = nextOffset, limit = 3000 })
			end
			local rest = assert(text:match("^[^\n]*\n(.*)$"))
			check("source pages concatenate without missing bytes", data.sourceId == sourceId and data.eof and firstSource .. rest == source)
			return { model = record.model, content = "Inspected exact source", reasoning = "", toolCalls = {}, finish = "stop" }
		end }
		local session = assert(f.env.require("agent/session").create({ ephemeral = true, maxTurns = 6 }))
		session.headless, session.systemPrompt = headless, "Inspect the named script using returned identities."
		local result = f.run(function() return f.env.require("agent/loop").run(session, "Inspect script source") end, 1)
		check("shared loop completes the requested inspection", requests == 4 and result == "Inspected exact source")
		f.healthy(); f.close()
	end
end)

case("retained native results and UTF-8 reader pages fit small result budgets", function()
	local f = F.new(); f.tools({ "coding" })
	local config, N = f.env.require("runtime/config"), f.env.require("tools/native_helpers")
	config.set("agent.resultCap", 256)
	local original = string.rep("\231\149\140\n", 90) .. "final source bytes"
	register(f, "fixture_large", "coding", function() return N.result({ blob = string.rep("detail", 1200), truth = false }, original) end)
	local result = f.dispatch("fixture_large")
	local pointer = decode(f, result.modelText)
	check("large data exposes an actionable exact reader reference", #result.modelText <= 256 and pointer.readTool == "workspace_result_read" and pointer.result_id)
	local pieces, offset = {}, 1
	repeat
		local page = f.dispatch(pointer.readTool, { result_id = pointer.result_id, section = "text", offset = offset })
		check("reader receipts stay within the model budget", page.ok and #page.modelText <= 256)
		local data = decode(f, page.modelText)
		check("reader pages do not create a recursive retained result", data.readTool == nil and type(data.value) == "string")
		check("reader byte offsets advance exactly", data.offset == offset and (data.nextOffset == nil or data.nextOffset == offset + #data.value))
		pieces[#pieces + 1], offset = data.value, data.nextOffset
	until offset == nil
	check("retained original text is reconstructed exactly", table.concat(pieces) == original)
	local truth = f.dispatch(pointer.readTool, { result_id = pointer.result_id, path = { "truth" } })
	check("false survives model serialization", decode(f, truth.modelText).value == false)
	f.healthy(); f.close()
end)

case("oversized combined source metadata retains the whole page before its cursor", function()
	local f = F.new(); f.tools({ "script" })
	f.env.require("runtime/config").set("agent.resultCap", 400)
	local source = string.rep("local text = '\231\149\140'\n", 70)
	local object = f.h.Instance.new("LocalScript", f.h.workspace); object.Name, object.Source = "LongSource", source
	local id = f.env.require("runtime/instance_refs").id(object)
	local result = f.dispatch("script_source", { instance_id = id, limit = 3000 })
	local pointer = decode(f, result.modelText)
	check("source page overflow uses its originating reader", pointer.readTool == "script_result_read" and #result.modelText <= 400)
	local pieces, offset = {}, 1
	repeat
		local page = f.dispatch(pointer.readTool, { result_id = pointer.result_id, section = "text", offset = offset })
		local data = decode(f, page.modelText); pieces[#pieces + 1], offset = data.value, data.nextOffset
	until offset == nil
	check("source page stays byte-for-byte identical to the UI receipt", table.concat(pieces) == result.text)
	local body = assert(result.text:match("^[^\n]*\n(.*)$"))
	check("the original source cursor still follows its complete page", result.data.nextOffset == #body + 1 and body == source:sub(1, #body))
	f.healthy(); f.close()
end)

case("unavailable readers never replace readable text or appear as instructions", function()
	local f = F.new(); f.tools({ "coding" })
	local config, N = f.env.require("runtime/config"), f.env.require("tools/native_helpers")
	config.set("agent.resultCap", 600)
	local text = "Exact file page\n" .. string.rep("source bytes\n", 25)
	register(f, "fixture_file", "fs", function() return { text = text, data = { nextOffset = 999, extra = string.rep("x", 8000) } } end)
	local page = f.dispatch("fixture_file")
	check("complete legacy source remains readable", page.modelText:sub(1, #text) == text and #page.modelText <= 600)
	check("available space preserves its cursor", decode(f, page.modelText).nextOffset == 999)
	register(f, "fixture_scoped", "coding", function() return N.result({ hidden = string.rep("x", 8000) }, "Summary") end)
	for _, session in ipairs({ { toolFilter = { fixture_scoped = true } }, { toolExclude = { workspace_result_read = true } } }) do
		local result = f.dispatch("fixture_scoped", {}, { session = session, aborted = function() return false end })
		check("excluded readers are never advertised", not has(result.modelText, "workspace_result_read") and #result.modelText <= 600)
	end
	f.env.require("agent/permissions").setRule("workspace_result_read", "deny")
	check("denied readers are never advertised", not has(f.dispatch("fixture_scoped").modelText, "workspace_result_read"))
	f.healthy(); f.close()
end)

case("postTool amendments cannot expose earlier retained source or fields", function()
	local f = F.new(); f.tools({ "coding" })
	local N, hooks = f.env.require("tools/native_helpers"), f.env.require("agent/hooks")
	register(f, "fixture_hooked", "coding", function() return N.result({ private = string.rep("hidden", 1200) }, "private source marker") end)
	local off = hooks.register("postTool", function(payload) if payload.tool.name == "fixture_hooked" then payload.text = "REDACTED" end end)
	local result = f.dispatch("fixture_hooked")
	check("post-hook text is authoritative", has(result.modelText, "REDACTED") and not has(result.modelText, "private source marker"))
	local data = decode(f, result.modelText)
	check("pre-hook retention is not offered to the model", data.readTool == nil and data.resultId == nil and data.result_id == nil)
	off()
	hooks.register("postTool", function(payload) if payload.tool.name == "fixture_hooked" then payload.data.status = "amended" end end)
	result = f.dispatch("fixture_hooked"); data = decode(f, result.modelText)
	check("in-place hook data changes invalidate previous retained detail", data.status == "amended" and data.readTool == nil and data.resultId == nil)
	f.healthy(); f.close()
end)

case("plain text results stay unchanged and cyclic host data fails safely", function()
	local f = F.new(); f.tools({})
	register(f, "fixture_plain", "misc", function() return "plain result" end)
	local plain = f.dispatch("fixture_plain")
	check("text-only tools keep their established content", plain.modelText == nil and plain.text == "plain result")
	local graph = {}; graph.self = graph
	register(f, "fixture_cycle", "misc", function() return { text = "Observed data", data = graph } end)
	local result = f.dispatch("fixture_cycle")
	check("cyclic data cannot crash dispatch or inflate context", result.ok and #result.modelText < 600 and has(result.modelText, "Observed data"))
	f.healthy(); f.close()
end)

suite.finish()
