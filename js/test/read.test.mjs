// The npm package reads every fixture as readstata13 and pandas do
// (compat/expected); the Rust tests cover the per-reader quirks, so
// this checks the binding: values, missing values, metadata, labels.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { openDta, MISSING, isMissing } = require("../dist/index.js");
const { openDtaFile } = require("../dist/node.js");

const compat = new URL("../../compat/", import.meta.url);
const fixtures = readdirSync(new URL("fixtures/", compat)).filter((f) => f.endsWith(".dta"));

function cell(v) {
  if (isMissing(v)) return { missing: v.missing };
  return v;
}

for (const name of fixtures) {
  const stem = name.replace(/\.dta$/, "");
  const expected = JSON.parse(readFileSync(new URL(`expected/${stem}.pandas.json`, compat), "utf8"));
  if (expected.error) continue;
  test(`${stem} reads as pandas reads it`, () => {
    const r = openDta(readFileSync(new URL(`fixtures/${name}`, compat)));
    assert.equal(r.info.release, expected.release);
    assert.equal(r.info.nobs, expected.nobs);
    assert.equal(r.info.label, expected.data_label);
    for (const [i, v] of expected.variables.entries()) {
      const ours = r.variables[i];
      assert.equal(ours.name, v.name);
      assert.equal(ours.type, v.type);
      assert.equal(ours.format, v.format);
      assert.equal(ours.label, v.label);
      const labels = r.valueLabels(ours.valueLabels);
      const pairs = labels ? [...labels].map(([k, t]) => [isMissing(k) ? k.missing : k, t]) : [];
      assert.deepEqual(pairs, v.labels);
      const rows = r.readRows(0, r.info.nobs, [i]).map((row) => cell(row[0]));
      // pandas decodes text before 118 as Latin-1; the Rust tests check those.
      if (!(r.info.release < 118 && ours.type.startsWith("str") && stem.startsWith("haven"))) {
        assert.deepEqual(rows, expected.values[v.name]);
      }
    }
    r.close();
  });
}

test("missing values are singletons", () => {
  assert.equal(MISSING[".a"], MISSING[".a"]);
  assert.ok(Object.isFrozen(MISSING[".z"]));
});

test("openDtaFile reads an unlinked file through a caller's fd", async () => {
  const fs = await import("node:fs");
  const os = await import("node:os");
  const path = await import("node:path");
  const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "dta-")), "x.dta");
  fs.copyFileSync(new URL("fixtures/haven_118.dta", compat), tmp);
  const fd = fs.openSync(tmp, "r");
  fs.unlinkSync(tmp);
  const r = openDtaFile(fd);
  assert.equal(r.readColumns(["text"])[0].values[1], "café");
  r.close();
  fs.closeSync(fd); // still the caller's to close
});

test("errors name the problem", () => {
  assert.throws(() => openDta(new Uint8Array([1, 2, 3])), /release|end of file/);
  const r = openDta(readFileSync(new URL("fixtures/haven_118.dta", compat)));
  assert.throws(() => r.readColumns(["nope"]), /no variable/);
  assert.throws(() => r.readColumns([0], { start: 5, count: 5 }), RangeError);
  r.close();
  assert.throws(() => r.readColumns([0]), /closed/);
});
