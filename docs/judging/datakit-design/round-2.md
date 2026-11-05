# Gate 1, round 2: review of plan 0019 revision 2

Judges as in round 1, each in a fresh session given revision 2, ADR
0034, round 1's record and the spike's note
(`docs/research/parquet-polars-spike.md`). Both returned **CHANGES**.

## Verdicts per library

| language | compared with | Sonnet | Terra |
|---|---|---|---|
| Python | polars | yes for profiled files, with "use polars directly"; after S4, S5 | no, until companion columns are fixed |
| Python | pyarrow | yes | no, same, and factor saves |
| Python | pandas | yes | no, same |
| Julia | Parquet2.jl | yes, after S6 | yes, for profiled files |
| Julia | DuckDB.jl | yes, after S6 | yes, for profiled files |
| TypeScript | keep Parquet in the npm package | agree | yes |

## Findings and what revision 3 did

| id | finding | answer in revision 3 |
|---|---|---|
| T1, S4 | Companion columns are not total: `letters="columns"` and `columns=None` pair only columns with letters, so generated `pl.col("x_letter")` fails on a window without them | `letters="columns"` and `letters_to_columns(columns=None)` give every eligible column a companion (cost stated); `letters=[...]` names columns; `letters=None` keeps none; a test runs one generated expression on windows with and without letters |
| T2 | A `select` that drops `x_letter` but keeps `x` loses letters silently | An error naming both, unless the pair is removed or `missing_letters=False` |
| T3, S5 | `factors=True` loses codes and merged texts; letters on an Enum; `save_dta` rejected Enum | Losses stated beside the argument; `save_parquet` refuses an Enum with letters (the message gives the ways out); `save_dta` writes an Enum as `encode` would (codes 1 to k, labelled), as R's `save_dta` writes factors, letters kept; round-trip tests treat it as an exception, with a duplicate-label case |
| T4, S7 | ADR said `vcat` keeps codes; companions follow "every" polars operation | ADR corrected: indexing, `filter`, `sort`, `subset` keep codes, `vcat`, `combine` and functions do not; companions follow row-preserving operations |
| T5 | The Arrow path's description still had a code byte per row | Rewritten around bitmaps, sparse letters and a digest computed while decoding, views built on worker threads |
| S1 | The core changes affect R, Julia and npm, which the plan called unchanged | The Arrow outputs are new beside the old ones; shared decoding changes run under a no-regression gate (plan 0018's R, Julia and npm benchmarks and tests) |
| S2 | Enum import and the write path unspiked; Enum needs polars' private key or a cast | Stated; PR 2a measures both Enum routes and records the one used (with a loud test and the `<3` pin if it is the key), and builds and benchmarks the write path |
| S3 | "Meets targets 1 and 2" too strong; quiet rerun needed; thread count must serve targets 1 and 3 together; the risk sits at the end of one big PR | "Not shown to miss"; step 0 is the quiet, per-family rerun; step 3 picks threads for both targets; PR 2 split into 2a (Arrow path and gate, stop and ask) and 2b (package, move, docs) |
| S6 | `transform!` under the same name keeps `:note` metadata (DataFrames 1.8.2), only a new name drops it | Corrected; codes still lost; DataFrames compat floor found in PR 3 |
| S8 | Digest storage and semantics; "sorted by" undefined | `Meta._digests`, ignored by `==`, carried by `copy`, `rename`, `select`; values hashed as doubles so lossless casts pass; sorted means Stata's order, and polars' default sort fails it, with the recipe that passes |
| S9 | The blind spot is any reordering among equal values | Stated |
| S10, T6 | `polars>=2.0,<3`; `letters` missing from the methods list; `letters=None`; `save_dta` of microsecond datetimes | All four done (`timestamps="truncate"` on `save_dta`) |
