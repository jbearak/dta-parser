```json
{"A": {"1": [2,3,2,3], "2": [2,2,2,2], "3": [2,3,1,3], "4": [0,0,0,0], "5": [0,0,0,0], "6": [0,0,0,0], "7": [1,2,1,1], "8": [2,2,2,3], "9": [0,0,0,0], "10": [0,0,0,0], "11": [2,2,1,2]},
 "B": {"1": [3,2,3,3], "2": [3,3,3,3], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,3,3,3], "7": [3,3,3,3], "8": [3,3,3,3], "9": [3,3,3,3], "10": [3,3,3,2], "11": [3,3,3,3]}}
```

Scores are in the order findability, correctness, completeness, clarity. Only scores below 3 have a reason.

## Library A

**Task 1, install: [2,3,2,3]**
- Findability 2: the front page links to "Getting started", and the install page is one more step in. The Parquet extra is only a line in the "Other data sources" table.
- Completeness 2: the install commands, dependency tables and the `pandas[parquet]` extra are there. Python versions are delegated to a "support policy" page that is not shown. Nothing says what to do when installation fails, apart from "test failures are not necessarily a broken install".

**Task 2, read a whole file: [2,2,2,2]**
- Findability 2: the path is front page, then user guide, then the long I/O page, then the Parquet section. The API entry for `read_parquet` is a second route.
- Correctness 2: the API page says the function "requires the pyarrow library", but the guide and `to_parquet` say pyarrow or fastparquet. The guide says fastparquet is a fallback, while the API page says it is deprecated in 3.1.0. These are small contradictions.
- Completeness 2: the call and the returned DataFrame are covered. `dtype_backend` and the caveats are covered too: categoricals of non-string type come back as their primitive type, object types are refused, and duplicate column names are not supported. There is no table of what each Parquet type becomes, and nested columns and encryption are not mentioned.
- Clarity 2: the guide examples are bare `result.dtypes` calls with no output shown, so what the dtypes become is left to the reader. The API example does show its output.

**Task 3, read some columns: [2,3,1,3]**
- Findability 2: it is one example in the Parquet section (`columns=["a","b"]`). No heading names it.
- Completeness 1: only the main path is shown. Nothing says whether order is kept, whether positions work, or what a missing name does.

**Task 4, read a range of rows: [0,0,0,0]**
- Nothing for Parquet says how to skip or limit rows. `filters` prunes row groups by value, which is not a row range. `limit` appears only for Iceberg.

**Task 5, schema and metadata without the data: [0,0,0,0]**
- Not covered. There is no call that reads the footer, and row count, row groups and key-value metadata are not mentioned.

**Task 6, value and variable labels: [0,0,0,0]**
- Not covered. There is no mention of variable labels, value labels or code lookup. The `Categorical` columns in the example are not value labels.

**Task 7, dates and timestamps: [1,2,1,1]**
- Findability 1: the only place is the example frame, which has `date_range` and a `tz="US/Eastern"` column. A sentence says "datetime with timezone" is supported.
- Correctness 2: what is stated is not wrong, but it is very thin.
- Completeness 1: units, out-of-range values and the naive versus zoned distinction are not covered.
- Clarity 1: there is no example showing the result of a round trip.

**Task 8, write a table: [2,2,2,3]**
- Findability 2: the `to_parquet` guide snippet and the API entry both cover it, but there is no heading for the task.
- Correctness 2: the `filesystem` parameter of `to_parquet` is described as being for "reading the parquet file", which looks copied from the reader.
- Completeness 2: the write call, the compression options and the `snappy` default are covered. Row group size is not mentioned. The type map is not given, and only object types and duplicate column names are named as errors.

**Task 9, write labels and check them: [0,0,0,0]**
- Not covered.

**Task 10, keep `.a` to `.z`: [0,0,0,0]**
- Not covered.

**Task 11, read a file another tool wrote: [2,2,1,2]**
- Findability 2: it is scattered across the caveats list and the notes on the index column.
- Correctness 2: the same pyarrow and fastparquet contradiction as in task 2.
- Completeness 1: only the engine choice and directory paths are covered. Codecs, encodings, nested columns and encryption are not listed. The only comment on what other tools see is the extra index column that can trip up non-pandas readers (Redshift).
- Clarity 2: the facts have to be pieced together from several caveats.

## Library B

**Task 1, install: [3,2,3,3]**
- Correctness 2: `docs/parquet.md` says "Nothing beyond the package". The Python page needs a Rust toolchain and a C compiler. The Python page also says wheels are built for several platforms while saying the package is not on PyPI, which is unclear.

**Task 10, keep `.a` to `.z`: [3,3,3,2]**
- Clarity 2: there are two mechanisms (`meta.missing` and companion columns), several traps and "tagged NaN" terms. The reader has to hold them together across several sections. The examples do show their output.

All other Library B scores are 3.

## Task scores

| task | A | B |
|---|---|---|
| 1 | 2.50 | 2.75 |
| 2 | 2.00 | 3.00 |
| 3 | 2.25 | 3.00 |
| 4 | 0.00 | 3.00 |
| 5 | 0.00 | 3.00 |
| 6 | 0.00 | 3.00 |
| 7 | 1.25 | 3.00 |
| 8 | 2.25 | 3.00 |
| 9 | 0.00 | 3.00 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 3.00 |
| **Total** | **12.00** | **32.50** |
