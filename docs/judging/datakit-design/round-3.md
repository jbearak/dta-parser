# Gate 1, round 3: review of plan 0019 revision 3

Judges as before, each in a fresh session. Both returned **CHANGES**.

## Verdicts per library

| language | compared with | Sonnet | Terra |
|---|---|---|---|
| Python | polars | yes for profiled files, after S2, S3 | no, until T1 to T3 |
| Python | pyarrow | yes, same | no, same |
| Python | pandas | yes | no, same |
| Julia | Parquet2.jl | yes, after S1 | yes, for profiled files |
| Julia | DuckDB.jl | yes, after S1 | yes, for profiled files |
| TypeScript | keep Parquet in the npm package | agree | yes |

## Findings and what revision 4 did

| id | finding | answer in revision 4 |
|---|---|---|
| S1 | The Julia recipe passes `stata_key(".d")`, a Float64, where `set_stata_code!` takes an integer code | `set_stata_code!(df.x, i, 5)`, with the codes explained in a comment |
| T1, S2 | Enum columns from `factors=True` are not eligible for companions, though the plan keeps their letters; the digest is undefined for an Enum | Eligibility decided by the file's type before `factors`; a labelled column made an Enum stays eligible; `save_parquet` still refuses an Enum with letters, `save_dta` keeps them; the digest is taken after `factors` and hashes Enum values as text; tested in both letter modes through `save_dta` |
| T2 | Hashing values as doubles misses changes beyond 2^53 | The digest hashes integers and whole-number floats as exact integers, other floats as bits, dates and datetimes as counts, text as bytes; Int64 2^53 + 1 to Float64 fails it, tested; the ADR states what the check cannot see |
| T3 | `letters=["x"]` does not say where other columns' letters go | They stay in `meta.missing`; tested |
| S3 | `meta.letters(x)` says "no letters" for a column whose letters are in a companion | It raises a `ValueError` naming the companion; tested |
| S4 | The `.dta` path to polars has no PR step; `save_dta` through `write_dta` would need pandas | PR 2a step 6: an Arrow output for the `.dta` reader and an Arrow input for its writer; `save_dta` calls the native writer; cell-by-cell tests against `dta_parser.read_dta`; published, not gated |
| S5 | `letters_to_columns` changes `meta` but returns only `df` | Stated, in the docstring too |
| S6 | A file column already named `x_letter`; stale pairs; the type of a date with letters; which Categorical levels | `letter_suffix` on every read, with an error naming the clash; a stale pair is an error; dates and timestamps with letters are DOUBLE with `"logical"`; an Enum writes its dtype's levels, a Categorical the categories its values use |
| S7 | Nothing warns in Julia when a function drops letters | The Julia README's first example shows it |
| S8 | PR 3 in parallel with 2a, which changes shared code | PR 3 rebases on 2a and runs its benchmarks and no-regression check after |
