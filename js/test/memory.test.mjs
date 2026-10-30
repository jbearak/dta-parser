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
    outfile: out,
    loader: { ".wasm": "binary" },
  });
  const big = require(out);
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
