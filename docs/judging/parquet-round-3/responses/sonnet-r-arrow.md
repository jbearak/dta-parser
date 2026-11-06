```json
{"A": {"1": [3, 2, 3, 3], "2": [2, 3, 1, 2], "3": [2, 3, 2, 3], "4": [1, 3, 1, 2], "5": [1, 3, 1, 2], "6": [1, 2, 1, 1], "7": [1, 3, 1, 2], "8": [2, 3, 2, 3], "9": [2, 3, 2, 2], "10": [0, 0, 0, 0], "11": [1, 2, 1, 1]},
 "B": {"1": [3, 3, 3, 2], "2": [3, 3, 3, 2], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 2, 3], "7": [3, 3, 2, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 3], "11": [3, 3, 3, 3]}}
```

Scores are in the order findability, correctness, completeness, clarity. Library A's bundle is the README, the install, read/write and metadata articles, and function pages for `read_parquet`, `write_parquet`, `ParquetFileReader`, `open_dataset` and `schema`. Library B's bundle is the README, `docs/parquet.md`, the R page and its function pages.

## Library A

**Task 1 (install): 3, 2, 3, 3**
- Correctness 2: the README says C++20 is required "as of version 23.0.0", but the install article says "as of version 22.0.0".
- Correctness 2: the install article refers to "method 2" and "Method 1b", which no longer exist.
- Correctness 2: the README's conda command uses `--strict-channel-priority`, which the install article says causes very long solve times.

**Task 2 (read a whole file): 2, 3, 1, 2**
- Findability 2: the answer is a section of the read/write article, reached from the README by a link.
- Completeness 1: it shows only the `read_parquet()` call and the `as_data_frame` choice. It says nothing about what each Parquet type becomes in R, or what is lost or refused. A data types article is linked but not included.
- Clarity 2: the example is clear, but the result is not described.

**Task 3 (read some columns): 2, 3, 2, 3**
- Findability 2: it is one paragraph in the Parquet section of a long article, with no heading of its own.
- Completeness 2: it covers names and tidyselect. It does not say whether column order is kept, whether positions work, or what a name not in the file does.

**Task 4 (read a range of rows): 1, 3, 1, 2**
- Findability 1: row groups appear only on the `ParquetFileReader` function page, with no pointer from the guide.
- Completeness 1: it lists `ReadRowGroup` and `ReadRowGroups` (0-based) and `num_row_groups`. There is no skip or limit, nothing on out-of-range requests, and nothing on cost.
- Clarity 2: the methods are described plainly, but no example reads a row group.

**Task 5 (schema and metadata without the data): 1, 3, 1, 2**
- Findability 1: `GetSchema()` and the `num_rows` and `num_row_groups` bindings are only in the function page. The metadata article is about in-memory Table schemas and never says how to read a Parquet footer.
- Completeness 1: no compression, no file key-value entries, and no statement of what each column will become in R.
- Clarity 2: the example prints a schema, but its output is not described.

**Task 6 (value labels and variable labels): 1, 2, 1, 1**
- Findability 1: the only mention is one sentence saying `haven::labelled` columns round-trip, plus one in the metadata article.
- Correctness 2: what is said is accurate, but the task is barely covered.
- Completeness 1: it does not show how to read a column's variable label or value labels, look up the text of a code, or make a factor.
- Clarity 1: there is no example and no definition of the terms.

**Task 7 (dates and timestamps): 1, 3, 1, 2**
- Findability 1: the only material is the timestamp arguments on the `write_parquet` function page.
- Completeness 1: on the write side it gives `coerce_timestamps` ("ms" or "us"), `use_deprecated_int96_timestamps` and `allow_truncated_timestamps`. It does not say what DATE and TIMESTAMP become on reading, and gives nothing on time zones, naive versus zoned times, or out-of-range values.
- Clarity 2: the option text is clear, but there is no example.

**Task 8 (write a table): 2, 3, 2, 3**
- Findability 2: it needs the link from the README to the read/write article, or the function page.
- Completeness 2: the call, the codecs, the snappy default, the per-column patterns and `chunk_size` as row group size are covered. The R-to-Parquet type mapping is missing, and so is what counts as an error.

**Task 9 (write labels and check them): 2, 3, 2, 2**
- Findability 2: the answer is the attributes paragraph in the read/write article, plus the linked metadata article.
- Completeness 2: it says column and data frame attributes are stored under the `r` key and restored on read. It never shows variable labels, value labels or a data label written to a Parquet file and read back, and the metadata example stops at a Table.
- Clarity 2: the example shows `tb$metadata`, not a round trip through a file.

**Task 10 (keep `.a` to `.z`): 0, 0, 0, 0**
- The documents say nothing about Stata's extended missing values or distinguishing missing values per value. The task is not covered.

**Task 11 (read a file another tool wrote): 1, 2, 1, 1**
- Findability 1: the only trace is the `ParquetFileReader` example that reads a bundled file, and the list of write codecs.
- Correctness 2: nothing stated is wrong, but a reader cannot tell what is read.
- Completeness 1: nothing on which encodings or types are read, nested columns, encryption, or what other tools see in files this library writes.
- Clarity 1: there is no explanation, so the reader has to infer it.

## Library B

**Task 1: 3, 3, 3, 2**
- Clarity 2: three R packages are involved. The README gives the install command for `dtatools`, while the Parquet functions are in `datakit`. The reader has to reconcile the README, the R Install section and the Parquet install section to know which to install.

**Task 2: 3, 3, 3, 2**
- Clarity 2: the example and its output are clear. The type table is dense, with cells like "double where `.a` to `.z` appear in the rows read of a column written wider for them", and `.a` to `.z` is not explained in this section.

**Task 3: 3, 3, 3, 3**

**Task 4: 3, 3, 3, 3**

**Task 5: 3, 3, 3, 3**

**Task 6: 3, 3, 2, 3**
- Completeness 2: the Parquet section shows only per-row lookup, `val_label(back$income)`. Looking up a chosen code with `values =` is documented elsewhere on the page. The `factors = TRUE` loss of `.a` to `.z` is in the function page, not in the labels section.

**Task 7: 3, 3, 2, 3**
- Completeness 2: units, zones, the number cases and nanosecond truncation are covered. Out-of-range values are not addressed for R. Naive versus zoned times is covered only indirectly: a `POSIXct` without a `tzone` comes back without one, and files from other tools default to UTC.

**Task 8: 3, 3, 3, 3**

**Task 9: 3, 3, 3, 3**

**Task 10: 3, 3, 3, 3**

**Task 11: 3, 3, 3, 3**

## Task scores

| Task | A | B |
|---|---|---|
| 1 Install | 2.75 | 2.75 |
| 2 Read a whole file | 2.00 | 2.75 |
| 3 Some columns | 2.50 | 3.00 |
| 4 Range of rows | 1.75 | 3.00 |
| 5 Schema and metadata | 1.75 | 3.00 |
| 6 Value and variable labels | 1.25 | 2.75 |
| 7 Dates and timestamps | 1.75 | 2.75 |
| 8 Write a table | 2.50 | 3.00 |
| 9 Write labels and check | 2.25 | 3.00 |
| 10 Keep `.a` to `.z` | 0.00 | 3.00 |
| 11 File another tool wrote | 1.25 | 3.00 |
| **Total (of 33)** | **19.75** | **32.00** |
