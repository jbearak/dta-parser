// `.` and `.a` to `.z` in a number column (ADR 0037): NA and NaNs tagged
// with their letter, in R's bits.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { MISSING, NA, formatValue, isTaggedNa, missingCode, naTag, openDta, taggedNa, writeDta } = require("../dist/index.js");

const view = new DataView(new ArrayBuffer(8));
const bits = (x) => (view.setFloat64(0, x), view.getBigUint64(0));
const number = (b) => (view.setBigUint64(0, b), view.getFloat64(0));

test("the bits are R's: NA_real_, and the letter in byte 4", () => {
  assert.equal(bits(NA), 0x7ff00000000007a2n);
  assert.equal(bits(taggedNa(".a")), 0x7ff00061000007a2n);
  assert.equal(bits(taggedNa("z")), 0x7ff0007a000007a2n);
  for (const bad of ["", ".", "A", ".A", "ab", "1"]) assert.throws(() => taggedNa(bad), /a letter is/);
});

test("missingCode, naTag and isTaggedNa", () => {
  const letters = Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`);
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

test("a column holds its letters, and readRows and formatValue give them as missing values", () => {
  const values = new Float64Array([1, 0, 0, 2]);
  values[1] = taggedNa(".r");
  values[2] = NA;
  const r = openDta(writeDta({
    variables: [{ name: "x", values, valueLabels: "why" }],
    valueLabels: { why: new Map([[MISSING[".r"], "Refused"]]) },
  }));
  const [col] = r.readColumns([0]);
  assert.deepEqual(Object.keys(col), ["kind", "values"]);
  assert.deepEqual(Array.from(col.values, missingCode), [0, 19, 1, 0]);
  assert.deepEqual(r.readRows(0, 4).map((row) => row[0]), [1, MISSING[".r"], MISSING["."], 2]);
  assert.equal(formatValue(col.values[1], "%9.0g", r.valueLabels("why")), "Refused");
  assert.equal(formatValue(col.values[2], "%9.0g"), ".");
  // Missing objects, null and tagged numbers in a plain array write the same.
  const again = openDta(writeDta({ variables: [{ name: "x", values: [1, MISSING[".r"], null, 2] }] }));
  assert.deepEqual(Array.from(again.readColumns([0])[0].values, missingCode), [0, 19, 1, 0]);
});
