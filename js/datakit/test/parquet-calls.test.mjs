// Reads split into many module calls (a budget of a few kilobytes in
// place of 64 MiB): by row groups, by columns and by rows, with text
// dictionaries and levels found in the rows carried across calls.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { checkFixture, parquetFixtures } from "./parquet-expected.mjs";

process.env.DTA_TEST_PARQUET_BUDGET = "6000";
const require = createRequire(import.meta.url);
const { openParquet, writeParquet } = require("../dist/index.js");

test("files other tools wrote read the same in small calls", () => {
  for (const { stem, doc, bytes } of parquetFixtures()) {
    const r = openParquet(bytes, doc.nested ? { nested: "skip" } : {});
    checkFixture(r, stem, doc, 0, doc.rows);
    checkFixture(r, stem, doc, 97, 401);
  }
});

test("text dictionaries carry across calls, and give up into plain strings", () => {
  const n = 70_000;
  const few = Array.from({ length: n }, (_, i) => (i % 101 === 0 ? null : `v${i % 7}`));
  // Distinct values past 65,536 rows: the dictionary gives up mid-read.
  const many = Array.from({ length: n }, (_, i) => (i < 1000 ? `r${i % 3}` : `u${i}`));
  const r = openParquet(writeParquet({ variables: [{ name: "few", values: few }, { name: "many", values: many }] }, { rowGroupSize: 9000 }));
  for (const strings of ["plain", "dictionary"]) {
    const [a, b] = r.readColumns([0, 1], { strings });
    for (let i = 0; i < n; i++) {
      const x = a.kind === "dictionary" ? (a.missing[i] ? null : a.values[a.codes[i]]) : a.missing[i] ? null : a.values[i];
      assert.equal(x, few[i], `few ${i}`);
      const y = b.kind === "dictionary" ? b.values[b.codes[i]] : b.values[i];
      assert.equal(y, many[i], `many ${i}`);
    }
    if (strings === "dictionary") {
      assert.equal(a.kind, "dictionary");
      assert.equal(b.kind, "string");
    }
  }
});
