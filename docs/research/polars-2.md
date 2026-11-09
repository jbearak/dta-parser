# Polars 2 in R and Python, for R datakit

Question: what does Polars 2 offer, in R and in Python, that bears on
making R's `datakit` (`r/datakit`) return and accept polars data frames,
as Python's `datakit` already does? This note gathers facts; it designs
nothing.

Read and measured 2026-11-09 on macOS arm64 (Apple M4 Max), R 4.6.1
(Homebrew, source packages only), Python 3.14.7. Versions probed:
Python polars 2.1.0, R polars 2.1.0, nanoarrow 0.9.0 (R and Python),
haven 2.5.5 and arrow 26.0.0 (R). R polars source is the R-multiverse
tarball `polars_2.1.0.tar.gz`, which is tag
[`v2.1.0`](https://github.com/pola-rs/r-polars/tree/v2.1.0) (commit
`8af96e2`); paths below are relative to that tree. Python polars source
is tag [`py-2.1.0`](https://github.com/pola-rs/polars/tree/py-2.1.0)
(commit `7f902bd`). "Observed" means we ran it here, on data made in the
probe scripts (appendix). No Stata, Stata files or Stata documentation
were used.

## Short answer

- **Released.** Python polars 2.0.0 came out on 2026-10-06 and 2.1.0 on
  2026-10-25. There is no Rust 2.0: the crates are still 0.55 (the
  workspace at `py-2.1.0` says 0.55.1; crates.io's newest is 0.55.2).
  R polars 2.0.0 (2026-10-18) matches Python 2.0.0, and R polars 2.1.0
  (2026-11-08) is built from the exact commit tagged `py-2.1.0`.
- **R polars is not on CRAN.** CRAN archived `polars` in 2023 (last
  there: 0.7.0). It installs from R-multiverse, as binaries on macOS,
  Windows, and Ubuntu, or from source with a prebuilt Rust library
  downloaded at install time (no Rust toolchain needed). It needs
  R >= 4.3; R datakit says R >= 4.2.
- **The way in without a copy is nanoarrow.** `as_polars_series()` on
  an R double copies element by element and turns every `NA`,
  tagged or not, into a null. `as_polars_df(nanoarrow stream)` imports
  R's own memory without a copy (observed: +0 MiB for 381 MiB). Every
  way out to R copies.
- **Tagged NaNs survive polars, if they arrive as non-null NaNs.**
  Built that way (nanoarrow with the validity buffer dropped, or
  integer64 bits reinterpreted), the letters survived filter, sort,
  join, concat, arithmetic, Parquet, IPC, the streaming engine, and the
  trip back to R bit for bit. They do not survive as group keys or in
  `unique()` (all NaNs are one value), `==` and `is_in()` match any
  NaN, and a Float32 round trip drops R's `NA` marker. The polars user
  guide says NaN payloads are not guaranteed.
- **Metadata does not survive.** Polars drops Arrow field and schema
  metadata on import, in R and Python, and R polars has no way to carry
  R attributes. Python polars has extension types (unstable); R polars
  2.1.0 is built without them, so it fails on any Arrow or Parquet
  column with an extension type, including the `arrow.r.vctrs` columns
  R's arrow writes for labelled vectors (observed: a Rust panic).
- **Factors lose levels.** An R factor becomes a `Categorical`, its
  level order and unused levels gone. R polars turns both `Categorical`
  and `Enum` back into factors with `as.factor()`, so an Enum's
  category order and unused categories are lost on the way back too.
- **Python datakit already targets polars 2** (`polars>=2.0,<3`) and
  uses none of the APIs 2.0 removed. One mismatch: polars 2.1 dropped
  Python 3.10, while datakit says `requires-python = ">=3.10"`.

## 1. Release status

### Python and Rust

| release | date | source |
|---|---|---|
| py-2.0.0-rc.1 | 2026-09-02 | [release](https://github.com/pola-rs/polars/releases/tag/py-2.0.0-rc.1) |
| py-2.0.0-rc.2 | 2026-09-20 | [release](https://github.com/pola-rs/polars/releases/tag/py-2.0.0-rc.2) |
| py-2.0.0 | 2026-10-06 | [release](https://github.com/pola-rs/polars/releases/tag/py-2.0.0), [PyPI](https://pypi.org/project/polars/2.0.0/) |
| py-2.1.0 | 2026-10-25 | [release](https://github.com/pola-rs/polars/releases/tag/py-2.1.0), [PyPI](https://pypi.org/project/polars/2.1.0/) |
| rs-0.55.2 (newest Rust) | 2026-08-06 | [release](https://github.com/pola-rs/polars/releases/tag/rs-0.55.2), [crates.io](https://crates.io/crates/polars) |

- The Rust crates have no 2.0. `[workspace.package] version` at
  `py-2.1.0` is `0.55.1`
  ([Cargo.toml](https://github.com/pola-rs/polars/blob/py-2.1.0/Cargo.toml)),
  and R polars' `polars_info()` reports "Rust Polars crate version:
  0.55.1" next to "Corresponding Python Polars: 2.1.0" (observed).
  "Polars 2" means the Python package and the bindings that track it.
- Python polars 2.1.0 requires Python >= 3.11; 2.0.0 required >= 3.10
  (PyPI metadata). The 2.1.0 notes list "Drop support for Python 3.10
  and test on Python 3.15 (#29888)".
- The 2.0.0 release notes list only the changes since rc.2. The full
  list of breaking changes is the migration guide,
  [Version 2.0](https://docs.pola.rs/releases/upgrade/2/)
  ([source](https://github.com/pola-rs/polars/blob/py-2.1.0/docs/source/releases/upgrade/2.md)).
  2.1.0 adds one: "Disallow mixed string <=> numeric arithmetic in eager
  (#30071)".

### Breaking changes in 2.0 that matter here

From the migration guide, those that touch building frames, dtypes,
Arrow interchange, or categoricals. The guide marks several "may
silently impact the results".

| change | what it does |
|---|---|
| Lazy API defaults to the streaming engine | `engine = "auto"` now picks streaming; row order of many results may change unless sorted or `maintain_order` is set |
| Unknown Arrow extension types load as extension dtypes | a column with an `ARROW:extension:name` polars does not know becomes `pl.Extension(name, storage)` instead of its storage type; `POLARS_UNKNOWN_EXTENSION_TYPE_BEHAVIOR=load_as_storage` restores the old behavior (Python) |
| `Map` dtype | Arrow, Parquet, and Iceberg map columns load as `pl.Map(key, value)`, not `List(Struct)` |
| `from_arrow(<stream-only object>)` returns a `Series` | an object with only `__arrow_c_stream__` now gives a `Series` of `Struct`; `pl.DataFrame(obj)` still gives a frame (observed) |
| DataFrame interchange protocol removed | `__dataframe__` gone; `pl.from_dataframe()` takes PyCapsule objects only |
| No casts between integers and categoricals | `UInt32 -> Enum` and `Enum -> UInt32` casts raise; use `.cat.to()` and `.cat.physical()` (observed in R and Python; `to_physical()` still works in Python) |
| `pl.Categorical(ordering=)` removed | categoricals always sort lexically; `pl.Categorical("physical")` silently names a `Categories` pool "physical" |
| Signed integer + `UInt64` supertype is `Int128` | was `Float64` |
| `is_in()` coerces only losslessly | `Float64.is_in([1, 2])` raises; `is_in([1.0, 2.0])` works (observed) |
| Parquet `ENUM` logical type reads as `String` | was `Binary`; polars never writes it |
| Removed deprecated APIs | including `Series.cat.get_categories()`, `cat.is_local()`, `to_local()`, `uses_lexical_ordering()`, `Enum.union()` (table under "Removal of deprecated functionality") |

### R polars

| release | date | tracks | source |
|---|---|---|---|
| 1.0.0 (rewrite) | 2025-07-21 | Python 1.31.0 | [release](https://github.com/pola-rs/r-polars/releases/tag/v1.0.0), [NEWS](https://github.com/pola-rs/r-polars/blob/v2.1.0/NEWS.md) |
| 1.16.0 | 2026-09-13 | Python 1.44, with 2.0 deprecation warnings | [release](https://github.com/pola-rs/r-polars/releases/tag/v1.16.0) |
| 2.0.0 | 2026-10-18 | Python 2.0.0 | [release](https://github.com/pola-rs/r-polars/releases/tag/v2.0.0) |
| 2.1.0 | 2026-11-08 | Python 2.1.0 | [release](https://github.com/pola-rs/r-polars/releases/tag/v2.1.0) |

- **Which Rust polars it binds.** `src/rust/Cargo.toml` at `v2.1.0`
  pins every polars crate to git rev
  `7f902bd3ffd27ff82d14278a09a295ff2f7aed92`
  ([Cargo.toml](https://github.com/pola-rs/r-polars/blob/v2.1.0/src/rust/Cargo.toml)).
  That is the commit the `py-2.1.0` tag points to (GitHub's compare
  API: "identical"). MSRV `rust-version = "1.97.0"`.
- **NEWS for 2.0.0** says it "matches Python Polars 2.0.0 and completes
  the R Polars 2.0 API transition" and points to the Python migration
  guide. The R-specific changes mirror Python's: streaming default,
  `Int128` supertype, strict `is_in`, `pl$Categorical()` without
  `ordering`, `pl$Map()`, Parquet `ENUM` as String, removed
  `$cat$get_categories()` and `<Enum>$union()`.
- **CRAN: no.** [CRAN's page](https://CRAN.R-project.org/package=polars)
  says the package "was removed from the CRAN repository ... Archived on
  2023-07-18 for policy violations"; the archive's last version is
  0.7.0.
- **R-multiverse: yes.** `https://community.r-multiverse.org/api/packages/polars`
  gives Version 2.1.0, published 2026-11-08, commit `8af96e2`, with
  binaries built and checked "OK" for macOS (R 4.5, 4.6; arm64 and
  x86_64), Windows (R 4.5, 4.6, 4.7; x86_64 and arm64 for 4.6, 4.7),
  and Linux (Ubuntu "resolute", R 4.6 and 4.7; x86_64 and aarch64).
  The README recommends
  `Sys.setenv(NOT_CRAN = "true"); install.packages("polars", repos = "https://community.r-multiverse.org")`.
  We did not check whether polars is in R-multiverse's production
  snapshot; its API did not answer.
- **Install from source.**
  [Installation details](https://pola-rs.github.io/r-polars/vignettes/install.html)
  (`vignettes/install.Rmd`): when `NOT_CRAN="true"`, `MY_UNIVERSE` is
  set, or `LIBR_POLARS_BUILD="false"`, the configure step downloads a
  prebuilt `libr_polars` for the platform from the `lib-v*` GitHub
  release, checks its SHA-256 against `tools/lib-sums.tsv`, and links
  it; otherwise, or if the download fails, it builds the Rust library
  with cargo. `LIBR_POLARS_PATH` points at a local copy.
  `SystemRequirements: Cargo (Rust's package manager), rustc`;
  `Config/pak/sysreqs: libclang-dev`.
- **Observed install.** On Homebrew R (source only) with
  `NOT_CRAN=true`, `install.packages()` fetched the 2.4 MB source
  tarball and the 261 MB `libr_polars-2.1.0-rc.1-aarch64-apple-darwin.tar.gz`,
  matched its SHA-256, and installed without running cargo, in about a
  minute. The installed package is 155 MB, 151 MB of it the shared
  library. `polars_info()` shows the `nightly` feature on. The 2.1.0
  package uses the `lib-v2.1.0-rc.1` library
  (`Config/polars/lib-version: 2.1.0-rc.1` in DESCRIPTION).
- **Dependencies.** `Depends: R (>= 4.3)`; `Imports: rlang (>= 1.2.0),
  S7 (>= 0.2.1)`; arrow, nanoarrow (>= 0.6.0), tibble, bit64, blob,
  hms, clock, vctrs and others are `Suggests`
  ([DESCRIPTION](https://github.com/pola-rs/r-polars/blob/v2.1.0/DESCRIPTION)).
  License MIT.

## 2. Building frames in R polars

### From R vectors

| call | what it does | source |
|---|---|---|
| `as_polars_series(x, name = NULL, ...)` | S3 generic; methods for logical, integer, double, character, factor, Date, POSIXct, POSIXlt, difftime, hms, ITime, integer64, raw, blob, list, data.frame, AsIs, `vctrs_rcrd`, `vctrs_unspecified`, clock classes, nanoarrow arrays and streams, arrow `ArrowTabular` and `RecordBatchReader`, Python objects | `R/as_polars_series.R`, `NAMESPACE` |
| `as_polars_df(x, ...)` | data.frame and list: one `as_polars_series()` per column, length-1 columns recycled; anything else: through `as_polars_series()`, which must give a Struct, then `$struct$unnest()` | `R/as_polars_df.R:84-114,160-195` |
| `pl$DataFrame(..., .schema_overrides = NULL, .strict = TRUE)` | columns as named arguments | `R/dataframe-frame.R:79` |

- An unknown class is an error: `as_polars_series.default` aborts with
  "can't be converted to a polars Series" (`R/as_polars_series.R:185`).
  S3 dispatch uses the class attribute, so `haven_labelled`
  (`c("haven_labelled", "vctrs_vctr", "double")`) reaches the double
  method, while `dtaparser_labelled` (`c("dtaparser_labelled",
  "vctrs_vctr")`) has no method and errors (observed). NEWS for 1.0.0:
  "Developers can specify how those objects should be handled by polars
  by creating a method for `as_polars_series.my_class`."
- **Copies.** `new_f64` and `new_i32` build the column by iterating
  over the R vector, mapping `is_na()` values to `None`
  (`src/rust/src/series/construction.rs:14-28`). So it is a copy, and
  every R `NA_real_`, tagged or not, becomes a null; R `NaN` stays NaN
  (observed). A factor goes through `as.character()` and a cast to
  `Categorical` (`R/as_polars_series.R:260-266`). POSIXct is stored in
  milliseconds (`new_i64_from_numeric_and_multiplier(..., 1000L,
  "floor")`, line 280).

### Arrow C stream (nanoarrow and arrow)

R polars has no `$export_stream()` or `__arrow_c_stream__`-like method
of its own. It plugs into nanoarrow's and arrow's generics, registered
lazily in `.onLoad` (`R/zzz.R:101-108`):

| direction | function | source |
|---|---|---|
| in | `as_polars_series(<nanoarrow_array_stream>)`, `as_polars_series(<nanoarrow_array>)` | `R/as_polars_series.R:467-484` |
| in | `as_polars_df(<nanoarrow_array_stream>)` (default method: struct Series, then unnest) | `R/as_polars_df.R:84` |
| in | `as_polars_series(<RecordBatchReader>)`, `as_polars_series(<ArrowTabular>)`, via arrow's C stream export | `R/as_polars_series.R:488-503` |
| out | `nanoarrow::as_nanoarrow_array_stream(<polars_data_frame | polars_series>, schema = NULL, polars_compat_level = c("newest", "oldest"))` | `R/dataframe-s3-nanoarrow.R`, `R/series-s3-nanoarrow.R` |
| out | `nanoarrow::as_nanoarrow_array_stream(<polars_lazy_frame>, ..., maintain_order = FALSE, chunk_size = NULL)`, which runs the query on the streaming engine as it is read (since R polars 1.8.0) | `R/lazyframe-s3-nanoarrow.R` |
| out | `arrow::as_arrow_table()`, `arrow::as_record_batch_reader()` | `R/dataframe-s3-arrow.R` |

- The Rust side is polars' own Arrow FFI: `PlRSeries$from_arrow_c_stream`
  takes the stream out of the external pointer, reads every array, and
  builds a Series from them (`src/rust/src/series/import.rs`);
  `to_arrow_c_stream` exports one array per chunk
  (`src/rust/src/series/export.rs:402-417`). Both carry "TODO: move to
  upstream polars" comments.
- A data frame goes out as one struct column; a struct array's
  children are the columns.
- `polars_compat_level = "oldest"` exports `large_string` instead of
  `string_view` (observed for dictionary values). The default can be
  set with option `polars.compat_level` (NEWS 1.4.0).
- **Zero copy, measured.** RSS change of the R process, 5e7 doubles
  (381 MiB):

  | step | RSS change |
  |---|---|
  | `as_polars_series(x)` | +388 MiB |
  | `as_polars_df(data.frame(y = x))` | +388 MiB |
  | `a <- nanoarrow::as_nanoarrow_array(x)` (no NA) | +0 MiB |
  | same with one `NA` | +6 MiB (the validity bitmap) |
  | `as_polars_series(a)` | +0 MiB |
  | `as_polars_df(as_nanoarrow_array_stream(data.frame(y = x)))` | +1 MiB |
  | `series$to_r_vector()` | +383 MiB |
  | `as.data.frame(polars_df)` | +395 MiB |
  | `as_nanoarrow_array_stream(series)` and `$get_next()` | +0 MiB |
  | `nanoarrow::convert_array()` of that array | +384 MiB |

  nanoarrow borrows the R vector's memory as the data buffer ("Zero-copy
  create: just borrow the data buffer", nanoarrow `src/as_array.c:263-264`),
  and polars imports Arrow buffers by reference, so R to polars through
  nanoarrow costs nothing for doubles and integers. Polars to R always
  copies: R vectors own their memory, and the doubles `convert_array()`
  returns are ordinary `REALSXP`s, not ALTREP (observed with
  `.Internal(inspect())`). The Arrow C data interface itself is "zero-copy
  by design" and keeps buffers alive through each structure's release
  callback ([C data interface](https://arrow.apache.org/docs/format/CDataInterface.html)).
- **nanoarrow marks R `NaN` as null too.** For a double vector it sets
  a row invalid when `R_IsNA(x) || R_IsNaN(x)` (nanoarrow 0.9.0
  `src/as_array.c:339-364`). So both `as_polars_series(x)` and the
  nanoarrow route turn tagged NAs into nulls; only the direct route
  keeps a plain `NaN` as NaN.

### Back to R

`as.data.frame(<polars_data_frame>)`, `tibble::as_tibble()`, and
`<series>$to_r_vector()` share one converter
(`src/rust/src/series/export.rs:105-383`). Options: `uint8 = c("integer",
"raw")`, `int64 = c("double", "character", "integer", "integer64")`,
`date = c("Date", "IDate")`, `time = c("hms", "ITime")`, `struct =
c("dataframe", "tibble")`, `decimal = c("double", "character")`,
`as_clock_class = FALSE`, also settable as `polars.to_r_vector.*`
options (`R/series-to_r_vector.R:187-217`). The `as_tibble()` method
returns a tibble and nests structs as tibbles (observed). Defaults,
observed:

| polars dtype | R class |
|---|---|
| Int8, Int16, Int32, UInt8, UInt16 | integer |
| Int64, Int128, UInt32, UInt64, UInt128 | double (`int64` option: character, integer, or `integer64`) |
| Float16, Float32, Float64 | double |
| Boolean | logical |
| String | character |
| Categorical, Enum | factor, made by `as.factor()` of the strings (`export.rs:153-161`) |
| Binary | `blob` |
| Date | Date |
| Datetime, with or without zone | POSIXct; a datetime without a zone is taken as wall-clock time in the local zone |
| Time | `hms` |
| Duration | `difftime` |
| Decimal | double (option: character) |
| Null | `vctrs_unspecified` |
| Struct | data.frame |
| List, Array | `vctrs_list_of` |
| Map | as its storage, a list of key/value data frames (NEWS 2.0.0) |
| Extension | unsupported (falls to "Conversion from Polars dtype ... to R vector is not supported", `export.rs:378`) |

R to polars, observed: logical → Boolean; integer → Int32; double →
Float64; character → String; factor and ordered factor → Categorical;
Date → Date; POSIXct → Datetime(ms, its `tzone`, or none); difftime →
Duration(ms); hms → Time; integer64 → Int64; blob → Binary; raw →
UInt8; list → List; data.frame → Struct; `haven_labelled` → Float64
(class, `labels`, and `label` dropped); `dtaparser_labelled` → error.

## 3. Dtypes

R polars 2.1.0 builds polars with `dtype-full`
(`src/rust/Cargo.toml:98`), which in the polars crate is date,
datetime, duration, time, array, i8, i16, i128, decimal, u8, u16, u128,
f16, categorical, struct, and map
([crates/polars/Cargo.toml:386-403](https://github.com/pola-rs/polars/blob/7f902bd3ffd27ff82d14278a09a295ff2f7aed92/crates/polars/Cargo.toml)).
It does not include `dtype-extension` (line 511), which polars' Python
bindings enable
([crates/polars-python/Cargo.toml:86](https://github.com/pola-rs/polars/blob/py-2.1.0/crates/polars-python/Cargo.toml)).
`Int128`, `UInt128`, and `Float16` all exist in R polars (observed;
Float16 since R polars 1.7.0).

### Categorical and Enum

- **The 1.32 rework.** Python 1.32.0 (2025-08-01) shipped "Rework
  Categorical/Enum to use (Frozen)Categories"
  ([pola-rs/polars#23016](https://github.com/pola-rs/polars/pull/23016),
  by a maintainer). Its description: "Physical ordering and the String
  Cache are gone"; "The concept of local and global categories is
  gone"; casts between Categorical and integers then referred to the
  physical codes and were to be removed (they were, in 2.0); a new
  Parquet encoding means Enums written by new versions read back as
  Categoricals in older ones.
- **Python's `Categories`.** `pl.Categories(name=None, namespace="",
  physical=pl.UInt32)` names a mapping; two with the same name,
  namespace, and physical type share codes; no name means the global
  one; physical may be UInt8, UInt16, or UInt32; marked unstable
  (`py-polars/src/polars/datatypes/classes.py:677`,
  [docs](https://docs.pola.rs/api/python/stable/reference/api/polars.datatypes.Categories.html)).
  `pl.Categorical(pl.Categories("dta"))` works (observed).
  `pl.StringCache()` and `pl.enable_string_cache()` still exist in 2.1
  and warn "the string cache has been replaced by pl.Categories"
  (observed).
- **R polars.** `pl$Categorical()` takes no arguments and always uses
  the global categories (`R/datatypes-classes.R:203-208`);
  `pl$Enum(categories)` takes a character vector without NA or
  duplicates (lines 213-229). No `Categories` object is exposed.
  `$cat$to()` and `$cat$physical()` exist since R polars 1.14.0.
- **Factors in.** `as_polars_series(<factor>)` is
  `as.character()` then a cast to Categorical, so level order, unused
  levels, and orderedness are dropped. `factor(c("lo", "hi"), levels =
  c("lo", "mid", "hi"))` came back from polars with levels `hi lo`
  (observed). Through nanoarrow a factor is a dictionary array (int32
  keys, string values) and also imports as `Categorical`. Through arrow,
  an ordered dictionary imports as `Categorical` too; polars makes an
  Enum from an Arrow dictionary only when the field carries polars' own
  `_PL_ENUM_VALUES2` metadata (observed).
- **Factors out.** Categorical and Enum both become `as.factor()` of
  their strings (`export.rs:153-161`), so levels are sorted and unused
  ones dropped: an `Enum(c("b", "a"))` came back with levels `a b`, and
  `Enum(c("lo", "mid", "hi"))` holding `lo` and `hi` came back with
  levels `hi lo` (observed). Through
  `arrow::as_arrow_table(df, polars_compat_level = "oldest")`, the same
  Enum became an ordered factor with levels `lo mid hi`, all kept
  (observed): polars exports an Enum as an ordered dictionary with uint8
  keys and field metadata `_PL_ENUM_VALUES2 = "2;lo3;mid2;hi"`.
- **Two nanoarrow 0.9.0 errors, observed, not investigated.**
  `nanoarrow::as_nanoarrow_array(<ordered factor>)` and
  `convert_array_stream()` of a polars frame holding an Enum both stop
  with "ArrowSchemaViewInit(): ARROW_FLAG_DICTIONARY_ORDERED is only
  relevant for dictionaries". arrow 26 cannot convert the default
  (`string_view`) dictionary values to R ("cannot handle Array of type
  <utf8_view>"); `polars_compat_level = "oldest"` avoids that. Read
  `docs/other-readers.md` before calling any of these a bug.

### Extension types

- **Python.** `pl.Extension(name, storage, metadata=None)` and
  `pl.BaseExtension` for user classes, with
  `pl.register_extension_type(ext_name, ext_class=None, *,
  as_storage=False)`, `unregister_extension_type`, and
  `get_extension_type`. All are marked unstable
  (`py-polars/src/polars/datatypes/extension.py`,
  [docs](https://docs.pola.rs/api/python/stable/reference/api/polars.register_extension_type.html)).
  Added in 1.36.0 by
  [pola-rs/polars#25322](https://github.com/pola-rs/polars/pull/25322);
  "name, and optional metadata ... is all stored when writing to
  Parquet/IPC". `Series.ext.to(dtype)` and `.ext.storage()` convert.
- **What works on an Extension column in Python** (observed, a
  `Float64` storage): sort, filter, join, group-by `first()`, concat,
  `is_null()`, Parquet and IPC round trips (dtype and metadata kept),
  and a registered class comes back as that class from Parquet. The
  Arrow C stream export carries `ARROW:extension:name` and
  `ARROW:extension:metadata`. What fails: `+ 1`, `== 1`,
  `cast(pl.Float64)` ("cannot cast extension types"), `fill_null(0)`;
  `mean()` returns None. `.ext.storage()` gives the storage back with
  tagged-NaN bits intact. (ADR 0036 rejected extension types for these
  reasons.)
- **R.** No Extension dtype or constructor; an open issue, "Support
  extension types"
  ([pola-rs/r-polars#1674](https://github.com/pola-rs/r-polars/issues/1674),
  opened by the maintainer). Importing a C stream whose field has an
  extension name fails: "cannot create series from
  Extension(ExtensionType { name: "dta.test", ... })". Reading a Parquet
  file with an extension column panics in Rust: "Arrow datatype
  Extension(...) not supported by Polars. You probably need to activate
  that data-type feature", with or without
  `POLARS_UNKNOWN_EXTENSION_TYPE_BEHAVIOR=load_as_storage` (observed).
  This includes a file R's own `arrow::write_parquet()` writes from a
  `haven_labelled` column, which is stored as extension type
  `arrow.r.vctrs` (see `parquet-r-julia.md`). Python polars reads that
  file as `Extension('arrow.r.vctrs', Float64, <serialized R
  prototype>)` (observed).

### Other new dtypes

`Map(key, value)` (2.0), `Int128`, `UInt128`, `Float16`, and
`Extension` (Python only) are the dtypes newer than 1.0. In R a Map
converts to a `vctrs::list_of` of key/value data frames (NEWS 2.0.0).

## 4. Missing values: null, NaN, and tagged NaNs

### What polars promises

- "The value NaN is considered to be a valid floating point value,
  which is different from missing data"
  ([Missing data](https://docs.pola.rs/user-guide/expressions/missing-data/)).
- "Any NaN compares equal to any other NaN, and greater than any
  non-NaN value. Operations do not guarantee any particular behavior on
  the sign of zero or NaN, nor on the payload of NaN values. This is not
  just limited to arithmetic operations, e.g. a sort or group by
  operation may canonicalize all zeroes to +0 and all NaNs to a positive
  NaN without payload for efficient equality checks"
  ([Data types and structures, "Floating point numbers"](https://docs.pola.rs/user-guide/concepts/data-types-and-structures/)).
- A maintainer's open issue proposes optional NaN canonicalization on
  Parquet writes, and says it "should be configurable, such that users
  are still able to pass floats through Polars without them being
  altered" ([pola-rs/polars#26770](https://github.com/pola-rs/polars/issues/26770)).
- Arrow says nothing on the value under a null: "Array slots which are
  null are not required to have a particular value; any 'masked' memory
  can have any value" ([Columnar format, Validity bitmaps](https://arrow.apache.org/docs/format/Columnar.html)).
  ADR 0036 found polars writes zeros there on sort, gather, and join.

### R to polars and back

The input was `c(1.5, tagged_na("a"), NA, tagged_na("z"), NaN)`, bits
`3ff8000000000000`, `7ff00061000007a2`, `7ff00000000007a2`, `7ff0007a000007a2`,
`7ff8000000000000` (haven's layout: R's `NA_real_`, low word 1954, the
letter in bits 32 to 39).

| route in | rows that are null in polars | back in R |
|---|---|---|
| `as_polars_series(x)` | the three `NA`s | plain `NA_real_` for all three; `NaN` kept |
| `as_polars_series(as_nanoarrow_array(x))` | all four NAs and NaNs | plain `NA_real_` for all four |
| nanoarrow array with the validity buffer dropped (`nanoarrow_array_modify(a, list(null_count = 0, buffers = list(NULL, a$buffers[[2]])))`) | none; `is_nan()` true on rows 2 to 5 | every bit as input |
| integer64 of the bits, `$reinterpret(dtype = pl$Float64)` | none | every bit as input |

The way back copies values as they are (`set_elt` per value; null →
`NA_real_`: `src/rust/src/conversion/chunked_array.rs:87-100`), so a
tagged NaN that reaches R is a tagged NA again: `is.na()` true,
`haven::na_tag()` the letter. `as.data.frame()`, `as_tibble()`,
`$to_r_vector()`, and `convert_array_stream()` all gave the input bits
back (observed).

### Through polars operations

The frame from the third route, with `id = 1:5` and `g`. "Kept" means
each row's bits came back as input, in the expected row order.

| operation | R polars 2.1.0 | Python polars 2.1.0 |
|---|---|---|
| `filter`, `sort` by another column, `concat`, `shift` | kept | (ADR 0036: kept) |
| `sort` by `x` | kept; NaNs last, in input order | kept; nulls first, NaNs last |
| `join` on another key, inner and left, eager and streaming | kept | kept |
| `group_by(g)` then `first()`, `last()`, or the list | kept | kept (streaming) |
| `x` as a group key | all NaNs one group; key came back as a plain NaN (no `maintain_order`) | all NaNs one group; key had the first NaN's bits (`maintain_order=True`) |
| `unique()` | one NaN left (the first, tag `a`) | one NaN left (tag `a`); `n_unique()` counts all NaNs as one |
| `join` on `x` | not tried | each NaN row matched every NaN row (10 rows from 5) |
| `x == tagged_na("a")`, `is_in()` | not tried | true for `a`, `z`, and plain NaN alike |
| `x + 0`, `abs()`, `when/then` | kept | (ADR 0036: arithmetic kept) |
| `x * 2` | tag and low word kept; quiet bit set (`7ff0` → `7ff8`) | |
| `-x` | tag kept; sign bit set | |
| `cast(Float32)$cast(Float64)` | tag kept, low word lost (`7ff8006100000000`): R sees NaN, not NA; `haven::na_tag()` still says `a` | same bits |
| `max()`, `min()` | NaNs ignored (1.5) | NaNs ignored; `mean()` NaN |
| `rank()` | | all NaNs tie |
| `fill_nan(NULL)` | every NaN, tagged or not, becomes null | |
| Parquet write and read (`read_parquet`, streaming `scan_parquet`), IPC | kept; arrow R reads polars' file with tags intact | kept |

So the letters ride through row operations, but any operation that
compares values (keys, `unique`, `==`, `is_in`, joins on the column)
treats every NaN as the same value, and the docs reserve the right to
canonicalize payloads in sort and group-by.

## 5. Metadata

- **Polars keeps no Arrow field or schema metadata.** A stream with
  schema metadata `dta = "schema-level"` and field metadata `label = "X
  label"` went into `pl.DataFrame()` (Python) and `as_polars_df()` (R)
  and came out of `__arrow_c_stream__` / `as_nanoarrow_array_stream()`
  with none (observed in both; input metadata confirmed present). A
  maintainer, closing
  [pola-rs/polars#18316](https://github.com/pola-rs/polars/issues/18316)
  in 2024: "Polars doesn't aim to maintain full arrow metadata nor
  types. We might do extension types, but I am not guaranteeing that to
  be arrow types."
- **What polars adds itself.** On export, polars writes its own field
  metadata for Enum (`_PL_ENUM_VALUES2`) and, per
  `parquet-python.md`, `_PL_CATEGORICAL2` for Categorical (observed for
  Enum through R's C stream). Extension types carry
  `ARROW:extension:name` and `ARROW:extension:metadata`, which the C
  data interface stores in `ArrowSchema.metadata`
  ([C data interface, Extension arrays](https://arrow.apache.org/docs/format/CDataInterface.html));
  the spec also lets the top-level `ArrowSchema.metadata` of a stream
  hold schema-level metadata.
- **Parquet.** Python's `write_parquet(metadata=...)` writes file
  key-value metadata (`read_parquet_metadata()` lists it beside
  `ARROW:schema`, observed), and `arrow_schema=` sets field metadata
  (`parquet-python.md`). R polars' `$write_parquet()` has neither
  argument (`R/output-parquet.R:204-216`: `file, ..., compression,
  compression_level, statistics, row_group_size, data_page_size,
  partition_by, partition_chunk_size_bytes, storage_options, mkdir`).
- **R attributes.** `as_polars_df()` builds columns from the vectors'
  data; column attributes (`label`) and frame attributes are gone on the
  way back (observed: `as.data.frame()` gives only `names`, `row.names`,
  `class`). No R polars function reads or writes metadata; the only
  `metadata` in its R code is Python's `importlib.metadata` in the
  reticulate integration.
- **Through operations.** Python extension dtypes, with their metadata
  string, survived sort, filter, join, group-by, concat, Parquet, and
  IPC (observed). Plain field metadata cannot survive operations since
  it is dropped on import.

So in R, labels, formats, and value labels cannot ride inside a polars
frame; R polars offers neither field metadata nor extension types.

## 6. Python datakit and polars 2

`python/datakit` already depends on `polars>=2.0,<3`
(`pyproject.toml`), and ADR 0036 was decided against polars 2.1. The
polars calls it makes, and how 2.0 treats each:

| datakit call | where | 2.0 status |
|---|---|---|
| `pl.DataFrame(native_frame)` on the core's Arrow stream object | `_frame.py:105` | unchanged; only `pl.from_arrow()` on stream-only objects now returns a Series (observed) |
| `cast(pl.Categorical)` from String | `_frame.py:112` | fine; global `Categories` |
| `pl.Enum(levels)`, `replace_strict(..., return_dtype=pl.Enum(...))` from Float64 | `_frame.py:278,335`, `_parquet.py:78` | fine (observed) |
| `to_physical()` on Enum and Categorical | `_frame.py:199,433,438`, `_tagged.py:71,96` | fine; integer ↔ categorical `cast()` would now raise, and datakit does not use it |
| `present.cast(pl.Float64).is_in(codes)` | `_frame.py:273` | fine: `codes` are floats (`_frame.py:242`); ints would now raise |
| `reinterpret(dtype=pl.UInt64)` / `(dtype=pl.Float64)` for tagged NaNs | `_tagged.py:71,97` | fine |
| `pl.Decimal(p, s)`, `Datetime`, `dt.epoch()`, `arg_sort_by` | `_frame.py`, `_parquet.py` | no listed change |
| no `StringCache`, `Categorical(ordering=)`, `from_arrow`, `__dataframe__`, extension types, or `pl.read_parquet` | | not affected |

Points a design may need to note for Python:

- `requires-python = ">=3.10"` while polars 2.1 needs 3.11; on 3.10 pip
  resolves to polars 2.0.0.
- Users who read Parquet with `pl.read_parquet()` (not datakit) now get
  `Extension` columns for unknown extension types, for example R arrow's
  `arrow.r.vctrs`.
- The equality semantics above (every NaN equal) apply to Python's
  letters as much as to R's.
- The lazy API's default engine is now streaming, which can reorder
  rows unless asked not to.

## 7. Letters in other frame libraries (probed after this note)

These probes followed the note, while deciding plan 0024 (whose move
of Python's datakit to pandas was later dropped; plan 0025, ADR 0041).
Their scripts
are in [`polars-2-probes/`](polars-2-probes/); they ran on 2026-11-09
on the same machine, with R 4.6.1, arrow 26.0.0, dplyr 1.2.1, vctrs
0.7.3, haven 2.5.5, bench 1.1.4, nanoarrow 0.9.0, Python polars 2.1.0
and pandas 3.1.1 (numpy 2.5.4). The rows were `1, 5000, .a, .b, .`,
with `.` a null (an `NA` in R) and the letters as R's tagged NaNs.

### Comparisons (`cmp.R`, `cmp.py`)

| expression | polars 2.1 | arrow 26 | R double (tibble) |
|---|---|---|---|
| `x == 1` | T F F F null | T F F F NA | T F NA NA NA |
| `x != 1` | F T T T null | F T T T NA | F T NA NA NA |
| `x > 3000` | F T T T null | F T F F NA | F T NA NA NA |
| `x == .a` | F F T T null | F F F F NA | NA everywhere |
| rows `filter(x != 1)` keeps | 3 | 3 | 1 |
| `if_else(x > 3000, "hi", "lo")` | lo hi hi hi lo | lo hi lo lo NA | lo hi NA NA NA |

polars orders NaN above every number and makes every NaN equal to
every other; arrow follows IEEE 754, so a NaN compares false with
everything. `pl.col("x").fill_nan(None) > 3000` gives
`F T null null null`.

### arrow (`probe*.R`)

Letters were put in an arrow array as non-null NaNs by dropping the
validity bit of their rows through nanoarrow; `Array$create()` of a
tagged NA makes a null and loses the letter.

- `unique`, `value_counts`, `group_by() |> summarise()`, `distinct()`,
  `left_join()` on the column and `is_in`/`%in%` kept `.a` and `.b`
  apart. `equal(x, .a)` was false on every row.
- Filter, arrange, arithmetic, Parquet and `collect()` kept the letters
  bit for bit.
- dplyr's `is.na(x)` was true for the letters; `mean(x, na.rm = TRUE)`
  was NaN until the NaNs were made nulls first.
- Grouping compares bits: an `.a` that had been through `x * 2` (quiet
  bit set) and one that had not formed two groups, and `%in%` matched
  only the untouched one.
- With the letters as nulls and their bits left in the data buffer,
  `filter` and `concat_arrays` kept the bits; `arrange` and `Take`
  wrote zeros.

### R (`probe5.R`, `bench.R`, `by.R`, `t.R`)

On a column `1 .a .b . .a` brought back by `collect()` (bit for bit):

- Put `.`, `.a` and `.b` in one group or value: base `unique()`,
  `duplicated()`, `match()`, `%in%`, `table()`, `factor()`, `split()`;
  vctrs `vec_unique()`, `vec_group_id()`, `vec_in()`; dplyr
  `distinct()`, `group_by()`, `count()`, `left_join()` (each `.a` row
  matched both `.a` and `.b` in the other table, and `.` matched both),
  `filter(x %in% .a)`.
- Kept the letters: subsetting, `order()`, `arrange()`, `ifelse()`,
  `if_else()`, arithmetic, `bind_rows()`, `is_tagged_na()`.

On 10 million rows (1,000 values, 10% letters, 5% `.`; median of 5
runs), vctrs comparison proxies on `dtaparser_labelled`
(dtatools' `dta_keys()` as the key, 47 ms per call) made `group_by() |>
summarise()` go from 140 to 200 ms, `distinct()` from 43 to 120 ms,
`arrange()` from 137 (plain) to 224 ms, and `filter(x > 500)` from 43 to
229 ms, since the class's `>` goes through vctrs' comparison. Grouping
by the column and `na_tag()` of it found 1,004 groups in 256 ms, against
1,001 in 136 ms for the column alone; a one-column proxy class took 207
ms but stayed on the column afterwards.

### pandas (`pd.py`, `pd2.py`, `pd3.py`)

- **Plain `float64` with tagged NaNs**: `isna()`, `count()` and `mean()`
  treat the letters as missing; comparisons are false (`x != 1` true)
  as in arrow; `groupby(dropna=False)` and `unique()` put every NaN in
  one group; sorting and arithmetic keep the bits.
- **Nullable `Float64`**: comparisons give `<NA>` and a filter keeps 1
  row, as R. Built from a numpy array (`pd.array(v, dtype="Float64")`)
  the NaNs become `<NA>` and the letter bits are gone. Built from values
  and a mask (`FloatingArray(v, mask)`), the bits under the mask
  survived take, filter, sort, concat, merge, reindex, shift, `-x`,
  `abs`, `round`, `clip` and arithmetic, but not `astype`,
  `groupby().transform("first")`, `apply`, `fillna`, `where`, `mask`
  or `combine_first`, and `cumsum()` overwrote the letters of its
  input column with zeros. An unmasked NaN became `<NA>` under `x * 2`.
- `pd.DataFrame.from_arrow` and `DataFrame.__arrow_c_stream__` need
  pyarrow.
- A nullable boolean mask with `<NA>`: `df[mask]` and `df.loc[mask]`
  drop those rows; `np.where(mask, ...)` and `bool(mask[i])` raise
  `TypeError`.

## What could not be established

- Whether the NaN payloads that survived here are guaranteed in later
  releases: the docs say they are not, and no code path we read
  promises them. Which operations canonicalize today was observed, not
  read from source.
- Whether polars is in R-multiverse's production snapshot (the API at
  `production.r-multiverse.org` did not return JSON).
- When R polars will add extension types (#1674 is open with no plan
  stated).
- The cause of the two nanoarrow 0.9.0 errors on ordered dictionaries.
- Whether R polars' lack of `dtype-extension` is deliberate or an
  oversight: neither NEWS nor #1674 says.

## Appendix: probe code

Scratch library: `R_LIBS=$TMPDIR/polars2-research/rlib`, installed with
`Sys.setenv(NOT_CRAN = "true"); install.packages("polars", repos =
c("https://community.r-multiverse.org", "https://cloud.r-project.org"),
type = "source")` and `install.packages("nanoarrow", type = "source")`.
Python: a uv venv with `polars==2.1.0`, `nanoarrow` 0.9.0 (pyarrow
26.0.1 was installed but hung on import inside the sandbox and was not
used). RSS was read with `ps` outside the sandbox.

Tagged NaNs in R (condensed):

```r
library(polars); library(nanoarrow)
hex <- function(x) vapply(x, function(v) paste(rev(as.character(writeBin(v, raw()))), collapse = ""), "")
x <- c(1.5, haven::tagged_na("a"), NA, haven::tagged_na("z"), NaN)
s1 <- as_polars_series(x, "x")                        # NAs become nulls
a <- as_nanoarrow_array(x); s2 <- as_polars_series(a) # NAs and NaN become nulls
a3 <- nanoarrow_array_modify(a, list(null_count = 0, buffers = list(NULL, a$buffers[[2]])))
s3 <- as_polars_series(a3, "x")                       # five values, four NaNs
i64 <- structure(readBin(writeBin(x, raw()), "double", n = 5), class = "integer64")
s4 <- pl$select(as_polars_series(i64, "x")$reinterpret(dtype = pl$Float64))$to_series()
df <- pl$DataFrame(id = 1:5, g = c("p", "q", "p", "q", "p"))$with_columns(x = s3)
other <- pl$DataFrame(id = c(4L, 2L, 1L, 5L, 3L), w = c(40, 20, 10, 50, 30))
hex(as.data.frame(df$sort("x"))$x)
hex(as.data.frame(other$join(df, on = "id", how = "left"))$x)
hex(as.data.frame(df$group_by("x")$agg(pl$len()))$x)
hex(as.data.frame(df$select(pl$col("x")$cast(pl$Float32)$cast(pl$Float64)))$x)
hex(as.data.frame(other$lazy()$join(df$lazy(), on = "id")$collect(engine = "streaming"))$x)
df$write_parquet(f <- tempfile(fileext = ".parquet")); hex(as.data.frame(pl$read_parquet(f))$x)
hex(convert_array_stream(as_nanoarrow_array_stream(df))$x)
haven::na_tag(as.data.frame(df)$x)
```

Copies (condensed; run outside the sandbox):

```r
rss <- function() as.numeric(system2("ps", c("-o", "rss=", "-p", Sys.getpid()), stdout = TRUE)) / 1024
x <- runif(5e7); gc()
r0 <- rss(); s <- as_polars_series(x); rss() - r0                      # +388
r0 <- rss(); a <- as_nanoarrow_array(x); p <- as_polars_series(a); rss() - r0   # +0
r0 <- rss(); v <- s$to_r_vector(); rss() - r0                          # +383
r0 <- rss(); a2 <- as_nanoarrow_array_stream(s)$get_next(); rss() - r0 # +0
r0 <- rss(); v2 <- convert_array(a2); rss() - r0                       # +384
```

Factors, dtypes, metadata, and extensions in R (condensed):

```r
f <- factor(c("lo", "hi", NA, "lo"), levels = c("lo", "mid", "hi"))
levels(as_polars_series(f)$to_r_vector())                               # "hi" "lo"
levels(as_polars_series(f)$cast(pl$Enum(levels(f)))$to_r_vector())      # "hi" "lo"
as_polars_series(c(1, 3))$cast(pl$Enum(c("a", "b", "c")))               # error: use $cat$to()
as_polars_series(dtaparser::with_labels(c(1, 2), c(yes = 1)))           # error: no method
sch <- nanoarrow_schema_modify(na_struct(list(x = na_double())), list(metadata = list(dta = "schema-level")))
sch$children$x <- nanoarrow_schema_modify(sch$children$x, list(metadata = list(label = "X label")))
st <- basic_array_stream(list(as_nanoarrow_array(data.frame(x = c(1, 2)), schema = sch)), schema = sch)
as_nanoarrow_array_stream(as_polars_df(st))$get_schema()$children$x$metadata   # list()
ext <- nanoarrow_schema_modify(na_double(), list(name = "x", metadata = list(
  "ARROW:extension:name" = "dta.test", "ARROW:extension:metadata" = "{\"k\":1}")))
arr <- nanoarrow_array_set_schema(as_nanoarrow_array(c(1, 2)), ext, validate = FALSE)
as_polars_series(basic_array_stream(list(arr), schema = ext, validate = FALSE))  # error
pl$read_parquet("written_by_python_with_extension.parquet")             # Rust panic
d <- data.frame(x = haven::labelled(c(1, 2), c(yes = 1, no = 2)))
arrow::write_parquet(d, f2 <- tempfile()); pl$read_parquet(f2)          # Rust panic
```

Python (condensed):

```python
import struct, nanoarrow as na, polars as pl
def tagged(c): return struct.unpack("<d", struct.pack("<Q", 0x7FF00000000007A2 | (ord(c) << 32)))[0]
df = pl.DataFrame({"id": [1, 2, 3, 4, 5], "x": [1.5, tagged("a"), None, tagged("z"), float("nan")]})
df.group_by("x", maintain_order=True).agg(pl.len())   # one NaN group, key = tag a
df["x"] == tagged("a")                                # True for a, z and NaN
df.join(df.select("x", y=pl.col("id")), on="x")       # NaN rows match each other
child = na.Schema(na.float64(), name="x", metadata={"label": "X label"})
sch = na.Schema(na.Type.STRUCT, fields=[child], metadata={"dta": "schema-level"})
arr = na.c_array_from_buffers(sch, 2, [None], children=[
    na.c_array_from_buffers(child, 2, [None, na.c_buffer([1.0, 2.0], na.float64())])])
na.ArrayStream(pl.DataFrame(na.ArrayStream(arr))).schema   # no metadata left
s = pl.Series("x", [1.0, tagged("a"), None]).ext.to(pl.Extension("dta.test", pl.Float64, '{"k":1}'))
s + 1                                                 # NotImplementedError
pl.DataFrame({"x": s}).write_parquet("e.parquet"); pl.read_parquet("e.parquet").schema  # Extension kept
pl.Series([0, 2], dtype=pl.UInt32).cast(pl.Enum(["lo", "mid", "hi"]))  # ComputeError
pl.Series([1.0, 2.0]).is_in([1, 2])                   # InvalidOperationError
```

## Sources and licenses

Our package is GPL-3.0-only. Nothing here is incompatible; nothing was
copied.

| source | version | license |
|---|---|---|
| [pola-rs/polars](https://github.com/pola-rs/polars) (Python polars, Rust crates, user guide, migration guide) | py-2.1.0 (`7f902bd`) | MIT |
| [polars on PyPI](https://pypi.org/project/polars/) | 2.0.0, 2.1.0 | MIT |
| [polars on crates.io](https://crates.io/crates/polars) | 0.55.2 | MIT |
| [pola-rs/r-polars](https://github.com/pola-rs/r-polars) (source, NEWS, install vignette) | v2.1.0 (`8af96e2`) | MIT |
| [R-multiverse: polars](https://community.r-multiverse.org/polars) | 2.1.0 | (repository) |
| [CRAN: polars](https://CRAN.R-project.org/package=polars) | archived 0.7.0 | |
| [docs.pola.rs](https://docs.pola.rs/) | stable, read 2026-11-09 | MIT (repository) |
| [pola-rs.github.io/r-polars](https://pola-rs.github.io/r-polars/) | 2.1.0 | MIT |
| nanoarrow (R, CRAN tarball; Python, PyPI) | 0.9.0 | Apache-2.0 |
| [Arrow C data interface](https://arrow.apache.org/docs/format/CDataInterface.html), [C stream interface](https://arrow.apache.org/docs/format/CStreamInterface.html), [Columnar format](https://arrow.apache.org/docs/format/Columnar.html) | read 2026-11-09 | Apache-2.0 |
| haven (probes only) | 2.5.5 | MIT |
| arrow (R, probes only) | 26.0.0 | Apache-2.0 |
| dplyr, vctrs, bench (R, probes only) | 1.2.1, 0.7.3, 1.1.4 | MIT |
| pandas, numpy (Python, probes only) | 3.1.1, 2.5.4 | BSD-3-Clause |
