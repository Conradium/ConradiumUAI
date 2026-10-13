-- Test harness emitted into the same managed execution chunk as project modules.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	function M.program(ids, filter)
		local quoted = {}
		for _, id in ipairs(ids) do quoted[#quoted + 1] = string.format("%q", id) end
		return "local __testIds = {" .. table.concat(quoted, ",") .. "}\nlocal __filter = " .. string.format("%q", filter or "") .. "\n" .. [[
local __fixtures = ... or {}
local __report = { passed = 0, failed = 0, total = 0, skipped = 0, cases = {}, complete = true, filter = __filter }
local function __copy(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local out = {}; seen[value] = out
	for key, child in pairs(value) do out[key] = __copy(child, seen) end
	return out
end
local function __trace(err)
	local message = tostring(err)
	if debug and debug.traceback then message = debug.traceback(message, 2) end
	return string.sub(message, 1, 2000)
end
local function __record(id, name, ok, err)
	if __report.total >= 100 then
		__report.complete, __report.reason = false, "At most 100 test cases per run; remaining cases were not executed"
		return false
	end
	__report.total = __report.total + 1
	if ok then __report.passed = __report.passed + 1 else __report.failed = __report.failed + 1 end
	__report.cases[#__report.cases + 1] = { module = id, name = name, ok = ok, error = not ok and tostring(err) or nil }
	return true
end
local __assertions = {}
function __assertions.equal(actual, expected, message)
	if actual ~= expected then error(message or ("Expected " .. tostring(expected) .. ", got " .. tostring(actual)), 2) end
end
function __assertions.truthy(value, message) if not value then error(message or "Expected a truthy value", 2) end end
function __assertions.raises(callback, contains)
	local ok, err = pcall(callback)
	if ok then error("Expected an error", 2) end
	if contains and not string.find(tostring(err), contains, 1, true) then error("Error did not contain " .. contains, 2) end
end
for _, id in ipairs(__testIds) do
	if __report.total >= 100 then
		__report.complete, __report.reason = false, "At most 100 test cases per run; remaining modules were not executed"
		break
	end
	local ok, suite = xpcall(function() return __newRequire(__copy(__fixtures))(id) end, __trace)
	if not ok or type(suite) ~= "table" then
		__record(id, "load", false, ok and "Test module must return a table of named functions" or suite)
	else
		local names, invalid = {}, nil
		for name, callback in pairs(suite) do
			if type(name) ~= "string" or #name > 120 or type(callback) ~= "function" then invalid = "Test names must be strings up to 120 bytes mapped to functions"; break end
			names[#names + 1] = name
			if #names > 100 then invalid = "Test module exceeds the 100-case run limit"; break end
		end
		if invalid then
			__record(id, "discovery", false, invalid)
		else
			table.sort(names)
			if #names == 0 then __record(id, "empty", false, "Test module contains no cases") end
			for _, name in ipairs(names) do
				if __filter ~= "" and not string.find(name, __filter, 1, true) then
					__report.skipped = __report.skipped + 1
				else
					if __report.total >= 100 then
						__report.complete, __report.reason = false, "At most 100 test cases per run; remaining cases were not executed"
						break
					end
					local passed, why = xpcall(function()
						-- Each case reloads project modules and fixtures; native game state is shared.
						local fixture = __copy(__fixtures)
						local require = __newRequire(fixture)
						local fresh = require(id)
						if type(fresh) ~= "table" or type(fresh[name]) ~= "function" then error("Test exports changed during discovery") end
						fresh[name](__copy(__assertions), fixture)
					end, __trace)
					__record(id, name, passed, why)
				end
			end
		end
	end
end
if __report.total == 0 then __report.complete, __report.reason = false, "No test cases matched the requested filter" end
return __report
]]
	end
	function M.fixtures(value)
		if value == nil then return {} end
		if type(value) ~= "table" then return nil, "fixtures must be a JSON object" end
		local ok, encoded = pcall(util.encode, value)
		if not ok then return nil, "Could not encode fixtures: " .. tostring(encoded) end
		if #encoded > 32000 then return nil, "fixtures exceed 32000 bytes" end
		return util.decode(encoded)
	end
	return M
end
