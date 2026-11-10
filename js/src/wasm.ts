// dta-parser's wasm module and the raw calls into it. Everything above
// this file deals in JavaScript values; everything here deals in
// pointers. The instance and its host callbacks are in wasm-core.ts.

import embedded from "../build/dta.wasm";
import { dtaError } from "./errors";
import { makeCore, type CoreExports, type ReadAt } from "./wasm-core";

export type { ReadAt };

interface Exports extends CoreExports {
  dta_open(file: number, len: number, encoding: number): number;
  dta_close(handle: number): void;
  dta_metadata(handle: number): number;
  dta_value_labels(handle: number): number;
  dta_characteristics(handle: number): number;
  dta_read(handle: number, cols: number, ncols: number, start: number, count: number, flags: number, maxStringBytes: number): number;
  dta_read_at(handle: number, cols: number, ncols: number, rows: number, nrows: number, flags: number, maxStringBytes: number): number;
  dta_read_end(handle: number): void;
  dta_strl_index(handle: number): number;
  dta_adopt_strl_index(handle: number, index: number, len: number): number;
  dta_column_mode(handle: number, k: number): number;
  dta_column_part(handle: number, k: number, part: number): number;
  dta_write_begin(nobs: number): void;
  dta_write_numbers(meta: number, metaLen: number, storage: number, values: number, missing: number): number;
  dta_write_strings(meta: number, metaLen: number, bytes: number, bytesLen: number, ends: number, binary: number): number;
  dta_write_labels(
    name: number,
    nameLen: number,
    n: number,
    values: number,
    missing: number,
    texts: number,
    textsLen: number,
    ends: number,
  ): number;
  dta_write_characteristics(text: number, len: number): number;
  dta_write_sort_order(indices: number, n: number): number;
  dta_write_finish(file: number, info: number, infoLen: number): number;
  /** Test builds only. */
  dta_test_set?(budget: number, chunkBytes: number, stringLimit: number): void;
}

const core = makeCore<Exports>(embedded, "dta-parser");

export function currentGeneration(): number {
  return core.generation();
}

const { guard, check, resultText, put, alloc } = core;

export const ENCODINGS = { "windows-1252": 0, latin1: 1, "utf-8": 2 } as const;
export type EncodingName = keyof typeof ENCODINGS;

export function open(read: ReadAt, length: number, encoding: EncodingName): number {
  if (!Object.hasOwn(ENCODINGS, encoding)) {
    throw dtaError("DTA_INVALID", `unknown encoding ${JSON.stringify(encoding)}; use ${Object.keys(ENCODINGS).join(", ")}`, undefined, TypeError);
  }
  const file = core.nextFile();
  core.files.set(file, read);
  try {
    const handle = guard(() => check(core.exports.dta_open(file, length, ENCODINGS[encoding])));
    core.opened();
    return handle;
  } catch (e) {
    core.files.delete(file);
    throw e;
  }
}

/** Close a handle of the current instance; may then replace it (see maybeReplace). */
export function close(handle: number): void {
  guard(() => core.exports.dta_close(handle));
  core.closed();
  core.maybeReplace();
}

export function metadataJson(handle: number): string {
  return guard(() => resultText(core.exports.dta_metadata(handle)));
}

/** A copy of the strL index's bytes (see dta_strl_index). */
export function strlIndex(handle: number): Uint8Array {
  return guard(() => {
    const ptr = check(core.exports.dta_strl_index(handle)) >>> 0;
    return new Uint8Array(core.exports.memory.buffer, ptr, core.exports.dta_result_len() >>> 0).slice();
  });
}

/** Adopt an exported strL index; it is copied into the module first. */
export function adoptStrlIndex(handle: number, index: Uint8Array): void {
  guard(() => {
    const ptr = put(index);
    try {
      check(core.exports.dta_adopt_strl_index(handle, ptr, index.length));
    } finally {
      core.exports.dta_free(ptr, index.length);
    }
  });
}

export function valueLabelsJson(handle: number): string {
  return guard(() => resultText(core.exports.dta_value_labels(handle)));
}

export function characteristicsJson(handle: number): string {
  return guard(() => resultText(core.exports.dta_characteristics(handle)));
}

/**
 * Read up to `count` rows into the handle; then `part` copies the
 * buffers out. Returns how many rows were read: the module stops once a
 * read holds 64 MiB.
 */
/** `read` flags: the first call of a read; code string columns. */
export const NEW_READ = 1;
export const DICTIONARY = 2;

export function read(handle: number, columns: number[], start: number, count: number, flags: number, maxStringBytes = -1): number {
  return guard(() => {
    const ptr = alloc(columns.length * 4);
    new Uint32Array(core.exports.memory.buffer, ptr, columns.length).set(columns);
    const n = core.exports.dta_read(handle, ptr, columns.length, start, count, flags, maxStringBytes);
    core.exports.dta_free(ptr, columns.length * 4);
    if (n < 0) check(0);
    return n;
  });
}

/** `read` for the rows listed, in their order. */
export function readAt(handle: number, columns: number[], rows: Float64Array, flags: number, maxStringBytes = -1): number {
  return guard(() => {
    const cols = put(Uint32Array.from(columns));
    let at = 0;
    try {
      at = put(rows);
      const n = core.exports.dta_read_at(handle, cols, columns.length, at, rows.length, flags, maxStringBytes);
      if (n < 0) check(0);
      return n;
    } finally {
      if (at !== 0) core.exports.dta_free(at, rows.byteLength);
      core.exports.dta_free(cols, columns.length * 4);
    }
  });
}

/** Free what a read kept between its calls (its dictionaries). */
export function readEnd(handle: number): void {
  guard(() => core.exports.dta_read_end(handle));
}

/** What read column `k` holds: 0 numbers, 1 plain strings, 2 dictionary codes. */
export function mode(handle: number, k: number): 0 | 1 | 2 {
  return guard(() => core.exports.dta_column_mode(handle, k)) as 0 | 1 | 2;
}

/**
 * A view of part `part` of read column `k` (see dta_column_part), in
 * module memory: valid until the next call that may allocate (a read,
 * open or write), so copy what you keep before making one.
 */
export function part(handle: number, k: number, kind: number, as: "f64"): Float64Array;
export function part(handle: number, k: number, kind: number, as: "u8"): Uint8Array;
export function part(handle: number, k: number, kind: number, as: "u32"): Uint32Array;
export function part(
  handle: number,
  k: number,
  kind: number,
  as: "f64" | "u8" | "u32",
): Float64Array | Uint8Array | Uint32Array {
  return guard(() => {
    const ptr = check(core.exports.dta_column_part(handle, k, kind)) >>> 0;
    const n = core.exports.dta_result_len() >>> 0;
    // Views are made after the call, since a call can grow (and so
    // replace) the module's memory.
    const buffer = core.exports.memory.buffer;
    if (as === "f64") return new Float64Array(buffer, ptr, n);
    if (as === "u32") return new Uint32Array(buffer, ptr, n);
    return new Uint8Array(buffer, ptr, n);
  });
}

export function forget(read: ReadAt): void {
  core.forget(read);
}

const utf8Encoder = new TextEncoder();

/** One column or label set to write, already in the module's terms. */
export type WritePart =
  | { kind: "numbers"; meta: string; storage: number; values: Float64Array; missing: Uint8Array }
  // `binary` makes the column strL: 1 where a value is binary bytes.
  | { kind: "strings"; meta: string; bytes: Uint8Array; ends: Uint32Array; binary?: Uint8Array }
  | { kind: "labels"; name: string; values: Float64Array; missing: Uint8Array; texts: Uint8Array; ends: Uint32Array }
  // NUL-separated variable, name and value of each characteristic.
  | { kind: "characteristics"; text: string }
  | { kind: "sortOrder"; indices: Uint32Array };

/**
 * Build a dataset of `nobs` rows from `parts` in the module and write it
 * to `sink`. `info` is the data label, timestamp and notes.
 */
export function write(nobs: number, parts: WritePart[], info: string[], sink: (bytes: Uint8Array) => void): void {
  guard(() => {
    try {
      writeParts(nobs, parts, info, sink);
    } catch (e) {
      // Drop the half-built dataset and the copies it holds.
      if (!(e instanceof WebAssembly.RuntimeError)) core.exports.dta_write_begin(0);
      throw e;
    }
  });
  core.maybeReplace();
}

function writeParts(nobs: number, parts: WritePart[], info: string[], sink: (bytes: Uint8Array) => void): void {
  core.exports.dta_write_begin(nobs);
  for (const part of parts) {
    const owned: [number, number][] = [];
    const own = (data: Uint8Array | Float64Array | Uint32Array) => {
      const ptr = put(data);
      owned.push([ptr, data.byteLength]);
      return ptr;
    };
    let ok: number;
    try {
      if (part.kind === "numbers") {
        const meta = utf8Encoder.encode(part.meta);
        ok = core.exports.dta_write_numbers(own(meta), meta.length, part.storage, own(part.values), own(part.missing));
      } else if (part.kind === "strings") {
        const meta = utf8Encoder.encode(part.meta);
        const binary = part.binary ? own(part.binary) : 0;
        ok = core.exports.dta_write_strings(own(meta), meta.length, own(part.bytes), part.bytes.length, own(part.ends), binary);
      } else if (part.kind === "characteristics") {
        const text = utf8Encoder.encode(part.text);
        ok = core.exports.dta_write_characteristics(own(text), text.length);
      } else if (part.kind === "sortOrder") {
        ok = core.exports.dta_write_sort_order(own(part.indices), part.indices.length);
      } else {
        const name = utf8Encoder.encode(part.name);
        ok = core.exports.dta_write_labels(
          own(name),
          name.length,
          part.values.length,
          own(part.values),
          own(part.missing),
          own(part.texts),
          part.texts.length,
          own(part.ends),
        );
      }
    } finally {
      for (const [ptr, len] of owned) core.exports.dta_free(ptr, len);
    }
    check(ok);
  }
  const file = core.nextFile();
  core.sinks.set(file, sink);
  const bytes = utf8Encoder.encode(info.join("\0"));
  const ptr = put(bytes);
  try {
    check(core.exports.dta_write_finish(file, ptr, bytes.length));
  } finally {
    core.exports.dta_free(ptr, bytes.length);
    core.sinks.delete(file);
  }
}

// Test builds only (js/test/memory.test.mjs bundles src with
// build/dta-test.wasm): lower the read budget and chunk size, and take
// or give back module memory.
export const test = {
  set(budget: number, chunkBytes: number, stringLimit = (1 << 29) - 24): void {
    core.exports.dta_test_set!(budget, chunkBytes, stringLimit);
  },
  alloc(len: number): number {
    return core.exports.dta_alloc(len) >>> 0;
  },
  free(ptr: number, len: number): void {
    core.exports.dta_free(ptr, len);
  },
  memoryBytes(): number {
    return core.memoryBytes();
  },
  replaceAbove(bytes: number): void {
    core.setReplaceAbove(bytes);
  },
  openHandles(): number {
    return core.openHandles();
  },
  generation(): number {
    return core.generation();
  },
  /** The module's export names, for the export-list test. */
  exportNames(): string[] {
    return Object.keys(core.exports);
  },
};
