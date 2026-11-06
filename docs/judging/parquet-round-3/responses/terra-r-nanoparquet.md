```json
{"A":{"1":[3,3,1,2],"2":[3,1,1,1],"3":[1,3,2,1],"4":[1,3,0,1],"5":[3,3,3,2],"6":[1,3,0,1],"7":[1,3,1,1],"8":[3,3,1,2],"9":[1,3,0,1],"10":[0,0,0,0],"11":[2,1,2,1]},"B":{"1":[3,3,3,3],"2":[3,2,3,3],"3":[3,3,3,3],"4":[3,3,3,3],"5":[3,3,3,3],"6":[3,3,3,3],"7":[3,3,2,3],"8":[3,3,3,3],"9":[3,3,3,3],"10":[3,3,3,3],"11":[3,3,3,3]}}
```

Scores are in findability, correctness, completeness, clarity order. A correctness score of 3 for a partial or unsupported task means the statements that are present are not contradicted by the supplied material; it does not mean the task can be completed from them. The bundle does not independently establish the pinned implementation's behavior, so correctness judgments rely on its own statements and internal consistency.

**Library A**

1. **[3, 3, 1, 2]** Completeness: the install command is given, but supported R versions, platforms and installation failure remedies are absent. Clarity: the command is straightforward, but no result or troubleshooting example is described.
2. **[3, 1, 1, 1]** Correctness: the README says nested types are unsupported, while the list-column article says standard LIST columns can be read; this can mislead a reader deciding whether a file will work. Completeness: the read call and data-frame result are provided, but the linked full type mapping is not in the supplied bundle. Clarity: the conflicting list guidance makes the supported result hard to determine.
3. **[1, 3, 2, 1]** Findability: the README mentions selecting columns but does not point to the selection argument; its details are in the function reference. Completeness: names, positions, order and duplicate selection are documented, but an unknown name's behavior is not. Clarity: the reference gives no selection example.
4. **[1, 3, 0, 1]** Findability: the explicit statement that row subsets cannot be read is in the presentation, without a task pointer from the README. Completeness: there is no row-range procedure, boundary behavior or cost for a range. Clarity: the limitation is stated, but there is no example or practical alternative.
5. **[3, 3, 3, 2]** Clarity: the README demonstrates the calls without showing their results; the detailed output fields require reading the reference.
6. **[1, 3, 0, 1]** Findability: factor preservation is mentioned in the README options, but the requested label operations have no task pointer. Completeness: the bundle does not show how to read variable or value labels, look up a code or convert a value-labelled column to a factor. Clarity: there is no example of those label operations.
7. **[1, 3, 1, 1]** Findability: temporal types are mentioned, while the type mapping is directed to a reference not included in the bundle. Completeness: examples show schema inference and writing generally, but do not give DATE and TIMESTAMP mappings, units, time zones, range limits or naive-time behavior. Clarity: no date or timestamp read/write example explains a result.
8. **[3, 3, 1, 2]** Completeness: the write call, codecs, default and row-group settings are documented, but the full R-to-Parquet mapping and type-specific errors are not supplied. Clarity: the basic write example does not show the resulting schema or output.
9. **[1, 3, 0, 1]** Findability: generic key-value metadata and factor preservation are mentioned, but the label-writing task is not indexed. Completeness: no procedure attaches and checks variable, value and data labels. Clarity: there is no label round-trip example.
10. **[0, 0, 0, 0]** Findability: the A bundle has no task-specific pointer. Correctness: the task is not covered. Completeness: it provides no way to distinguish, write and read the letters or explain what other tools see. Clarity: there is no explanation or example.
11. **[2, 1, 2, 1]** Findability: the README lists limitations and links to types, but the encoding and interoperability details require searching other material. Correctness: the README and presentation rule out LIST columns while the list-column article says they are supported. Completeness: codecs, encryption, encodings and some cross-tool behavior are discussed, but the full type mapping is absent from the bundle. Clarity: the conflicting nested-type statements leave readers unsure which files are supported.

**Library B**

1. **[3, 3, 3, 3]**
2. **[3, 2, 3, 3]** Correctness: the general Parquet guide says DECIMAL reads by default as the nearest double, while the R guide says values with more than 15 significant digits cause an error. The R-specific table clarifies the rule, but the general statement needs qualification.
3. **[3, 3, 3, 3]**
4. **[3, 3, 3, 3]**
5. **[3, 3, 3, 3]**
6. **[3, 3, 3, 3]**
7. **[3, 3, 2, 3]** Completeness: the documentation explains units, zone precedence, precision and truncation, but does not clearly specify out-of-range date/timestamp behavior in R or fully explain how an unadjusted, naive timestamp differs from a zoned instant on read.
8. **[3, 3, 3, 3]**
9. **[3, 3, 3, 3]**
10. **[3, 3, 3, 3]**
11. **[3, 3, 3, 3]**

| Task | Library A | Library B |
|---|---:|---:|
| 1 | 2.25 | 3.00 |
| 2 | 1.50 | 2.75 |
| 3 | 1.75 | 3.00 |
| 4 | 1.25 | 3.00 |
| 5 | 2.75 | 3.00 |
| 6 | 1.25 | 3.00 |
| 7 | 1.50 | 2.75 |
| 8 | 2.25 | 3.00 |
| 9 | 1.25 | 3.00 |
| 10 | 0.00 | 3.00 |
| 11 | 1.50 | 3.00 |
| **Total** | **17.25** | **32.50** |
