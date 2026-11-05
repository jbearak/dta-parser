// Parquet (plan 0018): round trips of what readDta returns, constructed
// data, files other tools wrote, windows, readRowsAt, the bytes a read
// touches, the async reader and the page cache.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync, openSync, closeSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkFixture, parquetFixtures } from "./parquet-expected.mjs";

const require = createRequire(import.meta.url);
const { openDta, openParquet, openParquetAsync, writeParquet, writeDta, ParquetReader, MISSING, isMissing, toDate } = require("../dist/index.js");
const { openParquetFile, writeParquetFile } = require("../dist/node.js");

const compat = new URL("../../compat/", import.meta.url);

/** What a .dta file holds, as WriteDataset, from its reader. */
function datasetOf(r) {
  const cols = r.readColumns(r.variables.map((_, i) => i));
  const valueLabels = {};
  for (const v of r.variables) {
    const labels = v.valueLabels && r.valueLabels(v.valueLabels);
    if (labels) valueLabels[v.valueLabels] = labels;
  }
  return {
    cols,
    data: {
      label: r.info.label,
      notes: r.notes(),
      characteristics: r.characteristics(),
      sortedBy: r.info.sortedBy,
      valueLabels,
      variables: r.variables.map((v, k) => ({ ...v, valueLabels: valueLabels[v.valueLabels] ? v.valueLabels : undefined, values: cols[k] })),
    },
  };
}

const withoutNotes = (chars) => chars.filter((c) => !(c.variable === "_dta" && /^note[0-9]+$/.test(c.name)));

for (const name of readdirSync(new URL("fixtures/", compat)).filter((f) => f.endsWith(".dta"))) {
  test(`${name}: what readDta returns comes back from Parquet`, () => {
    const r = openDta(readFileSync(new URL(`fixtures/${name}`, compat)), name.includes("_11") || name.includes("_10") ? {} : {});
    const { cols, data } = datasetOf(r);
    for (const compression of ["snappy", "zstd"]) {
      const p = openParquet(writeParquet(data, { compression }));
      assert.equal(p.info.format, "parquet");
      assert.equal(p.info.nobs, r.info.nobs);
      assert.equal(p.info.label, r.info.label);
      assert.deepEqual(p.info.sortedBy, r.info.sortedBy);
      assert.deepEqual(p.notes(), r.notes());
      assert.deepEqual(p.characteristics(), withoutNotes(r.characteristics()));
      const got = p.readColumns(p.variables.map((_, i) => i));
      r.variables.forEach((v, k) => {
        const pv = p.variables[k];
        assert.equal(pv.name, v.name);
        assert.equal(pv.format, v.format);
        assert.equal(pv.label, v.label);
        assert.equal(pv.valueLabels, data.variables[k].valueLabels ?? "");
        const c = cols[k];
        if (c.kind === "number") {
          assert.equal(pv.type, v.type, v.name);
          assert.deepEqual(got[k], c, v.name);
        } else {
          // A strL holding binary values is a binary column: its text
          // comes back as bytes (plan 0018, "Column types we write").
          const binary = c.values.some((x) => x instanceof Uint8Array);
          assert.equal(pv.type, binary ? "binary" : "string", v.name);
          const want = binary ? c.values.map((x) => (typeof x === "string" ? new TextEncoder().encode(x) : x)) : c.values;
          assert.deepEqual(got[k].values, want, v.name);
          assert.ok(!got[k].missing.includes(1));
        }
      });
      for (const set of Object.keys(data.valueLabels)) assert.deepEqual(p.valueLabels(set), r.valueLabels(set), set);
      // And back to .dta: the same values again.
      const back = openDta(writeDta({ ...data, variables: p.variables.map((v, k) => ({ ...v, values: got[k] })) }));
      const again = back.readColumns(back.variables.map((_, i) => i));
      cols.forEach((c, k) => {
        if (c.kind === "number") assert.deepEqual(again[k], c);
      });
    }
  });
}

/** A table with every kind of value plan 0018 writes from TypeScript. */
function constructed(n) {
  const letters = (i) => MISSING[`.${"abcdefghijklmnopqrstuvwxyz"[i % 26]}`];
  return {
    label: "Constructed, 2026",
    notes: ["First note.", "Second note: ü"],
    sortedBy: ["id"],
    characteristics: [{ variable: "age", name: "source", value: "q12" }],
    valueLabels: {
      agelbl: new Map([
        [97, "Refused"],
        [MISSING[".d"], "Don't know"],
      ]),
    },
    variables: [
      { name: "id", type: "long", values: Array.from({ length: n }, (_, i) => i) },
      { name: "age", type: "byte", label: "Age in years", format: "%9.0g", valueLabels: "agelbl", values: Array.from({ length: n }, (_, i) => (i % 17 === 3 ? letters(i) : i % 23 === 5 ? null : i % 100)) },
      { name: "inc", type: "int", values: Array.from({ length: n }, (_, i) => (i % 11 === 0 ? MISSING["."] : (i * 7) % 30000)) },
      { name: "big", type: "long", values: Array.from({ length: n }, (_, i) => (i % 13 === 1 ? letters(i + 3) : i * 1000)) },
      { name: "f", type: "float", values: Array.from({ length: n }, (_, i) => (i % 9 === 4 ? letters(i) : Math.fround(i / 8))) },
      { name: "d", values: Array.from({ length: n }, (_, i) => (i % 19 === 2 ? letters(i) : i % 7 === 6 ? NaN : i * 0.25 - 3)) },
      { name: "flag", type: "bool", values: Array.from({ length: n }, (_, i) => (i % 5 === 0 ? null : i % 2)) },
      { name: "day", type: "date", format: "%tdCCYY-NN-DD", values: Array.from({ length: n }, (_, i) => (i % 31 === 0 ? null : -40000 + i * 7)) },
      { name: "dayx", type: "date", values: Array.from({ length: n }, (_, i) => (i % 29 === 1 ? letters(i) : i)) },
      { name: "when", type: "timestamp", unit: "us", timeZone: "America/New_York", values: Array.from({ length: n }, (_, i) => (i % 37 === 0 ? null : 1_700_000_000_000_000 + i * 1_000_001)) },
      { name: "local", type: "timestamp", unit: "ns", values: Array.from({ length: n }, (_, i) => (i % 41 === 0 ? null : 1_700_000_000_000_000_123n + BigInt(i))) },
      { name: "secs", type: "timestamp", unit: "s", timeZone: "Asia/Tokyo", values: Array.from({ length: n }, (_, i) => (i % 43 === 2 ? letters(i) : 1e9 + i / 3)) },
      { name: "n64", values: Array.from({ length: n }, (_, i) => (i % 47 === 0 ? null : BigInt(i) * 3n ** 30n - 2n ** 62n)) },
      { name: "small64", type: "int64", values: Array.from({ length: n }, (_, i) => (i % 3 === 0 ? null : i - 5)) },
      { name: "word", values: Array.from({ length: n }, (_, i) => (i % 53 === 0 ? null : ["alpha", "beta", "gamma", "délta", ""][i % 5])) },
      { name: "uniq", values: Array.from({ length: n }, (_, i) => `row ${i} 😀`.repeat(1 + (i % 3))) },
      { name: "blob", type: "binary", values: Array.from({ length: n }, (_, i) => (i % 59 === 0 ? null : Uint8Array.of(i & 255, 0, 255))) },
      { name: "region", type: "categorical", levels: ["North", "South", "West", "Unused"], ordered: true, values: Array.from({ length: n }, (_, i) => (i % 61 === 0 ? null : i % 3)) },
    ],
  };
}

/** What `readColumns` should give for one constructed variable over rows. */
function expectedColumn(v, from, to) {
  const xs = v.values.slice(from, to);
  const code = (x) => (x === null ? 1 : isMissing(x) ? ["."].concat([..."abcdefghijklmnopqrstuvwxyz"].map((c) => `.${c}`)).indexOf(x.missing) + 1 : 0);
  if (v.name === "n64" || v.name === "local") {
    return { kind: "bigint", values: BigInt64Array.from(xs, (x) => x ?? 0n), missing: Uint8Array.from(xs, (x) => (x === null ? 1 : 0)) };
  }
  if (v.name === "word" || v.name === "uniq") {
    return { kind: "string", values: xs.map((x) => x ?? ""), missing: Uint8Array.from(xs, (x) => (x === null ? 1 : 0)) };
  }
  if (v.name === "blob") return { kind: "string", values: xs.map((x) => x ?? new Uint8Array(0)), missing: Uint8Array.from(xs, (x) => (x === null ? 1 : 0)) };
  if (v.name === "region") {
    return { kind: "dictionary", codes: Uint32Array.from(xs, (x) => x ?? 0), values: [...v.levels], missing: Uint8Array.from(xs, (x) => (x === null ? 1 : 0)) };
  }
  return {
    kind: "number",
    values: Float64Array.from(xs, (x) => (typeof x === "number" ? x : NaN)),
    missing: Uint8Array.from(xs, code),
  };
}

test("constructed data round trips: labels, .a to .z, dates, timestamps, categories, bigints, nulls", () => {
  const data = constructed(5000);
  const bytes = writeParquet(data, { rowGroupSize: 1500 });
  const r = openParquet(bytes);
  assert.equal(r.info.rowGroups.length, 4);
  assert.equal(r.info.label, data.label);
  assert.deepEqual(r.info.notes, data.notes);
  assert.deepEqual(r.info.sortedBy, ["id"]);
  assert.deepEqual(r.characteristics(), data.characteristics);
  assert.deepEqual(r.valueLabels("agelbl"), data.valueLabels.agelbl);
  const byName = Object.fromEntries(r.variables.map((v) => [v.name, v]));
  assert.equal(byName.age.type, "byte");
  assert.equal(byName.age.storage, "byte");
  assert.equal(byName.age.label, "Age in years");
  assert.equal(byName.age.valueLabels, "agelbl");
  assert.equal(byName.f.type, "float");
  assert.equal(byName.day.type, "date");
  assert.equal(byName.day.unit, "day");
  assert.equal(byName.day.format, "%tdCCYY-NN-DD");
  assert.equal(byName.dayx.type, "date");
  assert.equal(byName.when.timeZone, "America/New_York");
  assert.equal(byName.when.unit, "us");
  assert.equal(byName.when.columnKind, "number");
  assert.equal(byName.local.timeZone, undefined);
  assert.equal(byName.local.columnKind, "bigint");
  assert.equal(byName.secs.unit, "s");
  assert.equal(byName.secs.timeZone, "Asia/Tokyo");
  assert.equal(byName.n64.columnKind, "bigint");
  assert.match(byName.n64.int64.reason, /beyond the safe integers/);
  assert.equal(byName.small64.columnKind, "number");
  assert.equal(byName.region.columnKind, "dictionary");
  assert.deepEqual(byName.region.categorical, { levels: ["North", "South", "West", "Unused"], ordered: true });
  assert.equal(byName.blob.type, "binary");
  for (const [from, to] of [[0, 5000], [0, 1], [1499, 1502], [2000, 2700], [4999, 5000], [3000, 3000]]) {
    const got = r.readColumns(r.variables.map((_, i) => i), { start: from, count: to - from });
    data.variables.forEach((v, k) => assert.deepEqual(got[k], expectedColumn(v, from, to), `${v.name} rows ${from} to ${to}`));
  }
  // Writing what was read gives the same file contents again.
  const cols = r.readColumns(r.variables.map((_, i) => i));
  const again = openParquet(writeParquet({ ...data, variables: r.variables.map((v, k) => ({ ...v, values: cols[k] })) }));
  assert.deepEqual(again.readColumns(again.variables.map((_, i) => i)), cols);
  assert.deepEqual(again.variables.map((v) => [v.name, v.type, v.unit, v.timeZone, v.format, v.label]), r.variables.map((v) => [v.name, v.type, v.unit, v.timeZone, v.format, v.label]));
  // toDate
  assert.equal(toDate(19000, byName.day).toISOString(), "2022-01-08T00:00:00.000Z");
  assert.equal(toDate(1_700_000_000_000_000, byName.when).toISOString(), "2023-11-14T22:13:20.000Z");
  assert.equal(toDate(1_700_000_000_000_000_123n, byName.local).toISOString(), "2023-11-14T22:13:20.000Z");
  assert.equal(toDate(-1n, byName.local).toISOString(), "1969-12-31T23:59:59.999Z");
  assert.equal(toDate(0, { format: "%td" }).toISOString(), "1960-01-01T00:00:00.000Z");
  assert.equal(toDate(1e300, byName.day), null);
  assert.equal(toDate(5, { format: "%9.0g" }), null);
  // Cells
  const [row] = r.readRows(3, 1, ["age", "word", "region", "n64"]);
  assert.deepEqual(row, [MISSING[".d"], "délta", "North", 3n * 3n ** 30n - 2n ** 62n]);
  assert.deepEqual(r.readRows(0, 1, ["word", "region"])[0], [MISSING["."], MISSING["."]]);
});

test("missingLetters: false writes .a to .z as nulls and keeps each column's type", () => {
  const data = constructed(300);
  const r = openParquet(writeParquet(data, { missingLetters: false }));
  const age = r.variables.find((v) => v.name === "age");
  assert.equal(age.physicalType, "INT32");
  assert.equal(age.storage, undefined);
  const [c] = r.readColumns(["age"]);
  assert.ok(c.missing.every((m) => m <= 1));
  assert.ok(c.missing.includes(1));
});

test("strings: dictionary gives DictionaryColumns for repeating text", () => {
  const r = openParquet(writeParquet(constructed(3000), { rowGroupSize: 1000 }));
  const [word, uniq] = r.readColumns(["word", "uniq"], { strings: "dictionary" });
  assert.equal(word.kind, "dictionary");
  const plain = r.readColumns(["word", "uniq"]);
  for (let i = 0; i < 3000; i++) {
    assert.equal(word.missing[i] ? "" : word.values[word.codes[i]], plain[0].values[i]);
    assert.equal(uniq.kind === "dictionary" ? uniq.values[uniq.codes[i]] : uniq.values[i], plain[1].values[i]);
  }
});

test("zstd is libzstd: its levels change the file, and every level reads back", () => {
  const rows = 50_000;
  const data = { variables: [{ name: "x", values: Array.from({ length: rows }, (_, i) => `value ${i % 5000} of a text column`) }, { name: "y", values: Array.from({ length: rows }, (_, i) => (i * 7919) % 100_003) }] };
  const sizes = [1, 3, 19].map((compressionLevel) => {
    const bytes = writeParquet(data, { compression: "zstd", compressionLevel });
    const r = openParquet(bytes);
    assert.deepEqual(r.info.compression, ["zstd"]);
    const [x, y] = r.readColumns(["x", "y"]);
    assert.equal(x.values[4321], data.variables[0].values[4321]);
    assert.equal(y.values[rows - 1], data.variables[1].values[rows - 1]);
    return r.variables[0].chunks[0].compressedBytes;
  });
  // Data-dependent in general; on this column's text, level 19 finds
  // more than level 1 does.
  assert.ok(sizes[2] < sizes[0], `level 19 (${sizes[2]} bytes) should be smaller than level 1 (${sizes[0]})`);
});

test("text is written exactly: short and long, ASCII and not, in blocks of rows", () => {
  // Long strings are encoded a block of 65,536 rows at a time; a block
  // with non-ASCII text, a lone surrogate or a missing value takes the
  // slower route. Short strings always do.
  const rows = 200_000;
  const odd = (i) => (i === 70_000 ? "naïve résumé café, encore une fois" : i === 140_001 ? "lone \ud800 surrogate here" : i === 199_999 ? "😀 emoji at the end of it all" : null);
  const long = Array.from({ length: rows }, (_, i) => odd(i) ?? (i % 997 === 5 ? null : `row ${i} of a longer text value`));
  const short = Array.from({ length: rows }, (_, i) => (i === 3 ? "é" : `s${i % 50}`));
  const r = openParquet(writeParquet({ variables: [{ name: "long", values: long }, { name: "short", values: short }] }));
  const [a, b] = r.readColumns(["long", "short"]);
  for (let i = 0; i < rows; i++) {
    const want = long[i] === null ? "" : long[i].replace("\ud800", "�");
    if (a.values[i] !== want || Boolean(a.missing[i]) !== (long[i] === null)) assert.fail(`long row ${i}: ${a.values[i]}`);
    if (b.values[i] !== short[i]) assert.fail(`short row ${i}: ${b.values[i]}`);
  }
});

for (const { stem, doc, bytes } of parquetFixtures()) {
  test(`${stem}.parquet reads as pyarrow reads it`, () => {
    const r = openParquet(bytes, doc.nested ? { nested: "skip" } : {});
    assert.equal(r.info.nobs, doc.rows);
    assert.deepEqual(r.info.warnings, []);
    assert.equal(r.variables.length, doc.columns.length);
    for (const [start, count] of [[0, doc.rows], [0, 1], [250, 100], [doc.rows - 1, 1], [123, 300]]) {
      if (start + count <= doc.rows) checkFixture(r, stem, doc, start, count);
    }
    if (doc.nested) {
      const all = openParquet(bytes);
      assert.deepEqual(all.variables.filter((v) => v.role === "nested").map((v) => v.name), doc.nested);
      assert.throws(() => all.readRows(0, 1), /nested columns, which are not read: .*nested: "skip"/);
      assert.throws(() => all.readColumns([doc.nested[0]]), (e) => e.code === "DTA_INVALID");
      assert.equal(all.readColumns([doc.columns[0].name])[0].values.length, doc.rows);
    }
  });
}

/** A file of three double columns of `n` rows, in row groups of `group`. */
function doubles(n, group) {
  const col = (k) => Float64Array.from({ length: n }, (_, i) => Math.sin(i * (k + 1)) * 1e6);
  return writeParquet({ variables: [0, 1, 2].map((k) => ({ name: `x${k}`, values: col(k) })) }, { rowGroupSize: group, compression: "none" });
}

test("windows across pages and row groups, and readRowsAt in caller order with repeats", () => {
  const n = 400_000;
  const bytes = doubles(n, 150_000);
  const r = openParquet(bytes);
  assert.equal(r.info.rowGroups.length, 3);
  // Uncompressed doubles: 1.2 MB a row group, so pages of about 1 MiB.
  const whole = r.readColumns([0, 1, 2]);
  for (const [s, c] of [[0, n], [131_000, 2_000], [149_990, 20], [299_999, 2], [1, n - 2], [n - 1, 1]]) {
    const got = r.readColumns(["x1", "x2"], { start: s, count: c });
    assert.deepEqual(got[0].values, whole[1].values.subarray(s, s + c));
    assert.deepEqual(got[1].values, whole[2].values.subarray(s, s + c));
  }
  let seed = 7;
  const rows = [n - 1, 0, 0, 150_000, 149_999, 5, 5, ...Array.from({ length: 300 }, () => (seed = (seed * 1103515245 + 12345) % 2 ** 31) % n)];
  const got = r.readRowsAt(rows, ["x2", "x0"]);
  rows.forEach((row, j) => assert.deepEqual(got[j], [whole[2].values[row], whole[0].values[row]], `row ${row}`));
  assert.deepEqual(r.readRowsAt([]), []);
  for (const bad of [-1, n, 1.5, NaN]) assert.throws(() => r.readRowsAt([0, bad]), (e) => e instanceof RangeError && e.code === "DTA_OUT_OF_RANGE");
  assert.throws(() => r.readColumns(["nope"]), (e) => e.code === "DTA_OUT_OF_RANGE" && /the file's are "x0", "x1", "x2"/.test(e.message));
  assert.throws(() => r.readColumns([0], { start: n, count: 1 }), (e) => e.code === "DTA_OUT_OF_RANGE");
});

test("a one-column read touches only that column's byte ranges", () => {
  const n = 300_000;
  const bytes = doubles(n, n);
  const reads = [];
  const r = new ParquetReader(
    (into, offset) => {
      reads.push([offset, offset + into.length]);
      into.set(bytes.subarray(offset, offset + into.length));
    },
    bytes.length,
  );
  const footer = bytes.length - 8 - r.info.footerBytes;
  const planned = r.planRanges(["x1"], 0, n);
  reads.length = 0;
  r.readColumns(["x1"]);
  const inside = ([a, b]) => a >= footer || planned.some(([p, q]) => a >= p && b <= q);
  assert.ok(reads.length > 0);
  for (const range of reads) assert.ok(inside(range), `read ${range} outside column x1's chunk`);
  const touched = reads.reduce((s, [a, b]) => s + (a >= footer ? 0 : b - a), 0);
  assert.ok(touched < bytes.length / 2.5, `${touched} of ${bytes.length}`);
  // A window reads only the pages that hold it.
  reads.length = 0;
  r.readColumns(["x1"], { start: 200_000, count: 100 });
  const window = reads.reduce((s, [a, b]) => s + b - a, 0);
  assert.ok(window < 1.2 * 2 ** 20, `${window}`);
});

test("the async reader gives the same results and fetches only what it needs", async () => {
  const data = constructed(4000);
  const bytes = writeParquet(data, { rowGroupSize: 1000 });
  let fetched = 0;
  const readAt = async (offset, length) => {
    fetched += length;
    await new Promise((resolve) => setImmediate(resolve));
    return bytes.slice(offset, offset + length);
  };
  const a = await openParquetAsync(readAt, bytes.length);
  const s = openParquet(bytes);
  assert.deepEqual(a.info, s.info);
  assert.deepEqual(a.variables, s.variables);
  assert.deepEqual(await a.readColumns([0, 5, 14, 17], { start: 900, count: 1300 }), s.readColumns([0, 5, 14, 17], { start: 900, count: 1300 }));
  assert.deepEqual(await a.readRows(10, 20), s.readRows(10, 20));
  assert.deepEqual(await a.readRowsAt([3999, 2, 2, 1500]), s.readRowsAt([3999, 2, 2, 1500]));
  assert.deepEqual(a.valueLabels("agelbl"), s.valueLabels("agelbl"));
  assert.deepEqual(await Promise.all([a.readRows(0, 5, ["word"]), a.readRows(3000, 5, ["uniq"])]), [s.readRows(0, 5, ["word"]), s.readRows(3000, 5, ["uniq"])]);
  await assert.rejects(a.readColumns(["nope"]), (e) => e.code === "DTA_OUT_OF_RANGE");
  // Fetching a large file's window reads little of it.
  const big = doubles(400_000, 400_000);
  fetched = 0;
  const b = await openParquetAsync(async (o, l) => {
    fetched += l;
    return big.slice(o, o + l);
  }, big.length);
  const [w] = await b.readColumns(["x2"], { start: 333_333, count: 10 });
  assert.deepEqual(w, openParquet(big).readColumns(["x2"], { start: 333_333, count: 10 })[0]);
  assert.ok(fetched < big.length / 4, `${fetched} of ${big.length}`);
  a.close();
  await assert.rejects(a.readRows(0, 1), (e) => e.code === "DTA_CLOSED");
  await assert.rejects(openParquetAsync(async () => new Uint8Array(3), 3), (e) => e.code === "DTA_CORRUPT" || e.code === "DTA_IO" || /Parquet/.test(e.message));
});

test("scans in small batches decompress each page once", () => {
  const n = 300_000;
  const col = Float64Array.from({ length: n }, (_, i) => (i * 7919) % 1000);
  const bytes = writeParquet({ variables: [{ name: "x", values: col }] });
  const r = openParquet(bytes);
  for (let s = 0; s < n; s += 1000) {
    const [c] = r.readColumns([0], { start: s, count: Math.min(1000, n - s) });
    assert.equal(c.values[0], col[s]);
  }
  const [held, hits, misses] = r.cacheStats();
  assert.ok(held > 0 && held <= 8 * 2 ** 20);
  assert.ok(hits > 10 * misses, `${hits} hits, ${misses} misses`);
  const none = openParquet(bytes, { pageCacheBytes: 0 });
  none.readColumns([0], { start: 5, count: 5 });
  assert.deepEqual(none.cacheStats(), [0, 0, 0]);
});

test("openParquetFile reads by path and by a descriptor the caller keeps; writeParquetFile writes", () => {
  const dir = mkdtempSync(join(tmpdir(), "dta-pq-"));
  try {
    const path = join(dir, "c.parquet");
    const data = constructed(2000);
    writeParquetFile(path, data, { compression: "gzip" });
    using r = openParquetFile(path);
    assert.deepEqual(r.info.compression, ["gzip"]);
    const s = openParquet(readFileSync(path));
    assert.deepEqual(r.readColumns(r.variables.map((_, i) => i)), s.readColumns(s.variables.map((_, i) => i)));
    const fd = openSync(path, "r");
    const f = openParquetFile(fd);
    f.close();
    // The descriptor is still the caller's.
    const g = openParquetFile(fd);
    assert.equal(g.info.nobs, 2000);
    g.close();
    closeSync(fd);
    assert.throws(() => writeParquetFile(join(dir, "bad.parquet"), { variables: [{ name: "b", type: "byte", values: [1000] }] }), /row 0 holds 1000, which a byte column cannot hold/);
    assert.throws(() => readFileSync(join(dir, "bad.parquet")), /ENOENT/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("errors name what is wrong", () => {
  assert.throws(() => openParquet(new Uint8Array(20)), (e) => /not a Parquet file/.test(e.message));
  assert.throws(() => openParquet(writeDta({ variables: [{ name: "x", values: [1] }] })), /not a Parquet file/);
  assert.throws(() => writeParquet({ variables: [{ name: "x", values: [1] }] }, { compression: "lzo" }), /unknown compression "lzo"/);
  assert.throws(() => writeParquet({ variables: [{ name: "x", values: [1, 2] }, { name: "y", values: [1] }] }), /y has 1 values, not 2/);
  assert.throws(() => writeParquet({ variables: [{ name: "x", type: "float", values: [0.1] }] }), /a float column does not hold exactly/);
  assert.throws(() => writeParquet({ variables: [{ name: "x", type: "categorical", levels: ["a"], values: [1] }] }), /not a level code/);
  assert.throws(() => writeDta({ variables: [{ name: "x", values: [1n] }] }), /cannot hold 64-bit integers; use writeParquet/);
  // int64: "number" on values beyond the safe integers.
  const big = writeParquet({ variables: [{ name: "n", values: [1n, 2n ** 60n + 1n] }] });
  assert.throws(() => openParquet(big, { int64: "number" }).readColumns(["n"]), /int64: "bigint"/);
  assert.equal(openParquet(big, { int64: "bigint" }).readColumns(["n"])[0].kind, "bigint");
  const small = writeParquet({ variables: [{ name: "n", values: [1n, 2n] }] });
  assert.equal(openParquet(small, { int64: "bigint" }).readColumns(["n"])[0].kind, "bigint");
  assert.equal(openParquet(small).readColumns(["n"])[0].kind, "number");
  assert.throws(() => openParquet(small, { int64: "maybe" }), /int64 must be/);
  assert.throws(() => openParquet(small).readColumns(["n"], { maxStringBytes: 4 }), /maxStringBytes is for .dta files/);
});

test("an empty table and a table with no columns", () => {
  const r = openParquet(writeParquet({ variables: [{ name: "x", values: [] }, { name: "s", type: "string", values: [] }] }));
  assert.equal(r.info.nobs, 0);
  assert.deepEqual(r.readRows(0, 0), []);
  assert.deepEqual(r.readColumns([0, 1]).map((c) => c.kind), ["number", "string"]);
  const none = openParquet(writeParquet({ variables: [] }));
  assert.equal(none.variables.length, 0);
});
