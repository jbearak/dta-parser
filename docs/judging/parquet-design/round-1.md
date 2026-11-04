# Gate 1, round 1: design review of plan 0018 (revision 1)

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`), each in a fresh session with the plan, the three
research notes and the existing docs. Both returned **CHANGES**.

## Verdicts per library

| language | library | Sonnet | Terra |
|---|---|---|---|
| R | arrow | no (yes after zstd, INT64, letters, docs) | no |
| R | nanoparquet | no (same) | no |
| R | duckdb | yes | — |
| Python | pyarrow | no | no |
| Python | pandas | no | — |
| Python | polars | no | no |
| Python | fastparquet, duckdb | yes | — |
| Julia | Parquet2.jl | no | no |
| Julia | DuckDB.jl, Arrow.jl | yes | — |
| TypeScript | hyparquet (+ writer) | no | no |
| TypeScript | parquet-wasm | yes | no |

## Findings and what revision 2 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 2 |
|---|---|---|
| S-D1, T-D9 | No documentation plan; examples and loss tables missing | New "Documentation" section: shared `docs/parquet.md`, one heading per task in each language page with runnable examples tested in CI, migration tables per other library, error catalogue |
| S-D2, T-D8 | No zstd output, no level | zstd level 3 by default through C libzstd on native targets; `ruzstd` in wasm; `compression_level`; `lz4_raw` added |
| S-D3 | Codec numbers unrecorded; pure-Rust decoders may be slow | Measured on DHS data and recorded in `docs/research/parquet-codecs.md`; native reads use libzstd |
| S-D4, T-D3 | Naive vs zoned timestamps; units; nanoseconds | Naive times write `isAdjustedToUTC=false`; the frame's unit is kept (`[s]` via the profile); NANOS written; loss policies per language |
| S-D5, T-D7 | CPU rule ambiguous; no tolerance; inputs; geometric means hide misses; native results | Explicit rule `CPU ≤ theirs × max(1.15, s)`; 5% noise tolerance; per-file 1.25× cap; three inputs (pyarrow, polars, ours); other tools on our files; native types published; a miss blocks the PR |
| S-D6 | Install unspecified | "Install" section: unchanged routes; publishing is the user's decision; offline vendored builds tested in CI |
| S-D7 | arrow-rs `parquet` crate not considered | "Considered" section: memory (double copy), size, control; risk answered by the compat suite |
| S-D8, T-D3 | INT64 errors block reads; TypeScript column type varies | R `int64 = "double" / "integer64" / "character"`, exactness check; TypeScript decides per column at open from statistics, `int64` option |
| S-D9, T-D2 | Letter column: opt-out, reader rules, projections, stale profiles | `missing_letters` option; letter column read with its data column, validated (type, values, null alignment), one warning on any failure; info lists roles; docs say only our writers guarantee the match |
| S-D10 | Categoricals outside R; Julia zones; Python ints; round-trip tests per language | Categorical row for every language; Julia extensions with one warning; Python ints as `read_dta`; round-trip test stated per language |
| S-D11, T-D6 | Row groups too large; memory by bytes; no offset index | 64 MiB, at most 262,144 rows, at least 1; header walk when no offset index; DuckDB and polars measured on our files |
| S-D12, T-D1 | Pass rule lets a task lose; three-round cap; pandas missing; blinding | Per-task rule (ours ≥ theirs on every task they support, higher total, every task ≥ 2); rounds until pass; pandas added; blinding limit stated |
| S-D13 | Inputs other than paths | R raw vectors; Python bytes, file objects and `write_parquet(path=None)`; Julia `IO` and bytes |
| T-D4 | Profile limits, integer codes, duplicates | Codes finite and within ±2^53; 64 MiB cap; duplicate keys and codes; drop-entry-with-warning rules; tests |
| T-D5 | Interop metadata | `ARROW:schema` written (categoricals, zones); "What other tools see" table checked by the compat suite; `pandas` key left out, with the reason |
| T-D10 | Vertical slice first | Delivery reordered: core slice, then R end to end with benchmarks, then the core's breadth, then the other languages |
| S-D14 | Statistics details, long strings, dictionary probe, footer limits | Float rules; text statistics only up to 64 bytes; dictionary checked on the first page; a 5,000-column test read by pyarrow |
| S-D15 | Name masking; nested columns; TypeScript dates | Masking in the R docs' first paragraph; nested columns skipped with a warning when reading a whole file; `toDate()` |
| S-D16 | ADR missing; version bump; warnings | ADR 0033 lands with this plan; 3.1.0 for the three R packages |

Declined:

- **T, native Arrow or polars results as gated cases.** They skip the
  conversion to the language's usual table that every gated case pays.
  They are published per case alongside.
- **T, nested columns and predicate pushdown.** Out of scope, as the
  goal is flat survey and analysis tables; the docs say so.
- **S, cutting the offset index.** table-viewer reads windows in sorted
  order, one page per window, which needs it.
