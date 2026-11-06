// dtaKey and dtaKeys order values as Stata does: numbers, then . < .a < ... < .z.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { dtaKey, dtaKeys, stataKey, stataKeys, MISSING } = require("../dist/index.js");

test("stataKey and stataKeys, the 1.0 names, are dtaKey and dtaKeys", () => {
  assert.equal(stataKey, dtaKey);
  assert.equal(stataKeys, dtaKeys);
});

test("missing values sort after every number, in code order", () => {
  const values = [MISSING[".z"], 3, MISSING["."], -1e300, MISSING[".a"], 8.98e307, 0];
  const sorted = [...values].sort((a, b) => dtaKey(a) - dtaKey(b));
  assert.deepEqual(sorted, [-1e300, 0, 3, 8.98e307, MISSING["."], MISSING[".a"], MISSING[".z"]]);
  assert.ok(Number.isFinite(dtaKey(MISSING[".z"])));
  assert.equal(dtaKey(NaN), dtaKey(MISSING["."]));
  assert.notEqual(dtaKey(MISSING[".a"]), dtaKey(MISSING[".b"]));
});

test("dtaKeys follows a column's missing codes", () => {
  const column = { kind: "number", values: Float64Array.from([2, NaN, NaN, 1]), missing: Uint8Array.from([0, 3, 1, 0]) };
  const keys = dtaKeys(column);
  assert.deepEqual(Array.from(keys.slice(0, 1)), [2]);
  assert.equal(keys[1], dtaKey(MISSING[".b"]));
  assert.equal(keys[2], dtaKey(MISSING["."]));
  assert.ok(keys[3] < keys[0] && keys[0] < keys[2] && keys[2] < keys[1]);
});
