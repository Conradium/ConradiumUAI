-- Deterministic offline scripting reference, invoked before client bundling.
-- Return an entry point so --check from bundle.lua never writes generated source.
return function(checkOnly)
	local input = "docs/SCRIPT_DEVELOPMENT.md"
	local output = "src/runtime/script_development_docs.lua"
	local function read(path)
		local file = assert(io.open(path, "rb"), "cannot read " .. path)
		local source = file:read("*a")
		file:close()
		return source:gsub("\r\n", "\n")
	end
	local guide = read(input)
	local headings, seen, offset = {}, {}, 1
	while true do
		local first, last, title = guide:find("\n## ([^\n]+)\n", offset)
		if not first then break end
		local key = title:lower():gsub("[^a-z0-9]+", "_"):gsub("^_", ""):gsub("_$", "")
		assert(key ~= "" and not seen[key], "duplicate or empty scripting guide section: " .. key)
		seen[key] = true
		headings[#headings + 1] = { start = first + 1, title = title, key = key }
		offset = last
	end
	assert(seen.quickstart and seen.tool_reference and seen.execution_and_cleanup,
		"scripting guide requires Quickstart, Tool reference, and Execution and cleanup")
	local function longString(source)
		local equals = "="
		while source:find("]" .. equals .. "]", 1, true) do equals = equals .. "=" end
		return "[" .. equals .. "[\n" .. source .. "]" .. equals .. "]"
	end
	local lines = {
		"-- Generated from docs/SCRIPT_DEVELOPMENT.md by tools/build_script_docs.lua; edit the Markdown.",
		"return function(env)",
		"\treturn {",
		'\t\turl = "https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md",',
		"\t\torder = {",
	}
	for _, heading in ipairs(headings) do lines[#lines + 1] = "\t\t\t" .. string.format("%q", heading.key) .. "," end
	lines[#lines + 1] = "\t\t},"
	lines[#lines + 1] = "\t\ttitles = {"
	for _, heading in ipairs(headings) do
		lines[#lines + 1] = "\t\t\t[" .. string.format("%q", heading.key) .. "] = " .. string.format("%q", heading.title) .. ","
	end
	lines[#lines + 1] = "\t\t},"
	lines[#lines + 1] = "\t\tsections = {"
	for index, heading in ipairs(headings) do
		local nextHeading = headings[index + 1]
		local body = guide:sub(heading.start, nextHeading and nextHeading.start - 1 or #guide):gsub("%s+$", "") .. "\n"
		lines[#lines + 1] = "\t\t\t[" .. string.format("%q", heading.key) .. "] = " .. longString(body) .. ","
	end
	lines[#lines + 1] = "\t\t},"
	lines[#lines + 1] = "\t}"
	lines[#lines + 1] = "end"
	lines[#lines + 1] = ""
	local generated = table.concat(lines, "\n")
	if checkOnly then
		local exists = io.open(output, "rb")
		assert(exists, output .. " is missing; run luajit tools/bundle.lua --native")
		exists:close()
		assert(read(output) == generated, output .. " is stale; run luajit tools/bundle.lua --native")
	else
		local file = assert(io.open(output, "wb"), "cannot write " .. output)
		assert(file:write(generated))
		file:close()
	end
	return #headings, #generated
end
