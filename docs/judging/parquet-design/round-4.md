# Gate 1, round 4: design review of plan 0018 (revision 4)

Same judges, fresh sessions. Sonnet returned CHANGES with every library
a yes (one should, five nits); Terra returned CHANGES on one should,
with R, Julia and TypeScript a yes.

| language | library | Sonnet | Terra |
|---|---|---|---|
| R | arrow | yes | yes |
| R | nanoparquet | yes | yes |
| Python | pyarrow | yes | no (G1: decimal rows read as contradictory) |
| Python | pandas | yes | no (same) |
| Python | polars | yes | no (same) |
| Julia | Parquet2.jl | yes | yes |
| TypeScript | hyparquet (+ writer) | yes | yes |
| TypeScript | parquet-wasm | yes | yes |

Sonnet accepted Terra's stricter install rule.

## Findings and what revision 5 did

| id | finding | answer in revision 5 |
|---|---|---|
| Terra G1 | Python DECIMAL rows contradict each other | Worded as meant: float64 up to 15 digits, `Decimal` objects above, with no option |
| Sonnet G1 | Levels from `ARROW:schema`: PLAIN pages, which row groups, non-string values | Levels are the distinct non-null values of the rows read, from dictionary and PLAIN pages alike; two windows can differ, and the docs say so; only dictionaries of strings become categoricals, others read as their value type |
| Sonnet G2 | ADR states the size claim unconditionally | Cut from the ADR until PR 7 measures it |
| Sonnet G3 | Index restore under-specified | Took the smaller design: a stored pandas index reads as an ordinary column; the docs show `set_index()` |
| Sonnet G4 | `datetime64[D]` still listed | Removed |
| Sonnet G5 | Unsigned 8/16 with nulls in Python | float32, as signed |
| Sonnet G6 | An all-null row group has no min or max | Counts as in range |
| Sonnet (PR 3) | `ARROW:schema` dictionaries before PR 4 | Read as their value type until PR 4 |
| Sonnet (install) | Say how task 1 is scored | On the install documentation's four scores, like every task |
