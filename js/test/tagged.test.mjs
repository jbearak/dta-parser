// `.` and `.a` to `.z` in a number column (ADR 0037): NA and NaNs tagged
// with their letter, in R's bits. The column's bytes, rows, labels, keys
// and writes give the same answers on every engine (ADR 0047); the
// functions that take or give a tagged NaN as a number work only where
// numbers keep NaN payloads.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { engine, nanPayloads } from "./engine.mjs";
const require = createRequire(import.meta.url);
const { MISSING, NA, dtaKey, dtaKeys, formatValue, isTaggedNa, missingCode, missingCodes, naTag, openDta, taggedNa, writeDta } = require("../dist/index.js");
const format = require("../dist/format.js");

const view = new DataView(new ArrayBuffer(8));
const bits = (x) => (view.setFloat64(0, x), view.getBigUint64(0));
const number = (b) => (view.setBigUint64(0, b), view.getFloat64(0));
/** The bits of each value of a Float64Array, from its bytes. */
const bitsOf = (values) => {
  const v = new DataView(values.buffer, values.byteOffset, values.byteLength);
  return Array.from({ length: values.length }, (_, i) => v.getBigUint64(8 * i, true));
};
const letters = Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`);

// x: 1, .r, ., 2, .a, .z, labelled .r "Refused" and .a "Not asked".
const why = new Map([[1, "Yes"], [MISSING[".r"], "Refused"], [MISSING[".a"], "Not asked"]]);
const written = writeDta({
  variables: [{ name: "x", values: [1, MISSING[".r"], null, 2, MISSING[".a"], MISSING[".z"]], valueLabels: "why" }],
  valueLabels: { why },
});

test(`${engine}: a column read holds R's bits, and missingCodes reads them`, () => {
  const r = openDta(written);
  const [col] = r.readColumns([0]);
  assert.deepEqual(Object.keys(col), ["kind", "values"]);
  assert.deepEqual(bitsOf(col.values).slice(1, 3), [0x7ff00072000007a2n, 0x7ff00000000007a2n]);
  assert.deepEqual(Array.from(missingCodes(col)), [0, 19, 1, 0, 2, 27]);
  assert.deepEqual(Array.from(format.missingCodes(col)), [0, 19, 1, 0, 2, 27]);
  // A subarray, and a plain NaN, which is a number.
  const values = new Float64Array([0, NaN, 0, 0]);
  values.set(col.values.subarray(1, 3), 2);
  assert.deepEqual(Array.from(missingCodes({ values: values.subarray(1) })), [0, 19, 1]);
  r.close();
});

test(`${engine}: readRows, readRowsAt and formatValue give .a to .z as missing values, labelled`, () => {
  const r = openDta(written);
  const cells = r.readRows(0, 6).map((row) => row[0]);
  assert.deepEqual(cells, [1, MISSING[".r"], MISSING["."], 2, MISSING[".a"], MISSING[".z"]]);
  assert.equal(cells[1], MISSING[".r"]);
  assert.deepEqual(r.readRowsAt([5, 1, 4]).map((row) => row[0]), [MISSING[".z"], MISSING[".r"], MISSING[".a"]]);
  const labels = r.valueLabels("why");
  assert.deepEqual(cells.map((c) => formatValue(c, "%9.0g", labels)), ["Yes", "Refused", ".", "2", "Not asked", ".z"]);
  r.close();
});

test(`${engine}: dtaKeys reads a column's letters from its bytes`, () => {
  const r = openDta(written);
  const [col] = r.readColumns([0]);
  const keys = dtaKeys(col);
  assert.deepEqual(Array.from(keys), [1, ".r", ".", 2, ".a", ".z"].map((x) => dtaKey(typeof x === "number" ? x : MISSING[x])));
  r.close();
});

test(`${engine}: a column read writes back with its letters, as a column or its Float64Array`, () => {
  const r = openDta(written);
  const [col] = r.readColumns([0]);
  for (const values of [col, col.values, col.values.slice(), Float64Array.from(col.values)]) {
    const again = openDta(writeDta({ variables: [{ name: "x", values }] }));
    assert.deepEqual(Array.from(missingCodes(again.readColumns([0])[0])), [0, 19, 1, 0, 2, 27]);
    assert.deepEqual(again.readRows(0, 6).map((row) => row[0]), [1, MISSING[".r"], MISSING["."], 2, MISSING[".a"], MISSING[".z"]]);
  }
  r.close();
});

test(`${engine}: a NaN that is not a missing value is not written`, () => {
  assert.throws(() => writeDta({ variables: [{ name: "x", values: [1, NaN] }] }), { code: "DTA_INVALID", name: "RangeError" });
  assert.throws(() => writeDta({ variables: [{ name: "x", values: new Float64Array([1, NaN]) }] }), { code: "DTA_INVALID", name: "RangeError" });
});

if (nanPayloads) {
  test(`${engine} keeps NaN payloads: the bits are R's: NA_real_, and the letter in byte 4`, () => {
    assert.equal(bits(NA), 0x7ff00000000007a2n);
    assert.equal(bits(taggedNa(".a")), 0x7ff00061000007a2n);
    assert.equal(bits(taggedNa("z")), 0x7ff0007a000007a2n);
    for (const bad of ["", ".", "A", ".A", "ab", "1"]) assert.throws(() => taggedNa(bad), /a letter is/);
  });

  test(`${engine} keeps NaN payloads: missingCode, naTag and isTaggedNa`, () => {
    letters.forEach((l, i) => {
      assert.equal(missingCode(taggedNa(l)), i + 2);
      assert.equal(naTag(taggedNa(l)), l);
      assert.ok(isTaggedNa(taggedNa(l)) && isTaggedNa(taggedNa(l), l) && !isTaggedNa(taggedNa(l), i ? ".a" : ".b"));
    });
    assert.equal(missingCode(NA), 1);
    assert.equal(naTag(NA), undefined);
    assert.ok(!isTaggedNa(NA));
    // Numbers, and NaNs that are not R's, are numbers.
    for (const x of [0, -1.5, Infinity, NaN, number(0x7ff00041000007a2n), number(0x7ff00061000007a3n)]) {
      assert.equal(missingCode(x), 0, String(x));
    }
    // Arithmetic and plain arrays may quiet the NaN or flip its sign.
    const d = taggedNa(".d");
    for (const x of [d * 2, -d, d + 1, [1, d][1]]) assert.equal(naTag(x), ".d");
  });

  test(`${engine} keeps NaN payloads: tagged numbers write, and a column's values[i] reads`, () => {
    const values = new Float64Array([1, 0, 0, 2]);
    values[1] = taggedNa(".r");
    values[2] = NA;
    const r = openDta(writeDta({
      variables: [{ name: "x", values, valueLabels: "why" }],
      valueLabels: { why: new Map([[MISSING[".r"], "Refused"]]) },
    }));
    const [col] = r.readColumns([0]);
    assert.deepEqual(Array.from(col.values, missingCode), [0, 19, 1, 0]);
    assert.deepEqual(r.readRows(0, 4).map((row) => row[0]), [1, MISSING[".r"], MISSING["."], 2]);
    assert.equal(formatValue(col.values[1], "%9.0g", r.valueLabels("why")), "Refused");
    assert.equal(formatValue(col.values[2], "%9.0g"), ".");
    assert.equal(dtaKey(taggedNa("z")), dtaKey(MISSING[".z"]));
    // Missing objects, null and tagged numbers in a plain array write the same.
    for (const plain of [[1, MISSING[".r"], null, 2], [1, taggedNa(".r"), NA, 2], Array.from(col.values)]) {
      const again = openDta(writeDta({ variables: [{ name: "x", values: plain }] }));
      assert.deepEqual(Array.from(missingCodes(again.readColumns([0])[0])), [0, 19, 1, 0]);
    }
  });
} else {
  test(`${engine} clears NaN payloads: a number cannot hold a letter, and says so`, () => {
    // NA is a plain NaN here: a number, as any untagged NaN.
    assert.equal(missingCode(NA), 0);
    assert.equal(naTag(NA), undefined);
    assert.ok(!isTaggedNa(NA));
    for (const l of letters) assert.throws(() => taggedNa(l), { code: "DTA_INVALID", message: /clears NaN payloads/ });
    for (const bad of ["", ".", "A", ".A", "ab", "1"]) assert.throws(() => taggedNa(bad), /a letter is/);
    assert.throws(() => isTaggedNa(NA, "A"), /a letter is/);
    // A column's value, loaded into a number, has lost its letter...
    const r = openDta(written);
    const [col] = r.readColumns([0]);
    assert.equal(missingCode(col.values[1]), 0);
    assert.equal(bits(col.values[1]), 0x7ff8000000000000n);
    // ...but formatValue and dtaKey still show and sort it as missing.
    assert.equal(formatValue(col.values[1], "%9.0g"), ".");
    assert.equal(dtaKey(col.values[1]), dtaKey(MISSING["."]));
    // Copied value by value it cannot be written, rather than written as `.`.
    for (const plain of [Array.from(col.values), [1, NA], new Float64Array([1, NA])]) {
      assert.throws(() => writeDta({ variables: [{ name: "x", values: plain }] }), { code: "DTA_INVALID", name: "RangeError", message: /clears NaN payloads/ });
    }
    r.close();
  });
}
