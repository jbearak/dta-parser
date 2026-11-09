// readDataset and readDatasetAsync (plan 0021): a whole table from any
// TableReader, metadata included, equal to what the reader's own calls
// give; readParquet and readDta, and round trips through saveParquet and
// saveDta.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const dk = require("../dist/index.js");
const node = require("../dist/node.js");
const dp = require("@jbearak/dta-parser");
const { readDataset, readDatasetAsync, openParquet, openParquetAsync, writeParquet, MISSING } = dk;

/**
 * A column as cells, so two that hold the same values compare equal
 * whatever their representation: a string column with or without
 * `missing`, a 64-bit column read as numbers or as bigints.
 */
function cells(c) {
  const n = c.kind === "dictionary" ? c.codes.length : c.values.length;
  return Array.from({ length: n }, (_, i) => {
    if (c.missing?.[i]) return { missing: c.missing[i] };
    if (c.kind === "dictionary") return c.values[c.codes[i]];
    const x = c.values[i];
    return typeof x === "bigint" ? Number(x) : x;
  });
}

const compat = new URL("../../../compat/", import.meta.url);
const dtaFixtures = readdirSync(new URL("fixtures/", compat)).filter((f) => f.endsWith(".dta"));
const pqFixtures = readdirSync(new URL("parquet/fixtures/", compat)).filter((f) => f.endsWith(".parquet"));

/** What readDataset should give, from the reader's own calls. */
function expected(r, ks) {
  const columns = ks.length ? r.readColumns(ks) : [];
  const valueLabels = {};
  for (const n of r.valueLabelNames()) valueLabels[n] = r.valueLabels(n);
  return { columns, valueLabels, notes: r.notes(), characteristics: r.characteristics(), label: r.info.label, sortedBy: r.info.sortedBy };
}

function same(ds, want, r, ks) {
  assert.equal(ds.variables.length, ks.length);
  ds.variables.forEach((v, j) => {
    const src = r.variables[ks[j]];
    assert.equal(v.name, src.name);
    assert.equal(v.type, src.type);
    assert.equal(v.format, src.format);
    assert.equal(v.label, src.label);
    assert.equal(v.valueLabels, src.valueLabels);
    assert.deepEqual(v.values, want.columns[j], v.name);
  });
  assert.deepEqual(ds.valueLabels, want.valueLabels);
  assert.deepEqual(ds.notes, want.notes);
  assert.deepEqual(ds.characteristics, want.characteristics);
  assert.equal(ds.label, want.label);
  assert.deepEqual(ds.sortedBy, want.sortedBy);
}

for (const name of dtaFixtures) {
  test(`readDataset of ${name} is what DtaReader gives`, () => {
    const r = dp.openDta(readFileSync(new URL(`fixtures/${name}`, compat)));
    const ks = r.variables.map((_, i) => i);
    const ds = readDataset(r);
    same(ds, expected(r, ks), r, ks);
    assert.equal(ds.timestamp, r.info.timestamp);
    r.close();
  });
}

for (const name of pqFixtures) {
  test(`readDataset of ${name} is what ParquetReader gives`, async () => {
    const bytes = readFileSync(new URL(`parquet/fixtures/${name}`, compat));
    const r = openParquet(bytes, { nested: "skip" });
    const ks = r.variables.flatMap((v, i) => (v.columnKind === null ? [] : [i]));
    const ds = readDataset(r, { columns: ks });
    same(ds, expected(r, ks), r, ks);
    assert.equal(ds.timestamp, undefined);
    ds.variables.forEach((v, j) => {
      const src = r.variables[ks[j]];
      assert.equal(v.unit, src.unit);
      assert.equal(v.timeZone, src.timeZone);
      assert.deepEqual(v.categorical, src.categorical);
    });
    const a = await openParquetAsync(async (offset, length) => bytes.subarray(offset, offset + length), bytes.length, { nested: "skip" });
    assert.deepEqual(await readDatasetAsync(a, { columns: ks }), ds);
    a.close();
    r.close();
  });
}

test("a dataset keeps every value label set, used or not, and a window of rows", () => {
  const bytes = dp.writeDta({
    label: "L",
    notes: ["n1"],
    valueLabels: { used: new Map([[1, "one"]]), unused: new Map([[MISSING[".a"], "A"]]) },
    variables: [{ name: "x", type: "byte", valueLabels: "used", values: [1, 2, MISSING[".a"]] }, { name: "s", values: ["a", "b", "c"] }],
  });
  const r = dp.openDta(bytes);
  const ds = readDataset(r, { columns: ["s", 0], start: 1, count: 2 });
  assert.deepEqual(Object.keys(ds.valueLabels).sort(), ["unused", "used"]);
  assert.equal(ds.valueLabels.unused.get(MISSING[".a"]), "A");
  assert.deepEqual(ds.variables.map((v) => v.name), ["s", "x"]);
  assert.deepEqual(ds.variables[0].values.values, ["b", "c"]);
  assert.deepEqual(Array.from(ds.variables[1].values.missing), [0, 2]);
  assert.deepEqual(ds.notes, ["n1"]);
  assert.throws(() => readDataset(r, { columns: ["nope"] }), /no variable "nope"/);
  r.close();
});

test("readDataset takes any TableReader, not only the package's", () => {
  const custom = {
    info: { format: "parquet", nobs: 2, label: "custom", sortedBy: ["k"] },
    variables: [{ name: "k", type: "long", format: "%12.0g", label: "", valueLabels: "s" }],
    readColumns: () => [{ kind: "number", values: Float64Array.of(1, 2), missing: Uint8Array.of(0, 0) }],
    readRows: () => [],
    readRowsAt: () => [],
    valueLabels: (n) => (n === "s" ? new Map([[1, "a"]]) : undefined),
    valueLabelNames: () => ["s"],
    characteristics: () => [{ variable: "_dta", name: "x", value: "y" }],
    notes: () => ["note"],
    close() {},
    [Symbol.dispose]() {},
  };
  const ds = readDataset(custom);
  assert.equal(ds.label, "custom");
  assert.deepEqual(ds.sortedBy, ["k"]);
  assert.deepEqual(ds.notes, ["note"]);
  assert.deepEqual(ds.characteristics, [{ variable: "_dta", name: "x", value: "y" }]);
  assert.deepEqual([...ds.valueLabels.s], [[1, "a"]]);
  assert.deepEqual(Array.from(ds.variables[0].values.values), [1, 2]);
});

test("readParquet, saveParquet, readDta and saveDta round trip", () => {
  const dir = mkdtempSync(join(tmpdir(), "datakit-rt-"));
  try {
    for (const name of dtaFixtures) {
      const f = new URL(`fixtures/${name}`, compat);
      const ds = node.readDta(f.pathname);
      const out = join(dir, `${name}.dta`);
      node.saveDta(ds, out);
      const back = node.readDta(out);
      assert.deepEqual(back.variables.map((v) => [v.name, v.values]), ds.variables.map((v) => [v.name, v.values]), name);
      assert.deepEqual(back.valueLabels, ds.valueLabels, name);
      assert.deepEqual(back.notes, ds.notes, name);
      const pq = join(dir, `${name}.parquet`);
      node.saveParquet(ds, pq);
      const viaPq = node.readParquet(pq);
      // strN and strL come back from Parquet as "string".
      const type = (t) => (/^str([0-9]+|L)$/.test(t) ? "string" : t);
      assert.deepEqual(viaPq.variables.map((v) => [v.name, v.type, cells(v.values)]), ds.variables.map((v) => [v.name, type(v.type), cells(v.values)]), name);
      assert.deepEqual(viaPq.valueLabels, ds.valueLabels, name);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("saveParquet of what readParquet read gives the same dataset, for every fixture the writer can write", () => {
  const dir = mkdtempSync(join(tmpdir(), "datakit-pq-"));
  // What the writer cannot write back, as Python's round-trip test lists
  // it: TIME and DECIMAL, and unsigned 64-bit values past 2^63 - 1 (the
  // writer's INT64 is signed).
  const cannot = (v) => v.type === "time" || v.type === "decimal" || v.type === "uint64";
  try {
    for (const name of pqFixtures) {
      const r = openParquet(readFileSync(new URL(`parquet/fixtures/${name}`, compat)), { nested: "skip" });
      const ks = r.variables.flatMap((v, i) => (v.columnKind === null || cannot(v) ? [] : [i]));
      const ds = readDataset(r, { columns: ks });
      r.close();
      const out = join(dir, name);
      try {
        node.saveParquet(ds, out);
      } catch (e) {
        assert.fail(`${name}: ${e.message}`);
      }
      const back = node.readParquet(out);
      // The writer stores uint8 to uint32 in the next wider signed type
      // (as 1.1 did), so their type comes back widened.
      const widened = { uint8: "int", uint16: "long", uint32: "int64" };
      assert.deepEqual(
        back.variables.map((v) => [v.name, v.type, cells(v.values)]),
        ds.variables.map((v) => [v.name, widened[v.type] ?? v.type, cells(v.values)]),
        name,
      );
      assert.deepEqual(back.valueLabels, ds.valueLabels, name);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("readParquetInfo reads the footer, every label set and the characteristics, no data", () => {
  const dir = mkdtempSync(join(tmpdir(), "datakit-info-"));
  try {
    const f = join(dir, "a.parquet");
    node.saveParquet(
      {
        notes: ["n"],
        valueLabels: { a: new Map([[1, "x"]]), b: new Map([[2, "y"]]) },
        characteristics: [{ variable: "x", name: "c", value: "v" }],
        variables: [{ name: "x", valueLabels: "a", values: [1, 2] }],
      },
      f,
    );
    const info = node.readParquetInfo(f);
    assert.equal(info.info.nobs, 2);
    assert.deepEqual(info.info.notes, ["n"]);
    assert.deepEqual(Object.keys(info.valueLabels).sort(), ["a", "b"]);
    assert.deepEqual(info.characteristics, [{ variable: "x", name: "c", value: "v" }]);
    assert.equal(info.variables[0].name, "x");
    assert.equal(info.variables[0].chunks.length, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a categorical built with a letter is an error in writeParquet, not a silent null", () => {
  assert.throws(
    () => writeParquet({ variables: [{ name: "g", type: "categorical", levels: ["a", "b"], values: [0, MISSING[".a"]] }] }),
    /g: row 1 holds \.a; a categorical cannot hold \.a to \.z, so make it labelled numbers/,
  );
});
