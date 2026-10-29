# TypeScript and JavaScript: @jbearak/dta-parser

`@jbearak/dta-parser` reads Stata `.dta` files and writes them, in
Node, synchronously. It reads every release from 104 to 119 and writes
release 118. The format code is the Rust core compiled to WebAssembly
and embedded in the package, so there is no `.wasm` file to ship and no
native build. It reads only what you ask for: opening a file reads the
header and variable descriptors, and each read decodes just the
requested variables and rows, so files larger than memory work.

Contents:
[Install](#install) ·
[The example file](#the-example-file) ·
[Open and read a file](#open-and-read-a-file) ·
[Select columns](#select-columns) ·
[Read some rows](#read-some-rows) ·
[Metadata](#metadata) ·
[Missing values](#missing-values) ·
[Value labels](#value-labels) ·
[Dates and display formats](#dates-and-display-formats) ·
[Write a file](#write-a-file) ·
[Recipes](#recipes) ·
[Coming from @irbisadm/statfmt](#coming-from-irbisadmstatfmt) ·
[Coming from @jbearak/dta-parser 0.x](#coming-from-jbearakdta-parser-0x) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

Version 1.0, described here, is not on npm yet; npm has 0.x, a
different API. Build it from a checkout. You need Node 20 or later, and
Rust with the WebAssembly target to build:

```sh
git clone https://github.com/jbearak/dta-parser
cd dta-parser
rustup target add wasm32-unknown-unknown
scripts/build-wasm.sh
cd js && npm ci && npm run build
cd /path/to/your/project && npm install /path/to/dta-parser/js
```

The package has two entry points:

- `@jbearak/dta-parser`: reading from bytes in memory (`openDta`),
  writing to bytes (`writeDta`, `writeDtaTo`), missing values, keys and
  `formatValue`. It uses no Node API.
- `@jbearak/dta-parser/node`: reading and writing files on disk
  (`openDtaFile`, `writeDtaFile`).

It is a CommonJS package with TypeScript types; `import` and `require`
both work.

## The example file

Every example on this page reads `survey.dta`. This block makes it; run
it first. It also shows most of what writing can do, which
[Write a file](#write-a-file) explains.

```ts
import { MISSING, type Missing } from "@jbearak/dta-parser";
import { writeDtaFile } from "@jbearak/dta-parser/node";

// Stata dates count days from 1 January 1960.
const day = (iso: string) => (Date.parse(iso) - Date.UTC(1960, 0, 1)) / 86_400_000;

writeDtaFile("survey.dta", {
  label: "Household survey (example)",
  notes: ["Made up for the dta-parser documentation."],
  valueLabels: {
    region: new Map<number | Missing, string>([[1, "North"], [2, "South"], [3, "East"], [4, "West"]]),
    nonresponse: new Map<number | Missing, string>([[MISSING[".d"], "Don't know"], [MISSING[".r"], "Refused"]]),
  },
  variables: [
    { name: "id", type: "long", values: [1, 2, 3, 4, 5, 6] },
    { name: "region", type: "byte", label: "Region", valueLabels: "region", values: [1, 2, 2, 3, 4, 1] },
    { name: "age", type: "byte", label: "Age in years", values: [34, 51, 29, 62, 45, 38] },
    // .d = "don't know", .r = "refused"; null is Stata's `.`
    { name: "income", label: "Monthly income", valueLabels: "nonresponse",
      values: [2100, MISSING[".d"], 1850, null, MISSING[".r"], 3200] },
    { name: "interviewed", type: "long", format: "%td",
      values: ["2024-03-01", "2024-03-01", "2024-03-02", "2024-03-04", "2024-03-04", "2024-03-05"].map(day) },
    { name: "comment", values: ["", "moved in 2023", "", "", "asked to call back", ""] },
  ],
});
```

## Open and read a file

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
console.log(r.info.nobs, r.variables.map((v) => v.name));
// 6 [ 'id', 'region', 'age', 'income', 'interviewed', 'comment' ]
const rows = r.readRows(0, 3);
console.log(rows[1]);
// [ 2, 2, 51, { missing: '.d' }, 23436, 'moved in 2023' ]
r.close();
```

`openDtaFile(path)` opens a file and returns a `DtaReader`. It reads
the file through `fs.readSync` only as far as each call needs, so a
file of any size opens instantly. `openDtaFile(fd)` takes a file
descriptor you opened; you close it, and the file may be deleted after
opening. `openDta(bytes)` reads a `Uint8Array` already in memory (in a
browser, for example).

Call `close()` when done: it frees the reader's memory inside the
WebAssembly module and closes a file opened by path. Reads after
`close()` throw "the file is closed".

TypeScript has no standard table type, so the package has none either:
you get columns of typed arrays, or rows of cells, and can hand either
to the table library you use.

There are two ways to get data:

- **`readColumns(columns, { start, count })`** returns one column object
  per variable: fast, and the shape you want for analysis.
- **`readRows(start, count, columns?)`** returns an array per row, with
  each cell a `number`, `string`, `Uint8Array` (binary strL) or a
  missing value. Convenient for display.

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [age, comment] = r.readColumns(["age", "comment"]);
if (age.kind === "number") console.log(age.values, age.missing);
// Float64Array(6) [ 34, 51, 29, 62, 45, 38 ] Uint8Array(6) [ 0, 0, 0, 0, 0, 0 ]
if (comment.kind === "string") console.log(comment.values[1]);   // moved in 2023
r.close();
```

| in the file | `readColumns` | `readRows` cell |
|---|---|---|
| byte, int, long, float, double | `NumberColumn`: `values` (`Float64Array`) and `missing` (`Uint8Array`) | `number` |
| `.`, `.a` to `.z` | `values[i]` is `NaN`, `missing[i]` is 1 to 27 | `MISSING["."]` ... `MISSING[".z"]` |
| strN, strL text | `StringColumn`: `values` of `string` | `string` |
| strL with binary values | `Uint8Array` elements | `Uint8Array` |
| dates | numbers; see [Dates](#dates-and-display-formats) | `number` |

Every Stata number fits a JavaScript number exactly, including every
long and every double.

## Select columns

Both `readColumns` and `readRows` take variables by name or 0-based
index, in the order you want:

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const cols = r.readColumns(["income", 0]);      // income, then id
console.log(r.readRows(0, 2, ["id", "age"]));   // [ [ 1, 34 ], [ 2, 51 ] ]
r.close();
```

A name or index that is not in the file throws a `RangeError` naming
it. All selected variables are read in one pass over the rows.

## Read some rows

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [id] = r.readColumns(["id"], { start: 2, count: 3 });
console.log(id.kind === "number" && Array.from(id.values));   // [ 3, 4, 5 ]
for (let start = 0; start < r.info.nobs; start += 4) {
  const count = Math.min(4, r.info.nobs - start);
  console.log(start, r.readRows(start, count).length);
}
r.close();
```

`start` defaults to 0 and `count` to the rest of the file. Unlike the
R and Python packages, a range that runs past the last row throws a
`RangeError`; compute `count` from `r.info.nobs`. The reader seeks to
`start`, so reading the last rows of a large file costs the same as the
first.

## Metadata

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
console.log(r.info);
// { release: 118, byteOrder: 'little', nobs: 6, label: 'Household survey (example)',
//   timestamp: '...', encoding: 'utf-8', sortedBy: [] }
console.log(r.variables[3]);
// { name: 'income', type: 'double', format: '%10.0g', label: 'Monthly income', valueLabels: 'nonresponse' }
console.log(r.notes());              // [ 'Made up for the dta-parser documentation.' ]
console.log(r.characteristics());    // [ { variable: '_dta', name: 'note0', value: '1' }, ... ]
r.close();
```

| where | holds |
|---|---|
| `info.release` | the file's release, such as 114 or 118 |
| `info.byteOrder` | `"little"` or `"big"` |
| `info.nobs` | the number of rows |
| `info.label` | the data label (`""` if none) |
| `info.timestamp` | the time stamp text, such as `"01 Mar 2024 14:05"` |
| `info.encoding` | how text was decoded: `"utf-8"` from release 118 |
| `info.sortedBy` | names of the variables the data is sorted by |
| `variables[i].name`, `.type` | name; storage type: `byte`, `int`, `long`, `float`, `double`, `str1` to `str2045`, `strL` |
| `variables[i].format`, `.label`, `.valueLabels` | display format; variable label; name of its value label set (`""` if none) |
| `notes()` | the dataset's notes, in order |
| `characteristics()` | every characteristic, notes included: `{ variable, name, value }` |

All of it is available right after opening; no rows are read.

## Missing values

Stata has 27 numeric missing values: `.` and `.a` to `.z` (see the
[guide](guide/missing-values.md)). The package numbers them with
*missing codes*: 1 for `.`, 2 for `.a`, ..., 27 for `.z` (0 means not
missing).

- In a `NumberColumn`, `missing[i]` holds the code and `values[i]` is
  `NaN`.
- In a row, a missing cell is one of the 27 frozen objects in `MISSING`,
  so `cell === MISSING[".d"]` works. `missingValue(code)` gives the
  object for a code, and `isMissing(cell)` tells a missing value from a
  number or string.

```ts
import { MISSING, isMissing, missingValue, stataKey } from "@jbearak/dta-parser";
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [income] = r.readColumns(["income"]);
if (income.kind === "number") {
  console.log(income.missing);                   // Uint8Array(6) [ 0, 5, 0, 1, 19, 0 ]
  console.log(missingValue(income.missing[1]));  // { missing: '.d' }
}
const cells = r.readRows(0, 6, ["income"]).map((row) => row[0]);
console.log(cells.filter((c) => c === MISSING[".r"]).length);   // 1
console.log(cells.filter((c) => !isMissing(c)));                // [ 2100, 1850, 3200 ]
r.close();
```

**Order.** Stata sorts missing values after every number, in the order
`.` < `.a` < ... < `.z`. `stataKey(cell)` turns a number or missing
value into a number that sorts that way, and `stataKeys(column)` does
the same for a whole `NumberColumn`:

```ts
import { stataKey, stataKeys } from "@jbearak/dta-parser";
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const cells = r.readRows(0, 6, ["income"]).map((row) => row[0]);
cells.sort((a, b) => stataKey(a as number) - stataKey(b as number));
console.log(cells);   // [ 1850, 2100, 3200, { missing: '.' }, { missing: '.d' }, { missing: '.r' } ]
const [income] = r.readColumns(["income"]);
if (income.kind === "number") {
  const keys = stataKeys(income);
  const order = [...keys.keys()].sort((i, j) => keys[i] - keys[j]);
  console.log(order);   // [ 2, 0, 5, 3, 1, 4 ]
}
r.close();
```

The keys are the doubles Stata stores for missing values: finite and
larger than any number Stata stores. The same keys come out of the R,
Python and Julia packages.

## Value labels

`variables[i].valueLabels` names a column's value label set;
`valueLabels(name)` returns the set as a `Map` from value to text, or
`undefined` if the file has no set by that name. Missing values are
keyed by the `MISSING` objects.

```ts
import { MISSING } from "@jbearak/dta-parser";
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const set = r.variables[1].valueLabels;   // "region"
const labels = r.valueLabels(set)!;
console.log(labels.get(2));               // South
console.log(r.valueLabels("nonresponse")?.get(MISSING[".d"]));   // Don't know
const regions = r.readRows(0, 6, ["region"]).map(([v]) => labels.get(v as number) ?? v);
console.log(regions);   // [ 'North', 'South', 'South', 'East', 'West', 'North' ]
r.close();
```

`formatValue(cell, format, labels)` does the lookup too and falls back
to the formatted number; see the next section.

## Dates and display formats

Dates are numbers in the file: `%td` counts days since 1 January 1960,
`%tc` milliseconds since then (see the [guide](guide/dates.md)). The
package always returns the numbers (there is no option to convert
them), so nothing is lost, and gives
`formatValue(cell, format, labels?)` to show a value as Stata would:

```ts
import { formatValue } from "@jbearak/dta-parser";
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [row] = r.readRows(0, 1);
const fmt = (i: number) => formatValue(row[i], r.variables[i].format, r.valueLabels(r.variables[i].valueLabels));
console.log(fmt(1), fmt(4));                          // North 01mar2024
console.log(formatValue(23436, "%tdCCYY-NN-DD"));     // 2024-03-01
console.log(formatValue(1234.5678, "%9.2f"));         // 1234.57
console.log(formatValue(1234567, "%12.0gc"));         // 1,234,567
r.close();
```

`formatValue` handles `%f`, `%g` and `%e` numbers (with `c` for
thousands separators), string formats, and the date formats `%td`,
`%tc`, `%tC`, `%tw`, `%tm`, `%tq`, `%th`, `%ty` and the older `%d`,
with masks such as `CCYY-NN-DD` or `Mon_DD,_CCYY`. It ignores the width
except to choose how many digits `%g` shows, and treats `%tC` like `%tc`
(no leap seconds). A labelled value shows its label; a missing value
shows `.`, `.a` and so on, or its label.

To get a JavaScript `Date`:

```ts
const EPOCH = Date.UTC(1960, 0, 1);
const fromTd = (days: number) => new Date(EPOCH + days * 86_400_000);
const fromTc = (ms: number) => new Date(EPOCH + ms);
console.log(fromTd(23436).toISOString());   // 2024-03-01T00:00:00.000Z
```

## Write a file

```ts
import { MISSING, type Missing } from "@jbearak/dta-parser";
import { writeDtaFile } from "@jbearak/dta-parser/node";
import { openDtaFile } from "@jbearak/dta-parser/node";

writeDtaFile("smokers.dta", {
  label: "Smoking",
  valueLabels: { yesno: new Map<number | Missing, string>([[0, "No"], [1, "Yes"], [MISSING[".d"], "Don't know"]]) },
  variables: [
    { name: "id", type: "long", label: "Person", values: [1, 2, 3] },
    { name: "smoker", type: "byte", label: "Smokes daily", valueLabels: "yesno", values: [1, 0, MISSING[".d"]] },
  ],
});

const back = openDtaFile("smokers.dta");
console.log(back.info.label, back.variables[1].label);   // Smoking Smokes daily
console.log(back.valueLabels("yesno"));                  // Map(3) { 0 => 'No', 1 => 'Yes', { missing: '.d' } => "Don't know" }
back.close();
```

`writeDtaFile(path, dataset)` streams a release 118 file to disk;
`writeDta(dataset)` returns its bytes as a `Uint8Array`, and
`writeDtaTo(dataset, sink)` hands them to `sink` in pieces (for a
stream or an upload). The dataset:

| field | meaning |
|---|---|
| `variables` | the columns, in order; each has the same number of values |
| `label` | data label |
| `valueLabels` | value label sets by name: `Map` from number or `MISSING` value to text |
| `notes` | the dataset's notes |
| `timestamp` | a `Date` for the file's time stamp; default now |

Each variable:

| field | meaning |
|---|---|
| `name` | 1 to 32 letters, digits or `_`, not starting with a digit |
| `values` | numbers, with `null` or a `MISSING` value for missing; or strings |
| `type` | `"byte"`, `"int"`, `"long"`, `"float"` or `"double"` (the default) for numbers; leave it out for strings |
| `format` | display format such as `"%9.2f"` or `"%td"`; default the type's |
| `label` | variable label |
| `valueLabels` | name of a set in `valueLabels` |

Strings are written as `strN` (N the longest value in bytes) up to
2045 bytes and as strLs beyond, each distinct strL stored once.
Stata has no missing string; write `""`. A number that does not fit
its type (300 in a byte, 1.5 in an int, a value in the range Stata
reserves for missing codes) throws an error naming the variable. The
writer does not write characteristics other than notes, the sort order,
or binary strLs.

To write back what you read, pass each variable's `type`, `format`,
`label` and `valueLabels` from `r.variables`, and the sets from
`r.valueLabels(...)`; the [recipe](#copy-a-file-keeping-its-labels)
below does this.

## Recipes

### Copy a file, keeping its labels

```ts
import { missingValue, type Missing, type ValueLabels, type WriteVariable } from "@jbearak/dta-parser";
import { openDtaFile, writeDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const columns = r.readColumns(r.variables.map((_, i) => i));
const variables: WriteVariable[] = r.variables.map((v, i) => {
  const c = columns[i];
  const values = c.kind === "number"
    ? Array.from(c.values, (x, k) => (c.missing[k] ? missingValue(c.missing[k]) : x))
    : (c.values as string[]);
  const type = c.kind === "number" ? (v.type as WriteVariable["type"]) : undefined;
  return { name: v.name, type, format: v.format, label: v.label, valueLabels: v.valueLabels, values };
});
const valueLabels: Record<string, ValueLabels> = {};
for (const v of r.variables) {
  const set = v.valueLabels && r.valueLabels(v.valueLabels);
  if (set) valueLabels[v.valueLabels] = set;
}
writeDtaFile("copy.dta", { label: r.info.label, notes: r.notes(), valueLabels, variables });
r.close();
```

`.a` to `.z` are written back as they were read.

### Rows as objects

```ts
import { isMissing } from "@jbearak/dta-parser";
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const names = r.variables.map((v) => v.name);
const records = r.readRows(0, r.info.nobs).map((row) =>
  Object.fromEntries(row.map((cell, i) => [names[i], isMissing(cell) ? null : cell])),
);
console.log(records[0]);   // { id: 1, region: 1, age: 34, income: 2100, interviewed: 23436, comment: '' }
r.close();
```

### Read from bytes you already have

```ts
import { readFileSync } from "node:fs";
import { openDta, writeDta } from "@jbearak/dta-parser";

const bytes = writeDta({ variables: [{ name: "x", values: [1, 2, 3] }] });
const r = openDta(bytes);
console.log(r.info.release, r.readRows(0, 3));   // 118 [ [ 1 ], [ 2 ], [ 3 ] ]
r.close();
const again = openDta(readFileSync("survey.dta"));
console.log(again.info.nobs);                    // 6
again.close();
```

### A file older than Stata 14 with accented text

Files before release 118 do not record their encoding. The default is
Windows-1252; pass `{ encoding: "latin1" }` or `{ encoding: "utf-8" }`
to `openDtaFile` or `openDta` if text looks wrong (see the
[guide](guide/encodings.md)).

## Coming from @irbisadm/statfmt

| statfmt | @jbearak/dta-parser |
|---|---|
| `readDta(bytes)` (reads everything) | `openDta(bytes)` or `openDtaFile(path)`, then read what you need |
| `readDta(bytes, { rowOffset, rowLimit })` | `readColumns(cols, { start, count })` or `readRows(start, count)` |
| no column selection | `readColumns(["a", "b"])` |
| `{ inputEncoding: "WINDOWS-1252" }` | `{ encoding: "windows-1252" }` (also `"latin1"`, `"utf-8"`) |
| `ds.metadata.rowCount` | `r.info.nobs` |
| `ds.variables[i].name`, `.label`, `.format` | `r.variables[i].name`, `.label`, `.format` |
| `ds.variables[i].valueLabels` (array of `{ value, label }`) | `r.valueLabels(r.variables[i].valueLabels)` (a `Map`) |
| `ds.rows`, `ds.toObjects()` | `r.readRows(0, r.info.nobs)`; see [Rows as objects](#rows-as-objects) |
| missing values as `null` | `MISSING["."]` ... `MISSING[".z"]` in rows; codes in columns |
| `writeDta({ variables, rows, valueLabelSets, fileLabel })` | `writeDta({ variables: [{ name, values }], valueLabels, label })`: values by column, not by row |
| `ReadStatType.INT8` ... `DOUBLE`, `STRING` | `type: "byte"` ... `"double"`; strings need no type |
| `writeDta({ version: 117 })` | always release 118 |
| ESM only | CommonJS, works with `import` and `require` |

statfmt also reads and writes SPSS and SAS files; this package does
only Stata.

## Coming from @jbearak/dta-parser 0.x

1.0 is a new, synchronous API. [docs/migration.md](migration.md) maps
each 0.x call to its 1.0 replacement.

## Troubleshooting

**"unsupported .dta release".** The file is not a `.dta` file, or its
release is older than 104 or newer than 119. See
[Releases](guide/releases.md).

**`RangeError: rows 0 to 10 are outside 0 to 6`.** `start + count` runs
past the last row; compute `count` from `r.info.nobs`.

**`RangeError: no variable "incme"`.** A name in `columns` is not in
the file; check `r.variables`.

**`scripts/build-wasm.sh` fails, or `js/build/dta.wasm` is missing.** The
WebAssembly target must be installed for the toolchain that builds it:
run `rustup target add wasm32-unknown-unknown` with the same `rustup`
default (or `RUSTUP_TOOLCHAIN`) the script uses, then rerun it.
`npm run build` embeds the existing `js/build/dta.wasm` and does not rebuild it, so run
the script again after changing Rust code.

**"the file is closed".** You called a method after `close()`.

**Accented letters are wrong.** The file is older than release 118;
pass `{ encoding: "latin1" }` or `{ encoding: "utf-8" }`.

**"... mixes strings and numbers" or "holds strings" when writing.** A
variable's `values` must be all numbers (with `null` or `MISSING`
values) or all strings.

**A number "does not fit" when writing.** The value is outside the
`type`'s range or not a whole number for byte, int or long; widen
`type`, or leave it out to write a double.

## API reference

TSDoc comments in the package's `.d.ts` files describe each export.

From `@jbearak/dta-parser`:

- `openDta(bytes, options?)`: open a file held in a `Uint8Array`.
- `class DtaReader`: an open file. `new DtaReader(read, length, options?)`
  opens any source given a `ReadAt` function `(into, offset) => void`
  that fills `into` from byte `offset`. Members: `info`, `variables`,
  `readColumns(columns, range?)`, `readRows(start, count, columns?)`,
  `valueLabels(name)`, `notes()`, `characteristics()`, `close()`.
- `writeDta(dataset)`, `writeDtaTo(dataset, sink)`: write release 118.
- `MISSING`, `missingValue(code)`, `isMissing(cell)`: missing values.
- `stataKey(cell)`, `stataKeys(column)`: Stata's sort order as numbers.
- `formatValue(cell, format, labels?)`: show a value as its display
  format says.
- Types: `Missing`, `Cell`, `Variable`, `Info`, `NumberColumn`,
  `StringColumn`, `Column`, `ValueLabels`, `Characteristic`, `Options`
  (`encoding`), `EncodingName` (`"windows-1252"`, `"latin1"`,
  `"utf-8"`), `ReadAt`, `WriteVariable`, `WriteDataset`.

From `@jbearak/dta-parser/node`:

- `openDtaFile(pathOrFd, options?)`: open a file on disk.
- `writeDtaFile(path, dataset)`: write a file to disk; on an error the
  partial file is removed.
