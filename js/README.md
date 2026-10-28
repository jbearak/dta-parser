# @jbearak/dta-parser

Read Stata `.dta` files (releases 104 to 119) and write release 118, in
Node, synchronously. The format is implemented once, in Rust, and runs
here as an embedded wasm module.

```ts
import { openDta, formatValue, MISSING, isMissing } from "@jbearak/dta-parser";
import { openDtaFile, writeDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");       // or openDta(bytes)
r.info;                                    // release, nobs, label, timestamp, encoding, sortedBy
r.variables;                               // name, type, format, label, valueLabels
const [age, region] = r.readColumns(["age", "region"], { start: 0, count: 1000 });
const rows = r.readRows(0, 20);            // cells: number | string | Uint8Array | Missing
r.valueLabels("yesno")?.get(MISSING[".d"]);
formatValue(rows[0][0], r.variables[0].format, r.valueLabels(r.variables[0].valueLabels));
r.close();

writeDtaFile("out.dta", {
  label: "Example",
  valueLabels: { yesno: new Map([[0, "No"], [1, "Yes"], [MISSING[".d"], "Don't know"]]) },
  variables: [
    { name: "answer", type: "byte", values: [1, 0, MISSING[".d"]], valueLabels: "yesno" },
    { name: "note", values: ["a", "b", "c"] },
  ],
});
```

A file is read only as far as asked: opening reads the header and the
variable descriptors, and `readColumns` decodes just the requested
variables and rows. Each call into the module holds at most 64 MiB of
decoded data. See `docs/migration.md` for moving from 0.x.
