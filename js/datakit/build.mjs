// Bundle the package to CommonJS, embedding the wasm module's bytes so
// consumers have no .wasm file to locate (as dta-parser's build does).
// The glue it shares with dta-parser (../src/wasm-core.ts and the helpers
// it uses) is bundled in; @jbearak/dta-parser itself is a peer dependency,
// loaded at run time.
import { build } from "esbuild";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { deflateRawSync } from "node:zlib";

const deflated = {
  name: "deflated-wasm",
  setup(b) {
    b.onLoad({ filter: /datakit\.wasm$/ }, ({ path }) => {
      const bytes = readFileSync(path);
      const size = Buffer.alloc(4);
      size.writeUInt32LE(bytes.length);
      return { contents: Buffer.concat([size, deflateRawSync(bytes, { level: 9 })]), loader: "binary" };
    });
  },
};
// dta-parser's glue that datakit shares (plan 0021), copied in as
// src/_shared (not committed) so the bundle and its types have them.
mkdirSync("src/_shared", { recursive: true });
for (const f of ["errors", "inflate", "shared", "tagged", "values", "wasm-core"]) {
  const text = readFileSync(`../src/${f}.ts`, "utf8");
  writeFileSync(`src/_shared/${f}.ts`, `// Copied from js/src/${f}.ts by build.mjs; edit that file.\n\n${text}`);
}
// A clean dist, so no file a source no longer makes is packed.
rmSync("dist", { recursive: true, force: true });
const external = ["@jbearak/dta-parser", "@jbearak/dta-parser/format", "@jbearak/dta-parser/node"];
const common = { bundle: true, format: "cjs", target: "node24", platform: "node", loader: { ".wasm": "binary" }, plugins: [deflated] };
await build({ ...common, entryPoints: ["src/index.ts"], outfile: "dist/index.js", external });
// The Node entry point uses the main one (and its module instance).
await build({ ...common, entryPoints: ["src/node.ts"], outfile: "dist/node.js", external: [...external, "@jbearak/datakit"] });
