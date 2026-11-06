# Parquet in TypeScript: can the docs alone get you there?

Source used: `typescript/docs.md` only (README, docs/parquet.md, the TypeScript Parquet sections, and the
API excerpts at the end). Package built from `typescript/checkout`, installed into `scratch` with
`npm install ../checkout/js` (a symlink). Node v26.12.1. Scripts are `scratch/t*.ts`, run with `node tN.ts`
(Node's type stripping); I also type-checked them with the checkout's `tsc` (`scratch/tsconfig.json`).

No Stata was run; every `.dta` and Parquet file read was written by this library, except the task-11 files,
which R's `arrow` (26.0.0) wrote (`mk11.R`). Python had pandas 3.0.5 but no Parquet engine (no pyarrow, polars,
duckdb, fastparquet); R had `arrow` (used), but not nanoparquet or duckdb; Julia errored when I queried its packages, so I did not use it.

## Summary table

| # | outcome | doc problem |
|---|---|---|
| 1 | succeeded (after a build workaround) | The Homebrew-cargo fix (`CARGO=~/.cargo/bin/cargo`) does not work where rustup has no `~/.cargo/bin` proxies; `rustc` must come first on `PATH` too |
| 2 | succeeded | There is no "usual table type" in TypeScript; the docs never say what to make of the typed-array columns |
| 3 | succeeded | none |
| 4 | succeeded | none (error text not quoted in the docs; it is `rows 4 to 9 are outside 0 to 6`) |
| 5 | succeeded | none; `info.keyValue` lists keys and sizes only, text needs `keyValue(key)` (documented) |
| 6 | succeeded | The Labels example's `formatValue(row[0], ...)` does not type-check (`TableCell` includes `bigint`); `valueLabels` is `""` for no label, not documented |
| 7 | succeeded | none; the `"UTC"`/`undefined` zone distinction is only implied |
| 8 | succeeded | The `maxStringBytes` error row does not say it is a `readColumns` range option; passing it elsewhere is ignored |
| 9 | succeeded | none |
| 10 | succeeded | none |
| 11 | succeeded | `parquet.md` says "the one encoding not read is BIT_PACKED", while `typescript.md` lists more not-read things (nested, FLOAT16, INTERVAL, LZO, Hadoop LZ4, encrypted, multi-file) |

## Task 1: install the packages Parquet needs, check they load: succeeded (with a workaround)

The docs say "Parquet needs nothing beyond this package" so there is nothing to install beyond building the checkout.

```sh
cd checkout
scripts/build-wasm.sh            # FAILED: can't find crate for `core` / `std`
```

This machine has Homebrew's `cargo`/`rustc` first on `PATH` and rustup's stable toolchain (with the wasm32 target) in
`~/.rustup/toolchains/stable-aarch64-apple-darwin`. The docs' Troubleshooting says to use
`CARGO=~/.cargo/bin/cargo scripts/build-wasm.sh`. There is no `~/.cargo/bin` here. `CARGO=$(rustup which cargo) scripts/build-wasm.sh`
still failed with the same error, because the Homebrew `rustc` was still found first. What worked:

```sh
export PATH=$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH
scripts/build-wasm.sh            # ok, ~20 s
cd js && npm ci && npm run build # ok (npm warns that esbuild's postinstall is not covered by allowScripts; harmless)
cd ../../scratch && npm init -y && npm pkg set type=module && npm install ../checkout/js
```

Doc problem. Quote: "the `cargo` first on your `PATH` is not rustup's (Homebrew's Rust, for example) and has no WebAssembly
target. Point the script at rustup's: `CARGO=~/.cargo/bin/cargo scripts/build-wasm.sh`." This is incomplete: the `rustc` on
`PATH` matters too, and `~/.cargo/bin` may not exist. Suggest "put rustup's toolchain `bin` directory (`dirname $(rustup which cargo)`)
first on `PATH`".

Check (`t1.ts`): `openParquet`, `openParquetAsync`, `writeParquet`, `toDate` are functions from `@jbearak/dta-parser`;
`openParquetFile`, `writeParquetFile` from `@jbearak/dta-parser/node`; a write and read of three numbers gave `3 [[1],[2],[3]]`.

## Task 2: write and read a six-column table: succeeded

```ts
writeParquetFile("t2.parquet", { variables: [
  { name: "i", type: "long", values: [1,2,3,4,5,6] },
  { name: "f", type: "double", values: [0.5,1.5,null,3.25,4,5] },
  { name: "s", values: ["a","b",null,"d","e","f"] },
  { name: "b", type: "bool", values: [1,0,1,null,0,1] },
  { name: "d", type: "date", values: [0,1,19783,19784,null,20000] },
  { name: "t", type: "timestamp", values: [0,1_000_000,1_709_301_600_123_456,5,6,null] },
]});
using r = openParquetFile("t2.parquet");
r.variables.map(v => ...); r.readColumns(r.variables.map((_, i) => i)); r.readRows(0, 6);
```

What each became (`variables[i].type`, `columnKind`, Parquet physical/logical type):

| column | type | readColumns kind | physical / logical |
|---|---|---|---|
| i | long | NumberColumn | INT32 |
| f | double | NumberColumn | DOUBLE |
| s | string | StringColumn | BYTE_ARRAY / STRING |
| b | bool | NumberColumn (0/1) | BOOLEAN |
| d | date | NumberColumn, unit `day` (days since 1970) | INT32 / DATE |
| t | timestamp | NumberColumn, unit `us`, no zone | INT64 / TIMESTAMP(MICROS, local) |

Nulls: `missing[i]` is 1 (value `NaN` for numbers, `""` for text); in `readRows` they are `{ missing: '.' }`. There is no data-frame type in
TypeScript; "the usual table type" is the set of typed-array columns (`NumberColumn`, `StringColumn`, ...) or rows
(`TableCell[][]`). Doc gap: the docs never say there is no object-of-arrays or table form, or how to turn columns into one.
The README says "typed arrays per column, or rows", which is the only hint.

## Task 3: two columns, reversed order; a missing column: succeeded

```ts
r.readColumns(["t", "i"]);          // 2 columns, in that order
r.readRows(0, 2, ["t", "i"]);       // [ [ 0, 1 ], [ 1000000, 2 ] ]
r.readColumns(["nope"]);            // RangeError, code DTA_OUT_OF_RANGE
r.readColumns([99]);                // RangeError, code DTA_OUT_OF_RANGE
```

Order returned is the order asked for. Error messages: `no variable "nope"; the file's are "i", "f", "s", "b", "d", "t"` and
`no variable 99; the file's are ...`. This matches the docs' table (`DTA_OUT_OF_RANGE`). No problems.

## Task 4: rows 3 to 5; rows past the end: succeeded

```ts
r.readRows(2, 3, ["i","s"]);                       // [[3, {missing:'.'}], [4,'d'], [5,'e']]
r.readColumns(["i"], { start: 2, count: 3 });      // values [3,4,5]
r.readRows(4, 5, ["i"]);   // RangeError DTA_OUT_OF_RANGE: rows 4 to 9 are outside 0 to 6
r.readRows(6, 1, ["i"]);   // same code: rows 6 to 7 are outside 0 to 6
r.readRows(0, 7, ["i"]);   // same code: rows 0 to 7 are outside 0 to 6
```

Rows 3 to 5 are 0-based start 2, count 3 (the docs use `start`/`count`, 0-based; "rows 3 to 5" needs this translation, which
the docs do not spell out). Matches "A window that runs past the last row throws a `RangeError` (`DTA_OUT_OF_RANGE`)".
It does not clip: a window that starts in range but ends past the end is also an error.

## Task 5: names, types, row count, row groups, compression, key-value metadata without reading data: succeeded

```ts
using r = openParquetFile("t2.parquet");
r.variables.map(v => [v.name, v.type, v.physicalType, v.logicalType]);
r.info.nobs;  r.info.rowGroups;  r.info.compression;  r.info.createdBy;
r.info.keyValue;           // [{key,bytes}]
r.keyValue("dta");         // the entry's text
r.variables[0].chunks[0];  // per-chunk codec, encodings, min, max, nullCount
```

Output: `nobs 6`; `rowGroups [{ firstRow: 0, rows: 6, compressedBytes: 280, uncompressedBytes: 288 }]`; `compression [ 'snappy' ]`;
`createdBy dta-parquet version 0.1.0`; `keyValue [ { key: 'dta', bytes: 13 }, { key: 'ARROW:schema', bytes: 632 } ]`;
`r.keyValue("dta")` is `{"version":1}`; `r.keyValue("nothere")` is `undefined`; chunk: `{ codec:'snappy', encodings:['RLE','PLAIN'], nullCount:0, min:1, max:6, ... }`.
No problems; the table under "A Parquet file's schema and metadata" was enough.

## Task 6: .dta with value labels and variable labels to Parquet, labels read back, categorical: succeeded

```ts
writeDtaFile("t6.dta", { label: "Task 6 data", notes: ["a note"],
  valueLabels: { region: new Map([[1,"North"],[2,"South"],[3,"East"],[4,"West"]]),
                 nonresp: new Map([[MISSING[".a"],"Refused"],[MISSING[".z"],"Not asked"]]) },
  variables: [
    { name: "id", type: "long", label: "Respondent id", values: [1,2,3,4,5,6] },
    { name: "region", type: "byte", label: "Region of residence", valueLabels: "region", values: [1,2,2,3,4,1] },
    { name: "income", type: "double", label: "Monthly income", valueLabels: "nonresp",
      values: [2100, MISSING["."], MISSING[".a"], 1850, MISSING[".z"], 3200.5] } ] });
const dta = openDtaFile("t6.dta");
const cols = dta.readColumns(dta.variables.map((_, i) => i));
// then as the docs' "Read a Parquet file" example, with the value-label sets collected from the variables:
writeParquetFile("t6.parquet", { label: dta.info.label, notes: dta.notes(), valueLabels: vl,
  variables: dta.variables.map((v, i) => ({ ...v, values: cols[i] })) });
```

Read back: `region.label` is `Region of residence`; `region.valueLabels` is `region`; `r.valueLabels("region")` is
`Map(4) {1=>'North', 2=>'South', 3=>'East', 4=>'West'}`; code 3 gives `East`. The docs' categorical recipe gave
levels `[ 'North', 'South', 'East', 'West' ]`; written to `t6cat.parquet` and read back as `type: categorical`,
`columnKind: dictionary`, `categorical: { levels: [...], ordered: false }`. `info.label` is `Task 6 data`, `notes()` is `[ 'a note' ]`.

Doc problems:
- The "Read a Parquet file" example hard-codes the label-set names (`region`, `nonresponse`) for the example file;
  to convert any file you have to collect the sets from `variables[i].valueLabels` yourself, as I did. Not wrong, but the
  generic form is not shown.
- `dta.variables[i].valueLabels` is `""` (empty string) for a variable with no label set, and the spread `{...v}` passes
  that to the writer, which accepts it. The docs do not say `""` means none.
- Type error in the docs' example (see task 10 for the code): the Labels section's
  `formatValue(row[0], r.variables[3].format, r.valueLabels("nonresponse"))` with `row` from a `ParquetReader.readRows` fails
  `tsc` (TS2345: `TableCell` is not assignable to `Cell`, because `bigint` is not a `Cell`). It runs, but is not valid
  TypeScript; I reproduced it in `t_types.ts`. `formatValue` takes `Cell`; Parquet cells are `TableCell`.

## Task 7: date, timestamp without a zone, timestamp with a zone: succeeded

```ts
const bytes = writeParquet({ variables: [
  { name: "born",  type: "date", values: [0, 19_783, null] },
  { name: "naive", type: "timestamp", unit: "ms", values: [1_709_301_600_123, 0, null] },
  { name: "seen",  type: "timestamp", unit: "us", timeZone: "America/New_York", values: [1_709_301_600_123_456, 0, null] },
  { name: "secs",  type: "timestamp", unit: "s",  timeZone: "Europe/Paris", values: [1_709_301_600, 0, null] },
  { name: "nanos", type: "timestamp", unit: "ns", timeZone: "UTC", values: [1_709_301_600_000_000_001n, -1n, null] } ] });
```

| column | type / kind | physical / logical | unit | timeZone |
|---|---|---|---|---|
| born | date / number | INT32 / DATE | `day` | undefined |
| naive | timestamp / number | INT64 / TIMESTAMP(MILLIS, local) | `ms` | undefined (a clock time, no zone) |
| seen | timestamp / number | INT64 / TIMESTAMP(MICROS, UTC) | `us` | `America/New_York` |
| secs | timestamp / number | DOUBLE / (none) | `s` | `Europe/Paris` |
| nanos | timestamp / bigint | INT64 / TIMESTAMP(NANOS, UTC) | `ns` | `UTC` |

Values came back as exact counts of the unit (`1709301600123456`, `1709301600000000001n`). `toDate` gives
`2024-03-01T14:00:00.123Z` for `seen`/`naive`, `2024-03-01T00:00:00.000Z` for the date, `1969-12-31T23:59:59.999Z` for `-1n` ns.
The seconds column being DOUBLE is stated in the docs ("A timestamp in seconds ... is written as DOUBLE with its type in
the dta profile"). Nanosecond values past 2^53 come back as `bigint` columns, as documented.

## Task 8: codec and row group size; an error: succeeded

```ts
writeParquetFile("t8.parquet", ds /* 25 rows */, { compression: "zstd", compressionLevel: 5, rowGroupSize: 10 });
using r = openParquetFile("t8.parquet");
r.info.compression;                         // [ 'zstd' ]
r.info.rowGroups.map(g => [g.firstRow, g.rows]);  // [[0,10],[10,10],[20,5]]
r.variables[0].chunks.map(c => c?.codec);   // ['zstd','zstd','zstd']
```

Same check for gzip, lz4_raw and none: codecs and `[[0,10],[10,10],[20,5]]` row groups confirmed. Rows 23 to 24 read back correctly.
Errors the docs mention, all `DTA_INVALID` / `RangeError`:
- `compression: "lzo"`: `unknown compression "lzo"; use one of "snappy", "zstd", "gzip", "lz4_raw" or "none"`
- `compression: "snappy", compressionLevel: 3`: `snappy has no compression levels`
- `compression: "zstd", compressionLevel: 99`: `zstd levels run from 1 to 22, not 99`
- byte column holding 1000: `column "b": row 0 holds 1000, which a byte column cannot hold`; `writeParquetFile` left no file (checked).
- `rowGroupSize: 0`: `rowGroupSize must be a whole number of rows of at least 1, not 0` (not in the docs).
- `maxStringBytes` on a Parquet reader: only throws as a `readColumns` range option (`DTA_INVALID` `TypeError`:
  `maxStringBytes is for .dta files; Parquet strings are read whole`). Passed to `openParquet(...)` options, or as a fourth
  argument to `readRows`, it is silently ignored. Doc problem: the error table row says "`maxStringBytes` on a Parquet reader"
  without saying where the option goes. Minor.
- The docs' errors table for TypeScript has no row for the codec/level errors; they are only in the R/Python tables with those
  languages' option names ("The TypeScript package gives the same messages, with its own option names"). The messages matched
  the Python/R rows word for word, so this worked, but you have to infer it.

## Task 9: variable label, value labels, data label written and checked: succeeded

```ts
writeParquetFile("t9.parquet", { label: "Smoking survey, 2024", notes: ["Wave 2 only.", "Second note"],
  characteristics: [{ variable: "smokes", name: "source", value: "q12" }],
  valueLabels: { yesno: new Map([[0,"No"],[1,"Yes"],[MISSING[".r"],"Refused"],[MISSING[".d"],"Don't know"]]) },
  variables: [ { name: "id", type: "long", label: "Respondent", values: [1,2,3,4] },
    { name: "smokes", type: "byte", label: "Smokes now", valueLabels: "yesno", format: "%8.0g", values: [1,0,MISSING[".r"],MISSING[".d"]] } ] });
```

Read back: `info.label` `Smoking survey, 2024`; `notes()` both notes; `characteristics()` `[{variable:'smokes', name:'source', value:'q12'}]`;
variable `smokes` label `Smokes now`, set `yesno`, format `%8.0g`; `valueLabels("yesno")` is
`Map(4) {0=>'No', 1=>'Yes', {missing:'.r'}=>'Refused', {missing:'.d'}=>"Don't know"}`; `valueLabels("nonexistent")` is `undefined`.
`r.keyValue("dta")` shows the JSON profile with all of this. `smokes` is DOUBLE with `storage: 'byte'`, as documented for a column holding `.a`-`.z`. The
`Characteristic` shape (`variable`, `name`, `value`) is not in the Parquet docs' prose; I took it from the API excerpt and
`tsc` accepted it.

## Task 10: ordinary values plus `.`, `.a`, `.z`: succeeded

Used the `income` column of the task-6 `.dta` file: `[2100, ., .a, 1850, .z, 3200.5]`, written to Parquet by the docs' conversion.

```ts
const [c] = r.readColumns(["income"]);     // NumberColumn
Array.from(c.values);   // [ 2100, NaN, NaN, 1850, NaN, 3200.5 ]
Array.from(c.missing);  // [ 0, 1, 2, 0, 27, 0 ]    0 value, 1 ".", 2 ".a", 27 ".z"
r.readRows(0, 6, ["income"]).map(x => x[0]);
// [ 2100, {missing:'.'}, {missing:'.a'}, 1850, {missing:'.z'}, 3200.5 ]
```

The three kinds are told apart by `missing` code (0, 1, 2 to 27) or by the `{missing: ...}` object in rows. The Parquet file is
DOUBLE (`physicalType` DOUBLE, `type` double). `formatValue(cell, format, labels)` shows `['2100','.','Refused','1850','Not asked','3200.5']`.

What the docs say other tools see (TypeScript "Keep .a to .z"): "arrow (R), nanoparquet and DuckDB in R give the letters back;
pandas reads them as missing; pyarrow, polars and DuckDB SQL see NaN, which `IS NULL` does not match (use `x IS NULL OR isnan(x)`);
hyparquet gives `NaN`." `.` is a Parquet null. `.a` to `.z` are tagged NaNs in a DOUBLE column. `missingLetters: false` writes them as
nulls and the letters are lost. I could not test other tools on `.a` to `.z`: no pyarrow/polars/duckdb here, and pandas has no Parquet engine. I did not
check the docs' `missingLetters: false` example output in this task beyond its type; the docs' own example in the page did show `INT32`.

## Task 11: a file another tool wrote: succeeded

Tool on this machine: R `arrow` 26.0.0 (`mk11.R`; no pyarrow/polars/duckdb/nanoparquet). Files: zstd and snappy files with an
integer, double with null, string with null, logical, Date, POSIXct in America/New_York, and a factor with levels
lo, mid, hi (`t11_arrow*.parquet`), and one with a uint8 and a list column (`t11_nested.parquet`).

```ts
using r = openParquetFile("t11_arrow.parquet");
```

- Types read: integer is `long`, double `double`, string `string`, logical `bool`, Date `date` (unit `day`), the POSIXct is `timestamp`,
  `us`, `timeZone: America/New_York` (from `ARROW:schema`), the factor `categorical` / `DictionaryColumn`, uint8 `uint8`. Nulls are `{missing:'.'}`.
- The factor's levels came back in order of first appearance, `[ 'lo', 'hi', 'mid' ]`, not the R levels (lo, mid, hi), and a window
  `{start:1,count:2}` had only `[ 'hi' ]`: exactly as documented ("levels are the values of the rows read, in order of first appearance").
- zstd and snappy both read, `createdBy` is `parquet-cpp-arrow version 26.0.0`, and the key-values are `r` and `ARROW:schema`.
- The nested list column `l`: listed with `role: 'nested'`, `columnKind: null`, `notRead: 'column "l" is nested (a list, map or group), which is not read'`;
  `readRows(0, 2)` without `columns` throws `DTA_INVALID`: `the file has nested columns, which are not read: "l"; select the columns wanted, or open with nested: "skip"`;
  `readColumns(["l"])` throws `DTA_INVALID`; selecting other columns works; `openParquetFile(path, { nested: "skip" })` drops `l` from `variables`.

What the docs say this library does not read (typescript.md, "Not read"): values encoded BIT_PACKED (BIT_PACKED levels are read); nested
columns (lists, maps, structs; listed with `role: "nested"`, an error to read); encrypted files; datasets split over several files; and FLOAT16 and INTERVAL
columns (listed with `columnKind` null). LZO and the Hadoop framing of LZ4 are errors that name them. Doc problem: `parquet.md` ("Read a file
another tool wrote") says "The one encoding not read is BIT_PACKED for values", which on its own omits nested columns, the codecs, FLOAT16 and
INTERVAL, and encryption; the TypeScript page has the full list.

## Other notes

- Node's type stripping ran the `.ts` scripts directly; with `tsc` strict, only the `formatValue` call above failed. The `using` declarations work on Node 26.
- The docs file's later part is API-reference extracts from the source; I read those only for `WriteVariable`, `WriteDataset` and `ParquetWriteOptions`.
