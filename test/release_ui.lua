-- Focused v3 UI lifecycle and local asset regressions. No native rendering claims.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, luau = require("env"), require("luau")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1 end
local function loadSource(id, h, dependencies, extra)
	local file = assert(io.open("src/" .. id .. ".lua", "rb"))
	local source = file:read("*a"); file:close()
	local chunk = assert(luau.load(source, id)); setfenv(chunk, h.sandbox)
	local env = extra or {}
	function env.require(name) return dependencies[name] or {} end
	return chunk()(env)
end

do
	local h, buttons = envMock.new(), {}
	local overlay = loadSource("ui/overlay", h, {
		["ui/theme"] = { size = { modal = 380 } },
		["ui/primitives"] = { button = function(_, props) buttons[#buttons + 1] = props end },
		["ui/app"] = {},
	})
	local confirmed, cancelled = 0, 0
	local function confirm() confirmed = confirmed + 1 end
	check("unavailable overlay returns no dialog", overlay.confirm({ onConfirm = confirm,
		onCancel = function() cancelled = cancelled + 1 end }) == nil)
	check("unavailable overlay cancels without running the action", confirmed == 0 and cancelled == 1)
	check("unavailable overlay works without cancellation handler", overlay.confirm({ onConfirm = confirm }) == nil and confirmed == 0)
	check("cancellation errors stay contained", pcall(function()
		overlay.confirm({ onConfirm = confirm, onCancel = function() error("cancel failure") end })
	end) and confirmed == 0)
	local closed
	overlay.modal = function()
		return { footer = {}, close = function(value) closed = value end }
	end
	check("available confirmation still creates two actions", overlay.confirm({ onConfirm = confirm }) ~= nil and #buttons == 2)
	check("opening the dialog does not execute the action", confirmed == 0)
	buttons[2].onClick()
	check("explicit confirmation closes before executing", closed == true and confirmed == 1)
end

do
	local h, listener, modals, answers = envMock.new(), nil, {}, {}
	local ask = loadSource("ui/panels/ask", h, {
		["runtime/util"] = { trim = function(value) return tostring(value):match("^%s*(.-)%s*$") end },
		["runtime/dispose"] = { add = function(value) return value end },
		["agent/session"] = { anyEvent = { connect = function(_, fn) listener = fn; return function() end end } },
		["ui/theme"] = { size = { modalWide = 480 } },
		["ui/primitives"] = { button = function() end, field = function() return { get = function() return "" end } end },
		["ui/overlay"] = { modal = function(props)
			local modal = { content = {}, footer = {}, close = function() props.onClose() end }
			modals[#modals + 1] = modal; return modal
		end },
	})
	ask.watch()
	local first, second = {}, {}
	for index, session in ipairs({ first, second }) do
		listener(session, { kind = "ask:user", id = tostring(index), question = "Question",
			resolve = function(value) answers[index] = value end })
	end
	check("questions from separate sessions share one visible dialog", #modals == 1 and #ask.queue == 1)
	check("sweeping one session presents the retained question", ask.sweep(first) == 1 and #modals == 2 and #ask.queue == 0)
	check("sweep dismisses only its own session", answers[1] == "" and answers[2] == nil)
	check("the retained question can still be answered", ask.answer("2", "continue") and answers[2] == "continue")
end

local function iconFixture()
	local h = envMock.new()
	local files = { ["icons/x.png"] = "old-x", ["icons/minus.png"] = "old-minus", ["icons/send.png"] = "new-send" }
	local counts = { reads = 0, writes = 0, loads = 0, decodes = 0, tweens = 0 }
	local delayed, intervals = {}, {}
	local refused, silent = false, false
	local version = 1
	local dependencies = {
		["ui/theme"] = { color = { textSecondary = h.sandbox.Color3.fromRGB(180, 180, 180),
			accent = h.sandbox.Color3.fromRGB(217, 119, 87), canvas = h.sandbox.Color3.fromRGB(30, 30, 28) },
			radius = { sm = 6 }, stroke = { hair = 1 } },
		["ui/assets"] = { VERSION = 2, icons = { x = "new-x", minus = "new-minus", send = "new-send" },
			decode = function(bytes) counts.decodes = counts.decodes + 1; return bytes end },
		["runtime/config"] = { get = function() return version end, set = function(_, value) version = value end },
		["runtime/fsx"] = {
			resolve = function(path) return "UAI/" .. path end,
			exists = function(path) return files[path] ~= nil end,
			read = function(path) counts.reads = counts.reads + 1; return files[path] end,
			write = function(path, bytes)
				counts.writes = counts.writes + 1
				if refused then return false end
				if not silent then files[path] = bytes end
				return true
			end,
		},
		["runtime/caps"] = { fs = true, fn = { customasset = function(path)
			counts.loads = counts.loads + 1; return "rbxasset://" .. path
		end } },
		["ui/responsive"] = { reduceMotion = false },
		["runtime/clock"] = {
			delay = function(_, fn) delayed[#delayed + 1] = fn end,
			interval = function(_, fn)
				local entry = { callback = fn, stopped = false }; intervals[#intervals + 1] = entry
				return function() entry.stopped = true end
			end,
		},
	}
	local icons = loadSource("ui/icons", h, dependencies, { tween = { Create = function()
		counts.tweens = counts.tweens + 1
		return { Play = function() end, Cancel = function() end }
	end } })
	return h, icons, files, counts, function(reject, drop) refused, silent = reject, drop end, delayed, intervals
end

do
	local h, icons, files, counts = iconFixture()
	local parent = h.sandbox.Instance.new("Frame")
	icons.close(parent, 16); icons.minus(parent, 16)
	check("every older requested icon upgrades independently", files["icons/x.png"] == "new-x" and files["icons/minus.png"] == "new-minus")
	check("each changed icon is written and loaded once", counts.writes == 2 and counts.loads == 2)
	icons.send(parent, 16)
	check("matching embedded bytes avoid a write", counts.writes == 2 and counts.loads == 3)
	local reads, decodes = counts.reads, counts.decodes
	icons.enter(parent, 16); icons.send(parent, 16); icons.close(parent, 16)
	check("aliases and repeat draws reuse verified assets", counts.reads == reads and counts.decodes == decodes and counts.loads == 3)
end

do
	local h, icons, files, counts, setFailure = iconFixture()
	local parent = h.sandbox.Instance.new("Frame")
	setFailure(true, false)
	local refused = icons.close(parent, 16)
	check("refused writes use frame fallback", counts.loads == 0 and refused:FindFirstChild("Image") == nil)
	setFailure(false, true)
	local silent = icons.close(parent, 16)
	check("silent writes cannot load stale bytes", files["icons/x.png"] == "old-x" and counts.loads == 0 and silent:FindFirstChild("Image") == nil)
	setFailure(false, false)
	local recovered = icons.close(parent, 16)
	check("failed extraction remains retryable", counts.loads == 1 and recovered:FindFirstChild("Image") ~= nil)
end

do
	local h, icons, _, counts, _, delayed, intervals = iconFixture()
	local frame, handle = icons.mascot(h.sandbox.Instance.new("Frame"), 20)
	local eyes = {}
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Frame") and child.ZIndex == 5 then eyes[#eyes + 1] = child end
	end
	check("mascot has two eyes for the blink check", #eyes == 2)
	intervals[1].callback()
	check("blink schedules its opening", #delayed == 1)
	handle.stop()
	local restingSize = eyes[1].Size
	delayed[1]()
	check("stopped animation ignores pending blink callbacks", intervals[1].stopped and rawequal(restingSize, eyes[1].Size) and #delayed == 1)
	handle.setBusy(true); intervals[2].callback()
	local finalSize = eyes[1].Size
	frame:Destroy(); delayed[2]()
	local tweens = counts.tweens
	handle.setBusy(false); handle.stop()
	check("destroyed animation ignores delayed and handle work", intervals[2].stopped and rawequal(finalSize, eyes[1].Size) and counts.tweens == tweens)
end

print("release_ui: " .. passed .. " checks passed")
