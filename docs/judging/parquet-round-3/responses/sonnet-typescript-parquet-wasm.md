```json
{"A": {"1": [3, 3, 2, 3], "2": [3, 3, 3, 2], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 3, 3], "7": [3, 3, 3, 3], "8": [3, 3, 2, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 2], "11": [3, 3, 3, 3]},
 "B": {"1": [3, 3, 2, 3], "2": [3, 2, 1, 3], "3": [1, 1, 1, 1], "4": [1, 3, 1, 1], "5": [1, 2, 2, 2], "6": [0, 0, 0, 0], "7": [1, 2, 1, 1], "8": [3, 3, 2, 3], "9": [1, 1, 1, 1], "10": [0, 0, 0, 0], "11": [2, 3, 1, 2]}}
```

Scores are given as [findability, correctness, completeness, clarity]. Reasons are given for every score below 3.

## Library A

**Task 1 (install)**
- Completeness 2: the build needs and the troubleshooting entries cover macOS and Linux. Nothing says whether a Windows build works. Node 24 and the TypeScript versions are given.

**Task 2 (read a whole file)**
- Clarity 2: the first example prints `{ missing: '.d' }` and `missing: Uint8Array [0,5,0,1,19,0]` without saying here what the codes mean. The reader is sent to the `.dta` sections, and the code table only appears in the `.a` to `.z` section.

**Task 3 (some columns)**
- No deductions.

**Task 4 (range of rows)**
- No deductions.

**Task 5 (schema and metadata)**
- No deductions.

**Task 6 (labels)**
- No deductions.

**Task 7 (dates and timestamps)**
- No deductions.

**Task 8 (write a table)**
- Completeness 2: the write table lists what each type becomes and what is an error. It does not say whether the types a reader can return (decimal, time, uint8 to uint64) can be written, apart from a pointer in the API reference.

**Task 9 (write labels and check them)**
- No deductions.

**Task 10 (`.a` to `.z`)**
- Clarity 2: the example and its output are clear. The section never says what `.a` to `.z` are for. That is only explained on the README front page, so a reader who does not know Stata has to go there.

**Task 11 (files from other tools)**
- No deductions.

## Library B

**Task 1 (install)**
- Completeness 2: the npm and yarn commands are given, and the entry points cover browser, bundler and Node. The Node < 20 polyfill note and the Rust 1.60 minimum for custom builds are there, but there is no Node or TypeScript version for the package itself. Nothing covers what to do if installation or WASM initialisation fails, other than `setPanicHook`.

**Task 2 (read a whole file)**
- Correctness 2: the "Node" example uses `require("parquet-wasm")`. The entry-point table says Node uses `parquet-wasm/node`, so the example needs a fix.
- Completeness 1: only the main path is covered (`readParquet`, then `intoIPCStream` or `intoFFI`). There is no table of what each Parquet type becomes in Arrow. Nothing says what is lost or refused, such as nested columns or encodings.

**Task 3 (some columns)**
- Findability 1: `columns` appears only in the `ReaderOptions` type and in function reference comments. The README guide has no pointer to it.
- Correctness 1: the README's "Future work" lists "Column filtering, to download only certain columns" as not done, while the reference documents a `columns` option. A reader cannot tell which is true.
- Completeness 1: only the existence of `columns: string[]` is stated. Nothing covers positions, whether order is kept, or what happens with a name not in the file.
- Clarity 1: there is no example, and the contradiction above makes it hard to follow.

**Task 4 (range of rows)**
- Findability 1: `offset`, `limit` and `rowGroups` are only in the reference comments. The README mentions only reading "portions" of a remote file.
- Completeness 1: it names the options, with no out-of-range behaviour and no cost (whether skipped rows are decoded or whole row groups are read).
- Clarity 1: there is no example and no description of results.

**Task 5 (schema and metadata)**
- Findability 1: `readSchema` is listed in the README. `readMetadata` (row count, row groups, compression, key-value metadata) is only in the reference.
- Correctness 2: the docs are mostly accurate. `Schema.intoFFI`'s comment says "Export this Table", which is a copy-paste slip.
- Completeness 2: the metadata classes cover row count, row groups, codecs and key-value metadata. Nothing says what each column's type will become.
- Clarity 2: `readSchema` has an example. Metadata has none, so the reader must chain `readMetadata().fileMetadata().numRows()` and so on from method comments.

**Task 6 (value labels and variable labels)**
- All four scores 0: the docs never mention variable labels, value labels, looking up a code, or turning a labelled column into a categorical. Generic key-value metadata exists but is not linked to labels.

**Task 7 (dates and timestamps)**
- Findability 1: dates appear only inside the README's rainfall example, where `date: Date64<MILLISECOND>` is printed.
- Correctness 2: the example is plausible and nothing stated is wrong. Nothing is said about the task itself.
- Completeness 1: there are no units, no time zones, no out-of-range values and no naive-versus-zoned discussion.
- Clarity 1: an example output with no explanation.

**Task 8 (write a table)**
- Completeness 2: the write call, the `Compression` enum and builder options (row group size, dictionary, statistics, writer version) are documented. The default codec and default row group size are not stated, and there is no Arrow-to-Parquet type mapping. Write errors are only covered for freed objects.

**Task 9 (write labels and check them)**
- All four scores 1: the only route is the generic `setKeyValueMetadata` setter and `keyValueMetadata()` / `Schema.metadata()`, each a one-line comment. The docs never connect them to variable labels, value labels or a data label, and there is no example or read-back check.

**Task 10 (`.a` to `.z`)**
- All four scores 0: the docs say nothing about Stata extended missing values, per-value missing codes or what other tools see.

**Task 11 (file another tool wrote)**
- Findability 2: a "Compression support" heading names the codecs. Nothing else for the task has a heading.
- Completeness 1: the codec checklist covers snappy, gzip, brotli, zstd, lz4_raw, and says LZ4 is unsupported. Encodings read, supported types, nested columns, encryption and what other tools see in files this library writes are missing.
- Clarity 2: the checklist and the LZ4 explanation are clear, but the rest of the task is absent.

## Task scores

| task | Library A | Library B |
|---|---|---|
| 1 Install | 2.75 | 2.75 |
| 2 Read a whole file | 2.75 | 2.25 |
| 3 Some columns | 3.00 | 1.00 |
| 4 Range of rows | 3.00 | 1.50 |
| 5 Schema and metadata | 3.00 | 1.75 |
| 6 Value and variable labels | 3.00 | 0.00 |
| 7 Dates and timestamps | 3.00 | 1.25 |
| 8 Write a table | 2.75 | 2.75 |
| 9 Write labels | 3.00 | 1.00 |
| 10 `.a` to `.z` | 2.75 | 0.00 |
| 11 File another tool wrote | 3.00 | 2.00 |
| **Total** | **32.00** | **16.25** |
