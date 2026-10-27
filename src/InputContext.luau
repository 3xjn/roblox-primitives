--!strict

export type Listener = () -> ()
local InputContext = {}
InputContext.__index = InputContext

local function navigation(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.Keyboard or inputType.Name:match("^Gamepad") ~= nil
end

function InputContext.new(): Context
	local input = game:GetService("UserInputService")
	local self = setmetatable({
		keyboardVisible = navigation(input:GetLastInputType()),
		windowActive = true,
		guiService = game:GetService("GuiService"),
		_connections = {} :: { RBXScriptConnection },
		_listeners = {} :: { [Listener]: boolean },
		_destroyed = false,
	}, InputContext)
	table.insert(
		self._connections,
		input.InputBegan:Connect(function(object)
			local kind = object.UserInputType
			local visible = if navigation(kind)
				then true
				elseif
					kind == Enum.UserInputType.MouseButton1
					or kind == Enum.UserInputType.MouseButton2
					or kind == Enum.UserInputType.Touch
				then false
				else nil
			if visible ~= nil and visible ~= self.keyboardVisible then
				self.keyboardVisible = visible
				self:_notify()
			end
		end)
	)
	table.insert(
		self._connections,
		input.WindowFocusReleased:Connect(function()
			self.windowActive = false
			self:_notify()
		end)
	)
	table.insert(
		self._connections,
		input.WindowFocused:Connect(function()
			self.windowActive = true
			self:_notify()
		end)
	)
	return self
end

function InputContext._notify(self: Context)
	for listener in table.clone(self._listeners) do
		if self._destroyed then
			break
		end
		if self._listeners[listener] then
			listener()
		end
	end
end

function InputContext.subscribe(self: Context, listener: Listener): () -> ()
	assert(not self._destroyed, "Input context has been destroyed")
	self._listeners[listener] = true
	return function()
		self._listeners[listener] = nil
	end
end

function InputContext.destroy(self: Context)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._listeners)
end

export type Context = typeof(setmetatable(
	{} :: {
		keyboardVisible: boolean,
		windowActive: boolean,
		guiService: GuiService,
		_connections: { RBXScriptConnection },
		_listeners: { [Listener]: boolean },
		_destroyed: boolean,
	},
	InputContext
))

-- Modality and window focus belong to the native input service, not a control.
-- Scopes lease this observer; selection and native-target listeners stay local.
type Shared = { context: Context, references: number }
local shared: Shared? = nil

local function acquire(): (Context, () -> ())
	local current = shared
	if not current or current.context._destroyed then
		current = { context = InputContext.new(), references = 0 }
		shared = current
	end
	local lease = assert(current)
	lease.references += 1
	local released = false
	return lease.context,
		function()
			if released then
				return
			end
			released = true
			lease.references -= 1
			if lease.references == 0 then
				if shared == lease then
					shared = nil
				end
				lease.context:destroy()
			end
		end
end

return { create = InputContext.new, acquire = acquire }
