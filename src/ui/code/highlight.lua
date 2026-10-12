-- Highlighting is optional presentation. A lexer failure must leave source readable.
return function(env)
	local lexer = env.require("runtime/code_lexer")
	local M = {}
	M.lines = lexer.lines
	function M.scan(source, previous)
		local reusable = previous and not previous.plain and previous or nil
		local ok, result = pcall(lexer.scan, source, reusable)
		if ok then
			if previous and previous.plain then result.removed = previous.lines end
			return result
		end
		local lines, starts = lexer.lines(source)
		result = { source = source, lines = lines, starts = starts, spans = {}, states = {},
			added = lines, removed = previous and previous.lines or {}, plain = true }
		for index, line in ipairs(lines) do
			result.spans[index] = { { kind = "text", first = 1, last = #line } }
			result.states[index] = ""
		end
		return result
	end
	function M.richWindow(line, spans, colors, first, last)
		local ok, result = pcall(lexer.richWindow, line, spans, colors, first, last)
		return ok and result or lexer.escape(line:sub(first, last))
	end
	return M
end
