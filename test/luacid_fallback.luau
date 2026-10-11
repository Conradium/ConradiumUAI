-- The bundled luacid fallback, exercised with the real Luau compiler.
--
-- The offline LuaJIT harness compiles the project's portable dialect, so it
-- cannot compile the vendored luacid asset (which uses string interpolation).
-- Lune runs real Luau, so this check loads the generated wrapper, installs the
-- asset against a deliberately narrow compiled environment, and verifies both
-- where the executor functions come from and what the service call looks like.
--
-- Usage: lune run test/luacid_fallback.luau

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local luneTask = require("@lune/task")

local passed = 0
local function check(label, condition, detail)
	if not condition then error("FAIL " .. label .. (detail and (" -- " .. tostring(detail)) or ""), 0) end
	passed += 1
	stdio.write("ok " .. label .. "\n")
end

local function encodeJson(value)
	local kind = type(value)
	if kind == "string" then
		return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
	elseif kind == "number" or kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		local parts = {}
		if #value > 0 then
			for _, item in ipairs(value) do parts[#parts + 1] = encodeJson(item) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		for key, item in pairs(value) do
			if item ~= nil then parts[#parts + 1] = encodeJson(tostring(key)) .. ":" .. encodeJson(item) end
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local function encodeUrl(text)
	return tostring(text):gsub("[^%w%-_%.~]", function(character) return string.format("%%%02X", character:byte()) end)
end

-- The host's global table. A real getgenv() exposes the standard library, so
-- resolving names through the ambient environment keeps the pin faithful;
-- Lune's separate _G is not that table, and it has no executor `task`.
local AMBIENT = getfenv(1)
local TASK = {
	wait = luneTask.wait, spawn = luneTask.spawn, defer = luneTask.defer,
	delay = luneTask.delay, cancel = luneTask.cancel,
}

local function build(options)
	options = options or {}
	local state = {}
	local globals = setmetatable({}, { __index = AMBIENT })
	local transport = options.request or function()
		return { StatusCode = 200, Body = "return 42\n", Headers = {} }
	end
	local bytecode = options.getscriptbytecode or function(script)
		return "\27LuaU<" .. tostring(script.Name) .. ">"
	end
	globals._G = globals
	globals.getgenv = function() return globals end
	globals.warn = function() end -- the asset warns on retries; keep the transcript readable
	globals.typeof = function(value) return type(value) end
	globals.task = TASK
	globals.identifyexecutor = function() return "Lune", "0" end
	globals.getscriptbytecode = bytecode
	globals.request = transport
	globals.game = { PlaceId = 100, GameId = 200, GetService = function(_, name)
		if name == "HttpService" then
			return {
				UrlEncode = function(_, text) return encodeUrl(text) end,
				JSONEncode = function(_, value) return encodeJson(value) end,
			}
		end
		error("unexpected service: " .. tostring(name))
	end }
	globals.decompile = options.decompile or function() return "-- native\nreturn 1" end
	local capsFn = {
		loadstring = function(source)
			-- A plain closure so the wrapper's setfenv can replace its environment;
			-- the asset is then compiled into whatever environment it pinned. This
			-- chunk's own environment has none of the executor functions, so the
			-- fallback only works when that pinning actually happened.
			local function loader()
				local pinned = getfenv(1)
				local chunk = luau.load(source, {
					debugName = "luacid-asset", environment = pinned, injectGlobals = false,
				})
				return chunk()
			end
			return loader
		end,
		getscriptbytecode = bytecode,
		request = transport,
		getgenv = function() return globals end,
	}
	local chunk = assert(luau.load(fs.readFile("src/runtime/luacid.lua"), {
		debugName = "runtime/luacid", injectGlobals = true,
	}))
	local factory = assert(chunk(), "runtime/luacid must return its env factory")
	state.luacid = factory({ require = function(id)
		assert(id == "runtime/caps", "unexpected module: " .. tostring(id))
		return { fn = capsFn }
	end })
	state.globals, state.capsFn = globals, capsFn
	return state
end

local function target(name)
	return { Name = name, ClassName = "LocalScript", GetFullName = function() return "Workspace." .. name end }
end

do
	local host = build()
	check("the fallback advertises itself on a complete host", host.luacid.available())
	local previous = host.globals.decompile
	local decompiler, why = host.luacid.install()
	check("the asset installs through the pinned environment", type(decompiler) == "function", why)
	check("the native decompiler global is restored", host.globals.decompile == previous and host.luacid.installed == decompiler)
	check("installing again returns the same tool", host.luacid.install() == decompiler)
	local source = decompiler(target("First"))
	check("a successful decompile returns source", source == "return 42\n", source)
	host.capsFn.request = nil
	check("unavailable when the host has no HTTP function", not host.luacid.available())
	host.capsFn.getgenv = nil
	check("unavailable when the host has no global environment", not host.luacid.available())
end

do
	local sent
	local host = build({ request = function(options)
		sent = options
		return { StatusCode = 200, Body = "return 7\n", Headers = {} }
	end })
	local decompiler = assert(host.luacid.install())
	local source = decompiler(target("Shape"))
	check("the service call carries the context envelope", sent ~= nil and sent.Method == "POST"
		and sent.Url:find("https://api.luacid.dev/decompile?", 1, true) == 1
		and sent.Headers["Content-Type"] == "application/vnd.luacid.decompile-context; version=1"
		and sent.Body:sub(1, 8) == "LUACCTX1"
		and sent.Body:find("\27LuaU<Shape>", 1, true) ~= nil)
	check("the response body becomes the source", source == "return 7\n", source)
end

do
	local host = build({ request = function()
		return { StatusCode = 403, Body = "denied", Headers = {} }
	end })
	local decompiler = assert(host.luacid.install())
	local notice = decompiler(target("Refused"))
	check("a refused request returns the service's notice, not source",
		type(notice) == "string" and notice:find("^%-%- Decompiler API request failed", 1) ~= nil, notice)
end

do
	local host = build({ getscriptbytecode = function() error("this script is protected", 0) end })
	local decompiler = assert(host.luacid.install())
	local notice = decompiler(target("Protected"))
	check("an unreadable script reports the read failure",
		type(notice) == "string" and notice:find("^%-%- Failed to read script bytecode", 1) ~= nil, notice)
end

do
	local host = build({ getscriptbytecode = function() return "" end })
	local decompiler = assert(host.luacid.install())
	local notice = decompiler(target("Empty"))
	check("empty bytecode is refused before any request is sent",
		type(notice) == "string" and notice:find("^%-%- Failed to read script bytecode", 1) ~= nil, notice)
end

do
	local first = true
	local host = build({ request = function()
		if first then
			first = false
			return { StatusCode = 200, Body = "", Headers = {} }
		end
		return { StatusCode = 200, Body = "return 9\n", Headers = {} }
	end })
	local decompiler = assert(host.luacid.install())
	local source = decompiler(target("Retried"))
	check("an empty success is retried instead of cached as source", source == "return 9\n", source)
end

stdio.write("luacid fallback: " .. passed .. " checks passed\n")
process.exit(0)
