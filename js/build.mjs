// Bundle the package to CommonJS, embedding the wasm module's bytes so
// consumers have no .wasm file to locate.
import { build } from "esbuild";
import { readFileSync, rmSync } from "node:fs";
import { deflateRawSync } from "node:zlib";

// The module goes in deflated, after its length (src/wasm.ts inflates
// it): parsing 2.5 MB of base64 cost Node about 14 MB of memory, 0.7 MB
// about a quarter of that.
const deflated = {
  name: "deflated-wasm",
  setup(b) {
    b.onLoad({ filter: /dta\.wasm$/ }, ({ path }) => {
      const bytes = readFileSync(path);
      const size = Buffer.alloc(4);
      size.writeUInt32LE(bytes.length);
      return { contents: Buffer.concat([size, deflateRawSync(bytes, { level: 9 })]), loader: "binary" };
    });
  },
};
// A clean dist, so no file a source no longer makes is packed.
rmSync("dist", { recursive: true, force: true });
const common = { bundle: true, format: "cjs", target: "node24", platform: "node", loader: { ".wasm": "binary" }, plugins: [deflated] };
// The main entry takes the missing values, `dtaKey` and `formatValue`
// from the formatting entry's bundle at run time, so the package has one
// copy of each (plan 0021).
const formatEntry = {
  name: "format-entry",
  setup(b) {
    b.onResolve({ filter: /^\.\/format-entry$/ }, () => ({ path: "./format.js", external: true }));
  },
};
await build({ ...common, entryPoints: ["src/index.ts"], outfile: "dist/index.js", plugins: [deflated, formatEntry] });
// The Node entry point uses the main one rather than embedding a second copy.
await build({ ...common, entryPoints: ["src/node.ts"], outfile: "dist/node.js", external: ["@jbearak/dta-parser"] });
// The formatting entry point has no wasm and no Node built-ins, so a
// webview or browser bundle can use it. (Built for the node platform
// only so esbuild marks its exports for Node's ESM `import`.)
await build({ ...common, entryPoints: ["src/format-entry.ts"], outfile: "dist/format.js" });
