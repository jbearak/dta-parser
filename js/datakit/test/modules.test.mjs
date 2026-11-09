// The two packages' modules and entries (plan 0021): each module exports
// what its wrappers call and nothing of the other's; the root entry needs
// no Node API and no .dta module; MISSING is one set of objects across
// entries, packages and copies; datakit gives its module's memory back.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import vm from "node:vm";
import { build } from "esbuild";

const require = createRequire(import.meta.url);
const here = fileURLToPath(new URL("..", import.meta.url));
const dtaRoot = join(here, "..");

/** A bundle of `entry` with its module, exporting its wasm `test` too. */
async function withTest(srcDir, entry) {
  const out = join(mkdtempSync(join(tmpdir(), "datakit-mod-")), "bundle.js");
  await build({
    stdin: { contents: `export * from ${JSON.stringify(join(srcDir, entry))}; export { test } from ${JSON.stringify(join(srcDir, "wasm.ts"))};`, resolveDir: srcDir, loader: "ts" },
    bundle: true,
    format: "cjs",
    platform: "node",
    target: "node24",
    outfile: out,
    loader: { ".wasm": "binary" },
    nodePaths: [join(here, "node_modules")],
  });
  return require(out);
}

/** The export names a wrappers file calls (`core.exports.name`). */
const called = (file) => new Set([...readFileSync(file, "utf8").matchAll(/core\.exports\.(\w+)/g)].map((m) => m[1]));

test("each module exports what its wrappers call, and nothing of the other's", async () => {
  const dta = await withTest(join(dtaRoot, "src"), "index.ts");
  const dk = await withTest(join(here, "src"), "index.ts");
  const common = ["memory", "dta_alloc", "dta_free", "dta_error", "dta_error_kind", "dta_result_len"];
  const shared = called(join(dtaRoot, "src", "wasm-core.ts"));
  for (const [mod, file] of [[dta, join(dtaRoot, "src", "wasm.ts")], [dk, join(here, "src", "wasm.ts")]]) {
    const names = new Set(mod.test.exportNames());
    const wants = new Set([...common, ...called(file), ...shared]);
    // dta_test_set is in test builds only; neither ordinary module has it.
    wants.delete("dta_test_set");
    // zstd-sys exports the C library functions libzstd uses in wasm.
    const ours = [...names].filter((n) => !n.startsWith("__") && !n.startsWith("rust_zstd_wasm_shim_"));
    assert.deepEqual(ours.sort(), [...wants].sort(), file);
  }
  assert.ok(dta.test.exportNames().every((n) => !n.startsWith("pq_") && n !== "dta_fixed_width"));
  assert.ok(dk.test.exportNames().every((n) => !["dta_open", "dta_read", "dta_write_begin"].includes(n)));
});

test("datakit gives its module's memory back after a conversion, unless a Parquet reader is open", async () => {
  const dk = await withTest(join(here, "src"), "index.ts");
  const data = new TextEncoder().encode("0011 2\n".repeat(100_000));
  const setup = "DATA ;\nINPUT ID 1-3 SEX 4 KIDS 5-6 ;\nRUN ;";
  const g0 = dk.test.generation();
  dk.convertFixedWidth(data, [setup]);
  assert.equal(dk.test.generation(), g0 + 1);
  const r = dk.openParquet(dk.writeParquet({ variables: [{ name: "x", values: [1] }] }));
  dk.convertFixedWidth(data, [setup]);
  assert.equal(dk.test.generation(), g0 + 1);
  assert.deepEqual(r.readRows(0, 1), [[1]]);
  r.close();
});

test("the root entry uses no Node API and loads no .dta module", async () => {
  // Bundled for a neutral platform: a `node:` import (or any Node
  // built-in) fails the build.
  const out = join(mkdtempSync(join(tmpdir(), "datakit-neutral-")), "root.js");
  await build({
    entryPoints: [join(here, "src", "index.ts")],
    bundle: true,
    format: "cjs",
    platform: "neutral",
    // The oldest Node the package supports, as the published bundles
    // (esbuild's default target uses Uint8Array.fromBase64, which Node 24 lacks).
    target: "node24",
    mainFields: ["main"],
    outfile: out,
    loader: { ".wasm": "binary" },
    nodePaths: [join(here, "node_modules")],
    plugins: [
      {
        name: "no-node",
        setup(b) {
          b.onResolve({ filter: /^(node:|fs$|path$|os$)/ }, (a) => ({ errors: [{ text: `the root entry imports ${a.path}` }] }));
          b.onResolve({ filter: /^@jbearak\/dta-parser$/ }, () => ({ errors: [{ text: "the root entry imports dta-parser's .dta module" }] }));
        },
      },
    ],
  });
  // Run it with no `require` and no `process`: what a browser gives.
  const sandbox = { module: { exports: {} }, TextDecoder, TextEncoder, WebAssembly, console, FinalizationRegistry, Symbol, Object, Map, Set, Error, globalThis: undefined };
  sandbox.exports = sandbox.module.exports;
  sandbox.globalThis = sandbox;
  vm.runInNewContext(readFileSync(out, "utf8"), sandbox);
  const dk = sandbox.module.exports;
  const { dta, warnings } = dk.convertFixedWidth(new TextEncoder().encode("0011 2\n"), ["DATA ;\nINPUT ID 1-3 SEX 4 KIDS 5-6 ;\nRUN ;"]);
  assert.deepEqual(Array.from(warnings), []);
  assert.equal(String.fromCharCode(...dta.subarray(0, 11)), "<stata_dta>");
  const pq = dk.writeParquet({ variables: [{ name: "x", values: [1, dk.MISSING[".a"]] }] });
  assert.equal(dk.openParquet(pq).readRows(1, 1)[0][0], dk.MISSING[".a"]);
  // And the published bundle: importing it loads no .dta module.
  const run = spawnSync(process.execPath, ["-e", `require(${JSON.stringify(join(here, "dist", "index.js"))}); console.log(Object.keys(require.cache).some((k) => k.endsWith(${JSON.stringify(join("js", "dist", "index.js"))})))`], { encoding: "utf8" });
  assert.equal(run.stdout.trim(), "false", run.stderr);
});

test("MISSING is one set of objects across entries, packages and installed copies", () => {
  const dp = require("@jbearak/dta-parser");
  const fmt = require("@jbearak/dta-parser/format");
  const dk = require("../dist/index.js");
  for (const other of [fmt, dk]) {
    assert.equal(other.MISSING, dp.MISSING);
    assert.equal(other.MISSING[".r"], dp.MISSING[".r"]);
  }
  assert.equal(fmt.dtaKey, dp.dtaKey);
  assert.equal(dk.dtaKey, dp.dtaKey);
  assert.equal(fmt.stataKeys, dp.stataKeys);
  // Labels read through datakit are found with dta-parser's keys.
  const labels = dk.openParquet(dk.writeParquet({ valueLabels: { s: new Map([[dp.MISSING[".r"], "Refused"]]) }, variables: [{ name: "x", valueLabels: "s", values: [1] }] })).valueLabels("s");
  assert.equal(labels.get(dp.MISSING[".r"]), "Refused");
  assert.equal(labels.get(fmt.MISSING[".r"]), "Refused");

  // Two copies of dta-parser installed in different directories, in one process.
  const copies = [1, 2].map((k) => {
    const d = mkdtempSync(join(tmpdir(), `dta-copy-${k}-`));
    cpSync(join(dtaRoot, "package.json"), join(d, "package.json"));
    cpSync(join(dtaRoot, "dist"), join(d, "dist"), { recursive: true });
    return require(join(d, "dist", "index.js"));
  });
  assert.equal(copies[0].MISSING[".a"], copies[1].MISSING[".a"]);
  assert.equal(copies[0].MISSING[".a"], dp.MISSING[".a"]);
  const bytes = copies[0].writeDta({ valueLabels: { s: new Map([[copies[0].MISSING[".d"], "DK"]]) }, variables: [{ name: "x", valueLabels: "s", values: [1] }] });
  assert.equal(copies[1].openDta(bytes).valueLabels("s").get(dp.MISSING[".d"]), "DK");
});

test("a foreign value under the registry's key is left alone", () => {
  const script = join(mkdtempSync(join(tmpdir(), "datakit-foreign-")), "foreign.cjs");
  writeFileSync(
    script,
    `globalThis[Symbol.for("@jbearak/dta-parser/missing/v1")] = { ".": "not ours" };
     const dp = require(${JSON.stringify(join(dtaRoot, "dist", "index.js"))});
     const fmt = require(${JSON.stringify(join(dtaRoot, "dist", "format.js"))});
     if (dp.MISSING[".a"].missing !== ".a" || !Object.isFrozen(dp.MISSING[".a"])) throw new Error("bad MISSING");
     if (globalThis[Symbol.for("@jbearak/dta-parser/missing/v1")][\".\"] !== "not ours") throw new Error("overwritten");
     console.log(dp.MISSING === fmt.MISSING);`,
  );
  const run = spawnSync(process.execPath, [script], { encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  // One copy at run time either way: the root entry takes /format's.
  assert.equal(run.stdout.trim(), "true");
});
