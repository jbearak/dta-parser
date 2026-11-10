// Stata's missing values in a number column (ADR 0037): plain
// JavaScript, no wasm, so the /format entry has them too.
//
// `.` is R's NA_real_, a NaN whose low word is 1954, and `.a` to `.z` are
// that NaN with the letter's ASCII code in bits 32 to 39: the layout of
// haven's and dtaparser's tagged NAs and the Parquet files' DOUBLE
// columns. Any other NaN is a number. Reading the code
// ignores the sign and the quiet bit, which arithmetic, and a NaN stored
// in a plain array, may change.

import { dtaError } from "./errors";
import { MISSING_NAMES, type MissingName } from "./values";

const NA_LOW = 0x7a2;
const LITTLE = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
const LO = LITTLE ? 0 : 1;
const HI = LITTLE ? 1 : 0;

const scratch = new Float64Array(1);
const words = new Uint32Array(scratch.buffer);

/** The number for missing code 1 (`.`) to 27 (`.z`); 0 at index 0. */
export const MISSING_NUMBERS: Float64Array = (() => {
  const out = new Float64Array(28);
  const w = new Uint32Array(out.buffer);
  for (let code = 1; code <= 27; code++) {
    w[2 * code + LO] = NA_LOW;
    w[2 * code + HI] = code === 1 ? 0x7ff00000 : 0x7ff00000 | (0x61 + code - 2);
  }
  return out;
})();

/** Stata's `.`: R's `NA_real_`, a NaN that is not a number but a missing value. */
export const NA: number = MISSING_NUMBERS[1];

/**
 * The missing code of `x`: 0 for a number (a NaN that is not tagged
 * included), 1 for `.`, 2 to 27 for `.a` to `.z`. Where a 1.x reader's
 * `NumberColumn.missing[i]` was, use `missingCode(values[i])`.
 */
export function missingCode(x: number): number {
  if (x === x) return 0;
  scratch[0] = x;
  if (words[LO] !== NA_LOW || (words[HI] & 0x7ff7ff00) !== 0x7ff00000) return 0;
  const b = words[HI] & 0xff;
  if (b === 0) return 1;
  return b >= 0x61 && b <= 0x7a ? b - 0x61 + 2 : 0;
}

function letterCode(letter: string): number {
  if (typeof letter !== "string") throw dtaError("DTA_INVALID", `a letter is ".a" to ".z" or "a" to "z", not ${String(letter)}`, undefined, TypeError);
  const t = letter.startsWith(".") ? letter.slice(1) : letter;
  if (t.length !== 1 || t < "a" || t > "z") throw dtaError("DTA_INVALID", `a letter is ".a" to ".z" or "a" to "z", not ${JSON.stringify(letter)}`, undefined, RangeError);
  return t.charCodeAt(0) - 0x61 + 2;
}

/**
 * The number that holds Stata's missing value `letter` (`".a"` to
 * `".z"`, or `"a"` to `"z"`): a NaN tagged with it. Keep it in a
 * Float64Array, which keeps its bits; `Float64Array.prototype.sort`
 * does not.
 */
export function taggedNa(letter: string): number {
  return MISSING_NUMBERS[letterCode(letter)];
}

/** The letter of `x`, `".a"` to `".z"`, or undefined for a number or `.`. */
export function naTag(x: number): MissingName | undefined {
  const code = missingCode(x);
  return code > 1 ? MISSING_NAMES[code - 1] : undefined;
}

/** Whether `x` is one of `.a` to `.z`, or the letter given. */
export function isTaggedNa(x: number, letter?: string): boolean {
  const code = missingCode(x);
  return letter === undefined ? code > 1 : code === letterCode(letter);
}

/** Each value's missing code (see `missingCode`), as the module takes them. */
export function codesOf(values: Float64Array): Uint8Array {
  const codes = new Uint8Array(values.length);
  for (let i = 0; i < values.length; i++) {
    const x = values[i];
    if (x !== x) codes[i] = missingCode(x);
  }
  return codes;
}

/** Put the missing value of each nonzero code into `values`, from `at`. */
export function applyCodes(values: Float64Array, codes: Uint8Array, at = 0): void {
  for (let i = 0; i < codes.length; i++) if (codes[i]) values[at + i] = MISSING_NUMBERS[codes[i]];
}

/** `values` with the missing value of each nonzero code in place of its value (a copy, if any). */
export function withCodes(values: Float64Array, codes: Uint8Array): Float64Array {
  if (!codes.some((c) => c !== 0)) return values;
  const out = values.slice();
  applyCodes(out, codes);
  return out;
}
