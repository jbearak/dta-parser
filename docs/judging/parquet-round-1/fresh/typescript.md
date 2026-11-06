# TypeScript Parquet docs check

Only source of how to use the library: `docs.md`. I read the README, `docs/parquet.md`, the TypeScript Parquet sections and the API reference.
I did not read the library's source, tests or other docs.
Reading `scripts/build-wasm.sh`'s header comment to build the package was the only checkout file I opened apart from running the build.
Node v26.12.1, npm 11.20.0. Every script below ran and is in this directory.
Full code for each task is appended at the end (`t1.ts`, `t2_5.ts`, `t6.ts`, `t7_9.ts`, `t11_write.R`, `t11.ts`).

## Build and install (before task 1)

Steps run:
1. `scripts/build-wasm.sh`. The docs say `rustup target add wasm32-unknown-unknown` and then this script.
   - **First attempt failed.** `error[E0463]: can't find crate for std ... the wasm32-unknown-unknown target may not be installed`.
   - `rustup target list --installed` already showed the wasm target. The `cargo` and `rustc` on PATH were Homebrew's (`/opt/homebrew/bin`), which have no wasm target.
   - I fixed it by putting rustup's toolchain first: `C=$(rustup which cargo); RUSTC=$(rustup which rustc) CARGO=$C PATH="$(dirname $C):$PATH" scripts/build-wasm.sh`.
   - The script's header comment says "CARGO may point at a rustup toolchain's cargo when the default one has no wasm target". The docs' Install section and Troubleshooting do not say this.
   - Troubleshooting only says to run `rustup target add` "with the same rustup default (or RUSTUP_TOOLCHAIN) the script uses".
   - Not mentioned in the docs: the build also needs Homebrew's llvm and clang for libzstd. It found them here.
   - The build took more than 10 minutes. The docs give no time.
2. `cd js && npm ci && npm run build` succeeded. npm warns that esbuild's install script is not approved. This had no effect.
3. In scratch: `npm init -y; npm pkg set type=module; npm install /private/tmp/claude-501/gate2/fresh/typescript/checkout/js`. This matches the docs' `npm install /path/to/dta-parser/js`.
   - To run `.ts` files directly with Node 26 I needed `"type": "module"` in my own package.json. That is my own setup, not a doc problem.

## Task results

### 1. Install and load: succeeded
`t1.ts` imported `openParquet`, `openParquetAsync`, `writeParquet` and `toDate` from `@jbearak/dta-parser`. It imported `openParquetFile`, `writeParquetFile`, `openDtaFile` and `writeDtaFile` from `/node`. All are functions.
- Docs: "Parquet needs nothing beyond this package". That is true. Nothing to install beyond the build above.

### 2. Write a mixed table and read it back: succeeded
Seen from `r.variables[i]` (`type`, `physicalType`, `logicalType`, `columnKind`) and `readColumns`:

| column | written as | type | physical | logical | column kind | values |
|---|---|---|---|---|---|---|
| id | `long` | long | INT32 | (empty) | number | `Float64Array` |
| x | `double` | double | DOUBLE | | number | `Float64Array` |
| name | strings | string | BYTE_ARRAY | STRING | string | `Array` of strings |
| flag | `bool` | bool | BOOLEAN | | number | `Float64Array` of 0 and 1 |
| d | `date` | date | INT32 | DATE | number | `Float64Array`, unit `day` |
| ts | `timestamp` | timestamp | INT64 | `TIMESTAMP(MICROS, local)` | number | `Float64Array`, unit `us`, no timeZone |

- Nulls: `missing[i]` is 1 in numbers; in `readRows` a null shows as `{ missing: '.' }`, including nulls in a text column.
- Docs: there is no "usual table type" in TypeScript. The docs describe typed arrays per column, and that is what you get.
- Doc gaps:
  - The `logicalType` strings, such as `TIMESTAMP(MICROS, local)`, are not listed. The docs show only `"INT(8, signed)"` as an example.
  - `logicalType` is an empty string, not undefined, when a column has no logical type.

### 3. Two columns in reverse order; unknown name: succeeded
- `readColumns(["name","id"])` gave `[string column, number column]`, in the order asked. `readRows(0,2,["name","id"])` gave `[['a',1],['b',2]]`.
- An unknown name throws `RangeError`, code `DTA_OUT_OF_RANGE`, with the message `no variable "weight"; the file's are "id", "x", "name", "flag", "d", "ts"`.
- An out-of-range index throws the same error: `no variable 9; the file's are ...`.
- This matches the docs. The parquet.md TS table also lists this message.

### 4. Rows 3 to 5; past the end: succeeded
- "Rows 3 to 5" is ambiguous. The docs use 0-based `start`. `readColumns(["id"],{start:2,count:3})` gave `[3,4,5]`, and `readRows(2,3)` gave the three rows.
- Past the end, `readRows(4,5)` and `readRows(6,1)` threw `RangeError` / `DTA_OUT_OF_RANGE`: `rows 4 to 9 are outside 0 to 6`.
- `readColumns` with `{start:4,count:5}` threw the same. `readColumns` with `{start:4}` and no count read to the end: `[5,6]`.
- This matches the docs.
- Doc gap: the message `rows 4 to 9 are outside 0 to 6` writes the end as exclusive. The Troubleshooting entry shows "rows 0 to 10 are outside 0 to 6" for the same case, so it is consistent, but neither says "exclusive".

### 5. Metadata without data: succeeded
- Columns and types: `r.variables` gives `name:type:physicalType:logicalType:columnKind`.
- Row count: `info.nobs` was 6.
- Row groups: `info.rowGroups` was `[{firstRow:0,rows:6,compressedBytes:277,uncompressedBytes:288}]`.
- Compression: `info.compression` was `['snappy']`. Per column and group, `variables[i].chunks[g].codec` was `snappy`, with `encodings`, `min`, `max` and `nullCount` too.
- Key-value metadata: `info.keyValue` gave `[{key:'dta',bytes:13},{key:'ARROW:schema',bytes:664}]`. `r.keyValue("dta")` gave `{"version":1}`.
- Doc gaps:
  - `info.keyValue` has only the key and the size in bytes. You need `r.keyValue(key)` for the text. That is shown only in one table row, and the example prints keys only.
  - `keyValue` of a missing key returns `undefined`, which the docs do not say.

### 6. `.dta` to Parquet, then labels and categorical: partly
- Wrote `t6.dta` with `writeDtaFile`: a `byte` column `region` with a value-label set, variable labels on all three columns, and a data label. I then ran the docs' `.dta`-to-Parquet recipe with `survey.dta` swapped for `t6.dta`.
- It worked unchanged. Read back:
  - Variable label: `region.label` is "Region of residence".
  - Label set: `region.valueLabels` is `"region"`.
  - Value labels: `r.valueLabels("region")` is `Map {1=>North, 2=>South, 3=>West}`.
  - Text of code 2: `labels.get(2)` is "South".
  - Data label: `r.info.label` is "Task 6 data".
- **The categorical step is not shown.** The docs show no way to turn a numeric column plus its labels into a categorical.
  - The docs say "A categorical (a `DictionaryColumn`) already holds its text", but that is for files that stored a categorical.
  - `readColumns(["region"], {strings:"dictionary"})` on the numeric column is accepted silently and still gives `kind:'number'`.
  - What I did: built the levels from the `valueLabels` Map, mapped the codes to level indexes, and wrote a new file with `type:"categorical", levels, values`. Reading that gave `DictionaryColumn {codes:[0,1,1,2,0,0], values:['North','South','West'], missing:[0,0,0,0,0,1]}`.
  - Doc gap: add a recipe, or say there is no direct conversion.
- Doc gap: the recipe does not say that labels go through `dta.valueLabels(name)` only for names you list. A set you leave out of `valueLabels:` is lost.

### 7. Date, timestamp with and without a zone: succeeded
Written with `writeParquet` and read with `openParquet` (`t7_9.ts`):

| column | physical | logical | unit | timeZone | read as |
|---|---|---|---|---|---|
| date `born` | INT32 | DATE | `day` | none | number of days since 1970 |
| timestamp, no zone | INT64 | `TIMESTAMP(MICROS, local)` (also MILLIS, NANOS) | `us`, `ms`, `ns` | undefined | number; bigint for `ns` |
| timestamp with `America/New_York` | INT64 | `TIMESTAMP(MICROS, UTC)` | `us` | `America/New_York` | number |
| `unit:"s"`, zone UTC | DOUBLE | (empty) | `s` | `UTC` | number |

- Instants: `toDate` gave `2024-03-01T14:00:00.123Z` for the zoned instant. Formatted in `America/New_York` with `Intl.DateTimeFormat` it was "9:00 AM". This matches the docs.
- A date with 19783 gave `2024-03-01T00:00:00.000Z`. A nanosecond timestamp of `-1n` gave `1969-12-31T23:59:59.999Z`.
- The profile entry `dta` had `{"logical":"timestamp","tz":"UTC"}` for the seconds column and `{"tz":"America/New_York"}` for the New York one. I did not check this against the docs.
- A zone of `undefined` means a clock time with no zone, as the docs say.
- `toDate(null, v)` returns `null`. The docs do not say so.
- Docs: "A timestamp in seconds ... is written as DOUBLE". Confirmed, `physicalType` is `DOUBLE`.
- Doc gap: a user who writes `unit:"s"` gets a DOUBLE column with no `logicalType`, which looks odd next to the other units. The docs say it only in a clause, not in the Dates section's table or example.

### 8. Other codec, row group size, documented errors: succeeded
- Wrote ten rows with `rowGroupSize: 4` and `compression` of `zstd` (level 5), `gzip`, `lz4_raw` and `none`.
- Each file's `info.compression` was one entry equal to the codec. Each column chunk's `codec` matched.
- `info.rowGroups` was three groups: rows 0–3, 4–7 and 8–9. A `readRows(3,3)` across a group boundary gave `[4,5,6]`.
- Errors, all `DTA_INVALID`, matching the docs:
  - `unknown compression "lzo"; use one of "snappy", "zstd", "gzip", "lz4_raw" or "none"`
  - `zstd levels run from 1 to 22, not 99`
  - `snappy has no compression levels`
  - `rowGroupSize must be a whole number of rows of at least 1, not 0`
  - `column "b": row 0 holds 1000, which a byte column cannot hold`
  - `writeDta` with bigints: `b: a .dta file cannot hold 64-bit integers; use writeParquet`
  - a categorical with a level twice: `column "g" has the level "a" twice`
  - a value-label code of `Infinity`: `value label set s: the code Infinity is not a finite number within ±2^53`
  - `maxStringBytes` on a Parquet reader: `maxStringBytes is for .dta files; Parquet strings are read whole`
  - `writeParquetFile` with a bad value left no file (`existsSync` false).
- Doc gaps:
  - The `rowGroupSize: 0` message is not in the docs' error tables.
  - A table's "mixes strings and numbers" error differs from the Troubleshooting text. The real message is `m: row 0 holds number, among strings`.
  - The error table in `parquet.md` for TypeScript is missing its header separator row and runs into the Julia table. It renders badly.

### 9. Variable label, value labels, data label written and read back: succeeded
- Wrote with `writeParquetFile` and read back with `openParquetFile` (`t9.parquet`).
- Data label: `info.label` was "Smoking survey, 2024".
- Notes: `info.notes` and `r.notes()` were `['Wave 2 only.', 'Second note']`.
- Variable labels and formats: `smokes.label` was "Smokes now" and `smokes.format` was "%8.0g".
- Label set name: `smokes.valueLabels` was "yesno".
- Value labels: `r.valueLabels("yesno")` was `Map {0=>No, 1=>Yes, {missing:'.r'}=>Refused, {missing:'.d'}=>Don't know}`.
- An unknown set name returns `undefined`.
- Sort order: `info.sortedBy` was `['id']`.
- Doc gap: the `Characteristic` shape is not given. The API reference shows only `variable` ("`_dta` for the dataset, or a variable's name").
  - I guessed `{variable, name, text}`. The reader gave back `{variable:'smokes', name:'source', value:''}`.
  - So the field is `value`, and my wrong `text` was silently turned into an empty string, with no error.

### 10. `.`, `.a` and `.z` in one column: succeeded
- `t6.dta` has `income` as a double with `[2100, null, .a, 1850, .z, 3200]`, written to Parquet by the docs' recipe.
- Read back as `NumberColumn`: `values [2100,NaN,NaN,1850,NaN,3200]`, `missing [0,1,2,0,27,0]`.
- Kinds per value: ordinary is code 0, `.` is 1, `.a` is 2 and `.z` is 27.
- In `readRows`: `2100, {missing:'.'}, {missing:'.a'}, 1850, {missing:'.z'}, 3200`.
- `formatValue(cell, "%9.0g", r.valueLabels("nonresp"))` gave `'2100','.','Refused','1850','Other','3200'`.
- A real `NaN` is told apart: `[NaN, null, .b, 1]` came back with codes `[0,1,3,0]`.
- The `income` variable has `physicalType` DOUBLE and `storage` undefined, because it was a double already. A `byte` column with `.a` has `storage: "byte"` (shown in the profile for `smokes` in task 9).
- What the docs say other tools see: "`.` is a Parquet null". "`.a` to `.z` are written as tagged NaNs ... arrow (R), nanoparquet and DuckDB in R give the letters back; pandas reads them as missing; pyarrow, polars and DuckDB SQL see NaN, which `IS NULL` does not match (use `x IS NULL OR isnan(x)`); hyparquet gives `NaN`". `missingLetters: false` writes nulls instead.
- Doc gap: `.` and a plain null cannot be told apart in the file. The docs say `.` is a null but do not say that a null you write comes back as `.`. I saw that it does.

### 11. File from another tool: succeeded
- Looked for: pyarrow, polars and duckdb in Python (none; pandas 3.0.5 is installed but has no Parquet engine); `duckdb` and `nanoparquet` in R (none); the `duckdb` command (none). R's `arrow` 26.0.0 is installed, so I used it.
- Wrote with R arrow (`t11_write.R`): int32, float64, utf8, boolean, date32, timestamp(us, America/New_York), a dictionary column and an int8, all with zstd, plus a second file with a list column.
- `openParquetFile` read the flat file with no options:
  - Types: `long`, `double`, `string`, `bool`, `date` (unit `day`), `timestamp` (us, timeZone `America/New_York` from `ARROW:schema`), `categorical` and `byte` (INT(8)).
  - `info.compression` was `['zstd']` and `createdBy` was `parquet-cpp-arrow version 26.0.0`.
  - The key-value keys were `['r','ARROW:schema']`.
  - Nulls came as `{missing:'.'}`.
- The factor (levels lo, mid, hi) came back as a `DictionaryColumn` with `levels: null`, and `values ['lo','hi','mid']` in order of first appearance. That matches the docs.
- The nested file listed `l` with `role:"nested"`, `columnKind:null` and `notRead:'column "l" is nested (a list, map or group), which is not read'`.
  - `readRows(0,3)` and `readColumns(["l"])` threw `DTA_INVALID`.
  - `readColumns(["id"])` worked. `{nested:"skip"}` dropped `l` from `variables`.
- What the docs say this library does not read:
  - Nested columns (lists, maps, structs).
  - Encrypted files.
  - Datasets split over several files.
  - FLOAT16 and INTERVAL columns (listed but not read).
  - LZO, and the Hadoop framing of LZ4 (errors).
- Doc gap: nothing contradicted.
  - The nested error's code is `DTA_INVALID`; the docs give no code for it.
  - Only encoding and codec names are listed; I did not exercise those beyond zstd.

## Summary of doc problems

1. Build: Homebrew's `cargo` hides rustup's wasm target; the fix is only in the script's header comment. Also unsaid: the Homebrew llvm requirement and the build time.
2. Task 6: no documented path from a value-labelled numeric column to a categorical. `strings: "dictionary"` on a numeric column is silently ignored.
3. `Characteristic`'s fields `name` and `value` are undocumented, and an unknown field is dropped without an error.
4. `info.keyValue` gives only sizes; the text needs `keyValue(key)`. Undocumented: `keyValue` and `toDate(null)` return `undefined` and `null`.
5. `logicalType` strings (`TIMESTAMP(MICROS, local)` and so on) and the empty string for none are unlisted. A seconds timestamp has no logical type because it is DOUBLE.
6. Error table: the TypeScript table in `parquet.md` is malformed markdown, and the `rowGroupSize` message and the real "among strings" message are missing.
7. The "Write a file" section that the docs link to (`#write-a-file`) is not among the pages I was given. I used the API reference for `WriteDataset`.

---

# Code that ran

(Scripts are in this directory; the code in each is included below.)

## t1.ts

```ts
import * as m from "@jbearak/dta-parser";
import * as n from "@jbearak/dta-parser/node";
for (const k of ["openParquet","openParquetAsync","writeParquet","toDate"]) console.log(k, typeof (m as any)[k]);
for (const k of ["openParquetFile","writeParquetFile","openDtaFile","writeDtaFile"]) console.log(k, typeof (n as any)[k]);
```

## t2_5.ts

```ts
import { openParquetFile, writeParquetFile } from "@jbearak/dta-parser/node";
const path = "t2.parquet";
writeParquetFile(path, { variables: [
  { name: "id", type: "long", values: [1, 2, 3, 4, 5, 6] },
  { name: "x", type: "double", values: [0.5, 1.5, null, 3.25, 4, 5] },
  { name: "name", values: ["a", "b", null, "d", "e", "f"] },
  { name: "flag", type: "bool", values: [1, 0, 1, null, 0, 1] },
  { name: "d", type: "date", values: [0, 19783, 19784, null, 19786, 19787] },
  { name: "ts", type: "timestamp", values: [1_709_301_600_123_456, 0, 1, null, 4, 5] },
]});
console.log("--- task 2");
{ using r = openParquetFile(path);
  const cols = r.readColumns(r.variables.map((_, i) => i));
  r.variables.forEach((v, i) => console.log(v.name, "type=" + v.type, "kind=" + cols[i].kind, "columnKind=" + v.columnKind, v.physicalType, v.logicalType, "unit=" + v.unit, "tz=" + v.timeZone, cols[i].values.constructor.name));
  console.log(r.readRows(0, 6));
}
console.log("--- task 3");
{ using r = openParquetFile(path);
  const [name, id] = r.readColumns(["name", "id"]);
  console.log(name.kind, id.kind);
  console.log(r.readRows(0, 2, ["name", "id"]));
  try { r.readColumns(["weight"]); } catch (e: any) { console.log(e.constructor.name, e.code, e.message); }
  try { r.readColumns([9]); } catch (e: any) { console.log(e.constructor.name, e.code, e.message); }
}
console.log("--- task 4");
{ using r = openParquetFile(path);
  const [id] = r.readColumns(["id"], { start: 2, count: 3 });
  console.log(id.kind === "number" && Array.from(id.values));
  console.log(r.readRows(2, 3));
  for (const [s, c] of [[4, 5], [6, 1], [7, 1], [0, 7]] as const) {
    try { console.log(s, c, r.readRows(s, c).length); } catch (e: any) { console.log(s, c, e.constructor.name, e.code, e.message); }
  }
  try { r.readColumns(["id"], { start: 4, count: 5 }); } catch (e: any) { console.log("readColumns", e.constructor.name, e.code, e.message); }
  const o = r.readColumns(["id"], { start: 4 }); console.log("no count:", o[0].kind === "number" && Array.from(o[0].values));
}
console.log("--- task 5");
{ using r = openParquetFile(path);
  console.log(r.variables.map(v => `${v.name}:${v.type}:${v.physicalType}:${v.logicalType}:${v.columnKind}`));
  const i = r.info;
  console.log("nobs", i.nobs, "format", i.format, "rowGroups", i.rowGroups, "compression", i.compression, "createdBy", i.createdBy, "keyValue", i.keyValue, "footerBytes", i.footerBytes, "warnings", i.warnings);
  console.log(r.variables[0].chunks[0]);
  console.log("kv dta:", r.keyValue("dta"));
  console.log("kv missing key:", r.keyValue("nope"));
}
```

## t6.ts

```ts
import { MISSING, formatValue, type Missing } from "@jbearak/dta-parser";
import { openDtaFile, writeDtaFile, openParquetFile, writeParquetFile } from "@jbearak/dta-parser/node";

// --- write the .dta (tasks 6 and 10)
writeDtaFile("t6.dta", {
  label: "Task 6 data",
  valueLabels: {
    region: new Map<number | Missing, string>([[1, "North"], [2, "South"], [3, "West"]]),
    nonresp: new Map<number | Missing, string>([[MISSING[".a"], "Refused"], [MISSING[".z"], "Other"]]),
  },
  variables: [
    { name: "id", type: "long", label: "Respondent id", values: [1, 2, 3, 4, 5, 6] },
    { name: "region", type: "byte", label: "Region of residence", valueLabels: "region", values: [1, 2, 2, 3, 1, null] },
    { name: "income", type: "double", label: "Monthly income", valueLabels: "nonresp",
      values: [2100, null, MISSING[".a"], 1850, MISSING[".z"], 3200] },
  ],
});

// --- the docs' dta -> parquet recipe
const dta = openDtaFile("t6.dta");
const cols = dta.readColumns(dta.variables.map((_, i) => i));
console.log("dta vars", dta.variables, dta.info.label, dta.notes());
writeParquetFile("t6.parquet", {
  label: dta.info.label,
  notes: dta.notes(),
  valueLabels: { region: dta.valueLabels("region")!, nonresp: dta.valueLabels("nonresp")! },
  variables: dta.variables.map((v, i) => ({ ...v, values: cols[i] })),
});
dta.close();

console.log("--- task 6");
{ using r = openParquetFile("t6.parquet");
  console.log(r.info.nobs, r.variables.map((v) => `${v.name}:${v.type}:${v.physicalType}:${v.label}:${v.valueLabels}`));
  const region = r.variables[1];
  console.log("var label:", region.label, "| label set name:", region.valueLabels);
  const labels = r.valueLabels(region.valueLabels)!;
  console.log("value labels:", labels, "| text of code 2:", labels.get(2));
  const [codes] = r.readColumns(["region"]);
  console.log(codes);
  if (codes.kind === "number") console.log("as text:", Array.from(codes.values, (c, i) => codes.missing?.[i] ? "(missing " + codes.missing[i] + ")" : labels.get(c)));
  console.log("info.label", r.info.label, "notes", r.notes());
  // categorical: try readColumns strings: "dictionary" on the numeric labelled column
  try { console.log("dictionary option on numeric:", r.readColumns(["region"], { strings: "dictionary" })[0].kind); } catch (e: any) { console.log("err", e.message); }
  // manual: write a categorical column from the labels, read it back
  const levels = [...labels.entries()].filter(([k]) => typeof k === "number").map(([, t]) => t);
  const code = Array.from(codes.kind === "number" ? codes.values : [], (c, i) => (codes.kind === "number" && codes.missing![i]) ? null : [...labels.keys()].indexOf(c));
  writeParquetFile("t6cat.parquet", { variables: [{ name: "region", type: "categorical", levels, values: code }] });
  using c = openParquetFile("t6cat.parquet");
  const [d] = c.readColumns(["region"]);
  console.log(c.variables[0].type, c.variables[0].categorical, d);
  if (d.kind === "dictionary") console.log("text per row:", Array.from(d.codes, (k, i) => d.missing?.[i] ? null : d.values[k]));
  console.log(c.readRows(0, 6));
}

console.log("--- task 10");
{ using r = openParquetFile("t6.parquet");
  const v = r.variables[2];
  console.log(v.name, v.type, v.physicalType, v.storage, v.valueLabels);
  const [inc] = r.readColumns(["income"]);
  console.log(inc);
  const names = ["value", ".", ...Array.from({ length: 26 }, (_, i) => "." + String.fromCharCode(97 + i))];
  if (inc.kind === "number") console.log(Array.from(inc.values, (x, i) => `${x} -> ${names[inc.missing![i]]}`));
  console.log(r.readRows(0, 6, ["income"]).map((row) => row[0]));
  const nl = r.valueLabels("nonresp")!;
  console.log(nl);
  console.log(r.readRows(0, 6, ["income"]).map((row) => formatValue(row[0], "%9.0g", nl)));
  console.log("dta profile:", r.keyValue("dta"));
  // does a NaN stay different from .a?
  writeParquetFile("t10b.parquet", { variables: [{ name: "x", values: [NaN, null, MISSING[".b"], 1] }] });
  using q = openParquetFile("t10b.parquet");
  const [x] = q.readColumns(["x"]); console.log("NaN vs . vs .b:", x.kind === "number" && [Array.from(x.values), Array.from(x.missing!)]);
  console.log(q.readRows(0, 4));
}
```

## t7_9.ts

```ts
import { MISSING, toDate, writeParquet, openParquet, writeDta, type Missing } from "@jbearak/dta-parser";
import { openParquetFile, writeParquetFile } from "@jbearak/dta-parser/node";

console.log("--- task 7");
{
  const bytes = writeParquet({ variables: [
    { name: "born", type: "date", values: [0, 19_783, null] },
    { name: "naive_ms", type: "timestamp", unit: "ms", values: [1_709_301_600_123, 0, null] },
    { name: "naive_us", type: "timestamp", values: [1_709_301_600_123_456, 0, null] },
    { name: "ny_us", type: "timestamp", unit: "us", timeZone: "America/New_York", values: [1_709_301_600_123_456, 0, null] },
    { name: "utc_s", type: "timestamp", unit: "s", timeZone: "UTC", values: [1_709_301_600, 0, null] },
    { name: "naive_ns", type: "timestamp", unit: "ns", values: [1_709_301_600_000_000_001n, -1n, null] },
  ]});
  const r = openParquet(bytes);
  for (const v of r.variables) console.log(v.name, v.type, v.physicalType, v.logicalType, "unit=" + v.unit, "tz=" + v.timeZone, "kind=" + v.columnKind);
  const rows = r.readRows(0, 3);
  console.log(rows);
  const vs = r.variables;
  console.log("born", toDate(rows[1][0] as number, vs[0])?.toISOString());
  console.log("naive_ms", toDate(rows[0][1] as number, vs[1])?.toISOString());
  console.log("naive_us", toDate(rows[0][2] as number, vs[2])?.toISOString());
  console.log("ny_us", toDate(rows[0][3] as number, vs[3])?.toISOString());
  console.log("utc_s", toDate(rows[0][4] as number, vs[4])?.toISOString());
  console.log("naive_ns", toDate(rows[1][5] as bigint, vs[5])?.toISOString());
  console.log("null->", toDate(null as any, vs[0]));
  console.log(new Intl.DateTimeFormat("en-US", { timeZone: vs[3].timeZone, timeStyle: "short" }).format(toDate(rows[0][3] as number, vs[3])!));
  console.log(r.info.keyValue, r.keyValue("dta"));
}

console.log("--- task 8");
{
  const data = { variables: [
    { name: "id", type: "long" as const, values: Array.from({ length: 10 }, (_, i) => i + 1) },
    { name: "txt", values: Array.from({ length: 10 }, (_, i) => "row" + i) },
  ]};
  for (const [comp, level] of [["zstd", 5], ["gzip", undefined], ["lz4_raw", undefined], ["none", undefined]] as const) {
    writeParquetFile("t8.parquet", data, { compression: comp, compressionLevel: level, rowGroupSize: 4 });
    using r = openParquetFile("t8.parquet");
    console.log(comp, level, "compression", r.info.compression, "groups", JSON.stringify(r.info.rowGroups), "chunk codecs", r.variables.map(v => v.chunks.map(c => c?.codec)));
    console.log("  rows across groups", r.readRows(3, 3).map(x => x[0]));
  }
  const tries: [string, () => unknown][] = [
    ["unknown codec lzo", () => writeParquet(data, { compression: "lzo" as any })],
    ["zstd level 99", () => writeParquet(data, { compression: "zstd", compressionLevel: 99 })],
    ["snappy with level", () => writeParquet(data, { compression: "snappy", compressionLevel: 3 })],
    ["rowGroupSize 0", () => writeParquet(data, { rowGroupSize: 0 })],
    ["byte holds 1000", () => writeParquet({ variables: [{ name: "b", type: "byte", values: [1000] }] })],
    ["mixes strings and numbers", () => writeParquet({ variables: [{ name: "m", values: [1, "a"] as any }] })],
    ["writeDta bigint", () => writeDta({ variables: [{ name: "b", values: [1n] as any }] })],
    ["code twice level", () => writeParquet({ variables: [{ name: "g", type: "categorical", levels: ["a", "a"], values: [0] }] })],
    ["bad label code", () => writeParquet({ valueLabels: { s: new Map<number | Missing, string>([[Infinity, "x"]]) }, variables: [{ name: "v", type: "byte", valueLabels: "s", values: [1] }] })],
  ];
  for (const [name, f] of tries) {
    try { f(); console.log(name, "-> NO ERROR"); } catch (e: any) { console.log(name, "->", e.constructor.name, e.code, e.message); }
  }
  try { openParquet(writeParquet(data), { maxStringBytes: 3 } as any).readColumns(["txt"], { maxStringBytes: 3 }); console.log("maxStringBytes -> no error"); } catch (e: any) { console.log("maxStringBytes ->", e.code, e.message); }
  try { writeParquetFile("t8bad.parquet", { variables: [{ name: "b", type: "byte", values: [1000] }] }); } catch (e: any) { console.log("writeParquetFile:", e.message); }
  import("node:fs").then(fs => console.log("t8bad exists?", fs.existsSync("t8bad.parquet")));
}

console.log("--- task 9");
{
  writeParquetFile("t9.parquet", {
    label: "Smoking survey, 2024",
    notes: ["Wave 2 only.", "Second note"],
    characteristics: [{ variable: "smokes", name: "source", text: "q12" } as any],
    sortedBy: ["id"],
    valueLabels: { yesno: new Map<number | Missing, string>([[0, "No"], [1, "Yes"], [MISSING[".r"], "Refused"], [MISSING[".d"], "Don't know"]]) },
    variables: [
      { name: "id", type: "long", label: "Id", values: [1, 2, 3] },
      { name: "smokes", type: "byte", label: "Smokes now", format: "%8.0g", valueLabels: "yesno", values: [1, 0, MISSING[".r"]] },
    ],
  });
  using r = openParquetFile("t9.parquet");
  console.log("info:", r.info.label, r.info.notes, r.notes(), r.info.sortedBy, r.info.warnings);
  console.log("characteristics:", r.characteristics());
  console.log(r.variables.map(v => [v.name, v.label, v.format, v.valueLabels]));
  console.log(r.valueLabels("yesno"));
  console.log(r.valueLabels("nope"));
  console.log("profile:", r.keyValue("dta"));
}
```

## t11_write.R

```r
library(arrow)
df <- data.frame(
  i = 1:4, d = c(1.5, NA, 3, 4), s = c("a", NA, "c", "d"), b = c(TRUE, FALSE, NA, TRUE),
  dt = as.Date("2024-03-01") + 0:3,
  ts = as.POSIXct("2024-03-01 14:00:00", tz = "America/New_York") + 0:3,
  f = factor(c("lo", "hi", "lo", "mid"), levels = c("lo", "mid", "hi")),
  i8 = as.integer(c(1, 2, 3, 4)),
  stringsAsFactors = FALSE)
tab <- arrow_table(df, schema = schema(i = int32(), d = float64(), s = utf8(), b = boolean(), dt = date32(),
  ts = timestamp("us", "America/New_York"), f = dictionary(int32(), utf8()), i8 = int8()))
write_parquet(tab, "t11_flat.parquet", compression = "zstd")
nested <- arrow_table(id = 1:3, l = Array$create(list(1:2, 3L, integer(0))))
write_parquet(nested, "t11_nested.parquet")
cat("written\n")
```

## t11.ts

```ts
import { openParquetFile } from "@jbearak/dta-parser/node";
console.log("--- flat (R arrow, zstd)");
{ using r = openParquetFile("t11_flat.parquet");
  r.variables.forEach(v => console.log(v.name, v.type, v.physicalType, v.logicalType, v.columnKind, v.unit, v.timeZone, JSON.stringify(v.categorical)));
  console.log(r.info.compression, r.info.createdBy, r.info.keyValue.map(k => k.key), r.info.warnings);
  console.log(r.readRows(0, 4));
  const cols = r.readColumns(["f"]); console.log(cols[0]);
}
console.log("--- nested");
{ using r = openParquetFile("t11_nested.parquet", { nested: "error" } as any) as any;
  console.log(r.variables.map((v: any) => [v.name, v.role, v.columnKind, v.notRead]));
  for (const f of [() => r.readRows(0, 3), () => r.readColumns(["l"]), () => r.readColumns(["id"])]) {
    try { console.log("ok", f()); } catch (e: any) { console.log(e.code, e.message); }
  }
}
{ using r = openParquetFile("t11_nested.parquet", { nested: "skip" });
  console.log("skip:", r.variables.map(v => v.name), r.readRows(0, 3));
}
```
