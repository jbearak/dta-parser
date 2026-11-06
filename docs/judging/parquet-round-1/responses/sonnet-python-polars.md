```json
{"A": {"1": [2, 3, 3, 3], "2": [3, 3, 3, 3], "3": [3, 3, 3, 3], "4": [3, 3, 3, 3], "5": [3, 3, 3, 3], "6": [3, 3, 3, 3], "7": [3, 3, 3, 3], "8": [3, 3, 3, 3], "9": [3, 3, 3, 3], "10": [3, 3, 3, 2], "11": [3, 2, 3, 3]},
 "B": {"1": [2, 2, 2, 3], "2": [2, 3, 1, 2], "3": [1, 3, 1, 2], "4": [1, 3, 1, 2], "5": [1, 3, 1, 2], "6": [0, 0, 0, 0], "7": [0, 0, 0, 0], "8": [2, 3, 2, 2], "9": [1, 2, 1, 1], "10": [0, 0, 0, 0], "11": [1, 2, 1, 1]}}
```

## Reasons for scores below 3

### Library A

- **Task 1, findability 2.** The README says only that "each page says how to install". The Parquet-specific install is a second section, "Parquet: install", and the platform and wheel details sit in a separate "Install" section, so the reader must put the two together.
- **Task 10, clarity 2.** The section is dense (tagged NaNs, `meta.missing`, companion columns, `letters=` variants). It uses `.a` to `.z` without saying what they are; the README does that, not this section. A reader who doesn't know Stata has to reread.
- **Task 11, correctness 2.** The text says "every encoding (dictionary, PLAIN, the DELTA encodings, BYTE_STREAM_SPLIT)" is read. The errors table says BIT_PACKED is not read. That is a small overstatement.

### Library B

- **Task 1.**
  - Findability 2: the front page has no install link. Its only pointer is "next chapter", and the install page has to be found from the guide.
  - Correctness 2: the Rust example pins `polars = "0.26.1"` with old feature flags. `pip install polars[rtcompat]` is unquoted, which fails in some shells.
  - Completeness 2: no supported platforms or Python versions, and nothing on what to do if installation fails beyond the legacy-CPU variant.
- **Task 2.**
  - Findability 2: the Parquet page is reached via the user guide, not named on the front page.
  - Completeness 1: it gives the read call and says it returns a DataFrame. It says nothing on what each Parquet type becomes or what is lost or refused.
  - Clarity 2: the example is a single line and says nothing about what comes back.
- **Task 3.**
  - Findability 1: the answer is only in the `read_parquet` parameter list.
  - Completeness 1: `columns` accepts names or zero-based indices. Nothing is said about whether order is kept, or what happens with a name that is not in the file.
  - Clarity 2: one sentence, no example.
- **Task 4.**
  - Findability 1: only the `n_rows` entry in the API reference.
  - Completeness 1: `n_rows` is a limit only, and there is no skip or offset (`row_index_offset` only numbers the index). Row groups, out-of-range behaviour and cost are not covered.
  - Clarity 2: no example.
- **Task 5.**
  - Findability 1: only the API entries for `read_parquet_schema` and `read_parquet_metadata`.
  - Completeness 1: it gives column names and dtypes as a dict, and custom key-value metadata. It gives no row count, row groups or compression, and no statement of what each type will become.
  - Clarity 2: no example or output.
- **Task 6.** The documentation says nothing about value labels or variable labels. All four scores are 0.
- **Task 7.** The documentation says nothing about DATE or TIMESTAMP mapping, units, zones or out-of-range values. All four scores are 0.
- **Task 8.**
  - Findability 2: reached through the guide and API, not named on the front page.
  - Completeness 2: it lists the codecs and levels, and `row_group_size`, shown as "512^2". It does not state the default codec, the type mapping, or what is an error.
  - Clarity 2: the example has no output, and the API listing is long.
- **Task 9.**
  - Findability 1: the `metadata` parameter in the API reference is the only hook.
  - Correctness 2: what it says is true, but it is marked experimental and has no connection to labels.
  - Completeness 1: it can write file-level key-value metadata and `read_parquet_metadata` can read it back. Labels, value-label sets and a data label are not discussed.
  - Clarity 1: no example and no discussion of labels.
- **Task 10.** The documentation says nothing about `.a` to `.z`. All four scores are 0.
- **Task 11.**
  - Findability 1: only scattered API parameters.
  - Correctness 2: what is stated is true, but `use_pyarrow` and `decryption` appear with no context.
  - Completeness 1: no list of codecs, encodings or types read. Nested columns are not mentioned. Nothing says what other tools see in files this library writes, beyond a hint that snappy is safer for old readers.
  - Clarity 1: no example or explanation.

## Task scores

| Task | A | B |
|---|---|---|
| 1 | 2.75 | 2.25 |
| 2 | 3.00 | 2.00 |
| 3 | 3.00 | 1.75 |
| 4 | 3.00 | 1.75 |
| 5 | 3.00 | 1.75 |
| 6 | 3.00 | 0.00 |
| 7 | 3.00 | 0.00 |
| 8 | 3.00 | 2.25 |
| 9 | 3.00 | 1.25 |
| 10 | 2.75 | 0.00 |
| 11 | 2.75 | 1.25 |
| **Total** | **32.25** | **14.25** |
