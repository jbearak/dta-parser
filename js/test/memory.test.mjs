// Running out of module memory is an error, never a trap (plan 0008
// M2). These run the package's sources bundled with the test build of
// the module (build/dta-test.wasm: memory capped at 64 MiB, a lowered
// read budget), on files the ordinary build writes. After each error,
// a reader opened before it still reads.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const require = createRequire(import.meta.url);
const ordinary = require("../dist/index.js");
const src = fileURLToPath(new URL("../src/", import.meta.url));
const testWasm = fileURLToPath(new URL("../build/dta-test.wasm", import.meta.url));
const skip = existsSync(testWasm) ? false : "build/dta-test.wasm is missing (run scripts/build-wasm.sh)";

let capped;
let survivor;
const small = ordinary.writeDta({ variables: [{ name: "x", values: Float64Array.of(1, 2, 3) }, { name: "s", values: ["a", "b", "c"] }] });

before(async () => {
  if (skip) return;
  const dir = mkdtempSync(join(tmpdir(), "dta-memory-"));
  const out = join(dir, "capped.js");
  await build({
    stdin: { contents: `export * from ${JSON.stringify(join(src, "index.ts"))}; export { test } from ${JSON.stringify(join(src, "wasm.ts"))};`, resolveDir: src, loader: "ts" },
    bundle: true,
    format: "cjs",
    platform: "node",
    target: "node24",
    outfile: out,
    loader: { ".wasm": "binary" },
    plugins: [{ name: "test-wasm", setup: (b) => b.onResolve({ filter: /dta\.wasm$/ }, () => ({ path: testWasm })) }],
  });
  // One call may ask for every row, so a call can outgrow the budget.
  process.env.DTA_TEST_BLOCK_ROWS = String(1 << 23);
  capped = require(out);
  capped.test.set(1 << 20, 4096);
  survivor = capped.openDta(small);
});

const tooLarge = (e) => {
  assert.equal(e.code, "DTA_TOO_LARGE", `${e.message} (${e.code})`);
  return true;
};

function survivorReads() {
  const [x, s] = survivor.readColumns(["x", "s"]);
  assert.deepEqual(Array.from(x.values), [1, 2, 3]);
  assert.deepEqual(s.values, ["a", "b", "c"]);
}

test("the test module is capped", { skip }, () => {
  assert.ok(capped.test.memoryBytes() <= 64 << 20);
});

test("a read too large for a call is DTA_TOO_LARGE; a smaller budget then reads it", { skip }, () => {
  const rows = 4_000_000;
  const bytes = ordinary.writeDta({ variables: [{ name: "d", values: new Float64Array(rows).fill(2.5) }] });
  const r = capped.openDta(bytes);
  capped.test.set(200 << 20, 4096);
  try {
    assert.throws(() => r.readColumns(["d"]), tooLarge);
  } finally {
    capped.test.set(1 << 20, 4096);
  }
  const [d] = r.readColumns(["d"], { start: rows - 3 });
  assert.deepEqual(Array.from(d.values), [2.5, 2.5, 2.5]);
  r.close();
  survivorReads();
});

test("value labels too large are DTA_TOO_LARGE", { skip }, () => {
  const labels = new Map(Array.from({ length: 300_000 }, (_, i) => [i, `label number ${i} `.padEnd(60, "x")]));
  const bytes = ordinary.writeDta({ variables: [{ name: "x", values: [1], valueLabels: "big" }], valueLabels: { big: labels } });
  const r = capped.openDta(bytes);
  assert.throws(() => r.valueLabels("big"), tooLarge);
  r.close();
  survivorReads();
});

test("a variable list too large is DTA_TOO_LARGE when opening", { skip }, () => {
  const variables = Array.from({ length: 32_767 }, (_, i) => ({ name: `v${i}`, label: "l".repeat(80), values: [i] }));
  const bytes = ordinary.writeDta({ variables });
  assert.throws(() => capped.openDta(bytes), tooLarge);
  survivorReads();
});

test("a strL index too large is DTA_TOO_LARGE", { skip }, () => {
  const rows = 3_000_000;
  const bytes = ordinary.writeDta({ variables: [{ name: "l", type: "strL", values: Array.from({ length: rows }, (_, i) => `${i}`) }] });
  const r = capped.openDta(bytes);
  assert.throws(() => r.readColumns(["l"], { count: 1 }), tooLarge);
  r.close();
  survivorReads();
});

test("a strL too large fails after the index built; the error arrives whole", { skip }, () => {
  const big = new Uint8Array(70 << 20).fill(0x61);
  const bytes = ordinary.writeDta({ variables: [{ name: "l", type: "strL", values: ["small", big] }] });
  const r = capped.openDta(bytes);
  assert.equal(r.readColumns(["l"], { count: 1 })[0].values[0], "small");
  assert.throws(() => r.readColumns(["l"]), (e) => tooLarge(e) && /strL of 73400320 bytes/.test(e.message));
  r.close();
  survivorReads();
});

test("a write too large is DTA_TOO_LARGE", { skip }, () => {
  assert.throws(() => capped.writeDta({ variables: [{ name: "d", values: new Float64Array(10_000_000) }] }), tooLarge);
  const back = ordinary.openDta(capped.writeDta({ variables: [{ name: "x", values: [7] }] }));
  assert.equal(back.readRows(0, 1)[0][0], 7);
  survivorReads();
});

test("calls end before a column's text passes the string limit; one longer value is DTA_TOO_LARGE", { skip }, () => {
  const values = Array.from({ length: 10 }, (_, i) => `${i}`.repeat(300));
  const bytes = ordinary.writeDta({ variables: [{ name: "l", type: "strL", values: [...values, "€".repeat(1200)] }] });
  capped.test.set(1 << 20, 4096, 1000);
  try {
    const r = capped.openDta(bytes);
    assert.deepEqual(r.readColumns(["l"], { count: 10 })[0].values, values);
    assert.throws(() => r.readColumns(["l"], { start: 10, count: 1 }), tooLarge);
    r.close();
  } finally {
    capped.test.set(1 << 20, 4096);
  }
  survivorReads();
});

test("a large text strL after a binary one is DTA_TOO_LARGE, not a trap", { skip }, () => {
  const bytes = ordinary.writeDta({ variables: [{ name: "l", type: "strL", values: [Uint8Array.of(1), "t".repeat(35 << 20)] }] });
  const r = capped.openDta(bytes);
  assert.throws(() => r.readColumns(["l"]), tooLarge);
  r.close();
  survivorReads();
});

test("a large malformed UTF-8 strL is DTA_TOO_LARGE, not a trap", { skip }, () => {
  const bytes = ordinary.writeDta({ variables: [{ name: "l", type: "strL", values: ["MARK" + "\xff".repeat(0) + "m".repeat(30 << 20)] }] });
  // Make the value malformed: its "MARK" becomes 4 bytes that are not UTF-8.
  const at = Buffer.from(bytes).indexOf("MARK");
  bytes.set([0xff, 0xfe, 0xfd, 0xfc], at);
  const r = capped.openDta(bytes);
  assert.throws(() => r.readColumns(["l"]), tooLarge);
  r.close();
  survivorReads();
});

test("with no memory for the reserve, calls fail cleanly, then work again", { skip }, () => {
  const held = [];
  for (let size = 16 << 20; size >= 64 << 10; ) {
    const ptr = capped.test.alloc(size);
    if (ptr === 0) size >>= 1;
    else held.push([ptr, size]);
  }
  try {
    assert.throws(() => survivor.readColumns(["x"]), (e) => tooLarge(e) && /module memory/.test(e.message));
    assert.throws(() => survivor.readColumns(["x"]), tooLarge);
  } finally {
    for (const [ptr, size] of held) capped.test.free(ptr, size);
  }
  survivorReads();
});

test("past 2 GiB of module memory, reads and writes still work", async () => {
  // The ordinary module, with 2.1 GiB taken first so every pointer the
  // glue sees is past 2^31 (which arrive in JavaScript as negative i32s).
  const dir = mkdtempSync(join(tmpdir(), "dta-2gib-"));
  const out = join(dir, "ordinary.js");
  await build({
    stdin: { contents: `export * from ${JSON.stringify(join(src, "index.ts"))}; export { test } from ${JSON.stringify(join(src, "wasm.ts"))};`, resolveDir: src, loader: "ts" },
    bundle: true,
    format: "cjs",
    platform: "node",
    target: "node24",
    outfile: out,
    loader: { ".wasm": "binary" },
  });
  const big = require(out);
  // Keep this instance, filler and all, rather than give its memory back.
  big.test.replaceAbove(Infinity);
  // One allocation cannot pass 2 GiB (isize::MAX in wasm32), so two.
  const filler = Math.floor(1.1 * 2 ** 30);
  const held = [big.test.alloc(filler), big.test.alloc(filler)];
  assert.ok(held.every((p) => p > 0));
  try {
    assert.ok(big.test.memoryBytes() > 2 ** 31);
    const values = { n: Float64Array.of(1.5, -2, 3), s: ["a", "é", "😀"], l: ["long", Uint8Array.of(0, 1), "x"] };
    const bytes = big.writeDta({ variables: [{ name: "n", values: values.n }, { name: "s", values: values.s }, { name: "l", type: "strL", values: values.l }] });
    for (const r of [big.openDta(bytes), ordinary.openDta(bytes)]) {
      const [n, s, l] = r.readColumns(["n", "s", "l"]);
      assert.deepEqual(Array.from(n.values), [1.5, -2, 3]);
      assert.deepEqual(s.values, values.s);
      assert.deepEqual(l.values, values.l);
      r.close();
    }
  } finally {
    for (const p of held) big.test.free(p, filler);
  }
});

test("calls from inside a ReadAt callback or sink are DTA_INVALID; the outer call finishes", { skip }, () => {
  const bytes = ordinary.writeDta({ variables: [{ name: "x", values: Float64Array.of(4, 5, 6) }] });
  const nested = [];
  let inner;
  const r = new capped.DtaReader((into, offset) => {
    if (inner) {
      for (const call of [() => capped.openDta(small), () => inner.readColumns(["x"]), () => inner.close(), () => capped.writeDta({ variables: [{ name: "y", values: [1] }] })]) {
        try {
          call();
          nested.push("ran");
        } catch (e) {
          nested.push(e.code);
        }
      }
    }
    into.set(bytes.subarray(offset, offset + into.length));
  }, bytes.length);
  inner = r;
  assert.deepEqual(Array.from(r.readColumns(["x"])[0].values), [4, 5, 6]);
  assert.ok(nested.length >= 4 && nested.every((c) => c === "DTA_INVALID"), nested.join());
  r.close();
});

test("a write sink that calls the package gets DTA_INVALID; the write finishes", { skip }, () => {
  const codes = [];
  const chunks = [];
  capped.writeDtaTo({ variables: [{ name: "y", values: [1, 2] }] }, (b) => {
    try {
      capped.openDta(small);
    } catch (e) {
      codes.push(e.code);
    }
    chunks.push(b.slice());
  });
  assert.ok(codes.length > 0 && codes.every((c) => c === "DTA_INVALID"));
  const back = ordinary.openDta(Buffer.concat(chunks));
  assert.deepEqual(back.readRows(0, 2), [[1], [2]]);
});

test("closing the last reader after a large read replaces the module instance", { skip }, () => {
  const bytes = ordinary.writeDta({ variables: [{ name: "l", type: "strL", values: ["a".repeat(8 << 20)] }] });
  capped.test.replaceAbove(4 << 20);
  try {
    survivor.close();
    const before = capped.test.generation();
    const a = capped.openDta(bytes);
    const b = capped.openDta(bytes);
    assert.equal(a.readColumns(["l"])[0].values[0].length, 8 << 20);
    assert.ok(capped.test.memoryBytes() > 8 << 20);
    a.close();
    assert.equal(capped.test.generation(), before, "another reader is still open");
    b.close();
    assert.equal(capped.test.generation(), before + 1);
    assert.ok(capped.test.memoryBytes() < 4 << 20, `${capped.test.memoryBytes()} bytes after replacing`);
    assert.equal(capped.test.openHandles(), 0);
  } finally {
    capped.test.replaceAbove(256 << 20);
    survivor = capped.openDta(small);
  }
  survivorReads();
});

test("a reader dropped without close() releases its handle, never a borrowed fd", { skip }, async () => {
  const { setFlagsFromString } = await import("node:v8");
  const { runInNewContext } = await import("node:vm");
  const fs = await import("node:fs");
  setFlagsFromString("--expose-gc");
  const gc = runInNewContext("gc");
  const path = join(mkdtempSync(join(tmpdir(), "dta-fd-")), "small.dta");
  fs.writeFileSync(path, small);
  const fd = fs.openSync(path, "r");
  const { openDtaFile } = require("../dist/node.js");
  try {
    const handles = capped.test.openHandles();
    (() => {
      const read = (into, offset) => fs.readSync(fd, into, 0, into.length, offset);
      new capped.DtaReader(read, small.length).readColumns(["x"]);
      openDtaFile(fd).readColumns(["x"]);
    })();
    assert.equal(capped.test.openHandles(), handles + 1);
    for (let i = 0; i < 20 && capped.test.openHandles() > handles; i++) {
      gc();
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(capped.test.openHandles(), handles, "the dropped reader's handle was released");
    const buf = Buffer.alloc(4);
    assert.equal(fs.readSync(fd, buf, 0, 4, 0), 4, "the borrowed fd is still open");
  } finally {
    fs.closeSync(fd);
  }
});
