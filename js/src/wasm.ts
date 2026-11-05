// The wasm module and the raw calls into it. Everything above this file
// deals in JavaScript values; everything here deals in pointers.

import embedded from "../build/dta.wasm";
import { dtaError, type ErrorCode } from "./errors";
import { inflateRaw } from "./inflate";

/**
 * The module's bytes. build.mjs embeds them deflated (a 4-byte length,
 * then raw DEFLATE): a quarter the size, and parsing the bundle's
 * base64 text cost Node about 10 MB more than the module itself. Node
 * inflates with its zlib; elsewhere (a browser) `inflateRaw` does. A
 * bundle made with the plain module (the tests' capped build) passes
 * through.
 */
function moduleBytes(b: Uint8Array<ArrayBuffer>): Uint8Array {
  if (b[0] === 0 && b[1] === 0x61 && b[2] === 0x73 && b[3] === 0x6d) return b;
  const size = (b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)) >>> 0;
  const proc = (globalThis as { process?: { getBuiltinModule?: (id: string) => unknown } }).process;
  const zlib = proc?.getBuiltinModule?.("node:zlib") as { inflateRawSync(b: Uint8Array): Uint8Array } | undefined;
  // Compiled from where zlib left it: a copy into a buffer of its own
  // cost 2 MB more at the peak.
  if (zlib) return zlib.inflateRawSync(b.subarray(4));
  return inflateRaw(b.subarray(4), size);
}

interface Exports {
  memory: WebAssembly.Memory;
  dta_alloc(len: number): number;
  dta_free(ptr: number, len: number): void;
  dta_error(): number;
  dta_error_kind(): number;
  dta_result_len(): number;
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
}

/** Fills `into` with the file's bytes starting at `offset`. */
export type ReadAt = (into: Uint8Array, offset: number) => void;

const files = new Map<number, ReadAt>();
/** Where the file being written goes; takes each run of bytes. */
const sinks = new Map<number, (bytes: Uint8Array) => void>();
/** The number columns of the Parquet table being written, which the module asks for a block at a time. */
const fills = new Map<number, { values: Float64Array; missing: Uint8Array }>();
let nextFile = 1;
/** What the last `ReadAt` or sink threw, for the `DTA_IO` error's cause. */
let hostError: unknown;

// Synchronous compile and instantiate: Node allows it for any size, and
// it keeps the whole API synchronous.
// The bytes are not kept: only the compiled module is.
const module = new WebAssembly.Module(moduleBytes(embedded) as Uint8Array<ArrayBuffer>);
const imports = {
  env: {
    // Never lets a JavaScript exception unwind through wasm frames; the
    // module reports the failure, and `check` attaches the exception.
    // Pointers and lengths arrive as signed i32: `>>> 0` keeps those past
    // 2 GiB positive.
    host_read(file: number, ptr: number, len: number, offset: number): number {
      try {
        files.get(file)!(new Uint8Array(wasm.memory.buffer, ptr >>> 0, len >>> 0), offset);
        return 0;
      } catch (e) {
        hostError = e;
        return 1;
      }
    },
    host_fill(id: number, first: number, n: number, values: number, codes: number): number {
      try {
        const src = fills.get(id)!;
        const buffer = wasm.memory.buffer;
        new Float64Array(buffer, values >>> 0, n >>> 0).set(src.values.subarray(first, first + (n >>> 0)));
        new Uint8Array(buffer, codes >>> 0, n >>> 0).set(src.missing.subarray(first, first + (n >>> 0)));
        return 0;
      } catch (e) {
        hostError = e;
        return 1;
      }
    },
    host_write(file: number, ptr: number, len: number): number {
      try {
        sinks.get(file)!(new Uint8Array(wasm.memory.buffer, ptr >>> 0, len >>> 0));
        return 0;
      } catch (e) {
        hostError = e;
        return 1;
      }
    },
  },
};
let wasm = new WebAssembly.Instance(module, imports).exports as unknown as Exports;

/**
 * Counts module instances. We replace an instance when a trap (a bug:
 * damaged files give errors, not traps) leaves it unusable, and to give
 * memory back (wasm memory never shrinks): readers opened on the old
 * one see the count change and report themselves closed.
 */
let generation = 0;

export function currentGeneration(): number {
  return generation;
}

/** Readers open on this instance; it is replaced only when none are. */
let openHandles = 0;
/** Calls into the module running now: at most one (no re-entry). */
let depth = 0;
/** Memory past which an instance is replaced once nothing uses it. */
let replaceAbove = 256 * 2 ** 20;

function replaceInstance(): void {
  generation++;
  files.clear();
  openHandles = 0;
  wasm = new WebAssembly.Instance(module, imports).exports as unknown as Exports;
}

/**
 * Give the instance's memory back if it has grown past `replaceAbove`
 * and no reader is open on it and no call is running.
 */
function maybeReplace(): void {
  if (openHandles === 0 && depth === 0 && wasm.memory.buffer.byteLength > replaceAbove) replaceInstance();
}

function guard<T>(f: () => T): T {
  // The module's state is in use for the whole of a call, including
  // while it waits on a ReadAt callback or a write sink, so those may
  // not call back into the package.
  if (depth > 0) {
    throw dtaError("DTA_INVALID", "dta-parser was called from inside a ReadAt callback or write sink; call it after that returns", undefined, TypeError);
  }
  depth++;
  try {
    return f();
  } catch (e) {
    if (e instanceof WebAssembly.RuntimeError) {
      replaceInstance();
      throw dtaError("DTA_INTERNAL", `dta-parser failed (${e.message}); files it had open are now closed`, e);
    }
    throw e;
  } finally {
    depth--;
  }
}

// ignoreBOM: a value that starts with U+FEFF keeps it.
const utf8 = new TextDecoder("utf-8", { ignoreBOM: true });

/** The codes of `dta_error_kind`'s kinds, 1 to 7. */
const CODES: ErrorCode[] = ["DTA_CORRUPT", "DTA_TOO_LARGE", "DTA_IO", "DTA_INVALID", "DTA_OUT_OF_RANGE", "DTA_INTERNAL", "DTA_CLOSED"];

function check<T extends number>(result: T): T {
  if (result === 0) {
    const kind = wasm.dta_error_kind();
    const ptr = wasm.dta_error() >>> 0;
    const message = utf8.decode(new Uint8Array(wasm.memory.buffer, ptr, wasm.dta_result_len() >>> 0));
    const code = CODES[kind - 1] ?? "DTA_INTERNAL";
    const cause = code === "DTA_IO" ? hostError : undefined;
    hostError = undefined;
    // Arguments the module rejects (data that cannot be written) are
    // values outside what the format holds: RangeError.
    const errorClass = code === "DTA_OUT_OF_RANGE" || code === "DTA_INVALID" ? RangeError : Error;
    throw dtaError(code, message || "dta-parser failed", cause, errorClass);
  }
  return result;
}

/** The text a call left as its result. */
function resultText(ptr: number): string {
  check(ptr);
  return utf8.decode(new Uint8Array(wasm.memory.buffer, ptr >>> 0, wasm.dta_result_len() >>> 0));
}

export const ENCODINGS = { "windows-1252": 0, latin1: 1, "utf-8": 2 } as const;
export type EncodingName = keyof typeof ENCODINGS;

export function open(read: ReadAt, length: number, encoding: EncodingName): number {
  if (!Object.hasOwn(ENCODINGS, encoding)) {
    throw dtaError("DTA_INVALID", `unknown encoding ${JSON.stringify(encoding)}; use ${Object.keys(ENCODINGS).join(", ")}`, undefined, TypeError);
  }
  const file = nextFile++;
  files.set(file, read);
  try {
    const handle = guard(() => check(wasm.dta_open(file, length, ENCODINGS[encoding])));
    openHandles++;
    return handle;
  } catch (e) {
    files.delete(file);
    throw e;
  }
}

/** Close a handle of the current instance; may then replace it (see maybeReplace). */
export function close(handle: number): void {
  guard(() => wasm.dta_close(handle));
  openHandles--;
  maybeReplace();
}

export function metadataJson(handle: number): string {
  return guard(() => resultText(wasm.dta_metadata(handle)));
}

/** A copy of the strL index's bytes (see dta_strl_index). */
export function strlIndex(handle: number): Uint8Array {
  return guard(() => {
    const ptr = check(wasm.dta_strl_index(handle)) >>> 0;
    return new Uint8Array(wasm.memory.buffer, ptr, wasm.dta_result_len() >>> 0).slice();
  });
}

/** Adopt an exported strL index; it is copied into the module first. */
export function adoptStrlIndex(handle: number, index: Uint8Array): void {
  guard(() => {
    const ptr = put(index);
    try {
      check(wasm.dta_adopt_strl_index(handle, ptr, index.length));
    } finally {
      wasm.dta_free(ptr, index.length);
    }
  });
}

export function valueLabelsJson(handle: number): string {
  return guard(() => resultText(wasm.dta_value_labels(handle)));
}

export function characteristicsJson(handle: number): string {
  return guard(() => resultText(wasm.dta_characteristics(handle)));
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
    new Uint32Array(wasm.memory.buffer, ptr, columns.length).set(columns);
    const n = wasm.dta_read(handle, ptr, columns.length, start, count, flags, maxStringBytes);
    wasm.dta_free(ptr, columns.length * 4);
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
      const n = wasm.dta_read_at(handle, cols, columns.length, at, rows.length, flags, maxStringBytes);
      if (n < 0) check(0);
      return n;
    } finally {
      if (at !== 0) wasm.dta_free(at, rows.byteLength);
      wasm.dta_free(cols, columns.length * 4);
    }
  });
}

/** Free what a read kept between its calls (its dictionaries). */
export function readEnd(handle: number): void {
  guard(() => wasm.dta_read_end(handle));
}

/** What read column `k` holds: 0 numbers, 1 plain strings, 2 dictionary codes. */
export function mode(handle: number, k: number): 0 | 1 | 2 {
  return guard(() => wasm.dta_column_mode(handle, k)) as 0 | 1 | 2;
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
    const ptr = check(wasm.dta_column_part(handle, k, kind)) >>> 0;
    const n = wasm.dta_result_len() >>> 0;
    // Views are made after the call, since a call can grow (and so
    // replace) the module's memory.
    const buffer = wasm.memory.buffer;
    if (as === "f64") return new Float64Array(buffer, ptr, n);
    if (as === "u32") return new Uint32Array(buffer, ptr, n);
    return new Uint8Array(buffer, ptr, n);
  });
}

export function forget(read: ReadAt): void {
  for (const [file, r] of files) if (r === read) files.delete(file);
}

const utf8Encoder = new TextEncoder();

/** Room for `len` bytes in module memory, or DTA_TOO_LARGE. */
function alloc(len: number): number {
  const ptr = wasm.dta_alloc(len) >>> 0;
  if (ptr === 0) throw dtaError("DTA_TOO_LARGE", `${len} bytes do not fit in module memory`);
  return ptr;
}

/** Copy `data` into module memory; returns its address. Free with `free`. */
function put(data: Uint8Array | Float64Array | Uint32Array | Int32Array | BigInt64Array): number {
  const bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  const ptr = alloc(bytes.length);
  new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
  return ptr;
}

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
      if (!(e instanceof WebAssembly.RuntimeError)) wasm.dta_write_begin(0);
      throw e;
    }
  });
  maybeReplace();
}

function writeParts(nobs: number, parts: WritePart[], info: string[], sink: (bytes: Uint8Array) => void): void {
  wasm.dta_write_begin(nobs);
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
        ok = wasm.dta_write_numbers(own(meta), meta.length, part.storage, own(part.values), own(part.missing));
      } else if (part.kind === "strings") {
        const meta = utf8Encoder.encode(part.meta);
        const binary = part.binary ? own(part.binary) : 0;
        ok = wasm.dta_write_strings(own(meta), meta.length, own(part.bytes), part.bytes.length, own(part.ends), binary);
      } else if (part.kind === "characteristics") {
        const text = utf8Encoder.encode(part.text);
        ok = wasm.dta_write_characteristics(own(text), text.length);
      } else if (part.kind === "sortOrder") {
        ok = wasm.dta_write_sort_order(own(part.indices), part.indices.length);
      } else {
        const name = utf8Encoder.encode(part.name);
        ok = wasm.dta_write_labels(
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
      for (const [ptr, len] of owned) wasm.dta_free(ptr, len);
    }
    check(ok);
  }
  const file = nextFile++;
  sinks.set(file, sink);
  const bytes = utf8Encoder.encode(info.join("\0"));
  const ptr = put(bytes);
  try {
    check(wasm.dta_write_finish(file, ptr, bytes.length));
  } finally {
    wasm.dta_free(ptr, bytes.length);
    sinks.delete(file);
  }
}

// ---------------------------------------------------------------- Parquet

/** Open a Parquet file through `read`; see pq_open for `flags`. */
export function pqOpen(read: ReadAt, length: number, flags: number, cacheBytes: number): number {
  const file = nextFile++;
  files.set(file, read);
  try {
    const handle = guard(() => check(wasm.pq_open(file, length, flags, cacheBytes)));
    openHandles++;
    return handle;
  } catch (e) {
    files.delete(file);
    throw e;
  }
}

/** Close a Parquet handle of the current instance; may then replace it. */
export function pqClose(handle: number): void {
  guard(() => wasm.pq_close(handle));
  openHandles--;
  maybeReplace();
}

export function pqInfoJson(handle: number, int64: number): string {
  return guard(() => resultText(wasm.pq_info(handle, int64)));
}

export function pqChunksJson(handle: number): string {
  return guard(() => resultText(wasm.pq_chunks(handle)));
}

export function pqValueLabelsJson(handle: number): string {
  return guard(() => resultText(wasm.pq_value_labels(handle)));
}

export function pqCharacteristicsJson(handle: number): string {
  return guard(() => resultText(wasm.pq_characteristics(handle)));
}

/** A key-value metadata entry's bytes, or undefined when there is none. */
export function pqKeyValue(handle: number, key: string): Uint8Array | undefined {
  return guard(() => {
    const name = utf8Encoder.encode(key);
    const at = put(name);
    try {
      const ptr = wasm.pq_key_value(handle, at, name.length) >>> 0;
      if (ptr === 0) {
        if (wasm.dta_error_kind() !== 0) check(0);
        return undefined;
      }
      return new Uint8Array(wasm.memory.buffer, ptr, wasm.dta_result_len() >>> 0).slice();
    } finally {
      wasm.dta_free(at, name.length);
    }
  });
}

/** Bytes held by the page cache, its hits and misses. */
export function pqCacheStats(handle: number): [number, number, number] {
  return guard(() => {
    const ptr = check(wasm.pq_cache_stats(handle)) >>> 0;
    const v = new Float64Array(wasm.memory.buffer.slice(ptr, ptr + 24));
    return [v[0], v[1], v[2]];
  });
}

/** The byte ranges a read needs, as start, end pairs. */
export function pqPlan(handle: number, columns: number[], start: number, count: number): Float64Array {
  return guard(() => {
    const cols = put(Uint32Array.from(columns));
    try {
      const ptr = check(wasm.pq_plan(handle, cols, columns.length, start, count)) >>> 0;
      const n = wasm.dta_result_len() >>> 0;
      return new Float64Array(wasm.memory.buffer.slice(ptr, ptr + 8 * n));
    } finally {
      wasm.dta_free(cols, Math.max(1, columns.length * 4));
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
      const n = wasm.pq_read(handle, cols, columns.length, start, count, flags, maxText);
      if (n === OVER_BUDGET) return n;
      if (n < 0) check(0);
      return n;
    } finally {
      wasm.dta_free(cols, Math.max(1, columns.length * 4));
    }
  });
}

/** A copy of the last read's directory: ten numbers per column. */
export function pqDirectory(handle: number): Uint32Array {
  return guard(() => {
    const ptr = check(wasm.pq_directory(handle)) >>> 0;
    const n = wasm.dta_result_len() >>> 0;
    return new Uint32Array(wasm.memory.buffer.slice(ptr, ptr + 4 * n));
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
  const buffer = wasm.memory.buffer;
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
  guard(() => wasm.pq_read_end(handle));
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
      fills.clear();
      if (!(e instanceof WebAssembly.RuntimeError)) wasm.pq_write_begin(0);
      throw e;
    }
  });
  maybeReplace();
}

function pqWriteParts(
  rows: number,
  parts: (ParquetPart | (() => ParquetPart))[],
  info: string[],
  options: { compression: string; level: number; rowGroupRows: number; missingLetters: boolean },
  sink: (bytes: Uint8Array) => void,
): void {
  wasm.pq_write_begin(rows);
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
          const id = fills.size + 1;
          fills.set(id, part);
          ok = wasm.pq_write_numbers(...text(part.meta), part.type, part.unit, id, lettersIn(part.missing, part.type));
          break;
        }
        case "bigints":
          ok = wasm.pq_write_bigints(...text(part.meta), part.type, part.unit, own(part.values), own(part.missing));
          break;
        case "texts": {
          // The bytes are the module's once handed over (it frees them),
          // so they are put in last, after anything that could fail.
          const [meta, metaLen] = text(part.meta);
          const ends = own(part.ends);
          const missing = own(part.missing);
          ok = wasm.pq_write_texts(meta, metaLen, part.binary ? 1 : 0, put(part.bytes), part.bytes.length, ends, missing);
          break;
        }
        case "textCodes": {
          const [meta, metaLen] = text(part.meta);
          const bytes = own(part.bytes);
          const ends = own(part.ends);
          // Handed over, as the texts' bytes are.
          ok = wasm.pq_write_text_codes(meta, metaLen, bytes, part.bytes.length, ends, part.ends.length, put(part.codes), part.codes.byteLength);
          break;
        }
        case "categorical":
          ok = wasm.pq_write_categorical(...text(part.meta), part.ordered ? 1 : 0, own(part.codes), own(part.levels), part.levels.length, own(part.ends), part.ends.length);
          break;
        case "labels":
          ok = wasm.pq_write_labels(...text(part.name), part.values.length, own(part.values), own(part.missing), own(part.texts), part.texts.length, own(part.ends));
          break;
        case "characteristics":
          ok = wasm.pq_write_characteristics(...text(part.text));
          break;
        default:
          ok = wasm.pq_write_sort(...text(part.text));
      }
    } finally {
      for (const [ptr, len] of owned) wasm.dta_free(ptr, len);
    }
    check(ok);
  }
  const file = nextFile++;
  sinks.set(file, sink);
  const infoBytes = utf8Encoder.encode(info.join("\0"));
  const codec = utf8Encoder.encode(options.compression);
  const a = put(infoBytes);
  let b = 0;
  try {
    b = put(codec);
    check(wasm.pq_write_finish(file, a, infoBytes.length, b, codec.length, options.level, options.rowGroupRows, options.missingLetters ? 1 : 0));
  } finally {
    wasm.dta_free(a, infoBytes.length);
    if (b !== 0) wasm.dta_free(b, codec.length);
    sinks.delete(file);
    fills.clear();
  }
}

// Test builds only (js/test/memory.test.mjs bundles src with
// build/dta-test.wasm): lower the read budget and chunk size, and take
// or give back module memory.
export const test = {
  set(budget: number, chunkBytes: number, stringLimit = (1 << 29) - 24): void {
    wasm.dta_test_set!(budget, chunkBytes, stringLimit);
  },
  alloc(len: number): number {
    return wasm.dta_alloc(len) >>> 0;
  },
  free(ptr: number, len: number): void {
    wasm.dta_free(ptr, len);
  },
  memoryBytes(): number {
    return wasm.memory.buffer.byteLength;
  },
  replaceAbove(bytes: number): void {
    replaceAbove = bytes;
  },
  openHandles(): number {
    return openHandles;
  },
  generation(): number {
    return generation;
  },
};
