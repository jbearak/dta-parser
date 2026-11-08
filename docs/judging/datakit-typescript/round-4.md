# Gate 1, round 4: plan 0021 revision 4

**Sonnet: APPROVE**, two nits. **Terra: CHANGES**, two findings, both
on factors.

## Findings and what revision 5 did

| id | finding | answer in revision 5 |
|---|---|---|
| S-N1, T2 | the label set behind a restored factor stays in `valueLabels`, so `saveDta` would rename or overwrite; an unused set with the generated name can be overwritten | a restored factor's set leaves `valueLabels` unless another column read uses it; `saveDta` reserves every existing set name, used or not; tests for both |
| T1 | factor restoration only in `./node`'s `readDta`, not the browser path | restoration is in `readDataset` for `.dta` readers, so both paths match; warnings go to `onWarning`, else `process.emitWarning`, else `console.warn`; the browser `.dta` to Parquet path tested |
| S-N2 | where the fixed-width temporary file goes | `fs.mkdtempSync` under `os.tmpdir()` (0700), the file created exclusively (0600) |
