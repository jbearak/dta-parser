# Plan: datakit in TypeScript; Parquet leaves `@jbearak/dta-parser`

Status: approved at Gate 1 by Claude Sonnet and GPT Terra (revision 8,
after eight rounds; see `docs/judging/datakit-typescript/`).

## Goal

The user asked on 2026-11-08 for a datakit in TypeScript. Plan 0019
decided against one ("TypeScript: Parquet stays in
`@jbearak/dta-parser`"); this plan reverses that decision, answers its
two reasons, and makes the npm side match R, Python and Julia:

1. A new npm package, `@jbearak/datakit`, in `js/datakit/`: reading and
   writing Parquet (moved from `@jbearak/dta-parser`), reading
   fixed-width text through a SAS setup file (new to TypeScript), and
   reading and saving `.dta` into the same in-memory dataset, keeping
   labels and `.a` to `.z` throughout.
2. **The same verbs as the other datakits:** `readParquet`,
   `readParquetInfo`, `saveParquet`, `readDta`, `saveDta` and
   `readFixedWidth`, in TypeScript's camelCase.
3. `@jbearak/dta-parser` 2.0.0 is `.dta` only: its Parquet exports go,
   and so does the Parquet code in its WebAssembly module.
4. **No Stata-style helpers**, as in Python and Julia.
5. **No release.** Nothing goes to npm and no tag is made; the user
   publishes when they choose (AGENTS.md).

## Plan 0019's reasons, answered

1. *table-viewer needs one synchronous `TableReader` over `.dta` and
   Parquet.* It still gets one. The `TableReader` and `AsyncTableReader`
   interfaces, `TableInfo` (`format: "dta" | "parquet"`) and the column
   types (`NumberColumn`, `StringColumn`, `DictionaryColumn`,
   `BigIntColumn`, `TableColumn`, `TableCell`) stay in
   `@jbearak/dta-parser`; datakit's `ParquetReader` implements the same
   interface. A viewer imports `openDtaFile` from
   `@jbearak/dta-parser/node` and `openParquetFile` from
   `@jbearak/datakit/node` and holds either as a `TableReader`. Plan
   0019 said a second package would reach into the first's wasm exports
   or ship a second copy of the core. It ships a second module, on
   purpose (next section), and reaches into nothing: what it imports
   from `@jbearak/dta-parser` is its public API.
2. *No translator targets TypeScript.* datakit is not a translator. It
   is data preparation that keeps Stata's labels and `.a` to `.z`, with
   Parquet as the format the four languages exchange. The user wants it
   in each of them.

## Two WebAssembly modules, not one shared

In R, Python and Julia, datakit calls the format package's native code
through a versioned internal interface (ADR 0032, ADR 0034), because a
second Rust build there means a second compile at install time or a
second binary per wheel. npm is different: the module is prebuilt and
embedded in the package's JavaScript, so a second module costs CI time,
not users' time, and splitting gives the format package's users their
smaller module back. `@jbearak/dta-parser` 1.0.0 unpacked to 570 KB on
npm; 1.1.0, with Parquet and libzstd, to 1.13 MB. manuscript-markdown
and Sight read only `.dta` and carry the Parquet code for nothing.

### The Rust side

`parquet_wasm.rs` uses `wasm.rs`'s `State`, `call`, `copy`,
`ensure_room`, `ensure_room_parts`, `result`, `HostFile`, `HostSink`
and error codes, and both rely on `wasm.rs`'s allocator and error
exports (`dta_alloc`, `dta_free`, `dta_error`, `dta_error_kind`,
`dta_result_len`) and on `dta_test_set`. So `wasm.rs` splits in three:

- `wasm_common.rs`, compiled on wasm32 whatever the features: the
  allocator, the error and result exports, the host imports
  (`host_read`, `host_write`, `host_fill`), `HostFile`, `HostSink`,
  `call`, `copy`, `ensure_room*`, `result`, the error codes, and
  `State`'s shared fields (error, result, budget, chunk size, string
  limit), with `dta_test_set` under `test-hooks`.
- `wasm_dta.rs` under feature `wasm-dta`: the `.dta` exports (`dta_open`
  to `dta_write_finish`) and their handle table, which moves out of
  `State` into its own `thread_local`.
- `parquet_wasm.rs` under feature `wasm-parquet`, with its own handle
  table as now, plus the new fixed-width export (below).

Both features are on by default, so `cargo test` and the native build
(`native.rs`, `parquet_native.rs`, which Julia loads) are unchanged;
`dta-parquet` becomes an optional dependency that `wasm-parquet` and the
native build enable. `scripts/build-wasm.sh` builds
`--no-default-features --features wasm-dta` into `js/build/dta.wasm`
and `--no-default-features --features wasm-parquet` into
`js/datakit/build/datakit.wasm`, and a `test-hooks` build of each for
the memory tests. CI's existing `cargo build -p dta-parquet --target
wasm32-unknown-unknown` step stays. A test per package lists the
module's exports and compares them with the names its wrappers call, so
a missing or stray export fails.

datakit's module holds the Parquet reader and writer, the codecs,
libzstd, and `fixed_width_to_dta`, which brings part of the `.dta`
writer with it. datakit's `readDta` and `saveDta` call dta-parser's
public `openDta` and `writeDta`, not its own module.

### No ABI number

Neither package calls the other's module, so there is no native contract
to version. `@jbearak/datakit` declares `@jbearak/dta-parser`
(`^2.0.0`) a peer dependency, which npm 7 and later install
automatically.

### The JavaScript glue

`js/src/wasm.ts` today holds the generic glue (instantiation from the
deflated bytes, `guard`, `check`, instance replacement, `memView`, the
host callbacks) and every export's wrapper. It splits:

- `js/src/wasm-core.ts`: the generic part, a function that takes the
  embedded bytes and returns the calls over a new instance. Each package
  makes its own instance from its own module.
- `js/src/wasm.ts`: dta-parser's wrappers.
- `js/datakit/src/wasm.ts`: datakit's (`pq*`, fixed width).

datakit's build bundles `wasm-core.ts`, `inflate.ts`, `errors.ts` and
`shared.ts` from `js/src` at build time. The published package imports
none of dta-parser's private files.

### `MISSING`'s identity

`MISSING` holds one frozen object per missing value, and a `ValueLabels`
map is keyed by those objects (`labels.get(MISSING[".r"])`). Each bundle
that contains `values.ts` makes its own objects today:
`@jbearak/dta-parser` and `@jbearak/dta-parser/format` are separate
bundles, so their `MISSING[".r"]` already differ, and datakit would add
a third. A peer dependency does not guarantee one copy of dta-parser
either (separate subtrees, `--legacy-peer-deps`, bundlers).

So in 2.0 `values.ts` makes the 27 objects once per JavaScript realm:
it looks them up on `globalThis` under
`Symbol.for("@jbearak/dta-parser/missing/v1")` and creates them only if
absent (frozen, shape `{ missing: ".r" }` as now). What it finds there
is used only if it is a frozen record of exactly the 27 names, each a
frozen `{ missing: name }`; anything else (another script's value under
the symbol) is ignored and the copy makes private objects. `v1` names
the layout: a later layout takes a new key. Every copy of 2.0 or later,
in either package and any bundle, then hands out the same objects, and
`===` and `Map` lookups work across them. A 1.x copy makes its own; the
migration section says so. `isMissing` stays a shape test.
Tests load `values` from dta-parser's root, `./format` and datakit, and
from two copies of the package in separate directories, and check
identity and label lookups between each pair.

### What datakit imports at run time

datakit's root entry imports only `@jbearak/dta-parser/format`, which
has no wasm. `dtaKey` and `dtaKeys` are pure JavaScript and move there
in 2.0, with their deprecated aliases `stataKey` and `stataKeys`; the
root entry re-exports the same function objects. datakit
re-exports `MISSING`, `isMissing`, `missingValue`, `dtaKey`, `dtaKeys`,
`formatValue` and dta-parser's types. Its `./node` entry loads
`@jbearak/dta-parser/node` on the first call of `readDta`, `saveDta` or
`readFixedWidth`, so a script that only reads and writes Parquet never
compiles the `.dta` module. The import-time measurement checks that.

## Packages after the move

| package | entry | holds |
|---|---|---|
| `@jbearak/dta-parser` 2.0.0 | `.` | `openDta`, `DtaReader`, `writeDta`, `writeDtaTo`, values, `formatValue`, `dtaKey`, `dtaKeys`, `TableReader` and the column types |
| | `./node` | `openDtaFile`, `writeDtaFile` |
| | `./format` | as now, plus `dtaKey`, `dtaKeys` |
| `@jbearak/datakit` 2.0.0 | `.` (no Node API; browsers and webviews) | `openParquet`, `openParquetAsync`, `ParquetReader`, `AsyncParquetReader`, `writeParquet`, `writeParquetTo`, `toDate`, `readDataset`, `readDatasetAsync`, `convertFixedWidth`, the Parquet types, `Dataset`, `DatasetVariable`, `ReadDataset`, `ReadVariable`, and the re-exports above |
| | `./node` | `readParquet`, `readParquetInfo`, `saveParquet`, `readDta`, `saveDta`, `readFixedWidth`, `openParquetFile`, `writeParquetFile` |

The Parquet names keep their 1.1 names and behaviour, so moving to
datakit changes an import path; the one change is that a letter in a
categorical is an error rather than a silent null (`saveDta` below).
datakit's version starts at dta-parser's (2.0.0), the rule dta-datakit
and Datakit.jl followed (0.3.0, their format packages' version).

## The datakit API

### The types

```ts
/** What saveParquet and saveDta take. */
interface Dataset {
  variables: readonly DatasetVariable[];
  label?: string;
  notes?: readonly string[];
  valueLabels?: Readonly<Record<string, ValueLabels>>;
  characteristics?: readonly Characteristic[];
  sortedBy?: readonly string[];
  timestamp?: Date | string;   // .dta only
}
/** dta-parser 1.1's WriteVariable, Parquet fields included. */
interface DatasetVariable {
  name: string;
  values: /* 1.1's WriteVariable.values: number, string, bigint arrays,
             typed arrays, any TableColumn */;
  missing?: Uint8Array;
  type?: "byte" | "int" | "long" | "float" | "double" | "strL" | "bool"
       | "int64" | "uint8" | "uint16" | "uint32" | "uint64" | "date"
       | "timestamp" | "time" | "decimal" | "string" | "binary"
       | "categorical" | (string & {});   // (string & {}): strN
  unit?: string; timeZone?: string;
  levels?: readonly string[]; ordered?: boolean;
  categorical?: { readonly levels: readonly string[] | null; readonly ordered: boolean;
                  readonly labelSet?: string;     // .dta only: the set a restored factor came from
                  readonly codes?: readonly number[] };  // .dta only: each level's code in that set
  format?: string; label?: string; valueLabels?: string;
}
/** What the read functions return: every field filled. */
interface ReadDataset extends Dataset {
  variables: ReadVariable[];
  label: string; notes: string[]; valueLabels: Record<string, ValueLabels>;
  characteristics: Characteristic[]; sortedBy: string[];
}
interface ReadVariable extends DatasetVariable {
  type: string; format: string; label: string; valueLabels: string;
  values: TableColumn;
}
```

A `ReadDataset` is plain data: change `variables` (add, drop, reorder,
replace `values`) and save it. Columns keep `.a` to `.z` in their
`missing` codes, so the letters follow whatever the code does to a
column, unlike polars, where they travel beside the frame (plan 0019).
`saveDta` is where a dataset becomes `.dta`; a `Dataset` is not, in
general, a valid input to dta-parser's `writeDta` (it may hold Parquet
types), and the docs say to use `saveDta`.

dta-parser 2.0's `WriteVariable` loses the Parquet-only members: the
types `bool` to `categorical`, `unit`, `timeZone`, `levels`, `ordered`
and `categorical`, and from `values` the bigint arrays,
`BigInt64Array` and `null` among strings. It keeps `TableColumn` (so a
column a reader returned writes back), which includes `BigIntColumn`;
`writeDta` rejects one at run time, as now.

### `readDataset`

`readDataset(reader, { columns?, start?, count?, onWarning? })` builds a
`ReadDataset` from any `TableReader`. Everything it needs is on the
interface in 2.0:

- `TableReader` and `AsyncTableReader` gain `notes()`,
  `characteristics()` and `valueLabelNames()`. Both readers have the
  first two; `valueLabelNames()` is new on both (every set's name, in
  file order).
- `TableInfo` gains an optional `timestamp` (a `.dta` file's, as
  `Info.timestamp` already is; a Parquet file has none).
- `Variable` gains three optional members, set by a reader whose format
  has them: `unit`, `timeZone` and `categorical`, with the meanings
  `ParquetVariable` gives them now. `DtaReader` sets none of them.

**Factors.** For a `.dta` file (`info.format === "dta"`), `readDataset`
restores plan 0020's factors (this supersedes plan 0020's "npm: no
change" bullet), so the browser path (`openDta` then `readDataset`) and
`readDta` give the same dataset. A column marked `dtaparser_factor`
whose marker still holds under plan 0020's four checks (its value label
set is the one the marker names; every non-missing value has a label; no
two codes share a text; no `.a` to `.z`), and two more that make the
restoration lossless (every code in the set is a whole number within
long's range; the set labels no missing value, `.` to `.z`, whether or
not a row holds one), comes back as a `DictionaryColumn` with `type:
"categorical"`, levels from the label set in order of code and `ordered`
from the marker. The checks do not require codes 1 to k, so the code of
each level is kept, in `categorical.codes` (a set of 10 "low" and 20
"high" gives levels `["low", "high"]`, codes `[10, 20]`). The marker
characteristic is not in `characteristics`. The variable's `valueLabels`
is `""`, so nothing refers to a set, and the set's name is kept as
`categorical.labelSet`; the set itself leaves `valueLabels` unless
another column read uses it. A marked column failing a check comes back
as labelled numbers, its set and marker kept as read, with one warning
per call naming the columns (code `DATAKIT_FACTOR`), given to
`onWarning(messages)` when the caller passes one, else to
`process.emitWarning` where there is one, else to `console.warn`.
`readFixedWidth`'s warnings take the same route.

Otherwise a dataset keeps every value label set the file has, used or
not, and every characteristic; `label`, `sortedBy` and `timestamp` come
from `info` (`timestamp` as the file's text, unchanged, which `saveDta`
writes back as given); each variable's `unit`, `timeZone` and
`categorical` from `variables`. It is the browser-side path and what the
`./node` read functions call. `readDatasetAsync` does the same for an
`AsyncTableReader`. Tests run it on both readers and on a reader written
in the test that implements only the interface.

### `./node`

- `readParquet(path, { columns?, start?, count?, int64?, nested? })`:
  `int64` and `nested` are `ParquetOptions`' (default `"auto"` and
  `"error"`).
- `readParquetInfo(path)`: `info`, `variables`, every value label set,
  notes, characteristics and the key-value metadata keys, from the
  footer; no data read.
- `saveParquet(dataset, path, options?)`: `writeParquetFile`, options as
  `ParquetWriteOptions`.
- `readDta(path, { columns?, start?, count?, encoding?, onWarning? })`:
  `openDtaFile` then `readDataset`, factors restored as above.
- `saveDta(dataset, path, { timestamps?: "error" | "truncate" })`:
  release 118 through `writeDtaFile`, after converting what a `.dta`
  file holds differently. The rules follow Python datakit's `save_dta`:
  - Columns with a `.dta` type (`byte` to `double`, strN, `strL`) are
    written as they are.
  - `string`: strN for values up to 2,045 bytes, else `strL`, as
    `writeDta` chooses for strings with no type; `binary`: `strL`.
  - `bool`, `int64`, `uint8`, `uint16`, `uint32`, `uint64`, and numbers
    with no type: when every value is a whole number, the smallest of
    byte (−127 to 100), int (−32,767 to 32,740) and long
    (−2,147,483,647 to 2,147,483,620) that holds them, so no value
    lands on the codes `.` to `.z` use; otherwise (a fraction, or past
    long) double. A value past ±2^53 is an error naming the variable
    and row. A `BigIntColumn` is converted in bigint arithmetic and
    checked before it becomes a number.
  - `date` (days since 1970): long `%td`, the value + 3,653.
  - `timestamp` (counts of `unit` since 1970): double `%tc`,
    milliseconds since 1960. In bigint arithmetic: `s` × 1,000, `ms` as
    is, `us` ÷ 1,000, `ns` ÷ 1,000,000, then + 315,619,200,000. A
    remainder (a fraction of a millisecond) is an error naming the
    variable and row, or truncated toward minus infinity with
    `timestamps: "truncate"`; a result past ±2^53 is an error either
    way. A `timeZone` is an error saying to convert to clock times
    first, as in Python.
  - A null in a numeric, date or timestamp column is `.`; `.a` to `.z`
    stay letters. A `.dta` string has no missing value, so a null in a
    `string` or `binary` column (or any `StringColumn` whose `missing`
    has a 1) is an error naming the variable and row and saying to fill
    it (with `""`, say) first; nothing is filled silently.
  - `categorical` (a `DictionaryColumn`, or codes with `levels`): codes
    1 to k stored as long, or, for a restored factor, the codes in
    `categorical.codes` (an error naming the variable when `codes` and
    `levels` differ in length, or a code is not a whole number within
    long's range); and a value label set mapping those codes to the
    levels in order. The set's name is `categorical.labelSet` when the
    variable has one (a factor `readDataset` restored), else the
    column's name. If a set by that name already exists, in
    `dataset.valueLabels` (used or not) or written earlier in this save
    for another factor, and maps exactly the same codes to the same
    texts, nothing else, it is reused; if it differs, the new set is
    `name_2`, `name_3`, ... instead, so no set is overwritten. So a
    restored factor gets its own set name back, whatever that name is,
    and so do factors and labelled columns that shared a set. Parquet
    has no place for `labelSet` or `codes`, so a factor that goes
    through a Parquet file comes back to `.dta` as codes 1 to k under
    its column's name, as R writes factors. The variable gets the
    `dtaparser_factor` marker (`ordered set` or `unordered set`, naming
    the set written), as R's dtaparser and Python's dta_parser write
    them (plan 0020). Every `dtaparser_factor` characteristic in
    `dataset.characteristics` is dropped first, so a stale one never
    survives (a marker that failed its checks on reading is dropped this
    way, and its column saved as the labelled numbers it was read as). A
    categorical cannot hold `.a` to `.z`: one read from Parquet has only
    nulls (a `DictionaryColumn`'s `missing` is 0 or 1), written as `.`,
    and one built as codes with `levels` and given a letter is an error
    naming the variable and row, saying to make it labelled numbers (a
    numeric type with a value label set), which keep letters.
    `saveParquet` (and `writeParquet`) raise the same error; 1.1's
    writer turned such a letter into a null silently, the one change to
    the moved code.
  - `decimal`: by what the read gave. One read as a `NumberColumn`
    (precision 15 or less, each value the nearest double) is written as
    double. One read as text (precision above 15) is an error naming
    the variable, saying to parse it into numbers if doubles are close
    enough, or to set `type: "string"` to keep the digits as text.
  - Errors naming the variable: `time`, binary values in a column whose
    type is not `strL` or `binary`, a null string (above), and any type
    not named above.

  Dates and timestamps from a `NumberColumn` may hold fractions (R
  writes Dates as DOUBLE, and the reader gives DOUBLE counts as they
  are). Every finite double is converted exactly: split into an integer
  and a power of two, in bigint arithmetic, so the test for a fraction
  and the truncation are exact, never rounded through another double.
  A `date` with a fraction of a day, or a `timestamp` whose milliseconds
  have a fraction, is an error naming the variable and row; with
  `timestamps: "truncate"` (which covers dates too) it is truncated
  toward minus infinity (−0.5 days is −1). An infinity, or a NaN that is
  not `.` to `.z` (`missing` 0), is an error either way. A `date` must
  land within long's range and a `timestamp` within ±2^53 milliseconds,
  else an error either way.

  A test writes the same Parquet fixture through Python's `save_dta` and
  `saveDta` and compares the two files' storage types, values, formats
  and labels (the polars datakit writes no factor marker, so markers are
  compared with R's instead).
- `readFixedWidth(path, setup, { recodes?, commentedFormats?, columns?,
  start?, count?, onWarning? })`: `setup` is a path or a list of paths
  read in order as one setup. `recodes` is `"setup"` (default),
  `"tagged"` or `"none"`; `commentedFormats` defaults to true; both as
  in R and Python. Returns a `ReadDataset`. Every warning the Rust
  reader gives (skipped statements and value labels, unknown and
  duplicate names, fields that are not numbers, short records, no
  records, cut labels) reaches the caller: one `process.emitWarning`
  (code `DATAKIT_FIXED_WIDTH`) listing the first eight and a count, or,
  with `onWarning(messages)`, every message to that function and no
  emitted warning.

  Memory: the data file is read straight into datakit's module memory
  (one copy, not a JavaScript copy and then a module copy), and the
  `.dta` is streamed to a file created exclusively (mode 0600) in a new
  directory from `fs.mkdtempSync(path.join(os.tmpdir(), "datakit-"))`
  (mode 0700), removed afterwards, also on error. A wasm memory never
  shrinks, so datakit then replaces its instance, which gives the pages
  back, when no Parquet reader is open on it (the rule instance
  replacement already follows); with one open, the pages stay until it
  closes. The file is then read with `openDtaFile` in dta-parser's
  module, whose reads hold at most its 64 MiB budget per call beyond the
  columns. So the peak is the larger of (data file + converter working
  memory) and (dta-parser's read budget + the dataset), plus the dataset
  when datakit's instance cannot be replaced. A data file larger than
  datakit's module can address (4 GiB for everything) is a
  `DTA_TOO_LARGE` error naming the file's size, before any copy.
  Measured on the largest NSFG file (below). The expected bound, peak
  RSS under twice the data file plus the dataset plus 256 MiB, is an
  estimate: the PR records the measured peak and replaces the estimate
  with it.
- `openParquetFile`, `writeParquetFile`: unchanged from 1.1.

### `.` (no Node API)

- The Parquet reader and writer from 1.1, unchanged but for the
  categorical letter error.
- `readDataset`, `readDatasetAsync`.
- `convertFixedWidth(data, setups, options?)`: `data` a `Uint8Array`,
  `setups` `Uint8Array`s or strings; returns `{ dta: Uint8Array,
  warnings: string[] }`, the release 118 bytes, for `openDta`. Memory:
  the data, its copy in the module, and the `.dta` bytes; the docs say
  so.

The new wasm export is `dta_fixed_width(setups, data, recodes,
commented_formats, sink)`: setups and data passed as module memory, the
`.dta` written through `host_write`, the warnings left as JSON. The
native `dta_fixed_width_to_dta` is unchanged.

### Not in datakit

- **A frame library.** JavaScript has no frame library that most data
  code uses, as polars is for Python and DataFrames.jl for Julia.
  nodejs-polars (0.26) is native code for Node only, which rules out
  the browser and webview users the package has; Arquero (8.0) is pure
  JavaScript. A `ReadDataset` keeps labels and `.a` to `.z` in plain
  typed arrays, which either library takes. The docs have one tested
  recipe, a `ReadDataset` into Arquero and back with the letters as a
  companion column of letter strings (plan 0019's `x_letter`), Arquero
  a dev dependency of the docs test only. nodejs-polars is named in
  prose, without code.
- `:=` or another Stata-style helper.
- Lazy or streaming data preparation; `ParquetReader` reads windows for
  that.

## `@jbearak/dta-parser` 2.0.0

- Removed: `openParquet`, `openParquetAsync`, `ParquetReader`,
  `AsyncParquetReader`, `writeParquet`, `writeParquetTo`, `toDate`,
  `openParquetFile`, `writeParquetFile`, and the types `ColumnChunk`,
  `ParquetInfo`, `ParquetOptions`, `ParquetVariable`,
  `ParquetWriteOptions`, `RowGroup`, `Statistic`. Each moves to datakit
  under the same name.
- Kept: `TableReader`, `AsyncTableReader`, `TableInfo`, and every column
  and cell type, including `BigIntColumn` and `TableCell`.
- Changed: `TableReader` and `AsyncTableReader` gain `notes()`,
  `characteristics()` and `valueLabelNames()`; `DtaReader` gains
  `valueLabelNames()`; `TableInfo` gains optional `timestamp`, and
  `Variable` optional `unit`, `timeZone` and `categorical`;
  `WriteVariable` as above; `MISSING`'s objects
  come from the realm's registry; `dtaKey` and `dtaKeys` are also in
  `./format`.
- `package.json`: version 2.0.0, description back to `.dta` only.
- Why a major version: 1.1.0 is on npm with these exports. A 1.2 that
  re-exported them from datakit is impossible without a dependency
  cycle, and keeping two implementations is worse.
  [docs/migration.md](../migration.md) gains "dta-parser 1.x to 2.0":
  each moved name and its import, the `TableReader` additions (a class
  implementing it must add three methods), and that `MISSING` objects
  from 1.x and 2.0 differ.

## Layout, install, CI

- `js/datakit/` with its own `package.json`, `tsconfig.json`,
  `build.mjs`, `src/`, `test/`, `README.md`, `LICENSE` and
  `THIRD-PARTY-NOTICES` (the codecs' and libzstd's notices move there
  from dta-parser's). `js/tsconfig.json` and `js/package.json`'s `files`
  exclude `datakit/`, as `python/datakit` sits beside dta_parser.
- Until both are published, datakit's tests run against the checkout:
  `npm install --no-save ..` in `js/datakit` links dta-parser, and the
  README says how to install both from a checkout.
- CI's `npm` job builds both modules, then tests both packages on Node
  24 and 26. A test packs both (`npm pack`), installs the tarballs into
  an empty directory, and imports each entry, as a user without the
  repository would.
- The `readback` job's `.dta` writer (`compat/readback/write.mjs`) stays
  on dta-parser; `compat/parquet/readback.mjs` (hyparquet reads our
  files) uses datakit. The cross-language Parquet check
  (`compat/parquet/cross_language.sh`) gains TypeScript: it writes the
  fixtures R and Python write and checks every cell of R's, Python's and
  Julia's.
- `.github/workflows/npm-publish.yml` keeps publishing dta-parser only,
  building its module alone. Publishing datakit is the user's to set up
  when they publish.

## Documentation

- `docs/typescript.md` keeps `.dta` and dta-parser. Its "Parquet files"
  section becomes "datakit", with the imports changed and its headings
  kept, plus "Read a whole file" (`readParquet`, `readDta`), "Save a
  dataset" (`saveParquet`, `saveDta` and the conversion rules), ".dta to
  Parquet and back", "Fixed-width files with a SAS setup file" and "Into
  Arquero". The opening says when dta-parser alone is enough.
- `js/datakit/README.md`; `js/README.md`'s opening returns to `.dta` and
  points to datakit for Parquet.
- `docs/migration.md` as above; `docs/parquet.md` names
  `@jbearak/datakit` for TypeScript; `CONTEXT.md`'s datakit entry covers
  four languages.
- ADR 0035 records the decision and supersedes ADR 0034's TypeScript
  paragraph (ADR 0034 gains a "Superseded in part by" line).
- TSDoc on every export. The docs test runs every example in the
  TypeScript guide against the built packages.
- Gate 2 is not repeated: the Parquet sections passed it in plan 0019
  and change only their imports, and the new sections are tested
  examples of functions the other languages' guides already cover.

## Tests

- Every Parquet test moves to `js/datakit/test` with its import changed;
  none is dropped. dta-parser's tests lose only Parquet cases.
- Each module's exports against its wrappers' calls (above).
- `MISSING` identity and label lookups across dta-parser's root,
  `./format`, datakit, and two separately installed copies; a foreign
  value under the registry key is ignored; `dtaKey` from the root and
  `./format` is one function.
- `readFixedWidth` gives its module's memory back when no Parquet reader
  is open, and keeps it while one is.
- `readDataset` against per-column `readColumns`, `notes()`,
  `characteristics()`, `valueLabelNames()` and `info` for every `.dta`
  fixture and every Parquet fixture, metadata included (an unused label
  set survives).
- Round trips: `saveParquet(readParquet(f))` gives the same
  `ReadDataset` for every fixture in `compat/parquet/fixtures` the
  writer can write (the exceptions listed, as Python's round-trip test
  lists them); `saveDta(readDta(f))` the same for every `.dta` fixture;
  Parquet to `.dta` to Parquet keeps values, labels, letters and
  categoricals without letters (levels, order, unused levels).
- `saveDta`: each rule, including a Parquet `string` column (short and
  past 2,045 bytes), an untyped column holding 1.5, integers at each
  storage type's edges (101 is int, not byte), each timestamp unit at
  the edges (a fraction of a millisecond, ±2^53, before 1960,
  `truncate`), fractional dates and fractional timestamp counts in each
  unit, positive and negative, with and without `truncate`, an
  infinity and a non-letter NaN in each, a `BigIntColumn` past ±2^53,
  a decimal read as a number and one read as text, a categorical built
  with a letter (an error in `saveDta` and `saveParquet`), a stale
  marker on a non-categorical column, a name clash for the label set,
  and each error message; the comparison with Python's `save_dta`.
- `readDta`, and `openDta` with `readDataset`, of plan 0020's marked
  fixtures (R writes them): marked columns come back categorical, their
  set out of `valueLabels` (kept when another column uses it); each
  failing check gives labelled numbers and one warning, through
  `onWarning` and through the default; a restored variable has
  `valueLabels` `""` and `categorical.labelSet`; `saveDta(readDta(f))`
  gives the same set names back, including a marked column whose set is
  not named after it (`region` labelled by `regions`), a factor with
  codes 10 and 20 (same codes back), a factor sharing its set with a
  labelled numeric column, and two factors sharing one set (one set
  back, same name, in each case), a marked set with a fractional code
  and one with a label on `.r` that no row holds (each labelled numbers
  with the warning, then saved with every label kept and the marker
  dropped); `saveParquet` of a restored dataset writes no dangling set
  reference; the browser path `openDta`, `readDataset`,
  `writeParquet` writes a Parquet categorical.
- `saveDta` with an unused set already named after a categorical
  column: reused when it maps the same codes to the same texts; else
  it survives and the new one is `name_2`.
- `saveDta` of a null in a `string` column and in a `binary` column:
  each an error naming the variable and row.
- `readFixedWidth` against `compat/expected/fixed_width.json`
  (asciiSetupReader's reading, the oracle) for `recodes` `"setup"`,
  `"tagged"` and `"none"`; several setup files; `commentedFormats`;
  warnings of four kinds (skipped statement, unknown name, cut label,
  short records) through `onWarning` and through the default warning;
  the temporary directory gone after success and after an error; and
  the same `.dta` values as R's `read_fixed_width` for the synthetic
  file (both call one Rust function).
- `convertFixedWidth` with `node:fs` unavailable, so the root entry is
  shown to need no Node API.
- Memory: datakit's test module is capped at 64 MiB like dta-parser's,
  and `parquet-memory.test.mjs` moves with it.
- Packaging: the `npm pack` install test; bundle tests that
  dta-parser's `dist` has no Parquet code and that importing datakit's
  root compiles no `.dta` module.

## Speed and memory

No reading or writing code changes, so the plan 0018 targets carry over
unchanged. The PR measures, on one machine with the same packages on
both sides (A/B, `main` against the branch):

- the size of each module (raw and brotli) and each packed package, and
  of the two together, against 1.1.0's; reported, not gated;
- time to import each package, and both, against 1.1.0's;
- the existing Parquet and `.dta` benches in `bench/node`: within noise
  of `main`;
- `readFixedWidth` on the NSFG files `scripts/check-nsfg.R` uses: time
  and peak memory, the largest file included, with no target, since no
  other TypeScript library reads SAS setups.

## Delivery

One PR: this plan, ADR 0035 and the judging record, then the code, the
docs and the tests. Nothing is published. After it merges, a
table-viewer thread changes its Parquet import to datakit; this
repository's PR does not touch table-viewer.

## Risks

- **A project with dta-parser 1.x and datakit.** npm warns of, or
  refuses, the peer conflict; if forced, labels read through datakit are
  keyed by 2.0's `MISSING` and 1.x's keys miss them. The migration
  section says to upgrade together.
- **Bundlers.** Both packages embed their module in their JavaScript, so
  bundlers that handled 1.1 handle both; the `npm pack` test imports
  each entry from an installed copy.
