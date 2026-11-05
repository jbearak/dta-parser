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
[Parquet files](#parquet-files) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

Version 1.1 (1.0 with Parquet), described here, is not on npm yet; npm has 0.x, a
different API. Build it from a checkout. You need Node 24 or later, and
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
WebAssembly module and closes a file opened by path (never a file
descriptor you passed in). Reads after `close()` throw "the file is
closed". Close readers you are done with: the WebAssembly module's
memory only grows, so when the last open reader closes after a large
read, the package starts a fresh module and gives that memory back (a
reader you drop without closing is closed when it is garbage collected,
which may be much later). Or declare the reader with `using`, and it
closes at the end of the block:

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

{
  using r = openDtaFile("survey.dta");
  console.log(r.info.nobs);   // 3
}
```

TypeScript has no standard table type, so the package has none either:
you get columns of typed arrays, or rows of cells, and can hand either
to the table library you use.

There are two ways to get data:

- **`readColumns(columns, { start, count })`** returns one column object
  per variable: fast, and the shape you want for analysis.
- **`readRows(start, count, columns?)`** returns an array per row, with
  each cell a `number`, `string`, `Uint8Array` (binary strL) or a
  missing value. Convenient for display.
- **`readRowsAt(rows, columns?)`** returns the rows listed, in their
  order, as `readRows` does: a sorted or filtered page in one read
  rather than one per row. `r.readRowsAt([42, 7, 7, 1000])`.

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

## Strings as a dictionary

A string variable whose values repeat (a country, a category) can come
back as a dictionary: each distinct value once in `values`, and a code
per row in `codes`, so `values[codes[i]]` is row `i`. That takes far
less memory than one string per row, and codes compare and group as
numbers:

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [comment] = r.readColumns(["comment"], { strings: "dictionary" });
if (comment.kind === "dictionary") {
  console.log(comment.values);                // [ '', 'moved in 2023', 'asked to call back' ]
  console.log(Array.from(comment.codes));     // [ 0, 1, 0, 0, 2, 0 ]
}
r.close();
```

Values appear in the order they first appear in the rows read, and
codes mean nothing outside the one `readColumns` call that returned
them. A variable with too many distinct values (more than half of at
least 65,536 rows) or a binary strL comes back as an ordinary string
column instead, so check `kind`. Without the option, string variables
are always `string[]`; reading them that way is fast too, since the
package makes each repeated value once.

## Previews of long strings

To show long strings or strLs without reading them whole (a table cell,
say), pass `maxStringBytes`. Each string keeps at most that many of the
bytes stored in the file, cut back to a whole character, and a strL is
read no further than that. Each string column also gets `storedBytes`,
the full stored length of every value:

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [comment] = r.readColumns(["comment"], { maxStringBytes: 5 });
if (comment.kind === "string") console.log(comment.values[1], comment.storedBytes[1]);   // moved 13
r.close();
```

A value was cut exactly when `storedBytes[i] > maxStringBytes`.
`maxStringBytes: 0` gives lengths alone. Stored bytes are counted
before decoding, so in files before release 118 a cut value's text may
be longer than `maxStringBytes` bytes as UTF-8. It cannot be combined
with `strings: "dictionary"`.

## Sharing the strL index between readers

The first read of a strL variable scans the file's strLs to find each
one. Readers of the same file in several worker threads can share that
work: one reader's `strlIndex()` returns the index as bytes (copy them
into a `SharedArrayBuffer` to share them), and the others take it as
`strlIndex` when opening:

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";

const first = openDtaFile("survey.dta");
const index = first.strlIndex();
const second = openDtaFile("survey.dta", { strlIndex: index });
console.log(second.readRows(1, 1, ["comment"]));   // [ [ 'moved in 2023' ] ]
first.close();
second.close();
```

The index must come from the same file, unchanged since. It is checked
when it is adopted (the file's size and layout, and the index's own
consistency) and as each strL is read (its record must be the one the
index names), and either failure is `DTA_CORRUPT`; but a file rewritten
in place with the same layout is not detected.

The bytes are little-endian: the magic `DTASTRLX`; a version (u32, now
1) and a reserved u32; the file's length (u64), release (u32), byte
order (u32, 1 for big-endian), rows and variables (u64 each); the strL
section's start and end (u64 each); the entry count (u64); then the
entries' keys (u64, variable · 2^40 + row), payload offsets (u64),
lengths (u32), and binary flags (one bit each, in u64 words).

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
`formatValue(cell, format, labels?)` to show a value for display, the
way R prints it:

```ts
import { formatValue } from "@jbearak/dta-parser";
import { openDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const [row] = r.readRows(0, 1);
const fmt = (i: number) => formatValue(row[i], r.variables[i].format, r.valueLabels(r.variables[i].valueLabels));
console.log(fmt(1), fmt(4));                          // North 2024-03-01
console.log(formatValue(1 / 3, "%9.0g"));             // 0.3333333
console.log(formatValue(1234.5678, "%9.2f"));         // 1234.57
console.log(formatValue(1234567, "%12.0gc"));         // 1,234,567
r.close();
```

`formatValue` shows `%g` numbers (and any format it does not know) as R
prints them: 7 significant digits, or `d` for `%w.dg`, in fixed
notation unless scientific is narrower (`0.5`, `123456789012`,
`1e-05`). `%f` and `%e` keep their decimals, and a `c` adds thousands
separators. `%td` and the older `%d` show as R shows a `Date`
(`2024-03-01`), and `%tc` and `%tC` as a `POSIXct` in UTC
(`2024-03-01 13:05:09`), whatever their mask; `%tC`'s leap seconds are
not counted. `%tw`, `%tm`, `%tq`, `%th` and `%ty`, which have no R
class, show as `1960w1`, `2023m2`, `1959q4`, `1961h2` and `2024`, or by
masks such as `Mon_CCYY`. Widths are left to the caller. A labelled
value shows its label; a missing value shows `.`, `.a` and so on, or
its label.

`formatValue` is also at `@jbearak/dta-parser/format`, with `MISSING`,
`missingValue`, `isMissing` and their types, without the WebAssembly
module or any Node built-in, so a webview or browser bundle can format
cells it was sent without being allowed to run WebAssembly.

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
| `timestamp` | a `Date`, or text written as given (such as `info.timestamp` of a file read); default now |
| `characteristics` | as `characteristics()` returns them; those of variables not written, and `_dta` notes (`notes` gives those), are left out |
| `sortedBy` | names of the variables the data is sorted by; only the leading names among the variables written are kept |

Each variable:

| field | meaning |
|---|---|
| `name` | 1 to 32 letters, digits or `_`, not starting with a digit |
| `values` | numbers, with `null` or a `MISSING` value for missing; or strings, among which a `Uint8Array` is a binary strL; or a `Float64Array`, as a `NumberColumn` holds them |
| `missing` | with a `Float64Array`: each value's missing code, as `NumberColumn.missing` holds them (0 a number, 1 `.`, 2 to 27 `.a` to `.z`) |
| `type` | `"byte"`, `"int"`, `"long"`, `"float"` or `"double"` (the default) for numbers; for strings, leave it out or give `"strL"` to write strL whatever the length |
| `format` | display format such as `"%9.2f"` or `"%td"`; default the type's |
| `label` | variable label |
| `valueLabels` | name of a set in `valueLabels` |

Strings are written as `strN` (N the longest value in bytes) up to
2045 bytes and as strLs beyond, each distinct strL stored once.
Stata has no missing string; write `""`. A number that does not fit
its type (300 in a byte, 1.5 in an int, a value in the range Stata
reserves for missing codes) throws an error naming the variable.

To write back what you read, pass each variable's `type`, `format`,
`label` and `valueLabels` from `r.variables`, and the sets from
`r.valueLabels(...)`; the [recipe](#copy-a-file-keeping-its-labels)
below does this.

## Recipes

### Copy a file, keeping its labels

```ts
import { type ValueLabels, type WriteVariable } from "@jbearak/dta-parser";
import { openDtaFile, writeDtaFile } from "@jbearak/dta-parser/node";

const r = openDtaFile("survey.dta");
const columns = r.readColumns(r.variables.map((_, i) => i));
const variables: WriteVariable[] = r.variables.map((v, i) => {
  const c = columns[i];
  const meta = { name: v.name, format: v.format, label: v.label, valueLabels: v.valueLabels };
  return c.kind === "number"
    ? { ...meta, type: v.type as WriteVariable["type"], values: c.values, missing: c.missing }
    : { ...meta, values: c.values };
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

## Parquet files

The package reads and writes Parquet files too, keeping what a `.dta`
file says: value labels, variable labels, display formats, `.a` to `.z`,
the data label and notes, and also categoricals (with their levels and
ordering) and time zones. `openParquetFile(path)` returns a
`ParquetReader`, which has the members of `DtaReader` (it implements
the same `TableReader` interface), so code that reads `.dta` files reads
Parquet by changing the open call. `writeParquet` takes the same
`WriteDataset` as `writeDta`. Reads are synchronous; `openParquetAsync`
is the async reader for browsers and remote files. The files are plain
Parquet that pyarrow, pandas, polars, DuckDB, arrow (R), nanoparquet and
hyparquet read; [docs/parquet.md](parquet.md) says what each of them
sees and gives the file's specification. Only flat tables are read and
written: for lists, maps or structs, use parquet-wasm or DuckDB.

Contents:
[Install](#parquet-install) ·
[Read a Parquet file](#read-a-parquet-file) ·
[Read some columns](#read-some-columns-of-a-parquet-file) ·
[Read a range of rows](#read-a-range-of-rows-of-a-parquet-file) ·
[Schema and metadata](#a-parquet-files-schema-and-metadata) ·
[Labels](#labels-in-parquet-files) ·
[Dates and time zones](#dates-and-time-zones-in-parquet-files) ·
[Write a Parquet file](#write-a-parquet-file) ·
[Write labels](#write-labels-to-a-parquet-file) ·
[Keep .a to .z](#keep-a-to-z-in-a-parquet-file) ·
[Files from other tools](#parquet-files-from-other-tools) ·
[What each type becomes](#what-each-parquet-type-becomes-in-typescript) ·
[In a browser or over HTTP](#parquet-in-a-browser-or-over-http) ·
[One reader for both formats](#one-reader-for-dta-and-parquet) ·
[Coming from hyparquet or parquet-wasm](#coming-from-hyparquet-or-parquet-wasm)

### Parquet: install

Parquet needs nothing beyond this package ([Install](#install)): the
reader and writer are in the same WebAssembly module, built from the
same Rust core as the R, Python and Julia packages, with no Arrow or
other JavaScript library. The module with Parquet is 2.2 MB, 421 KB
compressed with brotli. `openParquet`, `openParquetAsync`,
`writeParquet` and `toDate` come from `@jbearak/dta-parser` and use no
Node API, so they run in a browser; `openParquetFile` and
`writeParquetFile` come from `@jbearak/dta-parser/node`.

### Read a Parquet file

This writes the example file as Parquet and reads it back:

```ts
import { openDtaFile, openParquetFile, writeParquetFile } from "@jbearak/dta-parser/node";

// survey.dta as Parquet, labels and all.
const dta = openDtaFile("survey.dta");
const cols = dta.readColumns(dta.variables.map((_, i) => i));
writeParquetFile("survey.parquet", {
  label: dta.info.label,
  notes: dta.notes(),
  valueLabels: { region: dta.valueLabels("region")!, nonresponse: dta.valueLabels("nonresponse")! },
  variables: dta.variables.map((v, i) => ({ ...v, values: cols[i] })),
});
dta.close();

const r = openParquetFile("survey.parquet");
console.log(r.info.nobs, r.variables.map((v) => v.name));
// 6 [ 'id', 'region', 'age', 'income', 'interviewed', 'comment' ]
console.log(r.readRows(0, 2));
// [ [ 1, 1, 34, 2100, 23436, '' ], [ 2, 2, 51, { missing: '.d' }, 23436, 'moved in 2023' ] ]
const [income] = r.readColumns(["income"]);
console.log(income);
// { kind: 'number', values: Float64Array(6) [ 2100, NaN, 1850, NaN, NaN, 3200 ],
//   missing: Uint8Array(6) [ 0, 5, 0, 1, 19, 0 ] }
r.close();
```

`openParquetFile(path)` reads the footer only; each read then reads,
through `fs.readSync`, only the pages it needs, so a file of any size
opens at once. `openParquetFile(fd)` takes a file descriptor you opened
and close yourself, so the file read is the one you checked.
`openParquet(bytes)` reads a `Uint8Array` already in memory. Close a
reader with `close()` or `using`, as for `.dta`.

The columns are the ones `.dta` reads give, so the rest of this page
applies: numbers are `NumberColumn`s (a `Float64Array` with a `missing`
code per row), text is a `StringColumn`, and in `readRows` a missing
value is a `MISSING` object. Parquet adds three things: a text column
can hold nulls (`missing[i]` is 1 and the value is `""`), a categorical
comes back as a `DictionaryColumn`, and a 64-bit integer column whose
values do not all fit a JavaScript number comes back as a
`BigIntColumn`. [What each type becomes](#what-each-parquet-type-becomes-in-typescript)
gives every type.

### Read some columns of a Parquet file

`readColumns` and `readRows` take variables by name or 0-based index, in
the order you want, and only those columns' pages are read from the
file:

```ts
import { openParquetFile } from "@jbearak/dta-parser/node";

using r = openParquetFile("survey.parquet");
console.log(r.readRows(0, 2, ["income", "id"]));   // [ [ 2100, 1 ], [ { missing: '.d' }, 2 ] ]
try {
  r.readColumns(["weight"]);
} catch (e) {
  console.log((e as Error).message);
  // no variable "weight"; the file's are "id", "region", "age", "income", "interviewed", "comment"
}
```

### Read a range of rows of a Parquet file

`readColumns(columns, { start, count })` and `readRows(start, count)`
read a window of rows. Only the row groups that hold the rows are read,
and within them only the pages that do (found through the file's offset
index, or, when it has none, by reading the page headers). Each reader
keeps the pages it decompressed (8 MiB by default, `pageCacheBytes`), so
neighbouring windows, such as a scan in batches, decompress each page
once:

```ts
import { openParquetFile } from "@jbearak/dta-parser/node";

using r = openParquetFile("survey.parquet", { pageCacheBytes: 16 * 2 ** 20 });
const [id] = r.readColumns(["id"], { start: 2, count: 3 });
console.log(id.kind === "number" && Array.from(id.values));   // [ 3, 4, 5 ]
for (let start = 0; start < r.info.nobs; start += 4) {
  const rows = r.readRows(start, Math.min(4, r.info.nobs - start));
  console.log(start, rows.length);   // 0 4, then 4 2
}
console.log(r.readRowsAt([5, 0, 5], ["id"]));   // [ [ 6 ], [ 1 ], [ 6 ] ]
```

A window that runs past the last row throws a `RangeError`
(`DTA_OUT_OF_RANGE`); compute `count` from `r.info.nobs`.
`readRowsAt(rows)` gives the rows listed, in their order, repeats
allowed: rows close together are read as one window, and each page is
decompressed once. `info.rowGroups` gives each row group's first row
and size, to align windows with them.

### A Parquet file's schema and metadata

Everything in the footer is there as soon as the file is open, before
any data is read: the rows, the row groups, the codecs, the writer, and
per variable its type, the column kind it reads as, its Parquet types,
labels, and each row group's sizes and statistics.

```ts
import { openParquetFile } from "@jbearak/dta-parser/node";

using r = openParquetFile("survey.parquet");
const { nobs, rowGroups, compression, createdBy, label } = r.info;
console.log(nobs, rowGroups.length, compression, createdBy, label);
// 6 1 [ 'snappy' ] dta-parquet version 0.1.0 Household survey (example)
const income = r.variables[3];
console.log(income.type, income.columnKind, income.physicalType, income.label, income.valueLabels);
// double number DOUBLE Monthly income nonresponse
const chunk = r.variables[2].chunks[0]!;
console.log(chunk.min, chunk.max, chunk.nullCount, chunk.codec, chunk.compressedBytes);
// 29 62 0 snappy 49
console.log(r.info.keyValue.map((kv) => kv.key));   // [ 'dta', 'ARROW:schema' ]
```

| where | holds |
|---|---|
| `info.format` | `"parquet"` (`"dta"` for a `DtaReader`) |
| `info.nobs`, `info.label`, `info.notes`, `info.sortedBy` | rows; the data label, notes and sort order from the dta profile |
| `info.rowGroups` | per row group: `firstRow`, `rows`, `compressedBytes`, `uncompressedBytes` |
| `info.compression`, `info.createdBy` | the codecs used; the writer the file names |
| `info.footerBytes`, `info.keyValue` | the footer's size; each key-value metadata entry's `key` and `bytes` |
| `info.warnings` | warnings about a damaged or newer dta profile (the values are still read); value label sets are read when `valueLabels` is first called, and a damaged one is then left out |
| `variables[i].name`, `.type`, `.format`, `.label`, `.valueLabels` | as for `.dta`; `type` is listed under [What each type becomes](#what-each-parquet-type-becomes-in-typescript) |
| `.role` | `"data"`, or `"nested"` for a list, map or struct, which is not read |
| `.physicalType`, `.logicalType` | Parquet's own types, such as `"INT32"` and `"INT(8, signed)"` |
| `.columnKind` | what `readColumns` returns: `"number"`, `"bigint"`, `"string"` or `"dictionary"`; null for a column not read, with `.notRead` saying why |
| `.unit`, `.timeZone` | a date's, time's or timestamp's unit and zone |
| `.categorical` | a categorical's `levels` and whether they are `ordered` |
| `.int64` | for a 64-bit integer column, the kind it reads as and the reason |
| `.storage` | the storage type of a column written as DOUBLE because it holds `.a` to `.z` |
| `.chunks[g]` | row group `g`'s `compressedBytes`, `uncompressedBytes`, `codec`, `encodings`, `dictionaryPageBytes`, `nullCount`, `min`, `max` |
| `keyValue(key)` | a key-value metadata entry's text, such as `r.keyValue("dta")` |

`min` and `max` are numbers (bigints by the `int64` rule), text or bytes,
as the writer recorded them, and null where the file does not say.

### Labels in Parquet files

Variable labels, value labels, the data label and notes are in the file
(in its dta profile), and the reader gives them as a `DtaReader` does:

```ts
import { formatValue } from "@jbearak/dta-parser";
import { openParquetFile } from "@jbearak/dta-parser/node";

using r = openParquetFile("survey.parquet");
const region = r.variables[1];
console.log(region.label, region.valueLabels);   // Region region
const labels = r.valueLabels(region.valueLabels)!;
console.log(labels.get(2));                      // South
const [codes] = r.readColumns(["region"]);
if (codes.kind === "number") console.log(Array.from(codes.values, (c) => labels.get(c)));
// [ 'North', 'South', 'South', 'East', 'West', 'North' ]
const [row] = r.readRows(1, 1, ["income"]);
console.log(formatValue(row[0], r.variables[3].format, r.valueLabels("nonresponse")));   // Don't know
console.log(r.info.label, r.notes());
// Household survey (example) [ 'Made up for the dta-parser documentation.' ]
```

Value labels map codes, including missing values, to text, as for
`.dta` ([Value labels](#value-labels)). A categorical (a `DictionaryColumn`)
already holds its text: `values[codes[i]]`. Other tools do not read our
labels: they see the codes. A file from another tool has none.

### Dates and time zones in Parquet files

A Parquet date or timestamp comes back as a number (or a bigint, by the
`int64` rule): a date counts days since 1970-01-01 (`unit` `"day"`), a
timestamp counts its unit (`"ms"`, `"us"` or `"ns"`) since 1970-01-01
00:00. Nothing is rounded: microseconds and nanoseconds keep every
digit. `toDate(value, variable)` gives a JavaScript `Date` when the
value is within a `Date`'s range (finer than a millisecond is dropped),
and null otherwise. A timestamp with `timeZone` is an instant, shown in
that zone; one without is a clock time with no zone.

```ts
import { toDate, writeParquet, openParquet } from "@jbearak/dta-parser";

const bytes = writeParquet({
  variables: [
    { name: "born", type: "date", values: [0, 19_783, null] },
    { name: "seen", type: "timestamp", unit: "us", timeZone: "America/New_York",
      values: [1_709_301_600_123_456, 0, null] },
    { name: "logged", type: "timestamp", unit: "ns", values: [1_709_301_600_000_000_001n, -1n, null] },
  ],
});
const r = openParquet(bytes);
const [born, seen, logged] = r.variables;
console.log(born.unit, seen.unit, seen.timeZone, logged.timeZone, logged.columnKind);
// day us America/New_York undefined bigint
const [row] = r.readRows(0, 1);
console.log(row);   // [ 0, 1709301600123456, 1709301600000000001n ]
console.log(toDate(row[1] as number, seen)?.toISOString());     // 2024-03-01T14:00:00.123Z
console.log(toDate(19_783, born)?.toISOString());               // 2024-03-01T00:00:00.000Z
console.log(toDate(-1n, logged)?.toISOString());                // 1969-12-31T23:59:59.999Z
console.log(new Intl.DateTimeFormat("en-US", { timeZone: seen.timeZone, timeStyle: "short" })
  .format(toDate(row[1] as number, seen)!));                    // 9:00 AM
```

To write them, give `type: "date"` (days since 1970) or `type:
"timestamp"` with `unit` (`"s"`, `"ms"`, `"us"`, the default, or `"ns"`)
and, for an instant, `timeZone`. Numbers must be whole counts of the
unit; bigints keep nanoseconds past 2^53. A timestamp in seconds, or a
date or timestamp column holding `.a` to `.z`, is written as DOUBLE with
its type in the dta profile, and reads back as it was.

A Stata date held as a number with a `%td` format (as `readDta` gives
it, days since 1960) is written as that number, with its format, and
reads back the same; `formatValue` shows it as for `.dta`. `toDate`
reads it too: `toDate(23436, { format: "%td" })` is 2024-03-01.
`formatValue`'s `%td` counts from 1960, so for a Parquet `DATE` column
(counting from 1970), use `toDate`.

### Write a Parquet file

`writeParquetFile(path, dataset, options?)` writes a file;
`writeParquet(dataset, options?)` returns its bytes, and
`writeParquetTo(dataset, sink, options?)` hands them to `sink` in order.
The dataset is `writeDta`'s `WriteDataset` ([Write a file](#write-a-file)),
and a variable's `values` may also be a column a reader returned:

```ts
import { MISSING } from "@jbearak/dta-parser";
import { openParquetFile, writeParquetFile } from "@jbearak/dta-parser/node";

writeParquetFile("people.parquet", {
  variables: [
    { name: "id", type: "long", values: [1, 2, 3] },
    { name: "score", type: "float", values: [0.5, null, 2.25] },
    { name: "name", values: ["Ana", null, "Bo"] },
    { name: "visits", type: "int64", values: [10n, 2n ** 60n, null] },
    { name: "smoker", type: "bool", values: [1, 0, null] },
    { name: "group", type: "categorical", levels: ["control", "treated"], values: [0, 1, 1] },
  ],
}, { compression: "zstd", rowGroupSize: 100_000 });
using r = openParquetFile("people.parquet");
console.log(r.variables.map((v) => `${v.name}:${v.physicalType}:${v.columnKind}`).join(" "));
// id:INT32:number score:FLOAT:number name:BYTE_ARRAY:string visits:INT64:bigint smoker:BOOLEAN:number group:BYTE_ARRAY:dictionary
```

| `type` | values | written as |
|---|---|---|
| `"byte"`, `"int"`, `"long"` | whole numbers within the type | INT32 annotated INT(8), INT(16), or none |
| `"float"`, `"double"` (the default for numbers) | numbers a float holds exactly; any number | FLOAT, DOUBLE |
| `"int64"` | bigints, or safe integers | INT64 |
| `"bool"` | 0 and 1 | BOOLEAN |
| `"date"`, `"timestamp"` | see [Dates](#dates-and-time-zones-in-parquet-files) | INT32 DATE, INT64 TIMESTAMP |
| `"string"`, `"strL"`, strN, or none with strings | text | BYTE_ARRAY STRING |
| `"binary"`, or any Uint8Array among the values | bytes (text values become their UTF-8 bytes) | BYTE_ARRAY |
| `"categorical"`, or a `DictionaryColumn` | level codes from 0 with `levels` (and `ordered`) | dictionary-encoded BYTE_ARRAY STRING, every level in order in every row group |

In every column `null` (and `MISSING["."]`) is a null. A value that does
not fit its type is an error naming the variable and row (`row 0 holds
1000, which a byte column cannot hold`), and `writeParquetFile` then
leaves no file.

The options (`ParquetWriteOptions`): `compression` is `"snappy"` (the
default), `"zstd"`, `"gzip"`, `"lz4_raw"` or `"none"`, with
`compressionLevel` where the codec has levels. Snappy is the default,
as in the other languages' packages, because other tools read our
snappy files faster than our zstd ones
([the measurements](parquet.md#defaults-and-the-measurements-behind-them));
zstd files of survey data are about a sixth smaller. zstd is C libzstd,
compiled into the module, with all its levels. `rowGroupSize` sets rows per row group; by default a row
group holds up to 262,144 rows and about 1 GiB of values, so a survey
file is one row group, as pyarrow and polars write it. `missingLetters`
is described [below](#keep-a-to-z-in-a-parquet-file). Every file has
statistics and an offset index, so other readers can skip row groups and
pages.

### Write labels to a Parquet file

Labels go in as for `writeDta`: `label` on a variable, `valueLabels`
naming a set in the dataset's `valueLabels`, and the dataset's `label`
and `notes`. Read them back to check:

```ts
import { MISSING, openParquet, writeParquet, type Missing } from "@jbearak/dta-parser";

const bytes = writeParquet({
  label: "Smoking survey, 2024",
  notes: ["Wave 2 only."],
  valueLabels: { yesno: new Map<number | Missing, string>([[0, "No"], [1, "Yes"], [MISSING[".r"], "Refused"]]) },
  variables: [{ name: "smokes", type: "byte", label: "Smokes now", valueLabels: "yesno", values: [1, 0, MISSING[".r"]] }],
});
const r = openParquet(bytes);
console.log(r.info.label, r.notes());               // Smoking survey, 2024 [ 'Wave 2 only.' ]
console.log(r.variables[0].label, r.variables[0].valueLabels);   // Smokes now yesno
console.log(r.valueLabels("yesno"));
// Map(3) { 0 => 'No', 1 => 'Yes', { missing: '.r' } => 'Refused' }
```

A value label code must be a finite number (within ±2^53 if whole) or a
missing value; two variables may share a set. `characteristics` and
`sortedBy` are kept too.

### Keep .a to .z in a Parquet file

`.a` to `.z` survive a write and a read: in a `NumberColumn` their
`missing` codes are 2 to 27, and in `readRows` they are `MISSING[".a"]`
and so on, told apart from `.` (code 1) and from `NaN`, which is a
value:

```ts
import { MISSING, openParquet, writeParquet } from "@jbearak/dta-parser";

const bytes = writeParquet({
  variables: [{ name: "x", type: "byte", values: [1, null, MISSING[".a"], MISSING[".z"]] }],
});
const r = openParquet(bytes);
const [x] = r.readColumns(["x"]);
console.log(x.kind === "number" && x.missing);   // Uint8Array(4) [ 0, 1, 2, 27 ]
console.log(r.readRows(0, 4).map((row) => row[0]));
// [ 1, { missing: '.' }, { missing: '.a' }, { missing: '.z' } ]
console.log(r.variables[0].type, r.variables[0].physicalType);   // byte DOUBLE
const plain = openParquet(writeParquet({ variables: [{ name: "x", type: "byte", values: [1, MISSING[".a"]] }] }, { missingLetters: false }));
console.log(plain.readRows(0, 2).map((row) => row[0]), plain.variables[0].physicalType);
// [ 1, { missing: '.' } ] INT32
```

`.` is a Parquet null. `.a` to `.z` are written as tagged NaNs, the bit
pattern R and haven use for them, so a column that holds any is written
as DOUBLE, with its storage type (`byte` above) in the dta profile, and
reads back as that type. Other tools see them differently: arrow (R),
nanoparquet and DuckDB in R give the letters back; pandas reads them as
missing; pyarrow, polars and DuckDB SQL see NaN, which `IS NULL` does
not match (use `x IS NULL OR isnan(x)`); hyparquet gives `NaN`.
`missingLetters: false` writes them as nulls instead, for files meant
for those tools; the letters are then lost.

### Parquet files from other tools

The reader reads every flat file pyarrow, pandas, polars, DuckDB, arrow
(R), nanoparquet, fastparquet, Parquet2.jl and hyparquet-writer write:

- **Codecs**: none, snappy, gzip, zstd, lz4_raw and brotli. LZO and the
  Hadoop framing of LZ4 are errors that name them.
- **Encodings**: PLAIN, dictionary (PLAIN_DICTIONARY and
  RLE_DICTIONARY), RLE and BIT_PACKED levels, RLE booleans,
  DELTA_BINARY_PACKED, DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY and
  BYTE_STREAM_SPLIT, in data pages v1 and v2.
- **Types**: every type in the [table below](#what-each-parquet-type-becomes-in-typescript).
  FLOAT16 and INTERVAL columns are listed with `columnKind` null and
  `notRead` saying why; reading them is an error.
- **Not read**: nested columns (lists, maps, structs). They are listed
  with `role` `"nested"`; reading one, or reading every column of a
  file that has any, is an error naming them. Select the columns you
  want, or open with `{ nested: "skip" }` to leave them out of
  `variables`. Encrypted files are an error, and so are datasets split
  over several files (open each file).

```ts
import { openParquet, writeParquet } from "@jbearak/dta-parser";

// A stand-in for another tool's file: plain columns, no dta profile.
const bytes = writeParquet({ variables: [{ name: "id", values: [1, 2] }, { name: "city", values: ["Oslo", null] }] });
const r = openParquet(bytes, { nested: "skip", int64: "auto" });
for (const v of r.variables) console.log(v.name, v.physicalType, v.logicalType, v.columnKind);
// id DOUBLE  number
// city BYTE_ARRAY STRING string
console.log(r.readRows(0, 2));   // [ [ 1, 'Oslo' ], [ 2, { missing: '.' } ] ]
```

A pandas `category`, polars `Categorical` or arrow factor (a dictionary
of strings in the file's `ARROW:schema`) comes back as a
`DictionaryColumn` whose levels are the values of the rows read, in
order of first appearance, so two windows of one column can have
different levels; a file this package writes keeps every level, in
order, instead. A timestamp's zone comes from the dta profile, else
from `ARROW:schema`, else is `"UTC"`. Other tools' files have no labels
and no `.a` to `.z`. [docs/parquet.md](parquet.md#what-other-tools-see-in-our-files)
says what other tools see in the files this package writes.

### What each Parquet type becomes in TypeScript

Every conversion is exact or an error; no value changes without one.

| Parquet | `variables[i].type` | `readColumns` gives | `readRows` cell |
|---|---|---|---|
| INT32: INT(8), INT(16), none | `byte`, `int`, `long` | `NumberColumn` (`Float64Array`, as for `.dta`) | `number` |
| unsigned 8, 16, 32 bits | `uint8`, `uint16`, `uint32` | `NumberColumn` | `number` |
| INT64, unsigned 64 bits | `int64`, `uint64` | `int64: "auto"` (default): `NumberColumn` when every row group's statistics keep every value within the safe integers (±(2^53 − 1)), else `BigIntColumn`; decided at open, so every window has one kind, and each value read as a number is checked | `number` or `bigint` |
| FLOAT, DOUBLE | `float`, `double` | `NumberColumn`; NaN is a value (`missing[i]` 0) | `number` |
| DOUBLE written for `.a` to `.z` | its storage type (`byte` ... `float`), or `date`/`timestamp` | `NumberColumn`, the letters as codes 2 to 27 | `number` or `Missing` |
| BOOLEAN | `bool` | `NumberColumn` of 0 and 1 | `number` |
| DECIMAL, precision ≤ 15 | `decimal` | `NumberColumn`, the nearest double to each value | `number` |
| DECIMAL, precision > 15 | `decimal` | `StringColumn`, every digit kept | `string` |
| DATE | `date` | `NumberColumn` of days since 1970, `unit` `"day"`; `toDate` | `number` |
| TIMESTAMP (and INT96) | `timestamp` | counts of `unit` since 1970 (INT96 as nanoseconds), by the INT64 rule; `timeZone` for an instant; `toDate` | `number` or `bigint` |
| TIME | `time` | counts of `unit` since midnight, by the INT64 rule | `number` or `bigint` |
| STRING, ENUM, JSON | `string` | `StringColumn`; `missing[i]` 1 for a null | `string`, or `MISSING["."]` for a null |
| BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY (with UUID) unannotated | `binary` | `StringColumn` of `Uint8Array` | `Uint8Array` |
| a categorical (dta profile) | `categorical` | `DictionaryColumn`: every level, in order; `categorical.ordered` | `string` |
| a dictionary of strings in `ARROW:schema` | `categorical` | `DictionaryColumn`, levels from the rows read | `string` |
| a dictionary of other values in `ARROW:schema` | its value type | as that type | as that type |
| null, anywhere | | `missing[i]` 1 | `MISSING["."]` |

Numbers are `Float64Array`s for every Parquet number type, as for
`.dta`: that keeps one column type across both formats, at twice the
memory of an `Int32Array` for 32-bit columns.

### Parquet in a browser or over HTTP

`openParquetAsync(readAt, size, options?)` reads a file through an async
function that returns bytes, such as HTTP range requests. It fetches the
footer (the last 512 KiB, then more if the footer is longer) and the
offset indexes, then each call fetches the byte ranges it needs and
decodes them with the same code as the synchronous reader, so the
results are the same. Its `readColumns`, `readRows` and `readRowsAt`
return promises; the rest is as `ParquetReader`.

```ts
import { readFileSync } from "node:fs";
import { openParquetAsync } from "@jbearak/dta-parser";

const file = readFileSync("survey.parquet");
// In a browser: fetch(url, { headers: { Range: `bytes=${offset}-${offset + length - 1}` } })
const readAt = async (offset: number, length: number) => file.subarray(offset, offset + length);
const r = await openParquetAsync(readAt, file.length);
console.log(await r.readRows(4, 2, ["id", "income"]));   // [ [ 5, { missing: '.r' } ], [ 6, 3200 ] ]
r.close();
```

Fetched ranges are kept up to `pageCacheBytes` (8 MiB by default), so
neighbouring windows do not fetch again.

### One reader for .dta and Parquet

`DtaReader` and `ParquetReader` both implement `TableReader`: `info`
(with `format`, `nobs`, `label`, `sortedBy`), `variables`,
`readColumns`, `readRows`, `readRowsAt`, `valueLabels`, `close` and
`[Symbol.dispose]`, all synchronous. `AsyncParquetReader` implements
`AsyncTableReader`, the same members with promises. A viewer can take
either file:

```ts
import { type TableReader } from "@jbearak/dta-parser";
import { openDtaFile, openParquetFile } from "@jbearak/dta-parser/node";

const open = (path: string): TableReader => (path.endsWith(".parquet") ? openParquetFile(path) : openDtaFile(path));
for (const path of ["survey.dta", "survey.parquet"]) {
  using r = open(path);
  console.log(r.info.format, r.readRows(0, 1, ["id", "income"])[0]);
}
// dta [ 1, 2100 ]
// parquet [ 1, 2100 ]
```

Cells and columns from a Parquet file may also be `bigint`s and
`BigIntColumn`s (`TableCell`, `TableColumn`). `ParquetReader` also has
`notes()`, `characteristics()` and `keyValue(key)`.

### Coming from hyparquet or parquet-wasm

| hyparquet, hyparquet-writer | parquet-wasm | this package | what changes |
|---|---|---|---|
| `await parquetReadObjects({ file })` | `readParquet(bytes)` then `tableFromIPC(table.intoIPCStream())` | `openParquet(bytes).readColumns(cols)` or `.readRows(0, n)` | synchronous; columns are typed arrays with a `missing` array, not plain arrays or Arrow vectors; nothing to free |
| `asyncBufferFromFile(name)` | `ParquetFile.fromFile(blob)` | `openParquetFile(path)` (sync), `openParquetAsync(readAt, size)` | the sync reader reads through `fs.readSync`, only the pages needed |
| `asyncBufferFromUrl({ url })` | `ParquetFile.fromUrl(url)` | `openParquetAsync(readAt, size)` with your own range requests | you control the fetch |
| `columns: ["a", "b"]` | `columns` (ignored by the sync `readParquet` in 0.9.0) | `readColumns(["a", "b"])`, names or indices | only those columns' pages are read |
| `rowStart`, `rowEnd` | `offset`, `limit` | `{ start, count }`, `readRowsAt(rows)` | a window past the end throws; rows in any order |
| `parquetMetadata`, `parquetSchema` | `readMetadata`, `readSchema` | `info`, `variables` | read at open; per variable the column kind it reads as, statistics per row group |
| INT64 always `bigint` | `BigInt64Array` | a `NumberColumn` when it fits (checked), else `BigIntColumn` | see `int64` |
| timestamps as `Date` (millisecond, zone ignored) | Arrow timestamps | exact counts with `unit` and `timeZone`; `toDate` | nothing rounded |
| DECIMAL as `number` | Arrow decimal | number up to 15 digits, else text with every digit | exact or text |
| dictionary values dereferenced | Arrow `Dictionary` | `DictionaryColumn` (codes and levels) for categoricals | |
| key-value metadata (`kvMetadata`) | `setKeyValueMetadata` | `keyValue(key)`; labels and formats in the dta profile, read for you | |
| `parquetWriteBuffer({ columnData })` | `writeParquet(table, props)` | `writeParquet({ variables })`, `writeParquetFile` | snappy by default; statistics and offset index always |
| `codec`, `rowGroupSize` | `setCompression`, `setMaxRowGroupSize` | `compression`, `rowGroupSize` | |
| null | null | `missing[i]` 1; `MISSING["."]` in rows | `.a` to `.z` kept as well |

Nested columns are the one thing they read that this package does not.

## Threads

WebAssembly runs on one thread, so the npm package reads and writes on one thread. The R, Python and Julia packages use up to three on large files.

## Errors

Every error the package throws has a `code`, so you can act on what
went wrong without matching its message:

| `code` | means | class |
|---|---|---|
| `DTA_CORRUPT` | the file is damaged, or is not a .dta file | `Error` |
| `DTA_TOO_LARGE` | the file is fine, but a value or read does not fit in memory | `Error` |
| `DTA_IO` | reading the file, or writing the output, failed; `cause` holds what your `ReadAt` or sink threw | `Error` |
| `DTA_INVALID` | an argument is wrong: an unknown encoding, or data that cannot be written | `TypeError` or `RangeError` |
| `DTA_OUT_OF_RANGE` | a variable or rows the file does not have | `RangeError` |
| `DTA_CLOSED` | the reader was closed | `Error` |
| `DTA_INTERNAL` | a bug in dta-parser; please report it | `Error` |

```ts
import { openDtaFile } from "@jbearak/dta-parser/node";
import type { DtaError } from "@jbearak/dta-parser";

try {
  openDtaFile("survey.dta").readColumns(["no_such_variable"]);
} catch (e) {
  console.log((e as DtaError).code);   // DTA_OUT_OF_RANGE
}
```

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

**"dta-parser was called from inside a ReadAt callback or write
sink".** A `ReadAt` function passed to `new DtaReader`, or a sink
passed to `writeDtaTo`, may not call the package while it runs; do that
work after the outer call returns.

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
  `readColumns(columns, range?)` (`range` is a `ReadRange`: `start`,
  `count`, `strings: "dictionary"` for `DictionaryColumn`s, and
  `maxStringBytes` for `PreviewColumn`s), `readRows(start, count, columns?)`,
  `readRowsAt(rows, columns?)`,
  `valueLabels(name)`, `notes()`, `characteristics()`, `strlIndex()`,
  `close()`, and
  `[Symbol.dispose]()` (so `using` closes it).
- `writeDta(dataset)`, `writeDtaTo(dataset, sink)`: write release 118.
- `MISSING`, `missingValue(code)`, `isMissing(cell)`: missing values.
- `stataKey(cell)`, `stataKeys(column)`: Stata's sort order as numbers.
- `formatValue(cell, format, labels?)`: show a value for display, as
  R prints it.
- `openParquet(bytes, options?)`: open a Parquet file held in a
  `Uint8Array`; `class ParquetReader`, the open file, with the members
  of `DtaReader` (but `strlIndex`) and `keyValue(key)`. `new
  ParquetReader(read, length, options?)` opens any source given a
  `ReadAt`. `options` is a `ParquetOptions`: `nested` (`"error"` or
  `"skip"`), `int64` (`"auto"`, `"bigint"` or `"number"`) and
  `pageCacheBytes`. See [Parquet files](#parquet-files).
- `openParquetAsync(readAt, size, options?)`: a Parquet file read
  through an async function; resolves to an `AsyncParquetReader`.
- `writeParquet(dataset, options?)`, `writeParquetTo(dataset, sink,
  options?)`: write Parquet; `options` is a `ParquetWriteOptions`
  (`compression`, `compressionLevel`, `rowGroupSize`, `missingLetters`).
- `toDate(value, variable)`: a date or timestamp value as a `Date`, or
  null.
- Types for both formats: `TableReader` and `AsyncTableReader` (what
  `DtaReader`, `ParquetReader` and `AsyncParquetReader` implement),
  `TableInfo`, `TableColumn`, `TableCell`, `BigIntColumn`. For Parquet:
  `ParquetInfo`, `ParquetVariable`, `RowGroup`, `ColumnChunk`,
  `Statistic`, `ParquetOptions`, `ParquetWriteOptions`.
- Types: `DtaError` (an error with a `code`), `ErrorCode` (the codes
  under [Errors](#errors)), `Missing`, `MissingName` (`"."` and `".a"` to `".z"`), `Cell`, `Variable`, `Info`, `NumberColumn`,
  `StringColumn`, `Column`, `DictionaryColumn`, `PreviewColumn`, `ReadRange`, `ValueLabels`, `Characteristic`, `Options`
  (`encoding`, `strlIndex`), `EncodingName` (`"windows-1252"`, `"latin1"`,
  `"utf-8"`), `ReadAt`, `WriteVariable`, `WriteDataset`.

From `@jbearak/dta-parser/format` (no WebAssembly, no Node built-ins):

- `formatValue`, `MISSING`, `missingValue`, `isMissing`, and the types
  `Cell`, `Missing`, `MissingName`, `ValueLabels`, as above.

From `@jbearak/dta-parser/node`:

- `openDtaFile(pathOrFd, options?)`: open a file on disk.
- `writeDtaFile(path, dataset)`: write a file to disk; on an error the
  partial file is removed.
- `openParquetFile(pathOrFd, options?)`: open a Parquet file on disk.
- `writeParquetFile(path, dataset, options?)`: write a Parquet file to
  disk; on an error the partial file is removed.
