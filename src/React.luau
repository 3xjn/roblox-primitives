--!strict

local Button = require(script.Parent.Button)
local Toggle = require(script.Parent.Toggle)
local TextInput = require(script.Parent.TextInput)
local Field = require(script.Parent.Field)

export type React = {
	useRef: <T>(T) -> { current: T },
	useState: <T>(T) -> (T, (T | ((T) -> T)) -> ()),
	useLayoutEffect: (() -> (() -> ())?, { unknown }?) -> (),
}
type Scope = {
	bindButton: (GuiButton, Button.Options?) -> Button.Binding,
	bindToggle: (GuiButton, Toggle.Options?) -> Toggle.Binding,
	bindTextInput: (TextBox, TextInput.Options?) -> TextInput.Binding,
	destroy: () -> (),
}
export type ButtonProps = { disabled: boolean?, onActivated: ((InputObject, number) -> ())? }
export type ToggleProps = {
	value: boolean?,
	defaultValue: boolean?,
	disabled: boolean?,
	readOnly: boolean?,
	onValueChange: ((boolean, InputObject, number) -> ())?,
}
export type TextInputProps = {
	value: string?,
	defaultValue: string?,
	disabled: boolean?,
	readOnly: boolean?,
	flushSync: ((() -> ()) -> ())?,
	onValueChange: ((string) -> ())?,
	onFocusLost: ((string, boolean, InputObject) -> ())?,
}

local ReactBindings = {}

local function sameInteraction(a: Button.State, b: Button.State): boolean
	return a.hovered == b.hovered
		and a.pressed == b.pressed
		and a.focused == b.focused
		and a.focusVisible == b.focusVisible
		and a.disabled == b.disabled
end

-- React and scope construction are injected; this module imports no CSS host,
-- renderer, component library or second React instance.
function ReactBindings.create(react: React, createScope: () -> Scope)
	local function useButton(props: ButtonProps): ((GuiObject) -> (() -> ())?, Button.State)
		local latest = react.useRef(props)
		local native = react.useRef(nil :: Button.Binding?)
		local release = react.useRef(nil :: (() -> ())?)
		local state, setState = react.useState({
			hovered = false,
			pressed = false,
			focused = false,
			focusVisible = false,
			disabled = props.disabled == true,
		} :: Button.State)
		local binder = react.useRef(nil :: ((GuiObject) -> (() -> ())?)?)
		if not binder.current then
			binder.current = function(target: GuiObject): (() -> ())?
				assert(target:IsA("GuiButton"), "Button behavior requires a native GuiButton")
				local scope = createScope()
				local settings: Button.Options = {
					disabled = latest.current.disabled,
					onState = function(nextState)
						setState(nextState)
					end,
					onActivated = function(input: InputObject, count: number)
						local current = latest.current
						if not current.disabled and current.onActivated then
							current.onActivated(input, count)
						end
					end,
				}
				local ok, binding = pcall(scope.bindButton, target, settings)
				if not ok then
					scope.destroy()
					error(binding, 0)
				end
				native.current = binding
				local function cleanup()
					if native.current == binding then
						native.current = nil
						release.current = nil
					end
					scope.destroy()
				end
				release.current = cleanup
				return cleanup
			end
		end
		react.useLayoutEffect(function()
			latest.current = props
			if native.current then
				native.current.setDisabled(props.disabled == true)
			end
			return nil
		end)
		react.useLayoutEffect(function()
			return function()
				if release.current then
					release.current()
				end
			end
		end, {})
		return binder.current :: (GuiObject) -> (() -> ())?, state
	end
	local function useToggle(props: ToggleProps): ((GuiObject) -> (() -> ())?, Toggle.State)
		local controlled = react.useRef(props.value ~= nil)
		assert(controlled.current == (props.value ~= nil), "Toggle cannot switch value ownership while mounted")
		local accepted = react.useRef(if controlled.current then props.value == true else props.defaultValue == true)
		local latest = react.useRef(props)
		local native = react.useRef(nil :: Toggle.Binding?)
		local release = react.useRef(nil :: (() -> ())?)
		local state, setState = react.useState({
			value = accepted.current,
			readOnly = props.readOnly == true,
			interaction = {
				hovered = false,
				pressed = false,
				focused = false,
				focusVisible = false,
				disabled = props.disabled == true,
			},
		} :: Toggle.State)
		local binder = react.useRef(nil :: ((GuiObject) -> (() -> ())?)?)
		if not binder.current then
			binder.current = function(target: GuiObject): (() -> ())?
				assert(target:IsA("GuiButton"), "Toggle behavior requires a native GuiButton")
				local scope = createScope()
				local current = latest.current
				local settings: Toggle.Options = {
					value = if controlled.current then current.value == true else nil,
					defaultValue = accepted.current,
					disabled = current.disabled,
					readOnly = current.readOnly,
					onState = function(nextState)
						accepted.current = nextState.value
						local committed = latest.current
						local ownsValue = controlled.current
						local followsProps = nextState.readOnly == (committed.readOnly == true)
							and (not ownsValue or nextState.value == (committed.value == true))
						setState(function(previous)
							-- Controlled value/read-only presentation comes from props.
							-- An echoed value needs no second render; native interaction
							-- changes and uncontrolled accepted values remain observable.
							if
								followsProps
								and (ownsValue or previous.value == nextState.value)
								and sameInteraction(previous.interaction, nextState.interaction)
							then
								return previous
							end
							return nextState
						end)
					end,
					onValueChange = function(nextValue, input, count)
						local committed = latest.current
						if committed.disabled or committed.readOnly then
							return
						end
						if not controlled.current then
							accepted.current = nextValue
						end
						if committed.onValueChange then
							committed.onValueChange(nextValue, input, count)
						end
					end,
				}
				local ok, binding = pcall(scope.bindToggle, target, settings)
				if not ok then
					scope.destroy()
					error(binding, 0)
				end
				native.current = binding
				local function cleanup()
					if native.current == binding then
						native.current = nil
						release.current = nil
					end
					scope.destroy()
				end
				release.current = cleanup
				return cleanup
			end
		end
		react.useLayoutEffect(function()
			latest.current = props
			local binding = native.current
			if binding then
				binding.setDisabled(props.disabled == true)
				binding.setReadOnly(props.readOnly == true)
				if controlled.current then
					binding.setValue(props.value == true)
				end
			end
			return nil
		end)
		react.useLayoutEffect(function()
			return function()
				if release.current then
					release.current()
				end
			end
		end, {})
		return binder.current :: (GuiObject) -> (() -> ())?,
			{
				value = if controlled.current then props.value == true else accepted.current,
				readOnly = props.readOnly == true,
				interaction = state.interaction,
			}
	end
	local function useTextInput(props: TextInputProps): ((GuiObject) -> (() -> ())?, TextInput.State, string)
		local controlled = react.useRef(props.value ~= nil)
		assert(controlled.current == (props.value ~= nil), "Text input cannot switch value ownership while mounted")
		assert(not controlled.current or props.flushSync, "Controlled text input requires its renderer's flushSync")
		local accepted = react.useRef(props.value or props.defaultValue or "")
		local latest = react.useRef(props)
		local native = react.useRef(nil :: TextInput.Binding?)
		local release = react.useRef(nil :: (() -> ())?)
		local state, setState = react.useState({
			text = accepted.current,
			focused = false,
			selected = false,
			focusVisible = false,
			disabled = props.disabled == true,
			readOnly = props.readOnly == true,
		} :: TextInput.State)
		local binder = react.useRef(nil :: ((GuiObject) -> (() -> ())?)?)
		if not binder.current then
			binder.current = function(target: GuiObject): (() -> ())?
				assert(target:IsA("TextBox"), "Text input behavior requires a native TextBox")
				local scope = createScope()
				local settings: TextInput.Options = {
					disabled = latest.current.disabled,
					readOnly = latest.current.readOnly,
					onState = function(nextState)
						accepted.current = nextState.text
						setState(nextState)
					end,
					onTextChanged = function(text)
						accepted.current = text
						local current = latest.current
						if controlled.current and current.value == text then
							return -- Applied controlled props are echoes, not edit requests.
						end
						if current.onValueChange then
							local function notify()
								(current.onValueChange :: (string) -> ())(text)
							end
							if current.flushSync then
								current.flushSync(notify)
							else
								notify()
							end
						end
					end,
					onFocusLost = function(text, enterPressed, input)
						if latest.current.onFocusLost then
							(latest.current.onFocusLost :: (string, boolean, InputObject) -> ())(
								text,
								enterPressed,
								input
							)
						end
					end,
				}
				local ok, binding = pcall(scope.bindTextInput, target, settings)
				if not ok then
					scope.destroy()
					error(binding, 0)
				end
				native.current = binding
				local function cleanup()
					if native.current == binding then
						native.current = nil
						release.current = nil
					end
					scope.destroy()
				end
				release.current = cleanup
				return cleanup
			end
		end
		react.useLayoutEffect(function()
			latest.current = props
			if native.current then
				native.current.setDisabled(props.disabled == true)
				native.current.setReadOnly(props.readOnly == true)
			end
			return nil
		end)
		react.useLayoutEffect(function()
			return function()
				if release.current then
					release.current()
				end
			end
		end, {})
		return binder.current :: (GuiObject) -> (() -> ())?, state, accepted.current
	end
	return { useButton = useButton, useToggle = useToggle, useTextInput = useTextInput, createFieldModel = Field.create }
end

return ReactBindings
