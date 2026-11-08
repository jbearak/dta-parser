// saveDta's conversions (plan 0021, "saveDta") and plan 0020's factors
// through readDta and readDataset.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const dk = require("../dist/index.js");
const node = require("../dist/node.js");
const dp = { ...require("@jbearak/dta-parser"), ...require("@jbearak/dta-parser/node") };
const { MISSING, readDataset, writeParquet, openParquet } = dk;

const dir = mkdtempSync(join(tmpdir(), "datakit-save-"));
process.on("exit", () => rmSync(dir, { recursive: true, force: true }));
let n = 0;

/** Save `data` as .dta and read it back with dta-parser. */
function roundTrip(data, options) {
  const f = join(dir, `${n++}.dta`);
  node.saveDta(data, f, options);
  const r = dp.openDtaFile(f);
  const cols = r.readColumns(r.variables.map((_, i) => i));
  const out = { variables: r.variables, cols, chars: r.characteristics(), labels: Object.fromEntries(r.valueLabelNames().map((s) => [s, r.valueLabels(s)])) };
  r.close();
  return { ...out, file: f };
}
const one = (v, options) => roundTrip({ variables: [v] }, options);

test("integer and untyped number columns take the smallest type that holds them", () => {
  const cases = [
    [{ name: "a", values: [1, 100, -127] }, "byte"],
    [{ name: "a", values: [1, 101] }, "int"],
    [{ name: "a", values: [-32767, 32740] }, "int"],
    [{ name: "a", values: [32741] }, "long"],
    [{ name: "a", values: [2147483620] }, "long"],
    [{ name: "a", values: [2147483621] }, "double"],
    [{ name: "a", values: [1, 1.5] }, "double"],
    [{ name: "a", type: "bool", values: [0, 1, null] }, "byte"],
    [{ name: "a", type: "uint8", values: [0, 255] }, "int"],
    [{ name: "a", type: "uint16", values: [0, 65535] }, "long"],
    [{ name: "a", type: "uint32", values: [0, 4294967295] }, "double"],
    [{ name: "a", type: "int64", values: [1n, null, -5n] }, "byte"],
    [{ name: "a", type: "int64", values: [2n ** 53n] }, "double"],
  ];
  for (const [v, want] of cases) {
    const { variables, cols } = one(v);
    assert.equal(variables[0].type, want, JSON.stringify(v, (_, x) => (typeof x === "bigint" ? `${x}n` : x)));
    const src = v.values.map((x) => (x === null ? null : Number(x)));
    assert.deepEqual(Array.from(cols[0].values, (x, i) => (cols[0].missing[i] ? null : x)), src);
  }
  assert.throws(() => one({ name: "big", type: "int64", values: [2n ** 53n + 1n] }), /big: row 0 holds 9007199254740993, past ±2\^53/);
  assert.throws(
    () => one({ name: "big", type: "int64", values: { kind: "bigint", values: BigInt64Array.of(1n, -(2n ** 60n)), missing: Uint8Array.of(0, 0) } }),
    /big: row 1 holds -1152921504606846976, past ±2\^53/,
  );
  // Letters stay letters.
  const { cols } = one({ name: "x", type: "int64", values: { kind: "number", values: Float64Array.of(1, NaN), missing: Uint8Array.of(0, 2) } });
  assert.deepEqual(Array.from(cols[0].missing), [0, 2]);
});

test("Parquet strings become strN or strL; a null string is an error", () => {
  const long = "x".repeat(3000);
  const { variables, cols } = roundTrip({
    variables: [
      { name: "s", type: "string", values: { kind: "string", values: ["a", "bc"], missing: Uint8Array.of(0, 0) } },
      { name: "l", type: "string", values: ["a", long] },
      { name: "b", type: "binary", values: [Uint8Array.of(1, 2), Uint8Array.of(3)] },
    ],
  });
  assert.equal(variables[0].type, "str2");
  assert.equal(variables[1].type, "strL");
  assert.equal(variables[2].type, "strL");
  assert.deepEqual(cols[1].values, ["a", long]);
  assert.deepEqual(cols[2].values, [Uint8Array.of(1, 2), Uint8Array.of(3)]);
  assert.throws(() => one({ name: "s", type: "string", values: ["a", null] }), /s: row 1 is a missing string, which a \.dta file cannot hold; fill it/);
  assert.throws(
    () => one({ name: "b", type: "binary", values: { kind: "string", values: [Uint8Array.of(1), new Uint8Array(0)], missing: Uint8Array.of(0, 1) } }),
    /b: row 1 is a missing string/,
  );
  assert.throws(() => one({ name: "s", type: "str5", values: [Uint8Array.of(1)] }), /s: binary values need type "strL" or "binary"/);
});

test("dates become %td, counted from 1960, exactly", () => {
  const { variables, cols } = one({ name: "d", type: "date", values: [0, -3653, 1, null, MISSING[".b"]] });
  assert.equal(variables[0].type, "long");
  assert.equal(variables[0].format, "%td");
  assert.deepEqual(Array.from(cols[0].values.slice(0, 3)), [3653, 0, 3654]);
  assert.deepEqual(Array.from(cols[0].missing), [0, 0, 0, 1, 3]);
  assert.throws(() => one({ name: "d", type: "date", values: [0.5] }), /d: row 0 holds 0\.5, a fraction of a day; pass timestamps: "truncate"/);
  const t = one({ name: "d", type: "date", values: [0.5, -0.5, -1.25] }, { timestamps: "truncate" });
  assert.deepEqual(Array.from(t.cols[0].values), [3653, 3652, 3651]);
  assert.throws(() => one({ name: "d", type: "date", values: [Infinity] }), /d: row 0 holds Infinity/);
  assert.throws(() => one({ name: "d", type: "date", values: { kind: "number", values: Float64Array.of(NaN), missing: Uint8Array.of(0) } }), /d: row 0 holds NaN, which is not a missing value/);
  assert.throws(() => one({ name: "d", type: "date", values: [2147483620] }), /d: row 0 is past what a long %td holds/);
});

test("timestamps become %tc, milliseconds since 1960, in each unit, exactly", () => {
  const ms1960 = 315619200000;
  const at = (unit, values, options) => Array.from(one({ name: "t", type: "timestamp", unit, values }, options).cols[0].values);
  assert.deepEqual(at("s", [0, 1, -1]), [ms1960, ms1960 + 1000, ms1960 - 1000]);
  assert.deepEqual(at("ms", [5, -ms1960]), [ms1960 + 5, 0]);
  assert.deepEqual(at("us", [5000, -5000]), [ms1960 + 5, ms1960 - 5]);
  assert.deepEqual(at("ns", [5_000_000]), [ms1960 + 5]);
  assert.deepEqual(at("us", { kind: "bigint", values: BigInt64Array.of(-1_500n, 2_000n), missing: Uint8Array.of(0, 0) }, { timestamps: "truncate" }), [ms1960 - 2, ms1960 + 2]);
  // A fractional count: 1.5 s is 1500 ms exactly; 0.0005 s is not whole.
  assert.deepEqual(at("s", [1.5]), [ms1960 + 1500]);
  assert.throws(() => at("s", [0.0005]), /t: row 0 holds 0\.0005, a fraction of a millisecond/);
  assert.deepEqual(at("s", [-0.0005], { timestamps: "truncate" }), [ms1960 - 1]);
  assert.throws(() => at("us", [1]), /a fraction of a millisecond/);
  assert.throws(() => at("ms", [2 ** 53]), /t: row 0 is past what a double %tc holds/);
  assert.throws(() => at("ns", [Infinity]), /row 0 holds Infinity/);
  const { variables } = one({ name: "t", type: "timestamp", unit: "ms", values: [1, null] });
  assert.equal(variables[0].format, "%tc");
  assert.throws(() => one({ name: "t", type: "timestamp", unit: "ms", timeZone: "UTC", values: [1] }), /t: a \.dta file has no time zones/);
  assert.throws(() => one({ name: "t", type: "timestamp", unit: "h", values: [1] }), /unknown unit "h"/);
});

test("decimal, time and unknown types", () => {
  const { variables } = one({ name: "x", type: "decimal", values: { kind: "number", values: Float64Array.of(1.25), missing: Uint8Array.of(0) } });
  assert.equal(variables[0].type, "double");
  assert.throws(() => one({ name: "x", type: "decimal", values: { kind: "string", values: ["123456789012345678.5"] } }), /x: this decimal was read as text .* set type: "string"/);
  assert.throws(() => one({ name: "x", type: "time", values: [1] }), /x: a \.dta file has no time of day type/);
  assert.throws(() => one({ name: "x", type: "interval", values: [1] }), /x: a \.dta file cannot hold type "interval"/);
  assert.throws(() => node.saveDta({ variables: [] }, join(dir, "x.dta"), { timestamps: "round" }), /timestamps must be "error" or "truncate"/);
});

test("categoricals become labelled codes with plan 0020's marker", () => {
  const dict = { kind: "dictionary", codes: Uint32Array.of(1, 0, 0), values: ["low", "high", "unused"], missing: Uint8Array.of(0, 0, 1) };
  const { variables, cols, chars, labels } = roundTrip({
    valueLabels: { g: new Map([[9, "something else"]]) },
    variables: [
      { name: "g", type: "categorical", categorical: { levels: ["low", "high", "unused"], ordered: true }, values: dict },
      { name: "h", type: "categorical", levels: ["a", "b"], values: [1, null, 0] },
    ],
  });
  assert.equal(variables[0].type, "long");
  // A set "g" that differs is kept; the new one is g_2.
  assert.equal(variables[0].valueLabels, "g_2");
  assert.deepEqual([...labels.g_2], [[1, "low"], [2, "high"], [3, "unused"]]);
  assert.deepEqual([...labels.g], [[9, "something else"]]);
  assert.deepEqual(Array.from(cols[0].values.slice(0, 2)), [2, 1]);
  assert.deepEqual(Array.from(cols[0].missing), [0, 0, 1]);
  assert.deepEqual(chars, [
    { variable: "g", name: "dtaparser_factor", value: "ordered g_2" },
    { variable: "h", name: "dtaparser_factor", value: "unordered h" },
  ]);
  assert.throws(
    () => one({ name: "c", type: "categorical", levels: ["a"], values: [0, MISSING[".a"]] }),
    /c: row 1 holds \.a; a categorical cannot hold \.a to \.z, so make it labelled numbers/,
  );
  assert.throws(() => one({ name: "c", type: "categorical", values: [0] }), /c: a categorical needs its levels/);
  assert.throws(
    () => one({ name: "c", type: "categorical", values: [0], categorical: { levels: ["a"], ordered: false, labelSet: "s", codes: [1, 2] } }),
    /c: categorical\.codes has 2 codes for 1 levels/,
  );
  assert.throws(
    () => one({ name: "c", type: "categorical", values: [0], categorical: { levels: ["a"], ordered: false, codes: [1.5] } }),
    /c: categorical\.codes holds 1\.5, not a whole number within long's range/,
  );
  // An unused set by the column's name that says the same is reused.
  const same = roundTrip({ valueLabels: { h: new Map([[1, "a"], [2, "b"]]) }, variables: [{ name: "h", type: "categorical", levels: ["a", "b"], values: [0] }] });
  assert.deepEqual(Object.keys(same.labels), ["h"]);
  assert.equal(same.variables[0].valueLabels, "h");
});

/** A .dta file with factor `region` marked as plan 0020's writers mark it, and whatever else `extra` adds. */
function marked({ set = "region", labels = new Map([[10, "low"], [20, "high"]]), values = [10, 20, null], mark = `ordered ${set}`, extra = [] } = {}) {
  const f = join(dir, `${n++}.dta`);
  dp.writeDtaFile(f, {
    valueLabels: { [set]: labels, other: new Map([[1, "one"]]) },
    characteristics: [{ variable: "region", name: "dtaparser_factor", value: mark }, { variable: "region", name: "keep", value: "me" }],
    variables: [{ name: "region", type: "long", valueLabels: set, values }, ...extra],
  });
  return f;
}

test("readDta restores a marked factor, keeping its codes and its set's name", () => {
  const f = marked({ set: "regions" });
  const ds = node.readDta(f);
  const v = ds.variables[0];
  assert.equal(v.type, "categorical");
  assert.equal(v.valueLabels, "");
  assert.deepEqual(v.categorical, { levels: ["low", "high"], ordered: true, labelSet: "regions", codes: [10, 20] });
  assert.deepEqual(v.values, { kind: "dictionary", codes: Uint32Array.of(0, 1, 0), values: ["low", "high"], missing: Uint8Array.of(0, 0, 1) });
  assert.deepEqual(Object.keys(ds.valueLabels), ["other"]);
  assert.deepEqual(ds.characteristics, [{ variable: "region", name: "keep", value: "me" }]);
  // The browser path gives the same.
  const r = dp.openDta(require("node:fs").readFileSync(f));
  assert.deepEqual(readDataset(r), ds);
  r.close();
  // Back to .dta: the same codes, set name and marker.
  const back = join(dir, `${n++}.dta`);
  node.saveDta(ds, back);
  const r2 = dp.openDtaFile(back);
  assert.equal(r2.variables[0].valueLabels, "regions");
  assert.deepEqual([...r2.valueLabels("regions")], [[10, "low"], [20, "high"]]);
  assert.deepEqual(Array.from(r2.readColumns([0])[0].values.slice(0, 2)), [10, 20]);
  assert.deepEqual(r2.characteristics().filter((c) => c.name === "dtaparser_factor"), [{ variable: "region", name: "dtaparser_factor", value: "ordered regions" }]);
  r2.close();
  // To Parquet: a categorical, no dangling set reference; back to .dta, codes 1 to k under the column's name.
  const pq = openParquet(writeParquet(ds));
  assert.deepEqual(pq.variables[0].categorical, { levels: ["low", "high"], ordered: true });
  assert.equal(pq.variables[0].valueLabels, "");
  const viaPq = readDataset(pq);
  pq.close();
  const again = join(dir, `${n++}.dta`);
  node.saveDta(viaPq, again);
  const r3 = dp.openDtaFile(again);
  assert.equal(r3.variables[0].valueLabels, "region");
  assert.deepEqual([...r3.valueLabels("region")], [[1, "low"], [2, "high"]]);
  r3.close();
});

test("a factor sharing its set with a labelled column, or with another factor, keeps one set on saving", () => {
  const f = marked({ extra: [{ name: "plain", type: "long", valueLabels: "region", values: [10, 10, 20] }] });
  const ds = node.readDta(f);
  assert.equal(ds.variables[0].type, "categorical");
  assert.deepEqual(Object.keys(ds.valueLabels).sort(), ["other", "region"]);
  const out = join(dir, `${n++}.dta`);
  node.saveDta(ds, out);
  const r = dp.openDtaFile(out);
  assert.deepEqual(r.valueLabelNames().sort(), ["other", "region"]);
  assert.deepEqual(r.variables.map((v) => v.valueLabels), ["region", "region"]);
  r.close();

  const two = join(dir, `${n++}.dta`);
  dp.writeDtaFile(two, {
    valueLabels: { lv: new Map([[1, "a"], [2, "b"]]) },
    characteristics: [
      { variable: "x", name: "dtaparser_factor", value: "unordered lv" },
      { variable: "y", name: "dtaparser_factor", value: "unordered lv" },
    ],
    variables: [{ name: "x", type: "long", valueLabels: "lv", values: [1, 2] }, { name: "y", type: "long", valueLabels: "lv", values: [2, 2] }],
  });
  const both = node.readDta(two);
  assert.deepEqual(both.variables.map((v) => v.type), ["categorical", "categorical"]);
  assert.deepEqual(Object.keys(both.valueLabels), []);
  const out2 = join(dir, `${n++}.dta`);
  node.saveDta(both, out2);
  const r2 = dp.openDtaFile(out2);
  assert.deepEqual(r2.valueLabelNames(), ["lv"]);
  assert.deepEqual(r2.variables.map((v) => v.valueLabels), ["lv", "lv"]);
  r2.close();
});

test("a marker that no longer holds gives labelled numbers and one warning; saving drops the marker", () => {
  const cases = [
    [{ values: [10, 30] }, /row 1 holds 30, which has no label/],
    [{ values: [10, MISSING[".d"]] }, /row 1 holds an extended missing value/],
    [{ labels: new Map([[10, "same"], [20, "same"]]) }, /two codes in its value label set share the text "same"/],
    [{ mark: "ordered elsewhere" }, /its value label set is "region", not "elsewhere"/],
    // (A code that is not a whole number within long's range cannot be
    // tested: no .dta file holds one; Stata's label codes are those.)
    [{ labels: new Map([[10, "low"], [MISSING[".r"], "Refused"]]), values: [10] }, /labels the missing value \.r/],
    [{ mark: "sideways region" }, /is not "ordered <set>" or "unordered <set>"/],
  ];
  for (const [opts, why] of cases) {
    const f = marked(opts);
    const got = [];
    const ds = node.readDta(f, { onWarning: (m) => got.push(m) });
    assert.equal(got.length, 1);
    assert.match(got[0][0], /changed after it was written, so it is read as labelled numbers/);
    assert.match(got[0][1], why);
    assert.equal(ds.variables[0].type, "long");
    assert.equal(ds.variables[0].valueLabels, ds.variables[0].valueLabels);
    assert.ok(ds.characteristics.some((c) => c.name === "dtaparser_factor"));
    const out = join(dir, `${n++}.dta`);
    node.saveDta(ds, out);
    const r = dp.openDtaFile(out);
    assert.equal(r.characteristics().some((c) => c.name === "dtaparser_factor"), false);
    assert.deepEqual(r.valueLabels(r.variables[0].valueLabels), ds.valueLabels[ds.variables[0].valueLabels]);
    r.close();
  }
  // Without onWarning, one process warning.
  const seen = [];
  const listen = (w) => seen.push(w);
  process.on("warning", listen);
  node.readDta(marked({ values: [99] }));
  return new Promise((done) =>
    setImmediate(() => {
      process.off("warning", listen);
      assert.equal(seen.length, 1);
      assert.equal(seen[0].code, "DATAKIT_FACTOR");
      done();
    }),
  );
});
