```json
{"A": {"1": [3,2,3,2], "2": [3,3,3,3], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,3,3,3], "7": [3,3,3,2], "8": [3,3,3,3], "9": [3,3,3,3], "10": [3,3,3,2], "11": [3,3,3,3]},
 "B": {"1": [3,2,3,3], "2": [2,2,2,3], "3": [2,3,1,3], "4": [2,3,2,3], "5": [2,3,2,3], "6": [0,0,0,0], "7": [2,1,2,2], "8": [2,2,2,3], "9": [0,0,0,0], "10": [0,0,0,0], "11": [2,2,2,2]}}
```

Scores are in the order findability, correctness, completeness, clarity. Reasons are given for every score below 3.

## Library A

**Task 1, install.**
- Correctness 2: the Python page says wheels are built for macOS, Linux, and Windows, and that "one wheel serves every Python from 3.10". The same page says the package is not on PyPI and must be built from a checkout with Rust. That is confusing. The `--force-reinstall ./python ./python/datakit` fix uses different paths from the install command (`./dta-parser/python`), so it needs an obvious adjustment.
- Clarity 2: the install text for the polars package is hard to follow. Placeholder-style names ("Library A needs polars 2", "For Library A, install both packages... Library A also needs...") make it unclear which package is meant. Two packages and an import name that differs from the distribution name add to this.

**Tasks 2, 3, 4, 5, 8, 9, 11:** all 3s. Each has a named heading one step from the README or `parquet.md`, runnable examples with their output shown, and the edge cases listed.

**Task 6, labels:** all 3s. The page covers the variable label, the value label set, a code-to-text lookup, `factors=True` for the categorical type, and what that conversion loses.

**Task 7, dates.**
- Clarity 2: the opening example is clear. The "Dates and timestamps from other files" paragraph is dense. It packs together `%tc`, DOUBLE-written dates, profile `unit: "s"`, and `timestamps="truncate"`. Those terms are not explained for a reader who doesn't know Stata.

**Task 10, keeping `.a` to `.z`.**
- Clarity 2: the section works, with examples whose outputs I checked as consistent. It needs rereading because it introduces many pieces at once: `meta.missing`, companion columns, `letters=` modes, the null-versus-NaN trap, and `ne_missing`. The recipe section helps.

## Library B

**Task 1, install.**
- Correctness 2: the pip command is printed as `pip install Library B`, which would not run as written. The conda command (`pyarrow`) is fine, so this is an obvious fix.

**Task 2, read a whole file.**
- Findability 2: the reader goes from the front page to the Parquet index, then to the single-files page.
- Correctness 2: the `read_table` docstring's last example is labelled "Read data from a single Parquet file" but reads `'dataset_name_2'`, the dataset, not the file just written. The filter examples also include `pc.field('x') = 0`, which is not valid Python.
- Completeness 2: there is no single table of what each Parquet type becomes in Arrow. The type-handling page covers only dictionary, binary, list, extension, and timestamp cases. What is refused is not stated.

**Task 3, some columns.**
- Findability 2: there is no heading for it. It is a paragraph and example on the single-files page.
- Completeness 1: only names are shown. The docs don't say whether order is kept, how positions work, or what happens with a missing name. The docstring adds only nested-prefix selection and an empty list.

**Task 4, range of rows.**
- Findability 2: it sits in "Finer-grained Reading and Writing" with no heading naming a row range.
- Completeness 2: row groups and `iter_batches` are shown with output. There is no skip/limit and no statement of what an out-of-range row group does. The cost is only hinted at: batches are described as memory-efficient, and filters as skipping row groups.

**Task 5, schema and metadata.**
- Findability 2: the heading is "Inspecting the Parquet File Metadata", but it takes two steps to reach.
- Completeness 2: it covers schema, row count, row groups, compression, encodings, and statistics. Key-value metadata is never shown being read, apart from `store_schema` mentioning `ARROW:schema`.

**Task 6, labels:** all 0. The docs say nothing about variable labels or value labels. `read_dictionary` gives a categorical, but it has no connection to labels.

**Task 7, dates and timestamps.**
- Findability 2: the section is "Storing timestamps" on the type-handling page.
- Correctness 1: that page says "the default is to write version 1.0 files" and recommends "the default version 1.0". The `write_table` docstring gives the default as "2.6", and the metadata outputs show `format_version: 2.6`. Under 2.6, nanoseconds are written natively, not cast to microseconds as the page says. A reader would be misled about what a default write produces.
- Completeness 2: units, `coerce_timestamps`, truncation errors, and INT96 are covered. DATE is not mentioned. Out-of-range values and the difference between naive and zoned times get only a passing mention in the `store_schema` docstring.
- Clarity 2: the examples have no output, and the page contradicts the docstring on the default.

**Task 8, write a table.**
- Findability 2: it is on the single-files page, with the docstring behind it.
- Correctness 2: the same contradiction about the default `version` (1.0 on the type-handling page, 2.6 in the docstring) affects what a default write produces.
- Completeness 2: the write call, codecs with the snappy default, and row group size (in the docstring) are covered. There is no table mapping Arrow types to Parquet types, and what counts as an error is only partly listed.

**Task 9, write labels and check them:** all 0. Nothing is documented about attaching or reading back labels.

**Task 10, keeping `.a` to `.z`:** all 0. The docs say nothing about extended missing values.

**Task 11, read another tool's file.**
- Findability 2: the relevant text is spread across "Compression, Encoding, and File Compatibility", the type-handling page, and the encryption page.
- Correctness 2: the timestamp and version compatibility advice ("default is 1.0") conflicts with the docstring.
- Completeness 2: read options for dictionary, binary, list, extension types, INT96, and encryption are documented. Which codecs and encodings are read is not listed. Unsupported features are not listed. What other tools see in files this library writes is covered only through the `version` and `flavor` notes.
- Clarity 2: there is no single place to read. The answer has to be pieced together.

## Task scores

| task | Library A | Library B |
|---|---|---|
| 1 | 2.50 | 2.75 |
| 2 | 3.00 | 2.25 |
| 3 | 3.00 | 2.25 |
| 4 | 3.00 | 2.50 |
| 5 | 3.00 | 2.50 |
| 6 | 3.00 | 0.00 |
| 7 | 2.75 | 1.75 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 0.00 |
| 10 | 2.75 | 0.00 |
| 11 | 3.00 | 2.00 |
| **Total** | **32.00** | **18.25** |
