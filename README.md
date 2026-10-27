# Roblox interaction primitives

Native control behavior shared by component libraries. This package has no CSS, Tailwind, Coss, React or executor dependency.

## Field state

`createFieldModel(initialValue, options?)` creates the independent string-field
model used by the React Field adapter. It owns state snapshots, subscriptions,
validation generations and cancellation. The native control keeps value ownership.
The setters receive accepted values and native focus changes. `configure`
replaces its options, `reset` clears validation and interaction state, and
`destroy` releases callbacks and pending work. `getSnapshot()` returns nil after
destruction. Asynchronous validation and debouncing use injected providers;
there is no native input creation or recurring check. See [Fields](../../docs/fields.md)
for integration and remaining form/control limits.

## Focus delegates

`Primitives.createLabelBinder(scope, options?)` adapts a renderer-supplied label
association to these delegates. Its default action focuses an existing bound
TextBox on press through `focusTextInput`, or activates an existing bound
GuiButton on pointer release through `activateButton`. Other control types
need an explicit action.
It has no CSS/React dependency and creates no native widgets. See the
[label contract](../../docs/labels.md) for setup, lifetime and verified scope.

`scope.bindFocusDelegate(source, options)` routes primary mouse-down and touch
begin events from an existing GuiObject to a supplied focus action. It creates
no GUI instances, changes no layout/input flags, and acquires no InputContext.
The caller owns sizing, spacing and presentation. Default `activationPhase =
"press"` preserves this focus timing. With `"release"` (or a function choosing
that phase), an accepted press installs transient InputEnded, input-state Cancel
and window-blur listeners. Only the matching input's end can dispatch, after
the same hit/presentation checks. End, cancel, blur, destruction and disposal
disconnect them. The two idle source connections are released on source
destruction, binding disposal or scope teardown. Repeated disposal is harmless.

```luau
local scope = Primitives.createScope()
local input = scope.bindTextInput(textBox)
local addon = scope.bindFocusDelegate(addonFrame, {
    focus = input.focus,
})
-- scope.destroy() releases both bindings.
```

The default hit provider uses the source's BasePlayerGui and
[GetGuiObjectsAtPosition](https://create.roblox.com/docs/reference/engine/classes/BasePlayerGui#GetGuiObjectsAtPosition).
Only a topmost hit belonging to the source is accepted. Native GuiButton and
TextBox descendants always exclude delegation, including disabled controls;
`isInteractive(object)` can add application roles. An outside overlay, hidden
or non-interactable source/ancestor, disabled collector or invalid point blocks
dispatch. An optional `hitTest(source, position)` returns the topmost GuiObject
and optional failure reason; other surfaces require that provider explicitly.
This does not implement CSS pointer-events or ARIA role mapping.

`binding.activateAt(position, input?)` runs the final dispatch policy directly,
without scheduling a gesture. It forwards the optional InputObject to `focus`
and returns the outcome and optional reason. Button delegates require it.
Coordinates match InputObject.Position. Native
[InputBegan](https://create.roblox.com/docs/reference/engine/classes/GuiObject#InputBegan)
works independently of Active; the delegate leaves an ordinary Frame's Active
property unchanged. Inactive button/text-input sources are still blocked.

When only the native editor target is available, use
`Primitives.focusTextInput(textBox)`. It routes to that target's existing
TextInput binding, preserving disabled, visibility/window and native-focus
checks. It neither adopts the editor nor creates a binding. An unbound target
returns `text-input-unbound`. The lookup uses the same package instance, weak
keys/values, and existing teardown; it adds no native listeners.

`Primitives.activateButton(button, input, count?)` similarly dispatches through
an existing Button owner. The native Activated listener calls that same path.
It checks declared/native availability, active window and ancestor presentation,
then supplies the original input and count (default 1) to the existing callback.
It never adopts a button, synthesizes an engine signal or sets control state.
An unbound target returns `button-unbound`; teardown releases the weak lookup.
A true result means accepted dispatch, not necessarily an accepted value change.

Bounded verification passed 52 policy checks, including a controlled signal
double for mouse/touch filtering and listener teardown, with zero InputContext
acquisitions. A native LocalScript passed 22 owned-focus checks using an injected
hit provider: focus/text/caret preservation, disabled/read-only/hidden policy,
a controlled window flag,
policy, target changes, rebinding and cleanup. A real Coss single-editor input
group passed 42 direct focus/value/disabled/identity/cleanup checks.

An early screen hit test returned no objects in its Studio session,
including three sampled inset coordinate choices. That failed observation is
retained separately. Default hit filtering, physical pointer/touch delivery,
CSS decorative-fragment routing, world surfaces and Player/Volt remain
unqualified. The injected provider is diagnostic only; production does not
fall back when native hit testing fails. Later Label fixtures exercise the
actual PlayerGui query successfully, including native button dispatch. The
label-activation artifact records 321 model checks and 51 native checks per
language. Physical pointer/touch delivery remains unqualified.

## Optional React bindings

`Primitives.createBindings(React)` supplies `useButton(props)` using the
application's React instance. It returns a stable native-target binder and the
current native button state. Pass the binder to your renderer's native target
lifetime (for the CSS renderer, `bindTarget`). The hook delegates to the same
button scope above: Roblox owns activation, input arguments and focus behavior.
Disabled updates and callback replacements use committed props without rebinding.
Target replacement or component unmount releases the scope; repeated release is
harmless. This optional adapter imports no CSS or component library and bundles
no React implementation. It does not add DOM callbacks or browser keyboard/form
semantics.

`useToggle({ value?, defaultValue?, disabled?, readOnly?, onValueChange? })`
returns the same stable binder shape and a toggle state snapshot. Ownership is
fixed on first render: `value` selects controlled requests; `defaultValue`
initializes an uncontrolled value. Controlled requests require accepted prop
updates. Later default changes do not reset an uncontrolled value, and replacing
the native target preserves its last accepted value. Committed disabled/read-only
props gate requests and update the existing binding. Switching ownership while
mounted fails. The hook reuses the existing toggle primitive; it does not invent
input, toggle the emulated value a second time, or bundle CSS classes.

`useTextInput(props)` returns a stable binder, the observed native text-input
state, and the last observed text for replacement/default initialization. It
delegates to the existing text-input scope and writes no Text/cursor/selection
properties. The renderer/component supplies controlled values or default text
through its own editor data path. Value ownership is fixed while mounted.
Controlled mode requires that renderer's `flushSync` callback so accepted props
commit before reconciliation. Matching controlled echoes do not emit another
value request. Disabled/read-only and callback updates use committed props;
native replacement/component teardown release the scope. Composition/IME,
submission, complete form semantics and StrictMode/concurrency remain unverified
or incomplete. Other React behavior hooks remain unfinished.

```lua
local scope = Primitives.createScope()
local binding = scope.bindButton(existingTextButton, {
    onState = function(state)
        -- Feed component state or your style adapter.
    end,
    onActivated = function(input, clickCount)
        -- Roblox owns mouse, touch and gamepad activation.
    end,
})

binding.setDisabled(true)
-- When the surface is removed:
scope.destroy()
```

Create one scope per UI surface. Scopes that need interaction lease the same module-owned input-modality/window observer. The first lease connects three native service signals; the last scope's release disconnects them. Each binding retains its target-specific events and state. Images and selection models do not initialize input observation. Destroy a scope when its surface is removed; destroying just one binding leaves the scope's lease available for its other controls. The package observes native events; it does not install frame listeners, polling, executor hooks or a custom input dispatcher.

## Images

`scope.bindImage(imageLabelOrButton, { onState = callback })` observes native source,
loading and per-URI fetch-status events. It reports idle/loading/loaded/error state
without writing properties or loading assets itself. Components own fallback
visibility and attributes. Source generations guard application error reports;
`getState`, `setError` and `destroy` expose that contract.

See [image loading](../../docs/image-loading.md) for native failure handling,
source-identity limits, cleanup, CSS target binding and pending runtime checks.

## Buttons

`scope.bindButton(guiButton, options)` binds an existing `TextButton` or `ImageButton`. It creates no visual instances and changes no layout, fonts, colors, icons or text. The component owns the button and its placement.

The binding owns `Active`, `Selectable`, `Interactable` and `AutoButtonColor`. Enabled bindings turn on the first three and disable automatic color feedback, so the component controls its visuals. `disabled = true` or `setDisabled(true)` disables those native behaviors and clears selection only when this exact button is selected. The callback also checks the current native state before forwarding `Activated`. External `Active`/`Interactable` changes are observed as additional activation gates.

`onState` receives an initial snapshot and subsequent changes:

| Field | Native source |
| --- | --- |
| `hovered` | Mouse enter/leave and native `GuiState.Hover`. |
| `pressed` | Native `GuiState.Press`. |
| `focused` | This button is `GuiService.SelectedObject`, selectable and presented. |
| `focusVisible` | Native selection plus the shared keyboard/gamepad input modality. |
| `disabled` | The controlled disabled flag, native `Active`/`Interactable` being off, or native `GuiState.NonInteractable`. |

Visibility and enabled-canvas changes, ancestry changes and window focus events gate interaction feedback. Mouse movement alone does not change keyboard-focus visibility. State notifications are deferred and coalesced from these events; `binding.getState()` reads the current snapshot immediately. Each returned snapshot is copied. Native `Activated` is forwarded directly with its original input and click count, without synthesizing a click from press/release events.

`binding.destroy()` disconnects its listeners and cancels pending state notifications. Destroying the native button releases the binding automatically. `scope.destroy()` releases every remaining binding and its input lease, even when one property's restoration fails. Other scopes keep their observer until their own release. Properties are restored only if their current value still matches this binding's last write. Different external values are retained; identical external writes cannot be distinguished by value. Global selection is not restored to an old button during cleanup. There can be only one behavior owner per native button across scopes.

Sharing applies to modality and window focus only. Scope-owned selection models,
focus groups/stacks, callbacks and target state remain independent. New scopes
inherit events already observed by a live shared context. The first context still
initializes window activity to true; native window state before its first event
and physical keyboard/gamepad/window-event behavior remain unqualified.

## Toggles

`scope.createSelectionModel(options)` shares accepted keyed values across
controls. It supports controlled/uncontrolled single or multiple selection,
empty-selection policy and disabled/read-only requests. It does not bind input
or choose focus. See [grouped selection](../../docs/selection.md) and the typed
`examples/NativeSelectionGroup.luau` composition.

`scope.bindToggle(guiButton, options)` reuses the button adapter and adds a
boolean value. Supply `value` for controlled requests, or `defaultValue` for an
uncontrolled value. `onValueChange(nextValue, input, clickCount)` receives native
activation details. Use `setValue`, `setReadOnly` and `setDisabled` for updates.

State contains the boolean `value`, `readOnly` and the separate native button
`interaction` snapshot. Components own indicators, attributes and semantic
roles. See [toggle behavior](../../docs/toggles.md) for ownership, lifecycle,
controlled updates and runtime limitations.

## Text inputs

```lua
local binding = scope.bindTextInput(existingTextBox, {
    readOnly = false,
    onTextChanged = function(value)
        -- Any native Text change, including another script's write.
    end,
    onFocusLost = function(value, enterPressed, input)
        -- The original native focus-loss signal, not inferred submission.
    end,
})

binding.setReadOnly(true)
binding.setDisabled(true)
```

This adapter binds an existing component-owned `TextBox`; it creates no visual instances. Roblox retains text editing, cursor/selection positions, clipboard behavior, multiline handling, internal text scrolling and on-screen keyboard behavior. The binding never writes `Text`, `CursorPosition` or `SelectionStart`. The component owns text updates, placeholder text, layout, typography and the other TextBox properties. `examples/NativeTextInput.luau` shows a binding without CSS or React.

The owned properties are `Active`, `Selectable`, `Interactable`, `TextEditable` and `ClearTextOnFocus`. Enabled inputs enable the first three; disabled inputs disable all editing/interaction. Read-only inputs set `TextEditable` to false while retaining native focus eligibility. `ClearTextOnFocus` is set to false so focusing an existing value does not clear it. `setDisabled` and `setReadOnly` apply the current requested flags; independent external property changes remain observable until the next explicit flag application.

`onState` receives an initial snapshot and deferred/coalesced changes. Snapshots contain `text`, `focused` (native editing focus), `selected` (native GUI navigation selection), `focusVisible`, `disabled` and `readOnly`. These two kinds of focus remain distinct. Focus-visible is an explicit native adapter policy: editing focus is visible even after a pointer interaction; navigation selection uses the scope's keyboard/gamepad modality. Disabled includes the requested flag and native interaction gates. Read-only reflects the current `TextEditable` value, so a disabled input can also be read-only. External overrides are reflected rather than reported as a successfully enforced requested flag.

`onTextChanged` forwards every observed native Text property change directly; there is no initial change callback and no claim that a change came from the user. `onFocusLost` forwards the original `enterPressed` and input object with a text snapshot. `onReturnPressedFromOnScreenKeyboard` optionally forwards that separate native event with a text snapshot while the input is enabled, presented and the window is active. Mobile/native focus loss and on-screen Return may both fire: the adapter does not combine them into a guessed submission event. Components choose which event their form uses.

`focus()` makes one native CaptureFocus attempt when presented, enabled and the window is active. It returns success or an explicit reason; it does not retry. `blur()` releases editing focus without submitting. Disabling, hiding, removing from the presented hierarchy or observing a native interaction gate close also releases this input's editing focus without submitting. Losing window focus gates the reported state without forcing a native blur. Read-only does not itself force blur; native read-only selection behavior remains unverified.

`getState()` returns a copied current snapshot or nil after teardown. Destroying the binding disconnects listeners, cancels pending notifications and conditionally restores owned properties. Text and cursor positions are not restored, and an existing surviving TextBox is not forcibly blurred during binding removal. Destroying the native TextBox releases the binding without restoration. Scopes release text inputs after focus groups/stacks and before shared input listeners. A single native TextBox can have only one text-input behavior owner across scopes. As with buttons, identical external property writes cannot be distinguished from owned values during restoration.

Native editing, IME composition, platform keyboard behavior, selection preservation during component-controlled text updates, filtering, validation, form submission and browser accessibility remain incomplete or unverified. The CSS scene now has a bounded [editable-target path](../../docs/native-controls.md#editable-targets), with fixed layout, native text rendering and explicit controlled/default values. `examples/BindCssTextInput.luau` shows a target binder. These adapters do not establish a complete Coss Input port or browser editing equivalence.

## CSS and React

Map snapshots to explicit CSS states: `hovered` → `hover`, `pressed` → `active`, `focused` → `focus`, `focusVisible` → `focus-visible`, and `disabled`/its inverse → `disabled`/`enabled`. `examples/NativeButton.luau` supplies a typed bridge to a component state setter. Pass that map to the logical element's `props.states` in the React tree. This keeps one state owner; imperative writes to a React-owned CSS tree would otherwise be replaced on the next render.

The default CSS block scene now maps an explicit `button` tag to an initially inactive native `TextButton`. The React adapter's `useNativeTarget` can bind that target through this package. Layout/text support is still bounded, and control composition, forms and general browser semantics remain unfinished. This package does not overlay hit targets or modify native Roblox menus.

## Native selection groups

```lua
local group = scope.bindFocusGroup(container, {
    contained = true,
    restoreFocus = true,
})
group.requestFocus(nil, function(selected, reason)
    -- Inspect the result; a failed attempt is not retried.
end)
```

The group owns `SelectionGroup` and the four native directional `SelectionBehavior` properties. `contained = true` sets them to `Stop`; false uses `Escape`. Change that policy with `setContained`. Native navigation chooses the next control; the adapter does not scan or sort descendants, replace directional input or change global navigation settings. This is gamepad selection containment, not a browser Tab trap.

`focus(target?)` returns the selected `GuiObject` or `nil, reason`. An explicit target must belong to the group and be presented/selectable. Without a target, the adapter calls native `GuiService:Select`, whose automatic lookup is documented for PlayerGui descendants. Other mount locations need an explicit target; engine navigation availability still applies. Native `SelectionOrder` determines automatic choice, independently of CSS or React source order.

`requestFocus(target?, onResult?)` coalesces requests into one deferred attempt using the latest target/callback. This lets all native target binders in a scene event finish before focus is attempted. There is no automatic retry if no control is ready. Destruction cancels the request. `getFocusWithin()` reads current native selection synchronously; it is not a subscription.

Focus restoration is opt-in. `restore()` returns a success flag/reason and writes only when selection remains inside this group and the saved outside target is still available. It leaves selection elsewhere or `nil` alone. With `restoreFocus = true`, destruction attempts the same operation. Call `restore()` before removing a group when the component lifecycle allows it: after the engine clears selection, ownership cannot be inferred. Reparented, disabled or removed restoration targets are checked by current identity/state. The adapter never guesses why selection changed.

Group teardown conditionally restores its owned properties, using the same value-comparison limitation as buttons. A scope releases ordinary groups in reverse registration order before releasing buttons. For coordinated native selection layers, use an explicit shared stack below; binding several independent groups does not create that stack implicitly. `examples/BindFocusGroup.luau` shows binding through the React adapter's native target hook.

## Native focus stack

```lua
local stack = scope.createFocusStack()
local first = stack.push(dialogRoot, { initialFocus = confirmButton })
local second = stack.push(nestedRoot, { initialFocus = nestedButton })

first.close() -- A layer can close while a later layer remains open.
second.close() -- Its return anchor skips the removed layer.
stack.destroy()
```

`push(root, options?)` creates one owned, contained native selection group and captures the current outside selection as its return anchor. `autoFocus` defaults to true; it schedules one deferred attempt with `initialFocus` and optional `onFocusResult`. Without an explicit target, native `GuiService:Select` still requires a PlayerGui hierarchy. Set `autoFocus = false` when the component will request focus after its target becomes available.

The entry exposes `focus(target?)`, `requestFocus(target?, onResult?)`, `isTop()` and idempotent `close()`. Only the top entry can initiate focus through these methods. Pending requests coalesce, use the latest target/callback and check current stack order before writing. A layer closed before its deferred request runs gets no callback. An obscured entry reports `focus-layer-not-top`; it does not retry when it becomes top later.

`restoreFocus` defaults to true. Closing the top entry restores its captured anchor only while native selection remains in the closing root, the window is active, the anchor is currently presented/selectable, and it belongs to the remaining active root (when one exists). A selection already moved elsewhere or cleared by another system is left alone. If the anchor is unavailable, restoration is skipped; no guessed descendant or forced retry is used. Native selection writes can still be rejected by the engine.

Removing an entry out of order retargets later anchors that point into its native subtree to its own outside anchor. Destroying a native root removes its entry through the owned group's existing destruction event. Closing/replacing a root cancels pending requests and releases owned group properties. Stack teardown releases entries from top to bottom; scope teardown releases stacks before ordinary groups and buttons. Setup also releases a group if reentrant callbacks destroy its stack while it is being bound.

Use one stack for layers which must coordinate. Separate stacks are independent. Native ancestry defines containment; CSS/React portals outside the registered root are not automatically included. This is a selection lifecycle adapter, not a complete browser modal: it does not block background pointer input, synthesize Tab/Enter/Escape behavior, change global navigation flags, force external selection back into the top root, manage visibility or provide accessibility semantics. Nested/out-of-order restoration, root destruction, CoreGui navigation and reentrant native events remain unverified on Roblox.

## Current boundaries

These are initial native control adapters, not a browser interaction implementation. Button focus represents native GUI selection; text inputs distinguish editing focus from selection. Focus-visible uses the documented adapter policies. Space/Enter activation, browser tab order/trapping, full modal semantics and focus restoration, ARIA/accessibility equivalence, disabled-but-focusable controls, forms, complete editing integration, popups and portals need further work. Attaching during an existing press and hover/selection behavior across every occlusion/reparenting case require runtime inspection. Window gating follows native focus events; no separate initial-window-focus probe is implemented.

Presentation checks cover DataModel ancestry, ancestor `Visible` flags and enabled canvases. They do not establish on-screen or unoccluded hit visibility; native automatic selection and activation retain their own eligibility rules.

Source/type analysis and compilation are the available evidence. Input behavior, native API availability and visual feedback remain unverified on Roblox.

References: [GuiButton activation](https://create.roblox.com/docs/reference/engine/classes/GuiButton#Activated), [native GUI states](https://create.roblox.com/docs/reference/engine/classes/GuiObject#GuiState), [native interactability](https://create.roblox.com/docs/reference/engine/classes/GuiObject#Interactable).

Selection references: [native selection groups](https://create.roblox.com/docs/reference/engine/classes/GuiBase2d#SelectionGroup), [automatic selection](https://create.roblox.com/docs/reference/engine/classes/GuiService#Select).

Editing references: [native TextBox](https://create.roblox.com/docs/reference/engine/classes/TextBox), [Roblox's TextBox API source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/TextBox.yaml).

The experimental Coss Input now has bounded Studio native-Backspace, read-only, disabled/focus and controlled/uncontrolled observations. It supplies the consuming renderer’s synchronous event boundary for controlled requests. See the [Coss integration](../coss/README.md#input-integration); this does not establish complete native editing or browser parity.

## Repository setup

This repository contains the `@3xjn/roblox-primitives` package. It is in active development and has not been published to npm.

Run `npm install` to install development dependencies from the related GitHub repositories.

Build the Luau module with `rojo build default.project.json --output Primitives.rbxm`. Runtime imports expect the related modules as siblings in the Roblox package tree.

The development gallery and cross-package tests remain in the private [roblox-styling workspace](https://github.com/3xjn/roblox-styling).
