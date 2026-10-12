-- Focused decompilation regressions. All script bytes and services are synthetic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Decompilation")
local case, check = suite.case, suite.check
local function has(value, part) return tostring(value):find(part, 1, true) ~= nil end
local function fixture()
	local f = F.new()
	f.sources, f.refs, f.caps = f.env.require("runtime/script_sources"), f.env.require("runtime/instance_refs"), f.env.require("runtime/caps")
	f.luacid = f.env.require("runtime/luacid")
	f.luacid.install = function() return nil, "unavailable fixture" end
	f.caps.fn.decompile, f.caps.fn.getscriptbytecode = nil, nil
	f.script = f.h.Instance.new("LocalScript", f.h.workspace); f.script.Name = "Fixture"
	f.key = f.refs.id(f.script)
	function f.inspect(options, ctx) return f.run(function() return f.sources.inspect(f.key, ctx, options or { decompile = true }) end) end
	return f
end

case("validation separates service documents and notices from Luau without a compiler", function()
	local f = fixture(); local validation = f.env.require("runtime/decompile_result")
	f.caps.fn.loadstring = nil
	for _, body in ipairs({ "", " \n-- error", "--[[failed\nprivate details]]", "--[=[failed\nprivate details]=]", "--[[unfinished",
		"<!doctype html><html>bad gateway</html>", '{"error":"private detail"}', '["error"]', '"error"', "true", "false", "null", "123" }) do
		check("non-source response is rejected", validation.problem(body) ~= nil)
	end
	for _, body in ipairs({ "return 42", "--[[header]]\nlocal x: number = 42\nreturn x", "--[=[header]=]\nreturn function() return false end" }) do
		check("real Luau survives comments and unavailable compiler", validation.problem(body) == nil)
	end
	check("invalid UTF-8 is rejected before caching", select(2, validation.problem("return '" .. string.char(255) .. "'")) == "invalid_source")
	f.env.require("runtime/code_limits").file = 16
	check("oversized output has a bounded diagnostic", select(2, validation.problem(string.rep("x", 17))) == "oversized_source")
	f.healthy(); f.close()
end)

case("malformed native output cannot displace a working fallback", function()
	for _, body in ipairs({ "return '" .. string.char(255) .. "'", string.rep("x", 65), "--[[failure\nprivate native detail]]", '{"error":"private native detail"}' }) do
		local f = fixture(); f.env.require("runtime/code_limits").file = 64
		f.caps.fn.decompile = function() return body end
		local called = 0
		f.luacid.install = function() return function(_, control)
			called = called + 1; check("fallback receives active request control", not control.aborted() and control.deadlineMs > 0)
			return "local answer: number = 42\nreturn answer"
		end end
		local item, why, detail = f.inspect(); assert(item)
		check("working fallback replaces malformed output", called == 1 and item.origin == "luacid" and item.readOnly and item.method == "decompiled")
		check("a successful capture carries no spurious failure reason", why == nil and detail == nil)
		check("recovery explains the safe reason without native text", item.diagnostics and not has(item.diagnostics, "private native detail"))
		f.healthy(); f.close()
	end
end)

case("installer failure still reaches ByteFall and reports real service failure", function()
	local f = fixture(); f.caps.fn.getscriptbytecode = function() return "ABC" end
	f.luacid.install = function() error("private loader detail") end
	f.h.http.queue({ StatusCode = 200, Body = "return 42", Headers = { ["content-type"] = "text/plain" } })
	local item = assert(f.inspect())
	check("throwing installer cannot skip the final fallback", item.origin == "bytefall" and not has(item.diagnostics, "private loader detail"))
	f.h.http.queue({ StatusCode = 500, Body = "private service detail", Headers = {} })
	local failed, why, detail = f.inspect({ decompile = true, refresh = true })
	check("an available failing service is a failure, not missing capability", not failed and detail.code == "decompiler_failure" and detail.status == "error")
	check("only the safe HTTP status reaches diagnostics", has(why, "HTTP 500") and not has(why, "private service detail") and not has(why, "private loader detail"))
	f.healthy(); f.close()
end)

case("abandoned native calls never start a later fallback", function()
	for _, mode in ipairs({ "cancel", "deadline", "refresh" }) do
		local f = fixture(); local owner, fallbacks, outcome = {}, 0, nil
		if mode == "deadline" then f.env.require("runtime/code_limits").sourceDeadline = 50 end
		f.caps.fn.decompile = function() f.h.sched.wait(0.1); return "-- native failure" end
		f.luacid.install = function() fallbacks = fallbacks + 1; return function() return "return 42" end end
		f.h.sched.spawn(function() local _, _, detail = f.sources.inspect(f.key, { requestOwner = owner }, { decompile = true }); outcome = detail end)
		f.h.sched.advance(0.02)
		if mode == "cancel" then f.sources.cancel(owner) elseif mode == "refresh" then f.sources.invalidate(f.key) end
		f.h.sched.advance(0.2)
		check("stale " .. mode .. " call stops before another service", outcome and outcome.code == "stale_request" and fallbacks == 0)
		check("stale native completion releases its worker without caching", f.sources.state().workers == 0 and f.sources.state().snapshots == 0)
		f.healthy(); f.close()
	end
end)

case("one cancelled owner cannot cancel another waiter's fallback", function()
	local f = fixture(); local owner, results, native, fallbacks = {}, {}, 0, 0
	f.caps.fn.decompile = function() native = native + 1; f.h.sched.wait(0.08); return "-- failed" end
	f.luacid.install = function() return function(_, control)
		fallbacks = fallbacks + 1; check("another waiter keeps the request active", not control.aborted()); return "return 42"
	end end
	f.h.sched.spawn(function() local _, _, detail = f.sources.inspect(f.key, { requestOwner = owner }, { decompile = true }); results.cancelled = detail end)
	f.h.sched.spawn(function() results.active = f.sources.inspect(f.key, nil, { decompile = true }) end)
	f.h.sched.advance(0.02); f.sources.cancel(owner); f.h.sched.advance(0.2)
	check("one shared native call and fallback serve the remaining reader", native == 1 and fallbacks == 1 and results.cancelled.code == "stale_request" and results.active.source == "return 42")
	check("completed source is reused without another service call", f.inspect().id == results.active.id and native == 1)
	f.healthy(); f.close()
end)

case("ByteFall preserves binary bytecode and rejects malformed success bodies", function()
	local f = fixture(); local bytefall = f.env.require("runtime/bytefall")
	f.caps.fn.getscriptbytecode = function() return string.char(0, 255, 65, 66) end
	-- Bypass the fixture's standard executor wrapper so aliases reach this backend.
	f.caps.fn.request = function(options) return f.h.http.dispatch(options, "executor") end
	f.h.http.queue({ Status = "200", ResponseData = "return 42", Headers = { ["content-type"] = "text/plain" } })
	local item = assert(f.inspect())
	local request = f.h.http.log[#f.h.http.log]
	check("binary bytecode is base64 in the documented JSON envelope", request.body == '{"script":"AP9BQg=="}' and request.url == bytefall.URL and item.origin == "bytefall")
	for _, reply in ipairs({
		{ StatusCode = 200, Body = "return 42", Headers = { ["content-type"] = "application/json" } },
		{ StatusCode = 200, Body = "<html>private error</html>", Headers = {} },
		{ StatusCode = 200, Body = '{"error":"private error"}', Headers = {} },
		{ StatusCode = 200, Body = "--[=[private error]=]", Headers = {} },
	}) do
		f.h.http.queue(reply)
		local failed, why, detail = f.inspect({ decompile = true, refresh = true })
		check("HTTP 200 is insufficient to publish source", not failed and detail.code == "decompiler_failure" and not has(why, "private error"))
	end
	check("only the original valid snapshot was retained", f.sources.state().snapshots == 1)
	f.healthy(); f.close()
end)

case("ByteFall bounds bytecode and checks cancellation after reading it", function()
	local f = fixture(); local bytefall = f.env.require("runtime/bytefall")
	bytefall.MAX_BYTECODE = 3
	f.caps.fn.getscriptbytecode = function() return "ABCD" end
	local source = f.run(function() return bytefall.decompile(f.script) end)
	check("oversized bytecode never leaves the client", has(source, "2 MiB request limit") and #f.h.http.log == 0)
	f.caps.fn.getscriptbytecode = function() f.h.sched.wait(0.1); return "ABC" end
	f.env.require("runtime/code_limits").sourceDeadline = 50
	local failed, _, detail = f.inspect()
	check("a slow bytecode reader cannot start an expired HTTP request", not failed and detail.code == "stale_request" and #f.h.http.log == 0)
	f.healthy(); f.close()
end)

case("native HTTP keeps its worker slot until an expired request really returns", function()
	local f = fixture(); local calls, timeout = 0, nil
	f.env.require("runtime/code_limits").sourceDeadline = 50
	f.caps.fn.getscriptbytecode = function() return "ABC" end
	f.caps.fn.request = function(options)
		calls, timeout = calls + 1, options.Timeout; f.h.sched.wait(0.15)
		return { StatusCode = 200, Body = "return 42", Headers = {} }
	end
	local result
	f.h.sched.spawn(function() local _, _, detail = f.sources.inspect(f.key, nil, { decompile = true }); result = detail end)
	f.h.sched.advance(0.08)
	check("the waiter stops while native work remains counted", result.code == "stale_request" and f.sources.state().workers == 1 and calls == 1 and timeout == 1)
	f.h.sched.advance(0.2)
	check("late native HTTP neither caches nor retries", f.sources.state().workers == 0 and f.sources.state().snapshots == 0 and calls == 1)
	f.healthy(); f.close()
end)

case("script_source pages a retained decompile without rerunning or executing it", function()
	local f = fixture(); f.tools({ "script" }); local calls = 0
	local source = "local text = [[" .. string.rep("synthetic source ", 400) .. "]]\nreturn text"
	f.caps.fn.decompile = function() calls = calls + 1; return source end
	local first = f.dispatch("script_source", { instance_id = f.key, decompile = true, limit = 300 })
	check("tool exposes immutable decompile identity and continuation", first.ok and first.data.source.readOnly and first.data.source.method == "decompiled" and first.data.nextOffset)
	local nextPage = f.dispatch("script_source", { source_id = first.data.sourceId, offset = first.data.nextOffset, limit = 300 })
	check("continuation keeps the exact snapshot and native call count", nextPage.ok and nextPage.data.sourceId == first.data.sourceId and calls == 1)
	f.healthy(); f.close()
end)

suite.finish()
