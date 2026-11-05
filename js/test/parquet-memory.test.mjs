// Parquet reads keep module memory bounded: with the test build of the
// module (build/dta-test.wasm, memory capped at 64 MiB) and a 16 MiB
// budget per call, a read whose output is several times the cap
// succeeds and gives what the ordinary build gives (plan 0018: the
// 64 MiB per-call cap of .dta reads, and no file copied whole into the
// module).
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
before(async () => {
  if (skip) return;
  const dir = mkdtempSync(join(tmpdir(), "dta-pq-memory-"));
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
  process.env.DTA_TEST_PARQUET_BUDGET = String(16 << 20);
  capped = require(out);
});

test("a read of several times the module's memory stays within it", { skip }, () => {
  const n = 2_000_000;
  const variables = [0, 1, 2, 3, 4].map((k) => ({ name: `x${k}`, values: Float64Array.from({ length: n }, (_, i) => i * (k + 1.5)) }));
  variables.push({ name: "w", values: Array.from({ length: n }, (_, i) => `word ${i % 1000}`) });
  const bytes = ordinary.writeParquet({ variables }, { rowGroupSize: 500_000 });
  const r = capped.openParquet(bytes);
  const got = r.readColumns(r.variables.map((_, i) => i));
  assert.ok(capped.test.memoryBytes() <= 64 << 20, `${capped.test.memoryBytes()}`);
  const want = ordinary.openParquet(bytes).readColumns(r.variables.map((_, i) => i));
  assert.deepEqual(got, want);
  // And in windows that cut row groups.
  const [x] = r.readColumns(["x3"], { start: 499_000, count: 1_200_000 });
  assert.deepEqual(x.values, want[3].values.subarray(499_000, 1_699_000));
  r.close();
});

test("a few large values among many small ones are read within the budget", { skip }, () => {
  // The read is planned by the footer's average sizes: 100 values of
  // 1 MiB among 200,000 empty ones average about 530 bytes a row, and
  // one planned call would gather all 100 MiB. The module counts the text
  // as it gathers it, and the rows are read again in smaller calls.
  const n = 200_000;
  const big = new Uint8Array(1 << 20).map((_, i) => (i * 7) % 251);
  const values = Array.from({ length: n }, (_, i) => (i >= 1000 && i < 1100 ? big : new Uint8Array(0)));
  const bytes = ordinary.writeParquet({ variables: [{ name: "b", type: "binary", values }] });
  const r = capped.openParquet(bytes);
  const [b] = r.readColumns(["b"]);
  assert.ok(capped.test.memoryBytes() <= 64 << 20, `${capped.test.memoryBytes()}`);
  assert.equal(b.values.length, n);
  for (let i = 0; i < n; i++) {
    const want = i >= 1000 && i < 1100 ? big.length : 0;
    if (b.values[i].length !== want) assert.fail(`row ${i}: ${b.values[i].length} bytes`);
  }
  assert.deepEqual(b.values[1050], big);
  r.close();
  // One value larger than a call may hold.
  const huge = ordinary.writeParquet({ variables: [{ name: "h", type: "binary", values: [new Uint8Array(17 << 20)] }] });
  const h = capped.openParquet(huge);
  assert.throws(() => h.readColumns(["h"]), (e) => e.code === "DTA_TOO_LARGE" && /row 0/.test(e.message));
  h.close();
});

test("a few large dictionary values repeated over many rows are read within the budget", { skip }, () => {
  // Three distinct values of 300 KiB over 1,000 rows: the chunk is a
  // 900 KiB dictionary and codes, small to decode, but each row of a
  // binary column is copied out in full, about 300 MB in all.
  const n = 1000;
  const distinct = [0, 1, 2].map((k) => new Uint8Array(300 << 10).map((_, i) => (i * (k + 3)) % 251));
  const values = Array.from({ length: n }, (_, i) => distinct[i % 3]);
  const bytes = ordinary.writeParquet({ variables: [{ name: "b", type: "binary", values }] });
  const r = capped.openParquet(bytes);
  const [chunk] = r.variables[0].chunks;
  // Dictionary-coded throughout: the chunk is little more than its dictionary.
  assert.ok(chunk.dictionaryPageBytes > 0 && chunk.uncompressedBytes < 1 << 20, JSON.stringify(chunk));
  const [b] = r.readColumns(["b"]);
  assert.ok(capped.test.memoryBytes() <= 64 << 20, `${capped.test.memoryBytes()}`);
  for (let i = 0; i < n; i++) {
    if (b.values[i].length !== distinct[i % 3].length || b.values[i][7] !== distinct[i % 3][7]) assert.fail(`row ${i}`);
  }
  r.close();
});
