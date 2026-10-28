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

/** Rows read per call into the wasm module, to bound its memory. */
const BLOCK = 1 << 20;

const utf8 = new TextDecoder("utf-8");

/** An open .dta file. Reads happen only when asked for. */
export class DtaReader {
  readonly info: Info;
  readonly variables: readonly Variable[];
  private handle: number;
  private readonly read: ReadAt;
  private labels?: Map<string, ValueLabels>;
  private readonly onClose?: () => void;

  /** Open a file given a function that reads its bytes. */
  constructor(read: ReadAt, length: number, options: Options = {}, onClose?: () => void) {
    this.read = read;
    this.onClose = onClose;
    this.handle = wasm.open(read, length, options.encoding ?? "windows-1252");
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
    if (this.handle === 0) throw new Error("the file is closed");
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
    for (let done = 0; done < count; done += BLOCK) {
      const n = Math.min(BLOCK, count - done);
      wasm.read(this.open, indices, start + done, n);
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
      wasm.close(this.handle);
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
