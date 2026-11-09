// readFixedWidth and convertFixedWidth (plan 0021): fixed-width text
// through a SAS setup file, against asciiSetupReader's reading of the
// synthetic file (compat/expected/fixed_width.json, ADR 0005), and the
// options, warnings and temporary files.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const dk = require("../dist/index.js");
const node = require("../dist/node.js");
const dp = require("@jbearak/dta-parser");
const { MISSING, convertFixedWidth, readDataset } = dk;

const fw = fileURLToPath(new URL("../../../compat/fixed_width/", import.meta.url));
const oracle = JSON.parse(readFileSync(new URL("../../../compat/expected/fixed_width.json", import.meta.url), "utf8"));
const synthetic = [join(fw, "synthetic.dat"), join(fw, "synthetic.sas")];
const alnum = (s) => s.replace(/[^A-Za-z0-9]/g, "");
const key = (k) => (typeof k === "object" ? k.missing : k);

test("recodes: setup gives what asciiSetupReader gives", () => {
  const ds = node.readFixedWidth(...synthetic, { onWarning: (m) => assert.fail(m.join("\n")) });
  assert.deepEqual(ds.variables.map((v) => v.name).sort(), oracle.variables.map((v) => v.name).sort());
  for (const want of oracle.variables) {
    const v = ds.variables.find((x) => x.name === want.name);
    // asciiSetupReader turns labels into names, adding the variable's name where two are the same.
    assert.ok([alnum(v.label), alnum(v.label) + v.name].includes(alnum(want.label)), `${v.name}: ${v.label}`);
    const got = v.values.kind === "string"
      ? v.values.values.map((s) => (s === "" ? null : s))
      : Array.from(v.values.values, (x, i) => (v.values.missing[i] ? null : x));
    assert.equal(got.length, oracle.nobs);
    got.forEach((x, i) => {
      const y = want.values[i];
      if (typeof x === "number" && y !== null) assert.ok(Math.abs(x - y) <= 1e-9 * Math.max(1, Math.abs(y)), `${v.name} row ${i}: ${x} ${y}`);
      else assert.equal(x, y, `${v.name} row ${i}`);
    });
    // Setup mode drops the labels of codes recoded to `.`.
    const labels = v.valueLabels ? [...ds.valueLabels[v.valueLabels]].map(([k, t]) => [key(k), t]) : [];
    const expect = (want.labels ?? []).filter(([k]) => !(want.recoded ?? []).includes(k));
    assert.deepEqual(labels.sort(), expect.sort(), v.name);
  }
});

test("recodes: tagged gives asciiSetupReader's codes with each recode a letter, labelled", () => {
  const ds = node.readFixedWidth(...synthetic, { recodes: "tagged" });
  for (const want of oracle.variables) {
    if (!want.tagged) continue;
    const v = ds.variables.find((x) => x.name === want.name);
    const got = Array.from(v.values.values, (x, i) => (v.values.missing[i] === 1 ? null : v.values.missing[i] ? MISSING_NAME(v.values.missing[i]) : x));
    assert.deepEqual(got, want.tagged.map((y) => (y && typeof y === "object" ? { missing: y.missing } : y)), v.name);
    const labels = v.valueLabels ? [...ds.valueLabels[v.valueLabels]].map(([k, t]) => [key(k), t]) : [];
    assert.deepEqual(labels.sort(), want.tagged_labels.sort(), v.name);
  }
});
const MISSING_NAME = (code) => ({ missing: dk.missingValue(code).missing });

// A small setup in CDC's style, as Python's test has it.
const SETUP = [
  "/* A setup in CDC's style */",
  'libname "data-file-path";',
  "PROC FORMAT;",
  "  VALUE sexf  1='(1) Boy' 2='(2) Girl' ;",
  "  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained' ;",
  "DATA ;",
  'INFILE "c:\\temp\\x.dat" LRECL=6;',
  "INPUT ID 1-3 SEX 4 KIDS 5-6 ;",
  "LABEL ID = 'Case number' SEX = \"R's sex\"",
  "  KIDS = '" + "k".repeat(200) + "' ;",
  "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
  "FORMAT SEX sexf. KIDS kidsf. ;",
  "RUN ;",
].join("\n");
const DATA = "0011 2\n002298\n003199\n004199\n0052 0\n";

function files(setup = SETUP, data = DATA) {
  const dir = mkdtempSync(join(tmpdir(), "datakit-fw-test-"));
  const setups = (Array.isArray(setup) ? setup : [setup]).map((s, k) => {
    const p = join(dir, `x${k}.sas`);
    writeFileSync(p, s);
    return p;
  });
  writeFileSync(join(dir, "x.dat"), data);
  return [join(dir, "x.dat"), setups.length === 1 ? setups[0] : setups];
}

test("the small setup: types, labels, recodes and the three modes", () => {
  const ds = node.readFixedWidth(...files(), { onWarning: (m) => assert.fail(m.join("\n")) });
  assert.deepEqual(ds.variables.map((v) => [v.name, v.type]), [["ID", "byte"], ["SEX", "byte"], ["KIDS", "byte"]]);
  const kids = ds.variables[2];
  assert.equal(kids.label, "k".repeat(200));
  assert.deepEqual(Array.from(kids.values.missing), [0, 1, 1, 1, 0]);
  assert.deepEqual([...ds.valueLabels[kids.valueLabels]], [[0, "(0) None"]]);
  const tagged = node.readFixedWidth(...files(), { recodes: "tagged" });
  assert.deepEqual(Array.from(tagged.variables[2].values.missing), [0, 2, 3, 3, 0]);
  assert.deepEqual([...tagged.valueLabels.kidsf], [[0, "(0) None"], [MISSING[".a"], "(98) DK"], [MISSING[".b"], "(99) Not ascertained"]]);
  const none = node.readFixedWidth(...files(), { recodes: "none" });
  assert.deepEqual(Array.from(none.variables[2].values.values), [2, 98, 99, 99, 0]);
  assert.throws(() => node.readFixedWidth(...files(), { recodes: "some" }), /recodes must be "setup", "tagged" or "none", not "some"/);
  assert.throws(() => node.readFixedWidth(...files(), { commentedFormats: "yes" }), /commentedFormats must be true or false/);
  // columns, start and count, as readDataset takes them.
  const part = node.readFixedWidth(...files(), { columns: ["KIDS", "ID"], start: 3, count: 2 });
  assert.deepEqual(part.variables.map((v) => v.name), ["KIDS", "ID"]);
  assert.deepEqual(Array.from(part.variables[1].values.values), [4, 5]);
});

test("several setup files read in order as one", () => {
  const [lead, rest] = [SETUP.slice(0, SETUP.indexOf("DATA ;")), SETUP.slice(SETUP.indexOf("DATA ;"))];
  const one = node.readFixedWidth(...files());
  const two = node.readFixedWidth(...files([lead, rest]));
  assert.deepEqual(two, one);
});

test("commentedFormats reads a PROC FORMAT step alone in a block comment", () => {
  const commented = SETUP.replace("PROC FORMAT;", "/* PROC FORMAT;").replace("Not ascertained' ;", "Not ascertained' ; */");
  assert.deepEqual([...node.readFixedWidth(...files(commented)).valueLabels.kidsf], [[0, "(0) None"]]);
  const got = [];
  const plain = node.readFixedWidth(...files(commented), { commentedFormats: false, onWarning: (m) => got.push(...m) });
  assert.deepEqual(Object.keys(plain.valueLabels), []);
});

test("every kind of warning reaches onWarning, or one process warning", async () => {
  const setup = SETUP.replace("RUN ;", "LABEL NOPE = 'x' ;\nX = 1;\nRUN ;").replace("'(1) Boy'", "'" + "b".repeat(400) + "'").replace(
    "KIDS = '" + "k".repeat(200) + "'",
    "KIDS = '" + "k".repeat(330) + "'",
  );
  const got = [];
  node.readFixedWidth(...files(setup, DATA + "006\n"), { onWarning: (m) => got.push(...m) });
  const text = got.join("\n");
  for (const what of [/NOPE/, /X = 1/i, /shorter than column/, /320 bytes|cut/]) assert.match(text, what);
  const seen = [];
  const listen = (w) => seen.push(w);
  process.on("warning", listen);
  node.readFixedWidth(...files(setup, DATA + "006\n"));
  await new Promise((r) => setImmediate(r));
  process.off("warning", listen);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].code, "DATAKIT_FIXED_WIDTH");
  assert.match(seen[0].message, /The setup file was read with warnings/);
});

test("the temporary directory is gone after a read and after an error", () => {
  // A directory of this test's own as the temporary directory, since
  // other test files run at the same time.
  const own = mkdtempSync(join(tmpdir(), "datakit-fw-tmp-"));
  const input = files();
  const bad = files("INPUT ;\nIF (( THEN ;")[1];
  const saved = process.env.TMPDIR;
  process.env.TMPDIR = own;
  try {
    node.readFixedWidth(...input);
    assert.deepEqual(readdirSync(own), []);
    assert.throws(() => node.readFixedWidth(input[0], bad), /./);
    assert.deepEqual(readdirSync(own), []);
    assert.throws(() => node.readFixedWidth(...input, { onWarning: () => {}, columns: ["NOPE"] }), /no variable "NOPE"/);
    assert.deepEqual(readdirSync(own), []);
  } finally {
    if (saved === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = saved;
  }
});

test("convertFixedWidth gives the same .dta in memory; readFixedWidth gives the module's memory back", () => {
  const [data, setup] = files();
  const { dta, warnings } = convertFixedWidth(readFileSync(data), [readFileSync(setup, "utf8")]);
  assert.deepEqual(warnings, []);
  const r = dp.openDta(dta);
  assert.deepEqual(readDataset(r), node.readFixedWidth(data, setup));
  r.close();
});
