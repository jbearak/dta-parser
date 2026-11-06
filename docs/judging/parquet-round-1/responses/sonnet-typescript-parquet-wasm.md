```json
{"A": {"1": [3, 3, 2, 3], "2": [2, 3, 1, 3], "3": [1, 1, 1, 1], "4": [1, 3, 2, 1], "5": [2, 3, 2, 2], "6": [0, 0, 0, 0], "7": [1, 2, 1, 1], "8": [2, 3, 2, 3], "9": [1, 2, 1, 1], "10": [0, 0, 0, 0], "11": [2, 2, 1, 2]},
 "B": {"1": [3, 2, 3, 3], "2": [3, 3, 3, 3], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 3, 3], "7": [3, 3, 3, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 2], "11": [3, 3, 3, 3]}}
```

I scored from the text of the file only. In Library A's bundle I took the README and the `.d.ts` as its documentation. Where I wrote "no example" below, I mean the bundle has none.

## Library A

**Task 1, install: [3, 3, 2, 3]**
- Completeness 2: It gives the npm and yarn commands, the three entry points, the need to initialise the wasm for `esm`, and a note for Node below 20. It does not list supported platforms beyond that, and it says nothing about what to do when install or initialisation fails apart from the one `TypeError` hint.

**Task 2, read a whole file: [2, 3, 1, 3]**
- Findability 2: `readParquet` is in the Sync API list, and the working example sits under a heading just called "Example". Nothing names the task.
- Completeness 1: It covers the read call and that a wasm-memory `Table` comes back, which you convert with `intoIPCStream`. It does not say what each Parquet type becomes in JavaScript. It does not say what is lost or refused, such as nested columns or unsupported types.

**Task 3, read only some columns: [1, 1, 1, 1]**
- Findability 1: The only mention is `columns?: string[]` in the `ReaderOptions` type and in the `readParquet` doc comment. The guide does not point to it.
- Correctness 1: The README "Future work" list still has "Column filtering, to download only certain columns" as an unticked item. That contradicts the `columns` option in the `.d.ts`, and a reader cannot tell which is true.
- Completeness 1: It says the option names columns. It does not cover positions, whether order is kept, or what happens with an unknown name.
- Clarity 1: It is a one-line description with no example.

**Task 4, read a range of rows: [1, 3, 2, 1]**
- Findability 1: `offset`, `limit`, `rowGroups` and `batchSize` appear only in the `ReaderOptions` type and the function comments.
- Completeness 2: It covers skip and limit, row groups and batches. It does not say what an out-of-range request does or what a range costs.
- Clarity 1: There is no example and no stated result.

**Task 5, schema and metadata without the data: [2, 3, 2, 2]**
- Findability 2: `readSchema` is in the README Sync API list. `readMetadata`, `ParquetFile.metadata()` and the metadata classes are only in the `.d.ts`.
- Completeness 2: The API exposes row count, row groups, compression, encodings and key-value metadata. It does not say what each column will become. It does not show how to read the pieces together.
- Clarity 2: The `readSchema` example works. The metadata classes have only one-line comments and no example.

**Task 6, value labels and variable labels: [0, 0, 0, 0]**
- The documentation does not mention variable labels, value labels, or turning a coded column into a categorical type. A generic schema-metadata map exists, but nothing connects it to labels.

**Task 7, dates and timestamps: [1, 2, 1, 1]**
- Findability 1: The only trace is the README example, which writes JavaScript `Date`s and prints `Date64<MILLISECOND>`.
- Correctness 2: What the example implies is plausible and nothing is wrong, but the task is barely covered.
- Completeness 1: Units, time zones, out-of-range values, and naive versus zoned times are not covered.
- Clarity 1: The printed schema is not explained.

**Task 8, write a table: [2, 3, 2, 3]**
- Findability 2: `writeParquet` is in the Sync API list. The details are in the "Example" section and the `.d.ts`, and no heading names writing.
- Completeness 2: It covers the write call, the codec setter, `setMaxRowGroupSize` and the full list of codecs. It does not state the default codec. It has no JavaScript-to-Parquet type mapping and does not say what is an error.

**Task 9, write labels and check them: [1, 2, 1, 1]**
- Findability 1: `setKeyValueMetadata`, `Schema.withMetadata` and `FileMetaData.keyValueMetadata` exist in the `.d.ts`. Nothing says they can carry labels.
- Correctness 2: What the generic metadata calls say is accurate. They are never shown doing the label task, so a reader gets nothing runnable.
- Completeness 1: Only the generic key-value mechanism exists. There is no convention for variable labels, value labels or a data label.
- Clarity 1: There is no example and no result.

**Task 10, keep `.a` to `.z`: [0, 0, 0, 0]**
- The documentation says nothing about this task, and the library cannot do it.

**Task 11, read a file another tool wrote: [2, 2, 1, 2]**
- Findability 2: The "Compression support" heading gives the codecs. Nothing else on the task has a heading.
- Correctness 2: The README codec checklist and the `.d.ts` disagree slightly. The `Compression` enum lists `LZ4` and `LZO`, and the README says LZ4 is unsupported without mentioning LZO.
- Completeness 1: Codecs are covered. Encodings read, types read, nested and encrypted files, and what other tools see in files this library writes are not covered.
- Clarity 2: The LZ4 explanation is clear. There is no example, and the user cannot see what happens on an unsupported file.

## Library B

**Task 1, install: [3, 2, 3, 3]**
- Correctness 2: The README says none of the packages is on a registry yet. The TypeScript page says npm has 0.x, which is a different API. The two statements disagree on small details.

**Task 2, read a whole file: [3, 3, 3, 3]**

**Task 3, read some columns: [3, 3, 3, 3]**

**Task 4, read a range of rows: [3, 3, 3, 3]**

**Task 5, schema and metadata: [3, 3, 3, 3]**

**Task 6, value and variable labels: [3, 3, 3, 3]**

**Task 7, dates and timestamps: [3, 3, 3, 3]**

**Task 8, write a table: [3, 3, 3, 3]**

**Task 9, write labels and check them: [3, 3, 3, 3]**

**Task 10, keep `.a` to `.z`: [3, 3, 3, 2]**
- Clarity 2: The section uses ".a to .z" and "tagged NaNs" without saying what these missing values are for. A reader who does not know Stata has to go to the README or the guide.

**Task 11, read a file another tool wrote: [3, 3, 3, 3]**

## Task scores

| Task | Library A | Library B |
|---|---|---|
| 1 | 2.75 | 2.75 |
| 2 | 2.25 | 3.00 |
| 3 | 1.00 | 3.00 |
| 4 | 1.75 | 3.00 |
| 5 | 2.25 | 3.00 |
| 6 | 0.00 | 3.00 |
| 7 | 1.25 | 3.00 |
| 8 | 2.50 | 3.00 |
| 9 | 1.25 | 3.00 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 3.00 |
| **Total** | **16.75** | **32.50** |
