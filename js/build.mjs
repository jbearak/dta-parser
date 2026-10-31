// Bundle the package to CommonJS, embedding the wasm module's bytes so
// consumers have no .wasm file to locate.
import { build } from "esbuild";

const common = { bundle: true, format: "cjs", target: "node24", platform: "node", loader: { ".wasm": "binary" } };
await build({ ...common, entryPoints: ["src/index.ts"], outfile: "dist/index.js" });
// The Node entry point uses the main one rather than embedding a second copy.
await build({ ...common, entryPoints: ["src/node.ts"], outfile: "dist/node.js", external: ["@jbearak/dta-parser"] });
// The formatting entry point has no wasm and no Node built-ins, so a
// webview or browser bundle can use it. (Built for the node platform
// only so esbuild marks its exports for Node's ESM `import`.)
await build({ ...common, entryPoints: ["src/format-entry.ts"], outfile: "dist/format.js" });
