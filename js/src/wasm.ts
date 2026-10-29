// The wasm module and the raw calls into it. Everything above this file
// deals in JavaScript values; everything here deals in pointers.

import wasmBytes from "../build/dta.wasm";

interface Exports {
  memory: WebAssembly.Memory;
  dta_alloc(len: number): number;
  dta_free(ptr: number, len: number): void;
  dta_error(): number;
  dta_result_len(): number;
  dta_open(file: number, len: number, encoding: number): number;
  dta_close(handle: number): void;
  dta_metadata(handle: number): number;
  dta_value_labels(handle: number): number;
  dta_characteristics(handle: number): number;
  dta_read(handle: number, cols: number, ncols: number, start: number, count: number): number;
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
}

/** Fills `into` with the file's bytes starting at `offset`. */
export type ReadAt = (into: Uint8Array, offset: number) => void;

const files = new Map<number, ReadAt>();
/** Where the file being written goes; takes each run of bytes. */
const sinks = new Map<number, (bytes: Uint8Array) => void>();
let nextFile = 1;

// Synchronous compile and instantiate: Node allows it for any size, and
// it keeps the whole API synchronous.
const module = new WebAssembly.Module(wasmBytes);
const imports = {
  env: {
    // Never lets a JavaScript exception unwind through wasm frames.
    host_read(file: number, ptr: number, len: number, offset: number): number {
      try {
        files.get(file)!(new Uint8Array(wasm.memory.buffer, ptr, len), offset);
        return 0;
      } catch {
        return 1;
      }
    },
    host_write(file: number, ptr: number, len: number): number {
      try {
        sinks.get(file)!(new Uint8Array(wasm.memory.buffer, ptr, len));
        return 0;
      } catch {
        return 1;
      }
    },
  },
};
let wasm = new WebAssembly.Instance(module, imports).exports as unknown as Exports;

/**
 * Counts module instances. A trap (a bug: damaged files give errors, not
 * traps) leaves an instance unusable, so we replace it; readers opened on
 * the old one see the count change and report themselves closed.
 */
let generation = 0;

export function currentGeneration(): number {
  return generation;
}

function guard<T>(f: () => T): T {
  try {
    return f();
  } catch (e) {
    if (e instanceof WebAssembly.RuntimeError) {
      generation++;
      files.clear();
      wasm = new WebAssembly.Instance(module, imports).exports as unknown as Exports;
      throw new Error(`dta-parser failed (${e.message}); files it had open are now closed`);
    }
    throw e;
  }
}

const utf8 = new TextDecoder("utf-8");

function check<T extends number>(result: T): T {
  if (result === 0) {
    const ptr = wasm.dta_error();
    const message = utf8.decode(new Uint8Array(wasm.memory.buffer, ptr, wasm.dta_result_len()));
    throw new Error(message || "dta-parser failed");
  }
  return result;
}

/** The text a call left as its result. */
function resultText(ptr: number): string {
  check(ptr);
  return utf8.decode(new Uint8Array(wasm.memory.buffer, ptr, wasm.dta_result_len()));
}

export const ENCODINGS = { "windows-1252": 0, latin1: 1, "utf-8": 2 } as const;
export type EncodingName = keyof typeof ENCODINGS;

export function open(read: ReadAt, length: number, encoding: EncodingName): number {
  const file = nextFile++;
  files.set(file, read);
  try {
    return guard(() => check(wasm.dta_open(file, length, ENCODINGS[encoding])));
  } catch (e) {
    files.delete(file);
    throw e;
  }
}

export function close(handle: number): void {
  guard(() => wasm.dta_close(handle));
}

export function metadataJson(handle: number): string {
  return guard(() => resultText(wasm.dta_metadata(handle)));
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
export function read(handle: number, columns: number[], start: number, count: number): number {
  return guard(() => {
    const ptr = wasm.dta_alloc(columns.length * 4);
    new Uint32Array(wasm.memory.buffer, ptr, columns.length).set(columns);
    const n = wasm.dta_read(handle, ptr, columns.length, start, count);
    wasm.dta_free(ptr, columns.length * 4);
    if (n < 0) check(0);
    return n;
  });
}

/** A copy of part `part` of read column `k` (see dta_column_part). */
export function part(handle: number, k: number, kind: 0 | 1 | 2, as: "f64"): Float64Array;
export function part(handle: number, k: number, kind: 0 | 1 | 2, as: "u8"): Uint8Array;
export function part(handle: number, k: number, kind: 0 | 1 | 2, as: "u32"): Uint32Array;
export function part(
  handle: number,
  k: number,
  kind: 0 | 1 | 2,
  as: "f64" | "u8" | "u32",
): Float64Array | Uint8Array | Uint32Array {
  return guard(() => {
    const ptr = check(wasm.dta_column_part(handle, k, kind));
    const n = wasm.dta_result_len();
    // Views are made after the call, since a call can grow (and so
    // replace) the module's memory.
    const buffer = wasm.memory.buffer;
    if (as === "f64") return new Float64Array(buffer, ptr, n).slice();
    if (as === "u32") return new Uint32Array(buffer, ptr, n).slice();
    return new Uint8Array(buffer, ptr, n).slice();
  });
}

export function forget(read: ReadAt): void {
  for (const [file, r] of files) if (r === read) files.delete(file);
}

const utf8Encoder = new TextEncoder();

/** Copy `data` into module memory; returns its address. Free with `free`. */
function put(data: Uint8Array | Float64Array | Uint32Array): number {
  const bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  const ptr = wasm.dta_alloc(bytes.length);
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
    wasm.dta_write_begin(nobs);
    for (const part of parts) {
      const owned: [number, number][] = [];
      const own = (data: Uint8Array | Float64Array | Uint32Array) => {
        const ptr = put(data);
        owned.push([ptr, data.byteLength]);
        return ptr;
      };
      let ok: number;
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
      for (const [ptr, len] of owned) wasm.dta_free(ptr, len);
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
  });
}
