// Helpers both writers use; nothing here is exported from the package.

import { MISSING_NAMES, type Missing } from "./values";

const encoder = new TextEncoder();

/**
 * UTF-8 bytes of `texts` (a Uint8Array as it is), end to end, with each
 * one's end offset. Encoded straight into one buffer, grown as needed: an
 * array per string cost about 100 bytes each, gigabytes for 10M strings.
 */
export function packTexts(texts: readonly (string | Uint8Array)[]): { bytes: Uint8Array; ends: Uint32Array } {
  let bytes = new Uint8Array(texts.reduce((n, t) => n + t.length, 0) + 64);
  const ends = new Uint32Array(texts.length);
  let at = 0;
  texts.forEach((t, i) => {
    // A UTF-16 unit is at most 3 bytes of UTF-8.
    const most = typeof t === "string" ? 3 * t.length : t.length;
    if (at + most > bytes.length) {
      const grown = new Uint8Array(Math.max(2 * bytes.length, at + most));
      grown.set(bytes.subarray(0, at));
      bytes = grown;
    }
    if (typeof t === "string") at += encoder.encodeInto(t, bytes.subarray(at)).written;
    else {
      bytes.set(t, at);
      at += t.length;
    }
    ends[i] = at;
  });
  return { bytes: bytes.subarray(0, at), ends };
}

/** Numbers and their missing codes, as the module takes them. */
export function packNumbers(values: readonly (number | Missing | null)[]): { values: Float64Array; missing: Uint8Array } {
  const out = { values: new Float64Array(values.length), missing: new Uint8Array(values.length) };
  values.forEach((v, i) => {
    if (typeof v === "number") out.values[i] = v;
    else out.missing[i] = v === null ? 1 : MISSING_NAMES.indexOf(v.missing) + 1;
  });
  return out;
}

