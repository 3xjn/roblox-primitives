--!strict

local Presentation = {}

function Presentation.isPresented(object: GuiObject, interactive: boolean?): boolean
	if not object:IsDescendantOf(game) then
		return false
	end
	local ancestor: Instance? = object
	local canvas = false
	while ancestor do
		if ancestor:IsA("GuiObject") and (not ancestor.Visible or (interactive and not ancestor.Interactable)) then
			return false
		end
		if ancestor:IsA("LayerCollector") then
			canvas = true
			if not ancestor.Enabled then
				return false
			end
		end
		ancestor = ancestor.Parent
	end
	return canvas
end

return Presentation
