# Gate 1, round 7: plan 0021 revision 7

**Sonnet: APPROVE**, three nits. **Terra: CHANGES**, one finding.

## Findings and what revision 8 did

| id | finding | answer in revision 8 |
|---|---|---|
| T1 | a marked set can pass plan 0020's checks with a fractional code, or a label on `.r` no row holds; restoring then saving loses it | two more checks for restoring: every code in the set a whole number within long's range, and no label on `.` to `.z`; failing either gives labelled numbers with the set and marker as read, and the warning; both tested through `saveDta(readDta(f))` |
| S-N1 | a failed marker stays in `characteristics` and `saveDta` drops it | stated; asserted in the test |
| S-N2 | `onWarning` missing from `readDataset`'s options | added |
| S-N3 | keep replacing the fixed-width estimate with the measurement | kept as written |
