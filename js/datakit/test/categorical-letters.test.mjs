// Categoricals that hold .a to .z (plan 0022): written as DOUBLE level
// numbers, read back as NumberColumns of the level numbers with the
// letters (ADR 0037) and as text by readRows; older readers; a value that
// is not a level number; saveDta.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { codesOf } from "./parquet-expected.mjs";

const require = createRequire(import.meta.url);
const dk = require("../dist/index.js");
const node = require("../dist/node.js");
const dp = { ...require("@jbearak/dta-parser"), ...require("@jbearak/dta-parser/node") };
const old = require("dta-parser-1");
const { MISSING, writeParquet, openParquet } = dk;

const dir = mkdtempSync(join(tmpdir(), "datakit-catletters-"));
process.on("exit", () => rmSync(dir, { recursive: true, force: true }));

const LEVELS = ["low", "mid", "high"];
// low, .a, high, ., .z, mid
const CODES = [0, MISSING[".a"], 2, null, MISSING[".z"], 1];
const DICT = { kind: "dictionary", codes: Uint32Array.of(0, 0, 2, 0, 0, 1), values: [...LEVELS], missing: Uint8Array.of(0, 2, 0, 1, 27, 0) };

/** Run `f`, collecting the process warnings it emits with `code`. */
async function warnings(code, f) {
  const got = [];
  const on = (w) => {
    if (w.code === code) got.push(w.message);
  };
  process.on("warning", on);
  try {
    f();
    await new Promise((r) => setImmediate(r));
  } finally {
    process.off("warning", on);
  }
  return got;
}

function checkGrade(bytes) {
  const r = openParquet(bytes);
  assert.deepEqual(r.info.warnings, []);
  const v = r.variables[0];
  assert.equal(v.type, "categorical");
  assert.equal(v.physicalType, "DOUBLE");
  assert.equal(v.columnKind, "dictionary");
  assert.deepEqual(v.categorical, { levels: LEVELS, ordered: true });
  assert.equal(v.valueLabels, "grade");
  assert.deepEqual([...r.valueLabels("grade")], [[1, "low"], [2, "mid"], [3, "high"]]);
  const [c] = r.readColumns([0]);
  assert.equal(c.kind, "number");
  assert.deepEqual(codesOf(c), [0, 2, 0, 1, 27, 0]);
  assert.deepEqual([0, 2, 5].map((i) => c.values[i]), [1, 3, 2]);
  assert.deepEqual(r.readRows(0, 6).map((row) => row[0]), ["low", MISSING[".a"], "high", MISSING["."], MISSING[".z"], "mid"]);
  r.close();
}

test("a categorical with letters writes DOUBLE level numbers and reads back with them", () => {
  for (const values of [CODES, DICT]) {
    const bytes = writeParquet({ variables: [{ name: "grade", type: "categorical", categorical: { levels: LEVELS, ordered: true }, values }] });
    checkGrade(bytes);
  }
  // Without letters it stays text, with no set.
  const r = openParquet(writeParquet({ variables: [{ name: "g", type: "categorical", levels: LEVELS, values: [0, null, 2] }] }));
  assert.equal(r.variables[0].physicalType, "BYTE_ARRAY");
  assert.equal(r.variables[0].valueLabels, "");
  assert.deepEqual(r.valueLabelNames(), []);
  // missingLetters: false writes the letters as nulls, so it stays text.
  const off = openParquet(writeParquet({ variables: [{ name: "g", type: "categorical", levels: LEVELS, values: CODES }] }, { missingLetters: false }));
  assert.equal(off.variables[0].physicalType, "BYTE_ARRAY");
  assert.deepEqual(codesOf(off.readColumns([0])[0]), [0, 1, 0, 1, 1, 0]);
});

test("the recorded set: the caller's if it fits, else the column's name or the next free one", () => {
  const sets = { g: new Map([[1, "low"], [2, "mid"], [3, "high"], [MISSING[".r"], "Refused"]]), grade: new Map([[1, "yes"]]) };
  let r = openParquet(writeParquet({ valueLabels: sets, variables: [{ name: "grade", type: "categorical", levels: LEVELS, valueLabels: "g", values: CODES }] }));
  assert.equal(r.variables[0].valueLabels, "g");
  assert.equal(r.valueLabels("g").get(MISSING[".r"]), "Refused");
  r = openParquet(writeParquet({ valueLabels: sets, variables: [{ name: "grade", type: "categorical", levels: LEVELS, values: CODES }] }));
  assert.equal(r.variables[0].valueLabels, "grade_2");
  assert.deepEqual([...r.valueLabels("grade")], [[1, "yes"]]);
});

test("the published 1.1.0 reader reads the column as labelled numbers with its letters", () => {
  const bytes = writeParquet({ variables: [{ name: "grade", type: "categorical", levels: LEVELS, values: CODES }] });
  const r = old.openParquet(bytes);
  const w = r.info.warnings;
  assert.equal(w.length, 2, w.join("\n"));
  assert.ok(w.some((m) => m.includes("logical")), w.join("\n"));
  assert.ok(w.some((m) => m.includes("levels")), w.join("\n"));
  assert.equal(r.variables[0].valueLabels, "grade");
  const [c] = r.readColumns([0]);
  assert.equal(c.kind, "number");
  assert.deepEqual(Array.from(c.missing), [0, 2, 0, 1, 27, 0]);
  assert.deepEqual([0, 2, 5].map((i) => c.values[i]), [1, 3, 2]);
  assert.deepEqual([...r.valueLabels("grade")], [[1, "low"], [2, "mid"], [3, "high"]]);
});

/** A file whose categorical holds 1.5 in its second row group (rows 2 and 3). */
function badFile() {
  // low, .a | high, mid: 3.0 only in the second row group, then made 1.5.
  const bytes = writeParquet({ variables: [{ name: "grade", type: "categorical", levels: LEVELS, values: [0, MISSING[".a"], 2, 1] }] }, { compression: "none", rowGroupSize: 2 });
  const three = new Uint8Array(new Float64Array([3]).buffer);
  const half = new Uint8Array(new Float64Array([1.5]).buffer);
  let n = 0;
  for (let i = 0; i + 8 <= bytes.length; i++) {
    if (three.every((b, j) => bytes[i + j] === b)) {
      bytes.set(half, i);
      n++;
    }
  }
  assert.ok(n > 0);
  return bytes;
}

test("a value that is not a level number reads as . with one warning per reader and column", async () => {
  const r = openParquet(badFile());
  assert.equal(r.info.rowGroups.length, 2);
  assert.equal(r.variables[0].type, "categorical");
  // The first row group: clean, no warning.
  let got = await warnings("DATAKIT_CATEGORICAL", () => {
    const [c] = r.readColumns([0], { start: 0, count: 2 });
    assert.equal(c.kind, "number");
    assert.deepEqual(codesOf(c), [0, 2]);
  });
  assert.deepEqual(got, []);
  got = await warnings("DATAKIT_CATEGORICAL", () => {
    const [c] = r.readColumns([0], { start: 1, count: 3 });
    assert.equal(c.kind, "number");
    assert.deepEqual(codesOf(c), [2, 1, 0]);
    assert.equal(c.values[2], 2);
  });
  assert.equal(got.length, 1);
  assert.match(got[0], /"grade": row 2 holds a value that is not one of its 3 level numbers/);
  // Not again from this reader.
  got = await warnings("DATAKIT_CATEGORICAL", () => r.readRows(0, 4));
  assert.deepEqual(got, []);
  r.close();
});

test("saveDta writes a categorical with letters as labelled codes, marked as a categorical", () => {
  for (const values of [CODES, DICT]) {
    const f = join(dir, `letters-${values === DICT ? "dict" : "codes"}.dta`);
    node.saveDta(
      {
        characteristics: [
          { variable: "grade", name: "dtaparser_factor", value: "ordered stale" },
          { variable: "num", name: "dtaparser_categorical", value: "unordered stale" },
        ],
        variables: [
          { name: "grade", type: "categorical", categorical: { levels: LEVELS, ordered: true }, values },
          { name: "plain", type: "categorical", levels: ["a"], values: [0, 0, null, 0, 0, 0] },
          { name: "num", values: [1, 2, 3, 4, 5, 6] },
        ],
      },
      f,
    );
    const r = dp.openDtaFile(f);
    assert.equal(r.variables[0].type, "long");
    assert.equal(r.variables[0].valueLabels, "grade");
    const [c] = r.readColumns([0]);
    assert.deepEqual(codesOf(c), [0, 2, 0, 1, 27, 0]);
    assert.deepEqual([0, 2, 5].map((i) => c.values[i]), [1, 3, 2]);
    assert.deepEqual([...r.valueLabels("grade")], [[1, "low"], [2, "mid"], [3, "high"]]);
    // Each categorical is marked, letters or not (plan 0023); the stale
    // markers given, on a categorical and on a column of numbers, are gone.
    assert.deepEqual(r.characteristics(), [
      { variable: "grade", name: "dtaparser_categorical", value: "ordered grade" },
      { variable: "plain", name: "dtaparser_categorical", value: "unordered plain" },
    ]);
    r.close();
  }
});

test("saveDta keeps the labels on letters of the set a categorical read from Parquet names", () => {
  const pq = join(dir, "labelled.parquet");
  node.saveParquet(
    {
      valueLabels: { grade: new Map([[1, "low"], [2, "mid"], [3, "high"], [MISSING[".r"], "Refused"]]) },
      variables: [{ name: "grade", type: "categorical", levels: LEVELS, valueLabels: "grade", values: [0, MISSING[".r"], 2] }],
    },
    pq,
  );
  const ds = node.readParquet(pq);
  assert.equal(ds.variables[0].valueLabels, "grade");
  const f = join(dir, "labelled.dta");
  node.saveDta(ds, f);
  const r = dp.openDtaFile(f);
  assert.equal(r.variables[0].valueLabels, "grade");
  assert.deepEqual(r.valueLabelNames(), ["grade"]);
  assert.deepEqual([...r.valueLabels("grade")], [[1, "low"], [2, "mid"], [3, "high"], [MISSING[".r"], "Refused"]]);
  assert.deepEqual(codesOf(r.readColumns([0])[0]), [0, 19, 0]);
  r.close();
});
