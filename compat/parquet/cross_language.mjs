// Files going between the languages' datakits (plan 0019, "Across
// languages"; TypeScript since plan 0021). TypeScript's half:
//
//     node compat/parquet/cross_language.mjs write DIR   # writes DIR/from_typescript.parquet
//     node compat/parquet/cross_language.mjs check DIR   # reads DIR/from_r.parquet, from_python*.parquet, from_julia.parquet
//
// compat/parquet/cross_language.sh runs every language's halves in turn.
// The values are the literal data cross_language.R, .py and .jl use, so
// each side checks the other's file cell by cell: the value, the missing
// code (`.` or which of `.a` to `.z`), and the labels, formats and value
// labels. Needs js/ and js/datakit/ built. Exits with status 1 if a check
// fails.

import { createRequire } from "node:module";
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const { MISSING } = require("../../js/datakit/dist/index.js");
const { readParquet, saveParquet } = require("../../js/datakit/dist/node.js");

const [mode, dir] = process.argv.slice(2);
if (!["write", "check"].includes(mode) || !dir) throw new Error("usage: node compat/parquet/cross_language.mjs write|check DIR");
mkdirSync(dir, { recursive: true });
const NY = "America/New_York";
const L = (x) => MISSING[x];
const day = (iso) => (iso === null ? null : Date.parse(`${iso}T00:00:00Z`) / 86_400_000);

if (mode === "write") {
  const us = (seconds) => seconds.map((s) => (s === null ? null : Math.round(s * 1_000_000)));
  const at = (values, letters) => values.map((v, i) => (letters[i] ? L(letters[i]) : v));
  saveParquet(
    {
      label: "From TypeScript",
      notes: ["A note from TypeScript."],
      valueLabels: {
        scorelab: new Map([[1.5, "Low"], [L(".a"), "Refused"], [L(".z"), "Other"]]),
        yn: new Map([[0, "No"], [1, "Yes"], [L(".d"), "Don't know"]]),
        dupl: new Map([[1, "Yes"], [2, "No"], [3, "Yes"]]),
        wl: new Map([[3, "three"]]),
      },
      variables: [
        { name: "id", type: "long", values: [1, 2, 3, 4, 5, 6] },
        { name: "score", type: "double", label: "A score", format: "%9.2f", valueLabels: "scorelab", values: [1.5, null, L(".a"), -2.25, L(".z"), 2 ** 1000] },
        { name: "small", type: "byte", valueLabels: "yn", values: [1, 0, L(".d"), 100, -127, null] },
        { name: "long", type: "long", label: "A long", values: [2147483620, -2147483647, L(".b"), 0, null, 7] },
        { name: "fl", type: "float", values: [0.5, L(".c"), 3.25, null, -1, 2] },
        { name: "count", type: "long", label: "A count", values: [3, null, 0, -5, 2147483647, 1] },
        { name: "word", type: "string", values: ["a", null, "", "été", "x y", "z"] },
        { name: "region", type: "categorical", levels: ["S", "N", "E", "W"], values: [1, 0, null, 1, 2, 0] },
        { name: "day", type: "date", format: "%tdCCYY-NN-DD", values: ["2024-03-01", null, "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01"].map(day) },
        { name: "when", type: "timestamp", unit: "us", timeZone: NY, values: us([0, 1709285400.25, null, -1, 86400, 1e9]) },
        // A date and a timestamp holding letters: written as DOUBLE days
        // and seconds since 1970, with "logical" in the profile.
        { name: "seen", type: "date", values: at(["2024-03-01", null, "2024-03-02", null, "1960-01-01", null].map(day), [null, ".d", null, null, null, ".z"]) },
        { name: "stamp", type: "timestamp", unit: "us", timeZone: "UTC", values: at(us([0.5, null, 1e9, null, -86400.25, 1.000001]), [null, ".k", null, null, null, null]) },
        { name: "dup", type: "byte", valueLabels: "dupl", values: [1, 2, 3, 1, 5, null] },
        { name: "w", type: "double", valueLabels: "wl", values: [0.5, 2, 100000, null, 1e-4, 3] },
        // A categorical holding letters (plan 0022): DOUBLE level numbers,
        // with a set the writer makes from the levels.
        { name: "grade", type: "categorical", categorical: { levels: ["low", "mid", "high"], ordered: true }, values: [0, L(".a"), 2, null, L(".z"), 1] },
      ],
    },
    join(dir, "from_typescript.parquet"),
  );
  console.log("TypeScript wrote", join(dir, "from_typescript.parquet"));
  process.exit(0);
}

const failures = [];
let checked = 0;
const check = (ok, what) => {
  checked++;
  if (!ok) failures.push(what);
};
const NAMES = [".", ...Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`)];

/** Each row's missing code and value: `.`, `.a`..., or the number, as text to 17 digits. */
function cells(ds, name) {
  const c = ds.variables.find((v) => v.name === name)?.values;
  if (!c) return [`no ${name}`];
  if (c.kind === "string") return c.values.map((v, i) => (c.missing?.[i] ? "." : v));
  if (c.kind === "dictionary") return Array.from(c.codes, (k, i) => (c.missing?.[i] ? NAMES[c.missing[i] - 1] : c.values[k]));
  return Array.from(c.values, (v, i) => (c.missing[i] ? NAMES[c.missing[i] - 1] : typeof v === "bigint" ? String(v) : String(Number(v.toPrecision(17)))));
}
const num = (...xs) => xs.map((x) => (typeof x === "number" ? String(Number(x.toPrecision(17))) : x));
const same = (ds, name, want, who) => {
  const got = cells(ds, name);
  check(got.length === want.length, `${who} ${name}: length ${got.length}`);
  want.forEach((w, i) => check(got[i] === w, `${who} ${name} row ${i + 1}: ${got[i]}, not ${w}`));
};
const variable = (ds, name) => ds.variables.find((v) => v.name === name) ?? {};
const labels = (ds, name) => {
  const set = ds.valueLabels[variable(ds, name).valueLabels];
  // In code order (Julia's sets come in its Dict's order), numbers first.
  const order = ([a], [b]) => (typeof a === typeof b ? (typeof a === "string" ? NAMES.indexOf(a) - NAMES.indexOf(b) : a - b) : typeof a === "string" ? 1 : -1);
  return set ? [...set].map(([k, t]) => [typeof k === "object" ? k.missing : k, t]).sort(order) : [];
};
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** What every language's file holds in common. */
function common(ds, who) {
  same(ds, "id", ["1", "2", "3", "4", "5", "6"], who);
  same(ds, "score", num(1.5, ".", ".a", -2.25, ".z", 2 ** 1000), who);
  const s = variable(ds, "score");
  check(s.label === "A score" && s.format === "%9.2f" && s.valueLabels === "scorelab", `${who} score: label, format, set`);
  check(eq(labels(ds, "score"), [[1.5, "Low"], [".a", "Refused"], [".z", "Other"]]), `${who} score labels ${JSON.stringify(labels(ds, "score"))}`);
  same(ds, "small", ["1", "0", ".d", "100", "-127", "."], who);
  check(variable(ds, "small").type === "byte", `${who} small: byte`);
  check(eq(labels(ds, "small"), [[0, "No"], [1, "Yes"], [".d", "Don't know"]]), `${who} small labels`);
  same(ds, "long", num(2147483620, -2147483647, ".b", 0, ".", 7), who);
  check(variable(ds, "long").type === "long" && variable(ds, "long").label === "A long", `${who} long: type, label`);
  same(ds, "fl", num(0.5, ".c", 3.25, ".", -1, 2), who);
  check(variable(ds, "fl").type === "float", `${who} fl: float`);
  same(ds, "count", ["3", ".", "0", "-5", "2147483647", "1"], who);
  check(variable(ds, "count").label === "A count", `${who} count: label`);
  same(ds, "word", ["a", ".", "", "été", "x y", "z"], who);
  same(ds, "region", ["N", "S", ".", "N", "E", "S"], who);
  check(eq(variable(ds, "region").categorical, { levels: ["S", "N", "E", "W"], ordered: false }), `${who} region: levels`);
  same(ds, "day", ["2024-03-01", ".", "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01"].map((d) => (d === "." ? d : String(day(d)))), who);
  check(variable(ds, "day").format === "%tdCCYY-NN-DD", `${who} day: format`);
  check(variable(ds, "when").timeZone === NY, `${who} when: zone`);
}

/** A timestamp column's instants, in microseconds, whatever its unit. */
function micros(ds, name) {
  const v = variable(ds, name);
  const f = { s: 1e6, ms: 1e3, us: 1, ns: 1e-3 }[v.unit];
  return cells(ds, name).map((c) => (c.startsWith(".") ? c : String(Math.round(Number(c) * f))));
}

const r = readParquet(join(dir, "from_r.parquet"));
check(r.label === "From R" && eq(r.notes, ["First note.", "Second note."]), "R: data label, notes");
common(r, "R");
check(eq(micros(r, "when"), num(0, 1709285400250000, ".", -1000000, 86400000000, 1e15)), `R when: ${micros(r, "when")}`);
// R's Dates with a fraction of a day, and seconds no whole number of
// microseconds gives back, are DOUBLE counts; TypeScript reads them as
// they are.
same(r, "dayfrac", num(19000.5, 0, ".", -1.25, 1, 2), "R");
same(r, "dup", ["1", "2", "3", "1", "5", "."], "R");

for (const f of ["from_python.parquet", "from_python_columns.parquet"]) {
  const p = readParquet(join(dir, f));
  check(p.label === "From Python" && eq(p.notes, ["A note from Python."]), `${f}: data label, notes`);
  common(p, f);
  check(eq(micros(p, "when"), num(0, 1709285400250000, ".", -1000000, 86400000000, 1e15)), `${f} when`);
  same(p, "seen", num(19783, ".d", 19784, ".", -3653, ".z"), f);
  check(variable(p, "seen").type === "date", `${f} seen: date`);
  check(eq(micros(p, "stamp"), num(500000, ".k", 1e15, ".", -86400250000, 1000001)), `${f} stamp: ${micros(p, "stamp")}`);
  same(p, "dup", ["1", "2", "3", "1", "5", "."], f);
  check(eq(labels(p, "dup"), [[1, "Yes"], [2, "No"], [3, "Yes"]]), `${f} dup labels`);
  // A categorical holding letters (plan 0022).
  same(p, "grade", ["low", ".a", "high", ".", ".z", "mid"], f);
  const g = variable(p, "grade");
  check(g.type === "categorical" && eq(g.categorical, { levels: ["low", "mid", "high"], ordered: true }), `${f} grade: levels`);
  check(g.valueLabels === "grade" && eq(labels(p, "grade"), [[1, "low"], [2, "mid"], [3, "high"]]), `${f} grade: set`);
}

const jl = join(dir, "from_julia.parquet");
if (existsSync(jl)) {
  const j = readParquet(jl);
  check(j.label === "From Julia" && eq(j.notes, ["A note from Julia."]), "Julia: data label, notes");
  common(j, "Julia");
  check(eq(micros(j, "when"), num(0, 1709285400250000, ".", -1000000, 86400000000, 1e15)), "Julia when");
  // Julia's date with letters is Stata's days since 1960, %td.
  same(j, "seen", num(23436, ".d", 23437, ".", 0, ".z"), "Julia");
  check(variable(j, "seen").format === "%td", "Julia seen: format");
} else {
  console.log("no from_julia.parquet in", dir, "(run Julia's write first); Julia's file not checked");
}

console.log(`TypeScript checked ${checked} values and labels in R's, Python's and Julia's files`);
if (failures.length) {
  console.log("FAILED:");
  for (const f of failures) console.log("  ", f);
  process.exit(1);
}
