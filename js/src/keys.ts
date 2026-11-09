// Stata's sort order for numbers and missing values: plain JavaScript,
// no wasm, so the /format entry has it too (plan 0021).

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
 * `rows.sort((a, b) => dtaKey(a) - dtaKey(b))`.
 */
export function dtaKey(value: number | Missing): number {
  if (typeof value === "number") return Number.isNaN(value) ? MISSING_KEYS[0] : value;
  return MISSING_KEYS[MISSING_NAMES.indexOf(value.missing)];
}

/** `dtaKey` for every value of a NumberColumn. */
export function dtaKeys(column: { readonly values: Float64Array; readonly missing: Uint8Array }): Float64Array {
  const out = new Float64Array(column.values.length);
  for (let i = 0; i < out.length; i++) {
    const code = column.missing[i];
    out[i] = code === 0 ? column.values[i] : MISSING_KEYS[code - 1];
  }
  return out;
}

/** @deprecated The 1.0 name of {@link dtaKey}, still exported. */
export const stataKey = dtaKey;

/** @deprecated The 1.0 name of {@link dtaKeys}, still exported. */
export const stataKeys = dtaKeys;
