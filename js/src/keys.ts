// Stata's sort order for numbers and missing values: plain JavaScript,
// no wasm, so the /format entry has it too (plan 0021).

import { codesOf, missingCode } from "./tagged";
import { MISSING_NAMES, type Missing } from "./values";

// The doubles Stata itself stores for `.` to `.z`: finite, increasing,
// and above every number Stata stores (code 1 is `.`).
const KEY_BITS = new DataView(new ArrayBuffer(8));
const MISSING_KEYS = Float64Array.from({ length: 27 }, (_, k) => {
  KEY_BITS.setBigUint64(0, 0x7fe0000000000000n + (BigInt(k) << 40n));
  return KEY_BITS.getFloat64(0);
});

/**
 * A number that sorts and compares as Stata does: a number is itself, and
 * `.` < `.a` < ... < `.z` come after every number. Use it to sort, group or
 * compare with missing values in Stata's order:
 * `rows.sort((a, b) => dtaKey(a) - dtaKey(b))`. A tagged NaN number
 * keeps its letter's place only where numbers keep NaN payloads (V8);
 * on Bun and in Safari any NaN sorts as `.`, so use `dtaKeys(column)`
 * or `readRows` cells there (ADR 0047).
 */
export function dtaKey(value: number | Missing): number {
  if (typeof value === "number") return value === value ? value : MISSING_KEYS[Math.max(missingCode(value), 1) - 1];
  return MISSING_KEYS[MISSING_NAMES.indexOf(value.missing)];
}

/** `dtaKey` for every value of a NumberColumn, its missing values read from the column's bytes. */
export function dtaKeys(column: { readonly values: Float64Array }): Float64Array {
  const values = column.values;
  const codes = codesOf(values);
  const out = new Float64Array(values.length);
  for (let i = 0; i < out.length; i++) {
    const x = values[i];
    out[i] = x === x ? x : MISSING_KEYS[Math.max(codes[i], 1) - 1];
  }
  return out;
}

/** @deprecated The 1.0 name of {@link dtaKey}, still exported. */
export const stataKey = dtaKey;

/** @deprecated The 1.0 name of {@link dtaKeys}, still exported. */
export const stataKeys = dtaKeys;
