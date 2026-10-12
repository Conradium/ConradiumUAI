-- The ByteFall decompile service: the second bundled fallback, after the
-- executor's own decompiler and the compiled-in luacid client.
--
-- It is a plain HTTP call -- base64 bytecode in a small JSON envelope -- so it
-- needs no compiler, only the bytecode reader and HTTP function the client has
-- already probed. That makes it the fallback of last resort on a host whose
-- executor cannot run the compiled luacid loader.
--
-- A successful response is Luau source as text; anything else becomes a comment
-- notice, the shape runtime/script_sources treats as "no source", so a service
-- error can never be cached or shown as script code.
return function(env)
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local limits = env.require("runtime/code_limits")
	local validation = env.require("runtime/decompile_result")
	local M = { URL = "https://decompiler.bytefall.dev/decompile", MAX_BYTECODE = 2 * 1024 * 1024 }
	local function stopped(control)
		if control and control.aborted then
			local ok, value = pcall(control.aborted)
			if not ok or value then return "cancelled" end
		end
		if control and control.deadlineMs and clock.ms() >= control.deadlineMs then return "deadline" end
		return nil
	end

	local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

	-- Standard base64 with padding, in the portable dialect: the executor's own
	-- encoder is not assumed, and the offline harness compiles this module too.
	function M.encode(data, control)
		local parts = {}
		for index = 1, #data, 3 do
			if control and index % 12288 == 1 then
				if index > 1 then clock.wait() end
				local reason = stopped(control); if reason then return nil, reason end
			end
			local first, second, third = data:byte(index), data:byte(index + 1), data:byte(index + 2)
			local value = first * 65536 + (second or 0) * 256 + (third or 0)
			local a = math.floor(value / 262144) % 64 + 1
			local b = math.floor(value / 4096) % 64 + 1
			local c = math.floor(value / 64) % 64 + 1
			local d = value % 64 + 1
			parts[#parts + 1] = ALPHABET:sub(a, a) .. ALPHABET:sub(b, b)
				.. (second and ALPHABET:sub(c, c) or "=") .. (third and ALPHABET:sub(d, d) or "=")
		end
		return table.concat(parts)
	end

	function M.available()
		return caps.fn.request ~= nil and caps.fn.getscriptbytecode ~= nil
	end

	local function notice(title, detail)
		return "-- " .. title .. "\n-- " .. tostring(detail):gsub("\r\n?", "\n"):gsub("\n", "\n-- ")
	end

	-- Source text, or a comment notice when the bytecode cannot be read or the
	-- service refuses the request. Only a 200 carrying a body is source.
	function M.decompile(object, control)
		control = control or { deadlineMs = clock.ms() + limits.sourceDeadline }
		local cancelled = stopped(control)
		if cancelled then return notice("ByteFall request failed (" .. cancelled .. ")", "source request is no longer active") end
		if caps.fn.getscriptbytecode == nil then
			return notice("Failed to read script bytecode", "the host cannot read script bytecode")
		end
		if caps.fn.request == nil then
			return notice("ByteFall request failed (no transport)", "the host has no executor HTTP function")
		end
		local readable, bytecode = pcall(caps.fn.getscriptbytecode, object)
		if not readable or type(bytecode) ~= "string" or bytecode == "" then
			return notice("Failed to read script bytecode", "the host did not return bytecode for this script")
		end
		if #bytecode > M.MAX_BYTECODE then return notice("Failed to read script bytecode", "bytecode exceeds the 2 MiB request limit") end
		local encoded, why = M.encode(bytecode, control)
		if not encoded then return notice("ByteFall request failed (" .. why .. ")", "source request is no longer active") end
		cancelled = stopped(control)
		if cancelled then return notice("ByteFall request failed (" .. cancelled .. ")", "source request is no longer active") end
		local deadline = math.min(control.deadlineMs or math.huge, clock.ms() + limits.sourceDeadline)
		-- The shared source worker retains its slot until this native request
		-- returns. A waiter timeout never abandons an uncounted HTTP coroutine.
		local sent, response = pcall(caps.fn.request, {
			Url = M.URL, Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["Accept"] = "text/plain" },
			Body = '{"script":"' .. encoded .. '"}',
			Timeout = math.max(1, math.ceil((deadline - clock.ms()) / 1000)),
		})
		cancelled = stopped(control)
		if cancelled then return notice("ByteFall request failed (" .. cancelled .. ")", "source request is no longer active") end
		local status = sent and type(response) == "table" and tonumber(response.StatusCode or response.Status) or nil
		local body = sent and type(response) == "table" and (response.Body or response.ResponseData) or nil
		if status == 200 then
			local contentType = ""
			for key, value in pairs(type(response.Headers) == "table" and response.Headers or {}) do
				if tostring(key):lower() == "content-type" then contentType = tostring(value):lower() end
			end
			local problem = validation.problem(body)
			if contentType:find("json", 1, true) or contentType:find("html", 1, true) then problem = "response is a service document" end
			if not problem then return body end
			return notice("ByteFall request failed (invalid source)", problem)
		end
		local label = status and ("HTTP " .. tostring(status)) or "no response"
		return notice("ByteFall request failed (" .. label .. ")", "the service did not return usable source; response details were omitted")
	end

	return M
end
