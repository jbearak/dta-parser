// String columns read the same plain and as dictionaries, whatever their
// text, however many distinct values, and across many wasm calls
// (plan 0008 S1-S3): each value compared with what was written.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

process.env.DTA_TEST_BLOCK_ROWS = "7919";
const require = createRequire(import.meta.url);
const { openDta, writeDta } = require("../dist/index.js");

let seed = 5;
const rnd = (n) => ((seed = (seed * 1103515245 + 12345) % 2 ** 31), seed % n);
const pool = ["", "a", "plain", "é", "naïve café", "€100", "😀", "a😀b", "﻿", "﻿lead", "x﻿", "日本語", "Ω"];
const ROWS = 150_000;

const columns = {
  // Few distinct values: stays a dictionary.
  few: Array.from({ length: ROWS }, () => pool[rnd(pool.length)]),
  // All distinct: gives the dictionary up after 65,536 rows.
  distinct: Array.from({ length: ROWS }, (_, i) => `${pool[i % pool.length]}#${i}`),
  // Repeats, then turns distinct mid-read: gives up partway.
  late: Array.from({ length: ROWS }, (_, i) => (i < 30_000 ? pool[i % 3] : `v${i}é`)),
  // strL with text and binary rows: never a dictionary.
  mixed: Array.from({ length: ROWS }, (_, i) => (i % 97 === 5 ? Uint8Array.of(0, 255, i & 255) : pool[rnd(pool.length)])),
};

const bytes = writeDta({
  variables: [
    { name: "few", values: columns.few },
    { name: "distinct", values: columns.distinct },
    { name: "late", values: columns.late },
    { name: "mixed", type: "strL", values: columns.mixed },
  ],
});

function expand(column) {
  if (column.kind === "dictionary") return Array.from(column.codes, (c) => column.values[c]);
  return column.values;
}

function same(actual, expected, name) {
  assert.equal(actual.length, expected.length, name);
  for (let i = 0; i < expected.length; i++) {
    const e = expected[i];
    if (e instanceof Uint8Array) assert.deepEqual(actual[i], e, `${name} row ${i}`);
    else if (actual[i] !== e) assert.fail(`${name} row ${i}: ${JSON.stringify(actual[i])} !== ${JSON.stringify(e)}`);
  }
}

for (const strings of ["plain", "dictionary"]) {
  test(`every value reads back (${strings})`, () => {
    const r = openDta(bytes);
    const read = r.readColumns(["few", "distinct", "late", "mixed"], { strings });
    for (const [k, name] of ["few", "distinct", "late", "mixed"].entries()) same(expand(read[k]), columns[name], name);
    if (strings === "dictionary") {
      assert.deepEqual(read.map((c) => c.kind), ["dictionary", "string", "string", "string"]);
      // Distinct values in order of first appearance.
      assert.deepEqual(read[0].values, [...new Set(columns.few)]);
    }
    r.close();
  });
}

test("ranges read the same as slices of the whole", () => {
  const r = openDta(bytes);
  for (const [start, count] of [[0, 1], [70_000, 20_000], [65_530, 30], [ROWS - 5, 5]]) {
    for (const strings of ["plain", "dictionary"]) {
      const [few, late] = r.readColumns(["few", "late"], { start, count, strings });
      same(expand(few), columns.few.slice(start, start + count), `few ${start}`);
      same(expand(late), columns.late.slice(start, start + count), `late ${start}`);
    }
  }
  r.close();
});
