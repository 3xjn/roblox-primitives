--!strict

local InputContext = require(script.Parent.InputContext)
local Presentation = require(script.Parent.Presentation)
export type State = { hovered: boolean, pressed: boolean, focused: boolean, focusVisible: boolean, disabled: boolean }
export type Options = {
	disabled: boolean?,
	onState: ((State) -> ())?,
	onActivated: ((InputObject, number) -> ())?,
}
export type Binding = {
	setDisabled: (boolean) -> (),
	getState: () -> State?,
	activate: (InputObject, number?) -> (boolean, string?),
	destroy: () -> (),
}

local Button = {}
-- One property owner per native button, even across independent scopes.
local owners: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" })
local activationBindings: { [GuiButton]: Binding } = setmetatable({}, { __mode = "kv" })

-- Dispatch through an existing owner; never adopt a control or synthesize an
-- engine event. Labels and other explicit delegates share the native gates.
function Button.activate(button: GuiButton, input: InputObject, count: number?): (boolean, string?)
	local binding = activationBindings[button]
	if not binding then
		return false, "button-unbound"
	end
	return binding.activate(input, count)
end

local function same(a: State?, b: State): boolean
	return a ~= nil
		and a.hovered == b.hovered
		and a.pressed == b.pressed
		and a.focused == b.focused
		and a.focusVisible == b.focusVisible
		and a.disabled == b.disabled
end

function Button.bind(button: GuiButton, context: InputContext.Context, options: Options?, onRelease: () -> ()): Binding
	assert(not owners[button], "This native button already has a behavior owner")
	local defaults: Options = options or {}
	local settings = table.clone(defaults)
	local disabled = settings.disabled == true
	local connections: { RBXScriptConnection } = {}
	local visibility: { RBXScriptConnection } = {}
	local unsubscribe: (() -> ())? = nil
	local destroyed = false
	local writing = false
	local hovered = button.GuiState == Enum.GuiState.Hover
	local state: State? = nil
	local announced: State? = nil
	local notificationPending = false
	local original = {
		active = button.Active,
		selectable = button.Selectable,
		interactable = button.Interactable,
		autoColor = button.AutoButtonColor,
	}
	local written = table.clone(original)
	owners[button] = true
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

	local function refresh()
		if destroyed or writing then
			return
		end
		local visible = Presentation.isPresented(button) and context.windowActive
		local blocked = disabled
			or not button.Active
			or not button.Interactable
			or button.GuiState == Enum.GuiState.NonInteractable
		local focused = visible and button.Selectable and context.guiService.SelectedObject == button
		local nextState: State = {
			hovered = visible and not blocked and hovered,
			pressed = visible and not blocked and button.GuiState == Enum.GuiState.Press,
			focused = focused,
			focusVisible = focused and context.keyboardVisible,
			disabled = blocked,
		}
		if not same(state, nextState) then
			state = nextState
			notify()
		end
	end
	local function release(restore: boolean)
		if destroyed then
			return
		end
		destroyed = true
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
		local clean, failure = pcall(function()
			if restore then
				-- Do not overwrite a property which another owner changed meanwhile.
				if button.Active == written.active then
					button.Active = original.active
				end
				if button.Selectable == written.selectable then
					button.Selectable = original.selectable
				end
				if button.Interactable == written.interactable then
					button.Interactable = original.interactable
				end
				if button.AutoButtonColor == written.autoColor then
					button.AutoButtonColor = original.autoColor
				end
			end
		end)
		owners[button] = nil
		activationBindings[button] = nil
		settings.onActivated, settings.onState = nil, nil
		onRelease()
		if not clean then
			error(failure, 0)
		end
	end
	local function applyDisabled()
		writing = true
		local blocked = disabled or button:GetAttribute("CssPointerBlocked") == true
		written.active = not blocked
		button.Active = written.active
		if destroyed then
			writing = false
			return
		end
		written.selectable = not blocked
		button.Selectable = written.selectable
		if destroyed then
			writing = false
			return
		end
		written.interactable = not blocked
		button.Interactable = written.interactable
		if destroyed then
			writing = false
			return
		end
		written.autoColor = false
		button.AutoButtonColor = written.autoColor
		if destroyed then
			writing = false
			return
		end
		if blocked and context.guiService.SelectedObject == button then
			context.guiService.SelectedObject = nil
		end
		writing = false
		refresh()
	end
	local function observeVisibility()
		for _, connection in visibility do
			connection:Disconnect()
		end
		table.clear(visibility)
		if destroyed then
			return
		end
		local ancestor: Instance? = button
		while ancestor do
			if ancestor:IsA("GuiObject") then
				table.insert(visibility, ancestor:GetPropertyChangedSignal("Visible"):Connect(refresh))
			elseif ancestor:IsA("LayerCollector") then
				table.insert(visibility, ancestor:GetPropertyChangedSignal("Enabled"):Connect(refresh))
			end
			ancestor = ancestor.Parent
		end
		refresh()
	end
	local controller = {}
	function controller.setDisabled(value: boolean)
		assert(not destroyed, "Button binding has been destroyed")
		if value == disabled then
			return
		end
		disabled = value
		applyDisabled()
	end
	function controller.getState(): State?
		return if state and not destroyed then table.clone(state) else nil
	end
	function controller.activate(input: InputObject, count: number?): (boolean, string?)
		if destroyed then
			return false, "button-destroyed"
		end
		if input == nil then
			return false, "button-activation-input-required"
		end
		if
			disabled
			or not button.Active
			or not button.Interactable
			or button.GuiState == Enum.GuiState.NonInteractable
		then
			return false, "button-disabled"
		end
		if not context.windowActive then
			return false, "button-window-inactive"
		end
		if not Presentation.isPresented(button, true) then
			return false, "button-not-presented"
		end
		if settings.onActivated then
			settings.onActivated(input, count or 1)
		end
		return true, nil
	end
	function controller.destroy()
		release(true)
	end

	local ok, failure = pcall(function()
		table.insert(
			connections,
			button.Destroying:Connect(function()
				release(false)
			end)
		)
		table.insert(connections, button.AncestryChanged:Connect(observeVisibility))
		table.insert(connections, button:GetAttributeChangedSignal("CssPointerBlocked"):Connect(applyDisabled))
		table.insert(
			connections,
			button.MouseEnter:Connect(function()
				hovered = true
				refresh()
			end)
		)
		table.insert(
			connections,
			button.MouseLeave:Connect(function()
				hovered = false
				refresh()
			end)
		)
		table.insert(
			connections,
			button:GetPropertyChangedSignal("GuiState"):Connect(function()
				if button.GuiState == Enum.GuiState.Hover then
					hovered = true
				elseif button.GuiState == Enum.GuiState.Idle or button.GuiState == Enum.GuiState.NonInteractable then
					hovered = false
				end
				refresh()
			end)
		)
		for _, property in { "Active", "Selectable", "Interactable" } do
			table.insert(connections, button:GetPropertyChangedSignal(property):Connect(refresh))
		end
		table.insert(connections, button.SelectionGained:Connect(refresh))
		table.insert(connections, button.SelectionLost:Connect(refresh))
		table.insert(
			connections,
			button.Activated:Connect(function(input, count)
				controller.activate(input, count)
			end)
		)
		unsubscribe = context:subscribe(refresh)
		observeVisibility()
		if not destroyed then
			applyDisabled()
			if not destroyed then
				activationBindings[button] = controller
			end
		end
	end)
	if not ok then
		local clean, cleanupFailure = pcall(release, true)
		if not clean then
			error(`Button setup: {tostring(failure)}; cleanup: {tostring(cleanupFailure)}`, 0)
		end
		error(failure, 0)
	end
	return controller
end

return Button
