```json
{"A": {"1": [3, 3, 1, 3], "2": [3, 3, 2, 2], "3": [3, 2, 1, 2], "4": [2, 2, 1, 2], "5": [2, 3, 2, 2], "6": [1, 2, 1, 1], "7": [1, 2, 0, 1], "8": [3, 3, 2, 3], "9": [2, 2, 1, 2], "10": [0, 0, 0, 0], "11": [1, 3, 1, 2]},
 "B": {"1": [3, 3, 3, 2], "2": [3, 3, 3, 3], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 3, 2], "7": [3, 3, 2, 2], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 2], "11": [3, 2, 3, 3]}}
```

## Reasons for every score below 3

### Library A

**Task 1 (Install)**
- Completeness 1: only `Pkg.add("Parquet2")` is given. There are no supported platforms or Julia versions and nothing on what to do if installation fails.

**Task 2 (Read a whole file)**
- Completeness 2: the read call, the returned type (DataFrame, NamedTuple of columns), `copycols`, and the parallel-loading and mmap options are covered. There is no table of what each Parquet type becomes. What is lost or refused (nested columns, encryption, decimals) appears only in the "wanted features" notes of the development page.
- Clarity 2: the schema printouts show the Julia types, but the page never says in words how types map. The reader has to infer it from the examples.

**Task 3 (Read some columns)**
- Correctness 2: the README example uses `TableOperations.select` after only `using Parquet2, Tables, DataFrames`, so it needs an obvious `using TableOperations`. The index page example does load it.
- Completeness 1: only selecting by `Symbol` is shown. Nothing is said about positions, whether the order given is kept, or what happens with a name that is not in the file.
- Clarity 2: the examples are short and commented but show no output. The `Parquet2.select` shortcut is asserted without explanation.

**Task 4 (Read a range of rows)**
- Findability 2: the only route is `ds[1]` (row groups) in the README and the "Initialing a Dataset" section. No heading names row selection.
- Correctness 2: the index page says RowGroups "typically correspond to files", yet its own example shows one small file holding two row groups. That is a small inconsistency.
- Completeness 1: only whole row groups can be loaded. There is no skip/limit, no word on out-of-range indexes, and little on cost beyond a general "expensive" note.
- Clarity 2: the row-group diagram is clear, but nothing explains how to get a specific range of rows.

**Task 5 (Schema and metadata)**
- Findability 2: `Tables.schema(ds)` is in the README. The schema display and `metadata` calls sit in the middle of long pages under headings that do not name the task.
- Completeness 2: column names, Julia types, and per-row-group row counts (printed with each RowGroup) are covered. Compression is only a function name in the API list. There is no total row count and no explanation of what the key-value metadata contains.
- Clarity 2: the schema printout is clear. `Parquet2.metadata(...)` is called "auxiliary metadata" with no example output.

**Task 6 (Value and variable labels)**
- Findability 1: only the generic `Parquet2.metadata(ds)` and `metadata(column)` calls could serve, and they are implied by an example. Labels are never mentioned.
- Correctness 2: what is shown is true, but nothing claims or shows labels.
- Completeness 1: there is no variable label, value-label lookup or categorical conversion, only a generic key-value read.
- Clarity 1: no example shows labels, so the reader has to work out that generic metadata could carry them.

**Task 7 (Dates and timestamps)**
- Findability 1: the only trace is the schema display showing `DateTime`.
- Correctness 2: nothing wrong is stated, but there is very little.
- Completeness 0: nothing on DATE, units, time zones, out-of-range values or naive versus zoned times. Only the `DateTime` type is visible in a printout.
- Clarity 1: no explanation or example.

**Task 8 (Write a table)**
- Completeness 2: `writefile`, per-column `compression_codec`, `npages` and row groups via `Tables.partitions` are covered. The default codec is not stated, there is no Julia-to-Parquet type table, and the errors (beyond "decimals unsupported" in the development notes) are not listed.

**Task 9 (Write labels and check them)**
- Findability 2: the `column_metadata` and `metadata` keywords appear in a general writing example, not under a labels heading.
- Correctness 2: the keywords work as shown, but the docs never say they carry labels, and there is no value-label support.
- Completeness 1: generic key-value metadata per column and per file stands in for variable and data labels. There are no value labels and no read-back example.
- Clarity 2: the metadata example is understandable, but it has no stated link to labels and no output.

**Task 10 (Keep `.a` to `.z`)**
- All four scores 0: the documentation has nothing on Stata missing values or on distinguishing `.` from `.a` to `.z`.

**Task 11 (Read a file another tool wrote)**
- Findability 1: the facts are scattered in the development notes (nested columns, encryption, decimal writing, "more compression types") and in the FAQ's mention of Spark. No section or pointer covers this task.
- Completeness 1: it names a few unsupported items (nested columns, encryption). It does not list which codecs, encodings and types are read, and it says nothing about what other tools see in files this library writes.
- Clarity 2: the notes are frank and readable, but they are opinion and "wanted features" prose rather than a statement of support.

### Library B

**Task 1 (Install)**
- Clarity 2: the text names the two packages in ways that are hard to tell apart ("Develop Library B before Library B"). The reader must follow an order of installs, a Rust build and an unregistered dependency.

**Task 6 (Value and variable labels)**
- Clarity 2: `dta_key`, `DtaColumn` and the "set" of value labels are explained in other sections. In the labels section, the reader has to infer that a label dictionary is keyed by `dta_key` values.

**Task 7 (Dates and timestamps)**
- Completeness 2: dates, `DateTime` in milliseconds, zoned times, the naive versus zoned difference, INT96, TIME and the `:truncate` option are all covered. Values out of range for `Date` or `DateTime` are not discussed in the Julia text.
- Clarity 2: the paragraph on date columns holding `.a` to `.z` is dense. It uses Stata `%td` and `%tc` formats and the "days since 1960" convention with only brief explanation.

**Task 10 (Keep `.a` to `.z`)**
- Clarity 2: the Julia section leans on terms like "tagged NaNs" and "the bits R holds them in". The numeric codes (1 is `.`, 2 to 27 are `.a` to `.z`) are given in another section.

**Task 11 (Read a file another tool wrote)**
- Correctness 2: the Julia text says `read_parquet` reads "every encoding", but the error table in docs/parquet.md says BIT_PACKED values are not read. The parenthetical list of encodings leaves BIT_PACKED out, so the claim overreaches slightly.

## Task scores (mean of the four)

| task | Library A | Library B |
|---|---|---|
| 1 Install | 2.50 | 2.75 |
| 2 Read a whole file | 2.50 | 3.00 |
| 3 Read some columns | 2.00 | 3.00 |
| 4 Read a range of rows | 1.75 | 3.00 |
| 5 Schema and metadata | 2.25 | 3.00 |
| 6 Value and variable labels | 1.25 | 2.75 |
| 7 Dates and timestamps | 1.00 | 2.50 |
| 8 Write a table | 2.75 | 3.00 |
| 9 Write labels and check them | 1.75 | 3.00 |
| 10 Keep `.a` to `.z` | 0.00 | 2.75 |
| 11 Read a file another tool wrote | 1.75 | 2.75 |
| **Total (of 33)** | **19.50** | **31.50** |
