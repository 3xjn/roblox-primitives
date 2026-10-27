--!strict

export type State = {
	value: { string },
	multiple: boolean,
	allowEmpty: boolean,
	disabled: boolean,
	readOnly: boolean,
}
export type Options = {
	value: { string }?,
	defaultValue: { string }?,
	multiple: boolean?,
	allowEmpty: boolean?,
	disabled: boolean?,
	readOnly: boolean?,
	onState: ((State) -> ())?,
	onValueChange: (({ string }, string, boolean) -> ())?,
}
export type Model = {
	getState: () -> State?,
	isSelected: (string) -> boolean?,
	setValue: ({ string }) -> (),
	request: (string, boolean) -> boolean,
	setDisabled: (boolean) -> (),
	setReadOnly: (boolean) -> (),
	destroy: () -> (),
}

local SelectionModel = {}
local function same(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for index, key in a do
		if key ~= b[index] then
			return false
		end
	end
	return true
end

function SelectionModel.create(options: Options?, onRelease: (() -> ())?): Model
	local defaults: Options = options or {}
	local settings = table.clone(defaults)
	local multiple, allowEmpty = settings.multiple == true, settings.allowEmpty ~= false
	local controlled = settings.value ~= nil
	local disabled, readOnly = settings.disabled == true, settings.readOnly == true
	local function normalized(keys: { string }): { string }
		local seen: { [string]: boolean } = {}
		local output: { string } = {}
		for _, key in keys do
			assert(type(key) == "string", "Selection keys must be strings")
			if not seen[key] then
				seen[key] = true
				table.insert(output, key)
			end
		end
		assert(multiple or #output <= 1, "Single selection accepts at most one key")
		return output
	end
	local value = normalized(settings.value or settings.defaultValue or {})
	local closed, pending = false, false
	local announced: State? = nil
	local releaseCallback = onRelease
	local function getState(): State?
		return if closed
			then nil
			else {
				value = table.clone(value),
				multiple = multiple,
				allowEmpty = allowEmpty,
				disabled = disabled,
				readOnly = readOnly,
			}
	end
	local function notify()
		if closed or pending or not settings.onState then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			local state = getState()
			if not state then
				return
			end
			if
				announced
				and same(announced.value, state.value)
				and announced.disabled == state.disabled
				and announced.readOnly == state.readOnly
			then
				return
			end
			announced = {
				value = table.clone(state.value),
				multiple = state.multiple,
				allowEmpty = state.allowEmpty,
				disabled = state.disabled,
				readOnly = state.readOnly,
			}
			if settings.onState then
				settings.onState(state)
			end
		end)
	end
	local model: Model = {
		getState = getState,
		isSelected = function(key)
			return if closed then nil else table.find(value, key) ~= nil
		end,
		setValue = function(keys)
			assert(not closed, "Selection model has been destroyed")
			local nextValue = normalized(keys)
			if not same(value, nextValue) then
				value = nextValue
				notify()
			end
		end,
		request = function(key, selected)
			assert(not closed, "Selection model has been destroyed")
			assert(type(key) == "string", "Selection keys must be strings")
			if disabled or readOnly or (table.find(value, key) ~= nil) == selected then
				return false
			end
			local nextValue = table.clone(value)
			if selected then
				if multiple then
					table.insert(nextValue, key)
				else
					nextValue = { key }
				end
			elseif not allowEmpty and #value == 1 then
				return false
			else
				local index = table.find(nextValue, key)
				if index then
					table.remove(nextValue, index)
				end
			end
			if not controlled then
				value = nextValue
				notify()
			end
			if settings.onValueChange then
				settings.onValueChange(table.clone(nextValue), key, selected)
			end
			return true
		end,
		setDisabled = function(nextValue)
			assert(not closed, "Selection model has been destroyed")
			if disabled ~= nextValue then
				disabled = nextValue
				notify()
			end
		end,
		setReadOnly = function(nextValue)
			assert(not closed, "Selection model has been destroyed")
			if readOnly ~= nextValue then
				readOnly = nextValue
				notify()
			end
		end,
		destroy = function()
			if closed then
				return
			end
			closed = true
			value, announced = {}, nil
			settings.value, settings.defaultValue = nil, nil
			settings.onState, settings.onValueChange = nil, nil
			local callback = releaseCallback
			releaseCallback = nil
			if callback then
				callback()
			end
		end,
	}
	notify()
	return model
end

return SelectionModel
