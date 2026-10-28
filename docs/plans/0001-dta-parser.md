# Plan: dta-parser

Status: under review (round 2).

## What we are building

One library that reads and writes Stata `.dta` files, and two thin
packages on top of it:

- `@jbearak/dta-parser` 1.0.0, an npm package, for three TypeScript tools
  (manuscript-markdown, Sight, table-viewer).
- dtatools, an R package for one downstream testthat suite (a private
  repository; nothing from it is copied here).

Out of scope: data manipulation in R (`gen`, `replace` and the like), a
general Stata-typed data frame, Arrow IPC (the user agreed it is scope
creep; table-viewer must get it elsewhere), `.dta` 102 and 103 (haven
cannot read them), and writing anything but release 118.

## Requirements, as found

**Reading** every version haven's current CRAN release (2.5.5, bundling
ReadStat 1.1.9 dev) reads. Its check accepts 104–119; the versions that
exist in that range are 104, 105, 108, 110, 111, 113, 114, 115, 117, 118
and 119. Each is tested, in both byte orders where a fixture can be had.

**Writing** release 118 only (user decision), like haven's default, but
faster and with less peak memory than haven's `write_dta`. A dataset 118
cannot hold (more than 32,767 variables, a value outside its declared
storage type) is an error, never a silent change.

**Metadata:** storage types, variable labels, value labels (including
labels on `.a`–`.z`), display formats, data label, timestamp, notes,
characteristics, sort order, and extended missing values, as far as each
version carries them.

**npm consumers** (from how they use 0.x today): all three run in Node
(extension host, LSP server, CLI, Electron main), bundled by esbuild to
CommonJS. They need

- a synchronous API (manuscript-markdown's embed pipeline and
  table-viewer's row decoding are synchronous);
- a file-backed reader that opens a path or takes a caller-owned fd,
  reads row windows and column subsets on demand, keeps working after
  the file is unlinked (Sight unlinks temp files after opening), and
  handles files over 4 GiB including strLs;
- whole-column reads of several columns in one pass (Sight's sort and
  filter), which they chunk by row range to stay responsive and
  cancellable;
- variable metadata, value labels with missing-code keys, strL text and
  binary, a typed missing value, the legacy text encoding with an
  override, and the format version;
- display formatting of a value by its `%fmt`, including `%t` dates.

None writes today; the user wants the npm package to write anyway (user
decision), through the same core writer.

**dtatools consumer:** a suite that reads a handful of columns out of
`.dta` 118 files of 5–12 GB, groups and compares codes with Stata
semantics, and writes small fixtures that Stata reads on another machine.
It calls `read_dta` (with `col_select` as a character vector or a
tidyselect expression), `save_dta`, `is_missing`, `is_tagged_missing`,
`.a`–`.z`, `val_label`, `val_labels`, `labelbook`, `dta_setequal`,
`dta_setdiff`, `dta_group_id`, `dta_group_tag` and `tab`. It relies on:

- `==`, `!=`, `<`, `<=`, `>`, `>=` never returning NA; missing values
  compare greater than every number, `.` < `.a` < … < `.z`; `x == NA`
  is TRUE exactly for `.`.
- `unique()`, `%in%`, `c()`, `[` and data-frame row subsetting keeping
  `.a`, `.b`, … distinct and keeping labels.
- set helpers receiving plain doubles built by `c(NA, .i)`, which drops
  the class but keeps the NaN payload.
- `rlang::eval_tidy` over the returned frame.

The suite itself has no dplyr call, but the user wants `mutate`,
`group_by` and `filter` supported on what `read_dta` returns (user
decision), keeping labels and keeping `.a`–`.z` distinct in groups.

**Acceptance:** the suite passes on this machine with dtatools from this
repository installed. Its tests that need Stata skip here; the user runs
them elsewhere. The suite's own assertions are its oracle; this project
treats nothing in that repository's data as an expected value. Separately,
`read_dta` matches haven on every fixture.

## Design

### One core in Rust, two bindings

```
crates/dta/        the format: read and write; no dependencies, no I/O of its own
crates/dta-ffi/    a small C ABI over crates/dta, built as wasm32 (npm) and staticlib (R)
js/                @jbearak/dta-parser: TypeScript over the wasm module
r/dtatools/        R package: C glue over the staticlib, plus R code
compat/            scripts that make fixtures and expected values with
                   haven, pandas, readstata13 and ReadStat
bench/             reproducible benchmarks
```

**Why not reuse ReadStat** (MIT, C, reads 104–119, writes): its API is a
push parser that walks every row in file order and calls back per value.
It has no random access to a row window, no way to skip unselected
columns' decoding cheaply, and no lazy strL access, which are what the
viewers and the 12 GB projection reads need. Its current CRAN build
misreads ≤108 value labels and 119 strLs. haven's write path converts the
whole data frame through it, which is the memory cost the user wants
beaten. Wrapping it would still leave the random-access layer, the
writer streaming and the wasm build to write, in C.

**Why Rust:** the readers parse untrusted files inside editors, and every
length and offset in a `.dta` file is attacker-controlled; Rust makes
bounds checks the default. One source compiles to wasm32 and to a C
static library. The core has no crate dependencies, so a reader can
follow all of it and the R build needs only `cargo`. Rust panics never
cross the FFI boundary: every FFI entry point wraps its body in
`catch_unwind` and returns a status (aborting would take down the R
session), and the C glue calls `Rf_error` only after Rust has returned.

**Why wasm, synchronously, without wasm-bindgen:** one implementation for
both languages, as the user asked. The module is embedded in the
CommonJS bundle as bytes and compiled with `new WebAssembly.Module(...)`
at load (synchronous in Node), so there is no `.wasm` file to locate and
no async init. The ABI is about a dozen functions over handles and byte
buffers; hand-written TypeScript glue is easier to read than generated
glue. Offsets cross the boundary as `f64` (exact to 2^53). Typed-array
views over wasm memory are re-created after every call that can grow it.
File bytes never all live in wasm memory: the core asks the host for byte
ranges.

### The core (`crates/dta`)

I/O goes through two traits, so the same code serves a file on disk (R),
a JS callback over `fs.readSync`/`fs.writeSync`, or a `Uint8Array`:

```rust
pub trait Source { fn len(&self) -> u64; fn read_at(&mut self, off: u64, buf: &mut [u8]) -> Result<()>; }
pub trait Sink   { fn write_all(&mut self, buf: &[u8]) -> Result<()>; }
```

`Reader::open(source, options)` reads the header and descriptors (and,
for 117+, the map), validating every count, width and offset against the
file length before allocating. It does not touch data, value labels,
strLs or characteristics until asked. Modules:

- `header`: binary layout (104–115) and tagged layout (117–119). A
  per-version `Layout` table holds field widths (name, format, label
  lengths; nvar and nobs widths; strL pointer split), so version
  differences live in data, not branches.
- `types`, `missing`: per-version type codes; decode/encode of `.` and
  `.a`–`.z` for each storage type, with the pre-113 single-sentinel
  rules.
- `data`: decodes a row range for a set of columns into caller-supplied
  columnar sinks: numbers as `f64` plus a `u8` missing code per cell
  (0 = not missing, 1 = `.`, 2–27 = `.a`–`.z`); strings as UTF-8 bytes
  plus offsets; strLs resolved through `strl`. Rows are read in chunks of
  about 8 MiB and only the selected columns are decoded, so reading 10
  columns of a 12 GB file streams it once in bounded memory.
- `strl`: on first use, one sequential scan of the GSO section records
  each entry's `(v, o) → (offset, length, kind)`, payloads not included;
  payloads are read only for the rows asked for. Text and binary are
  kept apart.
- `labels` (≤105 layout and 108+ layout), `chars` (characteristics;
  notes are the `_dta` `noteN` entries).
- `encoding`: 118+ is UTF-8. Older files decode as Windows-1252 by default
  (haven's choice; ADR), with Latin-1 and UTF-8 as options.
- `writer`: writes 118 from columns to a `Sink`. One pass sizes string
  widths and value-label tables; the map's offsets are then computable,
  so the file is written front to back in one pass, rows built into an
  8 MiB buffer at a time. Peak memory is that buffer plus the caller's
  columns: no row-major copy of the data, no per-cell objects.

Errors are one enum with a byte offset and a message. Nothing panics on
bad input: `cargo test` runs every fixture truncated at many points and
with deterministic bit flips, and requires an error or a clean read.

### npm package (`js/`, CommonJS, Node ≥ 20)

```ts
import { openDta, formatValue, MISSING } from "@jbearak/dta-parser";
import { openDtaFile, writeDtaFile } from "@jbearak/dta-parser/node";

const r = openDta(bytes, { encoding?: "windows-1252" | "latin1" | "utf-8" });
const r = openDtaFile(pathOrFd, options);  // fs.readSync; a passed fd stays the caller's

r.info        // { version, byteOrder, nobs, nvar, label, timestamp, encoding, sortedBy }
r.variables   // [{ name, type, format, label, valueLabelName }]
r.valueLabels(name)                       // Map<number | Missing, string>, parsed on first use
r.notes(); r.characteristics()
r.readColumns(columns, { start, count })  // NumberColumn { values: Float64Array, missing: Uint8Array }
                                          // StringColumn { values: string[] }
                                          // StrLColumn   { values: (string | Uint8Array)[] }
r.readRows(start, count, columns?)        // Cell[][], a wrapper over readColumns
r.close()

writeDtaFile(path, dataset)               // streams through the core writer
formatValue(cell, format, labels?)        // %w.d{f,g,e,fc,gc}, %s, %t{d,c,C,w,m,q,h,y} with masks
```

`count` per call is capped (default 1M rows) so a call's buffers stay
small; callers loop. `Missing` values are frozen singletons
(`MISSING[".a"]`), so `===` works. A short `docs/migration.md` maps each
consumer's 0.x calls to 1.0 (all now synchronous; Arrow no longer here)
without touching the consumers.

### dtatools (`r/dtatools/`, R ≥ 4.2, version 1.0.0)

**Representation.** Numeric columns are double vectors of class
`dta_num`. `.` is `NA_real_`; `.a`–`.z` are NA doubles carrying the
letter in the NaN payload (haven's `tagged_na` layout, so the two
interoperate). Attributes: `label`, `format`, `storage`
(`byte`/`int`/`long`/`float`/`double`), `labels` (named codes, haven's
convention) and `label_set` (the value-label set's name, so shared sets
round-trip). String columns are character vectors with `label` and
`format`. Data-frame attributes: `label` and `notes`. `read_dta` returns
a base `data.frame`, columns in `col_select` order. Every numeric storage
type is double in R, since integers cannot carry `.a`–`.z`. Dates stay
numbers. A binary strL is an error in `read_dta`.

**One key.** A single C function maps a vector to Stata order keys:
numbers unchanged, `.` … `.z` to 27 distinct finite doubles above the
largest value Stata stores. Everything else is base R on the keys:
comparisons (`Ops`; arithmetic returns plain doubles with missings as
`NA`), `mtfrm` (so `%in%`/`match` keep codes apart), `xtfrm` (sort,
order), `unique`, `duplicated`, and the set and group helpers.

**Where the class holds, and where it does not.** `[`, `c` (when a
`dta_num` comes first), `unique`, `rep`, `as.data.frame`, data-frame
row subsetting, and dplyr `filter`, `mutate`, `group_by` keep the class
and labels. `c(NA, .i)`, `ifelse()` and arithmetic return plain doubles:
the payload survives, and every dtatools function (`is_missing`,
`is_tagged_missing`, `dta_set*`, `dta_group_*`, `tab`, `val_label`)
reads codes from plain doubles too, but base `==`, `unique` and `%in%`
on such a plain vector see only `NA`. This is documented in the package.

**dplyr** (user decision): `vec_proxy`/`vec_restore` keep attributes;
`vec_ptype2`/`vec_cast` between `dta_num` and double; and
`vec_proxy_equal`/`vec_proxy_compare` return the keys, so `group_by`
keeps `.a` and `.b` apart and arranges in Stata order. Tested with
`filter`, `mutate`, `group_by` + `summarise`/`mutate`.

**Functions:** `read_dta(file, col_select = NULL, encoding = NULL)`;
`save_dta(data, file)`; `is_missing(x)`; `is_tagged_missing(x, tag)`;
`.a`–`.z`; `val_labels(x)` (a named `dta_num`); `val_label(x, values)`
(vectorised, unnamed character, `NA` where unlabelled); `labelbook(data)`
(`list(mappings = data.frame(variable, label_set, code, code_text,
text))`, Stata order); `dta_setequal(x, y)` and `dta_setdiff(x, y)`
(accept `dta_num`, plain double, logical `NA`, character);
`dta_group_id(..., missing = FALSE)` and `dta_group_tag(..., missing =
FALSE)` (vectors or one data frame; one `order()` over the keys, then
run boundaries, never pasting rows); `tab(x, missing = FALSE)` (named
integer counts in Stata order, named by the code as Stata writes it:
`1`, `.`, `.a`).

`save_dta` keeps a column's `storage`, and infers it otherwise: integer
→ long, double → double, logical → byte, character → strN or strL (above
2045 bytes). Values outside the storage type's range are an error.

**Build.** `configure` copies `crates/` into `src/rust/` when building
from a checkout and checks for `cargo`; `make r-package` produces a
self-contained source tarball, and CI installs that tarball outside the
checkout. For a machine without `cargo`, `R CMD INSTALL --build` here
makes a binary for the same OS and architecture.

### Testing

- **Fixtures, made without Stata,** from data the scripts generate
  (`compat/make-fixtures.*`): 113, 114, 115, 117, 118, 119 by haven
  `write_dta`; 114, 117, 118, 119 in both byte orders by pandas
  `to_stata`; 104, 105, 108, 110, 111 by a small C harness over
  ReadStat's writer (MIT, fetched at a pinned commit, not vendored; if
  it cannot write a version, that version falls to the next rule).
  Only where none of those can write a version and byte order (e.g.
  big-endian before 114) do we use files from pandas' test suite
  (BSD-3), listed with provenance in `compat/fixtures/README.md`.
- **Expected values** come from open-source readers: `compat/expected.R`
  (haven, readstata13) and `compat/expected.py` (pandas) dump values,
  missing codes and metadata to JSON committed beside each fixture. The
  Rust tests compare against them without R or Python. A table in
  `compat/README.md` says which reader is the oracle for each field per
  version (pandas and readstata13 are independent of each other and of
  ReadStat; haven and ReadStat are one lineage). Where readers disagree
  (known: haven 2.5.5 on ≤108 value labels and 119 strLs; Windows-1252
  vs Latin-1; trailing blanks; dates) an ADR records which we follow.
  Metadata no open-source reader exposes (e.g. sort order in pandas) is
  checked against whichever reader does expose it, or round-trip only.
- **Writer:** files written from R and from npm are read by haven,
  pandas and readstata13 and compared value for value, with metadata
  each reader exposes. A structural test compares our 118 output with
  haven's and pandas' 118 output for the same table: section order, map
  offsets, field widths and padding, ignoring the timestamp. The Stata
  round trip is the user's, on the Stata machine.
- **dtatools:** testthat tests of the semantics above, the dplyr verbs,
  and `read_dta` vs haven on every fixture; then the downstream suite as
  acceptance.
- **npm:** `node:test` over the same fixtures and expected JSON,
  formatting tables, and a bundled esbuild CommonJS smoke test.
- **CI** (GitHub Actions): cargo test + clippy, npm build/test, dtatools
  from the tarball, and the compat job with R and Python.

### Benchmarks

`bench/make-large.*` generates, with a fixed seed, a 1 GB file (10M rows,
mixed types) and a wide file over 4 GiB. `bench/run.*` measures full
reads, 5-column reads, writes and grouping (`dta_group_tag` on 10M rows),
with peak RSS from `/usr/bin/time -l`: dtatools vs haven vs readstata13,
npm vs pandas. Targets: reads within 1.5× of the fastest; writes faster
than haven and with lower peak RSS. Results and machine details go in
`bench/RESULTS.md`. The large files are generated, not committed.

## ADRs

1. Rust core with C ABI; wasm for npm, staticlib for R; not ReadStat.
2. Synchronous, columnar npm API.
3. The `dta_num` representation and the order key.
4. Stata comparison semantics in R; `tab` names.
5. Text encoding default for pre-118 files.
6. Writer: release 118 only, streaming.
7. Oracle per field where open-source readers disagree.
8. Fixture source per version.

## Pull requests

1. Scaffold: AGENTS.md, this plan, ADR 1, Cargo workspace, CI skeleton.
2. Vertical slice: core reader for 117–119 (numbers, strings, missing
   values, labels), the C ABI, a minimal R `read_dta` and a minimal wasm
   `openDtaFile` in an esbuild bundle; check selected-column time and
   peak RSS on the generated >4 GiB file. This proves the architecture
   before the rest is built.
3. Core: strLs, notes, characteristics, sort order; compat fixtures and
   expected JSON for 113–119.
4. Core reader for 104–111.
5. Core writer (118) and read-back; R `save_dta`; npm `writeDtaFile`.
6. dtatools: `dta_num` methods, missing-value functions, labels, sets,
   groups, `tab`, dplyr; downstream suite green.
7. npm: full API, `formatValue`, migration notes.
8. Benchmarks.

## Open question for the user

None remaining. Decided: write 118 only; dplyr supported; npm exposes
writing; Arrow out.
