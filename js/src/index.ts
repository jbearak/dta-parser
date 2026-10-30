// @jbearak/dta-parser: read Stata .dta files, synchronously.

import * as wasm from "./wasm";
import { dtaError, isAllocationFailure, type DtaError, type ErrorCode } from "./errors";
import type { EncodingName, ReadAt } from "./wasm";

export type { DtaError, EncodingName, ErrorCode, ReadAt };

import { MISSING, MISSING_NAMES, isMissing, missingValue, type Cell, type Missing, type MissingName, type ValueLabels } from "./values";

export { MISSING, isMissing, missingValue };
export type { Cell, Missing, MissingName, ValueLabels };

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
 * `rows.sort((a, b) => stataKey(a) - stataKey(b))`.
 */
export function stataKey(value: number | Missing): number {
  if (typeof value === "number") return Number.isNaN(value) ? MISSING_KEYS[0] : value;
  return MISSING_KEYS[MISSING_NAMES.indexOf(value.missing)];
}

/** `stataKey` for every value of a NumberColumn. */
export function stataKeys(column: NumberColumn): Float64Array {
  const out = new Float64Array(column.values.length);
  for (let i = 0; i < out.length; i++) {
    const code = column.missing[i];
    out[i] = code === 0 ? column.values[i] : MISSING_KEYS[code - 1];
  }
  return out;
}

/** One variable's descriptor, as the file stores it. */
export interface Variable {
  name: string;
  /** Storage type: byte, int, long, float, double, str1 to str2045, or strL. */
  type: string;
  /** Display format, such as `%9.0g`. */
  format: string;
  /** Variable label; empty when there is none. */
  label: string;
  /** Name of the value label set attached; empty when there is none. */
  valueLabels: string;
}

/** What the file's header says about it. */
export interface Info {
  /** The .dta release, such as 114 or 118. */
  release: number;
  byteOrder: "little" | "big";
  nobs: number;
  /** Data label; empty when there is none. */
  label: string;
  timestamp: string;
  /** How text was decoded: always utf-8 from release 118. */
  encoding: EncodingName;
  /** Names of the variables the data is sorted by. */
  sortedBy: string[];
}

/**
 * A numeric variable's values. Where `missing[i]` is not 0, `values[i]`
 * is NaN and the value is missing: 1 is `.`, 2 to 27 are `.a` to `.z`
 * (see `missingValue`).
 */
export interface NumberColumn {
  kind: "number";
  values: Float64Array;
  missing: Uint8Array;
}

/** A string variable's values; binary strLs are Uint8Arrays. */
export interface StringColumn {
  kind: "string";
  values: (string | Uint8Array)[];
}

/** One variable's values, as `readColumns` returns them. */
export type Column = NumberColumn | StringColumn;

/** A characteristic: named text attached to the dataset or to a variable. Notes are characteristics named `note1`, `note2`, .... */
export interface Characteristic {
  /** `_dta` for the dataset, or a variable's name. */
  variable: string;
  name: string;
  value: string;
}

/** Options for opening a file. */
export interface Options {
  /** Encoding of text in files before release 118; default windows-1252. */
  encoding?: EncodingName;
}

/** Most rows asked of the wasm module per call; it also stops at 64 MiB. */
const BLOCK = 1 << 20;

const utf8 = new TextDecoder("utf-8");

/** An open .dta file. Reads happen only when asked for. */
export class DtaReader {
  readonly info: Info;
  readonly variables: readonly Variable[];
  private handle: number;
  private readonly generation: number;
  private readonly read: ReadAt;
  private labels?: Map<string, ValueLabels>;
  private readonly onClose?: () => void;

  /** Open a file given a function that reads its bytes. */
  constructor(read: ReadAt, length: number, options: Options = {}, onClose?: () => void) {
    this.read = read;
    this.onClose = onClose;
    this.handle = wasm.open(read, length, options.encoding ?? "windows-1252");
    this.generation = wasm.currentGeneration();
    const meta = JSON.parse(wasm.metadataJson(this.handle));
    this.variables = Object.freeze(meta.variables.map((v: Variable) => Object.freeze(v)));
    this.info = Object.freeze({
      release: meta.release,
      byteOrder: meta.byteOrder,
      nobs: meta.nobs,
      label: meta.label,
      timestamp: meta.timestamp,
      encoding: meta.encoding,
      sortedBy: meta.sortedBy.map((i: number) => this.variables[i].name),
    });
  }

  private get open(): number {
    if (this.handle === 0 || this.generation !== wasm.currentGeneration()) throw dtaError("DTA_CLOSED", "the file is closed");
    return this.handle;
  }

  /** The value label set `name`, or undefined if the file has none by that name. */
  valueLabels(name: string): ValueLabels | undefined {
    if (!this.labels) {
      this.labels = new Map();
      for (const set of JSON.parse(wasm.valueLabelsJson(this.open))) {
        const map: ValueLabels = new Map();
        for (const [code, text] of set.labels) {
          map.set(typeof code === "string" ? MISSING[code] : code, text);
        }
        this.labels.set(set.name, map);
      }
    }
    return this.labels.get(name);
  }

  /** Every characteristic in the file, including the notes, in file order. */
  characteristics(): Characteristic[] {
    return JSON.parse(wasm.characteristicsJson(this.open));
  }

  /** The dataset's notes, in order. */
  notes(): string[] {
    return this.characteristics()
      .filter((c) => c.variable === "_dta" && /^note[1-9][0-9]*$/.test(c.name))
      .sort((a, b) => Number(a.name.slice(4)) - Number(b.name.slice(4)))
      .map((c) => c.value);
  }

  private index(column: number | string): number {
    const i = typeof column === "number" ? column : this.variables.findIndex((v) => v.name === column);
    if (!Number.isInteger(i) || i < 0 || i >= this.variables.length) {
      throw dtaError("DTA_OUT_OF_RANGE", `no variable ${JSON.stringify(column)}`, undefined, RangeError);
    }
    return i;
  }

  /**
   * Read `count` rows from row `start` (default: all rows) of the given
   * variables, by index or name, in one pass over the file.
   */
  readColumns(columns: readonly (number | string)[], range: { start?: number; count?: number } = {}): Column[] {
    const indices = columns.map((c) => this.index(c));
    const start = range.start ?? 0;
    const count = range.count ?? this.info.nobs - start;
    if (!Number.isInteger(start) || !Number.isInteger(count) || start < 0 || count < 0 || start + count > this.info.nobs) {
      throw dtaError("DTA_OUT_OF_RANGE", `rows ${start} to ${start + count} are outside 0 to ${this.info.nobs}`, undefined, RangeError);
    }
    let out: Column[];
    try {
      out = indices.map((i) =>
        /^str/.test(this.variables[i].type)
          ? { kind: "string", values: new Array<string | Uint8Array>(count) }
          : { kind: "number", values: new Float64Array(count), missing: new Uint8Array(count) },
      );
    } catch (e) {
      if (isAllocationFailure(e)) throw dtaError("DTA_TOO_LARGE", `${count} rows of ${indices.length} variables do not fit in memory`, e);
      throw e;
    }
    for (let done = 0; done < count; ) {
      const n = wasm.read(this.open, indices, start + done, Math.min(BLOCK, count - done));
      out.forEach((column, k) => {
        if (column.kind === "number") {
          column.values.set(wasm.part(this.handle, k, 0, "f64"), done);
          column.missing.set(wasm.part(this.handle, k, 1, "u8"), done);
        } else {
          const bytes = wasm.part(this.handle, k, 0, "u8");
          const ends = wasm.part(this.handle, k, 1, "u32");
          const binary = this.variables[indices[k]].type === "strL" ? wasm.part(this.handle, k, 2, "u8") : undefined;
          let from = 0;
          for (let i = 0; i < n; i++) {
            const piece = bytes.subarray(from, ends[i]);
            column.values[done + i] = binary?.[i] ? piece.slice() : utf8.decode(piece);
            from = ends[i];
          }
        }
      });
      done += n;
    }
    return out;
  }

  /** Rows as arrays of cells, one per variable asked for (default: all). */
  readRows(start: number, count: number, columns?: readonly (number | string)[]): Cell[][] {
    const cols = this.readColumns(columns ?? this.variables.map((_, i) => i), { start, count });
    const rows: Cell[][] = [];
    for (let i = 0; i < count; i++) {
      rows.push(
        cols.map((c) =>
          c.kind === "string" ? c.values[i] : c.missing[i] ? missingValue(c.missing[i]) : c.values[i],
        ),
      );
    }
    return rows;
  }

  /** Release the file (and close it, if `openDtaFile` opened it by path). Further reads throw. */
  close(): void {
    if (this.handle !== 0) {
      if (this.generation === wasm.currentGeneration()) wasm.close(this.handle);
      wasm.forget(this.read);
      this.handle = 0;
      this.onClose?.();
    }
  }

  /**
   * `close()`, so `using r = openDtaFile(path)` closes the reader at the
   * end of its block. A file descriptor the caller passed in stays open.
   */
  [Symbol.dispose](): void {
    this.close();
  }
}

/** Open a .dta file held in memory. */
export function openDta(bytes: Uint8Array, options: Options = {}): DtaReader {
  return new DtaReader(
    (into, offset) => {
      if (offset + into.length > bytes.length) throw new RangeError("read past the end of the file");
      into.set(bytes.subarray(offset, offset + into.length));
    },
    bytes.length,
    options,
  );
}

/** A variable to write. */
export interface WriteVariable {
  name: string;
  /**
   * Numbers, with `null` or a `Missing` for missing values, or strings.
   * Strings become strN, or strL beyond 2045 bytes. A Uint8Array is a
   * binary strL, and makes the variable strL; it may sit among strings,
   * as `StringColumn.values` holds them.
   */
  values: readonly (number | Missing | null)[] | readonly (string | Uint8Array)[] | Float64Array;
  /**
   * With a Float64Array of values, each one's missing code as
   * `NumberColumn.missing` holds them (0 a number, 1 `.`, 2 to 27 `.a` to
   * `.z`); none missing when absent. So a column `readColumns` returned
   * writes back as it is, without an array of values or `Missing`s.
   */
  missing?: Uint8Array;
  /**
   * Storage type of a numeric variable; default double. `strL` makes a
   * string variable strL whatever its length.
   */
  type?: "byte" | "int" | "long" | "float" | "double" | "strL";
  /** Display format; default the storage type's. */
  format?: string;
  label?: string;
  /** Name of a value label set in `WriteDataset.valueLabels`. */
  valueLabels?: string;
}

/** A dataset to write: its variables, in order, and dataset-level metadata. */
export interface WriteDataset {
  variables: readonly WriteVariable[];
  /** Data label. */
  label?: string;
  /** Value label sets by name. */
  valueLabels?: Readonly<Record<string, ValueLabels>>;
  notes?: readonly string[];
  /**
   * The file's timestamp: a Date, or text written as given (such as
   * `info.timestamp` of a file read); default now.
   */
  timestamp?: Date | string;
  /**
   * Characteristics, as `characteristics()` reads them. Those of
   * variables not written are left out, and so are `_dta` notes
   * (`note0`, `note1`, ...): `notes` gives those.
   */
  characteristics?: readonly Characteristic[];
  /**
   * Names of the variables the data is sorted by, as `info.sortedBy`.
   * Only the leading names among the variables written are kept: data
   * sorted by a, b and c is still sorted by a without b, but not by a and c.
   */
  sortedBy?: readonly string[];
}

const STORAGE = { byte: 0, int: 1, long: 2, float: 3, double: 4 } as const;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const encoder = new TextEncoder();

const isText = (x: unknown): x is string | Uint8Array => typeof x === "string" || x instanceof Uint8Array;

/**
 * UTF-8 bytes of `texts` (a Uint8Array as it is), end to end, with each
 * one's end offset. Encoded straight into one buffer, grown as needed: an
 * array per string cost about 100 bytes each, gigabytes for 10M strings.
 */
function packTexts(texts: readonly (string | Uint8Array)[]): { bytes: Uint8Array; ends: Uint32Array } {
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
function packNumbers(values: readonly (number | Missing | null)[]): { values: Float64Array; missing: Uint8Array } {
  const out = { values: new Float64Array(values.length), missing: new Uint8Array(values.length) };
  values.forEach((v, i) => {
    if (typeof v === "number") out.values[i] = v;
    else out.missing[i] = v === null ? 1 : MISSING_NAMES.indexOf(v.missing) + 1;
  });
  return out;
}

/**
 * Write a .dta file (release 118), handing its bytes to `sink` in order.
 * A value that does not fit its storage type is an error.
 */
export function writeDtaTo(data: WriteDataset, sink: (bytes: Uint8Array) => void): void {
  // Fields cross into the module separated by NULs, so none may hold one.
  const field = (text: string | undefined, what: string): string => {
    if (text?.includes("\0")) throw dtaError("DTA_INVALID", `${what} contains a NUL`, undefined, TypeError);
    return text ?? "";
  };
  const nobs = data.variables[0]?.values.length ?? 0;
  const parts: wasm.WritePart[] = data.variables.map((v) => {
    if (v.values.length !== nobs) throw dtaError("DTA_INVALID", `${v.name} has ${v.values.length} values, not ${nobs}`, undefined, RangeError);
    const meta = [
      field(v.name, "a variable name"),
      field(v.format, `the format of ${v.name}`),
      field(v.label, `the label of ${v.name}`),
      field(v.valueLabels, `the value label set of ${v.name}`),
    ].join("\0");
    if (v.values instanceof Float64Array) {
      const storage = STORAGE[(v.type ?? "double") as keyof typeof STORAGE];
      if (storage === undefined) throw dtaError("DTA_INVALID", `${v.name}: a Float64Array cannot be ${v.type}`, undefined, TypeError);
      const missing = v.missing ?? new Uint8Array(nobs);
      if (missing.length !== nobs) throw dtaError("DTA_INVALID", `${v.name} has ${missing.length} missing codes, not ${nobs}`, undefined, RangeError);
      return { kind: "numbers", meta, storage, values: v.values, missing };
    }
    if (v.type === "strL" || (v.type === undefined && v.values.some(isText))) {
      if (!v.values.every(isText)) throw dtaError("DTA_INVALID", `${v.name} mixes strings and numbers`, undefined, TypeError);
      const values = v.values as readonly (string | Uint8Array)[];
      const strL = v.type === "strL" || values.some((x) => x instanceof Uint8Array);
      const binary = strL ? Uint8Array.from(values, (x) => (x instanceof Uint8Array ? 1 : 0)) : undefined;
      return { kind: "strings", meta, ...packTexts(values), binary };
    }
    const storage = STORAGE[v.type ?? "double"];
    if (storage === undefined) throw dtaError("DTA_INVALID", `${v.name}: unknown type ${v.type}`, undefined, TypeError);
    if (v.values.some(isText)) throw dtaError("DTA_INVALID", `${v.name} is ${v.type} but holds strings`, undefined, TypeError);
    return { kind: "numbers", meta, storage, ...packNumbers(v.values as readonly (number | Missing | null)[]) };
  });
  for (const [name, labels] of Object.entries(data.valueLabels ?? {})) {
    field(name, "a value label set name");
    const keys = [...labels.keys()];
    const { bytes: texts, ends } = packTexts([...labels.values()]);
    parts.push({ kind: "labels", name, ...packNumbers(keys), texts, ends });
  }
  const names = data.variables.map((v) => v.name);
  const kept = new Set([...names, "_dta"]);
  const chars = (data.characteristics ?? []).filter(
    (c) => kept.has(c.variable) && !(c.variable === "_dta" && /^note[0-9]+$/.test(c.name)),
  );
  if (chars.length) {
    const text = chars
      .flatMap((c) => [
        field(c.variable, "a characteristic's variable"),
        field(c.name, "a characteristic's name"),
        field(c.value, `characteristic ${c.variable}[${c.name}]`),
      ])
      .join("\0");
    parts.push({ kind: "characteristics", text });
  }
  const sorted: number[] = [];
  for (const name of data.sortedBy ?? []) {
    const i = names.indexOf(name);
    if (i < 0) break;
    sorted.push(i);
  }
  if (sorted.length) parts.push({ kind: "sortOrder", indices: Uint32Array.from(sorted) });
  const t = data.timestamp ?? new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp =
    typeof t === "string"
      ? field(t, "the timestamp")
      : `${pad(t.getDate())} ${MONTHS[t.getMonth()]} ${t.getFullYear()} ${pad(t.getHours())}:${pad(t.getMinutes())}`;
  const notes = (data.notes ?? []).map((n) => field(n, "a note"));
  wasm.write(nobs, parts, [field(data.label, "the data label"), stamp, ...notes], sink);
}

/** Write a .dta file (release 118) into memory. */
export function writeDta(data: WriteDataset): Uint8Array {
  const chunks: Uint8Array[] = [];
  writeDtaTo(data, (bytes) => chunks.push(bytes.slice()));
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}
export { formatValue } from "./format";
