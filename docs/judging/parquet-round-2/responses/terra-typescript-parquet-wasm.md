```json
{"A":{"1":[2,3,2,3],"2":[2,1,3,2],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,3,3,3],"6":[2,3,1,3],"7":[2,3,3,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,3,3,3]},"B":{"1":[3,3,2,2],"2":[3,3,1,3],"3":[1,1,1,1],"4":[1,3,1,1],"5":[2,3,2,1],"6":[0,0,0,0],"7":[1,3,1,2],"8":[3,3,1,2],"9":[0,0,0,0],"10":[0,0,0,0],"11":[2,3,1,1]}}
```

Scores are ordered findability (F), correctness (Co), completeness (Cm), and clarity (Cl). I judge only what the supplied bundle establishes; an omission is not itself evidence that a supported feature fails.

### Library A

1. **[2, 3, 2, 3]** F: The README points to the TypeScript page, whose install section supplies the instructions. Cm: Node and browser use and a build failure are covered, but supported TypeScript versions and a full platform list are not stated.
2. **[2, 1, 3, 2]** F: The reader must follow the Parquet or TypeScript documentation and then find the task section. Co: The claim that every conversion is exact conflicts with the table's statement that DECIMAL values of precision at most 15 become the nearest double; this can mislead a reader about precision. Cl: The type table and the exactness claim require reconciliation.
3. **[2, 3, 3, 3]** F: The task is indexed in the linked Parquet guide, with the TypeScript answer another link away.
4. **[2, 3, 3, 3]** F: The task is indexed in the linked Parquet guide, with the TypeScript answer another link away.
5. **[2, 3, 3, 3]** F: The task is indexed in the linked Parquet guide, with the TypeScript answer another link away.
6. **[2, 3, 1, 3]** F: The labels task is indexed in the linked guide, with the TypeScript answer another link away. Cm: The example retrieves labels and maps codes to text, but does not show how to turn a labelled numeric column into a categorical.
7. **[2, 3, 3, 3]** F: The dates task is indexed in the linked guide, with the TypeScript answer another link away.
8. **[2, 3, 3, 3]** F: The write task is indexed in the linked guide, with the TypeScript answer another link away.
9. **[2, 3, 3, 3]** F: The label-writing task is indexed in the linked guide, with the TypeScript answer another link away.
10. **[2, 3, 3, 3]** F: The missing-values task is indexed in the linked guide, with the TypeScript answer another link away.
11. **[2, 3, 3, 3]** F: The interoperability task is indexed in the linked guide, with the TypeScript answer another link away.

### Library B

1. **[3, 3, 2, 2]** Cm: Installation commands, entry points, initialization, and a Node polyfill are described, but a complete platform and language-version support matrix is absent. Cl: The reader must piece together the install, entry-point, and Node-version sections.
2. **[3, 3, 1, 3]** Cm: The README demonstrates the read and conversion to an Arrow JS table, but does not map each Parquet type or explain losses and refusals.
3. **[1, 1, 1, 1]** F: Column selection is described in the reader reference, with no task-specific guide pointer. Co: The sync `readParquet` reference presents `columns` as effective, while the supplied comparison says it is ignored in version 0.9.0; following it could return unwanted columns. Cm: Names are listed, but ordering, positions, and unknown-name behavior are not explained. Cl: The reference has no selection example, and the bundle's statements conflict.
4. **[1, 3, 1, 1]** F: Offset, limit, row groups, and batch size appear in the reader reference without a task-specific guide pointer. Cm: It does not explain out-of-range behavior or the cost of a window. Cl: The options lack a worked range example.
5. **[2, 3, 2, 1]** F: The README links to schema and file APIs, but the metadata details must be assembled from reference entries. Cm: The APIs expose schema, rows, row groups, compression, and key-value metadata, but the docs do not give a type-conversion mapping. Cl: There is no complete example that gathers the metadata, and the reader must navigate several classes.
6. **[0, 0, 0, 0]** F: No value-label or variable-label task is indexed or described. Co, Cm, Cl: Generic schema metadata is exposed, but the bundle gives no label-reading, lookup, or categorical-conversion procedure to judge.
7. **[1, 3, 1, 2]** F: Date handling is only implied by the README example's input and resulting schema. Cm: The bundle does not explain DATE and TIMESTAMP conversion, units, zones, range limits, or naive versus zoned times. Cl: The example reports a schema but does not explain the date values or their round trip.
8. **[3, 3, 1, 2]** Cm: The write example and reference show compression and row-group controls, but do not give the default codec, default row-group size, type mapping, or a complete account of write errors. Cl: The example shows a schema after reading, but explaining its results and writer settings requires consulting separate reference entries.
9. **[0, 0, 0, 0]** F: No label-writing task is described. Co, Cm, Cl: Although the API can attach generic key-value metadata, the bundle gives no convention or round-trip example for variable, value, and data labels.
10. **[0, 0, 0, 0]** F: The documentation does not discuss these missing codes. Co, Cm, Cl: It supplies no way to distinguish, write, or read back the letters, or explanation of what other tools see.
11. **[2, 3, 1, 1]** F: The README has a compression section, while other relevant details are scattered through the reference. Cm: Codecs are listed, but the bundle does not establish a complete supported read-encoding and type matrix, encryption limits, or what other tools see in written files; an encoding enum alone does not establish reader support. Cl: There is no interoperability walkthrough tying these limits together.

| Task | A mean | B mean |
|---|---:|---:|
| 1 | 2.50 | 2.50 |
| 2 | 2.00 | 2.50 |
| 3 | 2.75 | 1.00 |
| 4 | 2.75 | 1.50 |
| 5 | 2.75 | 2.00 |
| 6 | 2.25 | 0.00 |
| 7 | 2.75 | 1.75 |
| 8 | 2.75 | 2.25 |
| 9 | 2.75 | 0.00 |
| 10 | 2.75 | 0.00 |
| 11 | 2.75 | 1.75 |
| **Total** | **28.75** | **15.25** |
