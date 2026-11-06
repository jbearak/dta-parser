```json
{"A": {"1": [2,2,2,3], "2": [3,3,1,2], "3": [1,3,1,2], "4": [1,3,1,2], "5": [1,3,1,2], "6": [0,0,0,0], "7": [0,0,0,0], "8": [3,3,2,3], "9": [1,2,1,1], "10": [0,0,0,0], "11": [1,3,1,2]},
 "B": {"1": [3,3,3,3], "2": [3,3,3,3], "3": [3,3,3,3], "4": [3,3,3,3], "5": [3,3,3,3], "6": [3,3,3,2], "7": [3,3,3,3], "8": [3,3,3,3], "9": [3,3,3,2], "10": [3,3,3,2], "11": [3,3,3,3]}}
```

## Library A: reasons for scores below 3

**Task 1, install.**
- Findability 2: the front page (index.md) does not link to the install page. A reader goes through "next chapter" or the navigation to reach `user-guide/installation.md`.
- Correctness 2: the page says "legacy CPUs without AVX2" in one place and "without AVX" in another. Also, the Rust snippet pins an old-looking version (`0.26.1`), though the Python part is right.
- Completeness 2: it gives the command, the extras and the legacy-CPU and big-index variants. It gives no supported Python versions or platforms, and no advice for when installation fails.

**Task 2, read a whole file.**
- Completeness 1: it shows only `pl.read_parquet(path)` and says a DataFrame comes back. It never says what each Parquet type becomes, or what is lost or refused.
- Clarity 2: there is one line of code and no result is described.

**Task 3, read some columns.**
- Findability 1: this is only in the `read_parquet` parameter reference. The Parquet guide page does not mention it.
- Completeness 1: it says `columns` takes names or zero-based indices. It does not say whether order is kept, and it does not say what happens with a name that is not in the file.
- Clarity 2: there is no example.

**Task 4, read a range of rows.**
- Findability 1: only the `n_rows` parameter entry covers it, with no guide pointer.
- Completeness 1: there is a limit (`n_rows`, and only for the non-PyArrow reader). There is no skip or offset, no row-group or batch access, nothing on out-of-range requests, and nothing on cost.
- Clarity 2: no example.

**Task 5, schema and metadata without the data.**
- Findability 1: `read_parquet_schema` and `read_parquet_metadata` appear only in the API reference.
- Completeness 1: the schema gives names and types as a dict, and `read_parquet_metadata` gives custom key-value metadata. Row count, row groups and compression are not covered. The page does not say what each type becomes in polars.
- Clarity 2: there are no examples, though the return values are described.

**Task 6, value labels and variable labels.**
- All four scores 0: nothing is said about variable labels, value labels, or turning a labelled column into a categorical.

**Task 7, dates and timestamps.**
- All four scores 0: nothing is said about DATE or TIMESTAMP, units, time zones, or out-of-range values. The only related text is the Hive date-parsing flag.

**Task 8, write a table.**
- Completeness 2: it covers the write call, the codec choices, compression levels and the row-group default (512^2 rows). It does not state the default codec. It has no table of how each language type maps to a Parquet type, and no list of what is an error.

**Task 9, write labels and check them.**
- Findability 1: nothing mentions labels. A reader might infer that the generic `metadata` and `arrow_schema` parameters could carry them.
- Correctness 2: nothing it says is wrong, but labels are not covered.
- Completeness 1: it says only that key-values can be attached, and that `read_parquet_metadata` reads them back.
- Clarity 1: no example, and no mention of labels.

**Task 10, keep `.a` to `.z`.**
- All four scores 0: nothing is said about this.

**Task 11, read a file another tool wrote.**
- Findability 1: only scattered parameters (`decryption`, `use_pyarrow`, `schema`) bear on it.
- Completeness 1: encryption is mentioned as an unstable option. There is no list of codecs, encodings or types, nothing on nested columns, and nothing on what other tools see in files this library writes.
- Clarity 2: what is there is clear, but it is thin.

## Library B: reasons for scores below 3

**Task 6, value labels and variable labels.**
- Clarity 2: Stata terms are used without explanation. Examples are "value label set" and "Stata's `encode`", and the notion of codes versus labels is assumed. The code examples with printed results are clear.

**Task 9, write labels and check them.**
- Clarity 2: "data label" and "characteristics" are never explained for a reader who does not know Stata. The worked example with read-back output is clear.

**Task 10, keep `.a` to `.z`.**
- Clarity 2: the section is dense. It has several mechanisms (`meta.missing`, companion columns, tagged NaNs, a staleness check) and assumes the reader knows what `.a` to `.z` mean and how `.` differs from them.

## Task scores

| Task | Library A | Library B |
|---|---|---|
| 1 | 2.25 | 3.00 |
| 2 | 2.25 | 3.00 |
| 3 | 1.75 | 3.00 |
| 4 | 1.75 | 3.00 |
| 5 | 1.75 | 3.00 |
| 6 | 0.00 | 2.75 |
| 7 | 0.00 | 3.00 |
| 8 | 2.75 | 3.00 |
| 9 | 1.25 | 2.75 |
| 10 | 0.00 | 2.75 |
| 11 | 1.75 | 3.00 |
| **Total** | **15.50** | **32.25** |
