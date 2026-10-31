// readRowsAt (plan 0008 D6): the rows listed, in their order, as
// readRows gives them, across many module calls.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

process.env.DTA_TEST_BLOCK_ROWS = "7";
const require = createRequire(import.meta.url);
const { openDta, writeDta, MISSING } = require("../dist/index.js");

const N = 300;
const bytes = writeDta({
  variables: [
    { name: "x", values: Array.from({ length: N }, (_, i) => (i % 11 === 3 ? MISSING[".b"] : i * 1.5)) },
    { name: "s", values: Array.from({ length: N }, (_, i) => `${"é".repeat(i % 5)}${i}`) },
    { name: "l", type: "strL", values: Array.from({ length: N }, (_, i) => (i % 13 === 0 ? Uint8Array.of(i & 255, 0) : `long ${i}`)) },
  ],
});

test("rows in any order, with repeats, match readRows", () => {
  const r = openDta(bytes);
  let seed = 3;
  const rows = [299, 0, 1, 2, 3, 150, 150, 9, 8, 7, ...Array.from({ length: 200 }, () => (seed = (seed * 1103515245 + 12345) % 2 ** 31) % N)];
  for (const columns of [undefined, ["l", "x"], [1]]) {
    const got = r.readRowsAt(rows, columns);
    assert.equal(got.length, rows.length);
    rows.forEach((row, j) => assert.deepEqual(got[j], r.readRows(row, 1, columns)[0], `row ${row}`));
  }
  assert.deepEqual(r.readRowsAt([]), []);
});

test("rows outside the file are DTA_OUT_OF_RANGE", () => {
  const r = openDta(bytes);
  for (const bad of [-1, N, 1.5, NaN]) {
    assert.throws(() => r.readRowsAt([0, bad]), (e) => e instanceof RangeError && e.code === "DTA_OUT_OF_RANGE");
  }
  assert.equal(r.readRowsAt([N - 1])[0][0], (N - 1) * 1.5);
});
