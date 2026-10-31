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
        : { type: v.type === "strL" ? "strL" : undefined, values: cols[i].values }),
    }));
    const again = openDta(
      writeDta({
        label: r.info.label,
        variables,
        valueLabels,
        notes: r.notes(),
        characteristics: r.characteristics(),
        sortedBy: r.info.sortedBy,
        timestamp: r.info.timestamp,
      }),
    );
    assert.deepEqual(again.readColumns(again.variables.map((_, i) => i)), cols, name);
    for (const set of Object.keys(valueLabels)) assert.deepEqual(again.valueLabels(set), valueLabels[set], name);
    assert.deepEqual(
      again.variables.map((v) => [v.name, v.format, v.label, v.type.startsWith("str") ? v.type === "strL" : v.type]),
      r.variables.map((v) => [v.name, v.format, v.label, v.type.startsWith("str") ? v.type === "strL" : v.type]),
      name,
    );
    assert.equal(again.info.label, r.info.label, name);
    assert.equal(again.info.timestamp, r.info.timestamp, name);
    assert.deepEqual(again.info.sortedBy, r.info.sortedBy, name);
    assert.deepEqual(again.notes(), r.notes(), name);
    assert.deepEqual(again.characteristics(), r.characteristics(), name);
  }
});

test("number columns write back as readColumns gives them", () => {
  for (const name of readdirSync(new URL("fixtures/", compat)).filter((f) => f.endsWith(".dta"))) {
    const r = openDta(readFileSync(new URL(`fixtures/${name}`, compat)));
    const cols = r.readColumns(r.variables.map((_, i) => i));
    const variables = r.variables.map((v, i) =>
      cols[i].kind === "number"
        ? { name: v.name, type: v.type, values: cols[i].values, missing: cols[i].missing }
        : { name: v.name, type: v.type === "strL" ? "strL" : undefined, values: cols[i].values },
    );
    const again = openDta(writeDta({ variables }));
    assert.deepEqual(again.readColumns(again.variables.map((_, i) => i)), cols, name);
  }
  assert.throws(
    () => writeDta({ variables: [{ name: "x", values: new Float64Array(2), missing: new Uint8Array(1) }] }),
    /missing codes/,
  );
});

/** A file with every kind of metadata and a strL column holding binary values. */
function withEverything() {
  return writeDta({
    timestamp: "05 Mar 2024 09:07",
    notes: ["first", "second"],
    characteristics: [
      { variable: "_dta", name: "origin", value: "test" },
      { variable: "a", name: "unit", value: "kg" },
      { variable: "gone", name: "x", value: "dropped: no such variable" },
      { variable: "_dta", name: "note1", value: "dropped: notes come from notes" },
    ],
    sortedBy: ["a", "b"],
    variables: [
      { name: "a", type: "byte", values: [1, 1, 2] },
      { name: "b", type: "byte", values: [1, 2, 1] },
      { name: "blob", values: [new Uint8Array([0, 1, 2, 255]), "text", new Uint8Array()] },
      { name: "short", type: "strL", values: ["x", "", "z"] },
    ],
  });
}

test("timestamp, notes, characteristics, sort order and binary strLs read back", () => {
  const r = openDta(withEverything());
  assert.equal(r.info.timestamp, "05 Mar 2024 09:07");
  assert.deepEqual(r.info.sortedBy, ["a", "b"]);
  assert.deepEqual(r.notes(), ["first", "second"]);
  assert.deepEqual(
    r.characteristics().filter((c) => !c.name.startsWith("note")),
    [{ variable: "_dta", name: "origin", value: "test" }, { variable: "a", name: "unit", value: "kg" }],
  );
  assert.deepEqual(r.variables.map((v) => v.type), ["byte", "byte", "strL", "strL"]);
  const [blob, short] = r.readColumns(["blob", "short"]);
  assert.deepEqual(blob.values, [new Uint8Array([0, 1, 2, 255]), "text", new Uint8Array()]);
  assert.deepEqual(short.values, ["x", "", "z"]);
  // and once more through readColumns and writeDta
  const cols = r.readColumns(r.variables.map((_, i) => i));
  const again = openDta(
    writeDta({
      timestamp: r.info.timestamp,
      notes: r.notes(),
      characteristics: r.characteristics(),
      sortedBy: r.info.sortedBy,
      variables: r.variables.map((v, i) => ({
        name: v.name,
        type: v.type,
        values: cols[i].kind === "number" ? Array.from(cols[i].values) : cols[i].values,
      })),
    }),
  );
  assert.deepEqual(again.readColumns(again.variables.map((_, i) => i)), cols);
  assert.deepEqual(again.characteristics(), r.characteristics());
  assert.deepEqual(again.info.sortedBy, r.info.sortedBy);
  assert.equal(again.info.timestamp, r.info.timestamp);
});

test("writing some variables keeps their characteristics and the leading sort keys", () => {
  const r = openDta(withEverything());
  const write = (names) => {
    const cols = r.readColumns(names);
    return openDta(
      writeDta({
        characteristics: r.characteristics(),
        sortedBy: r.info.sortedBy,
        variables: names.map((name, i) => ({
          name,
          values: cols[i].kind === "number" ? Array.from(cols[i].values) : cols[i].values,
        })),
      }),
    );
  };
  const b = write(["b", "short"]);
  assert.deepEqual(b.info.sortedBy, []);
  assert.deepEqual(b.characteristics().map((c) => c.variable), ["_dta"]);
  const a = write(["a", "short"]);
  assert.deepEqual(a.info.sortedBy, ["a"]);
  assert.deepEqual(a.characteristics().map((c) => c.variable), ["_dta", "a"]);
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
  assert.throws(() => writeDta({ variables: [{ name: "s", values: [new Uint8Array([1]), 2] }] }), /mixes/);
  assert.throws(() => writeDta({ variables: [{ name: "x", type: "strL", values: [1] }] }), /mixes/);
  assert.throws(
    () => writeDta({ characteristics: [{ variable: "x", name: "a", value: "b\0c" }], variables: [{ name: "x", values: [1] }] }),
    /NUL/,
  );
  assert.throws(() => writeDta({ timestamp: "a\0b", variables: [{ name: "x", values: [1] }] }), /NUL/);
  // A NUL in a binary strL is fine.
  const r = openDta(writeDta({ variables: [{ name: "s", values: [new Uint8Array([0, 0])] }] }));
  assert.deepEqual(r.readColumns(["s"])[0].values, [new Uint8Array([0, 0])]);
});

test("a leading U+FEFF survives in strN, strL, variable labels and value label text", () => {
  const bom = "\uFEFFhello";
  const bytes = writeDta({
    variables: [
      { name: "s", values: [bom, "x"] },
      { name: "l", type: "strL", values: [bom, "y"] },
      { name: "n", values: [1, 2], label: bom, valueLabels: "set" },
    ],
    valueLabels: { set: new Map([[1, bom]]) },
  });
  const r = openDta(bytes);
  const [s, l] = r.readColumns(["s", "l"]);
  assert.equal(s.values[0], bom);
  assert.equal(l.values[0], bom);
  assert.equal(r.variables[2].label, bom);
  assert.equal(r.valueLabels("set").get(1), bom);
  r.close();
});
