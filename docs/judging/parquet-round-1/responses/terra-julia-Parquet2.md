```json
{"A":{"1":[3,3,3,3],"2":[3,3,3,3],"3":[3,3,3,3],"4":[3,3,3,3],"5":[3,3,3,3],"6":[3,3,3,3],"7":[3,3,2,3],"8":[3,3,3,3],"9":[3,3,3,3],"10":[3,3,3,3],"11":[3,3,3,3]},"B":{"1":[3,3,1,2],"2":[2,3,1,2],"3":[3,2,1,2],"4":[2,3,2,2],"5":[2,3,1,2],"6":[0,0,0,0],"7":[1,3,1,1],"8":[3,3,1,2],"9":[0,0,0,0],"10":[0,0,0,0],"11":[2,3,1,1]}}
```

Scores are ordered findability, correctness, completeness, clarity. Correctness reflects the evidence in the supplied bundle; the documentation alone does not independently establish every claim or verify every example against a pinned implementation.

## Library A

1. **Install — 3, 3, 3, 3.**
2. **Read a whole file — 3, 3, 3, 3.**
3. **Read some columns — 3, 3, 3, 3.**
4. **Read a range of rows — 3, 3, 3, 3.**
5. **Schema and metadata — 3, 3, 3, 3.**
6. **Use labels — 3, 3, 3, 3.**
7. **Dates and timestamps — 3, 3, 2, 3.** Completeness: the guide covers units, zones and loss of sub-millisecond precision, but does not explain what happens to dates or timestamps outside Julia's representable range.
8. **Write a table — 3, 3, 3, 3.**
9. **Write and check labels — 3, 3, 3, 3.**
10. **Keep `.a` to `.z` — 3, 3, 3, 3.**
11. **Read another tool's file — 3, 3, 3, 3.**

## Library B

1. **Install — 3, 3, 1, 2.** Completeness: the README gives the installation commands but not supported Julia versions, platforms or installation troubleshooting. Clarity: the commands are understandable, but their result is not described.
2. **Read a whole file — 2, 3, 1, 2.** Findability: the README's basic usage example gives the call, while the guide places it under the broad “Accessing Data” heading. Completeness: it shows a DataFrame conversion but does not provide a full Parquet-to-Julia type mapping or a systematic account of losses and refusals. Clarity: the example explains what it loads but does not show the resulting table.
3. **Read some columns — 3, 2, 1, 2.** Correctness: the README's selection example uses `TableOperations.select` without loading `TableOperations`; adding the import is an obvious fix, and the guide also shows `Parquet2.select`. Completeness: names and selective loading are shown, but selection order and unknown-name behavior are not specified, and positional selection is not demonstrated for the multi-column call. Clarity: the example describes what loads but shows no result.
4. **Read a range of rows — 2, 3, 2, 2.** Findability: row-group access appears in basic examples and dataset discussion, rather than under a heading naming row selection. Completeness: the guide explains row groups and loading costs, but does not say what an out-of-range row-group request does. Clarity: the row-group example describes the operation without showing the resulting DataFrame.
5. **Schema and metadata — 2, 3, 1, 2.** Findability: the README and guide show schema and metadata calls within broader usage sections. Completeness: they show schema, row groups and auxiliary metadata, but do not give a complete recipe for total row count, compression and all requested footer details. Clarity: the schema display has output, but the metadata calls do not show or explain their results in detail.
6. **Use labels — 0, 0, 0, 0.** The Library B material shows generic auxiliary metadata access, but does not explain variable labels, value labels, code lookup or conversion of a labelled column to a categorical; the task is therefore not covered.
7. **Dates and timestamps — 1, 3, 1, 1.** Findability: `DateTime` is only apparent in the displayed example schema; there is no task-specific guide or pointer. Completeness: the example indicates a timestamp result type, but does not document the read/write conversions, units, zones or range behavior. Clarity: there is no worked date or timestamp example explaining its result.
8. **Write a table — 3, 3, 1, 2.** Completeness: the guide gives the write call, codec examples and partition-based row groups, but not a full type mapping, the default codec or a systematic list of errors. Clarity: the examples identify destinations and options but do not show a readback or describe the resulting file in detail.
9. **Write and check labels — 0, 0, 0, 0.** Generic file and column metadata write options are shown, but the Library B material gives no label convention or label round-trip procedure, so the task is not covered.
10. **Keep `.a` to `.z` — 0, 0, 0, 0.** Library B's own documentation does not cover distinguishing, writing or reading these missing-value codes, or explaining what other tools see.
11. **Read another tool's file — 2, 3, 1, 1.** Findability: relevant limitations appear in development notes rather than a task-specific interoperability guide. Completeness: nested columns and encryption are identified as wanted features, but the material lacks a usable inventory of readable codecs, encodings and types and what other tools see in its output. Clarity: there is no worked interoperability example or result, and the limitations are embedded in technical development notes.

| Task | Library A | Library B |
|---:|---:|---:|
| 1 | 3.00 | 2.25 |
| 2 | 3.00 | 2.00 |
| 3 | 3.00 | 2.00 |
| 4 | 3.00 | 2.25 |
| 5 | 3.00 | 2.00 |
| 6 | 3.00 | 0.00 |
| 7 | 2.75 | 1.50 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 0.00 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 1.75 |
| **Total** | **32.75** | **16.00** |
