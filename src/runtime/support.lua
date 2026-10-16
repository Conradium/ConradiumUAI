-- Shared support copy, independent of configuration, logging and presentation.
return function(env)
	local M = { invite = "https://discord.gg/9xYyyYuKap" }

	function M.opencodeProblem(message)
		local lower = tostring(message or ""):lower()
		if lower:find("go model requires global regions", 1, true) then return "region" end
		if lower:find("active opencode go subscription is required", 1, true) then return "subscription" end
		if lower:find("opencode proxy endpoint", 1, true) and (lower:find("deprecated", 1, true)
			or lower:find("retired", 1, true)) then return "retired" end
	end

	function M.error(message)
		local text = tostring(message or "An unexpected error occurred")
		-- Cancellation is a control signal used verbatim throughout the runtime.
		if text == "aborted" then return text end
		local lower = text:lower()
		local problem = M.opencodeProblem(text)
		if problem == "region" and not lower:find("review this privacy choice", 1, true) then
			text = text .. " -- In the OpenCode workspace that owns this key, this model requires Privacy regions set to Global. "
				.. "Review this privacy choice in OpenCode before changing it."
		elseif problem == "subscription" and not lower:find("check the key's workspace", 1, true) then
			text = text .. " -- Check the key's workspace and its Go subscription in OpenCode. "
				.. "If it is already active, report this refusal to OpenCode support. A public model list does not confirm subscription access."
		elseif problem == "retired" and not lower:find("a 410 does not validate", 1, true) then
			text = text .. " -- Select OpenCode Go for a Go subscription or OpenCode Zen for Zen access. "
				.. "A 410 does not validate your key or subscription."
		elseif not problem and not lower:find("mobile is unsupported", 1, true) and (lower:find("freetiererror", 1, true)
			or lower:find("can only be used from within opencode", 1, true)) then
			text = text .. " -- " .. M.opencode()
		end
		if text:find(M.invite, 1, true) then return text end
		return text .. "\nHelp and updates: " .. M.invite
	end

	function M.claudeCode()
		return "Claude Code (local CLI) needs Project UAI Bridge on this computer and your own installed Claude Code. "
			.. "Run `claude` in a terminal and sign in, then restart Cowork. It is for personal, local use only and is "
			.. "unavailable on mobile, through the Android companion and through relays."
	end

	function M.opencode()
		return "If the direct desktop workaround is refused, use the installed OpenCode CLI with Project UAI Desktop Bridge. "
			.. "Mobile is unsupported for OpenCode free models, including the Android companion. The OpenCode proxy is retired. "
			.. "Use Project UAI Free on mobile."
	end

	return M
end
