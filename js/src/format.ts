// Display formats: render a cell as its variable's %-format says.

import type { Cell, ValueLabels } from "./values";

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const DAY_MS = 86_400_000;

const NUMBER = /^%(-|~)?(0)?(\d+)?(?:\.(\d+))?([fge])(c)?$/;
const STRING = /^%(-|~)?(\d+)?s$/;
const TIME = /^%(-)?t?([cCdwmqhy])(.*)$/;

/**
 * Render a cell as its display format says: `%9.2f`, `%12.0gc`,
 * `%10.3e`, `%td`, `%tcCCYY-NN-DD_HH:MM:SS`, `%tm` and so on.
 *
 * - With `labels`, a labelled value shows its label.
 * - A missing value shows as `.`, `.a`, ... (or its label).
 * - The width only sets how many digits `%g` may use. Alignment is left
 *   to the caller.
 * - `%g` approximates Stata's choice of digits. `%tC` is treated as
 *   `%tc` (leap seconds are not counted).
 * - Date masks take `CC`, `YY`, `NN`, `nn`, `DD`, `dd`, `Mon`, `mon`,
 *   `Month`, `month`, `HH`, `hh`, `MM`, `SS`, `.s`, `.ss`, `.sss`, and
 *   for weekly, quarterly and half-yearly dates `WW`, `ww`, `q` and `h`.
 *   `_` stands for a space, `!x` for a literal `x`, and any other
 *   character is copied. Pieces a unit lacks (the day of a %tm) are left
 *   out. The older `%d` formats show as `%td` does, whatever their mask.
 *
 * An unrecognised format, a date outside JavaScript's date range, or a
 * format asking for more digits than JavaScript can show falls back to
 * the plain number (as `%9.0g` shows it). `formatValue` never throws.
 */
export function formatValue(cell: Cell, format: string, labels?: ValueLabels): string {
  const key = typeof cell === "object" && cell !== null && "missing" in cell ? cell : typeof cell === "number" ? cell : undefined;
  if (labels && key !== undefined && labels.has(key)) return labels.get(key)!;
  if (typeof cell === "string") return cell;
  if (cell instanceof Uint8Array) return `<${cell.length} bytes>`;
  if (typeof cell !== "number") return cell.missing;
  if (!Number.isFinite(cell)) return ".";
  try {
    return formatNumber(cell, format);
  } catch {
    return general(cell, 9, 0);
  }
}

function formatNumber(cell: number, format: string): string {
  const time = TIME.exec(format);
  if (time && (format.startsWith("%t") || format.startsWith("%-t"))) return formatTime(cell, time[2], time[3]);
  // The older %d formats: their masks are shown as %td's default.
  if (format.startsWith("%d")) return formatTime(cell, "d", "");
  const num = NUMBER.exec(format);
  if (num) {
    const width = num[3] ? Number(num[3]) : 9;
    const digits = num[4] === undefined ? undefined : Number(num[4]);
    const text = num[5] === "f" ? cell.toFixed(digits ?? 0) : num[5] === "e" ? exponential(cell, digits ?? 0) : general(cell, width, digits ?? 0);
    return num[6] ? commas(text) : text;
  }
  return String(cell);
}

/** `%w.dg`: `d` significant digits, or, with `d` 0, as many as fit in `w`. */
function general(v: number, width: number, digits: number): string {
  if (digits === 0) {
    // Fast path: a number JavaScript writes in fewer than `width`
    // characters has no more significant digits than `%g` would keep.
    const plain = String(v);
    if (Number.isInteger(v) ? plain.length <= width : plain.length < width && Math.abs(v) >= 1e-4 && !plain.includes("e")) return plain;
  }
  const precision = digits > 0 ? digits : Math.max(1, Math.min(width - (v < 0 ? 3 : 2), 15));
  const exponent = v === 0 ? 0 : Math.floor(Math.log10(Math.abs(v)));
  if (exponent < -4 || exponent >= Math.max(precision, width - 1)) {
    const [mantissa, power] = exponential(v, Math.max(0, precision - 1)).split("e");
    return `${trimZeros(mantissa)}e${power}`;
  }
  const text = v.toPrecision(precision);
  if (!text.includes("e")) return trimZeros(text);
  // toPrecision may round up into an exponent (9999999999.5 to 1.0e+10).
  const [mantissa, power] = text.split("e");
  return `${trimZeros(mantissa)}e${power.replace(/^([+-])(\d)$/, "$10$2")}`;
}

function exponential(v: number, digits: number): string {
  // JavaScript writes e+5; Stata writes e+05.
  return v.toExponential(digits).replace(/e([+-])(\d)$/, "e$10$2");
}

function trimZeros(s: string): string {
  return s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s;
}

function commas(s: string): string {
  const [int, frac] = s.split(".");
  if (/e/.test(s)) return s;
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return frac === undefined ? grouped : `${grouped}.${frac}`;
}

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/** The pieces of a date a mask can show; units without them leave them out. */
interface When {
  year: number;
  month?: number; // 0 to 11
  day?: number;
  hour?: number;
  minute?: number;
  second?: number;
  ms?: number;
  quarter?: number;
  half?: number;
  week?: number;
}

/** JavaScript's date range, in days either side of 1970 (so of 1960, near enough). */
const MAX_DAYS = 100_000_000;

function formatTime(v: number, unit: string, mask: string): string {
  const year = (per: number) => 1960 + Math.floor(Math.floor(v) / per);
  switch (unit) {
    case "d":
      return render(civil(Math.floor(v)), mask || "DDmonCCYY");
    case "c":
    case "C": {
      // Whole milliseconds, as pandas reads them.
      const ms = Math.floor(v);
      const days = Math.floor(ms / DAY_MS);
      const w = civil(days);
      let rest = ms - days * DAY_MS;
      w.hour = Math.floor(rest / 3_600_000);
      rest -= w.hour * 3_600_000;
      w.minute = Math.floor(rest / 60_000);
      rest -= w.minute * 60_000;
      w.second = Math.floor(rest / 1000);
      w.ms = rest - w.second * 1000;
      return render(w, mask || "DDmonCCYY_HH:MM:SS");
    }
    case "w":
      return render({ year: year(52), week: mod(v, 52) + 1 }, mask || "CCYY!www");
    case "m":
      return render({ year: year(12), month: mod(v, 12) }, mask || "CCYY!mnn");
    case "q":
      return render({ year: year(4), quarter: mod(v, 4) + 1 }, mask || "CCYY!qq");
    case "h":
      return render({ year: year(2), half: mod(v, 2) + 1 }, mask || "CCYY!hh");
    default:
      return render({ year: Math.floor(v) }, mask || "CCYY");
  }
}

/**
 * The calendar date `days` after 1 January 1960 (the proleptic
 * Gregorian calendar, as JavaScript's Date uses), by the usual
 * days-to-civil arithmetic on 400-year eras. Throws outside the range a
 * JavaScript Date covers, so such values show as plain numbers.
 */
function civil(days: number): When {
  if (!(Math.abs(days) <= MAX_DAYS)) throw new RangeError("date out of range");
  const z = days - 3653 + 719_468; // days since 0000-03-01
  const era = Math.floor(z / 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36_524) - Math.floor(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const day = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const month = mp < 10 ? mp + 2 : mp - 10;
  return { year: yoe + era * 400 + (month < 2 ? 1 : 0), month, day };
}

function mod(a: number, b: number): number {
  return ((Math.floor(a) % b) + b) % b;
}

const MASK = /^(\.sss|\.ss|\.s|Month|month|Mon|mon|CC|YY|NN|nn|DD|dd|HH|hh|MM|SS|WW|ww|q|h|!.|_)/;

/** A mask split into pieces, once per mask: a piece name, or `=` and literal text. */
const compiled = new Map<string, string[]>();

function pieces(mask: string): string[] {
  let out = compiled.get(mask);
  if (out) return out;
  out = [];
  for (let rest = mask; rest.length > 0; ) {
    const m = MASK.exec(rest);
    const piece = !m ? `=${rest[0]}` : m[1].startsWith("!") ? `=${m[1][1]}` : m[1] === "_" ? "= " : m[1];
    out.push(piece);
    rest = rest.slice(m ? m[1].length : 1);
  }
  if (compiled.size < 1000) compiled.set(mask, out);
  return out;
}

function render(w: When, mask: string): string {
  // A negative year shows its sign once, before the century.
  const y = Math.abs(w.year);
  let out = "";
  for (const p of pieces(mask)) {
    switch (p) {
      case "CC": out += (w.year < 0 ? "-" : "") + pad(Math.floor(y / 100)); break;
      case "YY": out += pad(y % 100); break;
      case "NN": if (w.month !== undefined) out += pad(w.month + 1); break;
      case "nn": if (w.month !== undefined) out += String(w.month + 1); break;
      case "DD": if (w.day !== undefined) out += pad(w.day); break;
      case "dd": if (w.day !== undefined) out += String(w.day); break;
      case "Mon": if (w.month !== undefined) out += MONTHS[w.month].slice(0, 3); break;
      case "mon": if (w.month !== undefined) out += MONTHS[w.month].slice(0, 3).toLowerCase(); break;
      case "Month": if (w.month !== undefined) out += MONTHS[w.month]; break;
      case "month": if (w.month !== undefined) out += MONTHS[w.month].toLowerCase(); break;
      case "HH": if (w.hour !== undefined) out += pad(w.hour); break;
      case "hh": if (w.hour !== undefined) out += String(w.hour); break;
      case "MM": if (w.minute !== undefined) out += pad(w.minute); break;
      case "SS": if (w.second !== undefined) out += pad(w.second); break;
      case ".s": if (w.ms !== undefined) out += `.${Math.floor(w.ms / 100)}`; break;
      case ".ss": if (w.ms !== undefined) out += `.${pad(Math.floor(w.ms / 10))}`; break;
      case ".sss": if (w.ms !== undefined) out += `.${pad(w.ms, 3)}`; break;
      case "WW": if (w.week !== undefined) out += pad(w.week); break;
      case "ww": if (w.week !== undefined) out += String(w.week); break;
      case "q": if (w.quarter !== undefined) out += String(w.quarter); break;
      case "h": if (w.half !== undefined) out += String(w.half); break;
      default: out += p.slice(1);
    }
  }
  return out;
}
