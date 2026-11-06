```json
{"A": {"1": [3, 3, 3, 2], "2": [3, 3, 3, 3], "3": [3, 3, 2, 3], "4": [3, 3, 2, 3], "5": [3, 3, 2, 3], "6": [3, 3, 3, 3], "7": [3, 3, 2, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 3], "11": [3, 2, 3, 3]},
 "B": {"1": [3, 3, 1, 3], "2": [3, 3, 2, 2], "3": [2, 3, 2, 2], "4": [2, 3, 1, 2], "5": [3, 3, 3, 2], "6": [0, 0, 0, 0], "7": [1, 2, 1, 1], "8": [3, 3, 2, 3], "9": [1, 2, 1, 1], "10": [0, 0, 0, 0], "11": [3, 2, 2, 2]}}
```

Scores are given as findability, correctness, completeness, clarity. I give a reason for every score below 3.

## Library A

**Task 1, Install: 3, 3, 3, 2**
- Clarity 2: Several packages are named, and the roles blur. The R Install section covers dtatools, dtaparser and datakit. The Parquet install section says only "nothing beyond Library A", so the reader has to work out which package to install for Parquet.

**Task 2, Read a whole file: 3, 3, 3, 3**
- There is a call with a runnable example and its results. A type table covers each Parquet type and what is refused (nested columns, FLOAT16, INTERVAL, and so on). Options for int64, decimal and timestamps are described.

**Task 3, Read some columns: 3, 3, 2, 3**
- Completeness 2: R takes names or tidyselect, order is kept, and an unknown name is an error that lists the columns. Selecting by position is not stated for R. Only the Python error table mentions it.

**Task 4, Read a range of rows: 3, 3, 2, 3**
- Completeness 2: `skip` and `n_max` are described, and the cost is stated (only the row groups and pages that hold the rows are read). What an out-of-range `skip` or `n_max` does is not said.

**Task 5, Schema and metadata without the data: 3, 3, 2, 3**
- Completeness 2: `read_parquet_info()` gives rows, row groups, codecs, data label and notes, and per-column types. It does not show a general key-value metadata listing, only the `dta` entry's contents.

**Task 6, Value labels and variable labels: 3, 3, 3, 3**
- `var_label()`, `val_labels()` and `val_label()` are shown with results. `factors = TRUE` gives the categorical type, and the trade-off for `.a` to `.z` is explained.

**Task 7, Dates and timestamps: 3, 3, 2, 3**
- Completeness 2: DATE becomes `Date`. TIMESTAMP becomes `POSIXct` in microseconds, with the zone kept, and the zone order is stated (profile, then `ARROW:schema`, then UTC). A nanosecond error and a fractional-date case are covered. A timestamp not adjusted to UTC from another tool is never contrasted with a zoned one, and out-of-range values get little attention.

**Task 8, Write a table: 3, 3, 3, 3**
- Covers the call, snappy as the default, the other codecs and levels, and row group size (default 262,144 rows or about 1 GiB). The R-to-Parquet type table and the list of error cases are complete.

**Task 9, Write labels and check them: 3, 3, 3, 3**
- A worked example attaches a variable label, value labels, a data label and notes, then reads them back with output shown. The rules for shared label sets are given.

**Task 10, Keep `.a` to `.z`: 3, 3, 3, 3**
- Covers the tagged-NaN encoding, `na_tag()` to tell `.` from `.a`, and the round trip. It also covers `missing_letters = FALSE`, and what DuckDB, polars and arrow see, with a query that treats them as missing.

**Task 11, Read a file another tool wrote: 3, 2, 3, 3**
- Correctness 2: The docs contradict each other on encodings. `r.md` says every encoding is read, while the errors table says BIT_PACKED is "not read yet". `parquet.md` also says "every encoding... other tools write by default". This is a small inconsistency.

## Library B

**Task 1, Install: 3, 3, 1, 3**
- Completeness 1: Only `install.packages("nanoparquet")`. No platforms, R versions or failure advice are given.

**Task 2, Read a whole file: 3, 3, 2, 2**
- Completeness 2: The call, the `data.frame` return and the `read_int64_type` and Arrow-metadata (factor) options are given. The per-type mapping is only a link ("nanoparquet-types") or something to discover with `read_parquet_schema()`.
- Clarity 2: The examples show no output or description of what comes back.

**Task 3, Read only some columns: 2, 3, 2, 2**
- Findability 2: The README bullet says only "can read a subset of columns". How to do it is in the `read_parquet` man page, with no README example.
- Completeness 2: Names or indices are accepted, order follows `col_select`, and duplicates are an error. What happens with a name not in the file is not stated.
- Clarity 2: There is no example.

**Task 4, Read a range of rows: 2, 3, 1, 2**
- Findability 2: Only the slide deck says "Cannot read a subset of the rows" (and lists it under future plans). The README is silent.
- Completeness 1: The limit is stated, but there is no workaround and nothing on cost.
- Clarity 2: It is a one-line bullet with no example.

**Task 5, Schema and metadata: 3, 3, 3, 2**
- Clarity 2: The README has an "Inspect" section naming three functions. The man pages are thorough but dense, with typo-like names such as `repettion_type`. The examples show no output.

**Task 6, Value labels and variable labels: 0, 0, 0, 0**
- The documentation does not mention variable or value labels. Factor reading through Arrow metadata is documented, but only as type detection, not as labels.

**Task 7, Dates and timestamps: 1, 2, 1, 1**
- Findability 1: Only a README bullet ("temporal types"), a `difftime` option note and a slide list of logical types.
- Correctness 2: What is stated is not wrong, but it is minimal.
- Completeness 1: There is nothing on units, time zones, naive versus zoned times or out-of-range values. The mapping is a link.
- Clarity 1: There is no example.

**Task 8, Write a table: 3, 3, 2, 3**
- Completeness 2: The compression codecs and default, encodings, row group size (default 122,880) and errors for bad encodings are documented. The type mapping is only via `infer_parquet_schema()` and a link, with no table.

**Task 9, Write labels and check them: 1, 2, 1, 1**
- Findability 1: Labels are not mentioned. The only route is the `metadata` argument of `write_parquet()` and the `key_value_metadata` in `read_parquet_metadata()`.
- Correctness 2: What is said is true, but it is not presented as a label route.
- Completeness 1: No labels, only generic key-value metadata.
- Clarity 1: There is no example.

**Task 10, Keep `.a` to `.z`: 0, 0, 0, 0**
- Not covered. The docs only say Parquet has built-in missing-value support.

**Task 11, Read a file another tool wrote: 3, 2, 2, 2**
- Correctness 2: The docs disagree. The README and slides say nested types and LIST are unsupported, while the list-columns article reads flat LIST columns from other tools.
- Completeness 2: Limitations are listed (compression codecs, encryption, nested types, INTERVAL and UNKNOWN). The type list is a link, and what other tools see in files this library writes is only hinted at (Arrow metadata, factors).
- Clarity 2: The limitation lists are clear, but there are no examples, and the README and slide deck lists differ.

## Task scores

| Task | A | B |
|---|---|---|
| 1 Install | 2.75 | 2.50 |
| 2 Read whole file | 3.00 | 2.50 |
| 3 Read some columns | 2.75 | 2.25 |
| 4 Read a range of rows | 2.75 | 2.00 |
| 5 Schema and metadata | 2.75 | 2.75 |
| 6 Value and variable labels | 3.00 | 0.00 |
| 7 Dates and timestamps | 2.75 | 1.25 |
| 8 Write a table | 3.00 | 2.75 |
| 9 Write labels and check | 3.00 | 1.25 |
| 10 Keep `.a` to `.z` | 3.00 | 0.00 |
| 11 Read another tool's file | 2.75 | 2.25 |
| **Total** | **31.50** | **19.50** |
