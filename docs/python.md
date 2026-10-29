# Python: dta_parser

`dta_parser` reads Stata `.dta` files into pandas DataFrames and writes
DataFrames back as `.dta` files. It reads every release from 104 to 119
and writes release 118. Unlike `pandas.read_stata` and pyreadstat, it
keeps Stata's extended missing values `.a` to `.z` per value, through
filtering, sorting, merging and writing.

Contents:
[Install](#install) ·
[The example file](#the-example-file) ·
[Read a file](#read-a-file) ·
[Select columns](#select-columns) ·
[Read some rows](#read-some-rows) ·
[Metadata](#metadata) ·
[Missing values](#missing-values) ·
[Value labels](#value-labels) ·
[Dates](#dates) ·
[Write a file](#write-a-file) ·
[Recipes](#recipes) ·
[Coming from pandas.read_stata](#coming-from-pandasread_stata) ·
[Coming from pyreadstat](#coming-from-pyreadstat) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

`dta_parser` needs Python 3.10 or later, numpy 1.23 or later and pandas
2.2 or later (pandas 3 works). It is not on PyPI yet, so install it from
a checkout of the repository. Building needs a Rust toolchain
([rustup.rs](https://rustup.rs)):

```sh
git clone https://github.com/jbearak/dta-parser
pip install ./dta-parser/python
```

pip builds the extension with maturin and installs it. Check it:

```sh
python -c "import dta_parser; print(dta_parser.read_dta)"
```

Wheels are built for macOS (arm64), Linux (x86_64, aarch64) and Windows
(x86_64); one wheel serves every Python from 3.10. Free-threaded Python
builds are not supported.

## The example file

Every example on this page reads `survey.dta`. This block makes it; run
it first. It also shows most of what writing can do, which
[Write a file](#write-a-file) explains.

```python
import numpy as np
import pandas as pd
import dta_parser as dp
from dta_parser import missing

df = pd.DataFrame({
    "id": [1, 2, 3, 4, 5, 6],
    "region": [1, 2, 2, 3, 4, 1],
    "age": [34, 51, 29, 62, 45, 38],
    # .d = "don't know", .r = "refused"; None is Stata's `.`
    "income": pd.Series([2100.0, missing.d, 1850.0, None, missing.r, 3200.0], dtype="stata[double]"),
    "interviewed": pd.to_datetime(["2024-03-01", "2024-03-01", "2024-03-02",
                                   "2024-03-04", "2024-03-04", "2024-03-05"]),
    "comment": ["", "moved in 2023", "", "", "asked to call back", ""],
})
df.attrs["dta"] = {
    "label": "Household survey (example)",
    "columns": {
        "region": {"label": "Region", "value_labels": "region"},
        "age": {"label": "Age in years"},
        "income": {"label": "Monthly income", "value_labels": "nonresponse"},
    },
    "value_labels": {
        "region": {1: "North", 2: "South", 3: "East", 4: "West"},
        "nonresponse": {missing.d: "Don't know", missing.r: "Refused"},
    },
    "notes": ["Made up for the dta_parser documentation."],
}
dp.write_dta(df, "survey.dta")
```

## Read a file

```python
import dta_parser as dp

df = dp.read_dta("survey.dta")
print(df)
print(df.dtypes)
```

```text
   id  region  age  income interviewed             comment
0   1       1   34  2100.0  2024-03-01
1   2       2   51      .d  2024-03-01       moved in 2023
2   3       2   29  1850.0  2024-03-02
3   4       3   62     NaN  2024-03-04
4   5       4   45      .r  2024-03-04  asked to call back
5   6       1   38  3200.0  2024-03-05
id                      int8
region                  int8
age                     int8
income         stata[double]
interviewed    datetime64[s]
comment                  str
```

`read_dta(path)` takes a path (a `str` or `os.PathLike`) and returns a
`DataFrame` with a default `RangeIndex`. What each column becomes:

| in the file | in pandas |
|---|---|
| byte, int, long, float, double with no missing value | `int8`, `int16`, `int32`, `float32`, `float64` |
| the same with `.` as the only missing value | `float32` (byte, int, float) or `float64` (long, double), `.` as `NaN` |
| any numeric type with one or more of `.a` to `.z` | `StataArray`, dtype `stata[byte]` ... `stata[double]` |
| `%td` dates, `%tc` times | `datetime64[s]`, `datetime64[ms]` (see [Dates](#dates)) |
| strN, strL text | pandas' default string dtype (`str` on pandas 3, `object` on 2.2) |
| strL with binary values | `object`, holding `bytes` for those values |

Every conversion is exact: no value is rounded and no missing code is
lost. The storage type each column came from is kept in the metadata,
so writing the frame back uses it again. The integer types are the
smallest that hold the values, so arithmetic such as `df.age * 1000`
can overflow `int8`; convert first with `df.age.astype("int64")`.

## Select columns

```python
df = dp.read_dta("survey.dta", columns=["income", "id"])
print(list(df.columns))   # ['income', 'id']
```

`columns` takes names or 0-based positions, or a mix, in the order you
want them back. A single name or position works too. A name the file
does not have raises `ValueError`; a position out of range raises
`IndexError`. Naming a column twice reads it once.

## Read some rows

```python
part = dp.read_dta("survey.dta", skip=2, n_max=3)
print(part["id"].tolist())   # [3, 4, 5]
```

`skip` rows are skipped, then at most `n_max` are read (all when
`None`). The index starts at 0 again. Asking for rows past the end gives
fewer rows, or an empty frame with the right columns; it is not an
error. To read a large file in pieces, use `read_meta` for the row
count and loop:

```python
nobs = dp.read_meta("survey.dta")["nobs"]
for start in range(0, nobs, 4):
    chunk = dp.read_dta("survey.dta", skip=start, n_max=4)
    print(start, len(chunk))
```

Each call seeks to its first row, so the loop reads every row once.

## Metadata

Everything the file says about itself is in `df.attrs["dta"]`, a plain
`dict`:

```python
df = dp.read_dta("survey.dta")
info = df.attrs["dta"]
print(info["label"])                    # Household survey (example)
print(info["columns"]["income"])
# {'storage': 'double', 'format': '%10.0g', 'label': 'Monthly income', 'value_labels': 'nonresponse'}
print(info["notes"])                    # ['Made up for the dta_parser documentation.']
print(info["release"], info["encoding"], info["timestamp"])
```

| key | holds |
|---|---|
| `label` | the data label (`""` if none) |
| `columns` | for each column read: `storage` (`"byte"`, `"str20"`, `"strL"`, ...), `format` (display format), `label` (variable label), `value_labels` (name of its value label set, or `""`) |
| `value_labels` | every value label set in the file: name to `{code: text}` |
| `notes` | the dataset's notes, in order |
| `characteristics` | `{"_dta" or column name: {characteristic name: text}}`, without the notes |
| `sort_order` | the columns the data is sorted by |
| `release`, `byte_order`, `encoding`, `timestamp` | about the file |

`read_meta(path)` returns the same dictionary for every column without
reading any rows, plus `nobs`, the row count:

```python
meta = dp.read_meta("survey.dta")
print(meta["nobs"], list(meta["columns"]))
```

pandas carries `attrs` through most operations, such as selecting rows
or columns, `sort_values` and `copy`. It drops or resets them in a few:
`merge`, and `concat` of frames whose `attrs` differ. A renamed column
loses its entry. When you write such a frame, columns without an entry
get their storage type from the dtype and no label; see
[Write a file](#write-a-file). To keep the metadata across a merge,
copy it back: `merged.attrs = left.attrs`.

## Missing values

Stata has 27 numeric missing values: `.` and `.a` to `.z`
(see the [guide](guide/missing-values.md)). In pandas:

- `.` is `NaN`, as everywhere in pandas.
- `.a` to `.z` are `dta_parser.missing.a` to `dta_parser.missing.z`, one
  object per letter, that compare equal only to themselves. They print as
  `.a` ... `.z`.

A column that has any of `.a` to `.z` is a `StataArray`, which stores a
missing code per row: 0 for a number, 1 for `.`, 2 to 27 for `.a` to
`.z`.

```python
import dta_parser as dp
from dta_parser import missing

df = dp.read_dta("survey.dta")
income = df["income"]
print(income[1])                          # .d
print(income[1] is missing.d)             # True
print(income.array.codes)                 # [ 0  5  0  1 19  0]
print(income.isna().tolist())             # [False, True, False, True, True, False]
print(dp.missing_codes(income))           # the same codes, for any column
refused = df[income == missing.r]         # compare with a letter: by code
print(refused["id"].tolist())             # [5]
```

Assign a letter like any value:

```python
df.loc[df["id"] == 4, "income"] = missing.s
print(df["income"].array.codes)           # [ 0  5  0 20 19  0]
```

To make a `StataArray` yourself, give pandas the dtype, or pass values
and codes:

```python
s = pd.Series([1.0, missing.a, None], dtype="stata[double]")
arr = dp.StataArray([1.0, np.nan, np.nan], codes=[0, 2, 1], storage="long")
print(arr.dtype)                          # stata[long]
```

**What keeps the codes.** Boolean and positional selection, `loc` and
`iloc`, `sort_values`, `concat` and `merge` when both columns are
`StataArray`s, `reindex` (new rows are `.`), `copy`, scalar get and set,
and `groupby` on the column, where `.`, `.a`, ... are separate groups as
in Stata. **What loses them.** Arithmetic (`income + 1` is a `float64`
column with `NaN`), `fillna`, `astype`, and anything else that goes
through numpy: the letters become `NaN`, which writes as `.`.

**Sorting.** `sort_values` on a `StataArray` puts missing values last,
in Stata's order: numbers, `.`, `.a`, ..., `.z`. To sort by several
columns, pass `key=dp.stata_keys`, which turns each numeric column into
floats that sort as Stata does and leaves other columns alone:

```python
ordered = df.sort_values(["region", "income"], key=dp.stata_keys)
print(dp.stata_key(missing.a) > dp.stata_key(np.nan) > 1e300)   # True
```

`stata_key(value)` gives the key of one value. The keys are the same in
R, Julia and TypeScript.

## Value labels

A labelled column holds codes; its value label set maps them to text.

```python
df = dp.read_dta("survey.dta")
info = df.attrs["dta"]
set_name = info["columns"]["region"]["value_labels"]   # 'region'
labels = info["value_labels"][set_name]
print(labels)                     # {1: 'North', 2: 'South', 3: 'East', 4: 'West'}
print(df["region"].map(labels).tolist())
# ['North', 'South', 'South', 'East', 'West', 'North']
```

As a pandas `Categorical`, with every label as a category in code
order, including labels no row uses:

```python
codes = sorted(labels)
region = pd.Categorical(df["region"].map(labels), categories=[labels[c] for c in codes])
print(region.categories.tolist())   # ['North', 'South', 'East', 'West']
```

Codes without a label become `NaN` in both. Labels of missing values are
keyed by the `missing` objects:

```python
nonresponse = info["value_labels"]["nonresponse"]
print(nonresponse[missing.d])                       # Don't know
print([nonresponse.get(v, v) for v in df["income"]])
# [2100.0, "Don't know", 1850.0, nan, 'Refused', 3200.0]
```

To change labels before writing, edit the dictionaries in `attrs`; see
[Write a file](#write-a-file).

## Dates

Columns with a `%td` (day) format become `datetime64[s]`, and `%tc`
(millisecond) columns `datetime64[ms]`, with `.` as `NaT`:

```python
df = dp.read_dta("survey.dta")
print(df["interviewed"].dt.day_name().tolist()[:2])   # ['Friday', 'Friday']
raw = dp.read_dta("survey.dta", dates=False)
print(raw["interviewed"].tolist()[:2])                # [23436, 23436]: days since 1960-01-01
```

A column stays numeric, with its format, if any value is not a whole
day (or millisecond), is too large for numpy's datetime, or is one of
`.a` to `.z`; converting it would lose information. `%tC` (milliseconds
with leap seconds) always stays numeric. Other date formats stay
numeric too; convert them yourself:

```python
months = pd.Series([0, 1, 779])            # %tm: months since January 1960
print(pd.PeriodIndex.from_ordinals(months - 120, freq="M").astype(str).tolist())
# ['1960-01', '1960-02', '2024-12']
days = pd.Series([0, 23436])               # %td numbers, if you read with dates=False
print((pd.Timestamp("1960-01-01") + pd.to_timedelta(days, unit="D")).tolist())
```

(Stata counts months from January 1960, pandas from January 1970, hence `- 120`.)

## Write a file

```python
dp.write_dta(df, "out.dta")
```

`write_dta(df, path, *, label=None, variable_labels=None, timestamp=None)`
writes release 118. A frame from `read_dta` writes back with its
values, missing codes, storage types, variable labels, value labels,
display formats, notes, characteristics and sort order. The index is not
written; call `df.reset_index()` first to keep it.

Columns without metadata get a storage type from their dtype:

| pandas | Stata |
|---|---|
| `bool` | byte |
| integers | the smallest of byte, int, long that holds every value; else double; an error beyond ±2^53 |
| `float32`, `float64` | float, double; `NaN` is `.` |
| nullable `Int*`, `boolean`, `Float*` | as above; `pd.NA` is `.` |
| `StataArray` | its storage type and missing codes |
| `category` | long codes 0, 1, 2, ..., with the categories as a value label set named after the column; missing is `.` |
| `datetime64` | `%td` (long) if every value is midnight, else `%tc` (double, milliseconds); `NaT` is `.` |
| text (`str`, `object` of `str`) | strN up to 2045 bytes, else strL; `None`, `NaN` and `pd.NA` become `""` |
| `bytes` values | binary strL |

Anything else raises `TypeError` naming the column. A column name Stata
cannot hold (1 to 32 letters, digits or `_`, not starting with a digit,
not a reserved word such as `in` or `long`) raises `ValueError`; there
is no silent renaming.

Labels, by argument or through `attrs`:

```python
out = pd.DataFrame({"id": [1, 2, 3], "smoker": [1, 0, 1]})
out.attrs["dta"] = {
    "columns": {"smoker": {"label": "Smokes daily", "value_labels": "yesno"}},
    "value_labels": {"yesno": {0: "No", 1: "Yes", missing.d: "Don't know"}},
}
dp.write_dta(out, "smokers.dta", label="Smoking", variable_labels={"id": "Person"})

back = dp.read_dta("smokers.dta")
print(back.attrs["dta"]["label"])                         # Smoking
print(back.attrs["dta"]["columns"]["smoker"]["label"])    # Smokes daily
print(back.attrs["dta"]["value_labels"]["yesno"])         # {0: 'No', 1: 'Yes', .d: "Don't know"}
```

`variable_labels` and `label` override `attrs`. Other keys of `attrs`
that the writer uses: each column's `format` and `storage` (used if the
values fit it), and `notes`, `characteristics` and `sort_order` (only
the leading columns that are still in the frame).

## Recipes

**Keep `.a` to `.z` through a filter, a sort and a write.**

```python
df = dp.read_dta("survey.dta")
older = df[df["age"] >= 40].sort_values("income")
dp.write_dta(older, "older.dta")
print(dp.read_dta("older.dta")["income"].array.codes)   # [ 1  5 19]
```

**Count each missing value, as Stata's `tab, missing` does.**

```python
df = dp.read_dta("survey.dta")
print(df["income"].value_counts(dropna=False, sort=False))
```

**Turn every labelled column into text**, keeping values that have no
label as they are:

```python
df = dp.read_dta("survey.dta")
info = df.attrs["dta"]
for col, meta in info["columns"].items():
    labels = info["value_labels"].get(meta["value_labels"])
    if labels:
        df[col] = [labels.get(v, v) for v in df[col]]
print(df["region"].tolist()[:3])   # ['North', 'South', 'South']
print(df["income"].tolist())       # [2100.0, "Don't know", 1850.0, nan, 'Refused', 3200.0]
```

The labelled columns become `object` columns of text and numbers, and
the frame no longer writes back as it was read.

**Read a file from an old Stata in another encoding.** Files before
release 118 do not record their encoding. The default is Windows-1252;
pass `encoding="latin1"` or `encoding="utf-8"` if text looks wrong
(see the [guide](guide/encodings.md)).

**Get the numbers of a `StataArray` for numpy.**
`df["income"].to_numpy(dtype="float64", na_value=np.nan)` gives a float
array with every missing value as `NaN`.

## Coming from pandas.read_stata

| pandas | dta_parser |
|---|---|
| `pd.read_stata(path)` | `dp.read_dta(path)` |
| `columns=[...]` | `columns=[...]` (names or positions) |
| `iterator=True`, `chunksize=n`, `StataReader.read(nrows)` | `skip=`, `n_max=` |
| `convert_dates=False` | `dates=False` |
| `convert_categoricals=True` (the default) | not done; codes stay numbers; see [Value labels](#value-labels) |
| `convert_missing=True` (an `object` column of `StataMissingValue`) | always on: a `StataArray` |
| `preserve_dtypes=False` | not available; columns keep their storage width |
| `index_col="id"` | `dp.read_dta(path).set_index("id")` |
| `StataReader.variable_labels()` | `{c: m["label"] for c, m in df.attrs["dta"]["columns"].items()}` |
| `StataReader.value_labels()` | `df.attrs["dta"]["value_labels"]` |
| `StataReader.data_label` | `df.attrs["dta"]["label"]` |
| `df.to_stata(path, write_index=False)` | `dp.write_dta(df, path)` |
| `to_stata(..., variable_labels=..., data_label=...)` | `write_dta(..., variable_labels=..., label=...)` |
| `to_stata(..., value_labels={"col": {1: "a"}})` | `attrs["dta"]["value_labels"]` and each column's `value_labels` |
| `to_stata(..., version=114)` | not available; always 118 |
| `to_stata(..., convert_strl=["col"])` | automatic for text over 2045 bytes |

What changes: integer columns are `int8`/`int16`/`int32` rather than
the wider types pandas picks when it fills missing values; labelled
columns stay numbers; old files decode as Windows-1252 rather than
Latin-1 (pass `encoding="latin1"` to match pandas).

## Coming from pyreadstat

| pyreadstat | dta_parser |
|---|---|
| `df, meta = pyreadstat.read_dta(path)` | `df = dp.read_dta(path)`; metadata in `df.attrs["dta"]` |
| `metadataonly=True` | `dp.read_meta(path)` |
| `usecols=[...]` | `columns=[...]` |
| `row_offset=`, `row_limit=` | `skip=`, `n_max=` |
| `apply_value_formats=True` | `df[c].map(labels)`; see [Value labels](#value-labels) |
| `user_missing=True` | always on: `.a` to `.z` are kept |
| `disable_datetime_conversion=True` | `dates=False` |
| `encoding=` | `encoding=` (`"windows-1252"`, `"latin1"`, `"utf-8"`) |
| `meta.column_names_to_labels` | `{c: m["label"] for c, m in df.attrs["dta"]["columns"].items()}` |
| `meta.variable_to_label` | `{c: m["value_labels"] for c, m in df.attrs["dta"]["columns"].items() if m["value_labels"]}` |
| `meta.value_labels` | `df.attrs["dta"]["value_labels"]` |
| `meta.file_label`, `meta.number_rows` | `attrs["dta"]["label"]`; `read_meta(path)["nobs"]` |
| `meta.original_variable_types` | `attrs["dta"]["columns"][c]["storage"]` |
| `pyreadstat.write_dta(df, path, file_label=..., column_labels=...)` | `dp.write_dta(df, path, label=..., variable_labels=...)` |
| `variable_value_labels={"col": {1: "a"}}` | `attrs["dta"]["value_labels"]` and each column's `value_labels` |
| `missing_user_values` | write a `StataArray` with the codes |
| `pyreadstat.read_file_in_chunks(...)` | a loop over `skip` and `n_max`; see [Read some rows](#read-some-rows) |

## Troubleshooting

**`ImportError: cannot import name '_native'`.** Python is importing the
source directory instead of the installed package; this happens when
you run Python from inside `dta-parser/python`. Change directory.

**`pip install` fails with "cargo not found" or a Rust error.** Install
Rust from [rustup.rs](https://rustup.rs) and open a new shell.

**`ValueError: unsupported .dta release`.** The file is not a `.dta`
file, or is a release older than 104 or newer than 119. See
[Releases](guide/releases.md).

**Accented letters come out wrong.** The file is older than release
118; pass `encoding="latin1"` or `encoding="utf-8"`.

**`.a` became `NaN` after an operation.** Arithmetic and numpy
functions do not know the codes. Do the arithmetic on the numbers, then
put the codes back with a mask, or keep the column out of the
computation.

**`write_dta` raises "x row 1: cannot write a int as a string".** An
`object` column is written as text, and this one holds something else
(numbers mixed with strings, Python `date` objects). Convert it first,
for example with `pd.to_numeric` or `pd.to_datetime`.

**A sort with several columns raises an error about missing
categories.** Pass `key=dp.stata_keys`.

**Labels disappeared after `merge`.** pandas dropped `attrs`; set
`merged.attrs = left.attrs`.

## API reference

The docstrings (`help(dp.read_dta)`) are the reference. Exports:

- `read_dta(path, columns=None, skip=0, n_max=None, encoding=None, dates=True)`:
  read a file into a DataFrame.
- `read_meta(path, encoding=None)`: the metadata dictionary and `nobs`,
  without data.
- `write_dta(df, path, *, label=None, variable_labels=None, timestamp=None)`:
  write release 118.
- `StataArray(values, codes=None, storage="double", copy=False)`: numbers
  with missing codes; `.codes` gives them.
- `StataDtype(storage="double")`: its dtype, `stata[byte]` ... `stata[double]`.
- `missing`: the module holding `missing.a` ... `missing.z`, and
  `missing.from_code(code)`.
- `MissingValue`: the class of `missing.a` ... `missing.z`; `.code` and
  `.name`.
- `missing_codes(column)`: the code of each value of any column.
- `stata_key(value)`, `stata_keys(column)`: floats that sort as Stata does.
