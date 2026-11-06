```json
{"A":{"1":[3,3,2,3],"2":[3,3,1,3],"3":[1,1,1,1],"4":[1,3,1,1],"5":[3,2,2,2],"6":[0,0,0,0],"7":[1,3,1,1],"8":[3,3,1,3],"9":[0,0,0,0],"10":[0,0,0,0],"11":[2,3,1,1]},"B":{"1":[2,3,2,3],"2":[2,1,3,3],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,2,3,3],"6":[2,3,1,3],"7":[2,3,3,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,2,3,3]}}
```

Scores are in the order findability (F), correctness (Co), completeness (Cm), and clarity (Cl). A score of 3 has no deduction to explain.

**Library A**

1. **Cm 2:** The install commands, entry points and a Node compatibility remedy are given, but supported JavaScript and TypeScript versions and general installation-failure guidance are not.
2. **Cm 1:** The example reads into an Arrow JS table, but does not map Parquet types or describe losses and refusals.
3. **F 1:** Column selection is in the reader options reference, with no task-specific guide pointer. **Co 1:** The reference says `columns` selects columns, while the bundle's comparison says synchronous `readParquet` ignores it in 0.9.0; following the reference can return unwanted columns. **Cm 1:** It names the option but does not explain ordering or missing names. **Cl 1:** There is no selection example, and the conflicting statements leave the reader unsure which path works.
4. **F 1:** Offset, limit and row-group options appear in the reference without a guide pointer to the task. **Cm 1:** The options are named, but out-of-range behavior and the cost of a range are not explained. **Cl 1:** There is no worked range example or result.
5. **Co 2:** The FFI schema example calls `parseSchema` and then accesses `.schema` on its result, although the example describes `parseSchema` as returning the schema; this needs an obvious correction. **Cm 2:** Schema, row counts, row groups, compression and key-value metadata are exposed, but the mapping from Parquet types to returned types is not documented. **Cl 2:** The reader must assemble the metadata path from several reference entries; there is no complete metadata example with results.
6. **F 0, Co 0, Cm 0, Cl 0:** Generic schema metadata is mentioned, but the documentation does not explain Stata variable or value labels, their lookup, or conversion of labelled codes to a categorical.
7. **F 1:** A date appears in the general write/read example, with no dates-and-timestamps guide or reference pointer. **Cm 1:** The example shows a `Date64<MILLISECOND>` result, but not the requested date and timestamp units, zones, range behavior or naive-versus-zoned distinction. **Cl 1:** There is no explanation of how to handle those temporal cases.
8. **Cm 1:** The example and builder show writing, codec selection and row-group controls, but omit the default codec, the type mapping and relevant data errors.
9. **F 0, Co 0, Cm 0, Cl 0:** The generic key-value metadata setter is documented, but no method or example attaches and checks the three requested kinds of labels.
10. **F 0, Co 0, Cm 0, Cl 0:** The documentation does not discuss preserving or losing the distinct missing-value letters, including what other tools see.
11. **F 2:** The README has a compression heading, but the rest of the interoperability answer must be sought in the reference. **Cm 1:** It lists codecs and an encoding enum, but does not establish the complete read support, encryption limits or what other tools see in written files. **Cl 1:** There is no worked interoperability example, and an enum of format encodings does not clearly identify reader support.

**Library B**

For each task, **F 2**: from the README the reader follows the Parquet or TypeScript page and then a task link or section within that long page; the task is not named one step from the front page.

1. **Cm 2:** The checkout build, Node requirement, browser and Node entry points, and a build-failure remedy are given, but supported TypeScript and browser versions are not specified.
2. **Co 1:** The type table says every conversion is exact or an error, yet says DECIMAL values of precision up to 15 become the nearest double; that blanket guarantee can mislead a reader about precision.
3. No further deductions.
4. No further deductions.
5. **Co 2:** The guide says everything in the footer is present as soon as the file opens, while the reference says chunk details are read on first access; the distinction needs correction.
6. **Cm 1:** The example reads labels and looks up codes, but does not show how to turn a labelled numeric column into a categorical. It distinguishes an already categorical column, which does not supply that conversion.
7. No further deductions.
8. No further deductions.
9. No further deductions.
10. No further deductions.
11. **Co 2:** The example calls its own `writeParquet` output a stand-in with no dta profile, although the write documentation says its files carry that profile; the example needs correction.

| Task | A mean | B mean |
|---|---:|---:|
| 1 | 2.75 | 2.50 |
| 2 | 2.50 | 2.25 |
| 3 | 1.00 | 2.75 |
| 4 | 1.50 | 2.75 |
| 5 | 2.25 | 2.50 |
| 6 | 0.00 | 2.25 |
| 7 | 1.50 | 2.75 |
| 8 | 2.50 | 2.75 |
| 9 | 0.00 | 2.75 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 2.50 |
| **Total** | **15.75** | **28.50** |
