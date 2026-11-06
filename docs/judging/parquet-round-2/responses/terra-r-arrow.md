```json
{"A":{"1":[3,2,2,2],"2":[3,3,1,2],"3":[2,3,1,2],"4":[1,3,1,1],"5":[1,3,1,2],"6":[2,3,1,1],"7":[1,3,1,1],"8":[3,3,2,2],"9":[2,3,1,1],"10":[0,0,0,0],"11":[2,3,1,1]},"B":{"1":[3,3,3,3],"2":[3,3,3,3],"3":[3,3,2,3],"4":[3,3,2,3],"5":[3,3,2,3],"6":[3,2,3,3],"7":[3,3,2,3],"8":[3,3,3,3],"9":[3,3,2,3],"10":[3,3,3,3],"11":[3,2,3,3]}}
```

Scores are in the order findability (F), correctness (Co), completeness (Cm), and clarity (Cl). Correctness is judged from the supplied material; it does not independently establish the behavior of a pinned version.

### Library A

1. **Install — [3, 2, 2, 2].** Co: The README says C++20 is required as of version 23, while the Linux guide says version 22. Cm: The general minimum R version and a complete platform support statement are not given. Cl: The conflicting version statements and lengthy Linux alternatives require some rereading.
2. **Read a whole file — [3, 3, 1, 2].** Cm: The call and return type are given, but the bundle lacks a Parquet-to-R type mapping and an account of losses and refusals. Cl: The example does not describe its resulting columns or values.
3. **Read columns — [2, 3, 1, 2].** F: Column selection is embedded within the Parquet section rather than named by a front-page-linked heading. Cm: Names and tidy selection are described, but selection order and unknown-name behavior are not. Cl: The example does not show its result.
4. **Read rows — [1, 3, 1, 1].** F: Row-group methods appear only in the reader reference, with no specific guide pointer. Cm: It gives zero-based row-group reads but not out-of-range behavior or their cost. Cl: There is no row-group example or explanation of how to turn a desired row range into groups.
5. **Schema and metadata — [1, 3, 1, 2].** F: The file-reader reference is the only direct route to the file schema and counts. Cm: It does not explain the resulting R types, per-group compression, or how to retrieve file key-value metadata. Cl: The schema example does not show its output and the necessary properties are scattered.
6. **Use labels — [2, 3, 1, 1].** F: Label preservation is mentioned within the read/write and metadata articles, not under a task-named heading. Cm: The docs say labelled attributes survive, but do not show how to inspect value and variable labels, look up a code, or make a factor. Cl: There is no label-use example or explanation of those terms.
7. **Dates and timestamps — [1, 3, 1, 1].** F: Timestamp options appear in the writer reference without a guide pointer for this task. Cm: Coercion and truncation options are listed, but DATE and TIMESTAMP conversions, zones, ranges, and naive times are not explained. Cl: There is no date or timestamp example.
8. **Write a table — [3, 3, 2, 2].** Cm: The call, codecs, default, and row-group size are covered, but the R-to-Parquet type mapping and type errors are not. Cl: The examples show calls without describing the resulting schema or data.
9. **Write and check labels — [2, 3, 1, 1].** F: Attribute round trips are discussed within the linked read/write article and a further metadata article. Cm: The general attribute example and labelled-column preservation do not show how to attach all three labels and check them after reading. Cl: There is no labelled Parquet round-trip example or explanation of the label concepts.
10. **Keep `.a` to `.z` — [0, 0, 0, 0].** F: No task-specific answer is found in A's bundle. Co: The task is not covered. Cm: It provides no procedure or account of loss; Cl: there is no explanation or example.
11. **Read another tool's file — [2, 3, 1, 1].** F: Relevant fragments about codecs and metadata are buried in linked articles and the writer reference. Cm: There is no reader support matrix for codecs, encodings, types, nested data, and encryption; interoperability is discussed only in part. Cl: No example shows reading another tool's file or its result.

### Library B

1. **Install — [3, 3, 3, 3].**
2. **Read a whole file — [3, 3, 3, 3].**
3. **Read columns — [3, 3, 2, 3].** Cm: Names, order, and unknown names are covered, but the Parquet section does not explicitly explain positional selection.
4. **Read rows — [3, 3, 2, 3].** Cm: The window and page-reading cost are explained, but the result of an out-of-range request is not stated.
5. **Schema and metadata — [3, 3, 2, 3].** Cm: The footer call covers types, counts, row groups, codecs, and selected profile metadata, but does not provide a way to inspect arbitrary key-value entries.
6. **Use labels — [3, 2, 3, 3].** Co: In the labelled-column reference example, `x[2]` is changed to `"Yes"`, but the subsequent `val_label(x)` and `table(x)` comments still report the old `"No"` value; removing or moving the assignment would fix the example.
7. **Dates and timestamps — [3, 3, 2, 3].** Cm: Units, zone fallback, and nanosecond truncation are covered, but out-of-range dates and timestamps and the distinction between naive and zoned Parquet timestamps in R are not fully specified.
8. **Write a table — [3, 3, 3, 3].**
9. **Write and check labels — [3, 3, 2, 3].** Cm: The example attaches the variable, value, and data labels and checks the value labels, but does not show checking the variable and data labels after reading.
10. **Keep `.a` to `.z` — [3, 3, 3, 3].**
11. **Read another tool's file — [3, 2, 3, 3].** Co: The R guide says it reads “every encoding,” while the errors table identifies BIT_PACKED values as unsupported; the broad claim needs that exception.

### Task scores

| Task | A | B |
|---:|---:|---:|
| 1 | 2.25 | 3.00 |
| 2 | 2.25 | 3.00 |
| 3 | 2.00 | 2.75 |
| 4 | 1.50 | 2.75 |
| 5 | 1.75 | 2.75 |
| 6 | 1.75 | 2.75 |
| 7 | 1.50 | 2.75 |
| 8 | 2.50 | 3.00 |
| 9 | 1.75 | 2.75 |
| 10 | 0.00 | 3.00 |
| 11 | 1.75 | 2.75 |
| **Total** | **19.00** | **31.25** |
