# Gate 1, round 1: plan 0023 revision 1

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Both returned **CHANGES**.

## Findings and what revision 2 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 2 |
|---|---|---|
| S1, T(writers) | Python's set naming, where letter labels come from, the marker's set, renumbered codes, `Categorical`, `missing_letters=False` | letter labels from the set `meta` names, read before the replacement; the marker names the set written; codes renumbered 1 to k, `Categorical` back as `Enum`, `missing_letters=False` writes `.` and the marker; each tested |
| S2, T4 | a file with both markers | read as unmarked, named in the categorical warning; tested |
| S3, T3 | the stale wording mentions letters; labels on `.`; duplicate letter-label texts | the categorical warning has its own words and R class `dtaparser_stale_categorical`; a label on `.` fails; letter labels may repeat any text; a labelled unused letter passes; tested |
| S4, T2 | Python's restore: where, `factors`, `letters=None`, dates, digests, windows | in `_frame.finish` before `to_factors` and letter placement, unconditional, on the rows read; `letters=None` drops letters as for every column; a `%t` format fails the check; digests after |
| T1 (blocker) | R's and Python's `factors=TRUE` passes would turn a valid lettered or stale column into a factor | a valid categorical with letters is skipped by R's pass; a stale column is read as unmarked, `factors` included, as plan 0020 reads a stale factor; tested both ways |
| S5 | every writer must drop both markers, for every column | listed: R, pandas, TypeScript and Python's Rust loop |
| S6 | TypeScript `check` and restore reject letters and letter labels, build levels from all labels, set `missing` to 1, drop the set | each named |
| S7 | Python restoring `dtaparser_factor` changes a default nobody asked to change | cut |
| S8 | R and pandas types depend on the window | stated as accepted; windowed tests |
| S9, T5 | missing tests: windows, label on `.`, unused labelled letter, both markers, renumbering, `missing_letters`, TypeScript codes 10/20/30, comparing set names; Python to TypeScript and back | all added; markers compared by kind and order word; a cross-language script reads each writer's file in the other reader |
| T2 | pandas date conversion after a failed marker | the marker check comes first, as now; a marked `%t` column fails |
