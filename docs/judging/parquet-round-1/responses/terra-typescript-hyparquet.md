```json
{"A":{"1":[2,0,0,1],"2":[2,3,1,2],"3":[2,3,1,2],"4":[2,3,2,2],"5":[3,2,2,2],"6":[0,0,0,0],"7":[2,2,1,1],"8":[3,2,2,2],"9":[0,0,0,0],"10":[0,0,0,0],"11":[2,1,1,1]},"B":{"1":[2,3,3,3],"2":[2,1,3,3],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,3,3,3],"6":[2,3,2,3],"7":[2,3,3,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,1,3,3]}}
```

Scores are ordered findability (F), correctness (Co), completeness (Cm), and clarity (Cl). The bundle supplies documentation rather than implementation or execution evidence, so correctness judgments are limited to errors and contradictions visible in that material.

**Library A**

1. **F 2:** Browser and Node use are described on the long front page, but there is no install heading or command. **Co 0:** Installation itself is not covered. **Cm 0:** There is no package installation path or installation-failure guidance. **Cl 1:** The platform notes are understandable, but there is no installation example.
2. **F 2:** The whole-file call is in the Node example on the long README. **Cm 1:** The call and returned row shape are documented, but there is no complete Parquet-to-JavaScript type mapping or account of losses and refusals. **Cl 2:** The example gives no resulting rows.
3. **F 2:** A column selection appears in the browser example, without a task heading. **Cm 1:** It shows names but does not explain output order or the behavior of unknown names. **Cl 2:** The example does not show the selected result.
4. **F 2:** The range appears in the quick-start example and its inclusive/exclusive bounds are explained in the type reference. **Cm 2:** Minimal row-group reads and index options are described, but out-of-range behavior is not. **Cl 2:** The example does not show the returned rows.
5. **Co 2:** The metadata example uses `asyncBufferFromUrl` without importing it. **Cm 2:** Metadata structures expose row groups, codecs and key-value entries, but the docs do not give a complete mapping to returned JavaScript types. **Cl 2:** The example identifies its results in comments but does not show their values, and the remaining metadata fields require reading type declarations.
6. **F 0, Co 0, Cm 0, Cl 0:** The supplied A documentation does not cover variable labels, value-label lookup, or conversion of labelled columns to categoricals.
7. **F 2:** Date writing appears in the companion writer's advanced example, reached from the writing link; parser hooks appear in type declarations. **Co 2:** The writer example has the obvious misspelling `snappyCompresss`. **Cm 1:** It shows a DATE schema and lists TIMESTAMP milliseconds, but does not explain the full read/write conversions, precision, zones or range limits. **Cl 1:** There is no focused date round-trip example or result, and the reader must infer behavior from schema and parser names.
8. **Co 2:** The advanced writing example uses `snappyCompresss` instead of the imported `snappyCompress`. **Cm 2:** The writer covers calls, codec and row-group defaults, explicit types and some inference pitfalls, but does not fully specify inference for each JavaScript type or all write errors. **Cl 2:** The examples do not show the resulting file or a read-back result.
9. **F 0, Co 0, Cm 0, Cl 0:** Generic key-value metadata is documented, but attaching and checking variable, value and data labels is not.
10. **F 0, Co 0, Cm 0, Cl 0:** The documentation does not explain distinguishing, writing or recovering `.a` to `.z`, or what other tools see.
11. **F 2:** Compression has a README heading, but the rest must be assembled from the long page and declarations. **Co 1:** The README claims support for all compression codecs, while its own table says most require a separate package; that can mislead a reader about a default installation. **Cm 1:** Codec choices and some nested-reading behavior are described, but supported encodings, encryption limits and what other tools see in written files are not adequately specified. **Cl 1:** The broad support claim conflicts with the codec table and there is no interoperability result example.

**Library B**

For every task, **F 2:** the front page links to the Parquet guide, whose task index links onward to the TypeScript section; the task-specific answers therefore take at least two links from the front page.

2. **Co 1:** The type table says DECIMAL values of precision at most 15 become the nearest double, while the surrounding claim says every conversion is exact or an error. That contradiction can give a reader a false expectation of exact decimal results.
6. **Cm 2:** The example reads variable and value labels and looks up their text, and describes existing dictionary columns, but it does not show how to turn a numerically labelled column into a categorical representation.
11. **Co 1:** The statement that the reader reads every flat file written by the named tools is broader than the immediately listed exceptions for codecs and types; a reader could wrongly rely on that unconditional claim.

All other B scores are 3: the relevant sections supply the task's main path, stated options and limits, and examples with results. For task 11 the detailed exception list is complete for the rubric, despite the conflicting broad claim.

| Task | A mean | B mean |
|---|---:|---:|
| 1 | 0.75 | 2.75 |
| 2 | 2.00 | 2.25 |
| 3 | 2.00 | 2.75 |
| 4 | 2.25 | 2.75 |
| 5 | 2.25 | 2.75 |
| 6 | 0.00 | 2.50 |
| 7 | 1.50 | 2.75 |
| 8 | 2.25 | 2.75 |
| 9 | 0.00 | 2.75 |
| 10 | 0.00 | 2.75 |
| 11 | 1.25 | 2.25 |
| **Total** | **14.25** | **29.00** |
