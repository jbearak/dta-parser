```json
{"A": {"1": [3, 3, 3, 2], "2": [3, 3, 3, 3], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 3, 2], "7": [3, 3, 2, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 3], "11": [3, 3, 3, 3]},
 "B": {"1": [3, 3, 1, 3], "2": [3, 3, 1, 2], "3": [3, 2, 1, 2], "4": [2, 3, 1, 2], "5": [2, 3, 2, 2], "6": [1, 2, 0, 1], "7": [1, 2, 1, 1], "8": [3, 3, 2, 3], "9": [1, 2, 1, 2], "10": [0, 0, 0, 0], "11": [2, 3, 1, 2]}}
```

## Reasons for scores below 3

### Library A

- **Task 1, clarity 2.** The steps are clear, but sentences such as "Develop Library A before Library A: Library A needs Library A 0.3" are hard to follow. The reader cannot tell which package is meant.
- **Task 6, clarity 2.** The example works, but terms such as "set", `dta_key` and style `:note` are explained only by pointers to other sections. A reader who does not know Stata has to follow those pointers.
- **Task 7, completeness 2.** DATE, TIMESTAMP, units, zones, naive against zoned, and the sub-millisecond error are all covered. Nothing says what happens to a date or time that is out of range for `Date` or `DateTime`.

### Library B

- **Task 1, completeness 1.** The only guidance is `Pkg.add("Parquet2")`. There are no supported platforms or Julia versions and nothing on what to do when installation fails.
- **Task 2, completeness 1.** The read calls are shown (`DataFrame(ds; copycols=false)`, `Tables.columntable`). There is no table of what each Parquet type becomes, and nothing on what is refused beyond scattered notes in the dev page.
- **Task 2, clarity 2.** The schema display shows some Julia types, but the page never says how a type is chosen or what is lost.
- **Task 3, correctness 2.** The README example calls `TableOperations.select` without a `using TableOperations`, so it fails as written. The index page does load the package.
- **Task 3, completeness 1.** Columns are selected by name only. Nothing says whether positions work, whether the order is kept, or what an unknown name does.
- **Task 3, clarity 2.** The examples do not say what comes back.
- **Task 4, findability 2.** Row groups appear in the README (`ds[1]`) and the index page, but no heading names reading a range of rows.
- **Task 4, completeness 1.** Only whole row groups can be read. There is no skip or limit, no out-of-range behaviour, and the cost is only hinted at in a note.
- **Task 4, clarity 2.** The example is brief and does not say what it gives for a row group.
- **Task 5, findability 2.** `Tables.schema(ds)` and `Parquet2.metadata(ds)` are inside code blocks on the index page, not under a heading for the task.
- **Task 5, completeness 2.** Column names and types, the row-group count (`length(ds)`) and metadata access are shown. There is no row count for the whole dataset, no compression information, and no description of the key-value metadata.
- **Task 5, clarity 2.** The schema display is shown, but `metadata(ds)` is left unexplained and its result is not described.
- **Task 6, findability 1.** Labels are not mentioned. Only the generic metadata calls are implied by examples.
- **Task 6, correctness 2.** Nothing said is wrong, but nothing is said about labels.
- **Task 6, completeness 0.** There is no variable label, no value labels, no lookup of a code's text and no categorical conversion.
- **Task 6, clarity 1.** There is no example for this task.
- **Task 7, findability 1.** Dates appear only in schema printouts, such as `Union{Missing, DateTime}`.
- **Task 7, correctness 2.** Nothing said is wrong, but it is very little.
- **Task 7, completeness 1.** Only the type name is visible. Units, time zones, out-of-range values and naive against zoned times are not covered.
- **Task 7, clarity 1.** There is no explanation, only a printed type.
- **Task 8, completeness 2.** The page shows `writefile`, the per-column `compression_codec`, partitions as row groups, `npages`, and file and column metadata. It does not give the default codec or the row group size, and it has no table mapping Julia types to Parquet types. The only error mentioned is that decimal writing is unsupported.
- **Task 9, findability 1.** Writing file-wide and per-column key-value metadata appears only as an example inside "Writing Data". Labels are never named.
- **Task 9, correctness 2.** The metadata example is plausible but is not tied to labels.
- **Task 9, completeness 1.** The mechanism for attaching key-value metadata is shown, but there is no data label, no value labels, and no read-back check.
- **Task 9, clarity 2.** The example is clear, but it does not show reading the metadata back.
- **Task 10, all four scores 0.** The documentation says nothing about `.a` to `.z`, tagged missing values, or what other tools see.
- **Task 11, findability 2.** The relevant limits are in the dev page's "Wanted Features", and the FAQ mentions files from other writers. Neither has a heading for reading another tool's file.
- **Task 11, completeness 1.** Nested columns, encryption and decimal writing are named as unsupported. There is no list of codecs, encodings or types that are read, and nothing on what other tools see in files this library writes.
- **Task 11, clarity 2.** The facts are scattered through opinionated development notes.

## Task scores (mean of the four)

| task | Library A | Library B |
|---|---|---|
| 1 | 2.75 | 2.50 |
| 2 | 3.00 | 2.25 |
| 3 | 3.00 | 2.00 |
| 4 | 3.00 | 2.00 |
| 5 | 3.00 | 2.25 |
| 6 | 2.75 | 1.00 |
| 7 | 2.75 | 1.25 |
| 8 | 3.00 | 2.75 |
| 9 | 3.00 | 1.50 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 2.00 |
| **Total** | **32.25** | **19.50** |
