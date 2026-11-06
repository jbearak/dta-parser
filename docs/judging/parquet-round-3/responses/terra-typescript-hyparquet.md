```json
{"A":{"1":[3,3,3,3],"2":[3,3,3,3],"3":[3,3,3,3],"4":[3,3,3,3],"5":[3,3,3,3],"6":[3,3,3,3],"7":[3,3,3,3],"8":[3,3,3,3],"9":[3,3,3,3],"10":[3,3,3,3],"11":[3,3,3,3]},"B":{"1":[0,0,0,0],"2":[2,2,1,2],"3":[1,3,1,2],"4":[1,3,2,2],"5":[3,2,2,2],"6":[0,0,0,0],"7":[1,3,1,1],"8":[3,2,2,2],"9":[1,3,1,1],"10":[0,0,0,0],"11":[2,3,1,2]}}
```

Scores are ordered findability (F), correctness (Co), completeness (Cm), and clarity (Cl). Correctness is judged from the supplied material; the bundle does not independently establish every implementation claim.

**Library A.** All four scores are 3 for each task. Its front page points to a Parquet task index, and the TypeScript guide gives task-specific examples, results, options and limits. In particular, it documents the conversion table and errors, the categorical recipe, timestamp units and zones, and the different ways other readers see missing letters.

**Library B.**

1. **F 0, Co 0, Cm 0, Cl 0.** There is no installation section or install command to find or assess. The badge and browser/Node examples do not supply a complete installation procedure, supported versions or failure guidance.
2. **F 2:** The Node quick start provides the read call, but the type conversions require searching elsewhere in the bundle. **Co 2:** The example imports `asyncBufferFromFile` from the main package, while the supplied declarations export it from the Node entry point. **Cm 1:** The call and returned row shape are given, but there is no complete table of conversions and losses. **Cl 2:** The examples show calls without showing their resulting rows.
3. **F 1:** Column selection appears in the quick-start example and option declaration rather than a named task section. **Cm 1:** Names are shown, but the docs do not say what happens for an absent name or whether the requested order is preserved. **Cl 2:** The example does not show the selected result.
4. **F 1:** Row selection is in the quick-start example and option declarations, without a task heading. **Cm 2:** The inclusive start, exclusive end and reading cost are described, but the out-of-range behavior is not. **Cl 2:** The range example has no displayed result.
5. **Co 2:** The metadata example uses `asyncBufferFromUrl` and `url` without defining or importing them in the snippet. **Cm 2:** The declarations expose row groups, codecs and key-value metadata, but do not explain what each schema type will become on reading. **Cl 2:** The example shows how to obtain the schema and names but no resulting values, and other fields require reading declarations.
6. **F 0, Co 0, Cm 0, Cl 0.** The bundle has no procedure for interpreting variable or value labels, looking up a code or making a categorical column. General key-value metadata alone does not explain a label convention.
7. **F 1:** A timestamp type and a DATE schema occur in writer material and parser declarations, without a dates task guide. **Cm 1:** The material gives a way to specify date-related schema but does not explain the full read/write conversion, range, precision or zone behavior. **Cl 1:** There is no focused date round-trip example with a result, and the reader must piece the approach together from schema details.
8. **Co 2:** The advanced example spells the imported `snappyCompress` as `snappyCompresss`; the local-file example also imports `parquetWriteFile` from the main entry point although its declaration is in the Node entry point. **Cm 2:** The codec, row groups, explicit types and an inference error are covered, but the mapping from every JavaScript input type and its errors is not. **Cl 2:** The write examples do not show the resulting file contents.
9. **F 1:** Generic key-value metadata is available in the writer options and metadata declarations, but there is no pointer to a label-writing task. **Cm 1:** The generic metadata mechanism is shown without a convention for attaching and checking the three kinds of label. **Cl 1:** There is no label round-trip example or explanation of how a reader should interpret the entries.
10. **F 0, Co 0, Cm 0, Cl 0.** The documentation does not describe representing or round-tripping the distinct missing letters; the task is not covered.
11. **F 2:** Codec support has a heading, while the rest requires searching the guide and declarations. **Cm 1:** The codec table, nested-data discussion and broad support claim do not provide a detailed encoding/type support matrix, encryption limits or what other tools see in written files. **Cl 2:** The codec example gives no result, and the broad support claim leaves the reader to reconcile it with the separate optional-codec explanation.

| Task | A mean | B mean |
|---|---:|---:|
| 1 | 3.00 | 0.00 |
| 2 | 3.00 | 1.75 |
| 3 | 3.00 | 1.75 |
| 4 | 3.00 | 2.00 |
| 5 | 3.00 | 2.25 |
| 6 | 3.00 | 0.00 |
| 7 | 3.00 | 1.50 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 1.50 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 2.00 |
| **Total** | **33.00** | **15.00** |
