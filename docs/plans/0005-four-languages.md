# Plan: R, TypeScript, Python and Julia, at parity, with proof

Status: draft, revised after review round 3.

## Goal

The user wants dta-parser to serve R, TypeScript, Python and Julia with
feature and performance parity, within reason; to benchmark every
implementation for speed and peak memory against the existing
open-source readers in its language, on synthetic files, each public-use
NSFG file and the India DHS files; and documentation that both Claude
Sonnet and GPT Terra judge better than that of the other open-source
Stata readers.

Today: one Rust core (`crates/dta`); R (`dtatools`, Rust bridge) and
TypeScript (`@jbearak/dta-parser`, wasm through `crates/dta-ffi`) on
top. No Python, no Julia. The top-level README is seven lines; R has no
generated man pages.

## Parity

| feature | R | TS | Python | Julia |
|---|---|---|---|---|
| read releases 104–119, both byte orders | ✓ | ✓ | new | new |
| select columns; a row range | cols ✓, rows **new** | ✓ | new | new |
| storage types, variable labels, display formats, data label, timestamp, notes, characteristics, sort order | ✓ | ✓ | new | new |
| value labels, including labels on `.a`–`.z` | ✓ | ✓ | new | new |
| `.`, `.a`–`.z` kept per value, through the operations listed below, and written back | ✓ `dta_num` | ✓ codes | new | new (not through DataFrames `vcat`) |
| binary strLs | — (an error) | ✓ `Uint8Array` | new (`bytes`) | new (`Vector{UInt8}`) |
| text encoding option before 118 | ✓ | ✓ | new | new |
| `%td`, `%tc`, `%tC` as dates (opt out) | — (numbers) | `formatValue` | new | new |
| write release 118 with all of the above | ✓ | ✓ | new | new |
| a key that sorts and compares as Stata does | ✓ | **new** | new | new |
| Stata comparisons, arithmetic, logic on columns; `tab`, group ids, sets, dibble | ✓ | — | — | — |

The core rows are the same in every language. The last row stays in R:
it exists for the downstream testthat suite. Every language gets the
Stata-ordering key, so its own sort, group and compare tools can follow
Stata. R keeps dates as numbers with their format (its users chose that
in ADR 0003); TypeScript formats them with `formatValue`.

**Round-trip guarantee**, within each language's capabilities in the
table (so R excludes binary strLs): reading a file and writing what was
read gives the same values, missing codes, storage types, labels, value
labels, formats, notes, characteristics and sort order; text in a
legacy encoding comes back as UTF-8 in release 118. Bytes may differ
(release, padding). Tested in every language, with values and codes
checked separately from metadata.

**Operations that keep missing codes** (tested; anything else may turn
`.a`–`.z` into `.`, and the docs say so):

- Python: boolean and positional selection, `loc`/`iloc`, `sort_values`
  (Stata order), `concat` and `merge` of frames whose columns are both
  `StataArray`, `reindex` (new rows `.`), `copy`, scalar get and set
  (a missing value comes back as a `dta_parser.missing` scalar such as
  `missing.a`, which assignment accepts), `groupby` on the column
  (`.`, `.a`, ... are separate groups, as in Stata; factorisation uses
  the Stata key). Metadata lives in `df.attrs["dta"]` keyed by column
  name: pandas carries `attrs` through most operations but drops them
  in some (`merge`, `concat` of frames with different `attrs`); a
  renamed column loses its entry. The writer uses what is there and
  defaults the rest; docs list this.
- Julia: bulk operations on a `DtaColumn`: slicing and indexing by
  ranges, vectors or masks, `view`, `copy`, `similar`, `sort`/`permute`,
  `subset`, `groupby`/`combine`, Tables.jl conversion, `vcat` of two
  `DtaColumn`s, and assigning a `DtaColumn` slice into another. A single
  element reads as `missing`, so element-wise copying (`b[i] = a[i]`)
  keeps `.` but not the letter; `stata_code(col, i)` and
  `set_stata_code!(col, i, code)` read and write it. DataFrames' `vcat`
  of tables builds a plain vector (`.` kept, letters dropped). Both
  documented.

## Representations

Prototyped before this revision (filter, sort, `iloc`, assignment,
concat, merge, reindex, group by; Julia: subset, sort, copy, assignment,
group by, Tables.jl):

- **Python.** `read_dta()` returns a pandas `DataFrame`. A numeric
  column without missing values keeps its storage width (`int8`,
  `int16`, `int32`, `float32`, `float64`); with only `.` it becomes
  `float32`/`float64` with `NaN` (exact for byte, int, float; long and
  double use `float64`); with any `.a`–`.z` it is a `StataArray`, a
  pandas ExtensionArray holding values and a `uint8` code per row, so
  codes follow their rows through the operations listed above
  (prototype: 70 lines). Strings are `object` columns of `str` (binary strLs:
  `bytes`). Metadata is `df.attrs["dta"]` (per-column labels, formats,
  storage, value labels; dataset label, notes, characteristics, sort
  order), which is column-keyed, not row-positional. Dates convert unless
  `dates=False`: `%td` to `datetime64[s]`, `%tc` to `datetime64[ms]`,
  `.` to `NaT`; a column converts only if every value is in range and
  round-trips exactly and none is `.a`–`.z`; otherwise it stays numbers
  with its format. `%tC` (which counts leap seconds) always stays
  numbers with its format, since a leap-second-free timestamp would be
  off by up to 27 seconds. Strings use pandas' default string dtype.
  Python 3.10 to 3.14 (CI tests the oldest and newest), the numpy and
  pandas releases that support each (pandas 2.2 and 3.x); free-threaded
  Python is not supported (abi3 wheels).
- **Julia.** `read_dta()` returns a `DtaTable` implementing Tables.jl
  and DataAPI's metadata, so `DataFrame(read_dta(p))` works and carries
  labels as column metadata. A numeric column with any missing value is
  a `DtaColumn{T} <: AbstractVector{Union{Missing,T}}` holding values
  and codes (`stata_code(col, i)`), keeping its storage type `T`;
  `copy`, `similar`, slicing and assignment keep codes (prototyped;
  DataFrames' default copy goes through `copy`, so codes survive).
  Concatenating tables with `vcat` gives a plain vector (`.` kept, the
  letters dropped), documented. Without missing values a column is a
  plain `Vector{T}`. Strings `Vector{String}`; binary strLs
  `Vector{UInt8}` elements. Dates convert to `Date`/`DateTime` unless
  `dates=false`, with the same rule as Python.
  Labels reach a DataFrame as column metadata through a DataFrames
  package extension (a weak dependency) that builds the frame and sets
  `colmetadata!`; a test checks `colmetadata(DataFrame(t), :x, "label")`.
  Julia ≥ 1.10; DataFrames ≥ 1.4 for the extension. Dependencies:
  Tables, DataAPI.

## Architecture

```
crates/dta        the format (unchanged)
crates/dta-ffi    wasm ABI (unchanged) + NEW native C ABI for Julia, dta.h
r/dtatools        R bridge (gains row ranges)
js/               TypeScript (gains the Stata key)
python/           NEW package dta_parser (PyO3 extension, ADR 0014)
julia/DtaParser/  NEW package DtaParser.jl
bench/            all four languages, NSFG builder, DHS
docs/             rewritten
```

The native C ABI (for Julia) lives in `dta-ffi` behind
`cfg(not(wasm32))`, sharing its JSON code; on native targets it builds
a cdylib. Its shape:

- `dta_open(path, encoding, err, err_len) -> handle`; `dta_close`.
  Every call takes an error buffer (UTF-8, truncated to `err_len`);
  no thread-local state, so Julia tasks may move between threads. A
  handle is not thread-safe; distinct handles are independent. Panics
  become errors. `dta_abi_version()` lets a package refuse a mismatched
  library.
- `dta_meta_json(handle, ...)`: metadata, value labels, characteristics
  as one JSON document.
- `dta_read(handle, cols, ncols, start, count, callback, user, err, ...)`:
  reads the rows once for all selected columns, chunk by chunk (the
  core's `read_chunks`), and calls `callback(user, first_row, columns)`
  per chunk with borrowed views: numbers in their storage type, a code
  array (NULL when the chunk has no missing values), string bytes with
  `uint64` offsets and a binary flag per value. The host copies them
  into arrays it allocated from the row count: one bounded copy per
  chunk. Memory beyond the result: the 8 MiB row chunk, its decoded
  columns, the strL index when strL columns are read (a map of each
  strL's position, built before the first chunk; text is read per
  chunk), and any single strL larger than the chunk. The benchmark
  measures peak RSS on string-heavy files. A nonzero callback return
  cancels.
- `dta_write(path, frame, meta_json, err, ...)`: one call; `frame` lists
  every column as pointers to host buffers (numbers in their storage
  type, optional codes, string bytes with `uint64` offsets), borrowed
  for the call. The core's streaming writer reads them in place (ADR
  0008). Hosts pass codes from `DtaColumn`, labels and metadata in JSON.

**Python binds the core through PyO3, not the C ABI** (ADR 0014). The
rule set before measuring: PyO3 if it builds strings more than 1.3×
faster than ctypes. The spike: 10M `str` in 0.16 s from a Rust loop
against 0.43–0.87 s through ctypes. The PyO3 extension calls the core
directly, fills numpy arrays Python allocated and builds strings in
Rust; writing borrows numpy buffers and encodes Python strings to UTF-8
one column at a time inside the call. The C ABI serves Julia.

**Writing a frame that did not come from `read_dta`** (Python and
Julia; R's and TypeScript's rules are unchanged):

| host type | Stata storage |
|---|---|
| bool | byte |
| integers | the smallest of byte (−127 to 100), int (−32,767 to 32,740), long (−2,147,483,647 to 2,147,483,620) that holds every value (the top of each range is reserved for missing values); else double, an error beyond ±2^53 |
| float32 / float64 | float / double; NaN is `.` |
| `StataArray`, `DtaColumn` | their storage and codes |
| nullable integer / `Union{Missing,Int}` | as integers, missing as `.` |
| pandas `category` | its codes as long, its categories as value labels |
| `datetime64` | `%td` (long) if every value is midnight, else `%tc` (double, milliseconds; finer non-zero parts are an error); `NaT` is `.` |
| `Date`, `DateTime` | `%td` (long), `%tc` (double) |
| `str` / `String`, `object` of str | strN up to 2045 bytes, else strL; `None`, `pd.NA` and Julia `missing` become `""` (Stata's empty string), as the docs say |
| `bytes`, `Vector{UInt8}` | binary strL |
| anything else | an error naming the column |

A column name Stata cannot hold (not 1–32 letters, digits or `_`, not
starting with a digit, or reserved) is an error naming it; there is no
silent renaming.

**Packaging.** Supported: macOS arm64, Linux x86_64 and aarch64
(manylinux2014), Windows x86_64. Python: maturin builds abi3 wheels
(one per platform for Python ≥ 3.10); CI builds them and installs each
in a fresh environment for a smoke test; nothing is published
(AGENTS.md).
Julia: a source build (`deps/build.jl` runs cargo) for this release; a
JLL artifact is deferred. CI runs Python and Julia on Ubuntu and macOS
and a build-and-smoke job on Windows (cdylib names, UTF-8 paths).

## Benchmarks

**Files** (never committed; scripts make or locate them):

- Synthetic: `long.dta`, `wide.dta`, `groups.dta`, plus `long.dta`
  rewritten by pandas as releases 114, 117 and 119 for the other read
  paths.
- NSFG: `bench/nsfg/make.py` first inventories CDC's public-use
  directory (every data file, its cycle, size, SHA-256) into
  `bench/nsfg/inventory.json`, then converts each: the fixed-width
  files through their dictionary (`.dct`: positions, types, names,
  variable labels) and label program (`label define` lines), the
  2022–2023 files from CDC's SAS data through pandas. The grammar comes
  from the CDC files themselves, written for this repository (no
  private code, no Stata documentation). Positions are cross-checked
  against CDC's SAS input programs where both exist; any file that
  fails conversion is listed with its error. Written as `.dta` by
  **pandas** (release 118), an independent implementation.
- India DHS: the user's copies (1992, 1998, 2006, 2016, 2021; women's
  and birth-history recodes; up to 5.2 GB), from `DTA_DHS_DIR`. The
  user asked for them. They are inputs only, never fixtures or oracles,
  never committed (their licence bars redistribution); RESULTS shows
  release, size, rows and variables only. ADR 0013 records this.

**Readers** (versions pinned in RESULTS):

| language | ours | others |
|---|---|---|
| R | dtatools | haven, readstata13 |
| Python | dta_parser | pandas `read_stata`, pyreadstat |
| Julia | DtaParser.jl | ReadStatTables.jl, StatFiles.jl |
| TypeScript | @jbearak/dta-parser | @irbisadm/statfmt (the only other npm package found that reads `.dta`) |

**Tasks:** (1) full read; (2) full read, then a pass over every value
computing a checksum (float64 sum of numbers, count of missing values,
total string length), which makes lazy strings and the like pay; (3) five named columns; (4)
a 1,000-row window; (5) metadata only; (6) write what was read (release
118 where a writer can choose; "no writer" where none exists). Options
are set so readers do comparable work (dates converted or not alike),
and recorded.

**Method:** the page cache is warm (each file is read once first, and
that run is discarded). Files over 100 MB: fresh process per run,
median of five (three over 1 GB), elapsed and peak RSS (macOS
`/usr/bin/time -l`; Linux `-v`, converted to MB). Smaller files: time
in-process after loading and one warm-up call, median of 20, with
process start and (Julia) first-call compile reported separately; their
peak RSS comes from one fresh-process run. Timeout 20 minutes; a reader
that errs or times out is reported as such, with the message.

**Correctness, outside timing:** for every file and task, each reader's
result is turned into a canonical per-cell form (numbers as float64,
missing codes where the reader exposes them, strings and binary values
as bytes, in row order) and hashed per column; ours must equal each
open-source reader's on what both expose (values exactly; codes where
both keep them), and the metadata (names, types, labels, formats, value
labels) is compared too. Selections, windows and writes are checked the
same way: a written file is re-read by an open-source reader and
compared with the source. Task-2 checksums agree to within 1e-9 times
the sum of absolute values for sums, and exactly for counts and
lengths. Any disagreement is reported, not hidden (for DHS files by
column position and kind, without values, names or labels).

**Targets, set now:** within each language, ours is fastest at task 2
on every NSFG and DHS file and at tasks 3–5 everywhere, within a 5%
tie band; peak RSS within 1.5× of the lowest (from the fresh-process
runs). Misses are reported with
their cause; work stops when a miss is explained by the host language
(as R's string cache is) or after one optimisation attempt per miss.

`bench/run.py` drives everything and writes `bench/RESULTS.md` with an
SVG chart per dataset family.

## Documentation

- `README.md`: what, why, a short example per language, the parity
  table, headline chart, links.
- `docs/guide/`: concepts for all languages: releases, storage types,
  `.` and `.a`–`.z`, value labels, encodings, strLs, dates, how each
  language represents them, memory and speed.
- `docs/r.md`, `docs/python.md`, `docs/julia.md`, `docs/typescript.md`:
  install, read, select, rows, metadata, missing values, labels, dates,
  writing, recipes, migration from haven / pandas / pyreadstat /
  ReadStatTables / statfmt, troubleshooting.
- API reference: R man pages (roxygen), Python and Julia docstrings,
  TSDoc.
- Objective checks in CI: every example runs (each writes the file it
  then reads; no sample `.dta` is committed), every exported function
  documented, links checked.

**Judging:** a rubric committed before any judging
(`docs/judging/rubric.md`: ten tasks a user does, from install to
writing labels, scored 0–3 for findability, correctness, completeness
and clarity). The rubric fixes, before any judging, which tasks are
common (every library supports them) and which only ours supports (such
as keeping `.a`). The pass is decided on the common tasks, each scoring
at least 2; the others are scored and published separately. Competitor docs pinned by
version or commit: haven, readstata13, pandas' Stata I/O, pyreadstat,
ReadStatTables.jl, statfmt. Sonnet and Terra each score blind,
order-randomised pairs (ours vs one competitor per language). Pass:
both judges score ours higher than every competitor in its language
on the common tasks, with no common task below 2. At most three rounds; transcripts and any
disagreement are published in `docs/judging/`. Plus one fresh agent per
language given only our docs completes the ten tasks.

## Delivery (one PR each, sol-loop on each)

1. This plan, ADR 0013 (DHS inputs) and ADR 0014 (PyO3, from the
   spike); R row ranges; the TypeScript Stata key.
2. Native C ABI in `dta-ffi` (for Julia), `dta.h`, Rust tests.
3. NSFG builder and inventory; synthetic release variants.
4. Python read (with `StataArray`, dates).
5. Python write; wheels in CI.
6. Julia read and write.
7. Benchmark harness and results.
8. Documentation, rubric, judging.

## Risks

- Competitor readers may fail on old releases or big files: reported.
- NSFG dictionaries vary by cycle: the inventory makes failures
  visible.
- pandas' and DataFrames' internals may change: the representation
  tests run in CI against the pinned minimums and the latest.
