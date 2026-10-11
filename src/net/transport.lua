-- One place decides which transport carries an inference request, so providers,
-- the relay and the UI cannot drift: Cowork's web bridge, the local companion
-- relay, or the executor directly. Precedence is Cowork, then companion, then
-- direct, exactly as the transport contract requires.
return function(env)
	local config = env.require("runtime/config")
	local connection = env.require("net/bridge_connection")
	local relayLink = env.require("net/relay_link")

	local M = {}

	-- Today's rule for the Cowork web runtime.
	function M.coworkWeb()
		return connection.enabled() and config.get("bridge.runtime", "game") == "web"
	end

	function M.companionReady()
		return relayLink.usable()
	end

	function M.target()
		if M.coworkWeb() then return "cowork" end
		if M.companionReady() then return "companion" end
		return nil
	end

	-- Images always need a resolver, so they relay whenever any relay exists.
	function M.shouldRelay(imageRequest)
		return imageRequest == true or M.coworkWeb() or M.companionReady()
	end

	-- Streaming is forced only for Cowork; the companion returns the whole body.
	function M.streamForced()
		return M.coworkWeb()
	end

	-- The effective relay, preferring an enabled Cowork connection over the
	-- companion so images keep using the link they use today.
	function M.endpoint()
		if connection.enabled() then
			local current = connection.get()
			return { target = "cowork", base = "http://127.0.0.1:" .. tostring(current.port),
				token = current.token, instance = current.instance, enabled = current.enabled }
		end
		return relayLink.endpoint()
	end

	return M
end
