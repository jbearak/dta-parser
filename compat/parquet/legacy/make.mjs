// The legacy fixtures' TypeScript half (README.md here): the npm
// package @jbearak/datakit 2.0.0 writes ts_*.parquet from the data below.
//
//     node compat/parquet/legacy/make.mjs
//
// Run from the repository root with js/ and js/datakit/ built. make.sh
// runs it between make.R's two modes. Every value is made here.

import { createRequire } from "node:module";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const { MISSING } = require("../../../js/datakit/dist/index.js");
const { saveParquet } = require("../../../js/datakit/dist/node.js");

const DIR = "compat/parquet/legacy";
const L = (x) => MISSING[x];
const day = (iso) => (iso === null ? null : Date.parse(`${iso}T00:00:00Z`) / 86_400_000);
const us = (seconds) => seconds.map((s) => (s === null ? null : Math.round(s * 1_000_000)));
const at = (values, letters) => values.map((v, i) => (letters[i] ? L(letters[i]) : v));

// Every type the TypeScript writer takes, with labels, formats, .a to .z
// and nulls.
const types = {
  label: "Legacy types from TypeScript",
  notes: ["A note from TypeScript.", "A second note, été."],
  characteristics: [
    { variable: "_dta", name: "origin", value: "make.mjs" },
    { variable: "score", name: "note1", value: "The score's note." },
  ],
  sortedBy: ["id"],
  valueLabels: {
    scorelab: new Map([[1.5, "Low"], [L(".a"), "Refused"], [L(".z"), "Other"]]),
    yn: new Map([[0, "No"], [1, "Yes"], [L(".d"), "Don't know"]]),
    dupl: new Map([[1, "Yes"], [2, "No"], [3, "Yes"]]),
    gradelab: new Map([[1, "low"], [2, "mid"], [3, "high"], [L(".a"), "Refused"]]),
  },
  variables: [
    { name: "id", type: "long", values: [1, 2, 3, 4, 5, 6, 7, 8] },
    { name: "score", type: "double", label: "A score", format: "%9.2f", valueLabels: "scorelab", values: [1.5, null, L(".a"), -2.25, L(".z"), 2 ** 1000, NaN, -0] },
    { name: "small", type: "byte", valueLabels: "yn", values: [1, 0, L(".d"), 100, -127, null, 0, 1] },
    { name: "small_plain", type: "byte", valueLabels: "yn", values: [1, 0, 1, 100, -127, null, 0, 1] },
    { name: "int16", type: "int", values: [-32767, 32740, L(".e"), 0, null, 1, 2, 3] },
    { name: "long", type: "long", label: "A long holding a letter", values: [2147483620, -2147483647, L(".b"), 0, null, 7, 8, 9] },
    { name: "fl", type: "float", values: [0.5, L(".c"), 3.25, null, -1, 2, 2 ** 100, -0.125] },
    { name: "fl_plain", type: "float", values: [0.5, 1.5, 3.25, null, -1, 2, 2 ** 100, -0.125] },
    { name: "dup", type: "byte", valueLabels: "dupl", values: [1, 2, 3, 1, 5, null, 2, 3] },
    { name: "flag", type: "bool", values: [1, 0, null, 1, 1, 0, null, 0] },
    { name: "big", type: "int64", values: [9007199254740992n, -9007199254740992n, null, 0n, 1n, 2n, 3n, 4n] },
    { name: "u8", type: "uint8", values: [0, 255, null, 1, 2, 3, 4, 5] },
    { name: "u16", type: "uint16", values: [0, 65535, null, 1, 2, 3, 4, 5] },
    { name: "u32", type: "uint32", values: [0, 4294967295, null, 1, 2, 3, 4, 5] },
    { name: "word", type: "string", values: ["a", null, "", "été", "x y", "z", "中文", "long ".repeat(40)] },
    { name: "blob", type: "binary", values: [Uint8Array.of(0, 1, 255), null, new Uint8Array(0), Uint8Array.of(7), Uint8Array.of(1, 2, 3, 4, 5, 6, 7, 8, 9, 10), null, Uint8Array.of(0), Uint8Array.of(2)] },
    { name: "region", type: "categorical", levels: ["S", "N", "E", "W"], values: [1, 0, null, 1, 2, 0, 1, 1] },
    { name: "grade_plain", type: "categorical", categorical: { levels: ["low", "mid", "high"], ordered: true }, values: [0, 2, 1, null, 0, 0, 2, 1] },
    // A categorical holding letters (plan 0022): DOUBLE level numbers, with
    // a value label set for the letters' labels.
    { name: "grade", type: "categorical", categorical: { levels: ["low", "mid", "high"], ordered: true }, valueLabels: "gradelab", values: [0, L(".a"), 2, null, L(".z"), 1, 0, 2] },
    { name: "day", type: "date", format: "%tdCCYY-NN-DD", values: ["2024-03-01", null, "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01", "0001-01-01", "9999-12-31"].map(day) },
    // A date and timestamps holding letters: DOUBLE days and seconds since
    // 1970, with "logical" in the profile.
    { name: "seen", type: "date", values: at(["2024-03-01", null, "2024-03-02", null, "1960-01-01", null, "1970-01-02", "1970-01-03"].map(day), [null, ".d", null, null, null, ".z", null, null]) },
    { name: "when", type: "timestamp", unit: "us", timeZone: "America/New_York", values: us([0, 1709285400.25, null, -1, 86400, 1e9, 2e9, -2e9]) },
    { name: "stamp", type: "timestamp", unit: "us", timeZone: "UTC", values: at(us([0.5, null, 1e9, null, -86400.25, 1.000001, 2, 3]), [null, ".k", null, null, null, null, null, null]) },
    { name: "local_ms", type: "timestamp", unit: "ms", values: [-1e12, 0, null, 1, 2, 3, 4, 1.7e12] },
    { name: "local_ns", type: "timestamp", unit: "ns", values: [0n, 1000n, null, 1700000000123456000n, -1000n, 2000n, 3000n, 4000n] },
  ],
};

// Several row groups: 1,200 rows.
const N = 1200;
const rows = Array.from({ length: N }, (_, i) => i + 1);
const letter = (i) => MISSING[`.${"abcdefghijklmnopqrstuvwxyz"[i % 26]}`];
const many = {
  valueLabels: { lab: new Map([[0, "None"], [1, "Some"], [2, "Many"], [L(".a"), "Refused"], [L(".m"), "Skipped"]]) },
  variables: [
    { name: "i", type: "long", values: rows },
    { name: "lab", type: "byte", label: "Labelled", valueLabels: "lab", values: rows.map((i) => (i % 4 === 1 ? null : i % 4 === 2 ? letter(i) : i % 3)) },
    { name: "x", values: rows.map((i) => (i % 11 === 0 ? null : i * 1.25 - 7)) },
    { name: "few", type: "string", values: rows.map((i) => (i % 29 === 0 ? null : ["alpha", "béta", "", "gamma"][i % 4])) },
    { name: "many", type: "string", values: rows.map((i) => `value ${i}`) },
    { name: "cat", type: "categorical", levels: ["low", "mid", "high", "unused"], values: rows.map((i) => i % 3) },
    { name: "catletters", type: "categorical", levels: ["low", "mid", "high"], values: rows.map((i) => (i % 5 === 1 ? letter(i) : i % 5 === 2 ? null : i % 3)) },
    { name: "when", type: "timestamp", unit: "ms", timeZone: "Asia/Kolkata", values: rows.map((i) => 1.7e12 + i) },
  ],
};

// Values R's reader refuses by default: 64-bit integers a double does
// not hold exactly, and nanoseconds below a microsecond.
const edges = {
  variables: [
    { name: "big", type: "int64", values: [9007199254740993n, -9223372036854775807n, null, 1n] },
    { name: "local_ns", type: "timestamp", unit: "ns", values: [0n, 1n, null, 1700000000123456789n] },
  ],
};

for (const [name, data, options] of [
  ["ts_types", types, {}],
  ["ts_edges", edges, {}],
  ["ts_types_no_letters", types, { missingLetters: false }],
  ["ts_rows_zstd", many, { compression: "zstd", rowGroupSize: 300 }],
  ["ts_rows_lz4_raw", many, { compression: "lz4_raw", rowGroupSize: 500 }],
]) {
  saveParquet(data, join(DIR, `${name}.parquet`), options);
  console.log("TypeScript wrote", name);
}
