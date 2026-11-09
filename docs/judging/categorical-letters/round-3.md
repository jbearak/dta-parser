# Gate 1, round 3: plan 0022 revision 3

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Sonnet returned **APPROVE** (three nits); Terra returned
**CHANGES**.

## Findings and what revision 4 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 4 |
|---|---|---|
| T1 (blocker) | columns that make their sets one at a time can make the same name for different sets (`x` makes `x_2` while categorical `x_2` makes `x_2` too) | a made name skips names of other columns; since a made name is the column's own name or `column_k`, no two columns can make the same one, even when each is made without seeing the other (a reader of some columns); the argument is in the plan; tested whole, column by column and through a Python write-back |
| T2 | `cellOf` gives `MISSING["."]` for every missing dictionary value, so `readRows` would lose letters | named: it uses `missingValue` of the code; `readRows` tested for `.a` and `.z` |
| T3 | a malformed `categorical` warns in the parser and then again when `logical` finds no levels | the parser drops `logical` categorical with a malformed `categorical`, without a second warning; dropping `logical` drops levels that would only warn again (except on text); absent and malformed tested at one warning each |
| S1 (nit) | `FillCodes` maps negatives below -27 to `.` while numeric codes past `.z` are errors | stated as deliberate: every negative was a null before |
| S2 (nit) | Python cannot give letters to an `Enum` without a set, so step 2 runs for Python only when its set does not fit | stated in the writing table |
| S3 (nit) | the other-tools read-backs could be trimmed | kept: they are existing scripts that gain a column |
