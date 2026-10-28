// writeDta and writeDtaFile write release 118 that reads back as written.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { openDta, writeDta, MISSING, missingValue } = require("../dist/index.js");
const { writeDtaFile, openDtaFile } = require("../dist/node.js");

const compat = new URL("../../compat/", import.meta.url);

test("a dataset reads back as written", () => {
  const bytes = writeDta({
    label: "Written by npm",
    notes: ["a note"],
    valueLabels: { yesno: new Map([[0, "No"], [1, "Yes"], [MISSING[".d"], "Don't know"]]) },
    variables: [
      { name: "b", type: "byte", values: [1, 0, MISSING[".d"]], valueLabels: "yesno", label: "Answer" },
      { name: "d", values: [1.5, null, MISSING[".z"]] },
      { name: "s", values: ["a", "", "café"] },
      { name: "big", values: ["x".repeat(3000), "", "x".repeat(3000)] },
    ],
  });
  const r = openDta(bytes);
  assert.equal(r.info.release, 118);
  assert.equal(r.info.label, "Written by npm");
  assert.deepEqual(r.notes(), ["a note"]);
  assert.deepEqual(
    r.variables.map((v) => [v.name, v.type, v.label, v.valueLabels]),
    [["b", "byte", "Answer", "yesno"], ["d", "double", "", ""], ["s", "str5", "", ""], ["big", "strL", "", ""]],
  );
  assert.deepEqual(r.readRows(0, 3, ["b", "d", "s"]), [
    [1, 1.5, "a"],
    [0, MISSING["."], ""],
    [MISSING[".d"], MISSING[".z"], "café"],
  ]);
  assert.equal(r.readColumns(["big"])[0].values[2].length, 3000);
  assert.equal(r.valueLabels("yesno").get(MISSING[".d"]), "Don't know");
});

test("every fixture survives readColumns, writeDta, readColumns", () => {
  for (const name of readdirSync(new URL("fixtures/", compat)).filter((f) => f.endsWith(".dta"))) {
    const r = openDta(readFileSync(new URL(`fixtures/${name}`, compat)));
    const cols = r.readColumns(r.variables.map((_, i) => i));
    const valueLabels = {};
    for (const v of r.variables) if (v.valueLabels && r.valueLabels(v.valueLabels)) valueLabels[v.valueLabels] = r.valueLabels(v.valueLabels);
    const variables = r.variables.map((v, i) => ({
      name: v.name,
      format: v.format,
      label: v.label,
      valueLabels: valueLabels[v.valueLabels] ? v.valueLabels : undefined,
      ...(cols[i].kind === "number"
        ? { type: v.type, values: Array.from(cols[i].values, (x, k) => (cols[i].missing[k] ? missingValue(cols[i].missing[k]) : x)) }
        : { values: cols[i].values }),
    }));
    const again = openDta(writeDta({ label: r.info.label, variables, valueLabels }));
    assert.deepEqual(again.readColumns(again.variables.map((_, i) => i)), cols, name);
    for (const set of Object.keys(valueLabels)) assert.deepEqual(again.valueLabels(set), valueLabels[set], name);
  }
});

test("a strL larger than one read's budget still reads", () => {
  const big = "y".repeat(70 << 20);
  const path = join(mkdtempSync(join(tmpdir(), "dta-")), "big.dta");
  writeDtaFile(path, { variables: [{ name: "s", values: [big, "small", big] }, { name: "n", values: [1, 2, 3] }] });
  const r = openDtaFile(path);
  const [s, n] = r.readColumns(["s", "n"]);
  assert.deepEqual(s.values.map((v) => v.length), [big.length, 5, big.length]);
  assert.deepEqual(Array.from(n.values), [1, 2, 3]);
  r.close();
});

test("a value outside its type is an error, and writeDtaFile leaves no file", () => {
  assert.throws(() => writeDta({ variables: [{ name: "x", type: "byte", values: [101] }] }), /does not fit storage type byte/);
  const path = join(mkdtempSync(join(tmpdir(), "dta-")), "bad.dta");
  assert.throws(() => writeDtaFile(path, { variables: [{ name: "x", type: "int", values: [1.5] }] }), /does not fit/);
  assert.equal(existsSync(path), false);
  assert.throws(() => writeDta({ variables: [{ name: "x", values: ["a", 1] }] }), /mixes/);
  assert.throws(() => writeDta({ variables: [{ name: "x", type: "double", values: ["a", "b"] }] }), /holds strings/);
  assert.throws(() => writeDta({ variables: [{ name: "x", label: "left\0right", values: [1] }] }), /NUL/);
  assert.throws(() => writeDta({ notes: ["a\0b"], variables: [{ name: "x", values: [1] }] }), /NUL/);
  assert.throws(() => writeDta({ variables: [{ name: "s", values: ["a\0b"] }] }), /without NULs/);
});
