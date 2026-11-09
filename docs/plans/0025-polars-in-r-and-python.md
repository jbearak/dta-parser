# Plan: polars in R and Python, with `is_missing()` and `is_na()`

Status: approved at Gate 1 (revision 4; Claude Sonnet and GPT Sol;
record in `docs/judging/polars-r-python/`). After the gate, on
2026-11-09, the user first dropped joins on columns holding `.a` to `.z`
as no use case, then restored their tests and docs, so that a change in
how polars joins them shows: the join recipes and join tests below
stand, in both languages (Python's in plan 0025's joins PR, R's in
stage 3).

## Problem

Plan 0024 kept R's datakit on tibbles (ADR 0038) and moved Python's
datakit to pandas, because polars and arrow hold `.a` to `.z` as NaNs
and treat a NaN as a value. Stage 4, the pandas datakit, was built and
then dropped on 2026-11-09 (PR #90 closed): on a DHS file of 4,962
columns, polars read it in 20 ms and the pandas datakit in 155 ms, and
pandas operations on wide frames stayed slow (a sort took 103 ms
against polars' 6 ms). The user: "If pandas is so slow on python then
we really should use polars with python."

The user then decided that polars is right for both languages "so long
as we understand the rules", with a function that says what R's
`is.na()` says. The rules, for the rows `1, 5000, .a, .b, .` in polars
2.1 (`.` a null, the letters tagged NaNs; `docs/research/polars-2.md`):

| expression | result | rows a filter keeps |
|---|---|---|
| `x != 1` | F T **T T** null | 3 |
| `(x != 1) & x.is_not_null()`, R's `x != 1 & !is.na(x)` written naively | F T **T T** F | 3 |
| `(x != 1) & x.is_not_nan()` | F T F F null | 1 |
| `x.fill_nan(None) != 1` | F T null null null | 1 |
| `x.is_null()` | `.` only | |
| `x.is_nan()` | `.a` and `.b` only | |
| `x.is_null() \| x.is_nan()`, R's `is.na(x)` | `.`, `.a` and `.b` | |

polars also makes every NaN equal to every other, so `group_by`,
`unique`, joins and `is_in` merge `.a` with `.b`; it orders NaN above
every number, so `x > 3000` is true on a letter; and its joins do not
match null keys unless asked (`nulls_equal`).

The user decided, on 2026-11-09:

1. **Python's datakit stays on polars** (ADR 0036 stands).
2. **R's datakit gains polars**, reversing ADR 0038's decision that it
   has none: `read_parquet_pl()`, `read_dta_pl()` and
   `read_fixed_width_pl()` return `list(df, meta)`; `save_parquet()` and
   `save_dta()` also take a polars frame with `meta`. The tibble
   functions stay as they are.
3. **R's polars frames come from the native code**, as Python's do: the
   Arrow C stream code is shared, so R and Python get the same columns,
   R strings are never built, and the letter rules are one set.
4. **`is_missing()`, with the alias `is_na()`**, in both languages: true
   for `.` and `.a` to `.z`, as R's `is.na()`. (An alias `is_mi` was
   considered and dropped.)

Nothing here changes dta_parser's `DtaArray` or `read_dta` (plan 0024,
stage 3, merged), or R's tibble functions and `datakit_by()`.

## Proposal

Four stages, each its own pull request; stage 2 is two.

### Stage 1: records, and the helpers for Python

**Records.**

- **ADR 0041, polars in R and Python.** Records decisions 1 to 4, the
  table above, and the benchmark that dropped plan 0024's stage 4. It
  supersedes ADR 0038's decision that R's datakit has no polars
  (`datakit_by()` and its reasons stand).
- **Plan 0024** gets a status line: stage 4 was built and dropped, and
  why. Its line naming "ADR 0040" for the pandas ADR that was never
  written is rewritten to say so.
- **ADR numbers.** Two ADRs are numbered 0039: `0039-datparser.md` (#89)
  and `0039-dtaarray-compares-as-missing.md` (#88). The second becomes
  `0040-dtaarray-compares-as-missing.md`; its own title line and text
  follow, and so do the references to it, found with `git grep 0039`:
  `docs/migration.md` (section "dta_parser 0.3 to 0.4") and plan 0024's
  stage 3 text. There is no ADR index to update. Every other
  `0039` in the repository (CONTEXT.md, CONTRIBUTING.md, ADRs 0018 and
  0032, `init.c`, datparser's tests and the crate comments) means the
  datparser ADR and stays.
- **"datakit moves to pandas"**: the sentences that say so (ADR 0038's
  closing paragraph and title line in its commit-facing summary, the
  DtaArray ADR's opening paragraph, `docs/research/polars-2.md` section
  7's introduction) gain "(dropped; ADR 0041)".

**`dk.is_missing(x)` and its alias `dk.is_na(x)`** (one function, two
names).

- A `Series`: by its dtype. A float Series gives `is_null() | is_nan()`;
  every other dtype gives `is_null()`. The result is a Boolean Series
  with no nulls.
- A column name or an `Expr`: an `Expr`, which has no dtype until it
  runs. It is `e.is_null() | e.to_physical().cast(pl.Float64,
  strict=False).is_nan().fill_null(False)`, as `_tagged._na_tag` builds
  its bits. It is right for numeric (Float32 included), Boolean,
  Decimal, Date, Datetime, Duration, Time, Categorical, Enum and Null
  columns: `to_physical()` turns a categorical into its codes, and a
  cast of any of these never makes a NaN, so only a float's own NaNs
  count. Two kinds are not for the `Expr` form, and the docstring and
  the guide say so:
  - text: the cast reads the text "nan" as a NaN, so a row holding
    "nan" would count; use `pl.col(c).is_null()`, or pass the Series;
  - Binary, List, Array and Struct: polars cannot cast them and raises
    its own error when the expression runs; use `is_null()`, or pass
    the Series.
- A NaN that is not a letter counts, as R's `is.na(NaN)` does.

**`dk.by(*columns, suffix="_letter")`**, the counterpart of R's
`datakit_by()`. Each argument is a column name, or an `Expr` with an
output name (`pl.col("x")`, `(pl.col("x") * 2).alias("y")`); one without
a name is an error. It returns a list of expressions: each column, then
`dk.na_tag(col).alias(name + suffix)` for every argument. An expression
has no dtype, so the letter column is there for every argument; for a
column that is not Float64 it is all null, which costs one column of
nulls and changes no grouping. Its arguments may be of the dtypes the
`Expr` form of `is_missing` takes, text included (its letter column is
null); a Binary, List, Array or Struct key raises polars' error, as
`na_tag` does, so such a key is grouped on by itself, without `dk.by`.
Two outputs with one name are an error.

- `df.group_by(dk.by("x"))` and `df.with_columns(dk.by("x")).unique(
  subset=["x", "x_letter"])` keep `.`, `.a` and `.b` apart. They need no
  flag: polars groups nulls together.
- **Joins need `nulls_equal=True`.** The letter column is null for every
  number and for `.`, and polars does not match null keys by default:
  a left join of `1, .a, .b, .` with itself on `["x", "x_letter"]`
  matched only the letters. The guide's recipe prepares both frames and
  joins with `nulls_equal=True`, which also matches `.` with `.`:

  ```python
  left = left.with_columns(dk.by("x"))
  right = right.with_columns(dk.by("x"))
  out = left.join(right, on=["x", "x_letter"], how="left", nulls_equal=True)
  ```

**`docs/python.md`**, where the guide introduces the letters: the table
above; `dk.is_missing` / `dk.is_na` as the translation of R's `is.na()`
and Stata's `missing()`; the ordering rule (`x > 3000` is true on a
letter: write `(x > 3000) & ~dk.is_na(x)`); the grouping and join rule
with `dk.by` and `nulls_equal=True`.

**Tests** (`python/datakit/tests/test_tagged.py`): each row of the table;
`is_missing` on a Series of Float64, Float32, Int64 with nulls, Boolean,
Decimal, Date, Datetime, Duration, Time, Categorical, Enum, Null,
String and Binary, and as an `Expr` on each of those but String and
Binary; the String `Expr` case shown by a test with "nan", and the
Binary `Expr` raising; `is_na` is `is_missing`; `by` in `group_by`,
`unique` and a left join with `nulls_equal=True` on numbers, `.a`,
`.b`, `.` and a plain NaN, each kept apart; `by` on Int64, String,
Categorical and Enum keys (letter column null) and a Binary key
raising; the suffix; an unnamed `Expr`; the name clash.

### Stage 2: one Arrow C stream crate for Python and R

`python/src/arrow/` (about 3,500 lines) holds the Arrow C data interface
by hand (ADR 0033's reasons for no arrow-rs) and the code that builds a
table from a Parquet or `.dta` read and writes one from an imported
stream. pyo3 runs through it: `Block::zeroed` and `Plan::block` return
`PyResult`; `import_stream` calls `__arrow_c_stream__`; `read.rs`,
`dta.rs` and `write.rs` build dicts and tuples and release the GIL
(`py.detach`); `letter_codes` and `label_sets` take Python objects; and
`read.rs` depends on `python/src/parquet.rs` (`with_reader_for` over a
Python source, `Access`, `select`, `kind_of`, `entries`, `read_error`).
So the move is two pull requests.

**Stage 2a: pyo3-free inside `python/`.** In place, with every Python
suite unchanged:

- A module error type replaces `PyResult` below the boundary, with a
  variant for each kind raised today: bad input (`ValueError`), an
  unknown column name (`KeyError`, as `parquet.rs::select` and
  `arrow/dta.rs` raise), a column position out of range (`IndexError`),
  a wrong type (`TypeError`), out of memory (`MemoryError`) and I/O
  (`OSError`). The binding maps each to the exception and message raised
  today; `prefix()` adds the path to a `ValueError` only, as now.
- Sources: the core takes a path, a byte buffer, or a `dta::Source`
  trait object. Python's file objects (`PyFile`) stay in the binding,
  which wraps one as a `Source`.
- `import_stream` takes a `*mut ArrowArrayStream`; the binding gets it
  from `__arrow_c_stream__`'s capsule, as now.
- What a read returns beside its table, now built as Python objects
  (`meta_dict`'s rows, names, columns with label, format, value label
  set, `ordered`, storage, flag and eligibility; value labels; label;
  notes; characteristics; sort; timestamp; warnings; and the letters
  table), becomes a Rust struct, `ReadMeta`, with the letters as a
  second `Table`. The binding turns it into the same dict and tuple.
- What a write takes beside its stream (the `meta` dict, which carries
  the profile and `missing`) becomes a Rust struct, `WriteMeta`.
- `Access`, `select`, `kind_of`, `entries` and `read_error` move from
  `python/src/parquet.rs` with the code that uses them.
- String conversion through Python's C API (the `PyUnicode*` calls in
  `python/src/lib.rs`) stays in the binding; the error variants cover
  what the moved code raises, not every exception `lib.rs` can raise.
- `digest.rs` (`arrow_digest`) and `ABI_VERSION` stay in `python/`:
  the digest is Python's, and the ABI number is the binding's.

**Stage 2b: the move.** The pyo3-free modules become a crate,
`crates/arrow` (package `dta-arrow`), depending on `dta` and
`dta-parquet` only, and no crate from crates.io, so R's offline
vendored build is unaffected. `python/` depends on it. For R it is
committed as `r/dtaparser/src/rust/arrow`, as `dta` and `parquet` are:
`r/dtaparser/configure` copies it, `scripts/build-r-package.sh` builds
it, `r/dtaparser/src/rust/Cargo.toml` and `Cargo.lock` name it, and the
`ci.yml` step "Committed Rust core matches" adds its path.

**Proof that nothing changes.** There are no native unit tests to move
(`python/src` has no `#[cfg(test)]`), so the stages add:

- in 2a, a Python test (`python/datakit/tests/test_errors.py`) written
  against today's code first: each bad input the suites know (missing
  file, not Parquet, an unknown column name, a column position out of
  range, bad `skip`, a type the writer refuses, a value out of range)
  raises the same exception type and message before and after: Parquet
  from a path, bytes and a file object, and `.dta` from a path (the only
  source Python's `read_dta` takes);
- in 2b, the crate's own tests: a table exported and imported again
  gives the same buffers; a stream imported and released frees once
  (counted in a test owner); a read of a fixture gives the `ReadMeta`
  the Python dict holds;
- a benchmark on one DHS file, read and write, before 2a and after 2b,
  within run-to-run noise;
- every Python suite, unchanged, on pandas 3 and 2.2 runs.

### Stage 3: R's polars functions

**Native.** dtaparser gains C callables, registered as the others are
(`R_RegisterCCallable`, ADR 0016). They are new, but datakit needs them
at load, so the dtaparser ABI number goes from 3 to 4: a datakit built
for them refuses an older dtaparser by name instead of failing in
`R_GetCCallable`. The number lives in `r/dtaparser/src/init.c`,
`r/datakit/R/zzz.R` and `r/dtatools/R/zzz.R` (`DTAPARSER_ABI`), and in
`r/datakit/src/init.c`'s `link()`, which fetches the callables only when
it finds that number (`found != 3` today); each package's `test-seam.R`
tests the refusal. All of them change with the bump, and `link()`
fetches the old callables and the new ones under 4. A fresh R session
then reads and saves a tibble Parquet file with datakit, with polars
and nanoarrow not installed, as a smoke test of the link.

- `dtaparser_parquet_read_arrow(source, cols, skip, n_max, options,
  data, letters)` and `dtaparser_dta_read_arrow(file, cols, skip, n_max,
  encoding, timestamps, data, letters)`. `data` and `letters` are
  external pointers R made with `nanoarrow::nanoarrow_allocate_array_stream()`;
  on success each receives a stream (the read's table, and the letters
  table: one LETTERS-coded dictionary column per column holding a
  letter in the rows read, as Python's read returns). The return value
  is an R list with `ReadMeta`'s fields under the names Python's dict
  uses.
- `dtaparser_parquet_write_arrow(stream, file, write_meta, options)` and
  `dtaparser_dta_write_arrow(stream, file, write_meta, options)`, where
  `stream` is the external pointer `nanoarrow::as_nanoarrow_array_stream()`
  gave for the prepared frame, and `write_meta` an R list with
  `WriteMeta`'s fields.
- `dtaparser_fixed_width_dta(data, setup, out, recodes,
  commented_formats)`: the core's `fixed_width_to_dta`, writing a
  release 118 file, as Python's `native.fixed_width` does. ADR 0039
  removed dtaparser's fixed-width callable when datparser took the
  tibble path; this one serves only `read_fixed_width_pl()`.

**Ownership and errors.**

- *Reads.* Rust reads into a `Table` it owns, held in an external pointer
  with a finalizer, so an R error before the end frees it. The metadata
  list is built under `R_UnwindProtect`, as `init.c` does for the other
  callables; Rust panics are caught (`catch_unwind`) and become R
  errors, so neither crosses a Rust frame. Last, Rust exports each
  stream into the struct behind `data` and `letters` (a move: the
  struct takes the release callback). On any failure before that, the
  structs keep a null `release`, and nanoarrow's finalizer does nothing.
- *Writes.* nanoarrow owns the stream struct. Rust takes it (copies the
  struct and sets the source's `release` to null, so nanoarrow's
  finalizer will not release it again), reads every batch, and calls
  `release` once whether the write succeeds or fails. A stream already
  taken is an error ("this stream was consumed").
- *Lifetime.* polars keeps our buffers after the import, so their release
  callbacks live in `dtaparser.so`; the docs say not to unload
  dtaparser while frames read from it exist (datakit imports it, so a
  session does not unload it by itself).

**Reading: the polars frame.** R's `read_parquet_pl()` and
`read_dta_pl()` import the two streams with `polars::as_polars_df()` and
finish the frame as Python's `_frame.finish` does, in R polars
expressions, so both languages follow one rule:

- the casts of `frame_of`: a `categorical` flag casts to `Categorical`;
  `decimal(p, s)` text casts to `Decimal(p, s)` for p up to 38 (R polars
  2.1 has `pl$Decimal`, checked), else stays text with the warning
  Python gives;
- `restore_categoricals` (`.dta` markers), `to_factors` for
  `factors = TRUE`, and `with_letters`: a column holding letters becomes
  `Float64` with tagged NaNs (`$reinterpret()` and the arithmetic of
  `_tagged.tag`); an `Int8`, `Int16`, `Int32` or `Float32` column is cast
  and its dtype kept in `meta$storage`; a date or timestamp holding
  letters becomes Stata's days or milliseconds since 1960 with `%td` or
  `%tc`; a categorical holding letters becomes its level numbers;
  `letters = FALSE` leaves the letters null.

The arguments follow Python's datakit, not R's `read_parquet()`: polars
holds `Int64`, `UInt64` and `Decimal` exactly, so `int64` and `decimal`
do not apply; `factors = TRUE` warns when it nulls letters, as Python's
does (there is no `warn_extended_missing`).

**Writing: preparing the frame.** `save_parquet()` and `save_dta()` on a
polars frame prepare it as Python's `_frame.prepare` does, in R polars,
before exporting the stream:

- each `Float64` column holding tagged NaNs is untagged (letters to
  null) and its letters go into `write_meta$missing`, so the native
  writers never see a tagged NaN (the `.dta` writer would write a
  bare NaN as `.`);
- a column whose dtype `meta$storage` names is cast back when every value
  fits it exactly, and written as double otherwise (Python's `stored()`);
- `Enum` and `Categorical` columns give the profile's levels;
  `meta$sort` is checked against the rows as `checked_sort` does.

**Functions** (datakit; polars and nanoarrow in `Suggests`, each polars
function calling `rlang::check_installed()`):

| function | does |
|---|---|
| `read_parquet_pl(file, col_select = NULL, skip = 0, n_max = Inf, factors = FALSE, letters = TRUE, timestamps = "error", nested = "error")` | `list(df, meta)`: a polars DataFrame and a `datakit_meta` |
| `read_dta_pl(file, col_select = NULL, skip = 0, n_max = Inf, factors = FALSE, letters = TRUE, encoding = NULL, timestamps = "error")` | the same, from `.dta` |
| `read_fixed_width_pl(file, setup, recodes = "setup", col_select = NULL, skip = 0, n_max = Inf, commented_formats = TRUE, factors = FALSE, letters = TRUE)` | `dtaparser_fixed_width_dta()` into a temporary file, then `read_dta_pl()` with the selection, window, `factors` and `letters`; the setup's warnings as one `datakit_fixed_width_warning`, as now. No R vector is built |
| `save_parquet(data, file, ...)`, `save_dta(data, file, ...)` | S3 generics; see below |
| `is_missing(x)`, `is_na(x)` | one S3 generic, two names; see below |
| `tagged_na_pl(letter)`, `na_tag_pl(x)`, `is_tagged_na_pl(x, letter = NULL)` | polars expressions: a tagged NaN literal (R's `pl$lit(tagged_na("a"))` makes a null, since R polars reads an R `NA` as null), each row's letter, a test for letters; the counterparts of Python's `tagged_na`, `na_tag` and `is_tagged_na`, needed to set or test a letter |
| `datakit_by_pl(..., .suffix = "_letter")` | the counterpart of `dk.by`: column names or named expressions in, a list of expressions out, a letter column for every argument; joins need `nulls_equal = TRUE` (R polars 2.1's `$join()` has the argument, checked) |

**Fixed width through release 118.** `fixed_width_to_dta` writes long
variable labels: a label of up to 320 UTF-8 bytes is kept whole (200
ASCII characters, say), and a longer one is cut at a character boundary
with a warning (`crates/dta/tests/fixed_width.rs`, `long_labels`: 200
"é" become 160); value label texts may be 32,000 bytes. Python's
`read_fixed_width` gives the same. datparser's tibble
`read_fixed_width()` cuts nothing (ADR 0039). The help page says so;
tests read a 200-character ASCII label whole and a 200-"é" label cut to
160, with the warning.

**The save generics.** datakit's `save_parquet` and `save_dta` become
`function(data, file, ...)` generics:

- the default methods keep today's formals and order exactly:
  `save_parquet.default(data, file, compression = "snappy",
  compression_level = NULL, row_group_size = NULL, missing_letters =
  TRUE)`, and `save_dta.default` calls `dtaparser::save_dta(data, file,
  ...)` with its arguments unchanged. So `save_parquet(df, f, "gzip")`
  and `save_dta(data = df, file = f)` mean what they mean today, and
  tibble saves need neither polars nor nanoarrow;
- a polars `LazyFrame` (`polars_lazy_frame`) gets an error saying to
  `$collect()` it first, rather than the default method's unrelated one;
- the `polars_data_frame` methods take the same arguments and then, by
  name, `meta = NULL`, `missing_letters = TRUE` (for `save_dta`; the
  `save_parquet` method has it already) and `timestamps = "error"`, as
  Python's `save_dta` and `save_parquet` do: `missing_letters = FALSE`
  writes every letter as `.`, through `_frame.prepare`'s rule;
- `NAMESPACE` gains `S3method(save_parquet, default)`,
  `S3method(save_parquet, polars_data_frame)` and the same for
  `save_dta`; datakit's `save_dta` is no longer dtaparser's object, so
  `tests/testthat/test-reexports.R`'s identity check for it becomes a
  check that the default method gives the same file; dtatools'
  `save_dta`, a re-export of dtaparser's, is unchanged (only its ABI
  constant follows the bump).

**`is_missing()` / `is_na()`** (one generic, two exported names):

- an R vector: `is.na(x)` (the default method);
- a polars expression (`polars_expr`): the expression of stage 1,
  `x$is_null() | x$to_physical()$cast(pl$Float64, strict = FALSE)$is_nan()$fill_null(FALSE)`,
  with the same dtypes and the same caveats for text and for Binary,
  List, Array and Struct;
- a polars Series (`polars_series`): by its dtype, as in Python.

R function calls build the expression once; polars evaluates it in
Rust. rlang, which dplyr and others import but scripts rarely attach,
also exports `is_na()` (a test for one `NA`) and `is_missing()` (a test
for a missing argument): the help page says that a script attaching
rlang after datakit gets rlang's.

**`datakit_meta`** is a list of class `datakit_meta` with Python's
`Meta` fields under the same names: `label`, `notes`,
`characteristics` (a named list of named character vectors), `sort`,
`timestamp`, `columns` (a named list of `label`, `format`,
`value_labels`, `ordered`), `value_labels` (a named list of named
double vectors, dtaparser's form: names are the texts, values the codes,
`.a` to `.z` as tagged NAs), `rows`, and `storage` (a named character
vector of polars dtype names, Python's private `_storage`). `print()`
shows it as Python's `repr` does, without `storage`.

**R versions.** R polars needs R 4.3; datakit keeps `R (>= 4.2)`, and
the polars functions say so on older R. `DESCRIPTION` gains
`Additional_repositories: https://community.r-multiverse.org`.

**Tests** (skipped without polars and nanoarrow): each function; the
letter rules on Int8/Int16/Int32/Float32, dates, timestamps and
categoricals; `letters = FALSE`; `factors = TRUE`; windows with and
without letters; a round trip through `save_parquet` and `save_dta` with
storage restored and widened; existing positional and named calls of
`save_parquet` and `save_dta` on tibbles unchanged; `is_missing` and
`is_na` on vectors, expressions and Series; the helpers and
`datakit_by_pl` with a join; a stream consumed twice; a failing read and
write (no leak, no double release); arrays that outlive their stream
across repeated `gc()`; the ABI check; `read_fixed_width_pl` with
recodes, warnings, a long label and labelled missing values; a LazyFrame
given to `save_parquet` and `save_dta`.

### Stage 4: one frame in both languages

- **Cross-language check** (`compat/parquet/`, beside
  `cross_language.{R,py}`): R's `read_parquet_pl()` / `read_dta_pl()` and
  Python's `dk.read_parquet()` / `dk.read_dta()` read the same files,
  each side writes what it read as Arrow IPC, and a Python checker
  compares them canonically: column order; dtypes, with temporal units
  and zones and `Enum` levels; validity; every valid cell, a Float64 by its bits
  (`reinterpret(UInt64)`) and a Float32 by its own (`reinterpret(UInt32)`,
  as `letters = FALSE` keeps Float32), so each letter's payload is
  checked; then the metadata, written as JSON by each side, field by
  field, `storage` compared by dtype name. Value labels are written as
  records, `{"set", "code", "text"}`, where `code` is a number or one of
  `"."`, `".a"` ... `".z"`, so R's tagged NAs and Python's keys meet in
  one form; the files include a set with two codes sharing a text and
  labels on `.`, `.a` and `.z`. Buffers under nulls, chunk
  boundaries and dictionary layout are not compared. The files cover
  Parquet and `.dta`, windows with and without letters, and `factors` and
  `letters` both ways; each language also reads what the other's
  `save_parquet` and `save_dta` wrote. Both sides use the same polars
  version (R polars 2.1.0 and Python polars 2.1.0 track one commit).
- **CI**: the `r`, `parquet-r` and `r-packages` jobs (macOS, Windows
  and Ubuntu 24.04, R release and oldrel) install nanoarrow from CRAN
  and polars from R-multiverse. R-multiverse has binaries for macOS and
  Windows; its Linux binaries are for Ubuntu "resolute" on R 4.6 and
  4.7, so on Ubuntu 24.04 polars installs from source with
  `NOT_CRAN=true`, which downloads its prebuilt Rust library (R polars'
  install vignette; checked on macOS in `docs/research/polars-2.md`).
  Each job then runs `library(polars); library(nanoarrow)` as a step of
  its own and fails if either does not load, and sets
  `DATAKIT_REQUIRE_POLARS=true`, which turns the tests' skip into a
  failure, so the polars tests cannot be skipped silently in CI.
- **Docs**: `docs/r.md` gains a polars section: the table above in R
  polars syntax, `is_missing` / `is_na`, `datakit_by_pl`, joins with
  `nulls_equal = TRUE`, and the lifetime note.
- **Benchmark**, kept small: one DHS file, R's `read_parquet_pl()`
  against `pl$read_parquet()` and datakit's `read_parquet()`, recorded in
  `bench/results/`. No target.

## Out of scope

- TypeScript and Julia.
- Publishing.
- Building the letter columns natively for both languages (both do it
  in polars expressions); a follow-up if the benchmark shows it matters.

## Considered options

- **R: `read_parquet(..., as = "polars")`.** One function whose return
  type depends on an argument; the user chose separate functions.
- **R: convert the tibble through nanoarrow.** Less work, but R strings
  are built first, memory holds both copies, and the letter rules would
  be written a second time; the user chose the native stream.
- **`read_fixed_width_pl` through datparser's tibble.** No release 118
  limits, but it builds R vectors, strings included; the native route
  is what Python does.
- **A letter column only for Float64 arguments in `dk.by`.** Needs the
  frame's schema; an all-null column for other types is cheaper than a
  frame argument.
- **Python: pandas.** Built and dropped (plan 0024, stage 4).
- **Letters as nulls in polars by default.** Comparisons would be right,
  but the letters would be lost; `letters = FALSE` stays available.
- **An alias `is_mi`** (Stata's `mi()`). The user chose `is_na`.

## Risks

- **R polars is not on CRAN.** Installation is from R-multiverse;
  datakit only suggests it.
- **NaN payloads are not promised by polars** (`docs/research/polars-2.md`).
  The cross-language check would catch a release that canonicalizes
  them.
- **Stage 2 touches the code Python's datakit depends on.** 2a and 2b
  change no behaviour, which the error-type test, the crate's tests, the
  benchmark and the unchanged suites check.
