export interface Validation { readonly errors: readonly string[]; readonly flags?: Readonly<Record<string, boolean>> }
export type Cancel = () => void;
export type Runner = (value: string, finish: (result: Validation) => void) => Cancel | undefined;
export interface Options {
  readonly disabled?: boolean;
  readonly readOnly?: boolean;
  readonly invalid?: boolean;
  readonly dirty?: boolean;
  readonly touched?: boolean;
  readonly validationMode?: 'onSubmit' | 'onBlur' | 'onChange';
  readonly validationDebounceTime?: number;
  readonly runValidation?: Runner;
  readonly schedule?: (milliseconds: number, callback: () => void) => Cancel;
}
export interface State {
  readonly disabled: boolean; readonly touched: boolean; readonly dirty: boolean;
  readonly valid: boolean | undefined; readonly filled: boolean; readonly focused: boolean;
}
export interface Snapshot {
  readonly state: State; readonly value: string; readonly initialValue: string;
  readonly errors: readonly string[]; readonly flags: Readonly<Record<string, boolean>>;
}
export interface Model {
  readonly getSnapshot: () => Snapshot | undefined;
  readonly configure: (options: Options) => void;
  readonly setValue: (value: string) => void;
  readonly setFocused: (focused: boolean) => void;
  readonly validate: () => void;
  readonly submit: () => void;
  readonly reset: (initialValue?: string) => void;
  readonly subscribe: (listener: (snapshot: Snapshot) => void) => Cancel;
  readonly destroy: () => void;
}
/** Owns field state and cancellation, with no native input or validation implementation. */
export declare function create(initialValue?: string, options?: Options): Model;
