// The documentation's TypeScript and JavaScript examples run, and every
// export is documented.
//
// Each ```ts or ```js block of README.md, docs/guide/*.md and
// docs/typescript.md runs, in order, as one module per file, in a fresh
// temporary directory. Import lines are gathered at the top (merged per
// module) and each block is wrapped in braces, so blocks share files on
// disk but not variables. Blocks whose info string says `norun` are
// skipped. Node strips the type annotations.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const pkg = fileURLToPath(new URL("..", import.meta.url));
const root = join(pkg, "..");
const page = join(root, "docs", "typescript.md");
const skip = existsSync(page) ? false : "docs/typescript.md is not here";

function docFiles() {
  const guide = join(root, "docs", "guide");
  const pages = existsSync(guide) ? readdirSync(guide).filter((f) => f.endsWith(".md")).sort().map((f) => join(guide, f)) : [];
  return [join(root, "README.md"), ...pages, page];
}

/** [line, code] of each ts or js block. */
function codeBlocks(path) {
  const lines = readFileSync(path, "utf8").split("\n");
  const out = [];
  for (let i = 0; i < lines.length; ) {
    const m = /^(`{3,})\s*([A-Za-z]*)(.*)$/.exec(lines[i]);
    if (!m) {
      i++;
      continue;
    }
    let end = i + 1;
    while (end < lines.length && !lines[end].startsWith(m[1])) end++;
    if ((m[2] === "ts" || m[2] === "js") && !m[3].includes("norun")) out.push([i + 1, lines.slice(i + 1, end).join("\n")]);
    i = end + 1;
  }
  return out;
}

/** One module from a page's blocks: imports merged at the top, each block in its own scope. */
function moduleOf(blocks) {
  const named = new Map();
  const other = new Set();
  const bodies = [];
  for (const [line, code] of blocks) {
    const body = [];
    for (const text of code.split("\n")) {
      const m = /^import\s+(type\s+)?\{([^}]*)\}\s+from\s+("[^"]+");?\s*$/.exec(text);
      if (m) {
        const names = named.get(m[3]) ?? new Set();
        for (const n of m[2].split(",").map((s) => s.trim()).filter(Boolean)) names.add(m[1] && !n.startsWith("type ") ? `type ${n}` : n);
        named.set(m[3], names);
      } else if (/^import\s/.test(text)) {
        other.add(text);
      } else {
        body.push(text);
      }
    }
    bodies.push(`// block at line ${line}\n{\n${body.join("\n")}\n}`);
  }
  const imports = [...named].map(([from, names]) => `import { ${[...names].join(", ")} } from ${from};`);
  return [...imports, ...other, ...bodies].join("\n");
}

for (const path of docFiles()) {
  const name = path.slice(root.length + 1);
  test(`examples in ${name} run`, { skip }, () => {
    const blocks = codeBlocks(path);
    if (blocks.length === 0) return;
    // Inside the package, so `@jbearak/dta-parser` resolves to it.
    const dir = mkdtempSync(join(pkg, ".docs-"));
    const work = mkdtempSync(join(tmpdir(), "dta-docs-"));
    try {
      const file = join(dir, "example.mts");
      writeFileSync(file, moduleOf(blocks));
      const run = spawnSync(process.execPath, [file], { cwd: work, encoding: "utf8" });
      assert.equal(run.status, 0, `${name}:\n${run.stderr}`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
      rmSync(work, { recursive: true, force: true });
    }
  });
}

test("every export has TSDoc and appears in docs/typescript.md", { skip }, () => {
  const text = readFileSync(page, "utf8");
  const mentioned = (n) => text.includes(`\`${n}`) || text.includes(`.${n}(`) || text.includes(`{ ${n}`) || text.includes(`, ${n}`);
  for (const src of ["index.ts", "node.ts", "format.ts"]) {
    const lines = readFileSync(join(pkg, "src", src), "utf8").split("\n");
    lines.forEach((line, i) => {
      const m = /^export\s+(?:declare\s+)?(?:function|class|const|interface|type)\s+(\w+)/.exec(line);
      if (!m) return;
      let k = i - 1;
      while (k >= 0 && lines[k].trim() === "") k--;
      assert.ok(lines[k]?.trim().endsWith("*/"), `${src}: ${m[1]} has no TSDoc`);
      assert.ok(mentioned(m[1]), `docs/typescript.md does not mention ${m[1]}`);
    });
  }
  for (const entry of ["../dist/index.js", "../dist/node.js"]) {
    for (const n of Object.keys(require(entry))) assert.ok(mentioned(n), `docs/typescript.md does not mention ${n}`);
  }
  // The reader's public methods.
  const index = readFileSync(join(pkg, "src", "index.ts"), "utf8").split("\n");
  index.forEach((line, i) => {
    const m = /^  (\w+)\(.*\{$/.exec(line);
    if (!m || m[1] === "constructor") return;
    assert.ok(index[i - 1].trim().endsWith("*/"), `DtaReader.${m[1]} has no TSDoc`);
    assert.ok(mentioned(m[1]), `docs/typescript.md does not mention ${m[1]}`);
  });
});
