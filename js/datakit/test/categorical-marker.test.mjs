// Plan 0023's dtaparser_categorical: saveDta marks every categorical, and
// readDta restores a marked one with its letter labels, or reads it as
// labelled numbers, with a warning, when the file changed since. One
// holding .a to .z in the rows read stays labelled numbers holding them,
// its marker kept (ADR 0037).
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { codesOf } from "./parquet-expected.mjs";

const require = createRequire(import.meta.url);
const dk = require("../dist/index.js");
const node = require("../dist/node.js");
const dp = { ...require("@jbearak/dta-parser"), ...require("@jbearak/dta-parser/node") };
const { MISSING, readDataset } = dk;

const dir = mkdtempSync(join(tmpdir(), "datakit-catmark-"));
process.on("exit", () => rmSync(dir, { recursive: true, force: true }));
let n = 0;
const path = () => join(dir, `${n++}.dta`);

const LEVELS = ["low", "mid", "high", "unused"];
// low, .a, high, ., .r, mid
const DICT = { kind: "dictionary", codes: Uint32Array.of(0, 0, 2, 0, 0, 1), values: [...LEVELS], missing: Uint8Array.of(0, 2, 0, 1, 19, 0) };

/** readDta, collecting the warnings. */
function read(f) {
  const got = [];
  const ds = node.readDta(f, { onWarning: (m) => got.push(m) });
  return { ds, got };
}

test("saveDta marks a categorical with letters and letter labels; readDta gives it back", () => {
  const f = path();
  node.saveDta(
    {
      // The set the variable names, which labels .r; it is not the column's name.
      valueLabels: { gl: new Map([[1, "low"], [2, "mid"], [3, "high"], [4, "unused"], [MISSING[".r"], "Refused"]]) },
      variables: [{ name: "grade", type: "categorical", categorical: { levels: LEVELS, ordered: true }, valueLabels: "gl", values: DICT }],
    },
    f,
  );
  const r = dp.openDtaFile(f);
  assert.deepEqual(r.characteristics(), [{ variable: "grade", name: "dtaparser_categorical", value: "ordered gl" }]);
  r.close();
  const { ds, got } = read(f);
  assert.deepEqual(got, []);
  const v = ds.variables[0];
  // It holds letters, so it stays its codes with them, labelled, the
  // marker kept.
  assert.equal(v.type, "long");
  assert.equal(v.categorical, undefined);
  assert.deepEqual(codesOf(v.values), [0, 2, 0, 1, 19, 0]);
  assert.deepEqual([0, 2, 5].map((i) => v.values.values[i]), [1, 3, 2]);
  assert.equal(v.valueLabels, "gl");
  assert.deepEqual([...ds.valueLabels.gl], [[1, "low"], [2, "mid"], [3, "high"], [4, "unused"], [MISSING[".r"], "Refused"]]);
  assert.deepEqual(ds.characteristics, [{ variable: "grade", name: "dtaparser_categorical", value: "ordered gl" }]);
  // The browser path gives the same.
  const b = dp.openDta(readFileSync(f));
  assert.deepEqual(readDataset(b), ds);
  b.close();
  // Saved again: the same set, codes and letters, as labelled numbers.
  const again = path();
  node.saveDta(ds, again);
  const r2 = dp.openDtaFile(again);
  assert.deepEqual(r2.valueLabelNames(), ["gl"]);
  assert.deepEqual([...r2.valueLabels("gl")], [...ds.valueLabels.gl]);
  assert.deepEqual(codesOf(r2.readColumns([0])[0]), [0, 2, 0, 1, 19, 0]);
  assert.deepEqual(r2.characteristics(), []);
  r2.close();
});

test("a marked categorical without letter labels drops its set, as a factor does", () => {
  const f = path();
  node.saveDta({ variables: [{ name: "g", type: "categorical", levels: ["a", "b", "c"], values: [0, null, 2] }] }, f);
  const { ds, got } = read(f);
  assert.deepEqual(got, []);
  const v = ds.variables[0];
  assert.equal(v.type, "categorical");
  // No ordering given: unordered.
  assert.deepEqual(v.categorical, { levels: ["a", "b", "c"], ordered: false, labelSet: "g", codes: [1, 2, 3] });
  assert.equal(v.valueLabels, "");
  assert.deepEqual(Object.keys(ds.valueLabels), []);
  assert.deepEqual(codesOf(v.values), [0, 1, 0]);
  // With a letter: its codes, labelled, the letter kept.
  const g = path();
  node.saveDta({ variables: [{ name: "g", type: "categorical", levels: ["a", "b", "c"], values: [0, MISSING[".a"], 2] }] }, g);
  const lettered = read(g);
  assert.deepEqual(lettered.got, []);
  assert.equal(lettered.ds.variables[0].type, "long");
  assert.deepEqual(codesOf(lettered.ds.variables[0].values), [0, 2, 0]);
  assert.equal(lettered.ds.variables[0].valueLabels, "g");
});

/** A .dta file with `region` marked `dtaparser_categorical` (and whatever `chars` adds), written by dta-parser. */
function marked({
  set = "region",
  labels = new Map([[10, "low"], [20, "mid"], [30, "high"], [MISSING[".a"], "Not asked"]]),
  values = [10, MISSING[".a"], 30, null, MISSING[".z"]],
  mark = `unordered ${set}`,
  chars = [],
  variable,
} = {}) {
  const f = path();
  dp.writeDtaFile(f, {
    valueLabels: { [set]: labels },
    characteristics: [{ variable: "region", name: "dtaparser_categorical", value: mark }, ...chars],
    variables: [variable ?? { name: "region", type: "long", valueLabels: set, values }],
  });
  return f;
}

test("a file's codes 10, 20, 30 stay the categorical's codes; a label on a letter no row holds passes", () => {
  const { ds, got } = read(marked({ values: [10, 20, 30, null] }));
  assert.deepEqual(got, []);
  const v = ds.variables[0];
  assert.deepEqual(v.categorical, { levels: ["low", "mid", "high"], ordered: false, labelSet: "region", codes: [10, 20, 30] });
  assert.deepEqual(v.values, { kind: "dictionary", codes: Uint32Array.of(0, 1, 2, 0), values: ["low", "mid", "high"], missing: Uint8Array.of(0, 0, 0, 1) });
  assert.equal(v.valueLabels, "region");
  // Saved: the same codes.
  const out = path();
  node.saveDta(ds, out);
  const r = dp.openDtaFile(out);
  assert.deepEqual(Array.from(r.readColumns([0])[0].values).map((x) => (Number.isNaN(x) ? null : x)), [10, 20, 30, null]);
  assert.deepEqual([...r.valueLabels("region")], [[10, "low"], [20, "mid"], [30, "high"], [MISSING[".a"], "Not asked"]]);
  r.close();
  // A label on .a that no row holds, whose text repeats a level's.
  const unused = read(marked({ labels: new Map([[1, "yes"], [2, "no"], [MISSING[".a"], "no"]]), values: [1, 2] }));
  assert.deepEqual(unused.got, []);
  assert.deepEqual(unused.ds.variables[0].categorical.levels, ["yes", "no"]);
  // Holding .a and .z: its codes 10 and 30 with the letters, the marker kept.
  const held = read(marked());
  assert.deepEqual(held.got, []);
  assert.equal(held.ds.variables[0].type, "long");
  assert.deepEqual(codesOf(held.ds.variables[0].values), [0, 2, 0, 1, 27]);
  assert.deepEqual(held.ds.characteristics.map((c) => c.name), ["dtaparser_categorical"]);
});

test("dtaparser_factor still restores, and letters in it still fail", () => {
  const values = [10, 20, null];
  const labels = new Map([[10, "low"], [20, "high"]]);
  const f = path();
  dp.writeDtaFile(f, {
    valueLabels: { s: labels },
    characteristics: [{ variable: "x", name: "dtaparser_factor", value: "ordered s" }],
    variables: [{ name: "x", type: "long", valueLabels: "s", values }],
  });
  const ok = read(f);
  assert.deepEqual(ok.got, []);
  assert.deepEqual(ok.ds.variables[0].categorical, { levels: ["low", "high"], ordered: true, labelSet: "s", codes: [10, 20] });
  assert.equal(ok.ds.variables[0].valueLabels, "");
  const g = path();
  dp.writeDtaFile(g, {
    valueLabels: { s: labels },
    characteristics: [{ variable: "x", name: "dtaparser_factor", value: "ordered s" }],
    variables: [{ name: "x", type: "long", valueLabels: "s", values: [10, MISSING[".a"]] }],
  });
  const stale = read(g);
  assert.equal(stale.ds.variables[0].type, "long");
  assert.match(stale.got[0][0], /^A column marked as a factor was changed/);
  assert.match(stale.got[0][1], /row 1 holds an extended missing value/);
});

/** `f` with its one run of the 4 bytes `from` made `to` (dta-parser's writer refuses to write what the tests need). */
function patch(f, from, to) {
  const b = readFileSync(f);
  let k = 0;
  for (let i = 0; i + 4 <= b.length; i++) {
    if (from.every((x, j) => b[i + j] === x)) {
      b.set(to, i);
      k++;
    }
  }
  assert.equal(k, 1);
  writeFileSync(f, b);
  return f;
}
// The long code -2147483647 made -2147483648, past long's range.
const pastLong = (f) => patch(f, [1, 0, 0, 0x80], [0, 0, 0, 0x80]);
// A label on .a (2147483622) made one on . (2147483621).
const dotLabel = (f) => patch(f, [0xe6, 0xff, 0xff, 0x7f], [0xe5, 0xff, 0xff, 0x7f]);

test("a categorical marker that no longer holds gives labelled numbers and the warning", () => {
  const cases = [
    [marked({ mark: "unordered elsewhere" }), /its value label set is "region", not "elsewhere"/],
    [marked({ values: [10, 40] }), /row 1 holds 40, which has no label/],
    [marked({ labels: new Map([[10, "same"], [20, "same"]]), values: [10] }), /two codes in its value label set share the text "same"/],
    [pastLong(marked({ labels: new Map([[-2147483647, "low"], [1, "high"]]), values: [1] })), /has the code -2147483648, which is not a whole number within long's range/, false],
    [dotLabel(marked({ labels: new Map([[10, "low"], [MISSING[".a"], "Missing"]]), values: [10] })), /labels the missing value \.$/, false],
    [marked({ mark: "sideways region" }), /its dtaparser_categorical characteristic is not "ordered <set>" or "unordered <set>"/],
    [marked({ variable: { name: "region", values: ["low", "high"] } }), /it is not numeric/],
    [marked({ chars: [{ variable: "region", name: "dtaparser_factor", value: "unordered region" }] }), /it has both markers, dtaparser_factor and dtaparser_categorical/],
    // (A code 1.5 cannot be tested: a .dta value label's code is a 4-byte integer.)
  ];
  // (saves: whether saveDta can write the set back; it refuses these two.)
  for (const [f, why, saves = true] of cases) {
    const { ds, got } = read(f);
    assert.equal(got.length, 1, String(why));
    assert.equal(got[0][0], "A column marked as a categorical was changed after it was written, so it is read as labelled numbers:");
    assert.equal(got[0].length, 2);
    assert.match(got[0][1], /^region: /);
    assert.match(got[0][1], why);
    const v = ds.variables[0];
    assert.notEqual(v.type, "categorical");
    assert.equal(v.categorical, undefined);
    assert.notEqual(v.values.kind, "dictionary");
    // The markers stay as read; saving drops them.
    assert.ok(ds.characteristics.some((c) => c.name === "dtaparser_categorical"));
    if (!saves) continue;
    const out = path();
    node.saveDta(ds, out);
    const r = dp.openDtaFile(out);
    assert.deepEqual(r.characteristics(), []);
    r.close();
  }
});

test("stale factors and categoricals share one warning", () => {
  const f = path();
  dp.writeDtaFile(f, {
    valueLabels: { s: new Map([[1, "a"]]) },
    characteristics: [
      { variable: "x", name: "dtaparser_factor", value: "unordered s" },
      { variable: "y", name: "dtaparser_categorical", value: "unordered s" },
      { variable: "z", name: "dtaparser_categorical", value: "ordered s" },
    ],
    variables: [
      { name: "x", type: "long", valueLabels: "s", values: [2, 1] },
      { name: "y", type: "long", valueLabels: "s", values: [3, 1] },
      { name: "z", type: "long", valueLabels: "s", values: [1, MISSING[".b"]] },
    ],
  });
  const { ds, got } = read(f);
  assert.equal(got.length, 1);
  assert.deepEqual(got[0], [
    "Columns marked as factors or categoricals were changed after they were written, so they are read as labelled numbers:",
    "x: row 0 holds 2, which has no label",
    "y: row 0 holds 3, which has no label",
  ]);
  // z holds .b, so it stays numbers too, without a warning.
  assert.deepEqual(ds.variables.map((v) => v.type), ["long", "long", "long"]);
  // The set stays: x, y and z still use it.
  assert.deepEqual(Object.keys(ds.valueLabels), ["s"]);
  assert.deepEqual(ds.characteristics.map((c) => c.variable), ["x", "y", "z"]);
});

test("this reader converts no dates, so a date format does not make the marker fail", () => {
  for (const format of ["%td", "%d"]) {
    const f = marked({ variable: { name: "region", type: "long", format, valueLabels: "region", values: [10, 20] } });
    const { ds, got } = read(f);
    assert.deepEqual(got, []);
    assert.equal(ds.variables[0].type, "categorical");
  }
});
