--!strict

local FocusDelegate = require(script.Parent.FocusDelegate)
local TextInput = require(script.Parent.TextInput)
local Button = require(script.Parent.Button)

type Scope = { bindFocusDelegate: (GuiObject, FocusDelegate.Options) -> FocusDelegate.Binding }
export type Context = { resolveLabelControl: () -> GuiObject? }
export type Options = {
	hitTest: ((GuiObject, Vector2) -> (GuiObject?, string?))?,
	isInteractive: ((GuiObject) -> boolean)?,
	-- Text inputs and buttons reuse their existing bindings by default.
	-- Other control kinds can supply an action; no control is adopted.
	activate: ((GuiObject, InputObject?) -> (boolean, string?))?,
}

local Label = {}

function Label.createBinder(scope: Scope, options: Options?): (GuiObject, Context?) -> (() -> ())?
	local settings: Options = if options then table.clone(options) else {}
	return function(source, context)
		assert(context ~= nil, "Label binding requires its renderer's committed association context")
		local current = context :: Context
		local binding = scope.bindFocusDelegate(source, {
			hitTest = settings.hitTest,
			isInteractive = settings.isInteractive,
			activationPhase = function(): "press" | "release"
				-- Existing custom providers keep their press policy. Native text
				-- inputs focus on press; buttons receive an ordinary release action.
				local control = current.resolveLabelControl()
				return if not settings.activate and control and control:IsA("GuiButton") then "release" else "press"
			end,
			focus = function(input: InputObject?): (boolean, string?)
				local control = current.resolveLabelControl()
				if not control then
					return false, "label-control-unavailable"
				end
				if settings.activate then
					return settings.activate(control, input)
				end
				if control:IsA("TextBox") then
					return TextInput.focus(control)
				elseif control:IsA("GuiButton") then
					if not input then
						return false, "button-activation-input-required"
					end
					return Button.activate(control, input)
				end
				return false, "label-control-activation-provider-required"
			end,
		})
		return binding.destroy
	end
end

return Label
