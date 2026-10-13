-- Focused v3 agent hot paths and tool contracts; synthetic services only.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Release agent efficiency")
local case, check = suite.case, suite.check
local function has(value, part) return tostring(value):find(part, 1, true) ~= nil end
local function call(id) return { id = id, ["function"] = { name = "fixture", arguments = "{}" } } end

case("SSE framing preserves byte-fragmented BOM, CRLF and multiline data", function()
	local f = F.new(); local sse = f.env.require("net/sse")
	local frames = {}
	local decoder = sse.decoder(function(frame) frames[#frames + 1] = frame end)
	local body = "\239\187\191event: completion\r\ndata: first\r\ndata: " .. string.rep("x", 32768) .. "\r\n\r\ndata: tail"
	for index = 1, #body do assert(decoder.push(body:sub(index, index))) end
	assert(decoder.finish())
	check("fragments produce exact events", #frames == 2 and frames[1].event == "completion"
		and frames[1].data == "first\n" .. string.rep("x", 32768) and frames[2].data == "tail")
	check("finished decoder has no buffered data", decoder.idle())
	local prior = sse.limits.frame; sse.limits.frame = 64
	local boundary = sse.decoder(function() end)
	check("exact frame boundary accepts its delimiter", boundary.push("data: " .. string.rep("a", 57) .. "\n\n"))
	local overflow = sse.decoder(function() end)
	check("oversized partial line is terminal", not overflow.push(string.rep("a", 65)) and not overflow.push("\n"))
	sse.limits.frame = prior
	f.healthy(); f.close()
end)

case("prose previews omit duplicate tool argument retention", function()
	local f = F.new(); local sse = f.env.require("net/sse")
	local preview, full = sse.assembler({ toolCalls = false }), sse.assembler()
	local chunk = { model = "fixture", choices = { { delta = { content = "Working", reasoning_content = "Inspecting",
		tool_calls = { { index = 0, id = "one", ["function"] = { name = "fixture", arguments = '{"source":"' .. string.rep("x", 10000) .. '"}' } } } } } } }
	assert(preview.feedChunk(chunk)); assert(full.feedChunk(chunk))
	check("preview stores no argument slots", #preview.order == 0 and next(preview.slots) == nil)
	check("preview still delivers both prose channels", preview.result().content == "Working" and preview.result().reasoning == "Inspecting")
	check("authoritative assembly retains the complete call", #full.result().toolCalls == 1 and #full.result().toolCalls[1]["function"].arguments > 10000)
	f.healthy(); f.close()
end)

case("context repair matches a batch once and removes duplicate receipts", function()
	local f = F.new(); local ctx = f.env.require("agent/context").new()
	ctx.pushUser("Inspect these")
	local calls = {}; for index = 1, 64 do calls[index] = call("call-" .. index) end
	ctx.pushAssistant({ toolCalls = calls })
	for index = 64, 2, -1 do ctx.pushToolResult("call-" .. index, "fixture", "result " .. index) end
	ctx.pushToolResult("call-64", "fixture", "duplicate")
	ctx.pushToolResult("unrelated", "fixture", "orphan")
	ctx.pushUser("Next request")
	local dropped, filled = ctx.repair()
	check("duplicate and orphan are dropped and missing outcome filled", dropped == 2 and filled == 1 and #ctx.messages == 67)
	check("synthetic outcome precedes the next request", ctx.messages[66].tool_call_id == "call-1" and ctx.messages[67].role == "user")
	local original = ctx.messages
	local again, missing = ctx.repair()
	check("valid repair is idempotent without replacing history", again == 0 and missing == 0 and ctx.messages == original)
	ctx.pushAssistant({ toolCalls = { call("call-64") } }); ctx.pushToolResult("call-64", "fixture", "new turn")
	check("IDs are matched within their own batch", ctx.repair() == 0)
	f.healthy(); f.close()
end)

case("validation preserves unions and bounds recursive work and feedback", function()
	local f = F.new(); local schema = f.env.require("agent/schema")
	for _, input in ipairs({ 42, "42", true }) do
		local value, errors, notes = schema.validate({ type = { "string", "number", "boolean" } }, input)
		check("valid union type stays unchanged", value == input and #errors == 0 and #notes == 0)
	end
	local recursive = { type = "object", properties = {} }; recursive.properties.next = recursive
	local cyclic = {}; cyclic.next = cyclic
	local _, depthErrors = schema.validate(recursive, cyclic)
	check("recursive arguments stop before stack exhaustion", #depthErrors == 1 and has(depthErrors[1], "size/depth"))
	local items = {}; for index = 1, 9000 do items[index] = index end
	local _, sizeErrors = schema.validate({ type = "array", items = { type = "number" } }, items)
	check("large schema walks stop at the value budget", #sizeErrors == 1 and has(sizeErrors[1], "size/depth"))
	local required = {}; for index = 1, 100 do required[index] = "field_" .. index end
	local _, errors = schema.validate({ type = "object", properties = {}, required = required }, {})
	check("invalid calls get bounded useful feedback", #errors == 16 and has(errors[1], "field_1"))
	local untouched = { "1", "2", "3" }
	local _, arrayErrors = schema.validate({ type = "array", maxItems = 2, items = { type = "number" } }, untouched)
	check("oversized arrays are rejected before coercing members", #arrayErrors == 1 and untouched[1] == "1")
	f.healthy(); f.close()
end)

case("invalid concurrency cannot strand an admitted batch", function()
	local f = F.new(); local registry = f.tools({}); local clock = f.env.require("runtime/clock")
	local config = f.env.require("runtime/config")
	registry.dispatch = function(item) clock.wait(0.01); return { id = item.id, ok = true, text = item.id } end
	for _, value in ipairs({ 0 / 0, math.huge, "invalid", -1, 0 }) do
		config.set("agent.toolConcurrency", value)
		local results = f.run(function() return registry.runAll({ call("a"), call("b") }, {}) end)
		check("invalid setting falls back and preserves order", #results == 2 and results[1].id == "a" and results[2].id == "b")
	end
	f.healthy(); f.close()
end)

case("small retained receipts deliver status and pointers without another round trip", function()
	local f = F.new(); local formatter = f.env.require("agent/tool_result")
	local details = f.env.require("tools/native_helpers")
	local receipt = details.result({ status = "applied", revision = 7, source = string.rep("x", 7000) }, "Applied 3 edits.", "coding")
	local model = formatter.render(receipt.text, receipt.data, 4000, "coding", function() return true end, true)
	check("bounded summary and revision are immediately visible", has(model, "Applied 3 edits.") and has(model, '"revision":7') and has(model, "workspace_result_read"))
	local unavailable = formatter.render(receipt.text, receipt.data, 4000, "coding", function() return false end, true)
	check("scope-excluded detail readers remain hidden", not has(unavailable, "workspace_result_read"))
	local amended = formatter.render("Hook amended result", receipt.data, 4000, "coding", function() return true end, false)
	check("post-hook receipts cannot redirect to old data", has(amended, "Hook amended result") and not has(amended, "workspace_result_read"))
	f.healthy(); f.close()
end)

case("Anthropic cached input is included in context accounting", function()
	local f = F.new(); local adapter = f.env.require("provider/anthropic")
	local result = adapter.fromMessage({ content = {}, usage = { input_tokens = 50, cache_read_input_tokens = 700,
		cache_creation_input_tokens = 100, output_tokens = 25 } })
	check("all input categories occupy the prompt window", result.usage.prompt_tokens == 850 and result.usage.total_tokens == 875)
	check("cache reads reach common usage metrics", result.usage.prompt_tokens_details.cached_tokens == 700)
	f.healthy(); f.close()
end)

case("conversation search skips paste reads when scoped and reports bounded scans", function()
	local f = F.new(); f.tools({ "agentself" })
	local sessions = f.env.require("agent/session")
	local current = assert(sessions.newThread({ ephemeral = true }))
	local other = assert(sessions.newThread({ ephemeral = true, title = "Prior work", activate = false }))
	other.ctx.pushUser("Find the lighthouse script")
	local fs = f.env.require("runtime/fsx"); local reads = 0
	fs.list = function() local items = {}; for index = 1, 200 do items[index] = { path = "paste" .. index, name = "paste" .. index } end; return items end
	fs.read = function() reads = reads + 1; return "unrelated" end
	local ctx = { session = current, aborted = function() return false end }
	local focused = f.dispatch("conversation_search", { query = "lighthouse", scope = "conversations" }, ctx)
	check("conversation-only search uses exact IDs without filesystem reads", focused.ok and reads == 0
		and focused.data.matches[1] and focused.data.matches[1].id == other.id)
	local bounded = f.dispatch("conversation_search", { query = "missing", scope = "pastes" }, ctx, 3)
	check("paste reads stop at the documented count", bounded.ok and reads == 128 and bounded.data.pastesRead == 128)
	check("a partial search never proves absence", bounded.data.complete == false and has(bounded.text, "incomplete"))
	f.healthy(); f.close()
end)

case("metadata reuses product facts and honors explicit refresh", function()
	local f = F.new(); local calls = 0
	f.h.services.MarketplaceService.GetProductInfo = function(_, id) calls = calls + 1; return { Name = "Asset " .. id, Creator = { Name = "Creator" } } end
	f.tools({ "meta" })
	local first = f.dispatch("game_info"); local second = f.dispatch("place_info")
	check("game/place requests share one product lookup", first.ok and second.ok and calls == 1 and second.data.cached)
	local fresh = f.dispatch("place_info", { refresh = true })
	check("refresh obtains fresh product metadata", fresh.ok and calls == 2 and not fresh.data.cached)
	local invalid = f.dispatch("user_lookup", { username = "Alice", user_id = 1 })
	check("ambiguous identity is rejected before HTTP", not invalid.ok and #f.h.http.log == 0)
	f.h.http.handler = function() return { StatusCode = 200, Body = "{}" } end
	local empty = f.dispatch("roblox_version")
	check("empty API documents are failures rather than nil-filled success", not empty.ok and has(empty.text, "no release version"))
	f.h.http.handler = function() return { StatusCode = 404, Body = '{"version":"not-a-success"}' } end
	local refusal = f.dispatch("roblox_version")
	check("HTTP errors cannot masquerade as metadata", not refusal.ok and has(refusal.text, "HTTP 404"))
	f.h.http.reset()
	local cancelled = false
	f.h.http.handler = function() cancelled = true; return { StatusCode = 200, Body = '{"data":[{"id":42}]}' } end
	local stopped = f.dispatch("user_lookup", { username = "Alice" }, { session = {}, aborted = function() return cancelled end })
	check("cancellation prevents a second identity request", not stopped.ok and #f.h.http.log == 1)
	f.healthy(); f.close()
end)

case("Responses tool identity and final arguments are assembled once", function()
	local f = F.new(); local adapter = f.env.require("provider/responses")
	local function stream(events)
		local frames = {}
		for _, event in ipairs(events) do frames[#frames + 1] = "data: " .. f.h.json.encode(event) .. "\n\n" end
		return table.concat(frames)
	end
	for _, ids in ipairs({ { "item-1", "call-1" }, { "same-id", "same-id" } }) do
		for _, added in ipairs({ false, true }) do
			local item = { type = "function_call", id = ids[1], call_id = ids[2], name = "fixture", arguments = "" }
			local events = {}
			if added then events[#events + 1] = { type = "response.output_item.added", output_index = 0, item = item } end
			events[#events + 1] = { type = "response.function_call_arguments.delta", item_id = ids[1], output_index = 0, delta = '{"value":' }
			events[#events + 1] = { type = "response.function_call_arguments.delta", item_id = ids[1], output_index = 0, delta = '42}' }
			events[#events + 1] = { type = "response.function_call_arguments.done", item_id = ids[1], output_index = 0, arguments = '{"value":42}' }
			events[#events + 1] = { type = "response.output_item.done", output_index = 0,
				item = { type = "function_call", id = ids[1], call_id = ids[2], name = "fixture", arguments = '{"value":42}' } }
			events[#events + 1] = { type = "response.completed", response = { status = "completed" } }
			local parsed = adapter.parse(stream(events))
			check("item and call IDs share one result without doubled JSON", not parsed.streamError and #parsed.toolCalls == 1
				and parsed.toolCalls[1].id == ids[2] and parsed.toolCalls[1]["function"].arguments == '{"value":42}')
		end
	end
	local parsed = adapter.parse(stream({
		{ type = "response.output_item.added", item = { type = "function_call", id = "item", call_id = "call", name = "fixture", arguments = "" } },
		{ type = "response.function_call_arguments.delta", item_id = "item", delta = "{}" },
		{ type = "response.completed", response = { output = { { type = "message", content = { { type = "output_text", text = "No action needed" } } } } } },
	}))
	check("authoritative final output clears superseded partial calls", not parsed.streamError and #parsed.toolCalls == 0 and parsed.content == "No action needed")
	f.healthy(); f.close()
end)

case("Responses call and argument bounds fail explicitly", function()
	local f = F.new(); local adapter, sse = f.env.require("provider/responses"), f.env.require("net/sse")
	local function stream(events)
		local frames = {}
		for _, event in ipairs(events) do frames[#frames + 1] = "data: " .. f.h.json.encode(event) .. "\n\n" end
		return table.concat(frames)
	end
	local calls, events = {}, {}
	for index = 1, sse.limits.calls + 1 do
		calls[index] = { type = "function_call", id = "item-" .. index, call_id = "call-" .. index, name = "fixture", arguments = "{}" }
		events[index] = { type = "response.output_item.done", item = calls[index] }
	end
	events[#events + 1] = { type = "response.completed", response = {} }
	check("streamed excess calls cannot become partial success", has(adapter.parse(stream(events)).streamError, "tool call limit"))
	check("final streamed excess calls cannot bypass the limit", has(adapter.parse(stream({ { type = "response.completed", response = { output = calls } } })).streamError, "tool call limit"))
	check("whole responses use the same call limit", has(adapter.fromResponse({ output = calls }).streamError, "tool call limit"))
	local prior = sse.limits.arguments; sse.limits.arguments = 8
	local oversized = { type = "function_call", id = "item", call_id = "call", name = "fixture", arguments = string.rep("x", 9) }
	check("whole responses reject oversized arguments", has(adapter.fromResponse({ output = { oversized } }).streamError, "tool argument limit"))
	check("done items reject oversized arguments", has(adapter.parse(stream({ { type = "response.output_item.done", item = oversized } })).streamError, "tool argument limit"))
	check("fragment totals are bounded", has(adapter.parse(stream({
		{ type = "response.function_call_arguments.delta", item_id = "item", delta = "12345" },
		{ type = "response.function_call_arguments.delta", item_id = "item", delta = "6789" },
	})).streamError, "tool argument limit"))
	sse.limits.arguments = prior
	f.healthy(); f.close()
end)

case("statistics preserve lifetime model metadata and hours across reload", function()
	local f = F.new(); local stats = f.env.require("agent/stats")
	local at = f.env.require("runtime/clock").ms()
	stats.recordMessage("user", at)
	stats.recordRequest({ model = "fixture-model", prompt = 12, completion = 8, cached = 3, at = at })
	assert(stats.saveNow())
	stats.load()
	local model = stats.data.models["fixture-model"]
	check("persisted model history remains available", model and model.requests == 1 and model.firstAt == at and model.lastAt == at)
	local hour = tostring(f.env.require("runtime/clock").hourOf(at))
	check("hour totals survive reload", stats.data.hours[hour] == 1)
	check("window model dates retain the recorded timestamp", stats.window("all").topModel.firstAt == at)
	f.healthy(); f.close()
end)

suite.finish()
