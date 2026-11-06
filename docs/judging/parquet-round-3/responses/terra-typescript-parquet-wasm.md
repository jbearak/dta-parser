```json
{"A":{"1":[3,3,3,3],"2":[3,3,3,3],"3":[3,3,3,3],"4":[3,3,3,3],"5":[3,3,3,3],"6":[3,3,3,3],"7":[3,3,3,3],"8":[3,3,3,3],"9":[3,3,3,3],"10":[3,3,3,3],"11":[3,3,3,3]},"B":{"1":[3,2,2,2],"2":[3,3,1,3],"3":[1,1,1,1],"4":[1,3,1,1],"5":[2,3,2,2],"6":[0,0,0,0],"7":[1,3,1,1],"8":[3,3,1,2],"9":[1,0,0,0],"10":[0,0,0,0],"11":[2,3,1,1]}}
```

Scores are in the order findability, correctness, completeness, and clarity. I treat the supplied text as the evidence for the pinned versions; an omission alone does not make a statement incorrect.

**Library A**

1. **Install — 3, 3, 3, 3.** The linked install section gives the build and install steps, requirements, platforms, versions, and troubleshooting.
2. **Read a whole file — 3, 3, 3, 3.** The guide shows the reader and its results, with a type table and limitations.
3. **Read columns — 3, 3, 3, 3.** It covers names, indices, order, and an unknown name with an example.
4. **Read rows — 3, 3, 3, 3.** It covers windows, range errors, pages, row groups, and caching.
5. **Schema and metadata — 3, 3, 3, 3.** The footer example and field table cover the requested information before data reads.
6. **Use labels — 3, 3, 3, 3.** The guide explains label sets and shows lookup and conversion to a dictionary column.
7. **Dates and timestamps — 3, 3, 3, 3.** It describes units, zones, precision, range and the distinction between clock times and instants, with examples.
8. **Write a table — 3, 3, 3, 3.** The guide includes the call, type mappings, defaults, options and errors.
9. **Write labels — 3, 3, 3, 3.** A complete example writes and reads back variable, value and data labels.
10. **Keep missing letters — 3, 3, 3, 3.** The example distinguishes the codes and round-trips them; the guide explains what other tools see.
11. **Files from other tools — 3, 3, 3, 3.** The guide lists codecs, encodings, types and exclusions, and links to other readers' results.

**Library B**

1. **Install — 3, 2, 2, 2.** Correctness: the Node section says to use the Node entry point but its `require` example names the default entry point; the documented `/node` path is an obvious correction. Completeness: it gives commands, entry points and a Node polyfill note, but no supported TypeScript versions or general installation-failure guidance. Clarity: the conflicting Node entry-point example requires rereading.
2. **Read a whole file — 3, 3, 1, 3.** Completeness: the example gives the read and Arrow table conversion, but no mapping for each Parquet type or account of all losses and refusals.
3. **Read columns — 1, 1, 1, 1.** Findability: the `columns` option appears in function and class reference entries, without a task pointer from the guide. Correctness: the reference presents it for synchronous `readParquet`, while the supplied comparison says that version ignores it, which can give the wrong result. Completeness: names are mentioned, but order, missing names and positional selection are not explained. Clarity: there is no selection example and the sync behavior conflicts with the comparison.
4. **Read rows — 1, 3, 1, 1.** Findability: offset, limit and row-group options are in reference entries rather than a guide pointer for this task. Completeness: the main options are named, but out-of-range behavior and the cost of a range are not explained. Clarity: there is no worked range example.
5. **Schema and metadata — 2, 3, 2, 2.** Findability: the front page points to schema and `ParquetFile` references, but the metadata methods must be sought in the reference. Completeness: row counts, groups, codecs and key-value metadata are exposed, but the type-conversion mapping is absent. Clarity: the schema example helps, but the metadata traversal has no worked example.
6. **Use labels — 0, 0, 0, 0.** Generic schema metadata is mentioned, but the supplied documentation gives no path for identifying variable or value labels, looking up a code, or converting labelled values to a categorical; the task is not covered.
7. **Dates and timestamps — 1, 3, 1, 1.** Findability: dates appear in the general read/write example rather than a task entry. Completeness: the example shows a date-like Arrow type, but not timestamp units, zones, range handling or naive versus zoned times. Clarity: there is no explanation or worked timestamp example.
8. **Write a table — 3, 3, 1, 2.** Completeness: the example writes an Arrow table and sets compression, and the reference names row-group controls, but it does not state the default codec or type mappings and errors. Clarity: the example gives a path but does not describe the resulting Parquet schema or output.
9. **Write labels — 1, 0, 0, 0.** Findability: only generic key-value and schema metadata setters are in the reference. They do not specify how to attach and check the requested labels, so the task is not covered for correctness, completeness or clarity.
10. **Keep missing letters — 0, 0, 0, 0.** The supplied documentation does not discuss distinguishing or round-tripping these values or what other tools see; the task is not covered.
11. **Files from other tools — 2, 3, 1, 1.** Findability: compression has a README heading, but the rest requires searching the reference. Completeness: the codec list is useful, but the docs do not establish the full read encoding and type support, encryption limits, or what other tools see in written files; the encoding enum alone does not establish reader support. Clarity: there is no interoperability example or consolidated explanation of those limits.

| Task | Library A mean | Library B mean |
|---|---:|---:|
| 1 | 3.00 | 2.25 |
| 2 | 3.00 | 2.50 |
| 3 | 3.00 | 1.00 |
| 4 | 3.00 | 1.50 |
| 5 | 3.00 | 2.25 |
| 6 | 3.00 | 0.00 |
| 7 | 3.00 | 1.50 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 0.25 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 1.75 |
| **Total** | **33.00** | **15.25** |
