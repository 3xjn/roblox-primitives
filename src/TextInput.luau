--!strict

local InputContext = require(script.Parent.InputContext)
local Presentation = require(script.Parent.Presentation)

export type State = {
	text: string,
	focused: boolean,
	selected: boolean,
	focusVisible: boolean,
	disabled: boolean,
	readOnly: boolean,
}
export type Options = {
	disabled: boolean?,
	readOnly: boolean?,
	onState: ((State) -> ())?,
	onTextChanged: ((string) -> ())?,
	onFocusLost: ((string, boolean, InputObject) -> ())?,
	onReturnPressedFromOnScreenKeyboard: ((string) -> ())?,
}
export type Binding = {
	setDisabled: (boolean) -> (),
	setReadOnly: (boolean) -> (),
	getState: () -> State?,
	focus: () -> (boolean, string?),
	blur: () -> (),
	destroy: () -> (),
}

local TextInput = {}
local owners: { [TextBox]: boolean } = setmetatable({}, { __mode = "k" })
local focusBindings: { [TextBox]: Binding } = setmetatable({}, { __mode = "kv" })

function TextInput.focus(box: TextBox): (boolean, string?)
	local binding = focusBindings[box]
	if not binding then
		return false, "text-input-unbound"
	end
	return binding.focus()
end

local function same(a: State?, b: State): boolean
	return a ~= nil
		and a.text == b.text
		and a.focused == b.focused
		and a.selected == b.selected
		and a.focusVisible == b.focusVisible
		and a.disabled == b.disabled
		and a.readOnly == b.readOnly
end

function TextInput.bind(box: TextBox, context: InputContext.Context, options: Options?, onRelease: () -> ()): Binding
	assert(not owners[box], "This native text input already has a behavior owner")
	local defaults: Options = options or {}
	local settings = table.clone(defaults)
	local disabled, readOnly = settings.disabled == true, settings.readOnly == true
	local destroyed, writing, releasingFocus, notificationPending = false, false, false, false
	local connections: { RBXScriptConnection } = {}
	local visibility: { RBXScriptConnection } = {}
	local unsubscribe: (() -> ())? = nil
	local state: State? = nil
	local registered: Binding? = nil
	local announced: State? = nil
	local original = {
		active = box.Active,
		selectable = box.Selectable,
		interactable = box.Interactable,
		editable = box.TextEditable,
		clearOnFocus = box.ClearTextOnFocus,
	}
	local written = table.clone(original)
	owners[box] = true

	local function notify()
		if notificationPending or not settings.onState then
			return
		end
		notificationPending = true
		task.defer(function()
			notificationPending = false
			local snapshot = state
			if destroyed or not snapshot or same(announced, snapshot) then
				return
			end
			announced = table.clone(snapshot)
			if settings.onState then
				settings.onState(table.clone(snapshot))
			end
		end)
	end
	local function blocked(): boolean
		return disabled or not box.Active or not box.Interactable or box.GuiState == Enum.GuiState.NonInteractable
	end
	local function releaseFocus()
		if destroyed or releasingFocus or not box:IsFocused() then
			return
		end
		releasingFocus = true
		local ok, failure = pcall(function()
			box:ReleaseFocus(false)
		end)
		releasingFocus = false
		if not ok then
			error(failure, 0)
		end
	end
	local function refresh()
		if destroyed or writing then
			return
		end
		local presented = Presentation.isPresented(box)
		local isBlocked = blocked()
		local available = presented and context.windowActive and not isBlocked
		local focused = available and box:IsFocused()
		local selected = available and box.Selectable and context.guiService.SelectedObject == box
		local nextState: State = {
			text = box.Text,
			focused = focused,
			selected = selected,
			-- Text entry expects keyboard input even after a pointer focus.
			focusVisible = focused or selected and context.keyboardVisible,
			disabled = isBlocked,
			readOnly = not box.TextEditable,
		}
		if not same(state, nextState) then
			state = nextState
			notify()
		end
	end
	local function enforceFocus()
		if destroyed or writing or releasingFocus then
			return
		end
		if blocked() or not Presentation.isPresented(box) then
			releaseFocus()
		end
		refresh()
	end
	local function release(restore: boolean)
		if destroyed then
			return
		end
		destroyed = true
		if focusBindings[box] == registered then
			focusBindings[box] = nil
		end
		registered = nil
		if unsubscribe then
			unsubscribe()
			unsubscribe = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, connection in visibility do
			connection:Disconnect()
		end
		table.clear(connections)
		table.clear(visibility)
		local ok, failure = pcall(function()
			if restore then
				if box.Active == written.active then
					box.Active = original.active
				end
				if box.Selectable == written.selectable then
					box.Selectable = original.selectable
				end
				if box.Interactable == written.interactable then
					box.Interactable = original.interactable
				end
				if box.TextEditable == written.editable then
					box.TextEditable = original.editable
				end
				if box.ClearTextOnFocus == written.clearOnFocus then
					box.ClearTextOnFocus = original.clearOnFocus
				end
			end
		end)
		owners[box] = nil
		onRelease()
		if not ok then
			error(failure, 0)
		end
	end
	local function applyFlags()
		writing = true
		-- Set the last-write marker before each native write for reentrant teardown.
		written.clearOnFocus = false
		box.ClearTextOnFocus = written.clearOnFocus
		if destroyed then
			writing = false
			return
		end
		written.editable = not disabled and not readOnly
		box.TextEditable = written.editable
		if destroyed then
			writing = false
			return
		end
		written.active = not disabled
		box.Active = written.active
		if destroyed then
			writing = false
			return
		end
		written.selectable = not disabled
		box.Selectable = written.selectable
		if destroyed then
			writing = false
			return
		end
		written.interactable = not disabled
		box.Interactable = written.interactable
		if destroyed then
			writing = false
			return
		end
		if disabled and context.guiService.SelectedObject == box then
			context.guiService.SelectedObject = nil
		end
		writing = false
		enforceFocus()
	end
	local function observeVisibility()
		for _, connection in visibility do
			connection:Disconnect()
		end
		table.clear(visibility)
		if destroyed then
			return
		end
		local ancestor: Instance? = box
		while ancestor do
			if ancestor:IsA("GuiObject") then
				table.insert(visibility, ancestor:GetPropertyChangedSignal("Visible"):Connect(enforceFocus))
			elseif ancestor:IsA("LayerCollector") then
				table.insert(visibility, ancestor:GetPropertyChangedSignal("Enabled"):Connect(enforceFocus))
			end
			ancestor = ancestor.Parent
		end
		enforceFocus()
	end

	local controller = {}
	function controller.setDisabled(value: boolean)
		assert(not destroyed, "Text input binding has been destroyed")
		if disabled ~= value then
			disabled = value
			applyFlags()
		end
	end
	function controller.setReadOnly(value: boolean)
		assert(not destroyed, "Text input binding has been destroyed")
		if readOnly ~= value then
			readOnly = value
			applyFlags()
		end
	end
	function controller.getState(): State?
		return if state and not destroyed then table.clone(state) else nil
	end
	function controller.focus(): (boolean, string?)
		if destroyed then
			return false, "text-input-destroyed"
		end
		if blocked() then
			return false, "text-input-disabled"
		end
		if not context.windowActive or not Presentation.isPresented(box) then
			return false, "text-input-not-presented"
		end
		local ok, failure = pcall(function()
			box:CaptureFocus()
		end)
		if not ok then
			return false, tostring(failure)
		end
		if destroyed then
			return false, "text-input-destroyed"
		end
		refresh()
		if destroyed then
			return false, "text-input-destroyed"
		end
		local focused = box:IsFocused()
		return focused, if focused then nil else "native-text-focus-not-acquired"
	end
	function controller.blur()
		releaseFocus()
		refresh()
	end
	function controller.destroy()
		release(true)
	end

	local ok, failure = pcall(function()
		table.insert(
			connections,
			box.Destroying:Connect(function()
				release(false)
			end)
		)
		table.insert(connections, box.AncestryChanged:Connect(observeVisibility))
		for _, property in { "Active", "Interactable", "Selectable", "TextEditable", "GuiState" } do
			table.insert(connections, box:GetPropertyChangedSignal(property):Connect(enforceFocus))
		end
		table.insert(
			connections,
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if destroyed then
					return
				end
				local value = box.Text
				refresh()
				if not destroyed and settings.onTextChanged then
					settings.onTextChanged(value)
				end
			end)
		)
		table.insert(connections, box.Focused:Connect(enforceFocus))
		table.insert(
			connections,
			box.FocusLost:Connect(function(enterPressed, input)
				if destroyed then
					return
				end
				local value = box.Text
				refresh()
				if not destroyed and settings.onFocusLost then
					settings.onFocusLost(value, enterPressed, input)
				end
			end)
		)
		table.insert(
			connections,
			box.ReturnPressedFromOnScreenKeyboard:Connect(function()
				if
					not destroyed
					and not blocked()
					and context.windowActive
					and Presentation.isPresented(box)
					and settings.onReturnPressedFromOnScreenKeyboard
				then
					settings.onReturnPressedFromOnScreenKeyboard(box.Text)
				end
			end)
		)
		table.insert(connections, box.SelectionGained:Connect(refresh))
		table.insert(connections, box.SelectionLost:Connect(refresh))
		unsubscribe = context:subscribe(refresh)
		if not destroyed then
			applyFlags()
		end
		if not destroyed then
			observeVisibility()
		end
	end)
	if not ok then
		local clean, cleanupFailure = pcall(release, true)
		if not clean then
			error(`Text input setup: {tostring(failure)}; cleanup: {tostring(cleanupFailure)}`, 0)
		end
		error(failure, 0)
	end
	if not destroyed then
		registered = controller
		focusBindings[box] = controller
	end
	return controller
end

return TextInput
