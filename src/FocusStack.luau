--!strict

local InputContext = require(script.Parent.InputContext)
local FocusGroup = require(script.Parent.FocusGroup)
local SelectionTarget = require(script.Parent.SelectionTarget)

export type Options = {
	initialFocus: GuiObject?,
	autoFocus: boolean?,
	restoreFocus: boolean?,
	onFocusResult: FocusGroup.ResultCallback?,
}
export type Entry = {
	focus: (GuiObject?) -> (GuiObject?, string?),
	requestFocus: (GuiObject?, FocusGroup.ResultCallback?) -> (),
	isTop: () -> boolean,
	close: () -> (),
}
export type Stack = { push: (GuiObject, Options?) -> Entry, getTop: () -> GuiObject?, destroy: () -> () }
type Record = { root: GuiObject, anchor: GuiObject?, binding: FocusGroup.Binding?, closed: boolean, restore: boolean }

local FocusStack = {}

local contains = SelectionTarget.contains
local selectable = SelectionTarget.selectable

function FocusStack.create(context: InputContext.Context, onRelease: () -> ()): Stack
	local entries: { Record } = {}
	local roots: { [GuiObject]: boolean } = {}
	local destroyed = false
	local gui = context.guiService
	local stack = {}
	local function remove(entry: Record)
		local index = table.find(entries, entry)
		if not index then
			return
		end
		local wasTop = index == #entries
		entry.closed = true
		roots[entry.root] = nil
		table.remove(entries, index)
		-- A later layer must not restore into a layer closed underneath it.
		for _, later in entries do
			if contains(entry.root, later.anchor) then
				later.anchor = entry.anchor
			end
		end
		local target = entry.anchor
		entry.anchor = nil
		if
			not wasTop
			or not entry.restore
			or not context.windowActive
			or not contains(entry.root, gui.SelectedObject)
		then
			return
		end
		local active = entries[#entries]
		if target and selectable(target) and (not active or contains(active.root, target)) then
			-- Selection may have been moved elsewhere by a game or another UI.
			-- Only replace selection still inside the layer that just closed.
			pcall(function()
				gui.SelectedObject = target
			end)
		end
	end
	function stack.getTop(): GuiObject?
		local top = entries[#entries]
		return if top then top.root else nil
	end
	function stack.push(root: GuiObject, options: Options?): Entry
		assert(not destroyed, "Focus stack has been destroyed")
		assert(not roots[root], "This selection layer is already in the focus stack")
		local defaults: Options = options or {}
		local settings = table.clone(defaults)
		local entry: Record = {
			root = root,
			anchor = if contains(root, gui.SelectedObject) then nil else gui.SelectedObject,
			closed = false,
			restore = settings.restoreFocus ~= false,
		}
		roots[root] = true
		table.insert(entries, entry)
		local controller = {}
		local pending = false
		local target: GuiObject? = nil
		local callback: FocusGroup.ResultCallback? = nil
		function controller.isTop(): boolean
			return not entry.closed and entries[#entries] == entry
		end
		function controller.focus(selected: GuiObject?): (GuiObject?, string?)
			if entry.closed then
				return nil, "focus-layer-closed"
			end
			if entries[#entries] ~= entry then
				return nil, "focus-layer-not-top"
			end
			local binding = entry.binding
			if not binding then
				return nil, "focus-layer-initializing"
			end
			local focused, failure = binding.focus(selected)
			if not controller.isTop() then
				return nil, "focus-layer-changed"
			end
			return focused, failure
		end
		function controller.requestFocus(selected: GuiObject?, onResult: FocusGroup.ResultCallback?)
			assert(not entry.closed, "Focus layer has been closed")
			target, callback = selected, onResult
			if pending then
				return
			end
			pending = true
			task.defer(function()
				pending = false
				local requested, result = target, callback
				target, callback = nil, nil
				if entry.closed then
					return
				end
				local focused, failure = controller.focus(requested)
				if not entry.closed and result then
					result(focused, failure)
				end
			end)
		end
		function controller.close()
			if entry.closed then
				return
			end
			target, callback = nil, nil
			if entry.binding then
				entry.binding.destroy()
			else
				remove(entry)
			end
		end
		local groupOptions: FocusGroup.Options = { contained = true, restoreFocus = false }
		local ok, binding = pcall(FocusGroup.bind, root, context, groupOptions, function()
			target, callback = nil, nil
			remove(entry)
		end)
		if not ok then
			remove(entry)
			error(binding, 0)
		end
		entry.binding = binding
		if destroyed or entry.closed then
			binding.destroy()
			error("Focus stack or layer was destroyed during setup", 0)
		end
		if settings.autoFocus ~= false then
			controller.requestFocus(settings.initialFocus, settings.onFocusResult)
		end
		return controller
	end
	function stack.destroy()
		if destroyed then
			return
		end
		destroyed = true
		local failures: { string } = {}
		local previous = table.clone(entries)
		for index = #previous, 1, -1 do
			local entry = previous[index]
			if entry.binding then
				local ok, failure = pcall(entry.binding.destroy)
				if not ok then
					table.insert(failures, tostring(failure))
				end
			else
				remove(entry)
			end
		end
		onRelease()
		if #failures > 0 then
			error(table.concat(failures, "\n"), 0)
		end
	end
	return stack
end

return FocusStack
