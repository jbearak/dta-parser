// The subpaths: `using` closes readers (but never a borrowed fd), the
// /format entry point carries no wasm and no Node built-ins, and every
// subpath's types resolve under old and new module resolution.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { closeSync, fstatSync, mkdtempSync, mkdirSync, openSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { openDtaFile } = require("../dist/node.js");
const pkg = fileURLToPath(new URL("..", import.meta.url));
const fixture = fileURLToPath(new URL("../../compat/fixtures/pandas_118_le.dta", import.meta.url));

test("using closes a reader opened by path", () => {
  let reader;
  {
    using r = openDtaFile(fixture);
    reader = r;
    assert.equal(r.readRows(0, 1, ["i8"])[0][0], 1);
  }
  assert.throws(() => reader.readRows(0, 1, ["i8"]), /closed/);
});

test("using leaves a borrowed fd open", () => {
  const fd = openSync(fixture, "r");
  try {
    {
      using r = openDtaFile(fd);
      r.readRows(0, 1);
    }
    assert.ok(fstatSync(fd).size > 0);
    using again = openDtaFile(fd);
    assert.equal(again.readRows(0, 1, ["i8"])[0][0], 1);
  } finally {
    closeSync(fd);
  }
});

test("the /format bundle has no wasm and no Node built-ins", () => {
  const js = readFileSync(join(pkg, "dist", "format.js"), "utf8");
  assert.doesNotMatch(js, /WebAssembly|\0asm|AGFzbQ/);
  assert.doesNotMatch(js, /require\(|from ["']node:/);
  const format = require("../dist/format.js");
  assert.equal(format.formatValue(1.5, "%9.2f"), "1.50");
  assert.equal(format.formatValue(format.MISSING[".a"], "%9.0g"), ".a");
});

test("subpath types resolve under node10 and bundler resolution, with readColumns' overloads", () => {
  const dir = mkdtempSync(join(tmpdir(), "dta-types-"));
  mkdirSync(join(dir, "node_modules", "@jbearak"), { recursive: true });
  symlinkSync(pkg, join(dir, "node_modules", "@jbearak", "dta-parser"));
  writeFileSync(
    join(dir, "main.ts"),
    `import { openDta } from "@jbearak/dta-parser";
     import { openDtaFile } from "@jbearak/dta-parser/node";
     import { formatValue, type Missing } from "@jbearak/dta-parser/format";
     import type { Column, DictionaryColumn, DtaReader } from "@jbearak/dta-parser";
     const m: Missing["missing"] = ".z";
     export function overloads(r: DtaReader) {
       const plain: Column[] = r.readColumns([0]);
       const ranged: Column[] = r.readColumns([0], { start: 1, count: 2 });
       const coded: (Column | DictionaryColumn)[] = r.readColumns([0], { strings: "dictionary" });
       // @ts-expect-error: a dictionary read may hold DictionaryColumns
       const wrong: Column[] = r.readColumns([0], { strings: "dictionary" });
       return [plain, ranged, coded, wrong];
     }
     export const used = [openDta, openDtaFile, formatValue, m];`,
  );
  // TypeScript 7 dropped node10 resolution, which projects on
  // "module": "commonjs" with TypeScript 5 still use.
  const checks = [
    ["typescript-5", "commonjs", "node10"],
    ["typescript", "esnext", "bundler"],
  ];
  for (const [ts, module, resolution] of checks) {
    const tsc = join(pkg, "node_modules", ts, "bin", "tsc");
    execFileSync(process.execPath, [tsc, "--noEmit", "--strict", "--skipLibCheck", "--module", module,
      "--moduleResolution", resolution, "--preserveSymlinks", join(dir, "main.ts")], { encoding: "utf8", cwd: dir });
  }
});
