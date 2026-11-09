# Gate 1, round 6: plan 0021 revision 6

**Sonnet: APPROVE**, three nits. **Terra: CHANGES**, two findings.

## Findings and what revision 7 did

| id | finding | answer in revision 7 |
|---|---|---|
| T1 | a marked factor may use codes other than 1 to k; restoring and saving recodes it silently | `categorical.codes` keeps each level's code; `saveDta` writes those codes; tested with codes 10 and 20; through Parquet (no place for codes) a factor comes back as 1 to k, stated |
| T2, S-N2, S-N3 | a set shared by a restored factor and another column, or by two factors, is renamed on save | an existing set (in `valueLabels` or written earlier in the save) with the same name is reused when it maps exactly the same codes to the same texts, and only a different one gets `name_2`; both shared cases tested |
| S-N1 | plan 0020's npm bullet; the four checks only referenced | the plan says it supersedes that bullet and lists the four checks |
