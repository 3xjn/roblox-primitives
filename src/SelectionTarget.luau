--!strict

local Presentation = require(script.Parent.Presentation)

local SelectionTarget = {}

function SelectionTarget.contains(root: GuiObject, target: GuiObject?): boolean
	return target ~= nil and (target == root or target:IsDescendantOf(root))
end

function SelectionTarget.selectable(target: GuiObject): boolean
	return target.Selectable
		and Presentation.isPresented(target)
		and (not (target:IsA("GuiButton") or target:IsA("TextBox")) or (target.Active and target.Interactable))
end

return SelectionTarget
