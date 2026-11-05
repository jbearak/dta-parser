# Gate 1, round 4: review of plan 0019 revision 4

Judges as before, each in a fresh session. Both returned **CHANGES**;
every library was now "yes" from both, conditional on the findings
below.

## Verdicts per library

| language | compared with | Sonnet | Terra |
|---|---|---|---|
| Python | polars | yes for profiled files, after S1 to S4 | yes for profiled files, after T1 |
| Python | pyarrow | yes, same | yes, after T1 |
| Python | pandas | yes | yes, after T1 |
| Julia | Parquet2.jl | yes | yes |
| Julia | DuckDB.jl | yes | yes |
| TypeScript | keep Parquet in the npm package | agree | yes |

## Findings and what revision 5 did

| id | finding | answer in revision 5 |
|---|---|---|
| T1 | `letters_to_columns` could move stale positional letters into companions after a reorder, bypassing the digest | It makes the same height and digest check first and stops with the same error; tested |
| T2 | "So is an Enum ..." said an Enum with letters is written as DOUBLE | Reworded: it is an error |
| S1 | The digest's timing (decoder vs after `factors`) was contradictory, and hashing every column costs CPU on the target-3 path | Digests only for columns with a `meta.missing` entry, in a native pass over the finished column (after `factors`); none for a read without letters, tested |
| S2 | Float32 to Float64 is lossless but changes the bits | Floats hashed as their value as a double (Float32 widened); Float64 to Float32 fails; whole numbers within ±2^127 as integers |
| S3 | 2a's gate omitted building `Meta`, which on 5,160 columns costs about the whole target-1 allowance | 2a's benchmark builds the whole `Meta` eagerly; the fallback (a lazily built `columns` mapping) is named, and the user is asked with both numbers if it is needed |
| S4 | Python `read_dta`'s dates, encoding and test comparison undefined, and not as dta_parser's | `encoding` and `timestamps` arguments; `%td` Date (fractions an error or truncated), `%tc` Datetime("ms"), `%tC` and other `%t` numbers; letters in dates; the cell-by-cell comparison defined |
| S5 | UInt8 and UInt16 with letters unspecified | Errors |
| S6 | Julia `read_fixed_width`'s return unstated | A DataFrame with `read_parquet`'s metadata keys; tests moved |
| S7 | Decimal read but not saved | Said in the type table row too |
| S8 | ADR's Julia keep-list omitted `groupby` | Added |
