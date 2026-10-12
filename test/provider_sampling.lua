-- Synthetic adapter requests verify sampling preferences reach either protocol.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider sampling")
local case, check = suite.case, suite.check

local function fixture(style)
	local f = F.new()
	local record = { id = "sampling-fixture", label = "Sampling fixture", model = "gateway-fixture",
		baseUrl = "https://sampling.test/v1", api = style, authStyle = "none", params = {}, stream = false }
	f.sent = {}
	f.h.http.handler = function(entry)
		f.sent[#f.sent + 1] = f.h.json.decode(entry.body)
		local response = style == "anthropic"
			and { type = "message", content = { { type = "text", text = "ok" } }, stop_reason = "end_turn" }
			or { choices = { { message = { role = "assistant", content = "ok" }, finish_reason = "stop" } } }
		return { StatusCode = 200, Body = f.h.json.encode(response) }
	end
	function f.complete(overrides)
		local request = { messages = { { role = "user", content = "Inspect the document." } }, attempts = 1 }
		for key, value in pairs(overrides or {}) do request[key] = value end
		local result, why = f.run(function() return f.env.require("provider/chat").complete(record, request) end)
		check(style .. " completes: " .. tostring(why), result and result.content == "ok")
		return f.sent[#f.sent]
	end
	return f, record
end

case("configured and explicit temperatures reach compatible endpoints", function()
	for _, style in ipairs({ "openai", "anthropic" }) do
		local f, record = fixture(style)
		local config = f.env.require("runtime/config")
		config.set("agent.temperature", 0.7)
		check(style .. " sends the configured preference", f.complete().temperature == 0.7)
		check(style .. " sends an explicit zero", f.complete({ temperature = 0 }).temperature == 0)
		check(style .. " request preference wins", f.complete({ temperature = 0.2 }).temperature == 0.2)
		record.model = "claude-haiku-4-5"
		check(style .. " retains sampling for a documented compatible model", f.complete().temperature == 0.7)
		check(style .. " preserves the configured preference", config.get("agent.temperature") == 0.7)
		f.healthy(); f.close()
	end
end)

case("models documented to reject sampling omit ordinary preferences", function()
	for _, style in ipairs({ "openai", "anthropic" }) do
		local f, record = fixture(style)
		record.model = "claude-opus-4-7"
		f.env.require("runtime/config").set("agent.temperature", 0.7)
		check(style .. " omits configured sampling", f.complete().temperature == nil)
		check(style .. " omits request sampling", f.complete({ temperature = 0 }).temperature == nil)
		f.healthy(); f.close()
	end
end)

case("explicit raw parameter overrides retain their existing precedence", function()
	for _, style in ipairs({ "openai", "anthropic" }) do
		local f, record = fixture(style)
		record.params = { temperature = 0.5, top_p = 0.9 }
		check(style .. " provider parameters override ordinary preference", f.complete({ temperature = 0.2 }).temperature == 0.5)
		local extra = { temperature = 0.1, top_p = 0.8 }
		local body = f.complete({ temperature = 0.2, extra = extra })
		check(style .. " request raw parameters win", body.temperature == 0.1 and body.top_p == 0.8)
		check(style .. " preserves caller-owned parameters", record.params.temperature == 0.5 and record.params.top_p == 0.9
			and extra.temperature == 0.1 and extra.top_p == 0.8)
		f.healthy(); f.close()
	end
end)

suite.finish()
