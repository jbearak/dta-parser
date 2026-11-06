```json
{"A": {"1": [2, 3, 3, 3], "2": [3, 3, 3, 2], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 2, 2], "7": [3, 3, 3, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 2], "10": [3, 3, 3, 2], "11": [3, 3, 3, 3]},
 "B": {"1": [1, 2, 1, 2], "2": [3, 3, 2, 2], "3": [1, 3, 1, 2], "4": [1, 3, 2, 2], "5": [3, 2, 2, 2], "6": [0, 0, 0, 0], "7": [1, 2, 1, 1], "8": [2, 2, 2, 3], "9": [1, 1, 1, 1], "10": [0, 0, 0, 0], "11": [2, 2, 2, 3]}}
```

Scores are in the order findability, correctness, completeness, clarity. Reasons are given for every score below 3.

## Library A

**1. Install.** Findability 2: the install steps are in the language page's Install section. The Parquet install entry is a separate subsection that points back to it, and the README says only that "each page says how to install". The other three scores are 3: the command, Node 24 or later and the build prerequisites are given, as is a fix for a failing build.

**2. Read a whole file.** Clarity 2: the section assumes the reader knows the `.dta` column types from earlier sections (`NumberColumn`, a `missing` code per row, "the dta profile"). The type table is clear, but a reader new to Stata has to look back.

**3. Read some columns.** All 3: names or indices, the order given, and the error for an unknown name (with its message shown).

**4. Read a range of rows.** All 3: `{start, count}`, `readRows` and `readRowsAt`; a window past the end throws a `RangeError`; the cost is described (row groups and pages, page cache).

**5. Schema and metadata.** All 3: a worked example with output and a table covering rows, row groups, codecs, key-value metadata and per-column statistics.

**6. Value labels and variable labels.** Completeness 2: a labelled column is mapped to its text by hand. The doc never shows turning it into a categorical, and JavaScript has no categorical type to turn it into. Clarity 2: "value label set", missing codes and "as for `.dta`" are explained only by a link back to an earlier section.

**7. Dates and timestamps.** All 3: DATE and TIMESTAMP units, how zoned and naive timestamps differ, the range limit of `Date` (null outside it), and a worked example with output.

**8. Write a table.** All 3: the write call, a type table, the default codec (snappy) and why, the row group size, and the error for a value that does not fit.

**9. Write labels and check them.** Clarity 2: the example is short and shows its output, but "value label set", `MISSING[".r"]` and "data label" are not explained for a reader who does not know Stata.

**10. Keep `.a` to `.z`.** Clarity 2: the docs show codes 2 to 27 and `.` as a null, and what other tools see. They never say what `.a` to `.z` mean, so a reader who does not know Stata has to infer it.

**11. Read a file another tool wrote.** All 3: codecs, encodings, types, what is not read (nested columns, encryption, datasets split over several files), and what other tools see in files this library writes.

## Library B

**1. Install.** Findability 1: there is no install section. An npm badge and a CDN import imply it. Correctness 2: nothing is wrong, but the examples are the only guide. Completeness 1: no `npm install` command, no Node version, and no failure advice. It says only "works in browsers and node.js" and "published as an ES module". Clarity 2: the CDN and `import()` examples are easy to follow.

**2. Read a whole file.** Completeness 2: `parquetReadObjects`, `parquetRead`, `rowFormat`, `utf8` and the codec table are covered. There is no table of what each Parquet type becomes, and nothing on what is refused. Clarity 2: the examples do not show what comes back.

**3. Read some columns.** Findability 1: only in the Browser Example and the type comment. Completeness 1: `columns: [...]` takes names. Nothing says whether position works, whether order is kept, or what an unknown name does. Clarity 2: the example is clear but its result is not described.

**4. Read a range of rows.** Findability 1: only the example and the option comments. Completeness 2: `rowStart` is inclusive and `rowEnd` is exclusive, and the cost options (offset index, page index) are listed. Nothing says what an out-of-range request does. Clarity 2: the example does not say what it returns.

**5. Schema and metadata.** Correctness 2: the snippet uses `asyncBufferFromUrl` without importing it (an obvious fix). Completeness 2: names and row count are shown. Row groups, codec and key-value metadata appear only in the type definitions, not in prose. What each type will become is not explained. Clarity 2: the example is short, but its result is not shown.

**6. Value labels and variable labels.** All 0: the docs say nothing about variable labels or value labels, and there is no categorical mapping.

**7. Dates and timestamps.** Findability 1: only the `parsers` option in the type file, one writer table row, and a `Date` in the writer example. Correctness 2: what is stated is accurate, but there is no reading example to run. Completeness 1: no prose says what DATE or TIMESTAMP become when read, how units or time zones are handled, or what an out-of-range value does. Clarity 1: the reader must work this out from type signatures.

**8. Write a table.** Findability 2: the reader README only points to the writer package. Correctness 2: the large example contains a typo (`snappyCompresss`). It also gives integer data a DECIMAL schema, which looks wrong. Completeness 2: the call, the codec and its default (SNAPPY), row group sizes, the `BasicType` table, and the need for `compressors` are covered. How JavaScript values are auto-typed is only hinted ("floats might be typed as int"). What is an error is only partly stated.

**9. Write labels and check them.** All 1: labels are never mentioned. `kvMetadata` is an implied place to put them, but nothing shows attaching labels or reading them back.

**10. Keep `.a` to `.z`.** All 0: not covered.

**11. Read a file another tool wrote.** Findability 2: the answer is in "Binary columns" and "Compression". There is no heading for this task. Correctness 2: "supports all parquet types, encodings, and compression codecs" sits beside a table showing that only snappy and uncompressed work by default. The metadata types also comment out encryption. Completeness 2: the codecs are well covered. Encodings are covered only by "all". Encryption and unsupported types are not stated, and nothing says what other tools see in files this library writes.

## Task scores

| task | Library A | Library B |
|---|---|---|
| 1 | 2.75 | 1.50 |
| 2 | 2.75 | 2.50 |
| 3 | 3.00 | 1.75 |
| 4 | 3.00 | 2.00 |
| 5 | 3.00 | 2.25 |
| 6 | 2.50 | 0.00 |
| 7 | 3.00 | 1.25 |
| 8 | 3.00 | 2.25 |
| 9 | 2.75 | 1.00 |
| 10 | 2.75 | 0.00 |
| 11 | 3.00 | 2.25 |
| **Total** | **31.50** | **16.75** |
