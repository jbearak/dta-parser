```json
{"A":{"1":[3,2,2,2],"2":[3,3,1,2],"3":[3,3,1,2],"4":[1,3,1,1],"5":[1,3,1,1],"6":[2,3,1,1],"7":[1,3,1,1],"8":[3,3,2,2],"9":[2,3,1,1],"10":[0,0,0,0],"11":[2,3,1,1]},"B":{"1":[3,3,3,3],"2":[2,3,3,3],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,3,3,3],"6":[2,3,3,3],"7":[2,3,2,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,3,3,3]}}
```

Scores are ordered findability (F), correctness (Co), completeness (Cm), and clarity (Cl). Correctness reflects what can be established from the supplied material; the bundle does not independently verify every claim or example against a pinned implementation.

## Library A

1. **Co 2:** The README says C++20 is required as of version 23, while the Linux guide says version 22. **Cm 2:** Installation routes, platforms and troubleshooting are covered, but the supported R version is not stated generally across platforms. **Cl 2:** The conflicting version statements require reconciliation.
2. **Cm 1:** The read call and return type are given, but there is no complete Parquet-to-R type table or account of losses and refusals. **Cl 2:** The example shows the call but does not describe its resulting columns or output.
3. **Cm 1:** Names and tidy selection are documented, but position selection, ordering and unknown-name behavior are not explained. **Cl 2:** The selection example does not describe its result.
4. **F 1:** Row-group reading is in the `ParquetFileReader` reference without a task-specific guide pointer. **Cm 1:** The methods and zero-based group indices are given, but out-of-range behavior and cost are not. **Cl 1:** There is no row-group reading example.
5. **F 1:** The file-reader reference is the only place presenting the relevant schema and count methods together. **Cm 1:** It gives schema, row count and row-group count, but not a complete account of R conversions, compression or footer key-value metadata. **Cl 1:** The example calls `GetSchema()` without showing or explaining the result, and does not demonstrate the other requested metadata.
6. **F 2:** The read/write guide mentions labelled columns and links to the metadata article, but does not name the label-use task. **Cm 1:** Attribute preservation is described, but the documentation does not show how to retrieve each label, look up a code or make a factor. **Cl 1:** There is no label-use example, and the term `haven::labelled` is left unexplained.
7. **F 1:** Timestamp writing options appear in the function reference; there is no task-specific guide pointer. **Cm 1:** Coercion, precision loss and INT96 writing are covered, but DATE and TIMESTAMP read mappings, zones, ranges and naive times are not. **Cl 1:** There is no dates-and-timestamps example.
8. **Cm 2:** The write call, codec choices, defaults and row-group sizing are documented, but the R-to-Parquet type mapping and type errors are not fully described. **Cl 2:** The examples demonstrate calls but do not describe their output or resulting schema.
9. **F 2:** The linked metadata article covers attribute preservation, but no heading names writing and checking labels. **Cm 1:** The general attribute example supports the main preservation idea, but does not show attaching and checking variable, value and data labels together. **Cl 1:** There is no label-specific round-trip example.
10. **F 0, Co 0, Cm 0, Cl 0:** Library A's supplied documentation does not cover distinguishing, writing and reading back `.a` to `.z`. The statement about other readers in Library B's bundle is not a substitute for Library A's own documentation.
11. **F 2:** The read/write guide is linked from the README, but interoperability details require searching the material. **Cm 1:** It describes reading Parquet, available write codecs and R metadata interoperability, but does not enumerate supported read encodings and types or encryption and nested-column limits. **Cl 1:** There is no example of reading another tool's file with an explained result.

## Library B

1. All four scores are 3: the README points directly to installation, and the R guide gives commands, supported versions and platforms, source requirements and troubleshooting.
2. **F 2:** The README links to the Parquet task index, which then links to the R read and type sections.
3. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide.
4. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide.
5. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide.
6. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide.
7. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide. **Cm 2:** The documentation covers classes, units, zones, precision and truncation, but does not clearly explain how an external naive timestamp differs from a zoned one or give R out-of-range behavior.
8. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide; the full mapping is in the shared file-format section and reference.
9. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide.
10. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide.
11. **F 2:** The task-specific R section is reached through the Parquet task index or the longer R guide, with cross-tool results in the shared Parquet page.

| Task | Library A | Library B |
|---|---:|---:|
| 1 | 2.25 | 3.00 |
| 2 | 2.25 | 2.75 |
| 3 | 2.25 | 2.75 |
| 4 | 1.50 | 2.75 |
| 5 | 1.50 | 2.75 |
| 6 | 1.75 | 2.75 |
| 7 | 1.50 | 2.50 |
| 8 | 2.50 | 2.75 |
| 9 | 1.75 | 2.75 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 2.75 |
| **Total** | **19.00** | **30.25** |
