-- The relay owns the provider connection; every executor exchange stays short.
-- A lost submission is retried with the same ID, never as a second inference
-- request. The endpoint is resolved per call so a companion that appears or
-- restarts mid-session is picked up without a reload.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local config = env.require("runtime/config")
	local dispose = env.require("runtime/dispose")
	local transport = env.require("net/transport")
	local alive, pending = true, {}
	local M = {}

	local function noRelay()
		return { status = 599, body = util.encode({ error = { message =
			"This request needs a local relay. Start the Project UAI Companion app on this device, "
			.. "or enable the web bridge in Cowork settings." } }), headers = {}, via = "web", terminal = true }, nil
	end

	function M.request(spec, headers, call)
		local endpoint = transport.endpoint()
		if not endpoint then return noRelay() end
		local base, token, target = endpoint.base, endpoint.token, endpoint.target
		local via = target == "companion" and "relay" or "web"
		local timeout = util.clamp(tonumber(config.get("bridge.requestTimeout", 180)) or 180, 10, 86400)
		local id = "inference_" .. env.services.HttpService:GenerateGUID(false)
		local deadline = clock.ms() + (timeout + 30) * 1000
		local function short(method, path, body)
			return call({ url = base .. path, method = method, body = body,
				headers = { Authorization = "Bearer " .. token }, identity = "none", silent = true, timeout = 15 })
		end
		local function cancel()
			clock.spawn(function() pcall(short, "DELETE", "/api/inference/" .. id) end)
		end
		pending[id] = cancel
		local function ended()
			local current = transport.endpoint()
			return not alive or not current or current.target ~= target or current.token ~= token
				or current.base ~= base or (current.instance or "") ~= (endpoint.instance or "")
				or (spec.aborted and spec.aborted())
		end
		local function failure(message)
			pending[id] = nil
			return { status = 599, body = util.encode({ error = { message = message } }), headers = {},
				via = via, terminal = true }, nil
		end
		if token == "" then
			if target == "companion" then
				return failure("The companion relay is not paired. Open Cowork settings and pair again.")
			end
			return failure("Web runtime needs the bridge token in Cowork settings.")
		end
		local hello = short("GET", "/api/hello")
		local info = hello and hello.ok and util.decode(hello.body)
		if type(info) ~= "table" or info.protocol ~= 2 or not info.instance then
			if target == "companion" then
				return failure("The companion relay did not answer. Start the Project UAI Companion app, then retry.")
			end
			return failure("Web runtime cannot connect. Start the updated bridge/server.js and check its token.")
		end
		local payload = util.encode({ id = id, instance = info.instance, url = spec.url, headers = headers,
			body = spec.body, timeout = timeout, sessionId = spec.sessionId })
		local submitted, attempts = false, 0
		while clock.ms() < deadline do
			if ended() then cancel(); pending[id] = nil; return nil, "aborted" end
			local response
			if not submitted then
				attempts = attempts + 1
				response = short("POST", "/api/inference", payload)
			else response = short("GET", "/api/inference/" .. id) end
			if ended() then cancel(); pending[id] = nil; return nil, "aborted" end
			if response and response.ok then
				local job = util.decode(response.body)
				if type(job) ~= "table" or job.id ~= id then cancel(); return failure("Invalid relay response; inference was not resubmitted.") end
				submitted = true
				if job.state == "completed" then
					pending[id] = nil
					return { status = job.status, headers = job.headers or {}, body = job.body or "", via = via, inferenceId = id }
				elseif job.state ~= "running" then
					return failure(job.error or ("Relay job " .. tostring(job.state) .. "; inference was not resubmitted."))
				end
			elseif response and response.status >= 400 and response.status < 500 then
				cancel()
				local decoded = util.decode(response.body or "")
				local reason = type(decoded) == "table" and type(decoded.error) == "string" and util.truncate(decoded.error, 400) or "Check the bridge token and restart state."
				return failure("Relay rejected the request (" .. response.status .. "): " .. reason .. " Inference was not resubmitted.")
			elseif not submitted and attempts >= 3 then
				cancel(); return failure("Could not confirm relay submission; stopped without resubmitting inference.")
			end
			local slept = 0
			while slept < 1 do
				if ended() then cancel(); pending[id] = nil; return nil, "aborted" end
				slept = slept + (clock.wait(0.1) or 0.1)
			end
		end
		cancel()
		return failure("Relay result deadline reached; inference was cancelled rather than retried.")
	end
	dispose.add(function()
		alive = false
		for _, cancel in pairs(pending) do cancel() end
		pending = {}
	end, "relayed inference")
	return M
end
