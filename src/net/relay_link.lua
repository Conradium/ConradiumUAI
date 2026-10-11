-- Discovers and pairs with the local inference relay (the mobile companion).
--
-- A phone's executor cuts long HTTP calls off after a wall-clock limit that a
-- reasoning turn easily exceeds. The companion is a tiny foreground service that
-- owns the upstream connection and answers every executor call in milliseconds.
-- This module finds it on loopback, pairs once for a stable token, and reports
-- whether it can be used. It performs no long work and never blocks boot.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local config = env.require("runtime/config")
	local dispose = env.require("runtime/dispose")
	local caps = env.require("runtime/caps")
	local http = env.require("net/http")
	local signal = env.require("runtime/signal")

	local M = { changed = signal.new("relay") }
	local alive, started, nextProbe, epoch = true, false, 0, 0
	local state, lastError, lastProbeAt = "off", nil, 0
	local PROBE_MS = 30000

	local function mode()
		local value = config.get("relay.mode", "auto")
		if value ~= "auto" and value ~= "always" and value ~= "off" then return "auto" end
		return value
	end

	local function port()
		local value = tonumber(config.get("relay.port", 8790)) or 8790
		if value < 1 or value > 65535 or value % 1 ~= 0 then return 8790 end
		return value
	end

	local function token() return tostring(config.get("relay.token", "")) end
	local function base() return "http://127.0.0.1:" .. tostring(port()) end

	function M.mode() return mode() end

	-- Presentation and defaults only; the prober runs the same way everywhere.
	local function mobile()
		local ok, touch = pcall(function() return env.uis.TouchEnabled == true end)
		if not ok then return false end
		local okMouse, mouse = pcall(function() return env.uis.MouseEnabled end)
		return touch and (not okMouse or mouse ~= true)
	end
	function M.mobile() return mobile() end

	local function setState(next, note)
		if state == next and lastError == note then return end
		state, lastError = next, note
		if next == "ready" then log.info("relay", "companion connected on port " .. tostring(port()))
		elseif next == "error" then log.debug("relay", "companion unavailable", note)
		elseif next == "searching" then log.debug("relay", "looking for the companion") end
		M.changed:fire()
	end

	local function remember(path, value)
		if config.get(path, "") ~= value then config.set(path, value, { quiet = true }) end
	end

	function M.status()
		return { mode = mode(), state = state, port = port(), server = tostring(config.get("relay.server", "")),
			instance = tostring(config.get("relay.instance", "")), placeId = tonumber(config.get("relay.placeId", 0)) or 0,
			error = lastError, lastProbeAt = lastProbeAt }
	end

	-- A single hello, then pair when a relay answers without a marker the client
	-- trusts. The marker is what stops a PC Cowork bridge -- which shares port 8790
	-- and also speaks protocol 2 -- from being mistaken for the companion.
	function M.probe()
		if not alive then return false, "unloaded" end
		if mode() == "off" then setState("off"); return false, "off" end
		if not caps.has("http") then setState("error", "no HTTP transport"); return false, "no HTTP transport" end
		setState("searching")
		local hello = http.request({ url = base() .. "/api/hello", method = "GET",
			identity = "none", silent = true, timeout = 1 })
		lastProbeAt = clock.ms()
		local info = hello and hello.ok and util.decode(hello.body)
		if type(info) ~= "table" or info.protocol ~= 2 or type(info.instance) ~= "string" or info.instance == "" then
			setState("error", "No companion answered on port " .. tostring(port()))
			return false, "no companion"
		end
		if token() == "" then
			if info.server ~= "uai-relay" then
				setState("error", "Port " .. tostring(port()) .. " is used by another program")
				return false, "not a companion"
			end
			local place = env.require("runtime/place")
			local body = util.encode({ client = "ProjectUAI-Mobile",
				version = (env.info and env.info.version) or "0.0.0", protocol = 2,
				placeId = place.id, gameId = place.gameId })
			local pair = http.request({ url = base() .. "/api/pair", method = "POST", body = body,
				headers = { ["Content-Type"] = "application/json" }, identity = "none", silent = true, timeout = 2 })
			local issued = pair and pair.ok and util.decode(pair.body)
			if type(issued) ~= "table" or issued.ok ~= true or type(issued.token) ~= "string"
				or #issued.token ~= 64 or not issued.token:match("^[a-f0-9]+$") then
				setState("error", "The companion refused pairing")
				return false, "pair failed"
			end
			remember("relay.token", issued.token)
			remember("relay.server", "uai-relay")
			remember("relay.placeId", place.id)
		end
		remember("relay.instance", tostring(info.instance))
		setState("ready")
		return true
	end

	function M.usable()
		return alive and mode() ~= "off" and state == "ready" and token() ~= "" and caps.has("http")
	end

	function M.endpoint()
		if not M.usable() then return nil end
		return { target = "companion", base = base(), token = token(),
			instance = tostring(config.get("relay.instance", "")), enabled = true }
	end

	local function start()
		if started or not alive then return end
		started = true
		clock.spawn(function()
			while alive do
				if mode() ~= "off" and clock.ms() >= nextProbe then
					local mine = epoch
					M.probe()
					if alive and mine == epoch then nextProbe = clock.ms() + PROBE_MS end
				end
				clock.wait(0.25)
			end
		end)
	end

	function M.ensure()
		if not alive then return end
		if mode() == "off" then setState("off"); return end
		start()
	end

	-- On-demand probe for a "Scan now" action.
	function M.scan()
		if mode() == "off" then return false, "off" end
		nextProbe = 0
		M.ensure()
		return M.probe()
	end

	function M.forget()
		remember("relay.token", "")
		remember("relay.server", "")
		remember("relay.instance", "")
		nextProbe = 0
		setState("searching")
	end

	dispose.add(config.changed:connect(function(path)
		if path ~= nil and path ~= "relay" and not util.startsWith(tostring(path), "relay.") then return end
		epoch = epoch + 1
		nextProbe = 0
		if path == "relay.port" then
			remember("relay.token", "")
			remember("relay.server", "")
			remember("relay.instance", "")
		end
		M.ensure()
		M.changed:fire()
	end), "relay settings")
	dispose.add(function() alive = false end, "relay prober")

	return M
end
