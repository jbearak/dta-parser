```json
{"A":{"1":[2,3,1,2],"2":[2,3,1,2],"3":[1,3,1,1],"4":[1,3,1,1],"5":[1,3,1,1],"6":[0,0,0,0],"7":[0,0,0,0],"8":[2,3,1,2],"9":[0,0,0,0],"10":[0,0,0,0],"11":[2,3,1,1]},"B":{"1":[2,3,3,3],"2":[2,3,3,3],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,3,3,3],"6":[2,3,3,3],"7":[2,3,3,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,1,3,2]}}
```

Scores are in the order findability (F), correctness (Co), completeness (Cm), clarity (Cl). Correctness is judged from the supplied text; omissions are reflected in completeness, not assumed to be false.

### Library A

1. **[2, 3, 1, 2]** F: The installation page must be reached from the documentation home; the supplied home has no direct install entry. Cm: It gives commands and a legacy CPU alternative, but not supported platforms, Python versions, or general installation troubleshooting. Cl: The command is clear, but there is no described verification result.
2. **[2, 3, 1, 2]** F: The Parquet guide is beyond the front page. Cm: It shows the call and DataFrame result but does not provide the requested type mapping or losses and refusals. Cl: The example does not describe its resulting contents.
3. **[1, 3, 1, 1]** F: Column selection appears in the function reference without a guide pointer to the task. Cm: Names and zero-based positions are given, but output order and an unknown name's behavior are not. Cl: There is no selection example.
4. **[1, 3, 1, 1]** F: The row limit is in the reference, without a guide pointer for row ranges. Cm: The reference gives `n_rows` and page-skipping options, but no complete skip-and-limit recipe or out-of-range behavior. Cl: There is no range example or explanation of its cost.
5. **[1, 3, 1, 1]** F: Schema and metadata calls appear in reference entries without a guide pointer. Cm: They return names and types and custom metadata, but the supplied entries do not show row counts, row groups, or compression. Cl: There is no example of the returned dictionaries.
6. **[0, 0, 0, 0]** F and Co: The supplied A documentation does not explain reading variable or value labels or converting them to categories. Cm and Cl: With no task coverage, it supplies neither a working path nor an explanation or example.
7. **[0, 0, 0, 0]** F and Co: The supplied A documentation has no Parquet date and timestamp conversion instructions. Cm and Cl: It supplies neither the requested mapping and edge cases nor an example explaining them.
8. **[2, 3, 1, 2]** F: The write section is on the Parquet guide beyond the front page. Cm: It gives a write call, codec choices and row-group size, but the A reference does not state the default codec or give type mappings and write errors. Cl: The short write example does not describe the resulting file's contents.
9. **[0, 0, 0, 0]** F and Co: Although the reference mentions generic metadata, it gives no instructions for attaching and checking the requested labels. Cm and Cl: There is no label-writing path or example.
10. **[0, 0, 0, 0]** F and Co: The supplied A documentation does not discuss distinguishing or preserving these missing values. Cm and Cl: It provides no round-trip path or explanation of what other tools see.
11. **[2, 3, 1, 1]** F: The read and write material is on the Parquet guide and reference beyond the front page. Cm: It mentions decryption and recommends snappy for compatibility, but does not enumerate readable codecs, encodings, types, or interoperability limits. Cl: There is no worked example explaining the result of interchange with another tool.

### Library B

1. **[2, 3, 3, 3]** F: The README links to the Python guide, where the Parquet installation details must be located; the Parquet task index is another route through an additional page.
2. **[2, 3, 3, 3]** F: The README's Parquet link leads to a task index, then to the Python read and type-mapping sections.
3. **[2, 3, 3, 3]** F: The named selection section is reached through the Parquet task index or the long Python guide.
4. **[2, 3, 3, 3]** F: The row-range section is reached through the Parquet task index or the long Python guide.
5. **[2, 3, 3, 3]** F: The schema and metadata section is reached through the Parquet task index or the long Python guide.
6. **[2, 3, 3, 3]** F: The labels section is reached through the Parquet task index or the long Python guide.
7. **[2, 3, 3, 3]** F: The date and time-zone section is reached through the Parquet task index or the long Python guide.
8. **[2, 3, 3, 3]** F: The write section is reached through the Parquet task index or the long Python guide.
9. **[2, 3, 3, 3]** F: The label-writing section is reached through the Parquet task index or the long Python guide.
10. **[2, 3, 3, 3]** F: The missing-letter round-trip section is reached through the Parquet task index or the long Python guide.
11. **[2, 1, 3, 2]** F: The interoperability section is reached through the Parquet task index or the long Python guide. Co: The Python section says it reads every encoding, while the shared errors table says BIT_PACKED values are not read; this can mislead a reader about whether a file will open. Cl: The conflicting statements require rereading to identify the limitation.

| Task | A mean | B mean |
|---:|---:|---:|
| 1 | 2.00 | 2.75 |
| 2 | 2.00 | 2.75 |
| 3 | 1.50 | 2.75 |
| 4 | 1.50 | 2.75 |
| 5 | 1.50 | 2.75 |
| 6 | 0.00 | 2.75 |
| 7 | 0.00 | 2.75 |
| 8 | 2.00 | 2.75 |
| 9 | 0.00 | 2.75 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 2.00 |
| **Total** | **12.25** | **29.50** |
