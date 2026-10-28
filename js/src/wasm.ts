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
}

/** Fills `into` with the file's bytes starting at `offset`. */
export type ReadAt = (into: Uint8Array, offset: number) => void;

const files = new Map<number, ReadAt>();
let nextFile = 1;

// Synchronous compile and instantiate: Node allows it for any size, and
// it keeps the whole API synchronous.
const instance = new WebAssembly.Instance(new WebAssembly.Module(wasmBytes), {
  env: {
    host_read(file: number, ptr: number, len: number, offset: number): number {
      try {
        files.get(file)!(new Uint8Array(wasm.memory.buffer, ptr, len), offset);
        return 0;
      } catch {
        return 1;
      }
    },
  },
});
const wasm = instance.exports as unknown as Exports;

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
    return check(wasm.dta_open(file, length, ENCODINGS[encoding]));
  } catch (e) {
    files.delete(file);
    throw e;
  }
}

export function close(handle: number): void {
  wasm.dta_close(handle);
}

export function metadataJson(handle: number): string {
  return resultText(wasm.dta_metadata(handle));
}

export function valueLabelsJson(handle: number): string {
  return resultText(wasm.dta_value_labels(handle));
}

export function characteristicsJson(handle: number): string {
  return resultText(wasm.dta_characteristics(handle));
}

/** Read rows into the handle; then `part` copies the buffers out. */
export function read(handle: number, columns: number[], start: number, count: number): void {
  const ptr = wasm.dta_alloc(columns.length * 4);
  try {
    new Uint32Array(wasm.memory.buffer, ptr, columns.length).set(columns);
    check(wasm.dta_read(handle, ptr, columns.length, start, count));
  } finally {
    wasm.dta_free(ptr, columns.length * 4);
  }
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
  const ptr = check(wasm.dta_column_part(handle, k, kind));
  const n = wasm.dta_result_len();
  // Views are made after the call, since a call can grow (and so
  // replace) the module's memory.
  const buffer = wasm.memory.buffer;
  if (as === "f64") return new Float64Array(buffer, ptr, n).slice();
  if (as === "u32") return new Uint32Array(buffer, ptr, n).slice();
  return new Uint8Array(buffer, ptr, n).slice();
}

export function forget(read: ReadAt): void {
  for (const [file, r] of files) if (r === read) files.delete(file);
}
