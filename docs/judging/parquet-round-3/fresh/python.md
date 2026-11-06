# Python Parquet docs check (datakit 0.3.0, dta_parser 0.3.0)

Source of truth: only `docs.md`. Checkout at `/private/tmp/claude-501/gate2/fresh3/python/checkout`; venv at `scratch/venv` (Python 3.14.7, polars 2.1.0, pandas 3.1.1, numpy 2.5.4, plus pyarrow 26.0.1 for task 11). Scripts: `t1_5.py`, `t6_10.py`, `t7_9.py`, `t8_check.py`, `t11.py`. Files written: every `.parquet`/`.dta` in `scratch/`.

Outside the docs: the first `pip install` failed in the sandboxed shell with `SSLCertVerificationError('OSStatus -26276')` while fetching maturin from PyPI. I re-ran the same command with the sandbox off, which worked. This is an environment issue, not a doc error. The docs do say "pip downloads maturin".

## Summary

| # | Outcome | Doc problem |
|---|---|---|
| 1 | succeeded | none |
| 2 | succeeded | none |
| 3 | succeeded | none |
| 4 | succeeded | minor: nothing maps "rows 3 to 5" onto `skip=2, n_max=3` |
| 5 | succeeded | none |
| 6 | succeeded | partly missing: no .dta-writing recipe with Meta; no Categorical recipe |
| 7 | succeeded | none |
| 8 | succeeded | none |
| 9 | succeeded | none |
| 10 | succeeded | minor: plain `.` vs `LETTERS` not spelled out |
| 11 | succeeded | none |

## Task 1: install and load: succeeded

```sh
python3 -m venv scratch/venv
scratch/venv/bin/pip install checkout/python checkout/python/datakit     # one command, as the docs say
scratch/venv/bin/python -c "import dta_parser, datakit; print(dta_parser.read_dta, datakit.read_parquet)"
```

Saw: the build finished (maturin from PyPI, Rust and `cc` were present), and the output was `T1 <function read_dta ...> <function read_parquet ...>`. Installed: dta-parser 0.3.0, dta-datakit 0.3.0, polars 2.1.0, pandas 3.1.1, numpy 2.5.4.

Checked the docs' claim "importing datakit does not load pandas": `python -I -c "import sys, datakit; print('pandas' in sys.modules)"` printed `False`, so the claim is right. The first check in `t1_5.py` showed True only because that script also imports `dta_parser`.

Docs: no pyarrow needed, as stated ("so pyarrow is not needed").

## Task 2: write six columns, read back, report types: succeeded

```python
df = pl.DataFrame({"i": [1..6], "f": [1.5, 2.5, None, ...], "s": [...], "b": [True, False, True, None, False, True],
                   "d": [date(2024,1,i)...], "t": [datetime(2024,1,i,12,30,15)...]})
dk.save_parquet(df, "t2.parquet")
back, meta = dk.read_parquet("t2.parquet")
```

Types after the read: `i` Int64, `f` Float64, `s` String, `b` Boolean, `d` Date, `t` Datetime(us, no zone). The frame is a `polars.DataFrame` and `meta` is a `datakit._meta.Meta`. These are identical to the input schema.

Docs: the "What each type becomes" and "What each dtype becomes" tables predicted this. No problems.

## Task 3: two columns in reverse order; unknown column: succeeded

```python
part, pm = dk.read_parquet("t2.parquet", columns=["t", "i"])
dk.read_parquet("t2.parquet", columns=["i", "nope"])
dk.read_parquet("t2.parquet", columns=[99])
```

Saw: `part.columns == ['t', 'i']` (the order requested, and `meta.columns` has the same order).
- Unknown name: `KeyError 'column "nope" is not in the file; its columns are "i", "f", "s", "b", "d", "t"'`.
- Position out of range: `IndexError there is no column 99; the file has 6 data columns`.

Both match the docs word for word.

## Task 4: rows 3 to 5; rows past the end: succeeded

```python
dk.read_parquet("t2.parquet", skip=2, n_max=3)    # ids [3, 4, 5], meta.rows == 3
dk.read_parquet("t2.parquet", skip=4, n_max=10)   # ids [5, 6]       (fewer rows)
dk.read_parquet("t2.parquet", skip=20, n_max=3)   # shape (0, 6), all six dtypes kept
```

Rows past the end are not an error: a partial window gives fewer rows, and a window wholly past the end gives an empty frame with the right columns and dtypes. This matches "Rows past the end give fewer rows, or an empty frame with the right columns and dtypes; it is not an error."

Doc problem (minor): the docs say "`skip` rows are skipped, then at most `n_max` are read". They never say how to turn "rows 3 to 5" (1-based, inclusive) into `skip=2, n_max=3`. It is derivable, but a one-line example would help.

## Task 5: metadata without the data: succeeded

```python
info = dk.read_parquet_info("t2.parquet")
info.columns.select("name","dtype","physical_type","logical_type"); info.rows; info.row_groups; info.compression; info.key_value
```

Saw:
- Rows: 6.
- Row groups: one, with 6 rows, 317 compressed bytes and 329 uncompressed.
- Compression: `['snappy']`.
- `created_by`: `dta-parquet version 0.1.0`.
- Key-value keys: `['ARROW:schema', 'dta']`, and `dta` is `{"version":1}` because there is no profile content.
- Columns: INT64, DOUBLE, BYTE_ARRAY/STRING, BOOLEAN, INT32/DATE, INT64/`TIMESTAMP(MICROS, local)`.

Everything the docs describe is there. No problems.

## Task 6: .dta with labels, into Parquet, read labels: succeeded

```python
df = pl.DataFrame({"id": Int32, "region": Int8 [1,2,2,3,4,1], "income": [2100.0, None, 1850.0, None, None, 3200.0]})
meta = dk.Meta(label="Task six data",
    columns={"id": dk.Column(label="Respondent id"),
             "region": dk.Column(label="Region of residence", value_labels="regionlbl"),
             "income": dk.Column(label="Monthly income", value_labels="inclbl")},
    value_labels={"regionlbl": {1:"North",2:"South",3:"East",4:"West"}, "inclbl": {".a":"Don't know", ".z":"Refused"}},
    missing={"income": pl.Series("income", [None, ".a", None, None, ".z", None], dtype=dk.LETTERS)}, rows=6)
dk.save_dta(df, "t6.dta", meta=meta)
d, m = dk.read_dta("t6.dta")
dk.save_parquet(d, "t6.parquet", meta=m)
back, bm = dk.read_parquet("t6.parquet")
bm.columns["region"].label            # 'Region of residence'
bm.labels("region")                   # {1: 'North', 2: 'South', 3: 'East', 4: 'West'}
bm.labels("region")[3]                # 'East'
cat, _ = dk.read_parquet("t6.parquet", factors=True)   # Enum(categories=['North','South','East','West'])
back["region"].replace_strict(bm.labels("region"), return_dtype=pl.String).cast(pl.Categorical)   # Categorical
```

Saw: all of it worked. `read_dta` kept the Int8 and the labels, and the Parquet read gave the same labels. `factors=True` gave `Enum(categories=['North', 'South', 'East', 'West'])` with values `['North', 'South', 'South', 'East', 'West', 'North']`. The manual cast gave a polars `Categorical`.

Doc problems:
1. The docs' examples all start from `dk.read_dta("survey.dta")`. "The example file" is in the contents list, but nothing says how it is made, and the `.dta` writer is covered by a few sentences under ".dta files into polars". I had to infer how to build a .dta with labels from the `Meta` example in "Write labels to a Parquet file" and then call `save_dta(df, path, meta=meta)`. A short "write a .dta file with labels" example in the datakit section would help; the pandas route (`dp.write_dta`, `df.attrs`) is documented only in the README.
2. "Turn the column into the language's categorical type": the docs give `factors=True`, which makes a polars `Enum`, and never show a polars `Categorical`. Enum is arguably the better type, but a reader who expects `Categorical` has to work out `.cast(pl.Categorical)` on their own.

## Task 7: date, naive timestamp, zoned timestamp: succeeded

```python
visits = pl.DataFrame({"day": [date(2024,3,1), None], "naive": [datetime(2024,3,1,9,30), datetime(2024,3,1,17,5)],
                       "zoned": [...]}).with_columns(pl.col("zoned").dt.replace_time_zone("America/New_York"))
dk.save_parquet(visits, "t7.parquet"); v, _ = dk.read_parquet("t7.parquet")
```

Read back:
- `day`: `Date`. Parquet INT32 / DATE.
- `naive`: `Datetime(us, time_zone=None)`. Parquet INT64 / `TIMESTAMP(MICROS, local)`.
- `zoned`: `Datetime(us, time_zone='America/New_York')`. Parquet INT64 / `TIMESTAMP(MICROS, UTC)`, i.e. stored as an instant, with the zone in the profile (`{"columns":{"zoned":{"tz":"America/New_York"}}}`).
- `v["zoned"][0]` is `2024-03-01 09:30:00-05:00`.
- A `Datetime("ms")` column round-trips as `ms`. polars' own `pl.read_parquet` gives the same three dtypes.

Matches the docs table. No problems.

## Task 8: codec and row group size; an error: succeeded

```python
dk.save_parquet(df, "t8.parquet", compression="zstd", compression_level=5, row_group_size=3)   # 10 rows
info = dk.read_parquet_info("t8.parquet")
```

Saw: `info.compression == ['zstd']` and row groups of `[3, 3, 3, 1]`. pyarrow's `pq.read_metadata` agrees: 4 row groups of 3, 3, 3 and 1 rows, codec `ZSTD`. The data round-trips equal.

Errors, all as the docs list them, and no `t8bad.parquet` was left behind:
- `compression="lzo"`: `ValueError compression is "snappy", "zstd", "gzip", "lz4_raw" or "none", not 'lzo'`.
- `zstd` with `compression_level=99`: `ValueError zstd levels run from 1 to 22, not 99`.
- `snappy` with `compression_level=3`: `ValueError snappy has no compression levels`.
- A `LazyFrame`: `TypeError save_parquet takes a polars DataFrame, not a LazyFrame; call .collect() on it first`.
- A `Decimal` column: `TypeError column "x" is Decimal, which save_parquet does not write; cast it to Float64 or String`.

No problems. The level is not visible in the metadata, which the docs do not claim.

## Task 9: write labels, read back: succeeded

Ran the docs' "Write labels" example (a `smoker` Int8 column, `Meta` with data label, notes, variable label, format, value labels with `.d`, and letters), written to `t9.parquet` and read back.

Saw:
- Data label: `Smoking`; notes: `['Wave 2 only.']`.
- Variable label: `Smokes daily`; format: `%8.0g`.
- Value labels: `{0: 'No', 1: 'Yes', '.d': "Don't know"}`.
- Letters: `[None, None, '.d']`; the frame is `[1, 0, None]` as Int8.
- `sm == meta` is `True`.
- `read_parquet_info` reports the label and value-label set name, and `storage='byte'`.
- The footer's `dta` entry holds the whole profile, and `ARROW:schema` sits beside it.

No problems.

## Task 10: ordinary value, `.`, `.a`, `.z`: succeeded

A .dta with `income = [2100.0, .a, 1850.0, ., .z, 3200.0]` (task 6's file) went `read_dta`, then `save_parquet`, then `read_parquet`. I also wrote a direct Parquet file with `[1.0, ., .a, .z]`.

Per value after `dk.read_parquet`: `frame["income"]` is `[2100.0, None, 1850.0, None, None, 3200.0]`, and `meta.missing["income"]` is `[None, '.a', None, None, '.z', None]`.

| row | frame | `meta.missing` | kind |
|---|---|---|---|
| 1, 3, 6 | number | null | ordinary value |
| 2 | null | `.a` | `.a` |
| 4 | null | null | plain `.` |
| 5 | null | `.z` | `.z` |

With `letters="columns"`: `income_letter == [None, '.a', None, None, '.z', None]`.

What other tools see in place of `.a` to `.z`: NaN. Docs: "`.a` to `.z` are **tagged NaNs**", "Other tools see `NaN`", and a table saying pyarrow and polars give NaN, pandas gives missing, and DuckDB SQL gives NaN rather than NULL. Reading the same file with `pl.read_parquet`: `[2100.0, nan, 1850.0, None, nan, 3200.0]`, so `.a` and `.z` are NaN and plain `.` stays null. `is_null() | is_nan()` flags the three missing rows. The docs also say plain `.` is an ordinary null, and that is what I saw. With `missing_letters=False` the letters become plain nulls (`null_count() == 3`).

Doc problem (minor): the docs say `dk.LETTERS` is "an Enum of `".a"` to `".z"`" but never say that a plain `.` is represented as null in the letters Series. My first attempt put `"."` in the Series and got `polars.exceptions.InvalidOperationError: conversion from str to enum failed ... ["."]`. The "In the frame, every `.a` to `.z` is null" paragraph and "`.`, `.a` and `.z` are all polars nulls in the frame" are the nearest statement. Elsewhere the docs say missing codes can be `"."` (value labels) and `"."` appears in the JSON profile's codes, which makes the omission more likely to trip up a reader. A sentence such as "a plain `.` is null in the frame and null in the letters" would settle it.

## Task 11: a Parquet file from another tool: succeeded

pyarrow 26.0.1 (installed into the venv) wrote a table with int64 with null, float64 with NaN and null, string, dictionary-encoded string, uint8, decimal128(10,2), timestamp(us, Europe/Paris), timestamp(ns), time64(us) and binary, in 24 combinations of codec (snappy, zstd, gzip, brotli, lz4, none) × format version (1.0, 2.6) × data page version (1.0, 2.0). A pandas-written category file was also read.

Saw: all 24 files read with no error. The schema came back as Int64, Float64, String, Categorical, UInt8, `Decimal(precision=10, scale=2)`, Datetime(us, 'Europe/Paris'), Datetime(ns), Time, Binary. `meta` was empty (no label, no value labels, no letters). The NaN stayed a value (`[1.5, nan, None]`), which the docs predict: "A file without a `dta` profile reads with an empty `Meta`, and there are no letters (a NaN is a value)". `key_value` was only `ARROW:schema`. pandas' category read as `Categorical`.

What the docs say this library does not read, and what I saw:
- FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, encrypted files, and values encoded BIT_PACKED: "each an error that names the column and its type".
- Nested columns: an error unless `columns` leaves them out or `nested="skip"`. Checked: a pyarrow list column raised `ValueError t11_nested.parquet: the file has nested columns, which are not read: "l"; select the columns wanted, or pass nested="skip"`, and both `nested="skip"` and `columns=["n"]` worked.
- FLOAT16, checked with a pyarrow float16 column: `ValueError t11_f16.parquet: column "h" is FLOAT16, which is not read`. `columns=["n"]` read the rest.
- Datasets of many files, Hive partitions and filters on values are not part of datakit; use `pl.scan_parquet` (not tested).

Not tested: LZO, INTERVAL, encryption, BIT_PACKED and Hadoop-framed LZ4. pyarrow 26 writes `lz4` as LZ4_RAW and cannot write the others, so I only verified the error text for FLOAT16 and nested columns.

Doc problem: none. One thing to note is that the docs' "Files from other tools" example uses `pl.Categorical`, and my pyarrow dictionary column also came back as `Categorical`, as the docs say.
