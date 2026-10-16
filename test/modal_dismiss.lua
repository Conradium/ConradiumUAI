-- Synthetic rectangle dispatch exercises dismissal geometry and lifecycle.
-- This does not simulate Roblox's native hit testing or verify host input.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Modal dismissal")
local case, check = suite.case, suite.check
local names = { Dismiss = true, DismissLeft = true, DismissRight = true, DismissBottom = true }

local function fixture(width, height, touch)
	local f = F.ui(width, height)
	f.env.uis.TouchEnabled, f.env.uis.MouseEnabled = touch == true, touch ~= true
	local responsive = f.env.require("ui/responsive")
	responsive.refresh()
	responsive.reduceMotion = true
	return f
end

local function regions(handle)
	local result = {}
	for _, child in ipairs(handle.scrim:GetChildren()) do
		if names[child.Name] and child:IsA("TextButton") then result[#result + 1] = child end
	end
	return result
end

local function rectangle(node)
	local position, size = node.AbsolutePosition, node.AbsoluteSize
	return { x = position.X, y = position.Y, width = size.X, height = size.Y }
end

local function contains(rect, x, y)
	return x >= rect.x and y >= rect.y and x < rect.x + rect.width and y < rect.y + rect.height
end

local function geometry(f, handle, x, y, width, height, cx, cy, cw, ch)
	local U, V = f.h.dt.UDim2, f.h.dt.Vector2
	handle.scrim.Position, handle.scrim.Size = U.fromOffset(x, y), U.fromOffset(width, height)
	handle.card.AnchorPoint = V.new(0, 0)
	handle.card.Position, handle.card.Size = U.fromOffset(cx, cy), U.fromOffset(cw, ch)
	-- The mock computes absolute geometry on read. Publish the signals the engine
	-- would emit after a layout pass, including when a parent alone moves.
	for _, node in ipairs({ handle.scrim, handle.card }) do
		node:GetPropertyChangedSignal("AbsolutePosition"):Fire()
		node:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	end
end

local function excludesCard(handle)
	local card, scrim = rectangle(handle.card), rectangle(handle.scrim)
	local targets = regions(handle)
	check("dismissal uses four outside regions", #targets == 4)
	for _, target in ipairs(targets) do
		local rect = rectangle(target)
		check("dismissal rectangles never have negative dimensions", rect.width >= 0 and rect.height >= 0)
		if target.Active and target.Visible then
			local intersects = rect.x < card.x + card.width and rect.x + rect.width > card.x
				and rect.y < card.y + card.height and rect.y + rect.height > card.y
			check("an active dismissal region excludes the card interior", not intersects)
			check("an active dismissal region stays within its scrim", rect.x >= scrim.x and rect.y >= scrim.y
				and rect.x + rect.width <= scrim.x + scrim.width and rect.y + rect.height <= scrim.y + scrim.height)
		end
	end
end

local function input(f, x, y, kind)
	return { UserInputType = f.h.sandbox.Enum.UserInputType[kind or "MouseButton1"],
		Position = f.h.dt.Vector3.new(x, y, 0) }
end

local function hit(f, handles, x, y, kind)
	local target
	for _, handle in ipairs(handles) do
		for _, candidate in ipairs(regions(handle)) do
			if candidate.Active and candidate.Visible and contains(rectangle(candidate), x, y)
				and (not target or candidate.ZIndex >= target.ZIndex) then target = candidate end
		end
	end
	if target then target.Activated:Fire(input(f, x, y, kind)) end
	return target
end

for _, device in ipairs({
	{ label = "desktop", width = 1000, height = 750, kind = "MouseButton1" },
	{ label = "touch", width = 390, height = 700, kind = "Touch" },
}) do
	case(device.label .. " modal padding is excluded from dismissal", function()
		local f = fixture(device.width, device.height, device.kind == "Touch")
		local overlay = f.env.require("ui/overlay")
		local modal = overlay.modal({ title = "Add a provider" })
		f.h.settle(0.2)
		geometry(f, modal, 0, 0, device.width, device.height, 30, 80, device.width - 60, 400)
		excludesCard(modal)
		check("empty card padding has no dismissal target", hit(f, { modal }, 34, 84, device.kind) == nil and not modal.closed)
		regions(modal)[1].Activated:Fire(input(f, 34, 84, device.kind))
		check("a stale activation inside the card is rejected", not modal.closed)
		check("outside input reaches a dismissal target", hit(f, { modal }, 8, 8, device.kind) ~= nil)
		check("outside input dismisses only that modal", modal.closed and #overlay.open == 0)
		f.healthy(); f.close()
	end)
end

case("moving and resizing the card or its scrim updates exclusion bounds", function()
	local f = fixture(1000, 750)
	local dialog = f.env.require("ui/overlay").dialog({ name = "Settings" })
	f.h.settle(0.2)
	geometry(f, dialog, 0, 0, 1000, 750, 100.25, 150.75, 500.5, 320.5)
	excludesCard(dialog)
	geometry(f, dialog, 47, 31, 700, 520, 210.5, 110.25, 300.25, 240.5)
	excludesCard(dialog)
	check("parent movement leaves the new card interior protected", hit(f, { dialog }, 260, 145) == nil)
	geometry(f, dialog, 47, 31, 700, 520, -35.25, -20.5, 300.5, 240.75)
	excludesCard(dialog)
	check("a partly offscreen card remains protected", hit(f, { dialog }, 55, 40) == nil and not dialog.closed)
	dialog.close()
	f.healthy(); f.close()
end)

case("unknown geometry cannot install a full-screen dismiss target", function()
	local f = fixture(390, 700, true)
	local modal = f.env.require("ui/overlay").modal({ title = "Waiting for layout" })
	f.h.settle(0.2)
	for _, size in ipairs({ { 390, 700, 0, 0 }, { 0, 0, 300, 400 } }) do
		geometry(f, modal, 0, 0, size[1], size[2], 30, 60, size[3], size[4])
		for _, region in ipairs(regions(modal)) do
			check("zero geometry disables every dismissal region", not region.Active and not region.Visible
				and region.Size.X.Offset == 0 and region.Size.Y.Offset == 0)
			region.Activated:Fire(input(f, 4, 4, "Touch"))
		end
		check("zero geometry rejects stale touch activation", not modal.closed)
	end
	geometry(f, modal, 0, 0, 390, 700, 30, 60, 300, 400)
	excludesCard(modal)
	check("dismissal recovers after the first valid layout", hit(f, { modal }, 4, 4, "Touch") ~= nil and modal.closed)
	f.healthy(); f.close()
end)

case("a dropdown dismisses above its modal without dismissing the form", function()
	local f = fixture(900, 650)
	local overlay = f.env.require("ui/overlay")
	local modal = overlay.modal({ title = "Provider" })
	local anchor = f.env.require("ui/primitives").button(modal.content, { text = "Preset", width = 180 })
	f.h.settle(0.2)
	geometry(f, modal, 0, 0, 900, 650, 180, 100, 500, 400)
	local menu = overlay.menu({ target = anchor.instance, options = { { label = "Custom endpoint", value = "custom" } } })
	geometry(f, menu, 0, 0, 900, 650, 200, 150, 160, 100)
	excludesCard(menu)
	regions(modal)[1].Activated:Fire(input(f, 8, 8))
	check("a covered modal ignores stale dismissal", not modal.closed and not menu.closed)
	check("menu content has no outside target", hit(f, { modal, menu }, 220, 175) == nil)
	local target = hit(f, { modal, menu }, 500, 300)
	check("a click inside the form but outside the menu dismisses the menu", target ~= nil and menu.closed)
	check("the provider form stays open", not modal.closed and #overlay.open == 1 and overlay.open[1] == modal)
	modal.close()
	f.healthy(); f.close()
end)

case("close and external destruction release dismissal listeners", function()
	for _, kind in ipairs({ "modal", "dialog", "menu" }) do
		for _, destroy in ipairs({ false, true }) do
			local f = fixture(900, 650)
			local overlay = f.env.require("ui/overlay")
			local anchor = f.env.require("ui/primitives").button(f.host, { text = "Open", width = 120 })
			local handle = kind == "menu" and overlay.menu({ target = anchor.instance, options = { { label = "Choice", value = "choice" } } })
				or overlay[kind]({ title = "Cleanup" })
			local targets, signals = regions(handle), {}
			for _, node in ipairs({ handle.scrim, handle.card }) do
				for _, property in ipairs({ "AbsolutePosition", "AbsoluteSize" }) do
					signals[#signals + 1] = node:GetPropertyChangedSignal(property)
				end
			end
			if destroy then handle.scrim:Destroy() else handle.close() end
			for _, signal in ipairs(signals) do check(kind .. " releases geometry subscriptions", signal:Count() == 0) end
			for _, target in ipairs(targets) do
				check(kind .. " releases activation subscriptions", target.Activated:Count() == 0 and not target.Active)
			end
			check(kind .. " leaves the overlay stack", handle.closed and #overlay.open == 0)
			f.healthy(); f.close()
		end
	end
end)

suite.finish()
