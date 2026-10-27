--!strict

local Presentation = require(script.Parent.Presentation)

export type Options = {
	focus: (InputObject?) -> (boolean, string?),
	-- Press keeps text-focus behavior. Release delegates pointer activation
	-- after a matching end, with hit/presentation policy rechecked.
	activationPhase: ("press" | "release" | (() -> "press" | "release"))?,
	-- Return the topmost native hit, using the same coordinates as InputObject.
	-- A provider is required outside a BasePlayerGui, e.g. for a world surface.
	hitTest: ((GuiObject, Vector2) -> (GuiObject?, string?))?,
	-- Additional interactive roles; native buttons/text inputs always exclude.
	isInteractive: ((GuiObject) -> boolean)?,
}
export type Binding = {
	activateAt: (Vector2, InputObject?) -> (boolean, string?),
	destroy: () -> (),
}

local FocusDelegate = {}
local owners: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" })

local function topHit(source: GuiObject, point: Vector2): (GuiObject?, string?)
	local canvas = source:FindFirstAncestorWhichIsA("BasePlayerGui") :: BasePlayerGui?
	if not canvas then
		return nil, "focus-delegate-hit-test-provider-required"
	end
	local hits = canvas:GetGuiObjectsAtPosition(point.X, point.Y)
	local first = hits[1]
	return if first and first:IsA("GuiObject") then first else nil, nil
end

local function interactive(object: GuiObject): boolean
	return object:IsA("GuiButton") or object:IsA("TextBox")
end

local function presented(source: GuiObject): boolean
	return Presentation.isPresented(source, true)
end

function FocusDelegate.bind(source: GuiObject, options: Options, onRelease: () -> ()): Binding
	assert(not owners[source], "This native focus delegate already has a behavior owner")
	assert(type(options.focus) == "function", "Focus delegate needs a focus action")
	local settings: Options? = table.clone(options)
	local target: GuiObject? = source
	local released: (() -> ())? = onRelease
	local destroyed = false
	local connections: { RBXScriptConnection } = {}
	local pending: { [InputObject]: () -> () } = {}
	owners[source] = true
	local controller: Binding = {} :: Binding
	local function release()
		if destroyed then
			return
		end
		destroyed = true
		if target then
			owners[target] = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, cancel in table.clone(pending) do
			cancel()
		end
		table.clear(pending)
		settings, target = nil, nil
		local notify = released
		released = nil
		if notify then
			notify()
		end
	end
	local function accepts(point: Vector2): (boolean, string?)
		local current, policy = target, settings
		if destroyed or not current or not policy then
			return false, "focus-delegate-destroyed"
		end
		if
			point.X ~= point.X
			or point.Y ~= point.Y
			or math.abs(point.X) == math.huge
			or math.abs(point.Y) == math.huge
		then
			return false, "focus-delegate-invalid-position"
		end
		if not presented(current) then
			return false, "focus-delegate-not-presented"
		end
		if (current:IsA("GuiButton") or current:IsA("TextBox")) and not current.Active then
			return false, "focus-delegate-disabled"
		end
		local hit, failure = (policy.hitTest or topHit)(current, point)
		if destroyed then
			return false, "focus-delegate-destroyed"
		end
		if failure then
			return false, failure
		end
		if not hit or (hit ~= current and not hit:IsDescendantOf(current)) then
			return false, "focus-delegate-outside-hit"
		end
		local ancestor: Instance? = hit
		while ancestor and ancestor ~= current do
			if
				ancestor:IsA("GuiObject")
				and (interactive(ancestor) or (policy.isInteractive and policy.isInteractive(ancestor)))
			then
				return false, "focus-delegate-interactive-hit"
			end
			ancestor = ancestor.Parent
		end
		-- Providers can invoke application code. Recheck ownership/presentation
		-- before dispatch if a callback destroyed, hid or reparented the source.
		if destroyed then
			return false, "focus-delegate-destroyed"
		end
		if ancestor ~= current or not presented(current) then
			return false, "focus-delegate-not-presented"
		end
		if (current:IsA("GuiButton") or current:IsA("TextBox")) and not current.Active then
			return false, "focus-delegate-disabled"
		end
		return true, nil
	end
	function controller.activateAt(point: Vector2, input: InputObject?): (boolean, string?)
		local accepted, reason = accepts(point)
		if not accepted then
			return false, reason
		end
		local policy = settings
		if not policy then
			return false, "focus-delegate-destroyed"
		end
		return policy.focus(input)
	end
	controller.destroy = release
	local function beginInput(input: InputObject)
		local policy = settings
		if destroyed or not policy or pending[input] then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local selected = policy.activationPhase
		local phase: "press" | "release" = if type(selected) == "function"
			then (selected :: () -> "press" | "release")()
			else (selected or "press") :: "press" | "release"
		assert(phase == "press" or phase == "release", "Focus delegate activation phase must be press or release")
		if destroyed or settings ~= policy then
			return
		end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if phase == "press" then
			controller.activateAt(point, input)
			return
		end
		if not accepts(point) then
			return
		end
		local ended: RBXScriptConnection? = nil
		local cancelled: RBXScriptConnection? = nil
		local blurred: RBXScriptConnection? = nil
		local active = true
		local function cancel()
			if not active then
				return
			end
			active = false
			pending[input] = nil
			for _, connection in { ended, cancelled, blurred } do
				if connection then
					connection:Disconnect()
				end
			end
		end
		pending[input] = cancel
		local connected, failure = pcall(function()
			local service = game:GetService("UserInputService")
			ended = service.InputEnded:Connect(function(value)
				if not active or value ~= input then
					return
				end
				cancel()
				if input.UserInputState ~= Enum.UserInputState.Cancel then
					controller.activateAt(Vector2.new(input.Position.X, input.Position.Y), input)
				end
			end)
			cancelled = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.Cancel then
					cancel()
				end
			end)
			blurred = service.WindowFocusReleased:Connect(cancel)
		end)
		if not connected or destroyed then
			cancel()
		end
		if not connected then
			error(failure, 0)
		end
	end
	local ok, failure = pcall(function()
		table.insert(connections, source.Destroying:Connect(release))
		table.insert(connections, source.InputBegan:Connect(beginInput))
	end)
	if not ok then
		local clean, cleanupFailure = pcall(release)
		if not clean then
			error(`Focus delegate setup: {tostring(failure)}; cleanup: {tostring(cleanupFailure)}`, 0)
		end
		error(failure, 0)
	end
	return controller
end

return FocusDelegate
