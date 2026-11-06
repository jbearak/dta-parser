```json
{"A": {"1": [3, 3, 2, 2], "2": [3, 3, 3, 2], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 2, 2, 2], "7": [3, 3, 3, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 3], "11": [3, 3, 3, 3]},
 "B": {"1": [3, 2, 2, 3], "2": [3, 3, 1, 3], "3": [1, 2, 1, 2], "4": [1, 3, 1, 2], "5": [2, 3, 2, 2], "6": [0, 0, 0, 0], "7": [1, 2, 1, 1], "8": [3, 3, 2, 3], "9": [1, 1, 1, 1], "10": [0, 0, 0, 0], "11": [2, 3, 1, 2]}}
```

## Reasons for scores below 3

### Library A

**Task 1 (install)**
- Completeness 2: It gives the build steps and the Node 24 requirement. It does not list supported operating systems or platforms. Failure help covers only the wasm build step (Troubleshooting).
- Clarity 2: "Version 1.1 (1.0 with Parquet), described here, is not on npm yet; npm has 0.x" is confusing about which version a reader gets.

**Task 2 (read a whole file)**
- Clarity 2: The section leans on earlier `.dta` sections ("The columns are the ones `.dta` reads give, so the rest of this page applies"). The example output shows `{ missing: '.d' }` and the `missing` codes without explaining Stata's `.a` to `.z` there.

**Task 6 (value labels and variable labels)**
- Correctness 2: In the labels example, `formatValue(row[0], ...)` is passed a `TableCell` from `ParquetReader.readRows`. The API reference defines `TableCell = Cell | bigint`, but `formatValue` takes `Cell`. So the example needs an obvious type fix, such as a cast. The other examples cast where needed.
- Completeness 2: It shows reading labels, looking up a code's text, and mapping codes to text with `labels.get`. It never shows turning a labelled column into the language's categorical type (`DictionaryColumn`). The `DictionaryColumn` mention is only for categoricals that were written as such.
- Clarity 2: Value labels are defined only by reference ("as for `.dta`"). A reader who does not know Stata must follow the link to learn what a label set is.

### Library B

**Task 1 (install)**
- Correctness 2: The Node snippet is `require("parquet-wasm")`, but the entry-points table gives the Node build as `parquet-wasm/node`. This is a small ambiguity that could mislead.
- Completeness 2: It gives the install command and the Node <20 polyfill note. It does not give a platform list, and it says little about what to do when installation or initialisation fails beyond `setPanicHook`.

**Task 2 (read a whole file)**
- Completeness 1: It covers the call (`readParquet`) and the move to Arrow via `intoIPCStream`. It says nothing about what each Parquet type becomes in Arrow or JS, and nothing about what is lost or refused (nested columns, encryption, unsupported types).

**Task 3 (read some columns)**
- Findability 1: `columns` appears only in the `ReaderOptions` type and function-reference comments. The README has no guide section for it, and its "Future work" lists "Column filtering, to download only certain columns".
- Correctness 2: The "Future work" line reads as if column filtering does not exist, while the type declarations have a `columns` option.
- Completeness 1: It says only "the column names from the file to read". It does not cover positions, whether order is kept, or what happens with a name that is not in the file.
- Clarity 2: There is a one-line description and no example.

**Task 4 (read a range of rows)**
- Findability 1: `offset`, `limit`, `rowGroups` and `batchSize` are only in the type and function-reference comments.
- Completeness 1: The options are named. An out-of-range request is not described, and the cost of skipping is not described.
- Clarity 2: There is no example and no result described.

**Task 5 (schema and metadata)**
- Findability 2: `readSchema` is in the README API list. `readMetadata`, which holds row count, row groups, compression and key-value metadata, is only in the declarations.
- Completeness 2: The declarations expose all the pieces. No guide shows them together, and there is no mapping from schema types to JS types.
- Clarity 2: There is no example for the metadata calls, only declaration comments.

**Task 6 (value labels and variable labels)**
- All four 0: The docs have no concept of variable labels or value labels. Nothing tells the reader how to read or look up labels or build a categorical from them.

**Task 7 (dates and timestamps)**
- Findability 1: Dates appear only in the write example (`Date64<MILLISECOND>` in the output comment).
- Correctness 2: What is shown is plausible. Nothing is stated about the DATE or TIMESTAMP mapping, so the reader must guess.
- Completeness 1: It does not cover units, time zones, out-of-range values, or naive versus zoned times.
- Clarity 1: The example shows an Arrow schema string and no explanation.

**Task 8 (write a table)**
- Completeness 2: The write call, the compression setters and the row group setters are documented (`setMaxRowGroupSize`, `setMaxRowGroupBytes`). The default compression codec and default row group size are not stated, and there is no type-mapping table.

**Task 9 (write labels and check them)**
- All four 1: The docs have no label feature. The only hook is the generic `setKeyValueMetadata` and `keyValueMetadata()`, which are one-line declaration comments. There is no example, no pointer from the README, and no way to attach value labels from the docs alone.

**Task 10 (keep `.a` to `.z`)**
- All four 0: Nothing is covered, and the library cannot do this task.

**Task 11 (read a file another tool wrote)**
- Findability 2: "Compression support" is a heading. Nothing names the task as a whole.
- Completeness 1: It covers codecs only, including the LZ4 versus LZ4_RAW caveat. Read encodings and types are not listed. Nested and encrypted files are not mentioned. What other tools see in files this library writes is not covered.
- Clarity 2: The LZ4 explanation is readable. There is no example.

## Task scores

| task | A | B |
|---|---|---|
| 1 | 2.50 | 2.50 |
| 2 | 2.75 | 2.50 |
| 3 | 3.00 | 1.50 |
| 4 | 3.00 | 1.75 |
| 5 | 3.00 | 2.25 |
| 6 | 2.25 | 0.00 |
| 7 | 3.00 | 1.25 |
| 8 | 3.00 | 2.75 |
| 9 | 3.00 | 1.00 |
| 10 | 3.00 | 0.00 |
| 11 | 3.00 | 2.00 |
| **Total** | **31.50** | **17.50** |
