// Both packages packed and installed into an empty project, as a user
// without the repository would install them (plan 0021): every entry
// imports, from CommonJS and ESM, and the dist holds what it should.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL("..", import.meta.url));
const dtaRoot = join(here, "..");
const npm = process.platform === "win32" ? "npm.cmd" : "npm";

test("the packed packages install and every entry imports", { timeout: 300_000 }, () => {
  const work = mkdtempSync(join(tmpdir(), "datakit-pack-"));
  const env = { ...process.env, npm_config_cache: join(work, ".npm"), npm_config_update_notifier: "false" };
  const pack = (dir) => execFileSync(npm, ["pack", "--pack-destination", work, "--silent"], { cwd: dir, env, encoding: "utf8" }).trim().split("\n").pop();
  const dta = join(work, pack(dtaRoot));
  const dk = join(work, pack(here));
  const app = join(work, "app");
  execFileSync("mkdir", [app]);
  writeFileSync(join(app, "package.json"), JSON.stringify({ name: "app", version: "1.0.0", private: true }));
  execFileSync(npm, ["install", "--no-audit", "--no-fund", "--offline", "--ignore-scripts", dta, dk], { cwd: app, env, stdio: "pipe" });
  const files = execFileSync("tar", ["-tzf", dk], { encoding: "utf8" }).split("\n").filter(Boolean).sort();
  assert.ok(files.includes("package/dist/index.js") && files.includes("package/dist/node.js") && files.includes("package/THIRD-PARTY-NOTICES"), files.join(" "));
  assert.ok(!files.some((f) => f.includes("/src/") || f.includes("/test/") || f.endsWith(".wasm")), files.join(" "));
  const dtaFiles = execFileSync("tar", ["-tzf", dta], { encoding: "utf8" });
  assert.ok(!dtaFiles.includes("datakit") && !dtaFiles.includes("parquet"), dtaFiles);
  // dta-parser's bundle has no Parquet code.
  assert.ok(!readFileSync(join(app, "node_modules", "@jbearak", "dta-parser", "dist", "index.js"), "utf8").includes("pq_open"));
  const cjs = `
    const dk = require("@jbearak/datakit");
    const node = require("@jbearak/datakit/node");
    const dp = require("@jbearak/dta-parser");
    const fs = require("node:fs"), path = require("node:path");
    if (dk.MISSING !== dp.MISSING) throw new Error("two MISSINGs");
    const f = path.join(${JSON.stringify(work)}, "x.parquet");
    node.saveParquet({ variables: [{ name: "x", values: [1, dk.MISSING[".a"]] }] }, f);
    const back = node.readParquet(f);
    node.saveDta(back, f + ".dta");
    console.log(JSON.stringify(Array.from(node.readDta(f + ".dta").variables[0].values.values, dk.missingCode)));`;
  const run = spawnSync(process.execPath, ["-e", cjs], { cwd: app, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(run.stdout.trim(), "[0,2]");
  const mjs = join(app, "main.mjs");
  writeFileSync(mjs, `import { openParquet, writeParquet, readDataset } from "@jbearak/datakit";\nimport { readFixedWidth } from "@jbearak/datakit/node";\nconsole.log(typeof openParquet, typeof writeParquet, typeof readDataset, typeof readFixedWidth);`);
  const esm = spawnSync(process.execPath, [mjs], { cwd: app, encoding: "utf8" });
  assert.equal(esm.status, 0, esm.stderr);
  assert.equal(esm.stdout.trim(), "function function function function");
});
