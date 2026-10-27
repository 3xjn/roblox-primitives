--!strict

local InputContext = require(script.Parent.InputContext)
local Presentation = require(script.Parent.Presentation)
local SelectionTarget = require(script.Parent.SelectionTarget)

export type ResultCallback = (GuiObject?, string?) -> ()
export type Options = { contained: boolean?, restoreFocus: boolean? }
export type Binding = {
	setContained: (boolean) -> (),
	focus: (GuiObject?) -> (GuiObject?, string?),
	requestFocus: (GuiObject?, ResultCallback?) -> (),
	restore: () -> (boolean, string?),
	getFocusWithin: () -> boolean,
	destroy: () -> (),
}

local FocusGroup = {}
local owners: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" })

local contains = SelectionTarget.contains
local selectable = SelectionTarget.selectable

function FocusGroup.bind(
	root: GuiObject,
	context: InputContext.Context,
	options: Options?,
	onRelease: () -> ()
): Binding
	assert(not owners[root], "This native selection group already has a behavior owner")
	local defaults: Options = options or {}
	local settings = table.clone(defaults)
	local gui = context.guiService
	local original = {
		group = root.SelectionGroup,
		up = root.SelectionBehaviorUp,
		down = root.SelectionBehaviorDown,
		left = root.SelectionBehaviorLeft,
		right = root.SelectionBehaviorRight,
	}
	local written = table.clone(original)
	local destroyed = false
	local previous: GuiObject? = nil
	local destroying: RBXScriptConnection? = nil
	local pending = false
	local pendingTarget: GuiObject? = nil
	local pendingResult: ResultCallback? = nil
	owners[root] = true
	local controller = {}
	function controller.setContained(contained: boolean)
		assert(not destroyed, "Focus group has been destroyed")
		local behavior = if contained then Enum.SelectionBehavior.Stop else Enum.SelectionBehavior.Escape
		written.group = true
		root.SelectionGroup = true
		if destroyed then
			return
		end
		written.up = behavior
		root.SelectionBehaviorUp = behavior
		if destroyed then
			return
		end
		written.down = behavior
		root.SelectionBehaviorDown = behavior
		if destroyed then
			return
		end
		written.left = behavior
		root.SelectionBehaviorLeft = behavior
		if destroyed then
			return
		end
		written.right = behavior
		root.SelectionBehaviorRight = behavior
	end
	function controller.focus(target: GuiObject?): (GuiObject?, string?)
		if destroyed then
			return nil, "focus-group-destroyed"
		end
		if not context.windowActive or not Presentation.isPresented(root) then
			return nil, "focus-group-not-presented"
		end
		if target then
			if not contains(root, target) then
				return nil, "focus-target-outside-group"
			end
			if not selectable(target) then
				return nil, "focus-target-not-selectable"
			end
		elseif not root:FindFirstAncestorWhichIsA("PlayerGui") then
			return nil, "native-select-requires-player-gui-or-explicit-target"
		end
		local before = gui.SelectedObject
		local oldAnchor = previous
		if not contains(root, before) then
			previous = before
		end
		local ok, failure = pcall(function()
			if target then
				gui.SelectedObject = target
			else
				gui:Select(root)
			end
		end)
		if destroyed then
			return nil, "focus-group-destroyed"
		end
		local selected = gui.SelectedObject
		if not selected or not contains(root, selected) then
			previous = oldAnchor
			if not ok then
				return nil, `native-focus:{tostring(failure)}`
			end
			return nil, "native-selection-unavailable"
		end
		if not ok then
			return nil, `native-focus:{tostring(failure)}`
		end
		if not selectable(selected) then
			return nil, "native-selection-not-interactable"
		end
		return selected, nil
	end
	function controller.requestFocus(target: GuiObject?, onResult: ResultCallback?)
		assert(not destroyed, "Focus group has been destroyed")
		pendingTarget, pendingResult = target, onResult
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			local requested, callback = pendingTarget, pendingResult
			pendingTarget, pendingResult = nil, nil
			if destroyed then
				return
			end
			local selected, reason = controller.focus(requested)
			if callback and not destroyed then
				callback(selected, reason)
			end
		end)
	end
	local function restore(): (boolean, string?)
		local target = previous
		if not target then
			return false, "no-previous-selection"
		end
		if not contains(root, gui.SelectedObject) then
			return false, "selection-left-group"
		end
		if contains(root, target) or not selectable(target) then
			return false, "previous-selection-unavailable"
		end
		gui.SelectedObject = target
		if gui.SelectedObject ~= target then
			return false, "native-selection-unavailable"
		end
		previous = nil
		return true, nil
	end
	function controller.restore(): (boolean, string?)
		if destroyed then
			return false, "focus-group-destroyed"
		end
		return restore()
	end
	function controller.getFocusWithin(): boolean
		local selected = gui.SelectedObject
		return not destroyed
			and context.windowActive
			and selected ~= nil
			and selected.Selectable
			and Presentation.isPresented(selected)
			and contains(root, selected)
	end
	local function release(restoreProperties: boolean)
		if destroyed then
			return
		end
		destroyed = true
		pendingTarget, pendingResult = nil, nil
		if destroying then
			destroying:Disconnect()
			destroying = nil
		end
		local failures: { string } = {}
		if settings.restoreFocus then
			local ok, failure = pcall(restore)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		if restoreProperties then
			local ok, failure = pcall(function()
				if root.SelectionGroup == written.group then
					root.SelectionGroup = original.group
				end
				if root.SelectionBehaviorUp == written.up then
					root.SelectionBehaviorUp = original.up
				end
				if root.SelectionBehaviorDown == written.down then
					root.SelectionBehaviorDown = original.down
				end
				if root.SelectionBehaviorLeft == written.left then
					root.SelectionBehaviorLeft = original.left
				end
				if root.SelectionBehaviorRight == written.right then
					root.SelectionBehaviorRight = original.right
				end
			end)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		previous = nil
		owners[root] = nil
		onRelease()
		if #failures > 0 then
			error(table.concat(failures, "\n"), 0)
		end
	end
	function controller.destroy()
		release(true)
	end
	local ok, failure = pcall(function()
		destroying = root.Destroying:Connect(function()
			release(false)
		end)
		controller.setContained(settings.contained == true)
	end)
	if not ok then
		local clean, cleanupFailure = pcall(release, true)
		if not clean then
			error(`Focus group setup: {tostring(failure)}; cleanup: {tostring(cleanupFailure)}`, 0)
		end
		error(failure, 0)
	end
	return controller
end

return FocusGroup
