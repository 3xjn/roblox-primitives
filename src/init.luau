--!strict

local InputContext = require(script.InputContext)
local Button = require(script.Button)
local Toggle = require(script.Toggle)
local SelectionModel = require(script.SelectionModel)
local FocusGroup = require(script.FocusGroup)
local FocusStack = require(script.FocusStack)
local TextInput = require(script.TextInput)
local FocusDelegate = require(script.FocusDelegate)
local Label = require(script.Label)
local Image = require(script.Image)
local Field = require(script.Field)
local ReactBindings = require(script.React)

export type React = ReactBindings.React
export type ReactButtonProps = ReactBindings.ButtonProps
export type ReactToggleProps = ReactBindings.ToggleProps
export type ReactTextInputProps = ReactBindings.TextInputProps

export type ButtonState = Button.State
export type ButtonOptions = Button.Options
export type ButtonBinding = Button.Binding
export type ToggleState = Toggle.State
export type ToggleOptions = Toggle.Options
export type ToggleBinding = Toggle.Binding
export type SelectionState = SelectionModel.State
export type SelectionOptions = SelectionModel.Options
export type SelectionController = SelectionModel.Model
export type TextInputState = TextInput.State
export type TextInputOptions = TextInput.Options
export type TextInputBinding = TextInput.Binding
export type FocusDelegateOptions = FocusDelegate.Options
export type FocusDelegateBinding = FocusDelegate.Binding
export type ImageState = Image.State
export type ImageOptions = Image.Options
export type ImageBinding = Image.Binding
export type ImageTarget = Image.Target
export type FocusGroupOptions = FocusGroup.Options
export type FocusGroupBinding = FocusGroup.Binding
export type FocusStackOptions = FocusStack.Options
export type FocusStackEntry = FocusStack.Entry
export type FocusStackController = FocusStack.Stack
export type Scope = {
	bindButton: (GuiButton, ButtonOptions?) -> ButtonBinding,
	bindToggle: (GuiButton, ToggleOptions?) -> ToggleBinding,
	bindTextInput: (TextBox, TextInputOptions?) -> TextInputBinding,
	bindFocusDelegate: (GuiObject, FocusDelegateOptions) -> FocusDelegateBinding,
	bindImage: (ImageTarget, ImageOptions?) -> ImageBinding,
	bindFocusGroup: (GuiObject, FocusGroupOptions?) -> FocusGroupBinding,
	createFocusStack: () -> FocusStackController,
	createSelectionModel: (SelectionOptions?) -> SelectionController,
	destroy: () -> (),
}

local function createScope(): Scope
	local input: InputContext.Context? = nil
	local releaseInput: (() -> ())? = nil
	local bindings: { [GuiButton]: ButtonBinding } = {}
	local toggles: { [GuiButton]: ToggleBinding } = {}
	local textBindings: { [TextBox]: TextInputBinding } = {}
	local delegates: { [GuiObject]: FocusDelegateBinding } = {}
	local imageBindings: { [ImageTarget]: ImageBinding } = {}
	local groups: { FocusGroupBinding } = {}
	local groupOwners: { [GuiObject]: boolean } = {}
	local stacks: { FocusStackController } = {}
	local selections: { SelectionController } = {}
	local destroyed = false
	local scope = {}
	local function getInput(): InputContext.Context
		local current = input
		if current then
			return current
		end
		local created, release = InputContext.acquire()
		if destroyed then
			release()
			error("Behavior scope was destroyed during input-context setup", 0)
		end
		input = created
		releaseInput = release
		return created
	end
	function scope.bindButton(button: GuiButton, options: ButtonOptions?): ButtonBinding
		assert(not destroyed, "Behavior scope has been destroyed")
		assert(not bindings[button] and not toggles[button], "Button is already bound in this scope")
		local released = false
		local binding = Button.bind(button, getInput(), options, function()
			released = true
			bindings[button] = nil
		end)
		if destroyed then
			binding.destroy()
			error("Behavior scope was destroyed during button setup", 0)
		end
		if not released then
			bindings[button] = binding
		end
		return binding
	end
	function scope.bindToggle(button: GuiButton, options: ToggleOptions?): ToggleBinding
		assert(not destroyed, "Behavior scope has been destroyed")
		assert(not bindings[button] and not toggles[button], "Button is already bound in this scope")
		local released = false
		local binding = Toggle.bind(button, getInput(), options, function()
			released = true
			toggles[button] = nil
		end)
		if destroyed then
			binding.destroy()
			error("Behavior scope was destroyed during toggle setup", 0)
		end
		if not released then
			toggles[button] = binding
		end
		return binding
	end
	function scope.bindTextInput(box: TextBox, options: TextInputOptions?): TextInputBinding
		assert(not destroyed, "Behavior scope has been destroyed")
		assert(not textBindings[box], "Text input is already bound in this scope")
		local released = false
		local binding = TextInput.bind(box, getInput(), options, function()
			released = true
			textBindings[box] = nil
		end)
		if destroyed then
			binding.destroy()
			error("Behavior scope was destroyed during text-input setup", 0)
		end
		if not released then
			textBindings[box] = binding
		end
		return binding
	end
	function scope.bindFocusDelegate(source: GuiObject, options: FocusDelegateOptions): FocusDelegateBinding
		assert(not destroyed, "Behavior scope has been destroyed")
		assert(not delegates[source], "Focus delegate is already bound in this scope")
		local released = false
		local binding = FocusDelegate.bind(source, options, function()
			released = true
			delegates[source] = nil
		end)
		if destroyed then
			binding.destroy()
			error("Behavior scope was destroyed during focus-delegate setup", 0)
		end
		if not released then
			delegates[source] = binding
		end
		return binding
	end
	function scope.bindImage(image: ImageTarget, options: ImageOptions?): ImageBinding
		assert(not destroyed, "Behavior scope has been destroyed")
		assert(not imageBindings[image], "Image is already observed in this scope")
		local released = false
		local binding = Image.bind(image, options, function()
			released = true
			imageBindings[image] = nil
		end)
		if destroyed then
			binding.destroy()
			error("Behavior scope was destroyed during image setup", 0)
		end
		if not released then
			imageBindings[image] = binding
		end
		return binding
	end
	function scope.bindFocusGroup(root: GuiObject, options: FocusGroupOptions?): FocusGroupBinding
		assert(not destroyed, "Behavior scope has been destroyed")
		assert(not groupOwners[root], "Focus group is already bound in this scope")
		local released = false
		local binding: FocusGroupBinding? = nil
		binding = FocusGroup.bind(root, getInput(), options, function()
			released = true
			groupOwners[root] = nil
			local index = if binding then table.find(groups, binding) else nil
			if index then
				table.remove(groups, index)
			end
		end)
		if destroyed then
			binding.destroy()
			error("Behavior scope was destroyed during focus-group setup", 0)
		end
		if not released then
			groupOwners[root] = true
			table.insert(groups, binding)
		end
		return binding
	end
	function scope.createFocusStack(): FocusStackController
		assert(not destroyed, "Behavior scope has been destroyed")
		local stack: FocusStackController? = nil
		stack = FocusStack.create(getInput(), function()
			local index = if stack then table.find(stacks, stack) else nil
			if index then
				table.remove(stacks, index)
			end
		end)
		table.insert(stacks, stack)
		return stack
	end
	function scope.createSelectionModel(options: SelectionOptions?): SelectionController
		assert(not destroyed, "Behavior scope has been destroyed")
		local model: SelectionController? = nil
		model = SelectionModel.create(options, function()
			local index = if model then table.find(selections, model) else nil
			if index then
				table.remove(selections, index)
			end
		end)
		table.insert(selections, model)
		return model
	end
	function scope.destroy()
		if destroyed then
			return
		end
		destroyed = true
		local failures: { string } = {}
		local previousStacks = table.clone(stacks)
		for index = #previousStacks, 1, -1 do
			local ok, failure = pcall(previousStacks[index].destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(stacks)
		-- Focus restoration must run while native button selection is still
		-- available. Reverse registration is deterministic, not a modal stack.
		local previousGroups = table.clone(groups)
		for index = #previousGroups, 1, -1 do
			local ok, failure = pcall(previousGroups[index].destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(groups)
		table.clear(groupOwners)
		for _, model in table.clone(selections) do
			local ok, failure = pcall(model.destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(selections)
		for _, binding in table.clone(imageBindings) do
			local ok, failure = pcall(binding.destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(imageBindings)
		for _, binding in table.clone(delegates) do
			local ok, failure = pcall(binding.destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(delegates)
		for _, binding in table.clone(textBindings) do
			local ok, failure = pcall(binding.destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(textBindings)
		for _, binding in table.clone(toggles) do
			local ok, failure = pcall(binding.destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(toggles)
		for _, binding in table.clone(bindings) do
			local ok, failure = pcall(binding.destroy)
			if not ok then
				table.insert(failures, tostring(failure))
			end
		end
		table.clear(bindings)
		if releaseInput then
			releaseInput()
			releaseInput = nil
			input = nil
		end
		if #failures > 0 then
			error(table.concat(failures, "\n"), 0)
		end
	end
	return scope
end

return {
	createScope = createScope,
	createFieldModel = Field.create,
	focusTextInput = TextInput.focus,
	activateButton = Button.activate,
	createLabelBinder = Label.createBinder,
	createBindings = function(react: ReactBindings.React)
		return ReactBindings.create(react, createScope)
	end,
}
