-- Virtual input: keyboard and mouse simulation.
--
-- Supports VirtualInputManager (standard engine input injector), executor globals
-- (keypress, mouse1click, etc.) and VirtualUser as fallbacks.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local H = env.require("tools/helpers")

	local KEY_ALIASES = {
		["0"] = "Zero",
		["1"] = "One",
		["2"] = "Two",
		["3"] = "Three",
		["4"] = "Four",
		["5"] = "Five",
		["6"] = "Six",
		["7"] = "Seven",
		["8"] = "Eight",
		["9"] = "Nine",
		enter = "Return",
		space = "Space",
		esc = "Escape",
		escape = "Escape",
		tab = "Tab",
		backspace = "Backspace",
		shift = "LeftShift",
		lshift = "LeftShift",
		rshift = "RightShift",
		ctrl = "LeftControl",
		control = "LeftControl",
		lctrl = "LeftControl",
		rctrl = "RightControl",
		alt = "LeftAlt",
		lalt = "LeftAlt",
		ralt = "RightAlt",
		up = "Up",
		down = "Down",
		left = "Left",
		right = "Right",
	}

	local validKeyCodes = nil
	local function getValidKeyCodes()
		if validKeyCodes then return validKeyCodes end
		validKeyCodes = {}
		local ok, items = pcall(function() return Enum.KeyCode:GetEnumItems() end)
		if ok and type(items) == "table" then
			for _, item in ipairs(items) do
				validKeyCodes[item.Name:lower()] = item
			end
		end
		return validKeyCodes
	end

	local function resolveKeyCode(rawName)
		local cleaned = util.trim(rawName or "")
		if cleaned == "" then return nil, "no key specified" end

		local lower = cleaned:lower()
		local targetName = KEY_ALIASES[lower] or cleaned

		local codes = getValidKeyCodes()
		if codes[targetName:lower()] then
			return codes[targetName:lower()]
		end

		if #cleaned == 1 then
			local upper = cleaned:upper()
			if codes[upper:lower()] then
				return codes[upper:lower()]
			end
		end

		return nil, "unrecognised KeyCode: '" .. cleaned .. "'"
	end

	local function getVim()
		local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
		return (ok and vim) or nil
	end

	local function getVu()
		local ok, vu = pcall(function() return game:GetService("VirtualUser") end)
		return (ok and vu) or nil
	end

	local function getMousePos(customX, customY)
		local x = tonumber(customX)
		local y = tonumber(customY)
		if x and y then return x, y end

		if env.uis and env.uis.GetMouseLocation then
			local ok, loc = pcall(function() return env.uis:GetMouseLocation() end)
			if ok and loc then
				x = x or loc.X
				y = y or loc.Y
			end
		end

		if not x or not y then
			local camera = env.services.Workspace and env.services.Workspace.CurrentCamera
			if camera and camera.ViewportSize then
				x = x or math.floor(camera.ViewportSize.X / 2)
				y = y or math.floor(camera.ViewportSize.Y / 2)
			end
		end

		return x or 0, y or 0
	end

	local function sendKeyVim(vim, keyCode, action, duration)
		if action == "press" then
			if vim:SendKeyEvent(true, keyCode, false, game) == false then return false end
			clock.wait(duration)
			return vim:SendKeyEvent(false, keyCode, false, game) ~= false
		elseif action == "down" then
			return vim:SendKeyEvent(true, keyCode, false, game) ~= false
		elseif action == "up" then
			return vim:SendKeyEvent(false, keyCode, false, game) ~= false
		end
		return false
	end

	local function sendKeyExecutor(keyCode, action, duration)
		local hasKp = pcall(function() return keypress end)
		local hasKr = pcall(function() return keyrelease end)
		if not (hasKp and hasKr and type(keypress) == "function" and type(keyrelease) == "function") then
			return false
		end

		local value = keyCode.Value
		if action == "press" then
			if keypress(value) == false then return false end
			clock.wait(duration)
			return keyrelease(value) ~= false
		elseif action == "down" then
			return keypress(value) ~= false
		elseif action == "up" then
			return keyrelease(value) ~= false
		end
		return false
	end

	local function sendKeyVu(vu, keyCode, action, duration)
		if vu:CaptureController() == false then return false end
		local name = keyCode.Name
		if action == "down" or action == "press" then
			if vu:SetKeyDown(name) == false then return false end
		end
		if action == "press" then
			clock.wait(duration)
		end
		if action == "up" or action == "press" then
			if vu:SetKeyUp(name) == false then return false end
		end
		return true
	end

	return {
		{
			name = "key_press",
			risk = "write",
			description = "Simulate pressing or holding a keyboard key (e.g. 'E', 'Space', 'Return', 'W', 'A', 'S', 'D', 'Tab', 'LeftShift', '1').",
			parameters = {
				type = "object",
				properties = {
					key = {
						type = "string",
						description = "Key name or character, e.g. 'E', 'Space', 'Return', 'W', '1', 'LeftShift'.",
					},
					action = {
						type = "string",
						enum = { "press", "down", "up" },
						description = "'press' taps key down and up. 'down' holds key. 'up' releases key. Default 'press'.",
					},
					duration = {
						type = "number",
						description = "Hold duration in seconds if action is 'press' (0.01 - 2.0, default 0.05).",
						minimum = 0.01,
						maximum = 2.0,
					},
				},
				required = { "key" },
			},
			run = function(args)
				local keyCode, keyErr = resolveKeyCode(args.key)
				if not keyCode then return H.fail(keyErr) end

				local action = args.action or "press"
				if action ~= "press" and action ~= "down" and action ~= "up" then return H.fail("unknown keyboard action") end
				local duration = util.clamp(tonumber(args.duration) or 0.05, 0.01, 2.0)

				local vim = getVim()
				local ok = false

				if vim and vim.SendKeyEvent then
					local okVim, sent = pcall(function()
						return sendKeyVim(vim, keyCode, action, duration)
					end)
					ok = okVim and sent == true
				end

				if not ok then
					local okExec, sent = pcall(function()
						return sendKeyExecutor(keyCode, action, duration)
					end)
					ok = okExec and sent == true
				end

				if not ok then
					local vu = getVu()
					if vu then
						local okVu, sent = pcall(function()
							return sendKeyVu(vu, keyCode, action, duration)
						end)
						ok = okVu and sent == true
					end
				end

				if not ok then
					return H.fail("no virtual input injection provider available on this host")
				end

				return string.format("Key %s: %s", keyCode.Name, action)
			end,
		},
		{
			name = "mouse_click",
			risk = "write",
			description = "Simulate mouse clicks or cursor movement on screen coordinates.",
			parameters = {
				type = "object",
				properties = {
					button = {
						type = "string",
						enum = { "left", "right", "middle" },
						description = "Mouse button to click. Default 'left'.",
					},
					action = {
						type = "string",
						enum = { "click", "down", "up", "move" },
						description = "'click' clicks down and up. 'down' holds button. 'up' releases button. 'move' positions cursor. Default 'click'.",
					},
					x = {
						type = "number",
						description = "Screen X coordinate in pixels. Defaults to current mouse location or viewport center.",
					},
					y = {
						type = "number",
						description = "Screen Y coordinate in pixels. Defaults to current mouse location or viewport center.",
					},
				},
				required = {},
			},
			run = function(args)
				local button = args.button or "left"
				local action = args.action or "click"
				if button ~= "left" and button ~= "right" and button ~= "middle" then return H.fail("unknown mouse button") end
				if action ~= "click" and action ~= "down" and action ~= "up" and action ~= "move" then return H.fail("unknown mouse action") end
				local x, y = getMousePos(args.x, args.y)

				local vim = getVim()
				local vu = getVu()
				local ok = false

				local btnIndex = 0
				if button == "right" then btnIndex = 1 end
				if button == "middle" then btnIndex = 2 end

				if vim then
					local okVim, sent = pcall(function()
						if action == "move" then
							return vim.SendMouseMoveEvent ~= nil and vim:SendMouseMoveEvent(x, y, game) ~= false
						elseif action == "click" then
							if vim:SendMouseButtonEvent(x, y, btnIndex, true, game, 0) == false then return false end
							clock.wait(0.05)
							return vim:SendMouseButtonEvent(x, y, btnIndex, false, game, 0) ~= false
						elseif action == "down" then
							return vim:SendMouseButtonEvent(x, y, btnIndex, true, game, 0) ~= false
						elseif action == "up" then
							return vim:SendMouseButtonEvent(x, y, btnIndex, false, game, 0) ~= false
						end
						return false
					end)
					ok = okVim and sent == true
				end

				if not ok and action == "click" then
					local hasM1 = pcall(function() return mouse1click end)
					local hasM2 = pcall(function() return mouse2click end)
					if button == "left" and hasM1 and type(mouse1click) == "function" then
						local succeeded, sent = pcall(mouse1click); ok = succeeded and sent ~= false
					elseif button == "right" and hasM2 and type(mouse2click) == "function" then
						local succeeded, sent = pcall(mouse2click); ok = succeeded and sent ~= false
					end
				end

				if not ok and vu and action ~= "move" and button ~= "middle" then
					local okVu, sent = pcall(function()
						if vu:CaptureController() == false then return false end
						local pos = Vector2.new(x, y)
						if action == "click" then
							if button == "right" then
								return vu:ClickButton2(pos) ~= false
							else
								return vu:ClickButton1(pos) ~= false
							end
						elseif action == "down" then
							if button == "right" then return vu:Button2Down(pos) ~= false end
							return vu:Button1Down(pos) ~= false
						elseif action == "up" then
							if button == "right" then return vu:Button2Up(pos) ~= false end
							return vu:Button1Up(pos) ~= false
						end
						return false
					end)
					ok = okVu and sent == true
				end

				if not ok then
					return H.fail("no mouse input injection provider available on this host")
				end

				return string.format("Mouse %s %s at (%.0f, %.0f)", button, action, x, y)
			end,
		},
	}
end
