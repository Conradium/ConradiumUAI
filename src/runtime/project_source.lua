-- Bounded lexical outlines. These are source hints, not a type checker or LSP.
return function(env)
	local util = env.require("runtime/util")
	local M = { MAX_FILE = 256000, MAX_TOKENS = 50000 }
	-- Exact source strings are keys: hashes identify revisions but never prove a
	-- cache hit. Return copies so a caller cannot change later inspections.
	local cache, cacheCount, cacheBytes, sequence = {}, 0, 0, 0
	local hits, misses = 0, 0
	local CACHE_ITEMS, CACHE_BYTES = 128, 4 * 1024 * 1024
	local function stopped(ctx) return ctx and ctx.aborted and ctx.aborted() end
	local function remember(text, outline)
		local weight = #text + 256
		for _, item in ipairs(outline.symbols) do weight = weight + #item.name + 96 end
		for _, item in ipairs(outline.imports) do weight = weight + #(item.id or "") + 80 end
		while cacheCount >= CACHE_ITEMS or cacheBytes + weight > CACHE_BYTES do
			local oldest, stamp
			for key, entry in pairs(cache) do
				if not stamp or entry.used < stamp then oldest, stamp = key, entry.used end
			end
			if not oldest then return end
			cacheBytes, cacheCount = cacheBytes - cache[oldest].weight, cacheCount - 1
			cache[oldest] = nil
		end
		-- Another reader may have populated this source while scan yielded.
		if cache[text] then cacheBytes, cacheCount = cacheBytes - cache[text].weight, cacheCount - 1 end
		sequence = sequence + 1
		cache[text] = { outline = util.deepCopy(outline), weight = weight, used = sequence }
		cacheBytes, cacheCount = cacheBytes + weight, cacheCount + 1
	end
	function M.cacheInfo()
		return { hits = hits, misses = misses, entries = cacheCount, bytes = cacheBytes, maxEntries = CACHE_ITEMS, maxBytes = CACHE_BYTES }
	end
	function M.hash(source)
		local value = 5381
		for i = 1, #source do value = (value * 33 + source:byte(i)) % 4294967296 end
		return string.format("%08x:%d", value, #source)
	end
	function M.valid(source)
		return type(source) == "string" and #source <= M.MAX_FILE and not source:find("%z") and util.validUtf8(source)
	end
	local function literal(raw)
		local quote = raw:sub(1, 1)
		if (quote ~= '"' and quote ~= "'") or raw:sub(-1) ~= quote then return nil end
		local text = raw:sub(2, -2)
		-- Module IDs have no escapes; other string expressions remain inspectable.
		if text:find("\\", 1, true) then return nil end
		return text
	end
	function M.scan(source, ctx)
		if stopped(ctx) then return nil, "Inspection cancelled" end
		local saved = type(source) == "string" and cache[source]
		if saved then
			sequence, hits = sequence + 1, hits + 1
			saved.used = sequence
			return util.deepCopy(saved.outline)
		end
		if not M.valid(source) then return nil, "Source must be UTF-8 text without NUL, at most 256000 bytes" end
		misses = misses + 1
		local tokens, at, line, column = {}, 1, 1, 1
		local function consume(last, kind)
			local raw = source:sub(at, last)
			if kind then tokens[#tokens + 1] = { text = raw, kind = kind, line = line, column = column, offset = at } end
			local _, count = raw:gsub("\n", "")
			if count > 0 then line, column = line + count, #raw - (raw:match(".*()\n") or 0) + 1
			else column = column + #raw end
			at = last + 1
		end
		local steps = 0
		while at <= #source do
			if #tokens >= M.MAX_TOKENS then return nil, "Source exceeds the 50000-token inspection limit" end
			steps = steps + 1
			if steps % 1024 == 0 then
				task.wait()
				if stopped(ctx) then return nil, "Inspection cancelled" end
			end
			local char, pair = source:sub(at, at), source:sub(at, at + 1)
			local comment = pair == "--"
			local open = comment and at + 2 or at
			local equals = source:match("^%[(=*)%[", open)
			if equals then
				local _, last = source:find("]" .. equals .. "]", open + #equals + 2, true)
				consume(last or #source, not comment and "string" or nil)
			elseif comment then consume((source:find("\n", at, true) or (#source + 1)) - 1)
			elseif char:match("%s") then
				local _, last = source:find("^%s+", at); consume(last)
			elseif char == '"' or char == "'" or char == string.char(96) then
				local last = at + 1
				while last <= #source do
					local current = source:sub(last, last)
					if current == "\\" then last = last + 2
					elseif current == char then last = last + 1; break
					else last = last + 1 end
				end
				consume(math.min(last - 1, #source), "string")
			elseif char:match("[%a_]") then
				local word = source:match("^[%a_][%w_]*", at); consume(at + #word - 1, "word")
			else consume(at, "punctuation") end
		end
		local symbols, imports, omitted = {}, {}, 0
		local function symbol(name, token, kind)
			if #symbols < 256 then symbols[#symbols + 1] = { name = util.ellipsis(name, 160), nameTruncated = #name > 160, kind = kind, line = token.line, column = token.column, offset = token.offset }
			else omitted = omitted + 1 end
		end
		for i, token in ipairs(tokens) do
			local previous, following = tokens[i - 1], tokens[i + 1]
			if token.text == "function" and following and following.kind == "word" then
				local name, j = following.text, i + 2
				while tokens[j] and (tokens[j].text == "." or tokens[j].text == ":") and tokens[j + 1] and tokens[j + 1].kind == "word" do
					name, j = name .. tokens[j].text .. tokens[j + 1].text, j + 2
				end
				symbol(name, following, "function")
			elseif token.text == "local" and following and following.kind == "word" and following.text ~= "function" then
				symbol(following.text, following, "local")
			elseif token.text == "require" and (not previous or (previous.text ~= "." and previous.text ~= ":" and previous.text ~= "function")) then
				local argument = following and following.text == "(" and tokens[i + 2] or following
				if following and (following.text == "(" or following.kind == "string") then
					local id = argument and argument.kind == "string" and literal(argument.text) or nil
					if id and #id > 100 then id = nil end
					if following.text == "(" and (not tokens[i + 3] or tokens[i + 3].text ~= ")") then id = nil end
					if #imports < 256 then imports[#imports + 1] = { id = id, dynamic = id == nil, line = token.line, column = token.column }
					else omitted = omitted + 1 end
				end
			end
		end
		local outline = { hash = M.hash(source), bytes = #source, lines = line, symbols = symbols, imports = imports,
			omitted = omitted, coverage = "lexical hints; no scope/type inference; interpolated string expressions are opaque" }
		if stopped(ctx) then return nil, "Inspection cancelled" end
		remember(source, outline)
		return outline
	end
	env.require("runtime/dispose").add(function() cache, cacheCount, cacheBytes = {}, 0, 0 end, "Project source inspection cache")
	return M
end
