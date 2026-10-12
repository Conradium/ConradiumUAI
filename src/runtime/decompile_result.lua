-- Validate decompiler responses without requiring a working host compiler.
return function(env)
	local util = env.require("runtime/util")
	local limits = env.require("runtime/code_limits")
	local M = {}
	function M.problem(source)
		if type(source) ~= "string" then return "returned no source text", "decompiler_failure" end
		if #source > limits.file then return "source exceeds 2 MiB", "oversized_source" end
		if not util.validUtf8(source) then return "source is not valid UTF-8", "invalid_source" end
		-- Strip only leading whitespace/comments. A block-comment diagnostic is
		-- no more source than a line-comment diagnostic; statements after either
		-- remain valid, including native Luau syntax the offline compiler lacks.
		local at = 1
		while at <= #source do
			local whitespace = source:match("^%s+", at)
			if whitespace then at = at + #whitespace
			elseif source:sub(at, at + 1) == "--" then
				local equals = source:match("^%-%-%[(=*)%[", at)
				if equals then
					local close = "]" .. equals .. "]"
					local finish = source:find(close, at + 4 + #equals, true)
					if not finish then return "returned an incomplete comment notice", "decompiler_failure" end
					at = finish + #close
				else
					local newline = source:find("\n", at + 2, true)
					at = newline and newline + 1 or #source + 1
				end
			else break end
		end
		if at > #source then return "returned empty or comment-only text", "decompiler_failure" end
		-- HTML and JSON success/error envelopes are not bare Luau chunks. Never
		-- cache them merely because an edge service returned HTTP 200.
		local first = source:sub(at, at)
		if first == "<" or first == "{" or first == "[" or first == '"' then
			return "returned a service document instead of Luau source", "invalid_source"
		end
		local bare = util.trim(source:sub(at))
		if bare == "true" or bare == "false" or bare == "null" or bare == "nil" or tonumber(bare) then
			return "returned a value instead of a Luau chunk", "invalid_source"
		end
		return nil
	end
	function M.noticeTitle(source)
		if type(source) ~= "string" then return nil end
		local first = (source:match("^%s*([^\n]*)") or ""):gsub("^%-%-%s*", ""):gsub("%s+$", "")
		if first == "Failed to read script bytecode" or first == "Decompiler API request failed" then return first end
		if first:match("^ByteFall request failed %(HTTP %d%d%d%)$") then return first end
		for _, label in ipairs({ "no transport", "no response", "no body", "cancelled", "deadline", "invalid source", "source too large" }) do
			if first == "ByteFall request failed (" .. label .. ")" then return first end
		end
		return nil
	end
	return M
end
