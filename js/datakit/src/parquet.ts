// Parquet files (plan 0018, moved to datakit by plan 0021):
// `ParquetReader`, a `TableReader` like dta-parser's `DtaReader`; an async
// reader for files read through a callback; and a writer that takes a
// `Dataset`.

import * as wasm from "./wasm";
import type { ReadAt } from "./wasm";
import { dtaError, isAllocationFailure } from "./_shared/errors";
import { MISSING, missingValue, type ValueLabels } from "@jbearak/dta-parser/format";
import { packNumbers, packTexts, packTextsBy } from "./_shared/shared";
import type { Dataset, DatasetVariable } from "./types";
import type {
  AsyncTableReader,
  BigIntColumn,
  Characteristic,
  DictionaryColumn,
  NumberColumn,
  ReadRange,
  StringColumn,
  TableCell,
  TableColumn,
  TableInfo,
  TableReader,
  Variable,
} from "@jbearak/dta-parser";

/** Options for opening a Parquet file. */
export interface ParquetOptions {
  /**
   * What to do with nested columns (lists, maps, structs), which are not
   * read. `"error"` (the default): they are in `variables`, with role
   * `"nested"`, and reading them, or reading every column, is an error
   * naming them. `"skip"`: they are left out of `variables`.
   */
  nested?: "error" | "skip";
  /**
   * How 64-bit integer columns (INT64, unsigned 64-bit, and timestamps
   * and times stored as INT64 or INT96) come back. `"auto"` (the
   * default): as a `NumberColumn` when the footer's statistics, present
   * for every row group, put every value within the safe integers (up
   * to 2^53 − 1 either side of 0); otherwise as a `BigIntColumn`. The
   * choice is made once, when the file is opened, and
   * `ParquetVariable.int64` says which and why. Each value read as a
   * number is still checked, and one beyond the safe integers is an
   * error naming the column, the row and `int64: "bigint"`.
   * `"bigint"` or `"number"` choose for every such column.
   */
  int64?: "auto" | "bigint" | "number";
  /**
   * Bytes of decompressed pages each reader keeps between reads; default
   * 8 MiB, 0 for none. Neighbouring windows (a viewer scrolling, a scan
   * in batches) then decompress each page once. Reads of whole column
   * chunks do not use it.
   */
  pageCacheBytes?: number;
}

/** A row group, as `ParquetInfo.rowGroups` lists them. */
export interface RowGroup {
  /** Its first row in the file, counted from 0. */
  firstRow: number;
  rows: number;
  compressedBytes: number;
  uncompressedBytes: number;
}

/** A statistic from the footer: a number, a bigint (by the `int64` rule), text, or bytes. */
export type Statistic = number | bigint | string | Uint8Array;

/** One column's part of one row group (a column chunk), from the footer. */
export interface ColumnChunk {
  compressedBytes: number;
  uncompressedBytes: number;
  /** The codec: `"snappy"`, `"zstd"`, `"gzip"`, `"lz4_raw"`, `"brotli"` or `"none"`. */
  codec: string;
  /** The encodings it uses, such as `"PLAIN"` and `"RLE_DICTIONARY"`. */
  encodings: string[];
  /** Bytes of its dictionary page, header included; null without one. */
  dictionaryPageBytes: number | null;
  /** Nulls in it, as the writer counted them; null when the file does not say. */
  nullCount: number | null;
  /**
   * The least and greatest value, as the writer recorded them; null when
   * the file does not say (and always for DECIMAL and INT96 columns).
   * Dates, times and timestamps are counts of their `unit`. A writer may
   * record bounds that are not themselves values in the column.
   */
  min: Statistic | null;
  max: Statistic | null;
}

/** What a Parquet file's footer says about it, read before any data. */
export interface ParquetInfo extends TableInfo {
  format: "parquet";
  /** The row groups, in order. */
  rowGroups: RowGroup[];
  /** The codecs the column chunks use, each once. */
  compression: string[];
  /** The writer the file names, such as `"parquet-cpp-arrow version 26.0.1"`. */
  createdBy: string;
  /** The dataset's notes, from the dta profile. */
  notes: string[];
  /** Bytes of the footer (schema, row groups, statistics and key-value metadata). */
  footerBytes: number;
  /** Each key-value metadata entry's key and size in bytes (see `ParquetReader.keyValue`). */
  keyValue: { key: string; bytes: number }[];
  /**
   * Warnings about a damaged or newer dta profile; the values are still
   * read. Value label sets are read when `valueLabels` is first called,
   * not at open, so a damaged set is not among these: it is left out
   * then, and `valueLabels` gives undefined for it.
   */
  warnings: string[];
}

/**
 * One column of a Parquet file: `Variable`'s name, type, display format,
 * variable label and value label set, and what Parquet says about it.
 * `type` is `"byte"`, `"int"`, `"long"`, `"float"`, `"double"`,
 * `"int64"`, `"uint8"` to `"uint64"`, `"bool"`, `"date"`,
 * `"timestamp"`, `"time"`, `"decimal"`, `"string"`, `"binary"`,
 * `"categorical"`, or `"nested"` or `"unsupported"` for a column that is
 * not read.
 */
export interface ParquetVariable extends Variable {
  /** `"data"`, or `"nested"` for a list, map or struct, which is not read. */
  role: "data" | "nested";
  /** Parquet's physical type: `"INT32"`, `"INT64"`, `"DOUBLE"`, `"BYTE_ARRAY"`, ... */
  physicalType: string;
  /** Parquet's logical type, such as `"INT(8, signed)"`, `"STRING"` or `"TIMESTAMP(MICROS, UTC)"`; empty when none. */
  logicalType: string;
  /** The column `readColumns` returns for it: `"number"`, `"bigint"`, `"string"` or `"dictionary"`; null when it is not read. */
  columnKind: "number" | "bigint" | "string" | "dictionary" | null;
  /** Why the column is not read, when `columnKind` is null. */
  notRead?: string;
  /** For a 64-bit integer column: the kind it reads as and why (see `ParquetOptions.int64`). */
  int64?: { kind: "number" | "bigint"; reason: string };
  /** A date's, time's or timestamp's unit: values count days, seconds, ms, µs or ns since 1970-01-01 (since midnight for a time). */
  unit?: "day" | "s" | "ms" | "us" | "ns";
  /**
   * A timestamp that is an instant (adjusted to UTC): the zone it is
   * shown in, from the dta profile or `ARROW:schema`, else `"UTC"`.
   * Absent for a clock time without zone.
   */
  timeZone?: string;
  /** A DOUBLE column written wider because it holds `.a` to `.z`: its storage type before. */
  storage?: string;
  /**
   * A categorical's levels, in order with unused ones (from the dta
   * profile), and whether they are ordered. `levels` is null for a
   * dictionary another tool wrote (pandas `category`, an arrow factor):
   * its levels are the values of the rows read, in order of first
   * appearance.
   */
  categorical?: { levels: string[] | null; ordered: boolean };
  /**
   * Per row group, the column chunk's sizes, codec and statistics. Read
   * from the footer (for every column at once) the first time any
   * variable's `chunks` is used, which must be before `close()`.
   */
  readonly chunks: (ColumnChunk | null)[];
}

const DEFAULT_CACHE = 8 * 2 ** 20;
const env = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env;
/** Most decoded bytes one module call holds; tests lower it. */
const BUDGET = Number(env?.DTA_TEST_PARQUET_BUDGET) || 64 * 2 ** 20;
const NEW_READ = 1;
const DICTIONARY = 2;
const NULL_CODE = 0xffffffff;
const EMPTY = new Uint8Array(0);
const utf8 = new TextDecoder("utf-8", { ignoreBOM: true });

const unclosed = new FinalizationRegistry((held: { handle: number; generation: number; read: ReadAt; onClose?: () => void }) => {
  try {
    if (held.generation === wasm.currentGeneration()) wasm.pqClose(held.handle);
  } catch {
    // Nothing to report to: the reader is gone.
  }
  wasm.forget(held.read);
  held.onClose?.();
});

function int64Mode(options: ParquetOptions): number {
  const mode = options.int64 ?? "auto";
  const k = ["auto", "bigint", "number"].indexOf(mode);
  if (k < 0) throw dtaError("DTA_INVALID", `int64 must be "auto", "bigint" or "number", not ${JSON.stringify(mode)}`, undefined, TypeError);
  return k;
}

function statistic(s: [string, unknown] | null): Statistic | null {
  if (!s) return null;
  const [tag, v] = s;
  if (tag === "b") return BigInt(v as string);
  if (tag === "x") return Uint8Array.from((v as string).match(/../g) ?? [], (h) => parseInt(h, 16));
  return v as number | string;
}

/** A column being read: what JavaScript keeps across module calls. */
interface Gathering {
  /** A text column's dictionary values so far (coded calls). */
  seen: string[];
  /** Levels found in the rows read, and their codes. */
  found: string[];
  foundIndex: Map<string, number>;
  /** A categorical holding .a to .z: the first row read whose value is not a level number. */
  bad?: number;
}

/** A call to make: positions in the read's columns, and rows. */
interface Call {
  cols: number[];
  start: number;
  count: number;
}

/**
 * A variable of an open Parquet file: its fields are copied from the
 * module's JSON, and `chunks` is a getter on the prototype (one function
 * for every variable, where a getter defined on each of thousands of
 * variables made opening a wide file a few milliseconds slower).
 */
class FileVariable {
  readonly #reader: ParquetReader;
  readonly #column: number;
  constructor(reader: ParquetReader, column: number) {
    this.#reader = reader;
    this.#column = column;
  }
  get chunks(): (ColumnChunk | null)[] {
    return this.#reader._chunksOf(this.#column);
  }
}

/**
 * An open Parquet file, read synchronously; open one with `openParquet`
 * or `openParquetFile`. Opening reads only the footer, and each read
 * reads only the pages it needs.
 */
export class ParquetReader implements TableReader {
  readonly info: ParquetInfo;
  readonly variables: readonly ParquetVariable[];
  private handle: number;
  /** Columns already warned about a value that is not a level number (once per reader and column). */
  private warnedCategorical = new Set<number>();
  private readonly generation: number;
  private readonly read: ReadAt;
  private readonly onClose?: () => void;
  private labels?: Map<string, ValueLabels>;
  /** Each variable's column in the file. */
  private readonly core: number[];
  /** Each variable's text bytes per row group (text columns only), for planning reads. */
  private readonly textBytes: (number[] | undefined)[];
  /** Every column's chunks, by column in the file, once read. */
  private chunkCache?: (ColumnChunk | null)[][];
  private readonly nested: string[];
  /** @internal Where the offset indexes are, for the async reader. */
  readonly _indexSpan: [number, number] | null;

  /**
   * Open a file given a function that reads its bytes (as `DtaReader`'s
   * constructor); `openParquet` and `openParquetFile` call it.
   */
  constructor(read: ReadAt, length: number, options: ParquetOptions = {}, onClose?: () => void) {
    const mode = int64Mode(options);
    const nestedMode = options.nested ?? "error";
    if (nestedMode !== "error" && nestedMode !== "skip") {
      throw dtaError("DTA_INVALID", `nested must be "error" or "skip", not ${JSON.stringify(nestedMode)}`, undefined, TypeError);
    }
    const cache = options.pageCacheBytes ?? DEFAULT_CACHE;
    if (!Number.isFinite(cache) || cache < 0) throw dtaError("DTA_INVALID", `pageCacheBytes must be 0 or more, not ${cache}`, undefined, RangeError);
    this.read = read;
    this.onClose = onClose;
    this.handle = wasm.pqOpen(read, length, (nestedMode === "skip" ? 1 : 0) | (mode << 1), cache);
    this.generation = wasm.currentGeneration();
    let meta;
    let footerBytes = 0;
    try {
      meta = JSON.parse(wasm.pqInfoJson(this.handle, mode));
      const tail = new Uint8Array(8);
      read(tail, length - 8);
      footerBytes = new DataView(tail.buffer).getUint32(0, true);
    } catch (e) {
      wasm.pqClose(this.handle);
      wasm.forget(read);
      throw e;
    }
    unclosed.register(this, { handle: this.handle, generation: this.generation, read, onClose }, this);
    const texts: (number[] | null)[] = meta.textBytes;
    this.core = [];
    this.textBytes = [];
    const kept: ParquetVariable[] = [];
    const vars: Record<string, unknown>[] = meta.variables;
    for (let k = 0; k < vars.length; k++) {
      const v = vars[k];
      if (nestedMode === "skip" && v.role === "nested") continue;
      if (v.categorical) Object.freeze(v.categorical);
      kept.push(Object.freeze(Object.assign(new FileVariable(this, k), v)) as unknown as ParquetVariable);
      this.core.push(k);
      this.textBytes.push(texts[k] ?? undefined);
    }
    this.nested = kept.filter((v) => v.role === "nested").map((v) => v.name);
    this.variables = Object.freeze(kept);
    this._indexSpan = meta.indexSpan;
    this.info = Object.freeze({
      format: "parquet" as const,
      nobs: meta.nobs,
      label: meta.label,
      sortedBy: meta.sortedBy,
      notes: meta.notes,
      rowGroups: meta.rowGroups,
      compression: meta.compression,
      createdBy: meta.createdBy,
      footerBytes,
      keyValue: meta.keyValue,
      warnings: meta.warnings,
    });
  }

  /** The chunks of the file's column `k`, all columns' read once. @internal */
  _chunksOf(k: number): (ColumnChunk | null)[] {
    if (!this.chunkCache) {
      const parsed: (Record<string, unknown> | null)[][] = JSON.parse(wasm.pqChunksJson(this.open));
      this.chunkCache = parsed.map((cs) =>
        Object.freeze(cs.map((c) => (c ? (Object.freeze({ ...c, min: statistic(c.min as never), max: statistic(c.max as never) }) as ColumnChunk) : null))) as (ColumnChunk | null)[],
      );
    }
    return this.chunkCache[k];
  }

  private get open(): number {
    if (this.handle === 0 || this.generation !== wasm.currentGeneration()) throw dtaError("DTA_CLOSED", "the file is closed");
    return this.handle;
  }

  /**
   * The value label set `name` from the dta profile, or undefined. The
   * first call reads every set (opening the file does not).
   */
  valueLabels(name: string): ValueLabels | undefined {
    if (!this.labels) {
      this.labels = new Map();
      for (const set of JSON.parse(wasm.pqValueLabelsJson(this.open))) {
        const map: ValueLabels = new Map();
        for (const [code, text] of set.labels) map.set(typeof code === "string" ? MISSING[code] : code, text);
        this.labels.set(set.name, map);
      }
    }
    return this.labels.get(name);
  }

  /** The names of every value label set in the dta profile, used or not, in order. */
  valueLabelNames(): string[] {
    this.valueLabels("");
    return [...this.labels!.keys()];
  }

  /** Every characteristic in the dta profile, as `DtaReader.characteristics` gives them. */
  characteristics(): Characteristic[] {
    return JSON.parse(wasm.pqCharacteristicsJson(this.open));
  }

  /** The dataset's notes, in order (also `info.notes`). */
  notes(): string[] {
    return [...this.info.notes];
  }

  /**
   * The value of a key-value metadata entry as text (such as `"dta"`,
   * the dta profile, or `"ARROW:schema"`), or undefined when the file
   * has none by that name.
   */
  keyValue(key: string): string | undefined {
    const bytes = wasm.pqKeyValue(this.open, key);
    return bytes && utf8.decode(bytes);
  }

  private index(column: number | string): number {
    const i = typeof column === "number" ? column : this.variables.findIndex((v) => v.name === column);
    if (!Number.isInteger(i) || i < 0 || i >= this.variables.length) {
      const names = this.variables.slice(0, 20).map((v) => JSON.stringify(v.name)).join(", ");
      const more = this.variables.length > 20 ? ` and ${this.variables.length - 20} more` : "";
      throw dtaError("DTA_OUT_OF_RANGE", `no variable ${JSON.stringify(column)}; the file's are ${names}${more}`, undefined, RangeError);
    }
    return i;
  }

  /** Every variable, or the error a read of every variable gives. */
  private all(): number[] {
    if (this.nested.length) {
      throw dtaError(
        "DTA_INVALID",
        `the file has nested columns, which are not read: ${this.nested.map((n) => JSON.stringify(n)).join(", ")}; select the columns wanted, or open with nested: "skip"`,
        undefined,
        TypeError,
      );
    }
    return this.variables.map((_, i) => i);
  }

  private rows(range: ReadRange): { start: number; count: number } {
    const start = range.start ?? 0;
    const count = range.count ?? this.info.nobs - start;
    if (!Number.isInteger(start) || !Number.isInteger(count) || start < 0 || count < 0 || start + count > this.info.nobs) {
      throw dtaError("DTA_OUT_OF_RANGE", `rows ${start} to ${start + count} are outside 0 to ${this.info.nobs}`, undefined, RangeError);
    }
    if (range.maxStringBytes !== undefined) {
      throw dtaError("DTA_INVALID", "maxStringBytes is for .dta files; Parquet strings are read whole", undefined, TypeError);
    }
    return { start, count };
  }

  /**
   * Read `count` rows from row `start` (default: all rows) of the given
   * variables, by index or name, in the order given. Numbers come back as
   * `NumberColumn`s, 64-bit integers as `NumberColumn`s or
   * `BigIntColumn`s (see `ParquetOptions.int64`), text and bytes as
   * `StringColumn`s (with `missing` for nulls), and categoricals as
   * `DictionaryColumn`s. With `strings: "dictionary"`, text columns whose
   * values repeat come back as `DictionaryColumn`s too.
   */
  readColumns(columns: readonly (number | string)[], range: ReadRange = {}): TableColumn[] {
    const idx = columns.map((c) => this.index(c));
    const { start, count } = this.rows(range);
    return this.gather(idx, start, count, range.strings === "dictionary");
  }

  /** Rows as arrays of cells, one per variable asked for (default: all); a null is `MISSING["."]`. */
  readRows(start: number, count: number, columns?: readonly (number | string)[]): TableCell[][] {
    const idx = columns ? columns.map((c) => this.index(c)) : this.all();
    const r = this.rows({ start, count });
    const cols = this.gather(idx, r.start, r.count, false);
    const out: TableCell[][] = [];
    for (let i = 0; i < r.count; i++) out.push(cols.map((c) => cellOf(c, i)));
    return out;
  }

  /**
   * The rows listed, in their order (repeats allowed), as `readRows`
   * gives them. Nearby rows are read together, and each page they need
   * is decompressed once.
   */
  readRowsAt(rows: readonly number[], columns?: readonly (number | string)[]): TableCell[][] {
    const idx = columns ? columns.map((c) => this.index(c)) : this.all();
    const spans = this.spansOf(rows);
    const where = new Map<number, [TableColumn[], number]>();
    for (const s of spans) {
      const cols = this.gather(idx, s.start, s.count, false);
      for (let i = 0; i < s.count; i++) where.set(s.start + i, [cols, i]);
    }
    return rows.map((r) => {
      const [cols, i] = where.get(r)!;
      return cols.map((c) => cellOf(c, i));
    });
  }

  /** @internal The windows `readRowsAt` reads for `rows`. */
  spansOf(rows: readonly number[]): { start: number; count: number }[] {
    for (const r of rows) {
      if (!Number.isInteger(r) || r < 0 || r >= this.info.nobs) {
        throw dtaError("DTA_OUT_OF_RANGE", `row ${r} is outside 0 to ${this.info.nobs - 1}`, undefined, RangeError);
      }
    }
    const sorted = Float64Array.from(new Set(rows)).sort();
    const spans: { start: number; count: number }[] = [];
    for (const r of sorted) {
      const last = spans[spans.length - 1];
      // Rows close together are read as one window: a few extra rows cost
      // less than another pass over the same pages.
      if (last && r - (last.start + last.count) < 64) last.count = r - last.start + 1;
      else spans.push({ start: r, count: 1 });
    }
    return spans;
  }

  /** @internal The byte ranges a read of these variables over these rows needs. */
  planRanges(columns: readonly (number | string)[] | undefined, start: number, count: number): [number, number][] {
    const idx = columns ? columns.map((c) => this.index(c)) : this.all();
    if (count === 0 || idx.length === 0) return [];
    for (const k of idx) this.readable(k);
    const pairs = wasm.pqPlan(this.open, idx.map((k) => this.core[k]), start, count);
    const out: [number, number][] = [];
    for (let i = 0; i + 1 < pairs.length; i += 2) out.push([pairs[i], pairs[i + 1]]);
    return out;
  }

  /** @internal Bytes held by the page cache, its hits and misses. */
  cacheStats(): [number, number, number] {
    return wasm.pqCacheStats(this.open);
  }

  private readable(k: number): ParquetVariable {
    const v = this.variables[k];
    if (v.columnKind === null) throw dtaError("DTA_INVALID", v.notRead ?? `column ${JSON.stringify(v.name)} is not read`, undefined, TypeError);
    return v;
  }

  /**
   * The module calls a read makes: whole row groups at a time while their
   * output fits the budget, else fewer columns at a time, else fewer rows,
   * by the footer's sizes.
   */
  private calls(idx: number[], start: number, count: number): Call[] {
    const groups = this.info.rowGroups;
    const perRow = (k: number, g: number): number => {
      const v = this.variables[idx[k]];
      if (v.columnKind === "string") {
        const bytes = this.textBytes[idx[k]]?.[g];
        const rows = groups[g].rows || 1;
        return 9 + (bytes !== undefined ? bytes / rows : 64);
      }
      return v.columnKind === "dictionary" ? 4 : 9;
    };
    const all = idx.map((_, k) => k);
    const rowBytes = (g: number) => all.reduce((n, k) => n + perRow(k, g), 0);
    const out: Call[] = [];
    const end = start + count;
    let g = 0;
    while (g < groups.length && groups[g].firstRow + groups[g].rows <= start) g++;
    let s = start;
    while (s < end && g < groups.length) {
      let spanEnd = Math.min(end, groups[g].firstRow + groups[g].rows);
      let bytes = rowBytes(g) * (spanEnd - s);
      if (bytes <= BUDGET) {
        let next = g + 1;
        while (spanEnd < end && next < groups.length) {
          const e = Math.min(end, groups[next].firstRow + groups[next].rows);
          const add = rowBytes(next) * (e - spanEnd);
          if (bytes + add > BUDGET) break;
          bytes += add;
          spanEnd = e;
          next++;
        }
        out.push({ cols: all, start: s, count: spanEnd - s });
        s = spanEnd;
        g = next;
        continue;
      }
      let group: number[] = [];
      let held = 0;
      for (const k of all) {
        const b = perRow(k, g) * (spanEnd - s);
        if (b > BUDGET) {
          const step = Math.max(1, Math.floor(BUDGET / perRow(k, g)));
          for (let r = s; r < spanEnd; r += step) out.push({ cols: [k], start: r, count: Math.min(step, spanEnd - r) });
          continue;
        }
        if (held + b > BUDGET) {
          out.push({ cols: group, start: s, count: spanEnd - s });
          group = [];
          held = 0;
        }
        group.push(k);
        held += b;
      }
      if (group.length) out.push({ cols: group, start: s, count: spanEnd - s });
      s = spanEnd;
      g++;
    }
    return out;
  }

  /** Read rows `start` to `start + count` of the variables at `idx` into columns. */
  private gather(idx: number[], start: number, count: number, asDictionary: boolean): TableColumn[] {
    // A variable asked for twice is read once (the module's text
    // dictionary is one per column, so a second copy in one call would
    // get codes without their values), and each later position gets a
    // copy of its own.
    const distinct = [...new Set(idx)];
    if (distinct.length < idx.length) {
      const read = this.gather(distinct, start, count, asDictionary);
      const given = new Set<number>();
      return idx.map((k) => {
        const col = read[distinct.indexOf(k)];
        if (!given.has(k)) {
          given.add(k);
          return col;
        }
        return copyColumn(col);
      });
    }
    const vars = idx.map((k) => this.readable(k));
    let out: TableColumn[];
    try {
      out = vars.map((v): TableColumn => {
        switch (v.columnKind) {
          case "number":
            return { kind: "number", values: new Float64Array(count), missing: new Uint8Array(count) };
          case "bigint":
            return {
              kind: "bigint",
              values: v.physicalType === "INT64" && v.type === "uint64" ? new BigUint64Array(count) : new BigInt64Array(count),
              missing: new Uint8Array(count),
            };
          case "dictionary":
            return { kind: "dictionary", codes: new Uint32Array(count), values: v.categorical?.levels ? [...v.categorical.levels] : [], missing: new Uint8Array(count) };
          default:
            return asDictionary && v.type !== "binary"
              ? { kind: "dictionary", codes: new Uint32Array(count), values: [], missing: new Uint8Array(count) }
              : { kind: "string", values: new Array<string | Uint8Array>(count), missing: new Uint8Array(count) };
        }
      });
    } catch (e) {
      if (isAllocationFailure(e)) throw dtaError("DTA_TOO_LARGE", `${count} rows of ${idx.length} variables do not fit in memory`, e);
      throw e;
    }
    if (count === 0 || idx.length === 0) return out;
    const state: Gathering[] = idx.map(() => ({ seen: [], found: [], foundIndex: new Map() }));
    const handle = this.open;
    let first = true;
    try {
      // The plan is by the footer's average sizes; the module counts the
      // text it gathers, and a call whose text passes the budget is read
      // again in halves, then a column at a time.
      const work = this.calls(idx, start, count).reverse();
      while (work.length) {
        const call = work.pop()!;
        const cols = call.cols.map((k) => this.core[idx[k]]);
        const fixed = call.count * call.cols.reduce((n, k) => n + (vars[k].columnKind === "dictionary" ? 4 : 9), 0);
        const n = wasm.pqRead(handle, cols, call.start, call.count, (first ? NEW_READ : 0) | DICTIONARY, Math.max(1, BUDGET - fixed));
        if (n === wasm.OVER_BUDGET) {
          if (call.count > 1) {
            const half = Math.ceil(call.count / 2);
            work.push({ cols: call.cols, start: call.start + half, count: call.count - half });
            work.push({ cols: call.cols, start: call.start, count: half });
          } else if (call.cols.length > 1) {
            for (let j = call.cols.length - 1; j >= 0; j--) work.push({ cols: [call.cols[j]], start: call.start, count: 1 });
          } else {
            throw dtaError("DTA_TOO_LARGE", `column ${JSON.stringify(vars[call.cols[0]].name)}: the value in row ${call.start} is more than the ${BUDGET} bytes one read of the module may hold`);
          }
          continue;
        }
        first = false;
        const dir = wasm.pqDirectory(handle);
        const at = call.start - start;
        call.cols.forEach((k, j) => {
          out[k] = place(out[k], dir.subarray(10 * j, 10 * j + 10), at, n, state[k], vars[k]);
          // Mode 6 (level codes) gives, for a categorical holding .a to .z,
          // the first row (from 1) whose value is not a level number.
          const bad = dir[10 * j] === 6 ? dir[10 * j + 8] : 0;
          if (bad && (state[k].bad === undefined || call.start + bad - 1 < state[k].bad!)) state[k].bad = call.start + bad - 1;
        });
      }
    } catch (e) {
      if (e instanceof RangeError && !("code" in e) && /string length/i.test(e.message)) {
        throw dtaError("DTA_TOO_LARGE", "a string is longer than JavaScript allows", e);
      }
      throw e;
    } finally {
      wasm.pqReadEnd(handle);
    }
    const bad: string[] = [];
    state.forEach((st, k) => {
      if (st.bad === undefined || this.warnedCategorical.has(idx[k])) return;
      this.warnedCategorical.add(idx[k]);
      bad.push(`column ${JSON.stringify(vars[k].name)}: row ${st.bad} holds a value that is not one of its ${vars[k].categorical?.levels?.length ?? 0} level numbers; it is read as .`);
    });
    if (bad.length) {
      const proc = (globalThis as { process?: { emitWarning?: (w: string, o: { code: string }) => void } }).process;
      if (proc?.emitWarning) proc.emitWarning(bad.join("\n"), { code: "DATAKIT_CATEGORICAL" });
      else console.warn(`DATAKIT_CATEGORICAL: ${bad.join("\n")}`);
    }
    return out;
  }

  /** Release the file (and close it, if `openParquetFile` opened it by path). Further reads throw. */
  close(): void {
    if (this.handle !== 0) {
      if (this.generation === wasm.currentGeneration()) wasm.pqClose(this.handle);
      unclosed.unregister(this);
      wasm.forget(this.read);
      this.handle = 0;
      this.onClose?.();
    }
  }

  /** `close()`, so `using r = openParquetFile(path)` closes the reader at the end of its block. */
  [Symbol.dispose](): void {
    this.close();
  }
}

/** A column with arrays of its own. */
function copyColumn(c: TableColumn): TableColumn {
  switch (c.kind) {
    case "number":
      return { kind: "number", values: c.values.slice(), missing: c.missing.slice() };
    case "bigint":
      return { kind: "bigint", values: c.values.slice(), missing: c.missing.slice() } as BigIntColumn;
    case "dictionary":
      return { kind: "dictionary", codes: c.codes.slice(), values: [...c.values], missing: c.missing?.slice() };
    default:
      return { kind: "string", values: [...c.values], missing: c.missing?.slice() };
  }
}

/** Copy one call's column from the module into `col`, from row `at`; returns the column (a new one if it had to change kind). */
function place(col: TableColumn, d: Uint32Array, at: number, n: number, st: Gathering, v: ParquetVariable): TableColumn {
  switch (d[0]) {
    case 0: {
      const c = col as NumberColumn;
      c.values.set(wasm.memView(d[2], d[3], "f64"), at);
      c.missing.set(wasm.memView(d[4], d[5], "u8"), at);
      return c;
    }
    case 1:
    case 2: {
      const c = col as BigIntColumn;
      if (d[0] === 1) (c.values as BigInt64Array).set(wasm.memView(d[2], d[3], "i64"), at);
      else (c.values as BigUint64Array).set(wasm.memView(d[2], d[3], "u64"), at);
      c.missing.set(wasm.memView(d[4], d[5], "u8"), at);
      return c;
    }
    case 3: {
      // Codes into the read's dictionary, and the values new in this call.
      const codes = wasm.memView(d[2], d[3], "u32");
      if (d[7] > 0) {
        const text = utf8.decode(wasm.memView(d[4], d[5], "u8"));
        const ends = wasm.memView(d[6], d[7], "u32");
        let from = 0;
        for (let i = 0; i < ends.length; i++) {
          st.seen.push(text.substring(from, ends[i]));
          from = ends[i];
        }
      }
      if (col.kind === "dictionary") {
        col.values = st.seen;
        for (let i = 0; i < n; i++) {
          const c = codes[i];
          if (c === NULL_CODE) col.missing![at + i] = 1;
          else col.codes[at + i] = c;
        }
        return col;
      }
      const c = col as StringColumn;
      for (let i = 0; i < n; i++) {
        const k = codes[i];
        if (k === NULL_CODE) {
          c.values[at + i] = "";
          c.missing![at + i] = 1;
        } else c.values[at + i] = st.seen[k];
      }
      return c;
    }
    case 4:
    case 5: {
      let c = col;
      if (c.kind === "dictionary") {
        // A dictionary given up: the rows so far as strings.
        const strings = new Array<string | Uint8Array>(c.codes.length);
        for (let i = 0; i < at; i++) strings[i] = c.missing![i] ? "" : c.values[c.codes[i]];
        c = { kind: "string", values: strings, missing: c.missing };
      }
      const s = c as StringColumn;
      const bytes = wasm.memView(d[2], d[3], "u8");
      const byteEnds = wasm.memView(d[4], d[5], "u32");
      s.missing!.set(wasm.memView(d[6], d[7], "u8"), at);
      const missing = s.missing!;
      if (d[0] === 5) {
        let from = 0;
        for (let i = 0; i < n; i++) {
          s.values[at + i] = missing[at + i] ? EMPTY : bytes.slice(from, byteEnds[i]);
          from = byteEnds[i];
        }
        return s;
      }
      // One decode for the call's text, then a substring per row.
      const text = utf8.decode(bytes);
      const ends = d[1] ? wasm.memView(d[8], d[9], "u32") : byteEnds;
      let from = 0;
      for (let i = 0; i < n; i++) {
        s.values[at + i] = text.substring(from, ends[i]);
        from = ends[i];
      }
      return s;
    }
    default: {
      // Level codes from 0, -1 for a null.
      const c = col as DictionaryColumn;
      const codes = wasm.memView(d[2], d[3], "i32");
      let map: Int32Array | undefined;
      if (!v.categorical?.levels) {
        // Levels found in this call's rows: give each its code over the read.
        const text = utf8.decode(wasm.memView(d[4], d[5], "u8"));
        const ends = wasm.memView(d[6], d[7], "u32");
        map = new Int32Array(ends.length);
        let from = 0;
        for (let i = 0; i < ends.length; i++) {
          const level = text.substring(from, ends[i]);
          from = ends[i];
          let k = st.foundIndex.get(level);
          if (k === undefined) {
            k = st.found.length;
            st.found.push(level);
            st.foundIndex.set(level, k);
          }
          map[i] = k;
        }
        c.values = st.found;
      }
      for (let i = 0; i < n; i++) {
        const k = codes[i];
        // -1 is ., -2 to -27 .a to .z (a categorical holding them, plan 0022).
        if (k < 0) c.missing![at + i] = -k;
        else c.codes[at + i] = map ? map[k] : k;
      }
      return c;
    }
  }
}

/** Row `i` of a column as a cell. */
function cellOf(c: TableColumn, i: number): TableCell {
  switch (c.kind) {
    case "number":
      return c.missing[i] ? missingValue(c.missing[i]) : c.values[i];
    case "bigint":
      return c.missing[i] ? MISSING["."] : c.values[i];
    case "dictionary":
      return c.missing?.[i] ? missingValue(c.missing[i]) : c.values[c.codes[i]];
    default:
      return c.missing?.[i] ? MISSING["."] : c.values[i];
  }
}

/** Open a Parquet file held in memory. Only the footer is read now. */
export function openParquet(bytes: Uint8Array, options: ParquetOptions = {}): ParquetReader {
  return new ParquetReader(
    (into, offset) => {
      if (offset + into.length > bytes.length) throw new RangeError("read past the end of the file");
      into.set(bytes.subarray(offset, offset + into.length));
    },
    bytes.length,
    options,
  );
}

// ---------------------------------------------------------------- async

/** A read the async reader had not fetched yet. */
class Miss extends Error {
  constructor(
    readonly offset: number,
    readonly length: number,
  ) {
    super(`bytes ${offset} to ${offset + length} have not been fetched`);
  }
}

function missOf(e: unknown): Miss | undefined {
  const cause = (e as { cause?: unknown })?.cause;
  return e instanceof Miss ? e : cause instanceof Miss ? cause : undefined;
}

/** Fetched byte ranges of a file, for the sync reader inside the async one. */
class RangeStore {
  private entries: { start: number; end: number; bytes: Uint8Array; pinned: boolean; used: number }[] = [];
  private tick = 0;

  constructor(
    private readonly fetch: (offset: number, length: number) => Promise<Uint8Array>,
    private readonly size: number,
    private readonly budget: number,
  ) {}

  readonly read: ReadAt = (into, offset) => {
    const end = offset + into.length;
    for (const e of this.entries) {
      if (e.start <= offset && end <= e.end) {
        into.set(e.bytes.subarray(offset - e.start, end - e.start));
        e.used = ++this.tick;
        return;
      }
    }
    throw new Miss(offset, into.length);
  };

  private has(start: number, end: number): boolean {
    return this.entries.some((e) => e.start <= start && end <= e.end);
  }

  /** Fetch what of `ranges` is not here yet, ranges less than 64 KiB apart together. */
  async ensure(ranges: [number, number][], pin = false): Promise<void> {
    const want = ranges
      .map(([a, b]): [number, number] => [Math.max(0, a), Math.min(this.size, b)])
      .filter(([a, b]) => b > a && !this.has(a, b))
      .sort((x, y) => x[0] - y[0]);
    const merged: [number, number][] = [];
    for (const r of want) {
      const last = merged[merged.length - 1];
      if (last && r[0] - last[1] < 65536) last[1] = Math.max(last[1], r[1]);
      else merged.push([r[0], r[1]]);
    }
    await Promise.all(
      merged.map(async ([a, b]) => {
        let bytes: Uint8Array;
        try {
          bytes = await this.fetch(a, b - a);
        } catch (e) {
          throw dtaError("DTA_IO", `reading bytes ${a} to ${b} of the file failed`, e);
        }
        if (!(bytes instanceof Uint8Array) || bytes.length !== b - a) {
          throw dtaError("DTA_IO", `reading bytes ${a} to ${b} of the file gave ${(bytes as Uint8Array)?.length} bytes, not ${b - a}`);
        }
        this.entries.push({ start: a, end: b, bytes, pinned: pin, used: ++this.tick });
      }),
    );
  }

  /** @internal Drop the least recently used ranges that are not pinned, down to the budget. */
  trim(): void {
    let held = this.entries.reduce((n, e) => n + (e.pinned ? 0 : e.end - e.start), 0);
    if (held <= this.budget) return;
    const order = this.entries.filter((e) => !e.pinned).sort((a, b) => a.used - b.used);
    const drop = new Set<object>();
    for (const e of order) {
      if (held <= this.budget) break;
      drop.add(e);
      held -= e.end - e.start;
    }
    this.entries = this.entries.filter((e) => !drop.has(e));
  }
}

/**
 * A Parquet file read through an async function (`openParquetAsync`):
 * the members of `ParquetReader`, with `readColumns`, `readRows` and
 * `readRowsAt` returning promises. Each call fetches the byte ranges it
 * needs, then decodes them as `ParquetReader` does, so the results are
 * the same.
 */
export class AsyncParquetReader implements AsyncTableReader {
  readonly info: ParquetInfo;
  readonly variables: readonly ParquetVariable[];

  /** @internal Use `openParquetAsync`. */
  constructor(
    private readonly sync: ParquetReader,
    private readonly store: RangeStore,
  ) {
    this.info = sync.info;
    this.variables = sync.variables;
  }

  /** Run `op`, fetching what it needs first and whatever it then finds missing. */
  private async run<T>(op: () => T, plan: () => [number, number][]): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        await this.store.ensure(plan());
        const result = op();
        this.store.trim();
        return result;
      } catch (e) {
        const m = missOf(e);
        if (!m || attempt >= 64) throw e;
        await this.store.ensure([[m.offset, m.offset + m.length]]);
      }
    }
  }

  /** As `ParquetReader.readColumns`. */
  readColumns(columns: readonly (number | string)[], range: ReadRange = {}): Promise<TableColumn[]> {
    const start = range.start ?? 0;
    const count = range.count ?? this.info.nobs - start;
    return this.run(
      () => this.sync.readColumns(columns, range),
      () => (Number.isInteger(start) && Number.isInteger(count) && start >= 0 && count >= 0 && start + count <= this.info.nobs ? this.sync.planRanges(columns, start, count) : []),
    );
  }

  /** As `ParquetReader.readRows`. */
  readRows(start: number, count: number, columns?: readonly (number | string)[]): Promise<TableCell[][]> {
    return this.run(
      () => this.sync.readRows(start, count, columns),
      () => (Number.isInteger(start) && Number.isInteger(count) && start >= 0 && count >= 0 && start + count <= this.info.nobs ? this.sync.planRanges(columns, start, count) : []),
    );
  }

  /** As `ParquetReader.readRowsAt`. */
  readRowsAt(rows: readonly number[], columns?: readonly (number | string)[]): Promise<TableCell[][]> {
    return this.run(
      () => this.sync.readRowsAt(rows, columns),
      () => this.sync.spansOf(rows).flatMap((s) => this.sync.planRanges(columns, s.start, s.count)),
    );
  }

  /** As `ParquetReader.valueLabels`. */
  valueLabels(name: string): ValueLabels | undefined {
    return this.sync.valueLabels(name);
  }

  /** As `ParquetReader.valueLabelNames`. */
  valueLabelNames(): string[] {
    return this.sync.valueLabelNames();
  }

  /** As `ParquetReader.characteristics`. */
  characteristics(): Characteristic[] {
    return this.sync.characteristics();
  }

  /** As `ParquetReader.notes`. */
  notes(): string[] {
    return this.sync.notes();
  }

  /** As `ParquetReader.keyValue`. */
  keyValue(key: string): string | undefined {
    return this.sync.keyValue(key);
  }

  /** As `ParquetReader.close`; the fetched bytes are dropped. */
  close(): void {
    this.sync.close();
  }

  /** `close()`, for `using`. */
  [Symbol.dispose](): void {
    this.close();
  }
}

/**
 * Open a Parquet file read through `readAt(offset, length)`, which
 * resolves to that many bytes from `offset`: for browsers, and remote
 * files over HTTP range requests. `size` is the file's length. The
 * footer is fetched now (the last 512 KiB, then more if it is longer),
 * and the offset indexes when they take at most 16 MiB; each read then
 * fetches the byte ranges it needs. Fetched pages are kept up to
 * `pageCacheBytes`.
 */
export async function openParquetAsync(
  readAt: (offset: number, length: number) => Promise<Uint8Array>,
  size: number,
  options: ParquetOptions = {},
): Promise<AsyncParquetReader> {
  if (!Number.isSafeInteger(size) || size < 0) throw dtaError("DTA_INVALID", `size must be a whole number of bytes, not ${size}`, undefined, RangeError);
  const store = new RangeStore(readAt, size, options.pageCacheBytes ?? DEFAULT_CACHE);
  const tail = Math.min(size, 512 * 1024);
  await store.ensure([[size - tail, size], [0, Math.min(4, size)]], true);
  if (size >= 12) {
    const t = new Uint8Array(8);
    store.read(t, size - 8);
    const footer = new DataView(t.buffer).getUint32(0, true);
    if (footer + 8 > tail && footer + 8 <= size) await store.ensure([[size - 8 - footer, size - tail]], true);
  }
  let sync: ParquetReader | undefined;
  for (let attempt = 0; !sync; attempt++) {
    try {
      sync = new ParquetReader(store.read, size, options);
    } catch (e) {
      const m = missOf(e);
      if (!m || attempt >= 8) throw e;
      await store.ensure([[m.offset, m.offset + m.length]], true);
    }
  }
  const span = sync._indexSpan;
  if (span && span[1] - span[0] <= 16 * 2 ** 20) {
    try {
      await store.ensure([span], true);
    } catch (e) {
      sync.close();
      throw e;
    }
  }
  return new AsyncParquetReader(sync, store);
}

// ---------------------------------------------------------------- write

/** How `writeParquet` writes. */
export interface ParquetWriteOptions {
  /**
   * The codec: `"snappy"` (the default), `"zstd"` (C libzstd), `"gzip"`,
   * `"lz4_raw"` or `"none"`.
   */
  compression?: "snappy" | "zstd" | "gzip" | "lz4_raw" | "none";
  /** The codec's level (gzip 0 to 10, zstd 1 to 22); default the codec's own (zstd 3). */
  compressionLevel?: number;
  /**
   * Rows per row group. By default a row group holds up to 262,144 rows
   * and about 1 GiB of values.
   */
  rowGroupSize?: number;
  /**
   * Write `.a` to `.z` (default true) as tagged NaNs, so this package and
   * R's Parquet readers give them back; a numeric, date or timestamp
   * column holding any is written as DOUBLE. With false they are written
   * as nulls, for SQL engines and polars, and the letters are lost.
   */
  missingLetters?: boolean;
}

/** Numbers' kinds, as the module takes them. */
const NUMBER_TYPES: Record<string, number> = {
  byte: 0,
  int: 1,
  long: 2,
  float: 3,
  double: 4,
  bool: 5,
  date: 6,
  timestamp: 7,
  int64: 8,
  // What other tools' files read as, written back without loss.
  uint8: 1,
  uint16: 2,
  uint32: 8,
  decimal: 4,
};
const UNITS: Record<string, number> = { s: 0, ms: 1, us: 2, ns: 3 };
const TEXT_TYPES = new Set(["string", "strL", "binary", "decimal"]);

function nul(text: string | undefined, what: string): string {
  if (text?.includes("\0")) throw dtaError("DTA_INVALID", `${what} contains a NUL`, undefined, TypeError);
  return text ?? "";
}

/** How many values a variable holds. */
function rowsOf(v: DatasetVariable): number {
  const x = v.values as unknown;
  if (Array.isArray(x) || ArrayBuffer.isView(x)) return (x as { length: number }).length;
  const c = x as TableColumn;
  return c.kind === "dictionary" ? c.codes.length : c.values.length;
}

/** One variable as the module takes it. */
/** Rows sampled, spread over the column, to judge whether its text repeats. */
const CODE_PROBE = 4096;

/**
 * A text column as its distinct values and a code per row (-1 for a
 * null), when values repeat: far less to copy into the module than the
 * text of every row. Undefined when a sample of rows spread over the
 * column is mostly distinct, or once the distinct values pass an eighth
 * of the rows.
 */
function textCodes(values: readonly (string | Uint8Array | null)[], missing: Uint8Array | undefined): { bytes: Uint8Array; ends: Uint32Array; codes: Int32Array } | undefined {
  const rows = values.length;
  if (rows > 2 * CODE_PROBE) {
    const sample = new Set<string>();
    const step = rows / CODE_PROBE;
    let looked = 0;
    for (let j = 0; j < CODE_PROBE; j++) {
      const i = Math.floor(j * step);
      const x = values[i];
      if (x === null || missing?.[i]) continue;
      sample.add(x as string);
      looked++;
    }
    if (sample.size > looked / 2) return undefined;
  }
  const most = Math.max(256, rows >>> 3);
  const seen = new Map<string, number>();
  const distinct: string[] = [];
  const codes = new Int32Array(rows);
  for (let i = 0; i < rows; i++) {
    const x = values[i];
    if (x === null || missing?.[i]) {
      codes[i] = -1;
      continue;
    }
    let k = seen.get(x as string);
    if (k === undefined) {
      k = distinct.length;
      if (k >= most) return undefined;
      seen.set(x as string, k);
      distinct.push(x as string);
    }
    codes[i] = k;
  }
  return { ...packTexts(distinct), codes };
}

function partOf(v: DatasetVariable, rows: number): wasm.ParquetPart {
  const fail = (why: string): never => {
    throw dtaError("DTA_INVALID", `${v.name}: ${why}`, undefined, TypeError);
  };
  const type = v.type;
  const zone = v.timeZone;
  const meta = [
    nul(v.name, "a variable name"),
    nul(v.format, `the format of ${v.name}`),
    nul(v.label, `the label of ${v.name}`),
    nul(v.valueLabels, `the value label set of ${v.name}`),
    zone === undefined ? "0" : "1",
    nul(zone, `the time zone of ${v.name}`),
  ].join("\0");
  const length = (n: number) => {
    if (n !== rows) throw dtaError("DTA_INVALID", `${v.name} has ${n} values, not ${rows}`, undefined, RangeError);
  };
  const unit = () => {
    const u = UNITS[v.unit ?? "us"];
    if (u === undefined) fail(`unknown unit ${JSON.stringify(v.unit)}; use "s", "ms", "us" or "ns"`);
    return u;
  };
  const numbers = (values: Float64Array, missing: Uint8Array): wasm.ParquetPart => {
    length(values.length);
    if (missing.length !== rows) fail(`${missing.length} missing codes, not ${rows}`);
    const levels = v.levels ?? v.categorical?.levels;
    if (type === "categorical" || (type === undefined && levels)) {
      if (!levels) fail("a categorical needs its levels");
      const codes = new Int32Array(rows);
      for (let i = 0; i < rows; i++) {
        const x = values[i];
        // -1 is ., -2 to -27 .a to .z (plan 0022).
        if (missing[i] > 27) fail(`row ${i} has missing code ${missing[i]}; codes run from 0 to 27`);
        else if (missing[i]) codes[i] = -missing[i];
        else if (!Number.isInteger(x) || x < 0 || x >= levels!.length) fail(`row ${i} holds ${x}, not a level code from 0 to ${levels!.length - 1}`);
        else codes[i] = x;
      }
      return categorical(codes, levels!);
    }
    let kind = NUMBER_TYPES[type ?? "double"];
    if (kind === undefined) fail(`numbers cannot be written as ${JSON.stringify(type)}`);
    if (kind === 6) {
      // A date with a fraction of a day, or beyond an INT32 of days, is
      // written as doubles (kind 9), a date again for our readers.
      for (let i = 0; i < rows; i++) {
        const x = values[i];
        if (missing[i] === 0 && !(Number.isInteger(x) && x >= -(2 ** 31) && x < 2 ** 31)) {
          kind = 9;
          break;
        }
      }
    }
    return { kind: "numbers", meta, type: kind, unit: kind === 7 ? unit() : 0, values, missing };
  };
  const bigints = (values: BigInt64Array | BigUint64Array, missing: Uint8Array): wasm.ParquetPart => {
    length(values.length);
    if (missing.length !== rows) fail(`${missing.length} missing codes, not ${rows}`);
    let signed: BigInt64Array;
    if (values instanceof BigUint64Array) {
      const big = values.findIndex((x, i) => !missing[i] && x >= 2n ** 63n);
      if (big >= 0) fail(`row ${big} holds ${values[big]}, more than a signed 64-bit integer holds`);
      signed = new BigInt64Array(values.buffer, values.byteOffset, values.length);
    } else signed = values;
    const t = type ?? "int64";
    const kind = t === "timestamp" ? 7 : t === "int64" || t === "uint64" ? 8 : undefined;
    if (kind === undefined) fail(`64-bit integers can be written as "int64" or "timestamp", not ${JSON.stringify(t)}`);
    return { kind: "bigints", meta, type: kind!, unit: kind === 7 ? unit() : 0, values: signed, missing };
  };
  const texts = (values: readonly (string | Uint8Array | null)[], missing?: Uint8Array): wasm.ParquetPart => {
    length(values.length);
    if (type !== undefined && !TEXT_TYPES.has(type) && !/^str/.test(type)) fail(`text cannot be written as ${JSON.stringify(type)}`);
    let binary = type === "binary";
    for (let i = 0; i < rows; i++) {
      const x = values[i];
      if (x === null || missing?.[i] || typeof x === "string") continue;
      if (x instanceof Uint8Array) binary = true;
      else fail(`row ${i} holds ${typeof x}, among strings`);
    }
    if (!binary) {
      const coded = textCodes(values, missing);
      if (coded) return { kind: "textCodes", meta, ...coded };
    }
    const flags = new Uint8Array(rows);
    // Packed from the column itself, a missing row as "".
    const packed = packTextsBy(rows, (i) => {
      const x = values[i];
      if (x === null || missing?.[i]) {
        flags[i] = 1;
        return "";
      }
      return x;
    });
    return { kind: "texts", meta, binary, ...packed, missing: flags };
  };
  const categorical = (codes: Int32Array, levels: readonly string[]): wasm.ParquetPart => {
    const packed = packTexts(levels);
    return { kind: "categorical", meta, ordered: v.ordered ?? v.categorical?.ordered ?? false, codes, levels: packed.bytes, ends: packed.ends };
  };

  const x = v.values;
  if (x instanceof Float64Array) return numbers(x, v.missing ?? new Uint8Array(x.length));
  if (x instanceof BigInt64Array || x instanceof BigUint64Array) return bigints(x, v.missing ?? new Uint8Array(x.length));
  if (Array.isArray(x)) {
    const arr = x as readonly unknown[];
    const firstValue = arr.find((e) => e !== null && e !== undefined);
    if (typeof firstValue === "bigint" || type === "int64" && arr.some((e) => typeof e === "bigint")) {
      length(arr.length);
      const values = new BigInt64Array(rows);
      const missing = new Uint8Array(rows);
      arr.forEach((e, i) => {
        if (e === null) missing[i] = 1;
        else if (typeof e !== "bigint") fail(`row ${i} holds ${typeof e}, among bigints`);
        else if (e < -(2n ** 63n) || e >= 2n ** 63n) fail(`row ${i} holds ${e}, beyond a 64-bit integer`);
        else values[i] = e;
      });
      return bigints(values, missing);
    }
    const textual = type !== undefined ? TEXT_TYPES.has(type) || /^str/.test(type) : arr.some((e) => typeof e === "string" || e instanceof Uint8Array);
    if (textual) return texts(arr as readonly (string | Uint8Array | null)[]);
    if (arr.some((e) => typeof e === "string" || e instanceof Uint8Array)) fail(`${type} but holds strings`);
    const packed = packNumbers(arr as readonly (number | { missing: never } | null)[]);
    return numbers(packed.values, packed.missing);
  }
  const c = x as TableColumn;
  switch (c.kind) {
    case "number":
      return numbers(c.values, c.missing);
    case "bigint":
      return bigints(c.values, c.missing);
    case "string":
      return texts(c.values, c.missing);
    case "dictionary": {
      length(c.codes.length);
      if (type === undefined || type === "categorical") {
        const codes = new Int32Array(rows);
        for (let i = 0; i < rows; i++) {
          const m = c.missing?.[i] ?? 0;
          if (m > 27) fail(`row ${i} has missing code ${m}; codes run from 0 to 27`);
          codes[i] = m ? -m : c.codes[i];
        }
        return categorical(codes, c.values);
      }
      if (type !== undefined && !TEXT_TYPES.has(type) && !/^str/.test(type)) fail(`text cannot be written as ${JSON.stringify(type)}`);
      // Already codes and distinct values: handed over as they are.
      const codes = new Int32Array(rows);
      for (let i = 0; i < rows; i++) {
        const k = c.codes[i];
        if (c.missing?.[i]) codes[i] = -1;
        else if (k >= c.values.length) fail(`row ${i} has code ${k}, but there are ${c.values.length} values`);
        else codes[i] = k;
      }
      return { kind: "textCodes", meta, ...packTexts(c.values), codes };
    }
    default:
      return fail("values of an unknown kind");
  }
}

/**
 * Write a Parquet file, handing its bytes to `sink` in order. It takes
 * a `Dataset` (as `saveParquet` does): variable labels, display
 * formats and value labels go into the file's dta profile, `.` is a null
 * and `.a` to `.z` are kept (see `missingLetters`). A value that does not
 * fit its type is an error naming the variable and row.
 */
export function writeParquetTo(data: Dataset, sink: (bytes: Uint8Array) => void, options: ParquetWriteOptions = {}): void {
  const rows = data.variables.length ? rowsOf(data.variables[0]) : 0;
  // Each variable's part is made as it is handed to the module, so only
  // one column's packed text is held at a time.
  const parts: (wasm.ParquetPart | (() => wasm.ParquetPart))[] = data.variables.map((v) => () => partOf(v, rows));
  for (const [name, labels] of Object.entries(data.valueLabels ?? {})) {
    nul(name, "a value label set name");
    const keys = [...labels.keys()];
    for (const k of keys) {
      if (typeof k === "number" && (!Number.isFinite(k) || (Number.isInteger(k) && Math.abs(k) > 2 ** 53))) {
        throw dtaError("DTA_INVALID", `value label set ${name}: the code ${k} is not a finite number within ±2^53`, undefined, RangeError);
      }
    }
    const { bytes: texts, ends } = packTexts([...labels.values()]);
    parts.push({ kind: "labels", name, ...packNumbers(keys), texts, ends });
  }
  const names = data.variables.map((v) => v.name);
  const kept = new Set([...names, "_dta"]);
  const chars = (data.characteristics ?? []).filter((c) => kept.has(c.variable) && !(c.variable === "_dta" && /^note[0-9]+$/.test(c.name)));
  if (chars.length) {
    parts.push({
      kind: "characteristics",
      text: chars.flatMap((c) => [nul(c.variable, "a characteristic's variable"), nul(c.name, "a characteristic's name"), nul(c.value, `characteristic ${c.variable}[${c.name}]`)]).join("\0"),
    });
  }
  const sorted: string[] = [];
  for (const name of data.sortedBy ?? []) {
    if (!names.includes(name)) break;
    sorted.push(nul(name, "a sort name"));
  }
  if (sorted.length) parts.push({ kind: "sort", text: sorted.join("\0") });
  const compression = options.compression ?? "snappy";
  if (typeof compression !== "string") throw dtaError("DTA_INVALID", "compression must be a codec's name", undefined, TypeError);
  const level = options.compressionLevel;
  if (level !== undefined && !Number.isInteger(level)) throw dtaError("DTA_INVALID", `compressionLevel must be a whole number, not ${level}`, undefined, RangeError);
  const rgs = options.rowGroupSize;
  if (rgs !== undefined && (!Number.isInteger(rgs) || rgs < 1)) throw dtaError("DTA_INVALID", `rowGroupSize must be a whole number of rows of at least 1, not ${rgs}`, undefined, RangeError);
  wasm.pqWrite(
    rows,
    parts,
    [nul(data.label, "the data label"), ...(data.notes ?? []).map((n) => nul(n, "a note"))],
    { compression, level: level ?? NaN, rowGroupRows: rgs ?? 0, missingLetters: options.missingLetters ?? true },
    sink,
  );
}

/** Write a Parquet file into memory; see `writeParquetTo`. */
export function writeParquet(data: Dataset, options: ParquetWriteOptions = {}): Uint8Array {
  const chunks: Uint8Array[] = [];
  writeParquetTo(data, (bytes) => chunks.push(bytes.slice()), options);
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

// ---------------------------------------------------------------- dates

const DAY = 86_400_000;
/** Days from 1960-01-01, Stata's origin, to 1970-01-01. */
const STATA_DAYS = 3653;
/** The most milliseconds either side of 1970 a `Date` holds. */
const DATE_MS = 8.64e15;

/**
 * A date, time or timestamp value as a `Date`, or null when it is
 * missing or outside the range a `Date` holds (about 270,000 years
 * either side of 1970). Parts finer than a millisecond are dropped
 * (rounded toward the past). The value itself, in `readColumns`, keeps
 * every digit.
 *
 * `variable` says what the value counts: a Parquet variable's `unit`
 * (`"day"`, `"s"`, `"ms"`, `"us"` or `"ns"` since 1970-01-01; for a
 * time, since midnight on 1970-01-01), or else a .dta variable's display
 * format: `%td` days and `%tc` milliseconds since 1960-01-01. Other
 * variables give null. A timestamp with a `timeZone` is an instant, and
 * the `Date` is that instant; a clock time without zone gives the `Date`
 * whose UTC fields show it.
 */
export function toDate(value: number | bigint | null | undefined, variable: { unit?: string; format?: string }): Date | null {
  if (value === null || value === undefined) return null;
  let ms: number;
  if (typeof value === "bigint") {
    const per: Record<string, bigint> = { ns: 1_000_000n, us: 1_000n };
    const div = per[variable.unit ?? ""];
    if (div) {
      let q = value / div;
      if (value % div !== 0n && value < 0n) q -= 1n;
      if (q > 8_640_000_000_000_000n || q < -8_640_000_000_000_000n) return null;
      ms = Number(q);
    } else {
      if (value > 2n ** 53n || value < -(2n ** 53n)) return null;
      return toDate(Number(value), variable);
    }
  } else {
    if (!Number.isFinite(value)) return null;
    switch (variable.unit) {
      case "day":
        ms = value * DAY;
        break;
      case "s":
        ms = value * 1000;
        break;
      case "ms":
        ms = value;
        break;
      case "us":
        ms = value / 1000;
        break;
      case "ns":
        ms = value / 1e6;
        break;
      default: {
        const f = variable.format ?? "";
        if (/^%-?t?d/.test(f) && !/^%-?t[cC]/.test(f)) ms = (value - STATA_DAYS) * DAY;
        else if (/^%-?t[cC]/.test(f)) ms = value - STATA_DAYS * DAY;
        else return null;
      }
    }
    ms = Math.floor(ms);
  }
  if (!(Math.abs(ms) <= DATE_MS)) return null;
  return new Date(ms);
}
