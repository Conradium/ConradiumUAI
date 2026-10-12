-- Run with: lune run test/lune_runner.luau test/native_script_syntax.luau
-- Actual Luau compilation/runtime with synthetic Roblox services and scheduling.
-- Project source still follows SPEC's LuaJIT-compatible authoring rules.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Native script syntax")
local case, check = suite.case, suite.check
local nativeCompile = loadstring

local function fixture()
	local f = F.new()
	local caps = f.env.require("runtime/caps")
	caps.fn.loadstring = function(source, name)
		local fn, why = nativeCompile(source, name)
		if fn then setfenv(fn, f.h.sandbox) end
		return fn, why
	end
	f.tools({ "script", "fs" })
	-- Lune's filesystem reads yield to its native scheduler. Load this lazy
	-- receipt dependency on the driver, before dispatch enters the virtual clock.
	f.env.require("agent/tool_result")
	local run = f.run
	f.run = function(...)
		local result = table.pack(pcall(run, ...))
		if not result[1] then
			local traces = { tostring(result[2]), "Virtual time: " .. tostring(f.h.sched.now) }
			for _, entry in ipairs(f.h.sched.queue) do
				traces[#traces + 1] = "Due " .. tostring(entry.at) .. ": " .. debug.traceback(entry.co)
			end
			error(table.concat(traces, "\n"), 0)
		end
		return table.unpack(result, 2, result.n)
	end
	return f
end

case("ordinary modern Luau survives compile and managed execution", function()
	local f = fixture()
	local code = [=[
local total: number = 0
for i = 1, 5 do
	if i == 3 then continue end
	total += i
end
return `half={total // 2}`, 0b101, 1_000
]=]
	check("check_luau accepts the real language", f.dispatch("check_luau", { code = code }).ok)
	local result = f.dispatch("run_luau", { code = code })
	check("instrumentation preserves modern syntax and returns", result.ok and result.text:find("half=6", 1, true)
		and result.text:find("1000", 1, true))
	f.healthy(); f.close()
end)

case("saved script creates a part with ordinary native method syntax", function()
	local f = fixture()
	local code = [=[
local world = game:GetService("Workspace")
local part = Instance.new("Part")
part.Name = "NativeScriptFixture"
part.Anchored = true
part.Position = Vector3.new(1, 2, 3)
part.Parent = world
return part.Name, part.Position.Y
]=]
	local saved = f.dispatch("file_write", { path = "files/native-syntax.lua", content = code })
	check("source saved exactly", saved.ok)
	check("saved-path compile succeeds", f.dispatch("check_luau", { path = "files/native-syntax.lua" }).ok)
	local result = f.dispatch("run_luau", { path = "files/native-syntax.lua" })
	local part = f.h.workspace:FindFirstChild("NativeScriptFixture")
	check("script performs the intended local change", result.ok and part and part.Anchored and part.Position.Y == 2)
	f.healthy(); f.close()
end)

case("comments and interpolated long literals remain data", function()
	local f = fixture()
	local code = [==[
--[[ do repeat while ]]
local text = [[do repeat { nested }]]
local value = `{text} / {[=[do { } repeat]=]}`
local seen = 0
for _, item in {2, 3} do seen += item end
return value, seen
]==]
	local result = f.dispatch("run_luau", { code = code })
	check("literal bodies are never instrumented", result.ok and result.text:find("do repeat { nested } / do { } repeat", 1, true))
	f.healthy(); f.close()
end)

suite.finish()
