# Gate 1, round 2: design review of plan 0018 (revision 2)

Same judges, fresh sessions, given the plan, `round-1.md` and the
research notes. Both returned **CHANGES**.

## Verdicts per library

| language | library | Sonnet | Terra |
|---|---|---|---|
| R | arrow | yes | no (nested data; docs unproven) |
| R | nanoparquet | yes | no (docs unproven) |
| Python | pyarrow | no (metadata keys; install) | no (nested; native results not gated) |
| Python | pandas | no (wrong claim about attrs; install) | no (docs unproven) |
| Python | polars | no (metadata keys; install) | no (nested; native results not gated) |
| Julia | Parquet2.jl | no (metadata keys; install) | no (nested; docs unproven) |
| TypeScript | hyparquet (+ writer) | no (column types; INT64 fallback; write default) | no (docs unproven) |
| TypeScript | parquet-wasm | no (same) | no (docs unproven) |

Still open from round 1: Terra kept T-D6, T-D7, S-D5 and S-D15 open
(nested data; native results). Sonnet kept S-D2 (npm zstd), S-D6
(install), S-D8 (INT64 fallback), S-D10 (categorical order, R contract)
and S-D16 (ADR missing) open.

## Findings and what revision 3 did

| id | finding | answer in revision 3 |
|---|---|---|
| Terra E2, T-D6, S-D15 | Skipping nested columns returns an incomplete table; a warning can be missed | Reading a file with nested columns is an error unless the selection leaves them out or `nested = "skip"` is passed. Scope stated as flat tables in the goal and in the first paragraph of `docs/parquet.md` |
| Terra E3, T-D7 | Native Arrow and polars results not gated | Declined, with the reason now in the plan ("What comparable means"): a comparable reader produces the same kind of result, and we produce none of those. Sonnet judged the decline reasonable. Published alongside; the Python docs point users who want those tables to polars or pyarrow |
| Terra E1, E4 | A window can span pages; the index's benefit overstated | Reworded: the index lets a reader go straight to the pages that hold a window; PR 2 measures it against the header walk |
| Sonnet E1 | TypeScript column types contradict `NumberColumn` | Every number reads as `NumberColumn` (`Float64Array`), as for `.dta`; the memory cost and why it stays are stated |
| Sonnet E2 | `int64: "auto"` without statistics | Falls back to `BigIntColumn`, with the reason on the variable |
| Sonnet E3 | npm zstd default is slow | The npm package writes snappy by default |
| Sonnet E4 | pandas keeps `attrs` | Corrected, with the real limits of that route |
| Sonnet E5 | Metadata keys unspecified outside R | Keys listed for Python `read_meta`, Julia `read_meta` and TypeScript `info`, reusing `nobs`/`nrows` |
| Sonnet E6 | Categorical order not guaranteed | Categoricals are always dictionary-encoded with every level, in order, in every row group |
| Sonnet E7 | Install can't match registries | The user is asked before Gate 2; an unpublished language's task 1 is scored and reported but leaves pass rule 1 |
| Sonnet E8 | Which `read_dta` | `dtaparser::read_dta`; dtatools' dibbles are not a target |
| Sonnet E9 | Julia `timestamps = :error` friction | Examples for other tools' files show `:truncate`; the error names it |
| Sonnet E10 | ADR missing | `docs/adr/0033-parquet-with-a-dta-profile.md` |
| Sonnet E11 | pandas nulls footnote; Python date rule; `datetime64[D]` | Footnote added; rule stated (as `write_dta`'s); `[D]` removed |
| Sonnet E12 | Scope | Hadoop LZ4, FLOAT16 and CRC moved to "later". `TableReader`, the page cache and `openParquetAsync` stay: table-viewer, which the user asked for, needs the first two, and Terra asked for the third (T-D9). `AsyncTableReader` is now defined |
| Sonnet E13 | arrow-rs claims unmeasured | Measured (44 crates and 13 s without its Arrow layer, 64 and 25 s with it; 54 MB vendored against 16 MB) and recorded; the build-time argument dropped, and the reasons given are dictionary codes, size and control |
