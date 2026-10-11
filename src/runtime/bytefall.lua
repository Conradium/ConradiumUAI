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
	local M = { URL = "https://decompiler.bytefall.dev/decompile" }

	local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

	-- Standard base64 with padding, in the portable dialect: the executor's own
	-- encoder is not assumed, and the offline harness compiles this module too.
	function M.encode(data)
		local parts = {}
		for index = 1, #data, 3 do
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
	function M.decompile(object)
		if caps.fn.getscriptbytecode == nil then
			return notice("Failed to read script bytecode", "the host cannot read script bytecode")
		end
		if caps.fn.request == nil then
			return notice("ByteFall request failed (no transport)", "the host has no executor HTTP function")
		end
		local readable, bytecode = pcall(caps.fn.getscriptbytecode, object)
		if not readable or type(bytecode) ~= "string" or bytecode == "" then
			return notice("Failed to read script bytecode", readable and "the host returned no bytecode for this script" or bytecode)
		end
		local sent, response = pcall(caps.fn.request, {
			Url = M.URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["Accept"] = "text/plain" },
			Body = '{"script":"' .. M.encode(bytecode) .. '"}',
		})
		local status = sent and type(response) == "table" and response.StatusCode or nil
		local body = sent and type(response) == "table" and response.Body or nil
		if status == 200 and type(body) == "string" and body ~= "" then return body end
		local detail = status and ("HTTP " .. tostring(status)) or "no response"
		if not sent then detail = tostring(response) end
		if type(body) == "string" and body ~= "" then detail = detail .. "\n" .. body:sub(1, 300) end
		local label = status and ("HTTP " .. tostring(status)) or (sent and "no body" or "no response")
		return notice("ByteFall request failed (" .. label .. ")", detail)
	end

	return M
end
