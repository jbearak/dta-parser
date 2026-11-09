# Gate 1, round 3: plan 0023 revision 3

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Sonnet returned **APPROVE** (four nits); Terra returned
**CHANGES**, noting every earlier finding answered.

## Findings and what revision 4 did

| id | finding | answer in revision 4 |
|---|---|---|
| T1, S3 (nit) | TypeScript's order word "`categorical.ordered`, else `ordered`" is unclear and differs from the code | `v.categorical?.ordered ?? v.ordered ?? false`, as now; an unspecified order tested |
| T2 | `categorical.codes` in any order reverses the levels on a round trip, since readers order levels by code | codes must increase with the levels; a repeated or out-of-order code is an error; tested |
| S1 (nit) | R's `factors = TRUE` pass skips only factors | the restore records the columns it left as numbers for their letters, and the pass skips those |
| S2 (nit) | with date conversion off, a date format is not converted | stated; the format tests read with conversion on |
| S4 (nit) | readers must collect both markers per variable | stated |
