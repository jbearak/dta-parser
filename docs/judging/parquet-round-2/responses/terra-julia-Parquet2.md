```json
{"A":{"1":[3,3,1,2],"2":[3,3,1,3],"3":[3,2,1,2],"4":[1,3,1,2],"5":[2,3,1,2],"6":[0,0,0,0],"7":[0,0,0,0],"8":[3,3,1,3],"9":[0,0,0,0],"10":[0,0,0,0],"11":[2,3,1,1]},"B":{"1":[2,3,3,3],"2":[2,1,3,2],"3":[2,3,3,3],"4":[2,3,3,3],"5":[2,3,3,3],"6":[2,3,3,3],"7":[2,2,2,3],"8":[2,3,3,3],"9":[2,3,3,3],"10":[2,3,3,3],"11":[2,1,3,2]}}
```

Scores are in the order findability (F), correctness (Co), completeness (Cm), and clarity (Cl). Correctness is judged against the evidence in the bundle; where it supplies no independent version evidence, the score reflects the statements and examples available there.

### Library A

1. **F 3, Co 3, Cm 1, Cl 2.** Cm: The installation command is given, but supported platforms, Julia versions and installation-failure advice are absent. Cl: The command is concise, but its result is not described.
2. **F 3, Co 3, Cm 1, Cl 3.** Cm: The DataFrame path and schema example are present, but a comprehensive Parquet-to-Julia type mapping and losses or refusals are missing.
3. **F 3, Co 2, Cm 1, Cl 2.** Co: The README's selection example uses `TableOperations` without loading it; the guide supplies the missing import. Cm: Names and selective loading are shown, but selection order, positions and unknown-name behavior are not explained. Cl: The example states which columns are loaded but does not show its result.
4. **F 1, Co 3, Cm 1, Cl 2.** F: Row-group selection is illustrated in basic usage, but no heading names reading a range of rows. Cm: Indexing a row group and the cost of loading columns are covered, but out-of-range behavior and a general row window are not. Cl: The example does not show the selected data.
5. **F 2, Co 3, Cm 1, Cl 2.** F: The reader must search the guide's dataset and data-access sections for the metadata and schema calls. Cm: Schema, row groups and auxiliary metadata are shown, but a complete recipe for row count, codecs and footer entries is missing. Cl: The metadata calls do not show their results.
6. **F 0, Co 0, Cm 0, Cl 0.** The supplied A documentation does not explain how to read or use value labels and variable labels, or make a categorical column from them.
7. **F 0, Co 0, Cm 0, Cl 0.** The supplied A documentation does not provide a date and timestamp read/write guide. A timestamp in a displayed schema is not an explanation of the task.
8. **F 3, Co 3, Cm 1, Cl 3.** Cm: The write call, per-column codec option and partition-based row groups are shown, but the A documentation does not give the default codec, a full type mapping or errors.
9. **F 0, Co 0, Cm 0, Cl 0.** General key-value metadata examples do not explain how to attach value labels, variable labels and a data label and check them after reading.
10. **F 0, Co 0, Cm 0, Cl 0.** The A documentation does not describe preserving or distinguishing these missing-value codes. The task statement says A cannot perform this task.
11. **F 2, Co 3, Cm 1, Cl 1.** F: The development notes discuss unsupported features, but the reader must search for them. Cm: Nested columns and encryption are identified as wanted features, without a complete list of readable codecs, encodings and types or a description of what other tools see. Cl: The discussion is framed as development notes and has no interoperability example.

### Library B

For all B tasks, **F 2**: the README links to the Parquet task index and the Julia guide, but reaching an individual task's answer requires navigating the longer guide or following further links.

1. **F 2, Co 3, Cm 3, Cl 3.** The Julia install section gives versions, platforms, commands, build requirements and troubleshooting.
2. **F 2, Co 1, Cm 3, Cl 2.** Co: The type table says every conversion is exact or an error, while it also says DECIMAL defaults to the nearest `Float64`; that can mislead readers about precision. Cl: The main example is clear, but understanding all conversions and exceptions requires moving among several sections.
3. **F 2, Co 3, Cm 3, Cl 3.** Names, positions, order and invalid selections are described with examples.
4. **F 2, Co 3, Cm 3, Cl 3.** The guide shows skip and limit, an out-of-range request and the pages and row groups read.
5. **F 2, Co 3, Cm 3, Cl 3.** The footer-only call and the requested schema and metadata fields are shown with output.
6. **F 2, Co 3, Cm 3, Cl 3.** The guide shows both label kinds, lookup by code and a categorical conversion with its resulting levels.
7. **F 2, Co 2, Cm 2, Cl 3.** Co: The type table says a timestamp without a supplied zone becomes UTC with a warning, while the date section says an unzoned clock time is read as written; the latter distinction matters. Cm: Units, zones, precision and naive versus zoned times are discussed, but the behavior of dates or timestamps outside the representable range is not specified.
8. **F 2, Co 3, Cm 3, Cl 3.** The guide gives the call, defaults, options, type mappings and unsupported-type errors.
9. **F 2, Co 3, Cm 3, Cl 3.** A complete example sets the three kinds of labels and reads them back.
10. **F 2, Co 3, Cm 3, Cl 3.** The documentation explains the per-value codes, round trip, optional loss of letters and what other tools see.
11. **F 2, Co 1, Cm 3, Cl 2.** Co: The Julia guide says it reads every encoding, but the shared errors section explicitly identifies `BIT_PACKED` values as unsupported; a reader could rely on the broader claim incorrectly. Cl: The worked examples are useful, but the encoding qualification and other-tool results require reading separate sections.

| Task | A mean | B mean |
|---:|---:|---:|
| 1 | 2.25 | 2.75 |
| 2 | 2.50 | 2.00 |
| 3 | 2.00 | 2.75 |
| 4 | 1.75 | 2.75 |
| 5 | 2.00 | 2.75 |
| 6 | 0.00 | 2.75 |
| 7 | 0.00 | 2.25 |
| 8 | 2.50 | 2.75 |
| 9 | 0.00 | 2.75 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 2.00 |
| **Total** | **14.75** | **28.25** |
