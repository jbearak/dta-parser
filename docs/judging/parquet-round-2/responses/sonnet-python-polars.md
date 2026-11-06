```json
{"A": {"1": [2, 2, 2, 3], "2": [2, 3, 1, 2], "3": [1, 3, 1, 2], "4": [1, 3, 1, 2], "5": [1, 3, 1, 2], "6": [0, 0, 0, 0], "7": [0, 0, 0, 0], "8": [2, 2, 2, 2], "9": [1, 2, 1, 1], "10": [0, 0, 0, 0], "11": [1, 3, 1, 1]},
 "B": {"1": [3, 2, 3, 2], "2": [3, 3, 3, 3], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 3, 2], "7": [3, 3, 3, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 3], "11": [3, 2, 3, 3]}}
```

Order of scores: findability, correctness, completeness, clarity. Scores of 3 are not explained.

## Library A

Library A's front page (`index.md`) has no table of contents and no link to the Parquet page. Its guide page is short, and most of what it offers is in the function reference.

1. Install: [2, 2, 2, 3]
   - Findability 2: the installation page is not linked from the front page, except as "next chapter".
   - Correctness 2: the legacy-CPU note says "without AVX2 support" in one place and "without AVX support" in another. Also, `pip install polars[rtcompat]` is unquoted in one place and quoted in another.
   - Completeness 2: the install command and the options are given. Supported Python versions and platforms are not stated, and the only guidance when installation fails is the legacy-CPU variant.
2. Read a whole file: [2, 3, 1, 2]
   - Findability 2: the Parquet guide page has a "Read" heading, but the front page does not point to it.
   - Completeness 1: it gives the call and says a `DataFrame` comes back. It says nothing on how Parquet types map to polars types, or on what is lost or refused. Nested columns are not mentioned.
   - Clarity 2: the example has no output. The return type is stated only in the reference.
3. Read some columns: [1, 3, 1, 2]
   - Findability 1: the only mention is the `columns` entry in the function reference.
   - Completeness 1: names and indices are accepted. Whether order is kept and what a name that is not in the file does are not said.
   - Clarity 2: the parameter text is plain but has no example.
4. Read a range of rows: [1, 3, 1, 2]
   - Findability 1: only the `n_rows` entry in the reference.
   - Completeness 1: there is a row limit but no skip or offset. What an out-of-range request does and what a read costs are not said. Row groups and batches are not discussed.
   - Clarity 2: no example.
5. Schema and metadata without data: [1, 3, 1, 2]
   - Findability 1: reference entries only.
   - Completeness 1: the schema (name to dtype) and file-level key-value metadata are covered. Row count, row groups and compression are not.
   - Clarity 2: no example. The return types are stated.
6. Value labels and variable labels: [0, 0, 0, 0]. Nothing in the text.
7. Dates and timestamps: [0, 0, 0, 0]. Nothing on what DATE and TIMESTAMP become, units, time zones or range. Only `try_parse_hive_dates` is mentioned.
8. Write a table: [2, 2, 2, 2]
   - Findability 2: the guide has a "Write" heading, but the front page does not link to it.
   - Correctness 2: the reference example uses an undefined `dirpath`, which needs an obvious fix.
   - Completeness 2: the codec choices, compression levels and the row-group default (512^2 rows) are given. The default codec is not stated. The mapping of language types to Parquet types and what is an error are missing.
   - Clarity 2: the guide example has no output.
9. Write labels and check them: [1, 2, 1, 1]
   - Findability 1: only the `metadata` and `arrow_schema` entries in the reference.
   - Correctness 2: what is said is true, but nothing is said about labels.
   - Completeness 1: generic file-level and field-level key-value metadata can be attached. Variable labels, value labels and the data label are not mentioned, and neither is reading them back.
   - Clarity 1: no example, and the task is not framed.
10. Keep `.a` to `.z`: [0, 0, 0, 0]. Nothing in the text.
11. Read a file another tool wrote: [1, 3, 1, 1]
    - Findability 1: scattered across the reference.
    - Completeness 1: only the `decryption` parameter and the `use_pyarrow` fallback are mentioned. Supported codecs, encodings and types, nested columns and what other tools see are not covered.
    - Clarity 1: nothing is explained as a task and there is no example.

## Library B

Parquet is reachable from the README's feature list. `docs/parquet.md` has one heading per task, and each links to the Python section, which has its own contents list.

1. Install: [3, 2, 3, 2]
   - Correctness 2: `docs/parquet.md` says "Nothing beyond the package", but the Python page requires a Rust toolchain, a C compiler and polars 2. The Python page also says wheels are built for several platforms while saying nothing is on PyPI and that pip builds the extension from the checkout. That is mildly confusing.
   - Clarity 2: "the two cannot be installed in one environment" does not say which two.
2. Read a whole file: [3, 3, 3, 3]
3. Read some columns: [3, 3, 3, 3]
4. Read a range of rows: [3, 3, 3, 3]
5. Schema and metadata: [3, 3, 3, 3]
6. Value labels and variable labels: [3, 3, 3, 2]
   - Clarity 2: Stata's `encode` is used without explanation, and "value label set" is only explained by the example. The `factors=True` section can be read as saying letters survive a save, while elsewhere saving an Enum with letters is an error.
7. Dates and timestamps: [3, 3, 3, 3]
8. Write a table: [3, 3, 3, 3]
9. Write labels and check them: [3, 3, 3, 3]
10. Keep `.a` to `.z`: [3, 3, 3, 3]
11. Read a file another tool wrote: [3, 2, 3, 3]
    - Correctness 2: the Python page says "every encoding" is read. The error table lists BIT_PACKED as not read, and the Python list of what is not read leaves it out.

## Task scores

| task | A | B |
|---|---|---|
| 1 | 2.25 | 2.50 |
| 2 | 2.00 | 3.00 |
| 3 | 1.75 | 3.00 |
| 4 | 1.75 | 3.00 |
| 5 | 1.75 | 3.00 |
| 6 | 0.00 | 2.75 |
| 7 | 0.00 | 3.00 |
| 8 | 2.00 | 3.00 |
| 9 | 1.25 | 3.00 |
| 10 | 0.00 | 3.00 |
| 11 | 1.50 | 2.75 |
| **Total** | **14.25** | **32.00** |
