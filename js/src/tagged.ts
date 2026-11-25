// Stata's missing values in a number column (ADR 0037, ADR 0047): plain
// JavaScript, no wasm, so the /format entry has them too.
//
// `.` is R's NA_real_, a NaN whose low word is 1954, and `.a` to `.z` are
// that NaN with the letter's ASCII code in bits 32 to 39: the layout of
// haven's and dtaparser's tagged NAs. Any other NaN is a number. Reading
// the code ignores the sign and the quiet bit, which arithmetic, and a
// NaN stored in a plain array, may change.
//
// The package reads and writes these bits through a Uint32Array over a
// Float64Array's buffer, never through a JavaScript number (ADR 0047):
// JavaScriptCore (Bun, Safari) gives every NaN it loads into a number one
// bit pattern, so a number cannot carry the code there, while a typed
// array's bytes keep it on every engine.

import { dtaError } from "./errors";
import { MISSING_NAMES, type MissingName } from "./values";

const NA_LOW = 0x7a2;
const LITTLE = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
const LO = LITTLE ? 0 : 1;
const HI = LITTLE ? 1 : 0;

const scratch = new Float64Array(1);
const words = new Uint32Array(scratch.buffer);

/** The code of the double whose high and low words these are (see `missingCode`). */
function codeOfWords(hi: number, lo: number): number {
  if (lo !== NA_LOW || (hi & 0x7ff7ff00) !== 0x7ff00000) return 0;
  const b = hi & 0xff;
  if (b === 0) return 1;
  return b >= 0x61 && b <= 0x7a ? b - 0x61 + 2 : 0;
}

/** The 32-bit words of `values`, two a value, over the same bytes. */
function wordsOf(values: Float64Array): Uint32Array {
  return new Uint32Array(values.buffer, values.byteOffset, values.length * 2);
}

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
const MISSING_WORDS = wordsOf(MISSING_NUMBERS);

/**
 * Whether this engine keeps a NaN's payload in a number. V8 (Node, Deno,
 * Chrome) does; JavaScriptCore (Bun, Safari) does not.
 */
export const NAN_PAYLOADS: boolean = (() => {
  scratch[0] = MISSING_NUMBERS[2];
  return words[LO] === NA_LOW && words[HI] === MISSING_WORDS[2 * 2 + HI];
})();

/**
 * Stata's `.`: R's `NA_real_`, a NaN that is not a number but a missing
 * value. On an engine that clears NaN payloads (JavaScriptCore: Bun,
 * Safari) it is a plain NaN, which `missingCode` gives 0 and `writeDta`
 * refuses; use `null` or `MISSING["."]` there.
 */
export const NA: number = MISSING_NUMBERS[1];

/**
 * The missing code of `x`: 0 for a number (a NaN that is not tagged
 * included), 1 for `.`, 2 to 27 for `.a` to `.z`.
 *
 * It reads the NaN's payload, which only an engine that keeps payloads
 * in numbers (V8: Node, Deno, Chrome) passes on. On JavaScriptCore (Bun,
 * Safari) every NaN arrives without one, so this is 0 for any number;
 * `missingCodes(column)`, which reads the column's bytes, works on every
 * engine, and is what replaces 1.1's `NumberColumn.missing`.
 */
export function missingCode(x: number): number {
  if (x === x) return 0;
  scratch[0] = x;
  return codeOfWords(words[HI], words[LO]);
}

/**
 * Each value's missing code (see `missingCode`), read from the column's
 * bytes rather than through numbers, so it gives the same codes on every
 * JavaScript engine: what 1.1's `NumberColumn.missing` held.
 */
export function missingCodes(column: { readonly values: Float64Array }): Uint8Array {
  return codesOf(column.values);
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
 *
 * Throws (`DTA_INVALID`) on an engine that clears NaN payloads
 * (JavaScriptCore: Bun, Safari), where the number would be a plain NaN
 * and the letter lost: use `MISSING[".a"]` in a plain array there.
 */
export function taggedNa(letter: string): number {
  const code = letterCode(letter);
  if (!NAN_PAYLOADS) throw dtaError("DTA_INVALID", `this JavaScript engine clears NaN payloads, so a number cannot hold ${MISSING_NAMES[code - 1]}; use MISSING["${MISSING_NAMES[code - 1]}"]`);
  return MISSING_NUMBERS[code];
}

/**
 * The letter of `x`, `".a"` to `".z"`, or undefined for a number or `.`.
 * Always undefined on an engine that clears NaN payloads (see
 * `missingCode`).
 */
export function naTag(x: number): MissingName | undefined {
  const code = missingCode(x);
  return code > 1 ? MISSING_NAMES[code - 1] : undefined;
}

/**
 * Whether `x` is one of `.a` to `.z`, or the letter given. Always false
 * on an engine that clears NaN payloads (see `missingCode`).
 */
export function isTaggedNa(x: number, letter?: string): boolean {
  const code = missingCode(x);
  return letter === undefined ? code > 1 : code === letterCode(letter);
}

/** Each value's missing code (see `missingCode`), read from the bytes, as the module takes them. */
export function codesOf(values: Float64Array): Uint8Array {
  const w = wordsOf(values);
  const codes = new Uint8Array(values.length);
  for (let i = 0; i < values.length; i++) {
    // Only a NaN's high word has all exponent bits set.
    const hi = w[2 * i + HI];
    if ((hi & 0x7ff00000) === 0x7ff00000) codes[i] = codeOfWords(hi, w[2 * i + LO]);
  }
  return codes;
}

/** Put the missing value of each nonzero code into `values`, from `at`, by its bytes. */
export function applyCodes(values: Float64Array, codes: Uint8Array, at = 0): void {
  const w = wordsOf(values);
  for (let i = 0; i < codes.length; i++) {
    const c = codes[i];
    if (c) {
      w[2 * (at + i)] = MISSING_WORDS[2 * c];
      w[2 * (at + i) + 1] = MISSING_WORDS[2 * c + 1];
    }
  }
}
