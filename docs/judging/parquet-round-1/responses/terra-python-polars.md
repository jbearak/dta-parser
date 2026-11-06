```json
{"A":{"1":[2,3,3,3],"2":[2,3,3,3],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,3,3,3],"6":[2,3,3,3],"7":[2,3,3,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,3,3,3]},"B":{"1":[2,3,1,2],"2":[2,3,1,2],"3":[1,3,1,1],"4":[1,3,1,1],"5":[1,3,1,1],"6":[0,0,0,0],"7":[0,0,0,0],"8":[2,3,1,2],"9":[1,3,0,1],"10":[0,0,0,0],"11":[1,3,1,1]}}
```

Scores are in the order findability (F), correctness (Co), completeness (Cm), and clarity (Cl). Correctness is judged from the supplied material; it does not independently establish the pinned implementation's behavior.

**Library A**

1. **[2, 3, 3, 3]** F: The README leads to the Python page, where the reader must search the long page or follow another link to the Parquet install section.
2. **[2, 3, 3, 3]** F: The Parquet task index is linked from the README, but the Python read and type mapping answers require another link or searching the language page.
3. **[2, 3, 3, 3]** F: The named column-selection section is reached through the Parquet index or by searching the Python page.
4. **[2, 3, 3, 3]** F: The named row-range section requires the same extra navigation from the front page.
5. **[2, 3, 3, 3]** F: The schema and metadata section is named in the Parquet task index, one link beyond the README's Parquet page.
6. **[2, 3, 3, 3]** F: The reader must follow the Parquet task index to the Python labels section or search the language page.
7. **[2, 3, 3, 3]** F: The dates and time zones section is linked from the Parquet task index, rather than directly from the README.
8. **[2, 3, 3, 3]** F: The write section and its type mapping are on the Python page after the front-page link or through the Parquet index.
9. **[2, 3, 3, 3]** F: The example for writing and checking labels is reached through the task index or by searching the Python page.
10. **[2, 3, 3, 3]** F: The dedicated section on keeping letters requires the task index or a search of the Python page.
11. **[2, 3, 3, 3]** F: The Python section and the cross-tool results are reached through the Parquet page's task index or by searching the linked pages.

**Library B**

1. **[2, 3, 1, 2]** F: The supplied front page does not directly name the installation task, so the installation page must be located. Cm: It gives the command and legacy-CPU option, but not supported Python versions and platforms or general failure remedies. Cl: The commands are understandable, but there is no example showing the result of a successful installation.
2. **[2, 3, 1, 2]** F: The Parquet guide must be located beyond the supplied front page. Cm: It gives the read call and DataFrame result, but no Parquet-to-language type mapping or account of loss and refusal. Cl: The example is short but does not show its result.
3. **[1, 3, 1, 1]** F: Selection by name or index appears in the function reference, without a pointer from the supplied Parquet guide. Cm: It omits selection order and the result of an unknown name. Cl: The reference has no column-selection example.
4. **[1, 3, 1, 1]** F: The row limit appears only in the function reference without a guide pointer. Cm: `n_rows` supplies a limit, but the supplied B material does not show how to skip to an arbitrary range, what happens out of range, or the cost of that range. Cl: There is no range example; the distinction between `n_rows` and the unrelated row-index offset requires care.
5. **[1, 3, 1, 1]** F: The schema and metadata functions appear only in reference entries without a pointer from the supplied guide. Cm: They give names and data types and custom metadata, but not row count, row groups or compression. Cl: The entries have no example showing the returned dictionaries.
6. **[0, 0, 0, 0]** F and Co: The supplied B documentation does not describe reading variable or value labels, looking up a code, or converting such labels to a categorical. Cm and Cl: With no task-specific path or example, neither completeness nor clarity can be assessed above zero.
7. **[0, 0, 0, 0]** F and Co: The supplied B material does not cover Parquet date and timestamp conversion or writing. Cm and Cl: It provides no task-specific path, edge cases or example.
8. **[2, 3, 1, 2]** F: The Parquet guide must be located beyond the supplied front page. Cm: It gives the write call, codec choices and row group size, but the B reference does not state the default codec, map language types to Parquet types, or explain type errors. Cl: The write example is understandable but does not describe the resulting file's schema or settings.
9. **[1, 3, 0, 1]** F: File-level key-value metadata and field-level schema metadata are mentioned only in the write reference. Cm: These generic hooks do not explain a representation for variable, value and data labels or how to check them after reading. Cl: There is no label example or explanation of how to use the hooks for this task.
10. **[0, 0, 0, 0]** F and Co: The supplied B documentation says nothing about distinguishing or round-tripping these missing values. Cm and Cl: It offers no task-specific procedure or explanation; the task is stated to be unsupported.
11. **[1, 3, 1, 1]** F: The supplied reference mentions reader decryption and writer codec choices, but the Parquet guide has no interoperability section. Cm: It does not enumerate readable codecs, encodings and types, nested-type limitations, or what other tools see. Cl: There is no interoperability example or consolidated explanation.

| Task | Library A | Library B |
|---|---:|---:|
| 1 | 2.75 | 2.25 |
| 2 | 2.75 | 2.00 |
| 3 | 2.75 | 1.50 |
| 4 | 2.75 | 1.50 |
| 5 | 2.75 | 1.50 |
| 6 | 2.75 | 0.00 |
| 7 | 2.75 | 0.00 |
| 8 | 2.75 | 2.00 |
| 9 | 2.75 | 1.25 |
| 10 | 2.75 | 0.00 |
| 11 | 2.75 | 1.50 |
| **Total** | **30.25** | **13.50** |
