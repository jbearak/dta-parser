# Gate 1, round 5: review of plan 0019 revision 5

Judges as before, each in a fresh session. Both returned **CHANGES**,
with every library "yes" from both.

## Verdicts per library

| language | compared with | Sonnet | Terra |
|---|---|---|---|
| Python | polars | yes for profiled files | yes for profiled files, after T1, T2 |
| Python | pyarrow | yes | yes, after T1, T2 |
| Python | pandas | yes | yes, after T1, T2 |
| Julia | Parquet2.jl | yes | yes |
| Julia | DuckDB.jl | yes | yes |
| TypeScript | keep Parquet in the npm package | agree | agree |

## Findings and what revision 6 did

| id | finding | answer in revision 6 |
|---|---|---|
| S1, T2 | The Arrow section still said the decoder computes the digest, against the post-`factors` pass | The decoder does no hashing; the digest is a native pass over finished columns with letters |
| T1 | `%tc` fractions of a millisecond and out-of-range values unspecified in `read_dta` | An error naming the column and row, unless `timestamps="truncate"`; the cell-by-cell test's exception stated |
| T3 | Float64 to Float32 fails only when it rounds a value | Reworded; both cases tested |
| S2 | A nanosecond count overflows an i64 outside 1678 to 2262 | Hashed as a 128-bit integer |
| S3 | Datetime("ns") with letters unspecified | An error naming the column and row unless `timestamps="truncate"` (new on `save_parquet`) |
| S4 | Julia reads a date column with letters as a `DtaColumn` of days, unlike Python | Stated in the Julia section and the shared type table |
| S5 | Julia has no `int64` option | Reworded |
| S6 | A `LETTERS` column no pair names is saved silently | Written as a categorical with a warning naming it |
| S7 | `save_dta` without `missing_letters`; exports table incomplete | `missing_letters` added; `ParquetInfo` and `FixedWidthWarning` listed |
