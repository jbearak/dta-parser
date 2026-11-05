// Helpers both writers use; nothing here is exported from the package.

import { MISSING_NAMES, type Missing } from "./values";

const encoder = new TextEncoder();

/**
 * UTF-8 bytes of `texts` (a Uint8Array as it is), end to end, with each
 * one's end offset. Encoded straight into one buffer, grown as needed: an
 * array per string cost about 100 bytes each, gigabytes for 10M strings.
 */
export function packTexts(texts: readonly (string | Uint8Array)[]): { bytes: Uint8Array; ends: Uint32Array } {
  const n = texts.length;
  let size = 64;
  let strings = true;
  for (let i = 0; i < n; i++) {
    const t = texts[i];
    size += t.length;
    if (typeof t !== "string") strings = false;
  }
  let bytes = new Uint8Array(size);
  const ends = new Uint32Array(n);
  let at = 0;
  const room = (most: number) => {
    if (at + most <= bytes.length) return;
    const grown = new Uint8Array(Math.max(2 * bytes.length, at + most));
    grown.set(bytes.subarray(0, at));
    bytes = grown;
  };
  /** Rows `from` to `to` one at a time. */
  const each = (from: number, to: number) => {
    for (let i = from; i < to; i++) {
      const t = texts[i];
      if (typeof t === "string") {
        // ASCII is copied a unit at a time, which is faster than a call
        // to the encoder per string; anything else goes to the encoder.
        const len = t.length;
        room(len);
        let j = 0;
        for (; j < len; j++) {
          const c = t.charCodeAt(j);
          if (c > 0x7f) break;
          bytes[at + j] = c;
        }
        if (j === len) at += len;
        else {
          // A UTF-16 unit is at most 3 bytes of UTF-8.
          room(3 * len);
          at += encoder.encodeInto(t, bytes.subarray(at)).written;
        }
      } else {
        room(t.length);
        bytes.set(t, at);
        at += t.length;
      }
      ends[i] = at;
    }
  };
  if (!strings || size - 64 < JOIN_LENGTH * n) {
    each(0, n);
    return { bytes: bytes.subarray(0, at), ends };
  }
  // Longer strings: a block of them joined and encoded in one call, which
  // is faster than a unit at a time. When the block's text is ASCII its
  // byte offsets are its strings' lengths; otherwise it is done again a
  // string at a time.
  for (let from = 0; from < n; from += JOIN_ROWS) {
    const to = Math.min(n, from + JOIN_ROWS);
    const block = (texts as readonly string[]).slice(from, to).join("");
    const start = at;
    room(block.length);
    const done = encoder.encodeInto(block, bytes.subarray(at));
    if (done.read === block.length && done.written === block.length) {
      for (let i = from; i < to; i++) {
        at += texts[i].length;
        ends[i] = at;
      }
    } else {
      at = start;
      each(from, to);
    }
  }
  return { bytes: bytes.subarray(0, at), ends };
}

/** Strings this long on average, or longer, are encoded a block at a time. */
const JOIN_LENGTH = 12;
const JOIN_ROWS = 1 << 16;

/** Numbers and their missing codes, as the module takes them. */
export function packNumbers(values: readonly (number | Missing | null)[]): { values: Float64Array; missing: Uint8Array } {
  const out = { values: new Float64Array(values.length), missing: new Uint8Array(values.length) };
  values.forEach((v, i) => {
    if (typeof v === "number") out.values[i] = v;
    else out.missing[i] = v === null ? 1 : MISSING_NAMES.indexOf(v.missing) + 1;
  });
  return out;
}

