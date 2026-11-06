```json
{"A":{"1":[3,3,3,3],"2":[3,3,3,3],"3":[3,3,3,3],"4":[3,3,3,3],"5":[3,3,3,3],"6":[3,3,2,3],"7":[3,3,2,3],"8":[3,3,3,3],"9":[3,3,3,3],"10":[3,3,3,3],"11":[3,3,3,3]},"B":{"1":[3,3,1,2],"2":[2,3,1,2],"3":[3,2,1,2],"4":[2,3,1,2],"5":[2,3,1,2],"6":[0,0,0,0],"7":[1,3,1,1],"8":[3,3,1,2],"9":[1,3,1,1],"10":[0,0,0,0],"11":[2,3,1,1]}}
```

Scores are in the order findability (F), correctness (Co), completeness (Cm), and clarity (Cl). Correctness reflects the evidence in the supplied material; omissions are scored under completeness.

### Library A

1. **Install — 3, 3, 3, 3.** The linked install instructions give the commands, requirements and troubleshooting.
2. **Read a whole file — 3, 3, 3, 3.** The guide gives the call, result, type table and conversion limits.
3. **Read columns — 3, 3, 3, 3.** The guide covers names, positions, order and invalid selections.
4. **Read rows — 3, 3, 3, 3.** The guide explains the window, past-end result and page-level reading cost.
5. **Schema and metadata — 3, 3, 3, 3.** The footer-only example covers schema, row groups, codecs and key-value entries.
6. **Use labels — 3, 3, 2, 3.** Cm: The categorical recipe assumes every observed code has a label; it does not explain how to handle unlabelled codes or missing values.
7. **Dates and timestamps — 3, 3, 2, 3.** Cm: Units, precision, zones and naive versus zoned times are explained, but the Julia section does not give a clear rule for date or timestamp values outside the representable range.
8. **Write a table — 3, 3, 3, 3.** The guide gives the call, defaults, mappings and errors.
9. **Write and check labels — 3, 3, 3, 3.** A complete example attaches and reads back all three kinds of label.
10. **Keep `.a` to `.z` — 3, 3, 3, 3.** The guide shows codes and round trips, explains the lossy option and describes other tools' interpretation.
11. **Other tools' files — 3, 3, 3, 3.** The guide lists supported encodings and codecs, exclusions and the interpretation of its own files by other tools.

### Library B

1. **Install — 3, 3, 1, 2.** Cm: The install command is present, but supported Julia versions, platforms and failure remedies are absent. Cl: The command is understandable, but no result or troubleshooting example is given.
2. **Read a whole file — 2, 3, 1, 2.** F: The README example is under the broad “Basic Usage” heading, so the reader must find the relevant lines. Cm: It gives the DataFrame path but no comprehensive Parquet-to-Julia type mapping or account of loss and refusal. Cl: The example is understandable but does not show its resulting table.
3. **Read columns — 3, 2, 1, 2.** Co: The README uses `TableOperations.select` without importing `TableOperations`; the guide supplies the missing import. Cm: It demonstrates names and individual-column access, but does not specify selected-column order or the result of an unknown name. Cl: The selection example does not show the resulting frame.
4. **Read rows — 2, 3, 1, 2.** F: Row-group access appears in general usage and dataset sections rather than a heading for reading a row range. Cm: A row group can be selected and the cost is discussed, but out-of-range behavior and arbitrary skip/limit are not explained. Cl: The example identifies the first group but does not show the resulting DataFrame.
5. **Schema and metadata — 2, 3, 1, 2.** F: The reader must find schema and metadata calls within the dataset and access sections. Cm: The examples show schema, row-group counts and metadata access, but do not explain a complete footer-only route to total rows and compression. Cl: Some schema and row-group output is shown, but the metadata call has no example result.
6. **Use labels — 0, 0, 0, 0.** F: No label-specific guide or reference is present. Co and Cm: Generic metadata access does not explain variable labels, value-label lookup or categorical conversion. Cl: There is no example explaining those concepts or operations.
7. **Dates and timestamps — 1, 3, 1, 1.** F: A timestamp's `DateTime` result is only implied by displayed schema output. Cm: The documentation does not give a date/timestamp read-write recipe, units, zone rules or range behavior. Cl: There is no date or timestamp example explaining its result.
8. **Write a table — 3, 3, 1, 2.** Cm: The write call, per-column codec example and partition-based row groups are shown, but the default codec, type mappings and errors are not specified. Cl: The example is readable but does not show a readback or resulting schema.
9. **Write and check labels — 1, 3, 1, 1.** F: Only generic file and column metadata examples imply a possible route. Cm: They do not define a label convention or show attaching and checking variable, value and data labels. Cl: The examples use arbitrary metadata and do not explain labels or show a readback result.
10. **Keep `.a` to `.z` — 0, 0, 0, 0.** F: No task-specific material is present in Library B's documentation. Co and Cm: It gives no method or limitation for preserving the distinctions. Cl: There is no explanation or example of the missing-value codes.
11. **Other tools' files — 2, 3, 1, 1.** F: Relevant limitations are scattered across the development notes and general guide. Cm: Nested columns and encryption appear as wanted features, but there is no supported-codec and encoding inventory or account of what other tools see in written files. Cl: There is no focused interoperability example with an explained result.

| Task | A | B |
|---|---:|---:|
| 1 | 3.00 | 2.25 |
| 2 | 3.00 | 2.00 |
| 3 | 3.00 | 2.00 |
| 4 | 3.00 | 2.00 |
| 5 | 3.00 | 2.00 |
| 6 | 2.75 | 0.00 |
| 7 | 2.75 | 1.50 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 1.50 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 1.75 |
| **Total** | **32.50** | **17.25** |
