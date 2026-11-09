// `saveDta`'s conversion: a `Dataset`, which may hold Parquet's types, into
// what dta-parser's `writeDta` takes (plan 0021, "saveDta"). The rules
// follow Python datakit's `save_dta`.

import type { Characteristic, Missing, ValueLabels, WriteDataset, WriteVariable } from "@jbearak/dta-parser";
import { isMissing } from "@jbearak/dta-parser/format";
import { dtaError } from "./_shared/errors";
import { codesOf, missingCode, withCodes } from "./_shared/tagged";
import { CATEGORICAL_MARK, FACTOR_MARK, warn } from "./dataset";
import type { Dataset, DatasetVariable } from "./types";

/** Options for `saveDta`. */
export interface SaveDtaOptions {
  /**
   * `"error"` (the default): a date with a fraction of a day, or a
   * timestamp with a fraction of a millisecond, is an error naming the
   * variable and row. `"truncate"`: such a value is truncated toward
   * minus infinity.
   */
  timestamps?: "error" | "truncate";
  /**
   * Takes the warnings, as messages, instead of `process.emitWarning`:
   * a value label set no saved variable uses, left out because a `.dta`
   * file cannot hold one of its codes.
   */
  onWarning?: (messages: string[]) => void;
}

const RANGES = [
  ["byte", -127, 100],
  ["int", -32767, 32740],
  ["long", -2147483647, 2147483620],
] as const;
const DTA_TYPES = new Set(["byte", "int", "long", "float", "double", "strL"]);
const INTEGER_TYPES = new Set(["bool", "int64", "uint8", "uint16", "uint32", "uint64"]);
const LIMIT = 2n ** 53n;
/** Days and milliseconds from 1960-01-01 to 1970-01-01. */
const DAYS_1960 = 3653n;
const MS_1960 = 315_619_200_000n;
/** Milliseconds per unit, as a fraction: [multiply, divide]. */
const MS_PER: Record<string, [bigint, bigint]> = { s: [1000n, 1n], ms: [1n, 1n], us: [1n, 1000n], ns: [1n, 1_000_000n] };

const invalid = (message: string) => dtaError("DTA_INVALID", message, undefined, TypeError);
const range = (message: string) => dtaError("DTA_INVALID", message, undefined, RangeError);

/** A column's numbers: a value and a missing code (0 a value, 1 `.`, 2 to 27 `.a` to `.z`) per row. */
interface Numbers {
  values: Float64Array;
  missing: Uint8Array;
  /** The exact values, when they came as bigints. */
  big?: (bigint | null)[] | BigInt64Array | BigUint64Array;
}

/** A column's strings, with a null flag per row. */
interface Texts {
  values: (string | Uint8Array)[];
  nulls: boolean[];
}

const NAMES = [".", ...Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`)];
const isText = (x: unknown): x is string | Uint8Array => typeof x === "string" || x instanceof Uint8Array;

function numbersOf(v: DatasetVariable): Numbers | undefined {
  const x = v.values as unknown;
  if (x instanceof Float64Array) return { values: x, missing: codesOf(x) };
  if (x instanceof BigInt64Array) {
    const missing = v.missing ?? new Uint8Array(x.length);
    return { values: Float64Array.from(x, Number), missing, big: x };
  }
  if (Array.isArray(x)) {
    if (x.some(isText)) return undefined;
    const n = x.length;
    const values = new Float64Array(n);
    const missing = new Uint8Array(n);
    let big: (bigint | null)[] | undefined;
    for (let i = 0; i < n; i++) {
      const e = x[i];
      if (e === null || e === undefined) missing[i] = 1;
      else if (isMissing(e)) {
        missing[i] = NAMES.indexOf((e as Missing).missing) + 1;
        values[i] = NaN;
      } else if (typeof e === "bigint") {
        big ??= new Array(n).fill(null);
        big[i] = e;
        values[i] = Number(e);
      } else {
        values[i] = e as number;
        if (values[i] !== values[i]) missing[i] = missingCode(values[i]);
      }
      if (big && missing[i]) big[i] = null;
    }
    if (big) for (let i = 0; i < n; i++) if (big[i] === null && !missing[i]) big[i] = BigInt(values[i]);
    return { values, missing, big };
  }
  const c = x as { kind: string };
  if (c.kind === "number") {
    const col = x as { values: Float64Array };
    return { values: col.values, missing: codesOf(col.values) };
  }
  if (c.kind === "bigint") {
    const col = x as { values: BigInt64Array | BigUint64Array; missing: Uint8Array };
    return { values: Float64Array.from(col.values as ArrayLike<bigint>, Number), missing: col.missing, big: col.values };
  }
  return undefined;
}

function textsOf(v: DatasetVariable): Texts | undefined {
  const x = v.values as unknown;
  if (Array.isArray(x)) {
    if (!x.every((e) => e === null || isText(e))) return undefined;
    return { values: x.map((e) => e ?? ""), nulls: x.map((e) => e === null) };
  }
  const c = x as { kind?: string };
  if (c.kind === "string") {
    const col = x as { values: (string | Uint8Array)[]; missing?: Uint8Array };
    return { values: col.values, nulls: Array.from(col.values, (_, i) => col.missing?.[i] === 1) };
  }
  if (c.kind === "dictionary") {
    const col = x as { codes: Uint32Array; values: string[]; missing?: Uint8Array };
    return { values: Array.from(col.codes, (k, i) => (col.missing?.[i] === 1 ? "" : col.values[k])), nulls: Array.from(col.codes, (_, i) => col.missing?.[i] === 1) };
  }
  return undefined;
}

/** `x` as an exact fraction `num / den`, `den` a power of two. */
function exact(x: number): [bigint, bigint] {
  if (Number.isInteger(x)) return [BigInt(x), 1n];
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  const bits = view.getBigUint64(0);
  const negative = bits >> 63n === 1n;
  const exponent = Number((bits >> 52n) & 0x7ffn);
  let mantissa = bits & ((1n << 52n) - 1n);
  let e: number;
  if (exponent === 0) e = -1074;
  else {
    mantissa |= 1n << 52n;
    e = exponent - 1075;
  }
  let num = negative ? -mantissa : mantissa;
  let den = 1n;
  if (e >= 0) num <<= BigInt(e);
  else den <<= BigInt(-e);
  return [num, den];
}

/** Floor of `a / b` for b > 0. */
function floorDiv(a: bigint, b: bigint): bigint {
  const q = a / b;
  return a % b !== 0n && a < 0n ? q - 1n : q;
}

/** A value of a date or timestamp in exact arithmetic: the result, or a message. */
function convertTime(
  name: string,
  row: number,
  value: number,
  big: bigint | undefined,
  [mul, div]: [bigint, bigint],
  offset: bigint,
  truncate: boolean,
  what: string,
): bigint {
  if (big === undefined && !Number.isFinite(value)) throw range(`${name}: row ${row} holds ${value}, which a ${what} cannot hold`);
  const [num, den] = big === undefined ? exact(value) : [big, 1n];
  const n = num * mul;
  const d = den * div;
  if (n % d !== 0n && !truncate) {
    throw range(`${name}: row ${row} holds ${value}, a fraction of a ${what === "date" ? "day" : "millisecond"}; pass timestamps: "truncate" to drop it`);
  }
  return floorDiv(n, d) + offset;
}

/** Whether two value label sets map the same codes to the same texts, and nothing else. */
function sameLabels(a: ValueLabels, b: ValueLabels): boolean {
  if (a.size !== b.size) return false;
  for (const [k, t] of a) if (b.get(k) !== t) return false;
  return true;
}

/**
 * The `WriteDataset` dta-parser's `writeDta` writes for `data`: each
 * variable converted as docs/typescript.md, "Save a dataset", says.
 */
export function toDta(data: Dataset, options: SaveDtaOptions = {}): WriteDataset {
  const truncate = options.timestamps === "truncate";
  if (options.timestamps !== undefined && options.timestamps !== "error" && options.timestamps !== "truncate") {
    throw invalid(`timestamps must be "error" or "truncate", not ${JSON.stringify(options.timestamps)}`);
  }
  const sets: Record<string, ValueLabels> = { ...(data.valueLabels ?? {}) };
  // Both markers leave every column (one that was a categorical may be
  // numbers now); each categorical gets its own below (plan 0023).
  const characteristics: Characteristic[] = (data.characteristics ?? []).filter((c) => c.name !== FACTOR_MARK && c.name !== CATEGORICAL_MARK);
  const variables: WriteVariable[] = data.variables.map((v) => convert(v, sets, characteristics, truncate));
  // A .dta value label's code is a whole number within long's range (or a
  // missing value). A set a variable uses with another code is an error,
  // as in R and Python; one no variable uses is left out, with a warning.
  const left: string[] = [];
  for (const [name, labels] of Object.entries(sets)) {
    const bad = [...labels.keys()].find((k) => !isMissing(k) && !(Number.isInteger(k) && (k as number) >= RANGES[2][1] && (k as number) <= RANGES[2][2]));
    if (bad === undefined) continue;
    const user = variables.find((v) => v.valueLabels === name);
    if (user) throw range(`${user.name}: its value label set ${name} labels ${bad}, and a .dta label's code is a whole number within long's range`);
    delete sets[name];
    left.push(`${name} (it labels ${bad})`);
  }
  if (left.length) {
    warn(["Value label sets no variable uses were left out, since a .dta file cannot hold one of their codes:", ...left], "DATAKIT_LABELS", options.onWarning);
  }
  const out: WriteDataset = { variables, valueLabels: sets, characteristics };
  if (data.label !== undefined) out.label = data.label;
  if (data.notes !== undefined) out.notes = data.notes;
  if (data.sortedBy !== undefined) out.sortedBy = data.sortedBy;
  if (data.timestamp !== undefined) out.timestamp = data.timestamp;
  return out;
}

function convert(v: DatasetVariable, sets: Record<string, ValueLabels>, characteristics: Characteristic[], truncate: boolean): WriteVariable {
  const t = v.type;
  const base = { name: v.name, label: v.label, valueLabels: v.valueLabels || undefined };
  if (t === "categorical" || (t === undefined && v.levels !== undefined)) return categorical(v, sets, characteristics);
  if (t === "date" || t === "timestamp") {
    const nums = numbersOf(v);
    if (!nums) throw invalid(`${v.name}: a ${t} holds numbers, not text`);
    if (t === "timestamp" && v.timeZone) {
      throw invalid(`${v.name}: a .dta file has no time zones; convert the instants to clock times in a zone first (drop timeZone)`);
    }
    const scale: [bigint, bigint] = t === "date" ? [1n, 1n] : MS_PER[v.unit ?? "us"];
    if (!scale) throw invalid(`${v.name}: unknown unit ${JSON.stringify(v.unit)}; use "s", "ms", "us" or "ns"`);
    const offset = t === "date" ? DAYS_1960 : MS_1960;
    const values = new Float64Array(nums.values.length);
    for (let i = 0; i < values.length; i++) {
      if (nums.missing[i]) {
        values[i] = NaN;
        continue;
      }
      const big = nums.big ? (nums.big[i] as bigint | null) ?? undefined : undefined;
      if (big === undefined && Number.isNaN(nums.values[i])) throw range(`${v.name}: row ${i} holds NaN, which is not a missing value; a ${t} cannot hold it`);
      const r = convertTime(v.name, i, nums.values[i], big, scale, offset, truncate, t);
      // Checked exactly, before it becomes a double.
      if (t === "date" ? r < BigInt(RANGES[2][1]) || r > BigInt(RANGES[2][2]) : r > LIMIT || r < -LIMIT) {
        throw range(`${v.name}: row ${i} is past what a ${t === "date" ? "long %td" : "double %tc"} holds`);
      }
      values[i] = Number(r);
    }
    // A %td (or %tc) format the variable has, such as %tdCCYY-NN-DD, is kept.
    const kind = t === "date" ? "%td" : "%tc";
    const format = v.format?.startsWith(kind) ? v.format : kind;
    return { ...base, type: t === "date" ? "long" : "double", format, values: withCodes(values, nums.missing) };
  }
  if (t === "time") throw invalid(`${v.name}: a .dta file has no time of day type; convert it to numbers (seconds since midnight, say) first`);
  if (t === "decimal") {
    const nums = numbersOf(v);
    if (!nums) {
      throw invalid(`${v.name}: this decimal was read as text (more than 15 digits); parse it into numbers if doubles are close enough, or set type: "string" to keep the digits as text`);
    }
    return { ...base, type: "double", format: v.format || undefined, values: withCodes(nums.values, nums.missing) };
  }
  if (t === "string" || t === "binary" || t === "strL" || (t !== undefined && /^str[0-9]+$/.test(t))) {
    const texts = textsOf(v);
    if (!texts) throw invalid(`${v.name}: a ${t} column holds text, not numbers`);
    nullCheck(v.name, texts);
    const binary = texts.values.some((x) => x instanceof Uint8Array);
    if (binary && t !== "strL" && t !== "binary") throw invalid(`${v.name}: binary values need type "strL" or "binary"`);
    return { ...base, type: t === "binary" || t === "strL" ? "strL" : t === "string" ? undefined : t, format: v.format || undefined, values: texts.values };
  }
  if (t === undefined) {
    const texts = textsOf(v);
    if (texts && !numbersOf(v)) {
      nullCheck(v.name, texts);
      return { ...base, format: v.format || undefined, values: texts.values };
    }
  }
  if (t === undefined || INTEGER_TYPES.has(t) || DTA_TYPES.has(t)) {
    const nums = numbersOf(v);
    if (!nums) throw invalid(`${v.name}: a ${t ?? "numeric"} column holds numbers`);
    if (t !== undefined && DTA_TYPES.has(t)) {
      if (nums.big) for (let i = 0; i < nums.values.length; i++) bigCheck(v.name, i, nums);
      // byte, int and long stop short of their integer type's range (the
      // codes past it are `.` to `.z`), so a column read from Parquet as
      // long may hold 2,147,483,647: it takes the next type that holds it,
      // as Python's save_dta does.
      const r = RANGES.findIndex(([name]) => name === t);
      const fits = r < 0 || nums.values.every((x, i) => nums.missing[i] !== 0 || (x >= RANGES[r][1] && x <= RANGES[r][2]));
      if (fits) return { ...base, type: t, format: v.format || undefined, values: withCodes(nums.values, nums.missing) };
    }
    const integer = t !== undefined && !DTA_TYPES.has(t);
    let whole = true;
    let lo = Infinity;
    let hi = -Infinity;
    for (let i = 0; i < nums.values.length; i++) {
      if (nums.missing[i]) continue;
      if (nums.big) bigCheck(v.name, i, nums);
      const x = nums.values[i];
      if (integer && Math.abs(x) > Number(LIMIT)) throw range(`${v.name}: row ${i} holds ${x}, past ±2^53, which a .dta file cannot hold exactly`);
      if (!Number.isInteger(x)) whole = false;
      if (x < lo) lo = x;
      if (x > hi) hi = x;
    }
    let type = "double";
    if (whole) for (const [name, min, max] of RANGES) if (lo >= min && hi <= max) {
      type = name;
      break;
    }
    if (lo === Infinity) type = integer ? "byte" : "double";
    // A Parquet integer type's display format would be its own; .dta's
    // default suits the storage type chosen.
    const format = integer || (t !== undefined && RANGES.some(([name]) => name === t)) ? undefined : v.format || undefined;
    return { ...base, type: type as WriteVariable["type"], format, values: withCodes(nums.values, nums.missing) };
  }
  throw invalid(`${v.name}: a .dta file cannot hold type ${JSON.stringify(t)}`);
}

function bigCheck(name: string, row: number, nums: Numbers): void {
  const b = nums.big![row];
  if (b === null || b === undefined || nums.missing[row]) return;
  if ((b as bigint) > LIMIT || (b as bigint) < -LIMIT) throw range(`${name}: row ${row} holds ${b}, past ±2^53, which a .dta file cannot hold exactly`);
}

function nullCheck(name: string, texts: Texts): void {
  const row = texts.nulls.indexOf(true);
  if (row >= 0) throw invalid(`${name}: row ${row} is a missing string, which a .dta file cannot hold; fill it (with "", say) first`);
}

function categorical(v: DatasetVariable, sets: Record<string, ValueLabels>, characteristics: Characteristic[]): WriteVariable {
  const c = v.values as { kind?: string };
  let levels: readonly string[];
  let index: Int32Array; // per row: level index, -1 for `.`, -2 to -27 for `.a` to `.z`
  if (c.kind === "dictionary") {
    const d = v.values as { codes: Uint32Array; values: string[]; missing?: Uint8Array };
    levels = d.values;
    index = Int32Array.from(d.codes, (k, i) => {
      const m = d.missing?.[i] ?? 0;
      if (m > 27) throw range(`${v.name}: row ${i} has missing code ${m}; codes run from 0 to 27`);
      return m ? -m : k;
    });
  } else {
    const lv = v.levels ?? v.categorical?.levels;
    if (!lv) throw invalid(`${v.name}: a categorical needs its levels (levels, or a DictionaryColumn)`);
    levels = lv;
    const nums = numbersOf(v);
    if (!nums) throw invalid(`${v.name}: a categorical's values are level codes from 0, or a DictionaryColumn`);
    index = new Int32Array(nums.values.length);
    for (let i = 0; i < index.length; i++) {
      const x = nums.values[i];
      if (nums.missing[i] > 27) throw range(`${v.name}: row ${i} has missing code ${nums.missing[i]}; codes run from 0 to 27`);
      if (nums.missing[i]) index[i] = -nums.missing[i];
      else if (!Number.isInteger(x) || x < 0 || x >= levels.length) throw range(`${v.name}: row ${i} holds ${x}, not a level code from 0 to ${levels.length - 1}`);
      else index[i] = x;
    }
  }
  const given = v.categorical?.codes;
  if (given !== undefined) {
    if (given.length !== levels.length) throw invalid(`${v.name}: categorical.codes has ${given.length} codes for ${levels.length} levels`);
    for (const k of given) if (!Number.isInteger(k) || k < RANGES[2][1] || k > RANGES[2][2]) throw range(`${v.name}: categorical.codes holds ${k}, not a whole number within long's range`);
    // Readers order the levels by code, so the codes must increase with them.
    const seen = new Set<number>();
    for (const k of given) {
      if (seen.has(k)) throw invalid(`${v.name}: categorical.codes gives the code ${k} twice`);
      seen.add(k);
    }
    for (let i = 1; i < given.length; i++) {
      if (given[i] < given[i - 1]) throw invalid(`${v.name}: categorical.codes must increase with the levels, but ${given[i]} follows ${given[i - 1]}`);
    }
  }
  const codes = given ?? levels.map((_, i) => i + 1);
  const labels: ValueLabels = new Map(levels.map((text, i) => [codes[i], text]));
  if (new Set(levels).size !== levels.length) throw invalid(`${v.name}: two levels share a text`);
  // Labels on .a to .z in the set the variable names (a categorical read
  // from Parquet holding them has one, plan 0022) are kept.
  const named = v.valueLabels ? sets[v.valueLabels] : undefined;
  if (named) for (const [k, text] of named) if (isMissing(k) && k.missing !== ".") labels.set(k, text);
  // The set's name: the one it came from, else the one it names, else the
  // column's; reused when a set by that name says the same, else name_2,
  // name_3, ...
  const base = v.categorical?.labelSet ?? (v.valueLabels || v.name);
  let name = base;
  for (let k = 2; sets[name] !== undefined && !sameLabels(sets[name], labels); k++) name = `${base}_${k}`;
  sets[name] = sets[name] ?? labels;
  const ordered = v.categorical?.ordered ?? v.ordered ?? false;
  const values = new Float64Array(index.length);
  const missing = new Uint8Array(index.length);
  for (let i = 0; i < index.length; i++) {
    if (index[i] < 0) {
      values[i] = NaN;
      missing[i] = -index[i];
    } else values[i] = codes[index[i]];
  }
  // The marker says the variable reads back as a categorical, with its
  // .a to .z and their labels (plan 0023).
  characteristics.push({ variable: v.name, name: CATEGORICAL_MARK, value: `${ordered ? "ordered" : "unordered"} ${name}` });
  return { name: v.name, label: v.label, type: "long", valueLabels: name, values: withCodes(values, missing) };
}
