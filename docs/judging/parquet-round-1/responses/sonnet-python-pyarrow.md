```json
{"A": {"1": [3,3,3,3], "2": [2,3,2,3], "3": [2,3,1,3], "4": [2,3,1,2], "5": [2,3,2,3], "6": [0,0,0,0], "7": [2,1,2,2], "8": [2,2,2,3], "9": [0,0,0,0], "10": [0,0,0,0], "11": [2,2,2,2]},
 "B": {"1": [2,3,3,3], "2": [2,3,3,3], "3": [2,3,3,3], "4": [2,3,3,3], "5": [2,3,3,3], "6": [2,3,3,3], "7": [2,3,3,3], "8": [2,3,3,3], "9": [2,3,3,2], "10": [2,3,3,2], "11": [3,3,3,3]}}
```

Scores are in the order findability, correctness, completeness, clarity.

## Library A

Library A's bundle never mentions Stata, value labels, variable labels, data labels or extended missing values. Tasks 6, 9 and 10 therefore score 0 on all four, as "not covered". The one nearby feature is `read_dictionary`, which gives a categorical for string and binary columns. It says nothing about labels.

- **Task 1 (install):** no reason for a score below 3. `install.rst` is a toctree entry on the front page. It gives the pip and conda commands, platforms, Python versions, the pip >= 19 and Visual C++ Redistributable failure notes, and the tzdata notes.
- **Task 2 (read a whole file):**
  - Findability 2: the answer is two links down (the front-page toctree, then the Parquet index, then the single-files page), and no heading says "read a whole file".
  - Completeness 2: the docs show `read_table` and its return type. There is no table of what each Parquet type becomes, only fragments (`read_dictionary`, `binary_type`, `list_type`, extension types, INT96 as nanoseconds). Nothing says what is refused.
- **Task 3 (read some columns):**
  - Findability 2: the `columns=` example sits in the opening prose of the single-files page, with no heading of its own.
  - Completeness 1: only names are shown. The docs do not say whether positions work, whether order is kept, or what an unknown name does. The API reference adds only the nested-prefix rule.
- **Task 4 (read a range of rows):**
  - Findability 2: the material is under "Finer-grained Reading and Writing", which does not name the task.
  - Completeness 1: there is no skip/limit. `read_row_group` and `iter_batches` are shown, but nothing says what an out-of-range request does or what any of it costs.
  - Clarity 2: the examples run, but a reader still cannot see how to get "rows 100 to 150" from them.
- **Task 5 (schema and metadata):**
  - Findability 2: the "Inspecting the Parquet File Metadata" heading is on a long page, two links from the front page.
  - Completeness 2: row count, row groups, compression and the schema are all shown. Key-value metadata is never shown being read; "ARROW:schema" appears only in the `store_schema` docstring.
- **Task 7 (dates and timestamps):**
  - Findability 2: the answer is in the Type Handling page, "Storing timestamps".
  - Correctness 1: that page says the default is to write version 1.0 files, so nanoseconds become microseconds. The `write_table` reference gives the default version as "2.6", under which nanoseconds are written natively. The `format_version: 2.6` in the metadata output agrees with the reference. A reader following the guide would expect the wrong default.
  - Completeness 2: units, the truncation error, INT96 and `coerce_timestamps` are covered. There is no statement of what DATE and TIMESTAMP become in Python, nothing on out-of-range values, and nothing on naive versus zoned times beyond a line in the `store_schema` entry.
  - Clarity 2: the version contradiction, and examples that show no output.
- **Task 8 (write a table):**
  - Findability 2: the answer is spread across "Parquet file writing options" and "Compression, Encoding, and File Compatibility".
  - Correctness 2: the version-default contradiction from task 7 applies. The reference page is right.
  - Completeness 2: the write call, codecs with the snappy default, and `row_group_size` (in the reference) are covered. There is no Arrow-to-Parquet type mapping table, and few statements of what is an error.
- **Task 11 (read a file another tool wrote):**
  - Findability 2: the material is split across the compression section, the Spark section, the type handling page and the encryption page.
  - Correctness 2: the "default is version 1.0" claim is wrong, and that is the compatibility advice.
  - Completeness 2: codecs, encodings, INT96, extension types, `flavor="spark"` and encryption are covered. There is no explicit list of what is read or refused, and nothing on what other tools see in the files it writes beyond the version advice.
  - Clarity 2: the same contradiction.

## Library B

- **Findability, tasks 1 to 10:** 2 for each. The README points to the language page or `docs/parquet.md`, and the answer is a named heading one more link away, listed in the Parquet contents line. The exception is task 11, scored 3: the "Read a file another tool wrote" and "What other tools see in our files" headings in `docs/parquet.md` are one link from the README and contain the answer.
- **Task 1 (install):** nothing below 3 beyond findability. It gives the commands, Python 3.10, Rust, a C compiler and polars 2, and the fixes for "cargo not found", no network access and the ABI mismatch error. The "Wheels are built for…" sentence sits oddly next to "not on PyPI, install from a checkout", but I did not count it as an error.
- **Tasks 2 to 5 and 7 (read, columns, rows, schema, dates):** each is complete and has examples with output.
  - Task 2: the type table and the list of what is refused (FLOAT16, INTERVAL, nested, encrypted) are both there.
  - Task 3: names and positions, order, `KeyError` and `IndexError` are all covered.
  - Task 4: `skip`/`n_max`, out-of-range behaviour and cost are all covered.
  - Task 5: rows, row groups, codecs, key-value entries and per-column dtypes are all covered.
  - Task 7: units, zones, naive versus zoned, out-of-range errors and `timestamps="truncate"` are all covered.
- **Task 6 (value and variable labels):** the reading side is complete. Label lookup is `meta.labels`, a categorical comes from `factors=True`, and the loss from `factors=True` is spelled out. Clarity 3, since the examples show their results.
- **Task 8 (write a table):** complete. It has the write call, codec and default, row group size, type table and errors.
- **Task 9 (write labels and check them):**
  - Clarity 2: the example introduces `dk.LETTERS`, `missing=` and `rows=` before they are explained, and `%8.0g` and `.d` are not explained at that point. The reader has to follow a later section.
- **Task 10 (keep `.a` to `.z`):**
  - Clarity 2: the section never says what `.a` to `.z` mean in Stata (the README does). It leans on terms such as "tagged NaNs" and "companion columns".
  - Completeness is fine: it covers how the letters are held, `meta.missing`, `letters="columns"`, and how to write and read them back. It also covers what other tools see (NaN, with `IS NULL` false), `missing_letters=False`, and which dtypes can hold letters.
- **Task 11 (read a file another tool wrote):** complete, with codecs, encodings, types, what is refused, nested columns, encryption and a "what other tools see" table. The only gap is that the Python page's "not read" list omits BIT_PACKED, which only the errors table in `docs/parquet.md` names. I did not deduct for it.

## Task scores

| Task | Library A | Library B |
|---|---|---|
| 1 | 3.00 | 2.75 |
| 2 | 2.50 | 2.75 |
| 3 | 2.25 | 2.75 |
| 4 | 2.00 | 2.75 |
| 5 | 2.50 | 2.75 |
| 6 | 0.00 | 2.75 |
| 7 | 1.75 | 2.75 |
| 8 | 2.25 | 2.75 |
| 9 | 0.00 | 2.50 |
| 10 | 0.00 | 2.50 |
| 11 | 2.00 | 3.00 |
| **Total** | **18.25** | **30.00** |
