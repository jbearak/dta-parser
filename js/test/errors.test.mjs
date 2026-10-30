// Errors carry a code (plan 0008 E), each from a real trigger here.
// DTA_TOO_LARGE needs a module with capped memory; memory.test.mjs has it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { DtaReader, openDta, writeDta } = require("../dist/index.js");
const bytes = readFileSync(new URL("../../compat/fixtures/pandas_118_le.dta", import.meta.url));

const code = (code, kind = Error) => (e) => {
  assert.ok(e instanceof kind, `${e} is not a ${kind.name}`);
  assert.equal(e.code, code, `${e.message}: ${e.code}`);
  return true;
};

test("a damaged file is DTA_CORRUPT", () => {
  const damaged = Uint8Array.from(bytes);
  damaged.fill(0x41, 0, 40);
  assert.throws(() => openDta(damaged), code("DTA_CORRUPT"));
});

test("a failing ReadAt is DTA_IO, with what it threw as the cause", () => {
  let fail = false;
  const thrown = new Error("disk gone");
  const r = new DtaReader((into, offset) => {
    if (fail) throw thrown;
    into.set(bytes.subarray(offset, offset + into.length));
  }, bytes.length);
  fail = true;
  assert.throws(() => r.readColumns([0]), (e) => code("DTA_IO")(e) && e.cause === thrown);
  r.close();
});

test("a failing write sink is DTA_IO, with what it threw as the cause", () => {
  const { writeDtaTo } = require("../dist/index.js");
  const thrown = new Error("disk full");
  const data = { variables: [{ name: "x", values: Float64Array.of(1) }] };
  assert.throws(() => writeDtaTo(data, () => { throw thrown; }), (e) => code("DTA_IO")(e) && e.cause === thrown);
});

test("an unknown encoding is DTA_INVALID", () => {
  assert.throws(() => openDta(bytes, { encoding: "latin-1" }), code("DTA_INVALID", TypeError));
});

test("data that cannot be written is DTA_INVALID", () => {
  const bad = { variables: [{ name: "1bad", values: Float64Array.of(1) }] };
  assert.throws(() => writeDta(bad), code("DTA_INVALID"));
  const short = { variables: [{ name: "x", values: Float64Array.of(1, 2) }, { name: "y", values: Float64Array.of(1) }] };
  assert.throws(() => writeDta(short), code("DTA_INVALID", RangeError));
});

test("a value its storage cannot hold is a DTA_INVALID RangeError", () => {
  const bad = { variables: [{ name: "b", type: "byte", values: [1000] }] };
  assert.throws(() => writeDta(bad), code("DTA_INVALID", RangeError));
});

test("a variable or rows outside the file are DTA_OUT_OF_RANGE", () => {
  const r = openDta(bytes);
  assert.throws(() => r.readColumns(["no_such_variable"]), code("DTA_OUT_OF_RANGE", RangeError));
  assert.throws(() => r.readColumns([0], { start: r.info.nobs, count: 1 }), code("DTA_OUT_OF_RANGE", RangeError));
  r.close();
});

test("a closed reader is DTA_CLOSED", () => {
  const r = openDta(bytes);
  r.close();
  assert.throws(() => r.readColumns([0]), code("DTA_CLOSED"));
});
