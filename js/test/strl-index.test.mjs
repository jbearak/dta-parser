// Sharing the strL index (plan 0008 M6, Sight's D3): readers that adopt
// another's index read the same values without scanning the strLs, and
// an index that does not fit the file is DTA_CORRUPT, on adoption or on
// reading the strLs it lists.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const { DtaReader, openDta, writeDta } = require("../dist/index.js");
const { openDtaFile } = require("../dist/node.js");

const values = Array.from({ length: 2000 }, (_, i) => (i % 7 === 0 ? Uint8Array.of(i & 255, 0) : `value ${i} ${"x".repeat(i % 50)}`));
const bytes = writeDta({ variables: [{ name: "n", values: Array.from({ length: 2000 }, (_, i) => i) }, { name: "l", type: "strL", values }] });
const corrupt = (e) => e.code === "DTA_CORRUPT";

function counting(data, options) {
  const reads = { bytes: 0 };
  const reader = new DtaReader((into, offset) => {
    reads.bytes += into.length;
    into.set(data.subarray(offset, offset + into.length));
  }, data.length, options);
  return { reader, reads };
}

test("an adopted index reads the same values without scanning the strLs", () => {
  const first = openDta(bytes);
  const index = first.strlIndex();
  const expected = first.readColumns(["l"])[0].values;
  first.close();
  const scanned = counting(bytes);
  scanned.reader.readColumns(["l"]);
  const adopted = counting(bytes, { strlIndex: index });
  assert.deepEqual(adopted.reader.readColumns(["l"])[0].values, expected);
  // The scan reads the strL section once; adopting skips it (each
  // record header is read with its payload instead).
  assert.ok(adopted.reads.bytes < scanned.reads.bytes, `${adopted.reads.bytes} >= ${scanned.reads.bytes}`);
  scanned.reader.close();
  adopted.reader.close();
});

test("every way of opening a file adopts an index, from a SharedArrayBuffer too", () => {
  const index = openDta(bytes).strlIndex();
  const shared = new Uint8Array(new SharedArrayBuffer(index.length));
  shared.set(index);
  const path = join(mkdtempSync(join(tmpdir(), "dta-index-")), "f.dta");
  writeFileSync(path, bytes);
  for (const r of [openDta(bytes, { strlIndex: shared }), openDtaFile(path, { strlIndex: index }), new DtaReader((into, o) => into.set(bytes.subarray(o, o + into.length)), bytes.length, { strlIndex: index })]) {
    assert.deepEqual(r.readColumns(["l"], { start: 1995 })[0].values, values.slice(1995));
    r.close();
  }
});

test("an index that does not fit the file is DTA_CORRUPT", () => {
  const index = openDta(bytes).strlIndex();
  const damaged = (f) => {
    const copy = index.slice();
    f(copy);
    return copy;
  };
  const view = (b) => new DataView(b.buffer, b.byteOffset, b.byteLength);
  const n = Number(view(index).getBigUint64(64, true));
  for (const bad of [
    index.subarray(0, index.length - 1), // truncated
    damaged((b) => (b[8] = 9)), // unknown version
    damaged((b) => view(b).setBigUint64(16, BigInt(bytes.length + 1), true)), // another file's length
    damaged((b) => view(b).setBigUint64(72, 2n ** 60n, true)), // keys out of order
    damaged((b) => view(b).setBigUint64(72 + n * 8, BigInt(bytes.length), true)), // offset outside the strL section
  ]) {
    assert.throws(() => openDta(bytes, { strlIndex: bad }), corrupt);
  }
});

test("an index from another file of the same size and layout is caught reading the strLs", () => {
  const swapped = [...values];
  [swapped[1], swapped[2]] = [swapped[2], swapped[1]];
  const other = writeDta({ variables: [{ name: "n", values: Array.from({ length: 2000 }, (_, i) => i) }, { name: "l", type: "strL", values: swapped }] });
  assert.equal(other.length, bytes.length);
  const r = openDta(other, { strlIndex: openDta(bytes).strlIndex() });
  assert.throws(() => r.readColumns(["l"]), corrupt);
  r.close();
});
