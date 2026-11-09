# Gate 1, round 2: plan 0023 revision 2

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Both returned **CHANGES**, each noting every round 1
finding answered.

## Findings and what revision 3 did

| id | finding | answer in revision 3 |
|---|---|---|
| S1 | "not `%t...`" misses `%d`, which Python reads as a date, and Python's datakit converts before the check | the check is "a format the reader converts" (`%td`, `%d`, `%tc`, ...); in Python's datakit, the frame's column must still be numeric; `%d` tested |
| S2 | where Python's writer gets `ordered` | `meta.columns[x].ordered`, read in `dta.rs` as `write.rs` does; tested |
| S3 (nit) | R and pandas tell a label on `.` from one on a letter only by its tag | stated: the tag tests they have |
| T1 | a marked string column can pass the checks; pandas skips string columns' markers | the variable must be stored as a number; a marked string warns and reads as text, empty window included; tested |
| T2 | TypeScript `saveDta` lets `categorical.codes` repeat a code | an error naming the variable; tested |
| T3 | tests miss non-whole and out-of-range codes | added for each reader |
