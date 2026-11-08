// What both packages' wasm modules share (plan 0021): instantiating a
// module from its embedded bytes, the host callbacks, error checking,
// copying into module memory, and replacing an instance to give memory
// back. @jbearak/dta-parser (src/wasm.ts) and @jbearak/datakit
// (datakit/src/wasm.ts) each make their own core over their own module;
// datakit's build bundles this file.

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

/** The exports every module has (`wasm_common.rs`). */
export interface CoreExports {
  memory: WebAssembly.Memory;
  dta_alloc(len: number): number;
  dta_free(ptr: number, len: number): void;
  dta_error(): number;
  dta_error_kind(): number;
  dta_result_len(): number;
}

/** Fills `into` with the file's bytes starting at `offset`. */
export type ReadAt = (into: Uint8Array, offset: number) => void;

/** The codes of `dta_error_kind`'s kinds, 1 to 7. */
const CODES: ErrorCode[] = ["DTA_CORRUPT", "DTA_TOO_LARGE", "DTA_IO", "DTA_INVALID", "DTA_OUT_OF_RANGE", "DTA_INTERNAL", "DTA_CLOSED"];

// ignoreBOM: a value that starts with U+FEFF keeps it.
const utf8 = new TextDecoder("utf-8", { ignoreBOM: true });

/** One module's instance and the calls every wrapper needs. */
export interface Core<E extends CoreExports> {
  /** The current instance's exports; read it anew after any call, since an instance can be replaced. */
  readonly exports: E;
  /** Files a module call may read, by number (`host_read`). */
  readonly files: Map<number, ReadAt>;
  /** Where files being written go (`host_write`). */
  readonly sinks: Map<number, (bytes: Uint8Array) => void>;
  /** Number columns the Parquet writer asks for a block at a time (`host_fill`). */
  readonly fills: Map<number, { values: Float64Array; missing: Uint8Array }>;
  /** A number for a new file or sink. */
  nextFile(): number;
  /** Counts module instances; readers opened on an older one are closed. */
  generation(): number;
  /** Count a handle opened on, or closed from, the current instance. */
  opened(): void;
  closed(): void;
  /** Give the instance's memory back if it has grown and nothing uses it. */
  maybeReplace(): void;
  /** Replace the instance now if no handle is open on it (and no call runs); whether it did. */
  replaceIfIdle(): boolean;
  /** Run `f` as a call into the module: no re-entry; a trap replaces the instance. */
  guard<T>(f: () => T): T;
  /** Throw the module's last error if `result` is 0. */
  check<T extends number>(result: T): T;
  /** The text a call left as its result. */
  resultText(ptr: number): string;
  /** Room for `len` bytes in module memory, or DTA_TOO_LARGE. */
  alloc(len: number): number;
  /** Copy `data` into module memory; free with `exports.dta_free`. */
  put(data: Uint8Array | Float64Array | Uint32Array | Int32Array | BigInt64Array): number;
  /** Forget the file numbers of a reader's `read`. */
  forget(read: ReadAt): void;
  /** The module's memory in bytes. */
  memoryBytes(): number;
  /** Open handles on the current instance. */
  openHandles(): number;
  /** Memory past which an instance is replaced once nothing uses it (tests lower it). */
  setReplaceAbove(bytes: number): void;
}

/**
 * Compile `embedded` and make an instance of it. Synchronous: Node allows
 * it for any size, and it keeps the whole API synchronous. The bytes are
 * not kept, only the compiled module.
 */
export function makeCore<E extends CoreExports>(embedded: Uint8Array<ArrayBuffer>, name: string): Core<E> {
  const module = new WebAssembly.Module(moduleBytes(embedded) as Uint8Array<ArrayBuffer>);
  const files = new Map<number, ReadAt>();
  const sinks = new Map<number, (bytes: Uint8Array) => void>();
  const fills = new Map<number, { values: Float64Array; missing: Uint8Array }>();
  let nextFile = 1;
  /** What the last `ReadAt` or sink threw, for the `DTA_IO` error's cause. */
  let hostError: unknown;
  // Never lets a JavaScript exception unwind through wasm frames; the
  // module reports the failure, and `check` attaches the exception.
  // Pointers and lengths arrive as signed i32: `>>> 0` keeps those past
  // 2 GiB positive. A module imports only the callbacks it uses.
  const imports = {
    env: {
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
  let wasm = new WebAssembly.Instance(module, imports).exports as unknown as E;

  // We replace an instance when a trap (a bug: damaged files give
  // errors, not traps) leaves it unusable, and to give memory back (wasm
  // memory never shrinks): readers opened on the old one see the count
  // change and report themselves closed.
  let generation = 0;
  /** Readers open on this instance; it is replaced only when none are. */
  let openHandles = 0;
  /** Calls into the module running now: at most one (no re-entry). */
  let depth = 0;
  let replaceAbove = 256 * 2 ** 20;

  function replaceInstance(): void {
    generation++;
    files.clear();
    openHandles = 0;
    wasm = new WebAssembly.Instance(module, imports).exports as unknown as E;
  }

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
      throw dtaError(code, message || `${name} failed`, cause, errorClass);
    }
    return result;
  }

  function alloc(len: number): number {
    const ptr = wasm.dta_alloc(len) >>> 0;
    if (ptr === 0) throw dtaError("DTA_TOO_LARGE", `${len} bytes do not fit in module memory`);
    return ptr;
  }

  return {
    get exports() {
      return wasm;
    },
    files,
    sinks,
    fills,
    nextFile: () => nextFile++,
    generation: () => generation,
    opened() {
      openHandles++;
    },
    closed() {
      openHandles--;
    },
    maybeReplace() {
      if (openHandles === 0 && depth === 0 && wasm.memory.buffer.byteLength > replaceAbove) replaceInstance();
    },
    replaceIfIdle() {
      if (openHandles !== 0 || depth !== 0) return false;
      replaceInstance();
      return true;
    },
    guard<T>(f: () => T): T {
      // The module's state is in use for the whole of a call, including
      // while it waits on a ReadAt callback or a write sink, so those may
      // not call back into the package.
      if (depth > 0) {
        throw dtaError("DTA_INVALID", `${name} was called from inside a ReadAt callback or write sink; call it after that returns`, undefined, TypeError);
      }
      depth++;
      try {
        return f();
      } catch (e) {
        if (e instanceof WebAssembly.RuntimeError) {
          replaceInstance();
          throw dtaError("DTA_INTERNAL", `${name} failed (${e.message}); files it had open are now closed`, e);
        }
        throw e;
      } finally {
        depth--;
      }
    },
    check,
    resultText(ptr: number): string {
      check(ptr);
      return utf8.decode(new Uint8Array(wasm.memory.buffer, ptr >>> 0, wasm.dta_result_len() >>> 0));
    },
    alloc,
    put(data) {
      const bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
      const ptr = alloc(bytes.length);
      new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
      return ptr;
    },
    forget(read: ReadAt) {
      for (const [file, r] of files) if (r === read) files.delete(file);
    },
    memoryBytes: () => wasm.memory.buffer.byteLength,
    openHandles: () => openHandles,
    setReplaceAbove(bytes: number) {
      replaceAbove = bytes;
    },
  };
}
