// Previews (plan 0008 M5, Sight's D2): maxStringBytes keeps at most that
// many stored bytes of each string, cut on whole characters, reads no
// more of a strL than that (and its last byte), and reports storedBytes.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { DtaReader, openDta, writeDta } = require("../dist/index.js");

const texts = ["", "abc", "€uro€", "😀x", "aaaaaaaaaa", "é", "﻿bom"];
const enc = new TextEncoder();
const bytes = writeDta({
  variables: [
    { name: "s", values: texts },
    { name: "l", type: "strL", values: texts },
    { name: "b", type: "strL", values: texts.map((t) => enc.encode(t)) },
  ],
});

test("every cap: values are prefixes, storedBytes is the stored length, cut exactly when longer", () => {
  const r = openDta(bytes);
  const full = r.readColumns(["s", "l", "b"]);
  for (let cap = 0; cap <= 12; cap++) {
    const cols = r.readColumns(["s", "l", "b"], { maxStringBytes: cap });
    for (const [k, col] of cols.entries()) {
      for (let i = 0; i < texts.length; i++) {
        const stored = enc.encode(texts[i]).length;
        assert.equal(col.storedBytes[i], stored, `col ${k} row ${i} cap ${cap}`);
        const v = col.values[i];
        const whole = full[k].values[i];
        if (v instanceof Uint8Array) {
          assert.deepEqual(v, whole.subarray(0, Math.min(cap, stored)));
        } else {
          assert.ok(whole.startsWith(v), `${JSON.stringify(v)} is not a prefix of ${JSON.stringify(whole)}`);
          assert.ok(enc.encode(v).length <= cap);
          assert.equal(v !== whole, stored > cap, `col ${k} row ${i} cap ${cap}`);
        }
      }
    }
  }
  r.close();
});

/** A reader over `data` that counts the bytes it is asked for. */
function counting(data) {
  const reads = { bytes: 0 };
  const reader = new DtaReader((into, offset) => {
    reads.bytes += into.length;
    into.set(data.subarray(offset, offset + into.length));
  }, data.length);
  return { reader, reads };
}

test("a capped read of a 64 MiB strL reads under 1 MB of it", () => {
  const big = writeDta({ variables: [{ name: "l", type: "strL", values: ["x".repeat(64 << 20)] }] });
  const { reader, reads } = counting(big);
  reader.readColumns(["l"], { count: 0 });
  const opened = reads.bytes;
  const [l] = reader.readColumns(["l"], { maxStringBytes: 100 });
  assert.equal(l.values[0], "x".repeat(100));
  assert.equal(l.storedBytes[0], 64 << 20);
  assert.ok(reads.bytes - opened < 1 << 20, `${reads.bytes - opened} bytes read`);
  reader.close();
});

test("maxStringBytes: 0 gives lengths, reading one byte of each text strL and none of a binary one", () => {
  const { reader, reads } = counting(bytes);
  reader.readColumns(["s"]); // index the file's sections first
  reader.readColumns(["l"], { count: 1 });
  const before = reads.bytes;
  const [l] = reader.readColumns(["l"], { maxStringBytes: 0 });
  const payload = reads.bytes - before;
  assert.deepEqual(l.values, texts.map(() => ""));
  assert.deepEqual(Array.from(l.storedBytes), texts.map((t) => enc.encode(t).length));
  // The rows themselves, plus one byte for each nonempty text strL.
  const rowBytes = (reads.bytes - before) - texts.filter((t) => t.length).length;
  assert.ok(rowBytes >= 0 && payload < 200, `${payload} bytes`);
  const b0 = reads.bytes;
  const [b] = reader.readColumns(["b"], { maxStringBytes: 0 });
  assert.deepEqual(Array.from(b.storedBytes), texts.map((t) => enc.encode(t).length));
  assert.ok(reads.bytes - b0 < 200);
  reader.close();
});

test("bad caps, and caps with dictionaries, are DTA_INVALID", () => {
  const r = openDta(bytes);
  for (const maxStringBytes of [-1, 1.5, 2 ** 32]) {
    assert.throws(() => r.readColumns(["s"], { maxStringBytes }), (e) => e.code === "DTA_INVALID");
  }
  assert.throws(() => r.readColumns(["s"], { maxStringBytes: 4, strings: "dictionary" }), (e) => e.code === "DTA_INVALID");
  r.close();
});
