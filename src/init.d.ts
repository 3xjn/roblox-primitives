import type { Model, Options } from './Field';
export type { Model as FieldModel, Options as FieldOptions } from './Field';
export declare function createFieldModel(initialValue?: string, options?: Options): Model;
export interface Scope { destroy(): void; bindButton(button: GuiButton, options?: unknown): unknown; bindToggle(button: GuiButton, options?: unknown): unknown; bindTextInput(box: TextBox, options?: unknown): unknown; bindFocusDelegate(source: GuiObject, options: unknown): unknown; bindImage(image: unknown, options?: unknown): unknown; bindFocusGroup(root: GuiObject, options?: unknown): unknown; createFocusStack(): unknown; createSelectionModel(options?: unknown): unknown }
export declare function createScope(): Scope;
export declare function focusTextInput(box: TextBox): LuaTuple<[boolean, string | undefined]>;
export declare function activateButton(button: GuiButton, input: InputObject, count?: number): LuaTuple<[boolean, string | undefined]>;
export declare function createLabelBinder(...args: unknown[]): unknown;
export declare function createBindings(react: unknown): unknown;
