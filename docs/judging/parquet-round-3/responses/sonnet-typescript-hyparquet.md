```json
{"A": {"1": [3,3,3,3], "2": [3,3,3,2], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,2,3,3], "7": [3,3,3,3], "8": [3,3,3,3], "9": [3,3,3,3], "10": [3,3,3,3], "11": [3,3,3,3]},
 "B": {"1": [1,1,1,1], "2": [3,2,1,2], "3": [2,3,1,2], "4": [2,3,2,2], "5": [3,2,2,2], "6": [0,0,0,0], "7": [1,1,1,1], "8": [2,2,2,3], "9": [1,1,1,1], "10": [0,0,0,0], "11": [2,2,2,2]}}
```

Scores are in the order findability, correctness, completeness, clarity. Only scores below 3 have reasons.

## Library A

1. Install: all 3. There is an Install heading with the build steps, Node 24 or later, a Parquet-specific install paragraph, and a Troubleshooting section for failed builds.
2. Read a whole file: [3,3,3,2].
   - Clarity 2: the example reads `survey.parquet`, which it builds from `survey.dta` (defined in another section). Output such as `{ missing: '.d' }` is shown without saying what `.d` is in this section.
3. Read some columns: all 3. Names and indices, order kept, the error message for an unknown name, and an example with output.
4. Read a range of rows: all 3. It covers `readColumns` with `{start, count}`, `readRows`, `readRowsAt`, the `RangeError` past the end, the row-group and page cost, and the page cache.
5. Schema and metadata: all 3. Rows, row groups, codecs, writer, per-column types, column kind, Parquet types, per-chunk statistics, and key-value entries, with an example and a table.
6. Value labels and variable labels: [3,2,3,3].
   - Correctness 2: the `formatValue(row[0], …)` example passes a `TableCell` (which can be a `bigint`) where `formatValue` takes a `Cell`. This needs a cast or fix to type-check. The rest runs and the output is right.
7. Dates and timestamps: all 3. The units, zones, instant versus clock time, a `Date`-range limit via `toDate` returning null, and a worked example that checks out.
8. Write a table: all 3. The call, the options, the type table, the default codec and why, the row-group default, and the error on a value that does not fit.
9. Write labels and check them: all 3. It sets a variable label, value labels and a data label, then reads them back, with the output shown.
10. `.a` to `.z`: all 3. Codes 2 to 27 versus `.` and NaN, the round trip, the `missingLetters: false` option, and what each other tool sees.
11. Files another tool wrote: all 3. Codecs, encodings, types, and what is not read (BIT_PACKED values, FLOAT16, INTERVAL, nested, encrypted, multi-file). It also covers categoricals and zones, and points to what other tools see in files this package writes.

## Library B

1. Install: [1,1,1,1].
   - Findability 1: there is no install heading or command. The only hints are the npm badges and an ESM note.
   - Correctness 1: nothing wrong is said, but the task is essentially not covered.
   - Completeness 1: only "published as an ES module". There is no command, no Node versions or platforms, and nothing on failures.
   - Clarity 1: it has to be inferred from imports.
2. Read a whole file: [3,2,1,2].
   - Correctness 2: "Supports all parquet types, encodings, and compression codecs" contradicts the codec table, where GZip, Brotli, ZSTD and others are not supported by default.
   - Completeness 1: the call and the row-object return are shown. It does not say what each Parquet type becomes, what is lost or refused, or how nested, int64 or decimal values come back. Only utf8 and GeoParquet are mentioned.
   - Clarity 2: the examples show no output or result shape beyond the type name.
3. Read some columns: [2,3,1,2].
   - Findability 2: the answer is only in the Quick Start example (`columns: [...]`) and the types file.
   - Completeness 1: names only. It says nothing on positions, on order, or on what an unknown name does.
   - Clarity 2: an example with no output.
4. Read a range of rows: [2,3,2,2].
   - Findability 2: `rowStart` and `rowEnd` appear in the Quick Start example and the types file.
   - Completeness 2: the minimal-row-groups behaviour, the exclusive end and `useOffsetIndex` are in the type comments, and `onChunk` may return rows outside the range. Out-of-range behaviour is missing.
   - Clarity 2: an example with no stated result.
5. Schema and metadata: [3,2,2,2].
   - Correctness 2: the example uses `asyncBufferFromUrl` without importing it.
   - Completeness 2: names and row count are shown. Row groups, codec and key-value metadata appear only in the type definitions. What each column will become is not said.
   - Clarity 2: no output is shown.
6. Value labels: all 0. Nothing is documented about labels, categorical conversion or code lookup.
7. Dates and timestamps: [1,1,1,1]. There is no date section. Only the `ParquetParsers` option names, the writer's `TIMESTAMP` type (millis) and a `Date` example appear. Units, zones and out-of-range values are not covered, and no example shows a read.
8. Write a table: [2,2,2,3].
   - Findability 2: it is in a separate writer README, reached by a link from the front page.
   - Correctness 2: the example has `snappyCompresss` (typo), while it imports `snappyCompress`.
   - Completeness 2: the call, the codec and its SNAPPY default, the row-group default, the basic-type table, and zero-row errors are covered. The auto-detection rules per JS type are not given. Other codecs need `compressors`, with no pointer to a package.
9. Write labels and check: [1,1,1,1]. Only the generic `kvMetadata` option and the `key_value_metadata` type are related. Labels are not mentioned, and there is no read-back check.
10. `.a` to `.z`: all 0. Nothing is documented about tagged missing values, nulls versus NaN, or what other tools see.
11. Files another tool wrote: [2,2,2,2].
   - Findability 2: the Compression table is easy to find. Types and encodings are covered only by one bullet, and nothing says what other tools see in files this library writes.
   - Correctness 2: the "all types, encodings and codecs" claim conflicts with the codec table. Encryption is never mentioned, and the types suggest it is not supported.
   - Completeness 2: codecs and `utf8` are covered. Encodings are not listed, and there is nothing on encryption or on other tools reading its output.
   - Clarity 2: the codec table is clear, but it sits next to the contradicting "all codecs" claim.

## Task scores

| task | Library A | Library B |
|---|---|---|
| 1 | 3.00 | 1.00 |
| 2 | 2.75 | 2.00 |
| 3 | 3.00 | 2.00 |
| 4 | 3.00 | 2.25 |
| 5 | 3.00 | 2.25 |
| 6 | 2.75 | 0.00 |
| 7 | 3.00 | 1.00 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 1.00 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 2.00 |
| **Total** | **32.50** | **15.75** |
