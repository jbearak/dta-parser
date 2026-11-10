# Migration notes

- [dta-parser 1.x to 2.0](#dta-parser-1x-to-20) (TypeScript): Parquet
  moves to `@jbearak/datakit`, which also reads fixed-width text and
  whole datasets.
- [Moving to @jbearak/dta-parser 1.0](#moving-to-jbearakdta-parser-10)
  (TypeScript).

The Python packages (`dta_parser` and Python's datakit) and the Julia
packages (DtaParser.jl and Datakit.jl) were removed on 2026-11-09. Their
last versions are in the repository's history before that date.

## dta-parser 1.x to 2.0

`@jbearak/dta-parser` 2.0 reads and writes `.dta` only; Parquet moved to
`@jbearak/datakit` (plan 0021), whose WebAssembly module carries the
Parquet code, so dta-parser's is an eighth the size it was (344 KB
against 2.8 MB). Install both from the checkout
([datakit: install](typescript.md#datakit-install)); dta-parser is
datakit's peer dependency.

| 1.x | 2.0 |
|---|---|
| `openParquet`, `openParquetAsync`, `ParquetReader`, `AsyncParquetReader`, `writeParquet`, `writeParquetTo`, `toDate` from `@jbearak/dta-parser` | the same names from `@jbearak/datakit` |
| `openParquetFile`, `writeParquetFile` from `@jbearak/dta-parser/node` | the same names from `@jbearak/datakit/node` |
| the types `ParquetInfo`, `ParquetOptions`, `ParquetVariable`, `ParquetWriteOptions`, `RowGroup`, `ColumnChunk`, `Statistic` | from `@jbearak/datakit` |
| `writeParquet`'s Parquet-only `WriteVariable` fields and types (`unit`, `timeZone`, `levels`, `ordered`, `categorical`; `bool` to `categorical`; bigint values) | datakit's `DatasetVariable`; dta-parser's `WriteVariable` is `.dta`'s |
| `TableReader`, `AsyncTableReader` | gain `valueLabelNames()`, `characteristics()` and `notes()`; `TableInfo` gains an optional `timestamp`, `Variable` optional `unit`, `timeZone` and `categorical`. A class of yours that implements `TableReader` adds the three methods |
| `DtaReader` | gains `valueLabelNames()` |
| `dtaKey`, `dtaKeys` | also from `@jbearak/dta-parser/format` (the same functions) |
| `NumberColumn.missing`, a code per row (0 a number, 1 `.`, 2 to 27 `.a` to `.z`), `values[i]` NaN where it was not 0 | gone: `values[i]` is the missing value itself, `NA` for `.` and a tagged NaN for `.a` to `.z`, in R's bits (ADR 0037). `missing[i]` becomes `missingCode(values[i])`; `naTag`, `isTaggedNa`, `taggedNa` and `NA` are new. A NaN without a tag (a Parquet file's NaN) is a number, as `missing[i]` 0 was |
| `WriteVariable.missing` (and datakit's `DatasetVariable.missing` for a Float64Array) beside a Float64Array | gone: put `NA` and `taggedNa(".a")` in the Float64Array; a plain array still takes `null` and `MISSING` values. `DatasetVariable.missing` stays for a BigInt64Array's nulls |
| `dtaKeys(column)` read `column.missing` | reads the values |
| a letter `.a` to `.z` in a categorical given to `writeParquet` became a null | kept: the column is written as DOUBLE level numbers and reads back, from `readColumns`, as a `NumberColumn` of the level numbers with the letters (plan 0022, ADR 0037); `readRows` gives the levels as text |

Nothing else changes: apart from categoricals holding `.a` to `.z`
(above), the Parquet functions read and write the same files the same
way.

`MISSING`'s objects are now one set per process, shared by every copy of
dta-parser 2.0 or later and by datakit, so a `ValueLabels` map one read
is found with another's keys. A copy of 1.x makes its own objects, so do
not mix 1.x and datakit in one project; npm reports the peer dependency
conflict.

New in datakit: `readParquet`, `readDta` and `readFixedWidth` read a
whole table into a `Dataset`, which `saveParquet` and `saveDta` write
([Read a whole file](typescript.md#read-a-whole-file)).

## Moving to @jbearak/dta-parser 1.0

1.0 is a new API, not an update of 0.x. Everything is synchronous. The
format is read by a wasm build of the Rust core, embedded in the
CommonJS bundle, so there is no `.wasm` file to ship. This note maps
what manuscript-markdown, Sight and table-viewer use today onto 1.0. It
changes nothing in those repositories.

### Opening a file

| Today | 1.0 |
|---|---|
| `parse_metadata` / `parse_legacy_metadata` on a buffer, then `read_rows_from_buffer` | `openDta(bytes)` gives a `DtaReader` |
| `DtaFile.open(path)` (async) | `openDtaFile(path)` from `@jbearak/dta-parser/node` (sync) |
| constructing `DtaFile` from your own fd, reading `_fd` / `_metadata` | `openDtaFile(fd)`; the fd stays yours to close, and the file may be unlinked after opening |
| probing growing prefixes for legacy metadata | not needed: the reader asks for the byte ranges it needs |

Release 104 to 119 files open the same way; there is no separate legacy
path. Files over 4 GiB, with or without strLs, read through
`openDtaFile`.

### Metadata

| Today | 1.0 |
|---|---|
| `.nobs`, `.nvar`, `format_version`, `byte_order` | `r.info.nobs`, `r.variables.length`, `r.info.release`, `r.info.byteOrder` |
| `.variables[i]` name, type, format, label, `value_label_name` | `r.variables[i]`: `name`, `type` (`byte` ... `double`, `str12`, `strL`), `format`, `label`, `valueLabels` |
| `.value_label_tables`, `parse_value_labels` | `r.valueLabels(name)`: a `Map` from value (or missing value) to text, parsed once |
| `text_encoding`, `resolve_text_encoding` | `openDta(bytes, { encoding })` for files before 118; `r.info.encoding` says what was used |
| `section_offsets`, `obs_length` | not exposed; the reader seeks for you |
| notes, characteristics, sort order | `r.notes()`, `r.characteristics()`, `r.info.sortedBy` (new) |

### Rows and columns

| Today | 1.0 |
|---|---|
| `read_rows(start, count, colStart, colEnd)` | `r.readRows(start, count, columns)`, where `columns` lists indices or names, e.g. a range of indices |
| `read_columns(indices, { signal })` | `r.readColumns(indices, { start, count })`: typed arrays per variable, in one pass. To stay cancellable, read row ranges in a loop and check your signal between them |
| `_decode_rows_range` into your own buffer | `readColumns` with a row range |
| `build_gso_index`, `resolve_strl`, `read_strl_pointer`, `decode_gso_entry` | strLs come back resolved: text as strings, binary as `Uint8Array` |

A `NumberColumn` has `values` (`Float64Array`) and `missing`
(`Uint8Array`: 0, or 1 to 27 for `.` to `.z`). `missingValue(code)` turns
a code into the frozen `MISSING` object.

### Missing values and display

| Today | 1.0 |
|---|---|
| `is_missing_value_object`, `MissingValue`, `MissingType` | `isMissing(cell)`, `Missing`; `MISSING[".a"]` objects compare with `===` |
| `missing_type_to_label_key` | not needed: value label maps are keyed by the same `MISSING` objects |
| `apply_display_format(value, fmt)` | `formatValue(cell, format, labels?)` |

### What users will see change

- Node 24 or later is required.
- Reading past the last row throws a `RangeError` with code
  `DTA_OUT_OF_RANGE`; 0.x returned the rows that exist. Every error now
  has a `code` (see "Errors" in docs/typescript.md).
- Files before release 118 decode as Windows-1252 unless you pass
  `{ encoding }`; 0.x always used UTF-8. This matches haven and pandas,
  but text written as UTF-8 into an old release now shows as mojibake
  until you pass `{ encoding: "utf-8" }`. An unknown encoding name is an
  error (`DTA_INVALID`).
- Binary strLs are `Uint8Array`s, not strings.
- Display formats follow R, not Stata: `%g` prints as R does (7
  significant digits, fixed unless scientific is narrower: `0.5`,
  `123456789012`), `%td` as `2024-03-01` and `%tc` as
  `2024-03-01 13:05:09`, whatever their mask. `%f`, `%e`, commas and the
  `%tw` to `%ty` masks format as before; `%td` floors fractional days,
  as haven does. `formatValue` never throws: a value its format cannot
  show (a date outside JavaScript's range) shows as the plain number.
- A value label set named twice keeps the last table (0.x kept the
  first), as pandas does.
- Some damaged files 0.x rejected now read: type-130 strLs that are empty
  or lack their final NUL, label text without a NUL or whose offset is
  the end of the text block (it reads as ""), and a map whose end-of-file
  offset is past the end. None of these can show one value's data as
  another's.
- Some damaged files 0.x read are now rejected: two strLs with the same
  variable and row (`DTA_CORRUPT`; they showed one's text in the other's
  cells). The R packages reject them too.
- A leading U+FEFF in a string or label is kept.

### Not in 1.0

- Arrow IPC (`ArrowBuffer` and friends); table-viewer has dropped it.
- Listing value label set names without reading them, limits on
  `valueLabels()`, and cancelling inside one read. Damaged or hostile
  files are errors, and running out of memory is `DTA_TOO_LARGE`, never
  a crash: every length is checked against the file before any
  allocation, and a read holds at most 64 MiB of decoded data in the
  module at a time. To stay cancellable, read row ranges in a loop. To
  show long strings without reading them, use `maxStringBytes`.

Writing is new: `writeDta(dataset)` gives the bytes of a release-118
file, and `writeDtaFile(path, dataset)` from `/node` streams one to disk.
