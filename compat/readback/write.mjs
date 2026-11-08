// Save every input again with the npm package's openDta and
// writeDtaFile, for compat/readback/check.py to read with other readers.
// Inputs are the fixtures in compat/fixtures, and strls.dta and binary.dta
// in compat/readback.
//   node compat/readback/write.mjs <out-dir>
import { mkdirSync, readFileSync, readdirSync } from "node:fs";
import { createRequire } from "node:module";
import { basename, join } from "node:path";

const require = createRequire(import.meta.url);
const { openDta, missingValue } = require("../../js/dist/index.js");
const { writeDtaFile } = require("../../js/dist/node.js");

const out = process.argv[2];
mkdirSync(out, { recursive: true });
const inputs = readdirSync("compat/fixtures")
  .filter((f) => f.endsWith(".dta"))
  .sort()
  .map((f) => join("compat/fixtures", f));
inputs.push("compat/readback/strls.dta", "compat/readback/binary.dta");
for (const path of inputs) {
  const name = basename(path);
  const r = openDta(readFileSync(path));
  const cols = r.readColumns(r.variables.map((_, i) => i));
  const valueLabels = {};
  for (const v of r.variables) {
    const labels = v.valueLabels && r.valueLabels(v.valueLabels);
    if (labels) valueLabels[v.valueLabels] = labels;
  }
  const variables = r.variables.map((v, i) => {
    const c = cols[i];
    const common = { name: v.name, format: v.format, label: v.label, valueLabels: valueLabels[v.valueLabels] ? v.valueLabels : undefined };
    if (c.kind === "string") return { ...common, type: v.type === "strL" ? "strL" : undefined, values: c.values };
    return { ...common, type: v.type, values: Array.from(c.values, (x, k) => (c.missing[k] ? missingValue(c.missing[k]) : x)) };
  });
  writeDtaFile(join(out, name), {
    label: r.info.label,
    notes: r.notes(),
    characteristics: r.characteristics(),
    sortedBy: r.info.sortedBy,
    timestamp: r.info.timestamp,
    variables,
    valueLabels,
  });
}
