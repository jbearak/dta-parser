// @jbearak/dta-parser: read Stata .dta files, synchronously.

import * as wasm from "./wasm";
import type { EncodingName, ReadAt } from "./wasm";

export type { EncodingName, ReadAt };

/** A Stata missing value: `.` or `.a` to `.z`. */
export interface Missing {
  readonly missing: string;
}

const MISSING_NAMES = [".", ...Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`)];

/**
 * The 27 missing values, one frozen object each, so `===` compares them:
 * `MISSING["."]`, `MISSING[".a"]`, ... `MISSING[".z"]`.
 */
export const MISSING: Readonly<Record<string, Missing>> = Object.freeze(
  Object.fromEntries(MISSING_NAMES.map((name) => [name, Object.freeze({ missing: name })])),
);

/** The missing value for a code in a NumberColumn's `missing` array (1 to 27). */
export function missingValue(code: number): Missing {
  return MISSING[MISSING_NAMES[code - 1]];
}

export function isMissing(value: unknown): value is Missing {
  return typeof value === "object" && value !== null && "missing" in value;
}

/** One cell: a number, a string, a binary strL, or a missing value. */
export type Cell = number | string | Uint8Array | Missing;

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

export type Column = NumberColumn | StringColumn;

/** Value label set: maps a value, or a missing value, to its text. */
export type ValueLabels = Map<number | Missing, string>;

export interface Characteristic {
  /** `_dta` for the dataset, or a variable's name. */
  variable: string;
  name: string;
  value: string;
}

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
    if (this.handle === 0 || this.generation !== wasm.currentGeneration()) throw new Error("the file is closed");
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
      throw new RangeError(`no variable ${JSON.stringify(column)}`);
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
      throw new RangeError(`rows ${start} to ${start + count} are outside 0 to ${this.info.nobs}`);
    }
    const out: Column[] = indices.map((i) =>
      /^str/.test(this.variables[i].type)
        ? { kind: "string", values: new Array<string | Uint8Array>(count) }
        : { kind: "number", values: new Float64Array(count), missing: new Uint8Array(count) },
    );
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

  close(): void {
    if (this.handle !== 0) {
      if (this.generation === wasm.currentGeneration()) wasm.close(this.handle);
      wasm.forget(this.read);
      this.handle = 0;
      this.onClose?.();
    }
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
   * Strings become strN, or strL beyond 2045 bytes.
   */
  values: readonly (number | Missing | null)[] | readonly string[];
  /** Storage type of a numeric variable; default double. */
  type?: "byte" | "int" | "long" | "float" | "double";
  /** Display format; default the storage type's. */
  format?: string;
  label?: string;
  /** Name of a value label set in `WriteDataset.valueLabels`. */
  valueLabels?: string;
}

export interface WriteDataset {
  variables: readonly WriteVariable[];
  /** Data label. */
  label?: string;
  /** Value label sets by name. */
  valueLabels?: Readonly<Record<string, ValueLabels>>;
  notes?: readonly string[];
  /** Written as the file's timestamp; default now. */
  timestamp?: Date;
}

const STORAGE = { byte: 0, int: 1, long: 2, float: 3, double: 4 } as const;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const encoder = new TextEncoder();

/** UTF-8 bytes of `texts`, end to end, with each one's end offset. */
function packTexts(texts: readonly string[]): { bytes: Uint8Array; ends: Uint32Array } {
  const parts = texts.map((t) => encoder.encode(t));
  const bytes = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  const ends = new Uint32Array(parts.length);
  let at = 0;
  parts.forEach((p, i) => {
    bytes.set(p, at);
    at += p.length;
    ends[i] = at;
  });
  return { bytes, ends };
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
    if (text?.includes("\0")) throw new TypeError(`${what} contains a NUL`);
    return text ?? "";
  };
  const nobs = data.variables[0]?.values.length ?? 0;
  const parts: wasm.WritePart[] = data.variables.map((v) => {
    if (v.values.length !== nobs) throw new RangeError(`${v.name} has ${v.values.length} values, not ${nobs}`);
    const meta = [
      field(v.name, "a variable name"),
      field(v.format, `the format of ${v.name}`),
      field(v.label, `the label of ${v.name}`),
      field(v.valueLabels, `the value label set of ${v.name}`),
    ].join("\0");
    if (v.type === undefined && v.values.some((x) => typeof x === "string")) {
      if (!v.values.every((x) => typeof x === "string")) throw new TypeError(`${v.name} mixes strings and numbers`);
      return { kind: "strings", meta, ...packTexts(v.values as readonly string[]) };
    }
    const storage = STORAGE[v.type ?? "double"];
    if (storage === undefined) throw new TypeError(`${v.name}: unknown type ${v.type}`);
    if (v.values.some((x) => typeof x === "string")) throw new TypeError(`${v.name} is ${v.type} but holds strings`);
    return { kind: "numbers", meta, storage, ...packNumbers(v.values as readonly (number | Missing | null)[]) };
  });
  for (const [name, labels] of Object.entries(data.valueLabels ?? {})) {
    field(name, "a value label set name");
    const keys = [...labels.keys()];
    const { bytes: texts, ends } = packTexts([...labels.values()]);
    parts.push({ kind: "labels", name, ...packNumbers(keys), texts, ends });
  }
  const t = data.timestamp ?? new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp = `${pad(t.getDate())} ${MONTHS[t.getMonth()]} ${t.getFullYear()} ${pad(t.getHours())}:${pad(t.getMinutes())}`;
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
