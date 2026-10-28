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
 *   `Month`, `month`, `HH`, `hh`, `MM`, `SS`, `.s`, `.ss` and `.sss`.
 *   `_` stands for a space, `!x` for a literal `x`, and any other
 *   character is copied.
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
  if (time && (format.startsWith("%t") || format.startsWith("%d") || format.startsWith("%-t"))) {
    return formatTime(cell, time[2], time[3]);
  }
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
  return trimZeros(v.toPrecision(precision));
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

function formatTime(v: number, unit: string, mask: string): string {
  switch (unit) {
    case "d":
      return dateTime(new Date(EPOCH + Math.round(v) * DAY_MS), mask || "DDmonCCYY");
    case "c":
    case "C":
      return dateTime(new Date(EPOCH + v), mask || "DDmonCCYY_HH:MM:SS");
    case "w":
      return `${1960 + Math.floor(v / 52)}w${mod(v, 52) + 1}`;
    case "m":
      return `${1960 + Math.floor(v / 12)}m${mod(v, 12) + 1}`;
    case "q":
      return `${1960 + Math.floor(v / 4)}q${mod(v, 4) + 1}`;
    case "h":
      return `${1960 + Math.floor(v / 2)}h${mod(v, 2) + 1}`;
    default:
      return String(Math.round(v));
  }
}

function mod(a: number, b: number): number {
  return ((Math.floor(a) % b) + b) % b;
}

const MASK = /^(\.sss|\.ss|\.s|Month|month|Mon|mon|CC|YY|NN|nn|DD|dd|HH|hh|MM|SS|!.|_)/;

function dateTime(t: Date, mask: string): string {
  const year = t.getUTCFullYear();
  const month = t.getUTCMonth();
  const ms = t.getUTCMilliseconds();
  const parts: Record<string, string> = {
    CC: pad(Math.floor(year / 100)),
    YY: pad(year % 100),
    NN: pad(month + 1),
    nn: String(month + 1),
    DD: pad(t.getUTCDate()),
    dd: String(t.getUTCDate()),
    Mon: MONTHS[month].slice(0, 3),
    mon: MONTHS[month].slice(0, 3).toLowerCase(),
    Month: MONTHS[month],
    month: MONTHS[month].toLowerCase(),
    HH: pad(t.getUTCHours()),
    hh: String(t.getUTCHours()),
    MM: pad(t.getUTCMinutes()),
    SS: pad(t.getUTCSeconds()),
    ".s": `.${Math.floor(ms / 100)}`,
    ".ss": `.${pad(Math.floor(ms / 10))}`,
    ".sss": `.${pad(ms, 3)}`,
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
