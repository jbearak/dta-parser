# Moving to @jbearak/dta-parser 1.0

1.0 is a new API, not an update of 0.x. Everything is synchronous. The
format is read by a wasm build of the Rust core, embedded in the
CommonJS bundle, so there is no `.wasm` file to ship. This note maps
what manuscript-markdown, Sight and table-viewer use today onto 1.0. It
changes nothing in those repositories.

## Opening a file

| Today | 1.0 |
|---|---|
| `parse_metadata` / `parse_legacy_metadata` on a buffer, then `read_rows_from_buffer` | `openDta(bytes)` gives a `DtaReader` |
| `DtaFile.open(path)` (async) | `openDtaFile(path)` from `@jbearak/dta-parser/node` (sync) |
| constructing `DtaFile` from your own fd, reading `_fd` / `_metadata` | `openDtaFile(fd)`; the fd stays yours to close, and the file may be unlinked after opening |
| probing growing prefixes for legacy metadata | not needed: the reader asks for the byte ranges it needs |

Release 104 to 119 files open the same way; there is no separate legacy
path. Files over 4 GiB, with or without strLs, read through
`openDtaFile`.

## Metadata

| Today | 1.0 |
|---|---|
| `.nobs`, `.nvar`, `format_version`, `byte_order` | `r.info.nobs`, `r.variables.length`, `r.info.release`, `r.info.byteOrder` |
| `.variables[i]` name, type, format, label, `value_label_name` | `r.variables[i]`: `name`, `type` (`byte` ... `double`, `str12`, `strL`), `format`, `label`, `valueLabels` |
| `.value_label_tables`, `parse_value_labels` | `r.valueLabels(name)`: a `Map` from value (or missing value) to text, parsed once |
| `text_encoding`, `resolve_text_encoding` | `openDta(bytes, { encoding })` for files before 118; `r.info.encoding` says what was used |
| `section_offsets`, `obs_length` | not exposed; the reader seeks for you |
| notes, characteristics, sort order | `r.notes()`, `r.characteristics()`, `r.info.sortedBy` (new) |

## Rows and columns

| Today | 1.0 |
|---|---|
| `read_rows(start, count, colStart, colEnd)` | `r.readRows(start, count, columns)`, where `columns` lists indices or names, e.g. a range of indices |
| `read_columns(indices, { signal })` | `r.readColumns(indices, { start, count })`: typed arrays per variable, in one pass. To stay cancellable, read row ranges in a loop and check your signal between them |
| `_decode_rows_range` into your own buffer | `readColumns` with a row range |
| `build_gso_index`, `resolve_strl`, `read_strl_pointer`, `decode_gso_entry` | strLs come back resolved: text as strings, binary as `Uint8Array` |

A `NumberColumn` has `values` (`Float64Array`) and `missing`
(`Uint8Array`: 0, or 1 to 27 for `.` to `.z`). `missingValue(code)` turns
a code into the frozen `MISSING` object.

## Missing values and display

| Today | 1.0 |
|---|---|
| `is_missing_value_object`, `MissingValue`, `MissingType` | `isMissing(cell)`, `Missing`; `MISSING[".a"]` objects compare with `===` |
| `missing_type_to_label_key` | not needed: value label maps are keyed by the same `MISSING` objects |
| `apply_display_format(value, fmt)` | `formatValue(cell, format, labels?)` |

## Not in 1.0

- Arrow IPC (`ArrowBuffer` and friends). table-viewer needs another source
  for it.
- Caller-set limits on rows, labels or metadata size. Damaged or hostile
  files are errors: every length is checked against the file before any
  allocation, and a read holds at most 64 MiB of decoded data in the
  module at a time.

Writing is new: `writeDta(dataset)` gives the bytes of a release-118
file, and `writeDtaFile(path, dataset)` from `/node` streams one to disk.
