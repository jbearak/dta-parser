# Gate 1, round 1: plan 0025 revision 1

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`, effort high) and GPT-6.1
Sol (`gpt-6.1-sol`, reasoning effort high), each in a fresh session
given `brief.md`. Both returned **CHANGES**. Between rounds the user
also changed the alias: `is_mi` was dropped for `is_na`.

## Findings and what revision 2 did

S = Sonnet, O = Sol.

| id | finding | answer in revision 2 |
|---|---|---|
| S1 (blocker) | `is_missing(Expr)` cannot choose by dtype; `is_nan()` raises on String; a cast turns "nan" into NaN | a Series dispatches on its dtype; an `Expr` is `is_null() \| cast(Float64, strict=False).is_nan().fill_null(False)`, right for numeric, Boolean and temporal columns, with the text caveat stated, documented and tested; the same rule in R (checked in R polars 2.1) |
| S2 (blocker) | `dk.by` cannot know which arguments are Float64 | a letter column for every argument (all null for other dtypes); arguments are names or named `Expr`s; the trade-off is in Considered options |
| S3, O1 (blocker) | joins on `[x, x_letter]` drop every number (null keys) | joins need `nulls_equal=True` (which also matches `.` with `.`); a full recipe; `group_by`/`unique` need no flag; tested on numbers, letters, `.` and a plain NaN; the same for `datakit_by_pl` (R polars 2.1's `$join()` has `nulls_equal`, checked) |
| S4 (blocker), O(stage 2) | pyo3 runs through `python/src/arrow/`; `parquet.rs` helpers and `digest.rs` unmentioned | stage 2 is 2a (pyo3-free in place: an error enum mapped to today's exceptions, sources as path/bytes/`Source`, `import_stream` on a raw pointer, `ReadMeta`/`WriteMeta` structs, `Access`/`select`/`kind_of`/`entries`/`read_error` moved) and 2b (the crate); `digest.rs` and `ABI_VERSION` stay in `python/` |
| S5, O(stage 2) | there are no native tests to move; exception types could change | new: an error-type-and-message test written against today's code; crate round-trip and release-once tests; a DHS benchmark before 2a and after 2b |
| S6 | the R copy needs more than the CI step | `configure`, `build-r-package.sh`, `Cargo.toml`, `Cargo.lock` and the CI step named; no crates.io dependency, so the offline vendored build holds |
| S7, O2 (blocker) | the read callables return too little (letters table, `meta_dict`'s fields); post-casts; dropped arguments; unwind protection; release callbacks in `dtaparser.so` | two stream out-parameters (data and letters) and an R list with `ReadMeta`'s fields; the finish mirrors `_frame.finish` (casts, markers, factors, letters) in R polars; `pl$Decimal` checked; `int64`/`decimal`/`warn_extended_missing` do not apply (stated); `R_UnwindProtect` and `catch_unwind`; the lifetime note |
| O2 (blocker) | writes: letters cross the boundary how? | `save_*` on polars prepares as `_frame.prepare`: untags letters into `write_meta$missing`, restores or widens storage, gives categorical levels, checks sort |
| O3 (blocker) | ownership and cleanup of streams | reads: the table in an external pointer with a finalizer, streams exported last; writes: Rust takes the struct (nulls the source's `release`), releases once on success or failure, a consumed stream is an error; tests for consumption, failures and repeated `gc()` |
| S12, O4 (blocker) | the save signatures break callers; `save_dta` is a re-export with an identity test | `function(data, file, ...)` generics; default methods keep today's formals and order; the polars methods add `meta` and `timestamps` by name; `NAMESPACE` lines; the re-export test becomes a same-file test; dtatools unchanged; tibble saves need neither polars nor nanoarrow |
| S9, O5 | `read_fixed_width_pl` built R vectors through datparser | a native callable, `dtaparser_fixed_width_dta`, writes the temporary `.dta` (Python's route); argument routing specified; release 118's limits stated and tested with a long label |
| S10, O6 | "bit for bit" stream equality cannot be run | a canonical comparison through Arrow IPC files: order, dtypes with units, zones and levels, validity, valid cells with float bits; metadata separately; Parquet and `.dta`, windows, `factors`/`letters`; same polars version on both sides; CI includes the binary matrix |
| S11, O2 | `datakit_meta` lacks storage; value-label form | `storage` (dtype names) added; value labels in dtaparser's form; restore and widen on save tested |
| S8 | ADR numbering: plan 0024 names "ADR 0040" for the pandas ADR; "four references" unverified | plan 0024's line rewritten; the real references listed (`docs/migration.md`, plan 0024); other `0039`s are datparser's and stay; "moves to pandas" sentences annotated |
| S13 (nit) | `is_missing` clashes with rlang; state DtaArray unchanged | the help page notes rlang's `is_na`/`is_missing`; the plan says DtaArray, `read_dta` and the tibble functions are unchanged |
| S14 (nit) | cut the `*_pl` letter helpers; benchmark only if cheap; CI install | kept: setting or testing a letter in R polars needs them (`pl$lit(tagged_na("a"))` makes a null), as Python has them; benchmark cut to one file; CI uses R-multiverse binaries |
