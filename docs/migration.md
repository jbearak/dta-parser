# Migration notes

- [dta_parser 0.2 to 0.3](#dta_parser-02-to-03) (Python): Parquet and
  fixed-width text move to datakit, in polars; `StataArray` becomes
  `DtaArray`, and `stata_key` becomes `dta_key`.
- [DtaParser 0.2 to 0.3](#dtaparser-02-to-03) (Julia): Parquet and
  fixed-width text move to Datakit.
- [Moving to @jbearak/dta-parser 1.0](#moving-to-jbearakdta-parser-10)
  (TypeScript).

## dta_parser 0.2 to 0.3

dta_parser 0.3 reads and writes `.dta` files with pandas, and nothing
else, and its pandas types are renamed after the format rather than
after Stata:

| dta_parser 0.2 | dta_parser 0.3 |
|---|---|
| `StataArray` | `DtaArray` |
| `StataDtype` | `DtaDtype` |
| the dtype strings `"stata[byte]"` ... `"stata[double]"`, and `"stata"` | `"dta[byte]"` ... `"dta[double]"`, and `"dta"` |
| `stata_key(value)`, `stata_keys(column)` | `dta_key(value)`, `dta_keys(column)` |

The old names are gone, with no aliases: replace them (for example
`sed -e 's/StataArray/DtaArray/g; s/StataDtype/DtaDtype/g; s/"stata\[/"dta[/g; s/stata_key/dta_key/g'`).
They behave as before. A pickle of a 0.2 frame holding a `StataArray`
does not load in 0.3; write it as `.dta` with 0.2 and read it back.

Its Parquet and fixed-width functions move to a new package,
datakit (distribution `dta-datakit`, import `datakit`), which works in
polars, not pandas (plan 0019, ADR 0034). Install both from the
checkout and import datakit:

    pip install ./python ./python/datakit

    import datakit as dk

A datakit read returns a tuple: a polars `DataFrame`, in which `.` and
`.a` to `.z` are all nulls, and a `Meta` holding what `df.attrs["dta"]`
held: the data label, notes, characteristics, sort order, each column's
label, format and value label set, the sets, and the letters.

| dta_parser 0.2 | datakit 0.3 | what changes |
|---|---|---|
| `df = dp.read_parquet(source, columns=, skip=, n_max=, nested=)` | `df, meta = dk.read_parquet(source, columns=, skip=, n_max=, nested=)` | a polars frame and a `Meta`; `df.attrs["dta"]` becomes `meta`; a `StataArray` (now `DtaArray`) column becomes a nullable polars column with its letters in `meta.missing` (or a companion column with `letters="columns"`); an integer column with nulls stays an integer column; dates are `Date` and `Datetime`; a categorical is an `Enum` |
| `dp.write_parquet(df, path, label=, variable_labels=, ...)` | `dk.save_parquet(df, path, meta=meta, ...)` | the name, as in R's and Julia's datakits; labels go in `meta` (`meta.label`, `meta.columns[name].label`), not in arguments; `compression`, `compression_level`, `row_group_size` and `missing_letters` are the same; there is no index to warn about |
| `dp.read_meta(parquet_file)` | `dk.read_parquet_info(parquet_file)` | a `ParquetInfo`: `rows` for `"nobs"`, `columns` as a polars frame with each column's polars dtype, `meta` for the labels, new `key_value`; `dp.read_meta` on a Parquet file is now a `ValueError` naming `read_parquet_info` |
| `df = dp.read_fixed_width(path, setup, ...)` | `df, meta = dk.read_fixed_width(path, setup, ...)` | a polars frame and a `Meta`; the warnings' full list is `FixedWidthWarning.messages`, not `df.attrs["warnings"]`; new `letters=` |
| `dp.FixedWidthWarning` | `dk.FixedWidthWarning` | |
| none | `dk.read_dta`, `dk.save_dta` | `.dta` files into polars and back, without pandas |

**Staying in pandas.** `meta` cannot follow a pandas frame, so the
pandas route for labelled data is `.dta`: `dk.save_dta(df, "x.dta",
meta=meta)` and then `dp.read_dta("x.dta")` gives the frame dta_parser
0.2's `read_parquet` gave, with `DtaArray` columns and `attrs["dta"]`
included. For plain values, `df.to_pandas()` (pyarrow needed) converts
the polars frame; `.a` to `.z` are then missing values in pandas, and
their letters stay in `meta`.

Everything else in dta_parser is unchanged: `read_dta`, `write_dta`,
`read_meta` for `.dta` files (from a path, bytes or a file object),
`DtaArray`, `DtaDtype`, `missing`, `MissingValue`, `missing_codes`,
`dta_key` and `dta_keys`, but for their names. `import dta_parser` no longer imports
pandas until one of these is used, so that datakit can use dta_parser's
compiled core without loading pandas; the `dta[...]` dtype is still
registered with pandas as soon as both are imported, in either order.

dta_parser's compiled module still holds the Parquet code: datakit
calls it through functions that are for datakit only, and checks
`dta_parser._native.ABI_VERSION` when it is imported. Install both from
one checkout.

## DtaParser 0.2 to 0.3

DtaParser 0.3 reads and writes `.dta` files only. Its Parquet and
fixed-width functions move to a new package, Datakit, which builds on
DtaParser and returns DataFrames (plan 0019, ADR 0034), as R's datakit
builds on dtaparser. Install both from the checkout, DtaParser first
([docs/julia.md, Install](julia.md#install)), and add `using Datakit`.

| DtaParser 0.2 | Datakit 0.3 | what changes |
|---|---|---|
| `read_parquet(source; ...)` | `read_parquet(source; ...)` | returns a `DataFrame` with the metadata, not a `DtaTable`; `DataFrame(read_parquet(f))` is no longer needed. A numeric column is a `DtaColumn` only when the rows read hold `.a` to `.z`; a column with only `.` is a `Vector{Union{Missing,T}}`. The arguments are the same |
| `write_parquet(path_or_io, table; ...)` | `save_parquet(path_or_io, table; ...)` | the name, as in R's datakit; the arguments and the file are the same |
| `read_meta(parquet_file)` | `read_parquet_info(parquet_file)` | `"columns"` is a `DataFrame` with a row per column, not a vector of `Dict`s; new `"key_value"` (the footer's key-value entries); no `"format"` key. `read_meta` on a Parquet file is now an `ArgumentError` naming `read_parquet_info` |
| `read_fixed_width(path, setup; ...)` | `read_fixed_width(path, setup; ...)` | returns a `DataFrame` with `read_parquet`'s metadata keys (no `"release"`, `"byte_order"` or `"encoding"`); the arguments are the same |
| TimeZones.jl and CategoricalArrays.jl as DtaParser's extensions | as Datakit's extensions | nothing to change: load them as before |

Everything else in DtaParser is unchanged: `read_dta`, `write_dta`,
`read_meta` for `.dta` files, `DtaTable`, `DtaColumn`, `stata_code`
and `set_stata_code!`, which Datakit re-exports, and `stata_key`, now
named `dta_key` (Datakit re-exports it too). Two fixes
come with 0.3: DataFrames' `sort!`, `permute!` and `invpermute!` of a
frame, and its `rightjoin` and `outerjoin` with a `DtaColumn` on the
left, keep `.a` to `.z` (they made them `.`, or failed, before).

DtaParser's native library still holds the Parquet code: Datakit calls
it through `DtaParser.Internals`, which is for Datakit only, and checks
the library's interface version when it loads. Its ABI version is now
5 (the Parquet footer's key-value entries were added), so rebuild with
`Pkg.build("DtaParser")` after updating.

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
  cells). The R, Python and Julia packages reject them too.
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
