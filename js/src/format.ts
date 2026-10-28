// Display formats: render a cell as its variable's %-format says.

import type { Cell, ValueLabels } from "./index";

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const DAY_MS = 86_400_000;
/** 1960-01-01, Stata's day 0, as a Unix time in milliseconds. */
const EPOCH = Date.UTC(1960, 0, 1);

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
 * An unrecognised format falls back to the plain number.
 */
export function formatValue(cell: Cell, format: string, labels?: ValueLabels): string {
  const key = typeof cell === "object" && cell !== null && "missing" in cell ? cell : typeof cell === "number" ? cell : undefined;
  if (labels && key !== undefined && labels.has(key)) return labels.get(key)!;
  if (typeof cell === "string") return cell;
  if (cell instanceof Uint8Array) return `<${cell.length} bytes>`;
  if (typeof cell !== "number") return cell.missing;
  if (!Number.isFinite(cell)) return ".";

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
  if (STRING.test(format)) return String(cell);
  return String(cell);
}

/** `%w.dg`: `d` significant digits, or, with `d` 0, as many as fit in `w`. */
function general(v: number, width: number, digits: number): string {
  if (digits === 0 && Number.isInteger(v) && String(v).length <= width) return String(v);
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

function formatTime(v: number, unit: string, mask: string): string {
  const year = (per: number) => 1960 + Math.floor(Math.floor(v) / per);
  switch (unit) {
    case "d":
      return render(fromDate(new Date(EPOCH + Math.round(v) * DAY_MS)), mask || "DDmonCCYY");
    case "c":
    case "C":
      // Whole milliseconds, as pandas reads them.
      return render(fromDate(new Date(EPOCH + Math.floor(v))), mask || "DDmonCCYY_HH:MM:SS");
    case "w":
      return render({ year: year(52), week: mod(v, 52) + 1 }, mask || "CCYY!www");
    case "m":
      return render({ year: year(12), month: mod(v, 12) }, mask || "CCYY!mnn");
    case "q":
      return render({ year: year(4), quarter: mod(v, 4) + 1 }, mask || "CCYY!qq");
    case "h":
      return render({ year: year(2), half: mod(v, 2) + 1 }, mask || "CCYY!hh");
    default:
      return render({ year: Math.round(v) }, mask || "CCYY");
  }
}

function fromDate(t: Date): When {
  return {
    year: t.getUTCFullYear(),
    month: t.getUTCMonth(),
    day: t.getUTCDate(),
    hour: t.getUTCHours(),
    minute: t.getUTCMinutes(),
    second: t.getUTCSeconds(),
    ms: t.getUTCMilliseconds(),
  };
}

function mod(a: number, b: number): number {
  return ((Math.floor(a) % b) + b) % b;
}

const MASK = /^(\.sss|\.ss|\.s|Month|month|Mon|mon|CC|YY|NN|nn|DD|dd|HH|hh|MM|SS|WW|ww|q|h|!.|_)/;

function render(w: When, mask: string): string {
  const opt = (n: number | undefined, f: (n: number) => string) => (n === undefined ? "" : f(n));
  const name = (n: number | undefined, len?: number) => opt(n, (m) => MONTHS[m].slice(0, len));
  const parts: Record<string, string> = {
    CC: pad(Math.floor(w.year / 100)),
    YY: pad(mod(w.year, 100)),
    NN: opt(w.month, (m) => pad(m + 1)),
    nn: opt(w.month, (m) => String(m + 1)),
    DD: opt(w.day, pad),
    dd: opt(w.day, String),
    Mon: name(w.month, 3),
    mon: name(w.month, 3).toLowerCase(),
    Month: name(w.month),
    month: name(w.month).toLowerCase(),
    HH: opt(w.hour, pad),
    hh: opt(w.hour, String),
    MM: opt(w.minute, pad),
    SS: opt(w.second, pad),
    ".s": opt(w.ms, (ms) => `.${Math.floor(ms / 100)}`),
    ".ss": opt(w.ms, (ms) => `.${pad(Math.floor(ms / 10))}`),
    ".sss": opt(w.ms, (ms) => `.${pad(ms, 3)}`),
    WW: opt(w.week, pad),
    ww: opt(w.week, String),
    q: opt(w.quarter, String),
    h: opt(w.half, String),
    _: " ",
  };
  let out = "";
  for (let rest = mask; rest.length > 0; ) {
    const m = MASK.exec(rest);
    if (!m) {
      out += rest[0];
      rest = rest.slice(1);
    } else {
      out += m[1].startsWith("!") ? m[1][1] : parts[m[1]];
      rest = rest.slice(m[1].length);
    }
  }
  return out;
}
