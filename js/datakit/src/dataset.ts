// A whole table from any reader into a `ReadDataset`, and plan 0020's
// factors restored from a .dta file (plan 0021).

import type {
  AsyncTableReader,
  Characteristic,
  DictionaryColumn,
  TableColumn,
  TableReader,
  ValueLabels,
  Variable,
} from "@jbearak/dta-parser";
import { isMissing } from "@jbearak/dta-parser/format";
import { dtaError } from "./_shared/errors";
import type { ReadDataset, ReadVariable } from "./types";

/** Which variables and rows `readDataset` reads, and where its warnings go. */
export interface ReadDatasetOptions {
  /** Variables by name or 0-based index, in the order wanted; default all. */
  columns?: readonly (number | string)[];
  /** First row; default 0. */
  start?: number;
  /** How many rows; default all from `start`. */
  count?: number;
  /**
   * Takes the warnings, as messages, instead of `process.emitWarning`
   * (or `console.warn` where there is no `process`).
   */
  onWarning?: (messages: string[]) => void;
}

/** The marker plan 0020 writes on a factor's variable. */
export const FACTOR_MARK = "dtaparser_factor";

/** Long's range: the codes a restored factor may have. */
const LONG_MIN = -2147483647;
const LONG_MAX = 2147483620;

/** Give `messages` to `onWarning`, or emit them as one warning with `code`. */
export function warn(messages: string[], code: string, onWarning?: (messages: string[]) => void): void {
  if (messages.length === 0) return;
  if (onWarning) {
    onWarning(messages);
    return;
  }
  const shown = messages.slice(0, 8).map((m) => `* ${m.length <= 100 ? m : m.slice(0, 97) + "..."}`);
  if (messages.length > 8) shown.push(`${messages.length - 8} more; pass onWarning to see every one`);
  const text = shown.join("\n");
  const proc = (globalThis as { process?: { emitWarning?: (w: string, o: { code: string }) => void } }).process;
  if (proc?.emitWarning) proc.emitWarning(text, { code });
  else console.warn(`${code}: ${text}`);
}

function indicesOf(reader: { variables: readonly Variable[] }, columns?: readonly (number | string)[]): number[] {
  if (!columns) return reader.variables.map((_, i) => i);
  return columns.map((c) => {
    if (typeof c === "number") {
      if (!Number.isInteger(c) || c < 0 || c >= reader.variables.length) {
        throw dtaError("DTA_OUT_OF_RANGE", `no variable ${c}; the file has ${reader.variables.length}`, undefined, RangeError);
      }
      return c;
    }
    const k = reader.variables.findIndex((v) => v.name === c);
    if (k < 0) throw dtaError("DTA_OUT_OF_RANGE", `no variable ${JSON.stringify(c)}`, undefined, RangeError);
    return k;
  });
}

/**
 * Read a whole table, or the columns and rows asked for, from any reader
 * (`DtaReader`, `ParquetReader`, or another `TableReader`) into a
 * `ReadDataset`: its columns, every value label set, notes,
 * characteristics, label, sort order and (.dta) timestamp. For a .dta
 * file, plan 0020's factors come back as categoricals; see
 * docs/typescript.md, "Read a whole file".
 */
export function readDataset(reader: TableReader, options: ReadDatasetOptions = {}): ReadDataset {
  const ks = indicesOf(reader, options.columns);
  const range = options.start === undefined && options.count === undefined ? undefined : { start: options.start, count: options.count };
  const columns = ks.length ? reader.readColumns(ks, range) : [];
  return assemble(reader, ks, columns, options);
}

/** `readDataset` for an `AsyncTableReader` (`openParquetAsync`). */
export async function readDatasetAsync(reader: AsyncTableReader, options: ReadDatasetOptions = {}): Promise<ReadDataset> {
  const ks = indicesOf(reader, options.columns);
  const range = options.start === undefined && options.count === undefined ? undefined : { start: options.start, count: options.count };
  const columns = ks.length ? await reader.readColumns(ks, range) : [];
  return assemble(reader, ks, columns, options);
}

function assemble(
  reader: TableReader | AsyncTableReader,
  ks: number[],
  columns: TableColumn[],
  options: ReadDatasetOptions,
): ReadDataset {
  // Own properties, even for a set named "__proto__".
  const valueLabels: Record<string, ValueLabels> = Object.fromEntries(reader.valueLabelNames().map((name) => [name, reader.valueLabels(name)!]));
  const variables: ReadVariable[] = ks.map((k, j) => {
    const v = reader.variables[k];
    const out: ReadVariable = { name: v.name, type: v.type, format: v.format, label: v.label, valueLabels: v.valueLabels, values: columns[j] };
    if (v.unit !== undefined) out.unit = v.unit;
    if (v.timeZone !== undefined) out.timeZone = v.timeZone;
    if (v.categorical !== undefined) out.categorical = { levels: v.categorical.levels && [...v.categorical.levels], ordered: v.categorical.ordered };
    return out;
  });
  const dataset: ReadDataset = {
    variables,
    label: reader.info.label,
    notes: reader.notes(),
    valueLabels,
    characteristics: reader.characteristics(),
    sortedBy: [...reader.info.sortedBy],
  };
  if (reader.info.timestamp !== undefined) dataset.timestamp = reader.info.timestamp;
  if (reader.info.format === "dta") restoreFactors(dataset, options.onWarning);
  return dataset;
}

/**
 * Turn each variable marked `dtaparser_factor` whose marker still holds
 * into a categorical: plan 0020's four checks, and two more that make it
 * lossless (whole codes within long's range; no label on a missing
 * value). One that fails a check stays as read, with a warning.
 */
function restoreFactors(dataset: ReadDataset, onWarning?: (messages: string[]) => void): void {
  const marks = new Map<string, Characteristic>();
  for (const c of dataset.characteristics) if (c.name === FACTOR_MARK) marks.set(c.variable, c);
  if (marks.size === 0) return;
  const failed: string[] = [];
  const restored = new Set<string>();
  const restoredSets = new Set<string>();
  for (const v of dataset.variables) {
    const mark = marks.get(v.name);
    if (!mark) continue;
    const why = check(v, mark, dataset.valueLabels);
    if (typeof why === "string") {
      failed.push(`${v.name}: ${why}`);
      continue;
    }
    const { set, ordered } = why;
    const labels = dataset.valueLabels[set];
    const entries = [...labels].map(([code, text]) => [code as number, text] as const).sort((a, b) => a[0] - b[0]);
    const levels = entries.map(([, text]) => text);
    const codes = entries.map(([code]) => code);
    const index = new Map(codes.map((c, i) => [c, i]));
    const column = v.values as { values: Float64Array; missing: Uint8Array };
    const n = column.values.length;
    const dict: DictionaryColumn = { kind: "dictionary", codes: new Uint32Array(n), values: levels, missing: new Uint8Array(n) };
    for (let i = 0; i < n; i++) {
      if (column.missing[i]) dict.missing![i] = 1;
      else dict.codes[i] = index.get(column.values[i])!;
    }
    v.values = dict;
    v.type = "categorical";
    v.valueLabels = "";
    v.categorical = { levels, ordered, labelSet: set, codes };
    restored.add(v.name);
    restoredSets.add(set);
  }
  dataset.characteristics = dataset.characteristics.filter((c) => !(c.name === FACTOR_MARK && restored.has(c.variable)));
  // A restored factor's set leaves `valueLabels` unless a column read still uses it.
  const used = new Set(dataset.variables.map((v) => v.valueLabels).filter(Boolean));
  for (const set of restoredSets) if (!used.has(set)) delete dataset.valueLabels[set];
  if (failed.length) {
    warn(
      [`${failed.length === 1 ? "A column marked as a factor was" : "Columns marked as factors were"} changed after it was written, so ${failed.length === 1 ? "it is" : "they are"} read as labelled numbers:`, ...failed],
      "DATAKIT_FACTOR",
      onWarning,
    );
  }
}

/** The marker's set and ordering, or why it no longer holds. */
function check(v: ReadVariable, mark: Characteristic, sets: Record<string, ValueLabels>): { set: string; ordered: boolean } | string {
  const m = /^(ordered|unordered) (.+)$/.exec(mark.value);
  if (!m) return `its ${FACTOR_MARK} characteristic is not "ordered <set>" or "unordered <set>"`;
  const [, order, set] = m;
  if (v.values.kind !== "number") return "it is not numeric";
  if (v.valueLabels !== set) return `its value label set is ${v.valueLabels ? `"${v.valueLabels}"` : "none"}, not "${set}"`;
  const labels = sets[set];
  if (!labels) return `the file has no value label set "${set}"`;
  const texts = new Set<string>();
  for (const [code, text] of labels) {
    if (isMissing(code)) return `its value label set labels the missing value ${code.missing}`;
    if (!Number.isInteger(code) || code < LONG_MIN || code > LONG_MAX) return `its value label set has the code ${code}, which is not a whole number within long's range`;
    if (texts.has(text)) return `two codes in its value label set share the text "${text}"`;
    texts.add(text);
  }
  const { values, missing } = v.values;
  for (let i = 0; i < values.length; i++) {
    if (missing[i] > 1) return `row ${i} holds an extended missing value (.a to .z)`;
    if (missing[i] === 0 && !labels.has(values[i])) return `row ${i} holds ${values[i]}, which has no label`;
  }
  return { set, ordered: order === "ordered" };
}
