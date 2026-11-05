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
