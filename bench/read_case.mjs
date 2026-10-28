// One timed read with the npm package: print elapsed seconds.
//   node bench/read_case.mjs <task> <file>
// task: full, five, touch (full, then compare every string value), or
// window-start / window-end (200 rows of every variable at the first or
// last row).
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { openDtaFile } = require("../js/dist/node.js");

const [task, file] = process.argv.slice(2);
const start = process.hrtime.bigint();
const r = openDtaFile(file);
const all = r.variables.map((_, i) => i);
if (task === "full") r.readColumns(all);
else if (task === "touch") {
  let hits = 0;
  for (const c of r.readColumns(all)) if (c.kind === "string") for (const v of c.values) hits += v === "x" ? 1 : 0;
}
else if (task === "five") r.readColumns(["V1", "V100", "V200", "V300", "V400"]);
else if (task === "window-start") r.readRows(0, 200);
else if (task === "window-end") r.readRows(r.info.nobs - 200, 200);
r.close();
console.log((Number(process.hrtime.bigint() - start) / 1e9).toFixed(3));
