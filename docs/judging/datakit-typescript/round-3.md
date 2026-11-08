# Gate 1, round 3: plan 0021 revision 3

**Sonnet: APPROVE**, no inaccuracies found, two nits. **Terra:
CHANGES**, three findings on conversion edges.

## Findings and what revision 4 did

| id | finding | answer in revision 4 |
|---|---|---|
| S-N1 | say the `.dta` timestamp's type | carried as the file's text, unchanged, and written back as given |
| S-N2 | the fixed-width memory bound is a guess | stated as an estimate; the PR records the measured peak and replaces it |
| T1 | a categorical given a letter keeps it in `saveDta`, but 1.1's Parquet writer turns it into a null silently | a letter in a categorical is an error in `saveDta`, `saveParquet` and `writeParquet`, saying to use labelled numbers; the one change to the moved code; tested |
| T2 | fractional date and timestamp counts (R's DOUBLE Dates) | every finite double converted exactly in bigint arithmetic; a fraction of a day or millisecond is an error, or truncated toward minus infinity with `timestamps: "truncate"` (dates too); infinities and non-letter NaNs errors; range rules; tests in each unit, negative values included |
| T3 | the decimal rule needs precision the dataset lacks | by what the read gave: a `NumberColumn` (precision ≤ 15) is double; text (precision > 15) is an error saying to parse it or keep it as a string; tested |
