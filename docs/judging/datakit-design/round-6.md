# Gate 1, round 6: review of plan 0019 revision 6

Judges as before, each in a fresh session. **Sonnet: APPROVE**, with
nits. **Terra: CHANGES**, two findings. Every library "yes" from both.

## Verdicts per library

| language | compared with | Sonnet | Terra |
|---|---|---|---|
| Python | polars | yes, for profiled files | yes, for profiled files |
| Python | pyarrow | yes | yes |
| Python | pandas | yes | yes |
| Julia | Parquet2.jl | yes | yes |
| Julia | DuckDB.jl | yes | yes |
| TypeScript | keep Parquet in the npm package | agree | agree |

## Findings and what revision 7 did

| id | finding | answer in revision 7 |
|---|---|---|
| T1 | `timestamps="truncate"` cannot bring an out-of-range `%tc` value into range | An error in both modes; both tested at each edge |
| T2 | Requiring a double of seconds to be a whole number of microseconds rejects 0.1 s | Read as the nearest whole microsecond when it converts back to the same double, the writers' rule; tests of one that does and one that does not |
| S1 (nit) | Float16, Int128, UInt128 and other dtypes missing from the write errors | "Any other dtype" is an error, these named |
| S2 (nit) | FLOAT16 could be read, polars holds it; `nested="skip"` unmentioned | Stated as a core limit for later; the nested row names `nested="skip"` |
| S3 (nit) | Name the fix for dictionary text (no intermediate `u32` pass) | Step 1 names it |
| S4 (nit) | The DHS open and setup cost is about 10 ms, not 5 to 6 | Corrected |
| S5 (nit) | `read_dta` gives Datetime("ms"), `read_parquet` Datetime("us") | Stated, with the cast, beside the type rows |
| S6 (nit) | Tests for several stated errors and warnings missing | Added |
| S7 (nit) | Info's `meta` equals only a default whole-file read's | Reworded |
