```json
{"A": {"1": [1, 2, 1, 1], "2": [3, 3, 2, 2], "3": [2, 3, 1, 2], "4": [2, 3, 2, 2], "5": [3, 2, 2, 2], "6": [0, 0, 0, 0], "7": [1, 2, 1, 1], "8": [3, 2, 2, 2], "9": [1, 2, 1, 1], "10": [0, 0, 0, 0], "11": [2, 3, 2, 3]},
 "B": {"1": [3, 2, 3, 3], "2": [3, 3, 3, 2], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 2, 2], "7": [3, 3, 3, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 3], "11": [3, 3, 3, 3]}}
```

Scores are in the order findability, correctness, completeness, clarity (F, Co, Cm, Cl). A task I don't list a reason for scored 3 on every dimension.

## Library A

Library A is the reader README, its type files, and the writer README and type files.

**Task 1, Install: F1, Co2, Cm1, Cl1**
- F1: No install heading or command appears anywhere. The reader only implies installation through `import('hyparquet')` and a CDN URL in Quick Start examples.
- Co2: What is said is right ("works in browsers and node.js", "dynamic import() may be required for old versions of node"), but there is no install command to check.
- Cm1: There are no install steps, no supported platforms or versions beyond that one note, and nothing on what to do when installation fails.
- Cl1: A reader has to infer the package name and install route from example code.

**Task 2, Read a whole file: F3, Co3, Cm2, Cl2**
- Cm2: The README gives the read call and return type (`parquetReadObjects` returns `Record<string, any>[]`). It covers `rowFormat`, `utf8`, `geoparquet` and compressors. It never says what each Parquet type becomes (the type files show int64 and `num_rows` as bigint, but there is no table), and it names no refused or lost types.
- Cl2: The examples are short but show no output or result type, so a reader has to work out what comes back.

**Task 3, Read only some columns: F2, Co3, Cm1, Cl2**
- F2: The answer appears in a Quick Start example (`columns: ['Breed Name', 'Lifespan']`) and a sentence about filtering by row and column. There is no heading for it.
- Cm1: The only description is `columns?: string[]` ("all columns if undefined"). Positions, whether order is kept, and what a missing name does are not stated.
- Cl2: The example works but shows no result.

**Task 4, Read a range of rows: F2, Co3, Cm2, Cl2**
- F2: The answer is in the same Quick Start example (`rowStart: 10, rowEnd: 20`) and in the types file. There is no heading for it.
- Cm2: The types file says `rowStart` is inclusive and `rowEnd` exclusive. The `parquetRead` docs say it reads the minimal row groups and columns, and `onChunk` may include data outside the range. An out-of-range request is not described, and the cost is only implied.
- Cl2: There is no output shown for the range example.

**Task 5, Schema and metadata without data: F3, Co2, Cm2, Cl2**
- Co2: The "Reading Metadata" example calls `asyncBufferFromUrl` without importing it (a small fix). Its import line also leaves `parquetMetadataAsync` and `parquetSchema` as the only imports.
- Cm2: Column names, row count and the schema tree are covered in prose. Row groups, compression and key-value metadata appear only as fields in `FileMetaData`, `ColumnMetaData` and `KeyValue` in the types file. The README does not say what each column type will become.
- Cl2: The example shows no output, and `schema.children.map(e => e.element.name)` needs some explanation.

**Task 6, Value labels and variable labels: F0, Co0, Cm0, Cl0**
- The docs never mention variable labels, value labels, code-to-text lookup or categorical conversion. The only related mechanism is generic key-value metadata, and nothing connects it to labels.

**Task 7, Dates and timestamps: F1, Co2, Cm1, Cl1**
- F1: There is no section on this. It is implied by the `parsers` option (`dateFromDays`, `timestampFromMillis`…), the `TIMESTAMP`/`isAdjustedToUTC`/`unit` types, and a `new Date` column in the writer example.
- Co2: Nothing stated is wrong, but there is little stated. The writer table maps `TIMESTAMP` to INT64 `TIMESTAMP_MILLIS`.
- Cm1: The docs don't say what DATE or TIMESTAMP become on reading (the parsers return `any`). They give no time-zone behavior, no range handling, and nothing on naive versus zoned times.
- Cl1: A reader has to work it out from type signatures.

**Task 8, Write a table: F3, Co2, Cm2, Cl2**
- Co2: The advanced example imports `snappyCompress` but then uses `snappyCompresss`, which is a ReferenceError and needs an obvious fix.
- Cm2: The write calls (`parquetWriteBuffer`, `parquetWriteFile`), codec default (SNAPPY), row group default (`[1000, 100000]`) and the `BasicType` mapping table are all covered. "What is an error" is thin: only the zero-row auto-detection case and the need for compressors other than snappy are mentioned.
- Cl2: The examples show no results.

**Task 9, Write labels and check them: F1, Co2, Cm1, Cl1**
- F1: Only the generic `kvMetadata` option and a `key1`/`value1` example exist. Nothing links it to labels.
- Co2: What is shown is right, but it does not address the task.
- Cm1: The docs show writing arbitrary key-value pairs. They show no label convention, no data label, and no read-back of the pairs (only the `key_value_metadata` type).
- Cl1: A user would have to invent their own convention for storing labels.

**Task 10, Keep .a to .z: F0, Co0, Cm0, Cl0**
- The docs don't cover it. The library cannot do it, and nothing is said about it.

**Task 11, Read a file another tool wrote: F2, Co3, Cm2, Cl3**
- F2: The "Compression" heading and the feature list on the front page cover most of it. Types and encodings are covered only by the line "Supports all parquet types, encodings, and compression codecs".
- Cm2: The codec table with and without `hyparquet-compressors` is clear. Encodings are only a blanket claim, with no list. Nested columns and encryption are not discussed. What other tools see in files this library writes is not covered (only "optimized for large text datasets and fast previews").

## Library B

Library B is the README, `docs/parquet.md`, and the Parquet sections of `docs/typescript.md`, plus the API reference.

**Task 1, Install: F3, Co2, Cm3, Cl3**
- Co2: The README says "None of them is on a package registry yet". The TypeScript page says "npm has 0.x, a different API", and "Version 1.1 (1.0 with Parquet)" is confusing.

**Task 2, Read a whole file: F3, Co3, Cm3, Cl2**
- Cl2: The section leans on earlier `.dta` sections ("the columns are the ones `.dta` reads give") and on the example file, which the bundle doesn't include. `NumberColumn`, `MISSING` and the dta profile need those sections to follow. The example output is shown.

**Task 3, Read some columns: all 3.**

**Task 4, Read a range of rows: all 3.**

**Task 5, Schema and metadata: all 3.**

**Task 6, Value labels and variable labels: F3, Co3, Cm2, Cl2**
- Cm2: Variable label, value label sets, code lookup (`labels.get(2)`), mapping a whole column and `formatValue` are all shown. Turning a labelled numeric column into the categorical type (`DictionaryColumn`) is not shown. `DictionaryColumn` appears only for stored categoricals and string dictionaries.
- Cl2: Terms like value label sets, the dta profile and `.d` rely on the guide, which is not part of this section. The example output is shown.

**Task 7, Dates and timestamps: all 3.**

**Task 8, Write a table: all 3.**

**Task 9, Write labels and check them: all 3.**

**Task 10, Keep .a to .z: all 3.**

**Task 11, Read a file another tool wrote: all 3.**

## Task scores

| Task | A | B |
|---|---|---|
| 1 Install | 1.25 | 2.75 |
| 2 Read whole file | 2.50 | 2.75 |
| 3 Some columns | 2.00 | 3.00 |
| 4 Range of rows | 2.25 | 3.00 |
| 5 Schema and metadata | 2.25 | 3.00 |
| 6 Value and variable labels | 0.00 | 2.50 |
| 7 Dates and timestamps | 1.25 | 3.00 |
| 8 Write a table | 2.25 | 3.00 |
| 9 Write labels | 1.25 | 3.00 |
| 10 Keep .a to .z | 0.00 | 3.00 |
| 11 File from another tool | 2.50 | 3.00 |
| **Total (of 33)** | **17.50** | **32.00** |
