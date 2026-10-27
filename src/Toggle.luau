--!strict

local Button = require(script.Parent.Button)
local InputContext = require(script.Parent.InputContext)

export type State = { value: boolean, readOnly: boolean, interaction: Button.State }
export type Options = {
	value: boolean?,
	defaultValue: boolean?,
	disabled: boolean?,
	readOnly: boolean?,
	onState: ((State) -> ())?,
	onValueChange: ((boolean, InputObject, number) -> ())?,
}
export type Binding = {
	getState: () -> State?,
	setValue: (boolean) -> (),
	setReadOnly: (boolean) -> (),
	setDisabled: (boolean) -> (),
	destroy: () -> (),
}

local Toggle = {}
local function same(a: State?, b: State): boolean
	return a ~= nil
		and a.value == b.value
		and a.readOnly == b.readOnly
		and a.interaction.hovered == b.interaction.hovered
		and a.interaction.pressed == b.interaction.pressed
		and a.interaction.focused == b.interaction.focused
		and a.interaction.focusVisible == b.interaction.focusVisible
		and a.interaction.disabled == b.interaction.disabled
end

function Toggle.bind(button: GuiButton, context: InputContext.Context, options: Options?, onRelease: () -> ()): Binding
	local defaults: Options = options or {}
	local settings = table.clone(defaults)
	local controlled = settings.value ~= nil
	local value = if controlled then settings.value == true else settings.defaultValue == true
	local readOnly = settings.readOnly == true
	local native: Button.Binding? = nil
	local closed, notificationPending = false, false
	local announced: State? = nil
	local releaseCallback: (() -> ())? = onRelease
	local function getState(): State?
		local state = if native and not closed then native.getState() else nil
		return if state then { value = value, readOnly = readOnly, interaction = state } else nil
	end
	local function notify()
		if closed or notificationPending or not settings.onState then
			return
		end
		notificationPending = true
		task.defer(function()
			notificationPending = false
			local state = getState()
			if closed or not state or same(announced, state) then
				return
			end
			announced = { value = state.value, readOnly = state.readOnly, interaction = table.clone(state.interaction) }
			if settings.onState then
				settings.onState(state)
			end
		end)
	end
	local function finish()
		if closed then
			return
		end
		closed = true
		native = nil
		announced = nil
		settings.onState, settings.onValueChange = nil, nil
		local callback = releaseCallback
		releaseCallback = nil
		if callback then
			callback()
		end
	end
	local controller: Binding = {
		getState = getState,
		setValue = function(nextValue)
			assert(not closed, "Toggle binding has been destroyed")
			if value ~= nextValue then
				value = nextValue
				notify()
			end
		end,
		setReadOnly = function(nextValue)
			assert(not closed, "Toggle binding has been destroyed")
			if readOnly ~= nextValue then
				readOnly = nextValue
				notify()
			end
		end,
		setDisabled = function(nextValue)
			local current = native
			assert(not closed and current, "Toggle binding has been destroyed")
			current.setDisabled(nextValue)
			notify()
		end,
		destroy = function()
			local previous = native
			finish()
			if previous then
				previous.destroy()
			end
		end,
	}
	local ok, failure = pcall(function()
		local created = Button.bind(button, context, {
			disabled = settings.disabled,
			onState = function()
				notify()
			end,
			onActivated = function(input, count)
				if closed or readOnly then
					return
				end
				local nextValue = not value
				if not controlled then
					value = nextValue
					notify()
				end
				if settings.onValueChange then
					settings.onValueChange(nextValue, input, count)
				end
			end,
		}, finish)
		if closed then
			created.destroy()
		else
			native = created
			notify()
		end
	end)
	if not ok then
		local previous = native
		finish()
		if previous then
			local clean, cleanupFailure = pcall(previous.destroy)
			if not clean then
				error(`Toggle setup: {tostring(failure)}; cleanup: {tostring(cleanupFailure)}`, 0)
			end
		end
		error(failure, 0)
	end
	return controller
end

return Toggle
