```json
{"A": {"1": [3,3,3,3], "2": [3,3,3,3], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,3,3,3], "7": [3,3,3,2], "8": [3,3,3,3], "9": [3,3,3,3], "10": [3,3,3,2], "11": [3,3,3,3]},
 "B": {"1": [3,3,3,3], "2": [2,3,2,3], "3": [2,3,1,3], "4": [2,3,1,2], "5": [2,3,2,3], "6": [1,2,1,2], "7": [2,1,2,2], "8": [2,2,2,3], "9": [0,0,0,0], "10": [0,0,0,0], "11": [2,1,2,3]}}
```

## Reasons for scores below 3

### Library A

- **Task 7, clarity 2.** The "Dates and other files" paragraph packs several rules together: `.a` to `.z` stored as a DOUBLE, a fraction of a day, `"unit": "s"`, and R-written values. A reader has to reread it to see what a plain DATE or TIMESTAMP becomes. The worked example and the table are clear.
- **Task 10, clarity 2.** There are two parallel mechanisms (`meta.missing` and companion columns), and the guide adds a "changes rows" warning. One sentence is garbled ("so `x` in a byte column comes back as `Int8` with its letters"). The examples with their output rescue it, but it takes rereading.

### Library B

- **Task 2.**
  - Findability 2: the front page goes to parquet/index, then to the single-files page, so two links.
  - Completeness 2: the read call and the returned Table are shown, but there is no table of what each Parquet type becomes. Only dictionary, binary/list, extension types and timestamps are covered, and what is lost or refused is barely mentioned.
- **Task 3.**
  - Findability 2: the example sits on a long page two links in.
  - Completeness 1: only the main path of naming columns. Positions are not mentioned, the docs never say whether order is kept, and they do not say what happens with a name not in the file. The nested-prefix rule appears only in the API reference.
- **Task 4.**
  - Findability 2: row groups and batches are spread across a long page and the API entries.
  - Completeness 1: there is no skip/limit. `read_row_group`, `read_row_groups` and `iter_batches` are shown, but not how to get rows 100–150. Out-of-range behaviour is not stated, and the cost is only hinted at (the page index is not used on read).
  - Clarity 2: the examples are clear, but the docs never connect them to "read a range of rows".
- **Task 5.**
  - Findability 2: the "Inspecting the Parquet File Metadata" heading is two links in.
  - Completeness 2: the schema, row count, row groups, compression and statistics are shown. Footer key-value metadata is not shown, and the Arrow type each column becomes comes only from `read_schema`, with no mention in this section.
- **Task 6.**
  - Findability 1: only `read_dictionary` (a column read as categorical) is there, and no heading names this task.
  - Correctness 2: what is said is true, but it covers only the categorical part.
  - Completeness 1: nothing on variable labels or value labels, and no code-to-text lookup. Only the turn-to-categorical step is covered.
  - Clarity 2: the dictionary example has its output, but it does not address labels.
- **Task 7.**
  - Findability 2: the "Storing timestamps" section is inside the type-handling page.
  - Correctness 1: that section says the default is to write version 1.0 files and recommends the "default 1.0". The API reference says the `write_table` default is `version="2.6"`, and `parquet.rst` shows `format_version: 2.6`. A reader would wrongly expect nanoseconds to be cast to microseconds by default.
  - Completeness 2: units and truncation are covered, and time zones only through the `store_schema` note and the tzdata install note. There is no statement of what DATE and TIMESTAMP become on read, nothing on out-of-range values, and little on how naive and zoned times differ.
  - Clarity 2: there is no example with output showing what comes back.
- **Task 8.**
  - Findability 2: the write section is inside a long page, two links in.
  - Correctness 2: the same version-default contradiction appears in the type-handling page, and the API reference is right. The compression and `row_group_size` defaults are correct.
  - Completeness 2: the codec list and default, the `row_group_size` default, per-column settings and the timestamp exception are covered. There is no table mapping Arrow types to Parquet types and no list of what is an error.
- **Task 9.** Nothing in the supplied text covers attaching variable labels, value labels or a data label. Key-value metadata is not shown as a way to carry labels, and the docs do not describe reading them back. All four scores are 0.
- **Task 10.** Not covered, and the library cannot do it. Nothing on `.a` to `.z`, tagged values or what other tools see. All four scores are 0.
- **Task 11.**
  - Findability 2: the encryption page, the type-handling page and the "Compression, Encoding, and File Compatibility" heading are separate.
  - Correctness 1: the compatibility advice rests on the wrong "default is version 1.0" claim, which matters for what other tools see in files this library writes.
  - Completeness 2: codecs for writing are listed, along with JSON/UUID extension types, INT96, nested list reading and encryption. The text does not list which encodings or codecs can be read, and does not list what is not supported.

## Task scores

| task | A | B |
|---|---|---|
| 1 | 3.00 | 3.00 |
| 2 | 3.00 | 2.50 |
| 3 | 3.00 | 2.25 |
| 4 | 3.00 | 2.00 |
| 5 | 3.00 | 2.50 |
| 6 | 3.00 | 1.50 |
| 7 | 2.75 | 1.75 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 0.00 |
| 10 | 2.75 | 0.00 |
| 11 | 3.00 | 2.00 |
| **Total** | **32.50** | **19.75** |
