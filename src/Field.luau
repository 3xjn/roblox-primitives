--!strict
-- Event-driven field state. Native controls and validation providers retain
-- value ownership; this model has no CSS, React, DOM or executor dependency.

export type Result = { errors: { string }, flags: { [string]: boolean }? }
export type Cancel = () -> ()
export type Runner = (string, (Result) -> ()) -> Cancel?
export type Scheduler = (number, () -> ()) -> Cancel
export type Options = {
	disabled: boolean?,
	readOnly: boolean?,
	invalid: boolean?,
	dirty: boolean?,
	touched: boolean?,
	validationMode: ("onSubmit" | "onBlur" | "onChange")?,
	validationDebounceTime: number?,
	runValidation: Runner?,
	schedule: Scheduler?,
}
export type State = {
	read disabled: boolean,
	read touched: boolean,
	read dirty: boolean,
	read valid: boolean?,
	read filled: boolean,
	read focused: boolean,
}
export type Snapshot = {
	read state: State,
	read value: string,
	read initialValue: string,
	read errors: { string },
	read flags: { [string]: boolean },
}
export type Model = {
	getSnapshot: () -> Snapshot?,
	configure: (Options) -> (),
	setValue: (string) -> (),
	setFocused: (boolean) -> (),
	validate: () -> (),
	submit: () -> (),
	reset: (string?) -> (),
	subscribe: ((Snapshot) -> ()) -> Cancel,
	destroy: () -> (),
}

local Field = {}

local function checked(options: Options): Options
	local value = table.clone(options)
	for _, name in { "disabled", "readOnly", "invalid", "dirty", "touched" } do
		local option = (value :: any)[name]
		assert(option == nil or type(option) == "boolean", `Field {name} must be boolean`)
	end
	local mode = value.validationMode
	assert(mode == nil or mode == "onSubmit" or mode == "onBlur" or mode == "onChange", "Unknown field validation mode")
	local delay = value.validationDebounceTime or 0
	assert(
		type(delay) == "number" and delay == delay and delay >= 0 and delay < math.huge,
		"Field validation delay must be finite and nonnegative"
	)
	assert(value.runValidation == nil or type(value.runValidation) == "function", "Field validator must be a provider")
	assert(value.schedule == nil or type(value.schedule) == "function", "Field scheduler must be a provider")
	assert(delay == 0 or value.schedule ~= nil, "Debounced validation requires a scheduler")
	return value
end

local function same(a: any, b: any): boolean
	for key, value in a do
		if b[key] ~= value then
			return false
		end
	end
	for key, value in b do
		if a[key] ~= value then
			return false
		end
	end
	return true
end

function Field.create(initialValue: string?, options: Options?): Model
	assert(initialValue == nil or type(initialValue) == "string", "Field initial value must be a string")
	local initial, value = initialValue or "", initialValue or ""
	local settings = checked(options or {})
	local closed, focused, touched, submitted = false, false, false, false
	local valid: boolean? = nil
	local errors: { string } = table.freeze({} :: { string })
	local flags: { [string]: boolean } = table.freeze({} :: { [string]: boolean })
	local listeners: { [(Snapshot) -> ()]: boolean } = {}
	local snapshot: Snapshot
	local generation = 0
	local cancelRun: Cancel? = nil
	local cancelDelay: Cancel? = nil
	local announcing, again = false, false
	local function cancel()
		generation += 1
		local timer, runner = cancelDelay, cancelRun
		cancelDelay, cancelRun = nil, nil
		if timer then
			timer()
		end
		if runner then
			runner()
		end
	end
	local function state(): State
		return {
			disabled = settings.disabled == true,
			touched = if settings.touched ~= nil then settings.touched else touched,
			dirty = if settings.dirty ~= nil then settings.dirty else value ~= initial,
			valid = if settings.invalid then false elseif settings.disabled then nil else valid,
			filled = value ~= "",
			focused = focused and not settings.disabled,
		}
	end
	local function publish()
		local current = state()
		if
			snapshot
			and snapshot.value == value
			and snapshot.initialValue == initial
			and snapshot.errors == errors
			and snapshot.flags == flags
			and same(snapshot.state, current)
		then
			return
		end
		snapshot = table.freeze({
			state = table.freeze(current),
			value = value,
			initialValue = initial,
			errors = errors,
			flags = flags,
		})
		if announcing then
			again = true
			return
		end
		announcing = true
		local ok, failure = pcall(function()
			repeat
				again = false
				local announcement = snapshot
				for listener in table.clone(listeners) do
					if closed then
						break
					end
					if listeners[listener] then
						listener(announcement)
					end
				end
			until not again or closed
		end)
		announcing = false
		if not ok then
			error(failure, 0)
		end
	end
	local function validate()
		assert(not closed, "Field model is destroyed")
		cancel()
		if settings.disabled or settings.readOnly then
			return
		end
		local ticket = generation
		local run = settings.runValidation
		if not run then
			return
		end
		local starting, completed = true, false
		local deferred: Result? = nil
		local function apply(result: Result)
			if closed or generation ~= ticket then
				return
			end
			assert(type(result) == "table" and type(result.errors) == "table", "Field validation requires errors")
			local messages: { string } = {}
			for index in result.errors do
				assert(
					type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #result.errors,
					"Field errors must be a dense array"
				)
			end
			for index = 1, #result.errors do
				local message = result.errors[index]
				assert(type(message) == "string", "Field errors must be strings")
				if message ~= "" then
					table.insert(messages, message)
				end
			end
			local nextFlags: { [string]: boolean } = {}
			local failed = #messages > 0
			for name, active in result.flags or {} do
				assert(
					type(name) == "string" and name ~= "valid" and type(active) == "boolean",
					"Invalid field validity flag"
				)
				nextFlags[name] = active
				failed = failed or active
			end
			valid = not failed
			if not same(errors, messages) then
				errors = table.freeze(messages)
			end
			if not same(flags, nextFlags) then
				flags = table.freeze(nextFlags)
			end
			local release = cancelRun
			cancelRun = nil
			if release then
				release()
			end
			publish()
		end
		local function finish(result: Result)
			if completed or closed or generation ~= ticket then
				return
			end
			completed = true
			if starting then
				deferred = result
			else
				apply(result)
			end
		end
		local ok, release = pcall(run, value, finish)
		starting = false
		if not ok then
			generation += 1
			error(release, 0)
		end
		assert(release == nil or type(release) == "function", "Field validation cancellation must be a function")
		if completed or closed or generation ~= ticket then
			if release then
				release()
			end
		else
			cancelRun = release
		end
		if deferred then
			apply(deferred)
		end
	end
	local function changeValidation()
		if closed or ((settings.validationMode or "onSubmit") ~= "onChange" and not submitted) then
			return
		end
		local delay = settings.validationDebounceTime or 0
		if delay == 0 then
			validate()
			return
		end
		local ticket = generation
		local fired = false
		local release = (settings.schedule :: Scheduler)(delay, function()
			if closed or generation ~= ticket then
				return
			end
			fired = true
			cancelDelay = nil
			validate()
		end)
		assert(type(release) == "function", "Field scheduler cancellation must be a function")
		if fired or closed or generation ~= ticket then
			release()
		else
			cancelDelay = release
		end
	end
	local model: Model
	model = {
		getSnapshot = function()
			return if closed then nil else snapshot
		end,
		configure = function(nextOptions: Options)
			assert(not closed, "Field model is destroyed")
			local nextSettings = checked(nextOptions)
			if same(settings, nextSettings) then
				return
			end
			cancel()
			settings = nextSettings
			if settings.disabled then
				focused = false
			end
			publish()
		end,
		setValue = function(nextValue: string)
			assert(not closed, "Field model is destroyed")
			assert(type(nextValue) == "string", "Field value must be a string")
			if value == nextValue then
				return
			end
			cancel()
			value = nextValue
			publish()
			changeValidation()
		end,
		setFocused = function(nextFocused: boolean)
			assert(not closed, "Field model is destroyed")
			assert(type(nextFocused) == "boolean", "Field focus must be boolean")
			if focused == nextFocused then
				return
			end
			local blurred = focused and not nextFocused
			focused = nextFocused
			if blurred then
				touched = true
			end
			publish()
			if not closed and blurred and settings.validationMode == "onBlur" then
				validate()
			end
		end,
		validate = validate,
		submit = function()
			assert(not closed, "Field model is destroyed")
			submitted = true
			validate()
		end,
		reset = function(nextInitial: string?)
			assert(not closed, "Field model is destroyed")
			assert(nextInitial == nil or type(nextInitial) == "string", "Field initial value must be a string")
			cancel()
			initial = nextInitial or initial
			value, focused, touched, submitted, valid = initial, false, false, false, nil
			errors, flags = table.freeze({} :: { string }), table.freeze({} :: { [string]: boolean })
			publish()
		end,
		subscribe = function(listener: (Snapshot) -> ())
			assert(not closed and type(listener) == "function", "Field subscription requires a live model and callback")
			assert(not listeners[listener], "Field listener is already subscribed")
			listeners[listener] = true
			return function()
				listeners[listener] = nil
			end
		end,
		destroy = function()
			if closed then
				return
			end
			closed = true
			cancel()
			table.clear(listeners)
		end,
	}
	publish()
	return model
end

return Field
