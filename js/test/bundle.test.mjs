// A consumer that bundles the package with esbuild to CommonJS, as the
// TypeScript tools do, can open and read a file.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

test("an esbuild CommonJS bundle works", async () => {
  const dir = mkdtempSync(join(tmpdir(), "dta-bundle-"));
  mkdirSync(join(dir, "node_modules", "@jbearak"), { recursive: true });
  symlinkSync(fileURLToPath(new URL("..", import.meta.url)), join(dir, "node_modules", "@jbearak", "dta-parser"));
  const fixture = fileURLToPath(new URL("../../compat/fixtures/pandas_118_le.dta", import.meta.url));
  writeFileSync(
    join(dir, "main.ts"),
    `import { openDtaFile } from "@jbearak/dta-parser/node";
     const r = openDtaFile(${JSON.stringify(fixture)});
     console.log(JSON.stringify(r.readRows(0, 1, ["i8", "s"])[0]));
     r.close();`,
  );
  await build({
    entryPoints: [join(dir, "main.ts")],
    outfile: join(dir, "out.js"),
    bundle: true,
    format: "cjs",
    platform: "node",
    target: "node20",
    absWorkingDir: dir,
    preserveSymlinks: true,
  });
  assert.equal(execFileSync(process.execPath, [join(dir, "out.js")], { encoding: "utf8" }).trim(), '[1,"a"]');
});
