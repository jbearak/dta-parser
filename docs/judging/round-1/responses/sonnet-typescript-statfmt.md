```json
{"A": {"1": [3,3,2,3], "2": [3,3,3,3], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,3,3,3], "7": [3,3,3,3], "8": [3,2,3,3], "9": [3,3,3,3], "10": [3,3,3,3]},
 "B": {"1": [3,3,2,3], "2": [2,3,1,2], "3": [1,1,1,1], "4": [2,3,1,2], "5": [1,3,2,2], "6": [2,3,1,2], "7": [0,0,0,0], "8": [2,3,1,2], "9": [2,3,2,2], "10": [1,1,1,1]}}
```

## Reasons for every score below 3

### Library A

- Task 1, Completeness 2: It gives the build-from-checkout steps and Node 20+, but no list of supported operating systems and no advice for when the Rust or WASM build fails.
- Task 8, Correctness 2: The README feature table says the TypeScript writer does not write the timestamp ("read, not written"). The writer docs, however, list a `timestamp` field on the dataset. It is a small inconsistency, and the write example itself runs.

### Library B

- Task 1, Completeness 2: It gives the install command, ESM-only and Node 18+. It does not say what to do when installation fails.
- Task 2, Findability 2: The reading example is for `readSav`. `readDta` appears only in an import and in the options line.
- Task 2, Completeness 1: It names `Dataset`, `rows` and `toObjects()`. It does not say what each Stata storage type becomes. The reader has to infer that all numbers are JS numbers, and cannot tell how int8, int16, int32 and float differ.
- Task 2, Clarity 2: The example uses an SPSS file, and the types are visible only in the `.d.ts` files.
- Task 3, all 1: There is no column-selection feature in the docs. The only hint is `SKIP_VARIABLE` in an enum, so the task is effectively not covered. Order and error behaviour are undocumented.
- Task 4, Findability 2: `rowLimit` and `rowOffset` appear in one example line under Reading.
- Task 4, Completeness 1: It gives no semantics for the options, and nothing on what an out-of-range offset does.
- Task 4, Clarity 2: The example gives no result and does not say whether it is zero-based.
- Task 5, Findability 1: The README shows only `metadata.rowCount` and `variables[0].name`. The other fields (`fileLabel`, `format`, `label`, `type`) are only in the `.d.ts` files.
- Task 5, Completeness 2: The `.d.ts` files list the data label, variable label, format and type. Nothing documents reading metadata without the data, apart from the low-level streaming handlers in an SPSS example.
- Task 5, Clarity 2: The fields are named without any explanation, and the `ReadStatType` enum is unexplained.
- Task 6, Findability 2: There is one comment line (`valueLabels; // [{ value: 1, label: "Male" }, ...]`) in the SPSS example.
- Task 6, Completeness 1: It shows the pair-array shape only. It has nothing on looking up a code's text, on labels for missing values, or on turning a column into a categorical.
- Task 6, Clarity 2: The shape is shown, but no worked lookup.
- Task 7, all 0: Dates are not mentioned at all.
- Task 8, Findability 2: The write example is for `writeSav`. The Stata case is a single sentence, including `version: 117`.
- Task 8, Completeness 1: It says default release 118 and that `version` can be changed. It does not say how `ReadStatType` maps to Stata storage types, what `INT32` becomes, or which inputs are errors (only an error-code enum).
- Task 8, Clarity 2: The example is for SPSS and the Stata mapping is left to the reader.
- Task 9, Findability 2: The labels appear in the SPSS write example (`fileLabel`, `valueLabelSets`, `label`, `valueLabels: "sex"`), not in a Stata-specific place.
- Task 9, Completeness 2: It covers the variable label, data label and value label set. It has no read-back check and does not explain `tag` or labels for missing values.
- Task 9, Clarity 2: The example is clear but is for SPSS and has no output.
- Task 10, all 1: The README has nothing on `.a` to `.z`. Only the low-level types (`isTaggedMissing`, `tag`, `insertTaggedMissingValue`) hint at tagged values. The high-level `CellValue` is `number | string | null`, with `null` for missing. Nothing covers keeping them through filtering, sorting or writing.

## Task scores (mean of the four)

| task | A | B |
|---|---|---|
| 1 (common) | 2.75 | 2.75 |
| 2 (common) | 3.00 | 2.00 |
| 3 | 3.00 | 1.00 |
| 4 (common) | 3.00 | 2.00 |
| 5 (common) | 3.00 | 2.00 |
| 6 (common) | 3.00 | 2.00 |
| 7 | 3.00 | 0.00 |
| 8 (common) | 2.75 | 2.00 |
| 9 (common) | 3.00 | 2.25 |
| 10 | 3.00 | 1.00 |

## Common totals (tasks 1, 2, 4, 5, 6, 8, 9)

- Library A: 20.50
- Library B: 15.00
