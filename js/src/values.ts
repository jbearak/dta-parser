// Cells and missing values: plain JavaScript, no wasm, so the /format
// subpath can use them where wasm cannot run (a webview, for one).

/** The name of a Stata missing value: `.` or `.a` to `.z`. */
export type MissingName =
  | "."
  | ".a" | ".b" | ".c" | ".d" | ".e" | ".f" | ".g" | ".h" | ".i" | ".j" | ".k" | ".l" | ".m"
  | ".n" | ".o" | ".p" | ".q" | ".r" | ".s" | ".t" | ".u" | ".v" | ".w" | ".x" | ".y" | ".z";

/** A Stata missing value: `.` or `.a` to `.z`. */
export interface Missing {
  readonly missing: MissingName;
}

export const MISSING_NAMES = [".", ...Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`)] as MissingName[];

/**
 * The 27 missing values, one frozen object each, so `===` compares them:
 * `MISSING["."]`, `MISSING[".a"]`, ... `MISSING[".z"]`.
 */
export const MISSING: Readonly<Record<string, Missing>> = Object.freeze(
  Object.fromEntries(MISSING_NAMES.map((name) => [name, Object.freeze({ missing: name })])),
);

/** The missing value for a code in a NumberColumn's `missing` array (1 to 27). */
export function missingValue(code: number): Missing {
  return MISSING[MISSING_NAMES[code - 1]];
}

/** Whether a cell is a missing value (`.` or `.a` to `.z`) rather than a number, string or bytes. */
export function isMissing(value: unknown): value is Missing {
  return typeof value === "object" && value !== null && "missing" in value;
}

/** One cell: a number, a string, a binary strL, or a missing value. */
export type Cell = number | string | Uint8Array | Missing;

/** Value label set: maps a value, or a missing value, to its text. */
export type ValueLabels = Map<number | Missing, string>;
