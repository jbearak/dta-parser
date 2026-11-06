# Gate 2, Python: can the docs alone get a user through Parquet with datakit?

Source used: `/private/tmp/claude-501/gate2/fresh/python/docs.md` only. I read no library source, tests or other checkout files. Built and installed from `/private/tmp/claude-501/gate2/fresh/python/checkout`.

Environment: macOS, Python 3.14 venv at `scratch/venv`. Installed: dta-parser 0.3.0, dta-datakit 0.3.0, polars 2.1.0, pandas 3.1.1, numpy 2.5.4, plus pyarrow (for task 11). All files I read were written by me (library, pyarrow, pandas, polars); outputs are in `scratch/out/`. Scripts: `t2_5.py`, `t6_10.py`, `t11.py`; their output is in the `.out` files beside them. DuckDB is not installed, so I did not run the docs' DuckDB snippets.

Environment note, not a docs problem: inside the tool sandbox, pip could not verify PyPI's certificate (`SSLCertVerificationError OSStatus -26276`), so `pip install` failed at "Installing build dependencies" (maturin). I reran the same `pip install` outside the sandbox, with the venv still under `scratch`, and it succeeded. The docs' "pip cannot reach PyPI" troubleshooting entry matches the symptom.

A second odd thing, also not a docs problem: two of my runs (`t6_10.py` piped through `tee`, and the first `t11.py`) came back with no output and a timeout. `t6_10.py` finished in 2.4 s when rerun, and `t11.py` had a plain bug of mine (a decimal cast), so I could not reproduce a hang in the library.

---

## Task 1. Install and check load: succeeded

```sh
python3 -m venv scratch/venv
scratch/venv/bin/pip install checkout/python checkout/python/datakit
scratch/venv/bin/python -c "import datakit as dk; print(dk.read_parquet); import dta_parser; print(dta_parser.read_dta)"
```

Saw: `Successfully installed dta-datakit-0.3.0 dta-parser-0.3.0 numpy pandas polars-2.1.0 ...`. Both imports printed function objects. Running from `scratch`, not from inside `python/`, avoided the `_native` import trap the docs warn about.

Docs:
- Correct: "nothing beyond the package" and "pyarrow is not needed".
- Minor: the docs say "datakit needs `polars>=2.0,<3`", and pip pulled it in as promised.
- Minor: the install section never says how long the Rust build takes.

## Task 2. Write a mixed table and read it back: succeeded

```python
t = pl.DataFrame({"i": [1..7], "f": [1.5, 2.5, None, ...], "s": list("abcdefg"),
                  "b": [True, False, True, None, ...], "d": [date(2024,1,d) ...],
                  "ts": [datetime(2024,1,1,12,0,k) ...]})
dk.save_parquet(t, "out/t2.parquet"); back, meta = dk.read_parquet("out/t2.parquet")
```

Saw: back is a `polars.DataFrame`; `meta` is `datakit._meta.Meta`. Types are Int64, Float64, String, Boolean, Date and `Datetime(time_unit='us', time_zone=None)`, the same as the input. This matches the docs' write table and "What each type becomes".

Docs: nothing wrong. The docs never say plainly that a polars frame round-trips to the same dtypes unless Stata types are involved. The "What a round trip does not keep" paragraph implies it.

## Task 3. Two columns, reversed: succeeded

```python
dk.read_parquet("out/t2.parquet", columns=["s", "i"])   # file order is i, s
dk.read_parquet("out/t2.parquet", columns=["s", "nope"])
dk.read_parquet("out/t2.parquet", columns=[9])
```

Saw: columns come back in the order given: `['s', 'i']`, and `meta.columns` has the same order. The unknown name raises `KeyError: 'column "nope" is not in the file; its columns are "i", "f", "s", "b", "d", "ts"'`. A position out of range raises `IndexError: there is no column 9; the file has 6 data columns`. All as documented.

## Task 4. Rows 3 to 5: succeeded

```python
dk.read_parquet(p, skip=2, n_max=3)      # [3, 4, 5], meta.rows == 3
dk.read_parquet(p, skip=5, n_max=10)     # [6, 7], rows 2
dk.read_parquet(p, skip=20, n_max=3)     # shape (0, 6), full schema kept, rows 0
```

Saw: fewer rows when the window runs over the end. When it starts past the end, an empty frame with the right columns and dtypes, with no error. This matches "Rows past the end give fewer rows, or an empty frame with the right columns and dtypes; it is not an error."

Docs: unclear but minor. `skip` counts rows to skip (0-based), so "rows 3 to 5" is `skip=2, n_max=3`. The example does show `skip=2` giving ids `[3, 4]`, so a user can work it out.

## Task 5. Schema and metadata without data: succeeded

```python
info = dk.read_parquet_info("out/t2.parquet")
info.columns.select("name","dtype","physical_type","logical_type"); info.rows
info.row_groups; info.compression; info.created_by; info.key_value
```

Saw:
- 6 rows of columns, with physical/logical types INT64/null, DOUBLE/null, BYTE_ARRAY/STRING, BOOLEAN/null, INT32/DATE and INT64/`TIMESTAMP(MICROS, local)`.
- `rows` = 7.
- `row_groups` is a polars frame with one row group: 7 rows, 338 compressed bytes, 362 uncompressed.
- `compression` = `['snappy']`.
- `created_by` = `dta-parquet version 0.1.0`.
- `key_value` has `ARROW:schema` and `dta`; `dta` is `{"version":1}`.

Docs:
- Unclear: `key_value` is described as "every key-value entry of the footer as text" and is in fact a `dict[str, str]`. I had to guess `.items()` and `sorted(info.key_value)`; the docs' only usage is `sorted(info.key_value)`.
- Minor: the `logical_type` text for a timestamp without a zone is `TIMESTAMP(MICROS, local)`, a wording the docs never show.

## Task 6. .dta with labels, into Parquet, labels read back: succeeded (the docs left a gap in writing the .dta)

```python
frame = pl.DataFrame({"id": Int32, "region": Int8 [1,2,2,3,4,1], "income": [...]})
meta = dk.Meta(label=..., columns={"region": dk.Column(label="Region of residence", value_labels="reg"), ...},
               value_labels={"reg": {1: "North", 2: "South", 3: "East", 4: "West"}}, missing={...}, rows=6)
dk.save_dta(frame, "out/t6.dta", meta=meta)
df, m = dk.read_dta("out/t6.dta"); dk.save_parquet(df, "out/t6.parquet", meta=m)
back, bm = dk.read_parquet("out/t6.parquet")
bm.columns["region"].label; bm.columns["region"].value_labels; bm.labels("region"); bm.labels("region")[3]
back["region"].replace_strict(bm.labels("region"), return_dtype=pl.String).cast(pl.Categorical)
dk.read_parquet("out/t6.parquet", factors=True)
```

Saw:
- The variable label is `Region of residence`, the set name is `reg`, and `labels` is `{1: 'North', 2: 'South', 3: 'East', 4: 'West'}`.
- The text of code 3 is `East`, and `bm == m` is True.
- The `replace_strict` plus `cast` route gave `Categorical`.
- `factors=True` gave `Enum(categories=['North', 'South', 'East', 'West'])` with the labels as values.

Docs problems:
- **Missing:** this docs bundle has no example that writes a `.dta` from scratch in Python with a value-labelled column. The `dta_parser` "Write a file" section is absent from `docs.md`; only `write_dta(df, path, *, label=None, variable_labels=None, timestamp=None)` appears in the API list, and the README's pandas example sets `df.attrs["dta"]`. I wrote the `.dta` by combining `dk.Meta(...)` from "Write labels to a Parquet file" with `dk.save_dta(df, path, meta=meta)` from ".dta files into polars". It worked, but a reader has to infer that `save_dta` takes the same `Meta`. The docs do say "with the same `(df, meta)`".
- **Unclear:** the docs never say whether `rows=` is required in `dk.Meta(...)`. Every example passes it. I passed it and did not test leaving it out.
- **Unclear:** "the language's categorical type" has two answers. `factors=True` gives an Enum, and the docs call the Enum the result. `pl.Categorical` needs a manual `replace_strict(...).cast(pl.Categorical)`, which the docs never show. They show the `replace_strict` line only for turning codes into text.

## Task 7. Date, timestamp without a zone, timestamp with a zone: succeeded

```python
visits = pl.DataFrame({"day": [date(2024,3,1), None],
                       "local": [datetime(2024,3,1,9,30,0,1), None],
                       "at": [datetime(2024,3,1,9,30), datetime(2024,3,1,17,5)]}
         ).with_columns(pl.col("at").dt.replace_time_zone("America/New_York"))
# plus local_ms (ms, no zone) and at_ns (ns, zone) via cast_time_unit
dk.save_parquet(visits, "out/t7.parquet"); v, _ = dk.read_parquet("out/t7.parquet")
```

Saw (through `read_parquet`):

| column | read back as | in the file |
|---|---|---|
| day | `Date` | INT32, DATE |
| local | `Datetime('us', None)` | INT64, `TIMESTAMP(MICROS, local)`; no profile entry |
| at | `Datetime('us', 'America/New_York')`, `2024-03-01 09:30:00-05:00` | INT64, `TIMESTAMP(MICROS, UTC)`; zone in the `dta` profile and in `ARROW:schema` |
| local_ms | `Datetime('ms', None)` | `TIMESTAMP(MILLIS, local)` |
| at_ns | `Datetime('ns', 'America/New_York')` | `TIMESTAMP(NANOS, UTC)` |

pyarrow reads the file as `timestamp[us]` for no zone and `timestamp[us, tz=America/New_York]` for the zoned column. The profile reads `{"version":1,"columns":{"at":{"tz":"America/New_York"},"at_ns":{...}}}`. All as documented.

Docs: nothing wrong. The statement that a unit is kept ("in its own unit") held for ms, us and ns.

## Task 8. Codec, row group size, errors: succeeded

```python
dk.save_parquet(df8, "out/t8.parquet", meta=m8, compression="zstd", compression_level=3, row_group_size=4)
dk.read_parquet_info("out/t8.parquet")
```

Saw: `compression ['zstd']`, row groups `[4, 2]` for 6 rows. pyarrow's own metadata agrees: ZSTD, 2 row groups.

Errors:

| call | result |
|---|---|
| `compression="lzo"` | `ValueError: compression is "snappy", "zstd", "gzip", "lz4_raw" or "none", not 'lzo'` |
| zstd, `compression_level=99` | `ValueError: zstd levels run from 1 to 22, not 99` |
| snappy with a level | `ValueError: snappy has no compression levels` |
| `LazyFrame` | `TypeError: save_parquet takes a polars DataFrame, not a LazyFrame; call .collect() on it first` |
| `Decimal` column | `TypeError: column "x" is Decimal, which save_parquet does not write; cast it to Float64 or String` |
| `List`, `Duration` | `TypeError: column "x" is List, which save_parquet does not write; cast it to a type save_parquet writes` |

Docs problems:
- **Unclear:** the docs' error table in `parquet.md` gives the R wording for the compression messages (`unknown compression "lzo"; use one of ...`). The Python rows of that table do not list the compression or level errors, and the Python page says only "An unknown `compression` raises `ValueError` listing the codecs". A Python reader looking up the table would not match the actual text, and the level errors have no Python entry. The behaviour is right.
- **Minor:** the Python page says `Duration, List, ... raise TypeError naming the column`; they do, but the hint text is the generic "cast it to a type save_parquet writes".

## Task 9. Variable label, value labels, data label, written and checked: succeeded

Used the docs' own "Write labels" example (`Meta` with `label`, `notes`, a `Column` with `label`, `format`, `value_labels`, a set with `.d`, and `missing`).

Saw on reading back:
- `Smoking ['Wave 2 only.']`
- `Column(label='Smokes daily', format='%8.0g', value_labels='yesno', ordered=None)`
- `{0: 'No', 1: 'Yes', '.d': "Don't know"}`
- `[None, None, '.d']`
- `s_meta == m9` is True.

`read_parquet_info` agrees, and its profile JSON reads `{"version":1,"label":"Smoking","notes":[...],"columns":{"smoker":{"label":"Smokes daily","format":"%8.0g","value_labels":"yesno","storage":"byte"}},"value_labels":{"yesno":[[0,"No"],[1,"Yes"],[".d","Don't know"]]}}`. The column reports `storage` = `byte` because it holds `.d`, as documented. No docs problem.

## Task 10. ordinary values, `.`, `.a`, `.z`: succeeded

I put the column `income` in the `.dta` of task 6, with `meta.missing["income"]` = `[None, None, None, ".a", ".z", None]` and a null in row 2 for `.`. Then `read_dta`, `save_parquet`, `read_parquet`.

Saw, with the per-value result:

| row | value | letter | kind |
|---|---|---|---|
| 1 | 2100.0 | None | value |
| 2 | None | None | `.` |
| 3 | 1850.0 | None | value |
| 4 | None | `.a` | `.a` |
| 5 | None | `.z` | `.z` |
| 6 | 3200.0 | None | value |

`letters="columns"` gives `income_letter` with the same pattern. The file holds `income` as DOUBLE with storage in the profile.

What other tools see, which is what the docs say ("Other tools see `NaN`"):
- polars' own reader: `[2100.0, None, 1850.0, nan, nan, 3200.0]`, so `.a` and `.z` are NaN, not null, and `.` is null.
- pyarrow: same, with `nan` for `.a` and `.z`.
- pandas: all three of `.`, `.a` and `.z` are `nan`, i.e. missing.
- `missing_letters=False` writes `.a` and `.z` as nulls (null_count 3), and the letters are gone.
- I also wrote an `Int8` column directly with `meta.missing` letters; it read back as `Int8 [1, None, None, None]` with `[None, None, '.a', '.z']`, and polars saw `[1.0, None, nan, nan]`.

Docs: nothing wrong. Unclear: to tell `.` apart from a value-null, you check the `meta.missing` letter for that row. Every null in the frame is a Stata missing value, so a null without a letter is `.`. The docs say "`.`, `.a` and `.z` are all polars nulls" and "which letter each null was is in `meta`", but never state that rule in one sentence.

## Task 11. A file another tool wrote: succeeded

pyarrow wrote the file (`out/t11_pyarrow.parquet`: int64 with null, float64 with NaN and null, string, uint8, date, timestamp with zone, dictionary-encoded string, decimal128(10,2)).

Saw from `dk.read_parquet`: `Int64`, `Float64` (NaN kept as a value, null as null), `String`, `UInt8`, `Date`, `Datetime('us', 'Europe/Paris')`, `Categorical`, and `Decimal(precision=10, scale=2)`. `meta.label` is None, `meta.columns[...]` are empty `Column`s, and `meta.missing` is `{}`, as documented ("a NaN is a value").

Also read fine: a pyarrow file with zstd, data page v2 and DELTA_BINARY_PACKED, DELTA_BYTE_ARRAY and BYTE_STREAM_SPLIT encodings; a brotli file; a pandas file; a polars file; a polars `lz4` file (lz4_raw).

What the docs say it does not read: "FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, and encrypted files", plus nested columns unless `columns=` leaves them out or `nested="skip"`. I checked two:
- FLOAT16: `ValueError: out/t11_f16.parquet: column "h" is FLOAT16, which is not read`; with `columns=["k"]` the same file reads.
- Nested list column: `ValueError: the file has nested columns, which are not read: "l"; select the columns wanted, or pass nested="skip"`; `nested="skip"` reads the rest, and `read_parquet_info` shows the column with role `nested` and dtype null.

I could not check INTERVAL, LZO, Hadoop-framed LZ4 or encryption: pyarrow on this machine wrote only lz4_raw when asked for `lz4`, and has no LZO or INTERVAL writer I could use.

Docs problems:
- **Unclear:** `parquet.md` says it reads "the types plan 0018 lists", pointing at a plan that is not part of the docs a reader is given.
- **Minor:** the FLOAT16 error text begins with the file path, which the docs' error table does not show.

---

## Summary of doc problems, in order of weight

1. Task 6: no Python example of writing a `.dta` with a value-labelled column in datakit (`dk.save_dta` with a `Meta`). The `dta_parser` "Write a file" section is not in the docs given. It worked by combining two other sections.
2. Task 6: the docs never say whether `Meta(rows=...)` is required, and they never show how to get `pl.Categorical` (only `Enum` via `factors=True`).
3. Task 8: the error table in `parquet.md` uses R's wording for compression and level errors and lists no Python rows for them; the Python page only says "ValueError listing the codecs".
4. Task 5: `info.key_value` is called "text" and is a `dict[str, str]`; `logical_type` has values like `TIMESTAMP(MICROS, local)` that the docs never show.
5. Task 10: the rule "a null with no letter is `.`" is implied, never stated.
6. Task 11: "the types plan 0018 lists" refers to a document the reader does not have.
