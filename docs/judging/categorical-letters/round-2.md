# Gate 1, round 2: plan 0022 revision 2

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Both returned **CHANGES**.

## Findings and what revision 3 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 3 |
|---|---|---|
| T1 (blocker) | R `read_parquet(factors = TRUE)` would turn the labelled double into a factor and lose the letters | the column stays a labelled double whatever `factors` says; the C read says which columns are such and the `factors` loop passes over them; tested with both settings |
| T2 (blocker) | the set name is not stable across a Python write and reread: the writer drops the column's set reference and keeps the set, so a reread picks `name_3` | the writer records the set on the column's profile entry (`value_labels`): the caller's set if it fits, else the first of `name`, `name_2`, ... that fits or is free; readers use it; writing back names the same set; tested over two Python rounds with a collision |
| T3 | selected-column and lazy profile reads skip sets, so a reader's collision check can miss names | the parser records every set name it passes over; `value_label_set_names` returns all in every mode; one core function, `Reader::categorical_labels`, reads or makes the set; tested with an unselected column owning the name |
| S1 | the levels-on-non-text warning loop would also warn about a valid DOUBLE categorical | the loop skips it; a clean file gives no warning, each damaged entry exactly one; tested |
| S2 | `profile_for` keeps a supplied `logical` on any Double column, so a stale `logical` categorical could reach a plain double | `logical` and `categorical` come from the values; a supplied entry keeps only `logical` date or timestamp on a Double column; a stale `categorical` is dropped too; tested |
| S3 | the TypeScript `DictionaryColumn` paths fold `missing` 2 to 27 into `.` (`save-dta.ts`, the copy and the refusal in `parquet.ts`, the TSDoc in `js/src/index.ts`) | each named; `writeParquet` and `saveDta` tests take a `DictionaryColumn` input as well as codes with `Missing` levels |
| S4 (nit) | installing npm 1.1.0 in the test needs the network | a devDependency alias in `js/datakit`, in the lockfile, installed by `npm ci` |
| (own) | the recorded set also carries labels on letters | stated and tested |
