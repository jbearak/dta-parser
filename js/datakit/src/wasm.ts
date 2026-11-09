// datakit's wasm module (Parquet and fixed-width text) and the raw calls
// into it. Everything above this file deals in JavaScript values;
// everything here deals in pointers. What it shares with dta-parser's
// module is in dta-parser's src/wasm-core.ts, bundled into this package.

import embedded from "../build/datakit.wasm";
import { makeCore, type CoreExports, type ReadAt } from "./_shared/wasm-core";

export type { ReadAt };

interface Exports extends CoreExports {
  pq_open(file: number, len: number, flags: number, cacheBytes: number): number;
  pq_close(handle: number): void;
  pq_info(handle: number, int64: number): number;
  pq_value_labels(handle: number): number;
  pq_chunks(handle: number): number;
  pq_characteristics(handle: number): number;
  pq_key_value(handle: number, name: number, len: number): number;
  pq_cache_stats(handle: number): number;
  pq_plan(handle: number, cols: number, ncols: number, start: number, count: number): number;
  pq_read(handle: number, cols: number, ncols: number, start: number, count: number, flags: number, maxText: number): number;
  pq_directory(handle: number): number;
  pq_read_end(handle: number): void;
  pq_write_begin(rows: number): void;
  pq_write_numbers(meta: number, metaLen: number, kind: number, unit: number, id: number, letters: number): number;
  pq_write_bigints(meta: number, metaLen: number, kind: number, unit: number, values: number, codes: number): number;
  pq_write_texts(meta: number, metaLen: number, binary: number, bytes: number, bytesLen: number, ends: number, missing: number): number;
  pq_write_text_codes(meta: number, metaLen: number, bytes: number, bytesLen: number, ends: number, nvalues: number, codes: number, codesLen: number): number;
  pq_write_categorical(
    meta: number,
    metaLen: number,
    ordered: number,
    codes: number,
    levels: number,
    levelsLen: number,
    ends: number,
    nlevels: number,
  ): number;
  pq_write_labels(name: number, nameLen: number, n: number, values: number, missing: number, texts: number, textsLen: number, ends: number): number;
  pq_write_characteristics(text: number, len: number): number;
  pq_write_sort(text: number, len: number): number;
  pq_write_finish(
    file: number,
    info: number,
    infoLen: number,
    compression: number,
    compressionLen: number,
    level: number,
    rowGroupRows: number,
    missingLetters: number,
  ): number;
  dta_fixed_width(
    setups: number,
    setupsLen: number,
    setupEnds: number,
    nSetups: number,
    data: number,
    dataLen: number,
    recodes: number,
    commentedFormats: number,
    sink: number,
  ): number;
  /** Test builds only. */
  dta_test_set?(): void;
}

const core = makeCore<Exports>(embedded, "datakit");

export function currentGeneration(): number {
  return core.generation();
}

export function forget(read: ReadAt): void {
  core.forget(read);
}

const { guard, check, resultText, put } = core;
const utf8Encoder = new TextEncoder();


/** Open a Parquet file through `read`; see pq_open for `flags`. */
export function pqOpen(read: ReadAt, length: number, flags: number, cacheBytes: number): number {
  const file = core.nextFile();
  core.files.set(file, read);
  try {
    const handle = guard(() => check(core.exports.pq_open(file, length, flags, cacheBytes)));
    core.opened();
    return handle;
  } catch (e) {
    core.files.delete(file);
    throw e;
  }
}

/** Close a Parquet handle of the current instance; may then replace it. */
export function pqClose(handle: number): void {
  guard(() => core.exports.pq_close(handle));
  core.closed();
  core.maybeReplace();
}

export function pqInfoJson(handle: number, int64: number): string {
  return guard(() => resultText(core.exports.pq_info(handle, int64)));
}

export function pqChunksJson(handle: number): string {
  return guard(() => resultText(core.exports.pq_chunks(handle)));
}

export function pqValueLabelsJson(handle: number): string {
  return guard(() => resultText(core.exports.pq_value_labels(handle)));
}

export function pqCharacteristicsJson(handle: number): string {
  return guard(() => resultText(core.exports.pq_characteristics(handle)));
}

/** A key-value metadata entry's bytes, or undefined when there is none. */
export function pqKeyValue(handle: number, key: string): Uint8Array | undefined {
  return guard(() => {
    const name = utf8Encoder.encode(key);
    const at = put(name);
    try {
      const ptr = core.exports.pq_key_value(handle, at, name.length) >>> 0;
      if (ptr === 0) {
        if (core.exports.dta_error_kind() !== 0) check(0);
        return undefined;
      }
      return new Uint8Array(core.exports.memory.buffer, ptr, core.exports.dta_result_len() >>> 0).slice();
    } finally {
      core.exports.dta_free(at, name.length);
    }
  });
}

/** Bytes held by the page cache, its hits and misses. */
export function pqCacheStats(handle: number): [number, number, number] {
  return guard(() => {
    const ptr = check(core.exports.pq_cache_stats(handle)) >>> 0;
    const v = new Float64Array(core.exports.memory.buffer.slice(ptr, ptr + 24));
    return [v[0], v[1], v[2]];
  });
}

/** The byte ranges a read needs, as start, end pairs. */
export function pqPlan(handle: number, columns: number[], start: number, count: number): Float64Array {
  return guard(() => {
    const cols = put(Uint32Array.from(columns));
    try {
      const ptr = check(core.exports.pq_plan(handle, cols, columns.length, start, count)) >>> 0;
      const n = core.exports.dta_result_len() >>> 0;
      return new Float64Array(core.exports.memory.buffer.slice(ptr, ptr + 8 * n));
    } finally {
      core.exports.dta_free(cols, Math.max(1, columns.length * 4));
    }
  });
}

/**
 * Read rows of the columns into the handle; returns the rows read. The
 * directory (`pqDirectory`) then says where each column's buffers are.
 */
/** What `pqRead` returns when the call's text passed `maxText` bytes. */
export const OVER_BUDGET = -2;

/** Read into the handle; the rows read, or `OVER_BUDGET` when the text gathered passed `maxText` bytes (0: no limit). */
export function pqRead(handle: number, columns: number[], start: number, count: number, flags: number, maxText = 0): number {
  return guard(() => {
    const cols = put(Uint32Array.from(columns));
    try {
      const n = core.exports.pq_read(handle, cols, columns.length, start, count, flags, maxText);
      if (n === OVER_BUDGET) return n;
      if (n < 0) check(0);
      return n;
    } finally {
      core.exports.dta_free(cols, Math.max(1, columns.length * 4));
    }
  });
}

/** A copy of the last read's directory: ten numbers per column. */
export function pqDirectory(handle: number): Uint32Array {
  return guard(() => {
    const ptr = check(core.exports.pq_directory(handle)) >>> 0;
    const n = core.exports.dta_result_len() >>> 0;
    return new Uint32Array(core.exports.memory.buffer.slice(ptr, ptr + 4 * n));
  });
}

/** A view of `n` elements at `ptr` in module memory, valid until the next call. */
export function memView(ptr: number, n: number, as: "f64"): Float64Array;
export function memView(ptr: number, n: number, as: "u8"): Uint8Array;
export function memView(ptr: number, n: number, as: "u32"): Uint32Array;
export function memView(ptr: number, n: number, as: "i32"): Int32Array;
export function memView(ptr: number, n: number, as: "i64"): BigInt64Array;
export function memView(ptr: number, n: number, as: "u64"): BigUint64Array;
export function memView(
  ptr: number,
  n: number,
  as: "f64" | "u8" | "u32" | "i32" | "i64" | "u64",
): Float64Array | Uint8Array | Uint32Array | Int32Array | BigInt64Array | BigUint64Array {
  const buffer = core.exports.memory.buffer;
  if (n === 0) ptr = 0;
  switch (as) {
    case "f64":
      return new Float64Array(buffer, ptr, n);
    case "u32":
      return new Uint32Array(buffer, ptr, n);
    case "i32":
      return new Int32Array(buffer, ptr, n);
    case "i64":
      return new BigInt64Array(buffer, ptr, n);
    case "u64":
      return new BigUint64Array(buffer, ptr, n);
    default:
      return new Uint8Array(buffer, ptr, n);
  }
}

export function pqReadEnd(handle: number): void {
  guard(() => core.exports.pq_read_end(handle));
}

/** One column (or label set, or table-level part) to write as Parquet, in the module's terms. */
export type ParquetPart =
  | { kind: "numbers"; meta: string; type: number; unit: number; values: Float64Array; missing: Uint8Array }
  | { kind: "bigints"; meta: string; type: number; unit: number; values: BigInt64Array; missing: Uint8Array }
  | { kind: "texts"; meta: string; binary: boolean; bytes: Uint8Array; ends: Uint32Array; missing: Uint8Array }
  // Distinct values (bytes end to end, and their ends) and a code per row, -1 for a null.
  | { kind: "textCodes"; meta: string; bytes: Uint8Array; ends: Uint32Array; codes: Int32Array }
  | { kind: "categorical"; meta: string; ordered: boolean; codes: Int32Array; levels: Uint8Array; ends: Uint32Array }
  | { kind: "labels"; name: string; values: Float64Array; missing: Uint8Array; texts: Uint8Array; ends: Uint32Array }
  | { kind: "characteristics"; text: string }
  | { kind: "sort"; text: string };

/** Write a Parquet table of `rows` rows built from `parts` to `sink`. */
/**
 * Whether a column's missing codes hold `.a` to `.z`, for the writer,
 * which otherwise reads every value once more to find out: 1 none, 2
 * some, 0 a code it must report (past `.z`, or a letter where a column
 * cannot be DOUBLE: bool and int64, kinds 5 and 8).
 */
function lettersIn(missing: Uint8Array, kind: number): number {
  // Most columns have no code over 1: look four at a time first (a byte
  // over 1 has a bit set besides its lowest).
  const n = missing.length;
  let i = 0;
  const head = Math.min(n, (4 - (missing.byteOffset & 3)) & 3);
  let any = false;
  for (; i < head && !any; i++) any = missing[i] > 1;
  if (!any) {
    const words = new Uint32Array(missing.buffer, missing.byteOffset + i, (n - i) >>> 2);
    for (let j = 0; j < words.length && !any; j++) any = (words[j] & 0xfefefefe) !== 0;
    for (i += 4 * words.length; i < n && !any; i++) any = missing[i] > 1;
  }
  if (!any) return 1;
  if (kind === 5 || kind === 8) return 0;
  for (let k = 0; k < n; k++) if (missing[k] > 27) return 0;
  return 2;
}

export function pqWrite(
  rows: number,
  parts: (ParquetPart | (() => ParquetPart))[],
  info: string[],
  options: { compression: string; level: number; rowGroupRows: number; missingLetters: boolean },
  sink: (bytes: Uint8Array) => void,
): void {
  guard(() => {
    try {
      pqWriteParts(rows, parts, info, options, sink);
    } catch (e) {
      core.fills.clear();
      if (!(e instanceof WebAssembly.RuntimeError)) core.exports.pq_write_begin(0);
      throw e;
    }
  });
  core.maybeReplace();
}

function pqWriteParts(
  rows: number,
  parts: (ParquetPart | (() => ParquetPart))[],
  info: string[],
  options: { compression: string; level: number; rowGroupRows: number; missingLetters: boolean },
  sink: (bytes: Uint8Array) => void,
): void {
  core.exports.pq_write_begin(rows);
  // A part given as a function is made only now, just before it goes
  // into the module, so a table's text is not all packed at once.
  for (const made of parts) {
    const part = typeof made === "function" ? made() : made;
    const owned: [number, number][] = [];
    const own = (data: Uint8Array | Float64Array | Uint32Array | Int32Array | BigInt64Array) => {
      const ptr = put(data);
      owned.push([ptr, data.byteLength]);
      return ptr;
    };
    const text = (t: string): [number, number] => {
      const b = utf8Encoder.encode(t);
      return [own(b), b.length];
    };
    let ok: number;
    try {
      switch (part.kind) {
        case "numbers": {
          // Not copied in: the module asks for a block at a time as it
          // writes (host_fill).
          const id = core.fills.size + 1;
          core.fills.set(id, part);
          ok = core.exports.pq_write_numbers(...text(part.meta), part.type, part.unit, id, lettersIn(part.missing, part.type));
          break;
        }
        case "bigints":
          ok = core.exports.pq_write_bigints(...text(part.meta), part.type, part.unit, own(part.values), own(part.missing));
          break;
        case "texts": {
          // The bytes are the module's once handed over (it frees them),
          // so they are put in last, after anything that could fail.
          const [meta, metaLen] = text(part.meta);
          const ends = own(part.ends);
          const missing = own(part.missing);
          ok = core.exports.pq_write_texts(meta, metaLen, part.binary ? 1 : 0, put(part.bytes), part.bytes.length, ends, missing);
          break;
        }
        case "textCodes": {
          const [meta, metaLen] = text(part.meta);
          const bytes = own(part.bytes);
          const ends = own(part.ends);
          // Handed over, as the texts' bytes are.
          ok = core.exports.pq_write_text_codes(meta, metaLen, bytes, part.bytes.length, ends, part.ends.length, put(part.codes), part.codes.byteLength);
          break;
        }
        case "categorical":
          ok = core.exports.pq_write_categorical(...text(part.meta), part.ordered ? 1 : 0, own(part.codes), own(part.levels), part.levels.length, own(part.ends), part.ends.length);
          break;
        case "labels":
          ok = core.exports.pq_write_labels(...text(part.name), part.values.length, own(part.values), own(part.missing), own(part.texts), part.texts.length, own(part.ends));
          break;
        case "characteristics":
          ok = core.exports.pq_write_characteristics(...text(part.text));
          break;
        default:
          ok = core.exports.pq_write_sort(...text(part.text));
      }
    } finally {
      for (const [ptr, len] of owned) core.exports.dta_free(ptr, len);
    }
    check(ok);
  }
  const file = core.nextFile();
  core.sinks.set(file, sink);
  const infoBytes = utf8Encoder.encode(info.join("\0"));
  const codec = utf8Encoder.encode(options.compression);
  const a = put(infoBytes);
  let b = 0;
  try {
    b = put(codec);
    check(core.exports.pq_write_finish(file, a, infoBytes.length, b, codec.length, options.level, options.rowGroupRows, options.missingLetters ? 1 : 0));
  } finally {
    core.exports.dta_free(a, infoBytes.length);
    if (b !== 0) core.exports.dta_free(b, codec.length);
    core.sinks.delete(file);
    core.fills.clear();
  }
}

// ------------------------------------------------------------ fixed width

/** `recodes` as the module takes it. */
export const RECODES = { setup: 0, tagged: 1, none: 2 } as const;

/**
 * Data already in module memory, put there by `fill` (straight from a
 * file, with no JavaScript copy), for `fixedWidth`.
 */
export interface ModuleBytes {
  ptr: number;
  len: number;
}

/** Room for `len` bytes, which `fill(view)` writes into; free with `freeBytes`. */
export function putBytes(len: number, fill: (view: Uint8Array) => void): ModuleBytes {
  return guard(() => {
    const ptr = core.alloc(len);
    try {
      // A view made after the allocation, which can grow the memory.
      fill(new Uint8Array(core.exports.memory.buffer, ptr, len));
    } catch (e) {
      core.exports.dta_free(ptr, len);
      throw e;
    }
    return { ptr, len };
  });
}

export function freeBytes(b: ModuleBytes): void {
  guard(() => core.exports.dta_free(b.ptr, b.len));
}

/**
 * Convert fixed-width `data` (in module memory) as `setups` describe it,
 * handing the release 118 file to `sink` in order. Returns the warnings.
 */
export function fixedWidth(
  setups: Uint8Array[],
  data: ModuleBytes,
  recodes: number,
  commentedFormats: boolean,
  sink: (bytes: Uint8Array) => void,
): string[] {
  return guard(() => {
    const total = setups.reduce((n, s) => n + s.length, 0);
    const joined = new Uint8Array(total);
    const ends = new Uint32Array(setups.length);
    let at = 0;
    setups.forEach((s, k) => {
      joined.set(s, at);
      at += s.length;
      ends[k] = at;
    });
    const a = put(joined);
    let b = 0;
    const file = core.nextFile();
    core.sinks.set(file, sink);
    try {
      b = put(ends);
      const json = resultText(
        core.exports.dta_fixed_width(a, joined.length, b, setups.length, data.ptr, data.len, recodes, commentedFormats ? 1 : 0, file),
      );
      return JSON.parse(json) as string[];
    } finally {
      core.exports.dta_free(a, Math.max(1, joined.length));
      if (b !== 0) core.exports.dta_free(b, ends.byteLength);
      core.sinks.delete(file);
    }
  });
}

/** Replace the instance, giving its memory back, if no Parquet reader is open on it; whether it did. */
export function giveMemoryBack(): boolean {
  return core.replaceIfIdle();
}

// Test builds only (datakit/test/memory.test.mjs bundles src with
// build/datakit-test.wasm).
export const test = {
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
