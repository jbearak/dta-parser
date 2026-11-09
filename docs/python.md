# Python: dta_parser and datakit

`dta_parser` reads Stata `.dta` files into pandas DataFrames and writes
DataFrames back as `.dta` files. It reads every release from 104 to 119
and writes release 118. Unlike `pandas.read_stata` and pyreadstat, it
keeps Stata's extended missing values `.a` to `.z` per value, through
filtering, sorting, merging and writing.

`datakit` is data preparation in polars that keeps Stata's labels and
`.a` to `.z`: it reads and saves Parquet files, `.dta` files, and
fixed-width text with a SAS setup file as a polars `DataFrame`, with
`.a` to `.z` as tagged NaNs in its columns and a `Meta` of labels beside
it ([datakit](#datakit-parquet-dta-and-fixed-width-files-in-polars)).
Parquet and fixed-width text moved there from `dta_parser` in 0.3
([migration notes](migration.md#dta_parser-02-to-03)).

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
[datakit](#datakit-parquet-dta-and-fixed-width-files-in-polars) ·
[Fixed-width files](#fixed-width-files-with-a-sas-setup-file) ·
[Parquet files](#parquet-files) ·
[.dta files into polars](#dta-files-into-polars) ·
[Threads](#threads) ·
[Troubleshooting](#troubleshooting) ·
[API reference](#api-reference)

The [guide](guide/README.md) explains the Stata concepts behind each
section.

## Install

There are two packages, and neither is on PyPI: you install them from
a checkout of this repository, and pip builds them on your machine.

- `dta_parser` reads and writes `.dta` files with pandas. It holds the
  compiled core.
- `datakit` reads and writes Parquet, `.dta` and fixed-width files with
  polars ([datakit](#datakit-parquet-dta-and-fixed-width-files-in-polars)).
  It is pure Python and needs `dta_parser`'s core, so install the two
  together.

You need Python 3.10 or later (not a free-threaded build) on macOS,
Linux or Windows, a Rust toolchain ([rustup.rs](https://rustup.rs)), and
a C compiler, which builds the zstd library: Xcode's command line tools
on macOS, `build-essential` or your distribution's gcc on Linux, and
the Visual Studio Build Tools on Windows. From the directory you want
the checkout in:

```sh
git clone https://github.com/jbearak/dta-parser
pip install ./dta-parser/python ./dta-parser/python/datakit
python -c "import dta_parser, datakit; print(dta_parser.read_dta, datakit.read_parquet)"
```

For `.dta` files with pandas only, `pip install ./dta-parser/python` is
enough. pip builds the extension with maturin (it downloads maturin
the first time) and installs numpy 1.23 or later and pandas 2.2 or
later (pandas 3 works); datakit adds polars 2. The extension works with
every Python from 3.10 on, so one build serves them all.

If the build fails:

- "cargo not found", or a Rust error: install Rust from
  [rustup.rs](https://rustup.rs), open a new shell, and run the same
  `pip install` again.
- An error from `cc`, `clang` or `link.exe` while building zstd: install
  the C compiler above.
- pip cannot reach PyPI: see [Troubleshooting](#troubleshooting).
- `import datakit` says the two packages come from different checkouts:
  run the same command with `--force-reinstall`:
  `pip install --force-reinstall ./dta-parser/python ./dta-parser/python/datakit`.

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
    "income": pd.Series([2100.0, missing.d, 1850.0, None, missing.r, 3200.0], dtype="dta[double]"),
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
income         dta[double]
interviewed    datetime64[s]
comment                  str
```

`read_dta(path)` takes a path (a `str` or `os.PathLike`) and returns a
`DataFrame` with a default `RangeIndex`. What each column becomes:

| in the file | in pandas |
|---|---|
| byte, int, long, float, double with no missing value | `int8`, `int16`, `int32`, `float32`, `float64` |
| the same with `.` as the only missing value | `float32` (byte, int, float) or `float64` (long, double), `.` as `NaN` |
| any numeric type with one or more of `.a` to `.z` | `DtaArray`, dtype `dta[byte]` ... `dta[double]` |
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

Everything the file says about itself is in `df.attrs["dta"]`, a
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

The frames and columns pandas derives from `df` share its
`attrs["dta"]`, so a change to it shows in all of them. pandas would
otherwise copy it for each one, which for a file of thousands of
variables takes milliseconds per column. To change one frame's metadata
alone, give it its own copy first:
`sub.attrs["dta"] = df.attrs["dta"].copy()`.

## Missing values

Stata has 27 numeric missing values: `.` and `.a` to `.z`
(see the [guide](guide/missing-values.md)). In pandas:

- `.` is `NaN`, as everywhere in pandas.
- `.a` to `.z` are `dta_parser.missing.a` to `dta_parser.missing.z`, one
  object per letter, that compare equal only to themselves. They print as
  `.a` ... `.z`.

A column that has any of `.a` to `.z` is a `DtaArray`, which stores a
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

To make a `DtaArray` yourself, give pandas the dtype, or pass values
and codes:

```python
s = pd.Series([1.0, missing.a, None], dtype="dta[double]")
arr = dp.DtaArray([1.0, np.nan, np.nan], codes=[0, 2, 1], storage="long")
print(arr.dtype)                          # dta[long]
```

**What keeps the codes.** Boolean and positional selection, `loc` and
`iloc`, `sort_values`, `concat` and `merge` when both columns are
`DtaArray`s, `reindex` (new rows are `.`), `copy`, scalar get and set,
and `groupby` on the column, where `.`, `.a`, ... are separate groups as
in Stata. **What loses them.** Arithmetic (`income + 1` is a `float64`
column with `NaN`), `fillna`, `astype`, and anything else that goes
through numpy: the letters become `NaN`, which writes as `.`.

**Comparisons.** `>`, `<` and `==` on a `DtaArray` follow pandas, not
Stata: a missing value compares false with everything (`income > 1000`
is false where `income` is `.a`). For Stata's rule, where missing values
are larger than every number, compare keys:
`dp.dta_keys(df["income"]) > 1000`.

**Sorting.** `sort_values` on a `DtaArray` puts missing values last,
in Stata's order: numbers, `.`, `.a`, ..., `.z`. To sort by several
columns, pass `key=dp.dta_keys`, which turns each numeric column into
floats that sort as Stata does and leaves other columns alone:

```python
ordered = df.sort_values(["region", "income"], key=dp.dta_keys)
print(dp.dta_key(missing.a) > dp.dta_key(np.nan) > 1e300)   # True
```

`dta_key(value)` gives the key of one value. The keys are the same in
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

### Columns written from categoricals

Some writers mark a column they wrote from a categorical with a
characteristic, `ordered <set>` or `unordered <set>`, `<set>` being its
value label set, and `read_dta` reads it back as a category:

- `dtaparser_factor`: `write_dta` on a `category`, and R's `save_dta` on
  a factor (plan 0020). The column is a category with its labels as
  categories in code order, unused ones included, if the file still
  holds what was written: the same set, a label on every value read, no
  two codes with the same text, and no `.a` to `.z`.
- `dtaparser_categorical`: datakit's `save_dta` on an `Enum` or
  `Categorical`, and TypeScript's `saveDta` on a categorical (plan
  0023). Such a categorical may hold `.a` to `.z`. When the rows read
  hold none, the column is a category as above; when they hold some, it
  is the numbers with their letters (a `DtaArray`), its set in `attrs`,
  without a warning. Letters, and labels on them, are allowed; a label on
  `.`, a code that is not a whole number within long's range, a text
  column, or a date format (unless `dates=False`) are not.

So a column can be a category in one window of rows (`skip`, `n_max`)
and numbers in another. A column that fails the checks, or that has both
characteristics, is read as if unmarked, with one warning per read
naming such columns (`dtaparser_factor` and `dtaparser_categorical` have
a warning each). The characteristics stay in `attrs`; `write_dta` does
not write them back, and marks each `category` it writes afresh.

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
values, missing codes, numeric storage types, variable labels, value labels,
display formats, notes, characteristics and sort order. String columns are written as narrow as their values allow ([storage types](guide/storage-types.md)). The index is not
written; call `df.reset_index()` first to keep it.

Columns without metadata get a storage type from their dtype:

| pandas | Stata |
|---|---|
| `bool` | byte |
| integers | the smallest of byte, int, long that holds every value; else double; an error beyond ±2^53 |
| `float32`, `float64` | float, double; `NaN` is `.` |
| nullable `Int*`, `boolean`, `Float*` | as above; `pd.NA` is `.` |
| `DtaArray` | its storage type and missing codes |
| `category` | long codes 0, 1, 2, ..., with the categories as a value label set named after the column (or the first free of `name_2`, `name_3`, ... when another column's labels use that name); missing is `.`. A characteristic, `dtaparser_factor`, marks it, so `read_dta` reads it back as the same category, ordered or not (plan 0020). A `dtaparser_factor` or `dtaparser_categorical` characteristic in `attrs` is not written: each describes what a writer wrote, and a column that was a category may be numbers now |
| `datetime64` | `%td` (long) if every value is midnight, else `%tc` (double, milliseconds); `NaT` is `.` |
| text (`str`, `object` of `str`) | strN up to 2045 bytes, else strL; `None`, `NaN` and `pd.NA` become `""` |
| `bytes` values | binary strL |

Anything else raises `TypeError` naming the column. A column name Stata
cannot hold (1 to 32 letters, digits or `_`, not starting with a digit)
raises `ValueError`; there is no silent renaming. A column named with a
word Stata reserves (`_all`, `_b`, `byte`, `_coef`, `_cons`, `double`,
`float`, `if`, `in`, `int`, `long`, `_n`, `_N`, `_pi`, `_pred`, `_rc`,
`_skip`, `strL`, `using`, `with`, or `str` followed by digits) is
written, with one `UserWarning`, since Stata cannot use it until it is
renamed; datakit's `save_dta` does the same.

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

**Get the numbers of a `DtaArray` for numpy.**
`df["income"].to_numpy(dtype="float64", na_value=np.nan)` gives a float
array with every missing value as `NaN`.

## Coming from pandas.read_stata

| pandas | dta_parser |
|---|---|
| `pd.read_stata(path)` | `dp.read_dta(path)` |
| `columns=[...]` | `columns=[...]` (names or positions) |
| `iterator=True`, `chunksize=n`, `StataReader.read(nrows)` | `skip=`, `n_max=` |
| `convert_dates=False` | `dates=False` |
| `convert_categoricals=True` (the default) | not done; codes stay numbers; see [Value labels](#value-labels). A column `write_dta` wrote from a category, R's `save_dta` from a factor, or datakit's `save_dta` from an `Enum`, is a category again ([Columns written from categoricals](#columns-written-from-categoricals)) |
| `convert_missing=True` (an `object` column of `StataMissingValue`) | always on: a `DtaArray` |
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
| `meta.original_variable_types` (display formats) | `attrs["dta"]["columns"][c]["format"]` |
| `meta.readstat_variable_types` | `attrs["dta"]["columns"][c]["storage"]` (Stata's own names: `byte`, `int`, `long`, `float`, `double`, `strN`, `strL`) |
| `pyreadstat.write_dta(df, path, file_label=..., column_labels=...)` | `dp.write_dta(df, path, label=..., variable_labels=...)` |
| `variable_value_labels={"col": {1: "a"}}` | `attrs["dta"]["value_labels"]` and each column's `value_labels` |
| `missing_user_values` | write a `DtaArray` with the codes |
| `pyreadstat.read_file_in_chunks(...)` | a loop over `skip` and `n_max`; see [Read some rows](#read-some-rows) |

## datakit: Parquet, .dta and fixed-width files in polars

`datakit` is the data-preparation package beside `dta_parser`. It reads
Parquet files, `.dta` files, and fixed-width text with a SAS setup file
into a polars `DataFrame`, with Stata's missing values `.a` to `.z` in
the frame as tagged NaNs, and keeps what polars cannot hold in a `Meta`
beside the frame: variable labels, value labels, display formats and
notes. It saves both back as Parquet or `.dta`. The Parquet files carry the same `dta`
profile R's and Julia's datakits write, so a file goes between the
three languages with its labels and letters.

```python
import datakit as dk

df, meta = dk.read_dta("survey.dta")      # every read returns (frame, Meta)
print(type(df).__name__, df.columns)
# DataFrame ['id', 'region', 'age', 'income', 'interviewed', 'comment']
print(df["income"].to_list())             # [2100.0, nan, 1850.0, None, nan, 3200.0]
print(dk.na_tag(df["income"]).to_list())  # [None, '.d', None, None, '.r', None]
print(meta.columns["income"].label)       # Monthly income
```

`.` is a polars null. `.a` to `.z` are NaNs tagged with their letter,
the bits R and haven hold them in, so each letter is in its row and
follows it through every polars operation. polars counts NaN as a
value, though: call `fill_nan(None)` before `is_null()`, `drop_nulls()`,
`mean()` or `count()` to treat the letters as Stata does
([.a to .z in the frame](#a-to-z-in-the-frame)). Importing `datakit`
does not import pandas.

## Fixed-width files with a SAS setup file

Some surveys are published as fixed-width text with a SAS program, the
*setup file*, that says where each variable sits. CDC publishes the
National Survey of Family Growth this way, from 1973 to 2017-2019.
`dk.read_fixed_width` reads such data through its setup file: columns
from `INPUT`, variable labels from `LABEL`, value labels from
`PROC FORMAT` and `FORMAT`, record types from
`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`, and the setup's
*missing-value recodes*, such as `IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`.

```python
with open("survey.sas", "w") as f:
    f.write("""PROC FORMAT;
  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained';
DATA;
INPUT ID 1-3 KIDS 4-5;
LABEL KIDS = 'Number of children';
IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;
FORMAT KIDS kidsf.;
""")
with open("survey.dat", "w") as f:
    f.write("001 2\n00298\n00399\n004 0\n")
```

By default the recodes apply as the setup writes them, so 98 and 99 are
`.`, a null:

```python
df, meta = dk.read_fixed_width("survey.dat", "survey.sas")
print(df["KIDS"].to_list())             # [2, None, None, 0]
print(meta.columns["KIDS"].label)       # Number of children
print(meta.labels("KIDS"))              # {0: '(0) None'}
```

`recodes="tagged"` keeps why each value is missing: per variable, the
codes recoded to `.` become `.a`, `.b`, ... in the order the setup names
them, and each code's value label moves to its letter:

```python
df, meta = dk.read_fixed_width("survey.dat", "survey.sas", recodes="tagged")
print(dk.na_tag(df["KIDS"]).to_list())  # [None, '.a', '.b', None]
print(meta.labels("KIDS"))              # {0: '(0) None', '.a': '(98) DK', '.b': '(99) Not ascertained'}
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes="none"` ignores the recodes, keeping the codes as
numbers. The letters are tagged NaNs, as in every read
([.a to .z in the frame](#a-to-z-in-the-frame)); `letters=False` reads
them as nulls.

Numeric columns take the smallest storage type that holds their values
(`Int8` for these), and records shorter than the setup's columns read
as blank (`.`). Statements the reader does not run, such as other
data-step code or a range in `VALUE`, are skipped with one
`dk.FixedWidthWarning`, whose `messages` attribute lists them all. A
`LENGTH` statement for numbers, which sets only how SAS stores them, is
skipped without one. A variable label with stray quotes inside it, such
as `X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"` in CDC's 2011-2013
to 2015-2017 setups, is read from its first quote to its last, without a
warning. `columns`, `skip` and `n_max` work as in `read_dta`, after the
whole file is read.

CDC's setups from 2002 on differ in two ways, and `read_fixed_width`
reads both. The 2002 setups come in three files (`2002FemPregInput.sas`,
`2002FemPregVarLabel.sas`, `2002FemPregValueLabel.sas`); give `setup`
a list of the paths in that order, and they are read as one setup. A
statement may not run from one file into the next, and errors and
warnings name a file by its place (`"file 2 line 8"`):

```python
with open("input.sas", "w") as f:
    f.write("DATA;\nINPUT ID 1-3 KIDS 4-5;\nRUN;\n")
with open("labels.sas", "w") as f:
    f.write("PROC FORMAT;\n  VALUE kidsf 0='(0) None' 98='(98) DK';\nRUN;\nFORMAT KIDS kidsf.;\n")
df, meta = dk.read_fixed_width("survey.dat", ["input.sas", "labels.sas"], recodes="none")
print(meta.value_labels["kidsf"])   # {0: '(0) None', 98: '(98) DK'}
```

From 2006-2010 on, CDC puts the `PROC FORMAT` step and the `FORMAT`
statement each in a block comment (`/* ... */`), so that SAS users
without CDC's format catalog can run the file as published. The value
labels are still there, so by default a comment that holds nothing but
a `PROC FORMAT` step or a `FORMAT` statement is read as code; a comment
that only mentions them stays a comment. `commented_formats=False`
reads every comment as a comment, and those files then have no value
labels:

```python
with open("commented.sas", "w") as f:
    f.write("""/*
PROC FORMAT;
  VALUE kidsf 0='(0) None' 98='(98) DK';
*/
DATA;
INPUT ID 1-3 KIDS 4-5;
/*
FORMAT KIDS kidsf.;
*/
""")
_, meta = dk.read_fixed_width("survey.dat", "commented.sas", recodes="none")
print(meta.value_labels)   # {'kidsf': {0: '(0) None', 98: '(98) DK'}}
_, meta = dk.read_fixed_width("survey.dat", "commented.sas", recodes="none", commented_formats=False)
print(meta.value_labels)   # {}
```

To work in pandas instead, read the converted data with
`dp.read_dta`: `dk.read_fixed_width` returns polars, and
`dk.save_dta(df, "nsfg.dta", meta=meta)` then `dp.read_dta("nsfg.dta")`
gives the pandas frame with `DtaArray` columns.

## Parquet files

**When to use polars directly.** For a Parquet file without a `dta`
profile, or for lazy queries, predicate pushdown, many files, cloud
paths, or nested columns, use polars' own `pl.scan_parquet`,
`pl.read_parquet` and `DataFrame.write_parquet`. datakit is for files
that carry labels and `.a` to `.z`, which polars drops, and for files a
script reads and saves for R, Julia, or Stata users.

`dk.read_parquet` and `dk.save_parquet` read and write Parquet files
that keep what a `.dta` file says: variable labels, value labels,
display formats, `.a` to `.z`, the data label, notes, and
characteristics, and also categories and time zones. The files are
plain Parquet that pyarrow, pandas, polars, DuckDB, and R's arrow read;
what Parquet has no place for goes into one JSON entry of the file's
metadata, the `dta` profile ([docs/parquet.md](parquet.md)). Only flat
tables are read and written: for lists, maps, or structs, use polars.

Contents:
[Install](#parquet-install) ·
[Read a Parquet file](#read-a-parquet-file) ·
[Read some columns](#read-some-columns-of-a-parquet-file) ·
[Read a range of rows](#read-a-range-of-rows-of-a-parquet-file) ·
[Schema and metadata](#a-parquet-files-schema-and-metadata) ·
[Labels](#labels-in-parquet-files) ·
[Dates and time zones](#dates-and-time-zones-in-parquet-files) ·
[Write a Parquet file](#write-a-parquet-file) ·
[Write labels](#write-labels-to-a-parquet-file) ·
[.a to .z in the frame](#a-to-z-in-the-frame) ·
[Keep .a to .z](#keep-a-to-z-in-a-parquet-file) ·
[Files from other tools](#parquet-files-from-other-tools) ·
[What each type becomes](#what-each-parquet-type-becomes-in-python) ·
[Labels through polars operations](#labels-through-polars-operations) ·
[.dta files into polars](#dta-files-into-polars) ·
[Coming from polars, pyarrow or pandas](#coming-from-pyarrow-pandas-or-polars)

### Parquet: install

Parquet is in datakit, which needs `dta_parser`; install both from a
checkout of this repository, in one command. You need Python 3.10 or
later, a Rust toolchain ([rustup.rs](https://rustup.rs)) and a C
compiler ([Install](#install) says which, and what to do when the build
fails):

```sh
git clone https://github.com/jbearak/dta-parser
pip install ./dta-parser/python ./dta-parser/python/datakit
python -c "import datakit as dk; print(dk.read_parquet)"
```

That installs polars 2 (datakit needs `polars>=2.0,<3`) and, through
`dta_parser`, numpy and pandas; importing datakit does not load pandas.
The codecs (snappy, zstd, gzip, lz4, brotli) are built in, so pyarrow is
not needed. Neither package is on PyPI. datakit's distribution name is
`dta-datakit` (`pip show dta-datakit`) and its import name `datakit`;
an unrelated PyPI package called `datakit` uses the same import name,
so do not install both in one environment.

If `import datakit` stops with "needs dta_parser's native functions at
ABI version 1", the two packages come from different checkouts;
reinstall both from one, with the same paths as above:
`pip install --force-reinstall ./dta-parser/python ./dta-parser/python/datakit`.

### Read a Parquet file

This writes the example file as Parquet and reads it back:

```python
import datakit as dk
import polars as pl
from polars.testing import assert_frame_equal

df, meta = dk.read_dta("survey.dta")
dk.save_parquet(df, "survey.parquet", meta=meta)
back, back_meta = dk.read_parquet("survey.parquet")
assert_frame_equal(back, df)             # no error: the same values and dtypes
print(back_meta == meta)                 # True: labels, formats, notes
print(back.schema)
# Schema({'id': Int8, 'region': Int8, 'age': Int8, 'income': Float64, 'interviewed': Date, 'comment': String})
```

`read_parquet(source, columns=None, skip=0, n_max=None, factors=False,
letters=True, timestamps="error", nested="error")` takes a path (`str` or `os.PathLike`), the file as
`bytes`, or a binary file object with `read` and `seek`, and returns a
tuple `(df, meta)`. Unpack it: `dk.read_parquet(p).filter(...)` fails,
because a tuple has no `filter`.

```python
with open("survey.parquet", "rb") as f:
    print(dk.read_parquet(f)[0].height)                     # 6
raw = open("survey.parquet", "rb").read()
print(dk.read_parquet(raw)[0]["id"].to_list())              # [1, 2, 3, 4, 5, 6]
```

Each column gets a polars dtype: Int8, Int16, Int32, Float32, and
Float64 for Stata's byte, int, long, float, and double, with nulls for
`.`; Date and Datetime for dates and timestamps; String for text; and
an Enum for a categorical. A column holding `.a` to `.z` in the rows
read is Float64 instead, so that it can hold them
([.a to .z in the frame](#a-to-z-in-the-frame)).
[What each type becomes](#what-each-parquet-type-becomes-in-python)
gives every Parquet type, including those of files other tools write,
and what is refused. No value is rounded: each is exact or an error.

### Read some columns of a Parquet file

`columns` takes names or 0-based positions (of the file's data
columns), or a mix, and returns them in the order given; only those
columns are read from the file, and `meta` describes only them:

```python
part, part_meta = dk.read_parquet("survey.parquet", columns=["income", 0])
print(part.columns, list(part_meta.columns))   # ['income', 'id'] ['income', 'id']
```

A name the file does not have raises `KeyError`, listing the file's
columns (`column "weight" is not in the file; its columns are "id",
"region", ...`); a position out of range raises `IndexError`. Naming a
column twice reads it once.

### Read a range of rows of a Parquet file

`skip` rows are skipped, then at most `n_max` are read (all when
`None`):

```python
part, part_meta = dk.read_parquet("survey.parquet", skip=2, n_max=2)
print(part["id"].to_list(), part_meta.rows)   # [3, 4] 2
```

Only the row groups that hold the rows are read, and within them only
the pages that do (through the file's offset index, or, where a file has
none, by walking the page headers), so a window of a large file is
quick. Rows past the end give fewer rows, or an empty frame with the
right columns and dtypes; it is not an error. `meta.rows` describes
the rows read, and a column is Float64 for its letters only when those
rows hold one.

### A Parquet file's schema and metadata

`dk.read_parquet_info(source)` reads the footer only and returns a
`ParquetInfo`: the row count, row groups, codecs, the writer, every
key-value entry of the footer, the `Meta` a whole-file read gives, and
a polars frame of the columns:

```python
info = dk.read_parquet_info("survey.parquet")
print(info.rows, info.compression, info.created_by)   # 6 ['snappy'] dta-parquet version 0.1.0
print(info.row_groups["rows"].to_list())               # [6]
print(info.columns.select("name", "dtype", "physical_type", "logical_type").row(1))
# ('region', 'Int8', 'INT32', 'INT(8, signed)')
print(info.meta.label, sorted(info.key_value))        # Household survey (example) ['ARROW:schema', 'dta']
```

`info.columns` has one row per Parquet column:

| column | holds |
|---|---|
| `name` | the column's name |
| `role` | `"data"`, or `"nested"` for a list, map or struct, which is not read |
| `dtype` | the polars dtype `read_parquet` gives it when the rows read hold no `.a` to `.z` (with them, `Float64`), as text (`"Int8"`, `"Datetime(time_unit='us', time_zone='UTC')"`), null for a column it does not read |
| `physical_type`, `logical_type` | Parquet's types, such as `"INT32"` and `"INT(8, signed)"`, `"DOUBLE"` and null, `"BYTE_ARRAY"` and `"STRING"` |
| `label`, `value_labels` | the variable label and the value label set's name, from the `dta` profile |
| `storage` | for a DOUBLE column written so because it holds `.a` to `.z`, the Stata storage type it reads as without them (`"byte"`, `"int"`, `"long"`, `"float"`) |

`info.row_groups` has `rows`, `compressed_bytes` and
`uncompressed_bytes` per row group. `info.key_value` is a `dict` of every
key-value entry in the footer, key to value as text: the `dta` profile,
`ARROW:schema`, pandas' metadata, anything another writer put there. For polars' own view of a file, use
`pl.read_parquet_schema(p)` and `pl.read_parquet_metadata(p)`.

### Labels in Parquet files

Labels are in `meta`. `meta.columns[name]` is a `dk.Column` with the
variable `label`, the display `format`, and `value_labels`, the name of
the column's value label set in `meta.value_labels` (several columns can
share a set). `meta.labels(name)` gives the set itself:

```python
df, meta = dk.read_parquet("survey.parquet")
print(meta.columns["age"].label)     # Age in years
print(meta.labels("region"))         # {1: 'North', 2: 'South', 3: 'East', 4: 'West'}
print(meta.labels("income"))         # {'.d': "Don't know", '.r': 'Refused'}
labels = meta.labels("region")
print(df["region"].replace_strict(labels, return_dtype=pl.String).to_list())
# ['North', 'South', 'South', 'East', 'West', 'North']
```

A code is an `int` or `float`, or a missing code as text: `"."`, `".a"`
to `".z"`. `meta.labels(name)` returns `{}` for a column without a set
and raises `KeyError` for a name `meta.columns` lacks.

`factors=True` makes each column with value labels an Enum, as R's
datakit does with `factors = TRUE`: its levels are the column's values
and the set's codes, in order of value, each labelled code as its label
and any other value as its number in text:

```python
df, meta = dk.read_parquet("survey.parquet", factors=True)
print(df["region"].dtype)            # Enum(categories=['North', 'South', 'East', 'West'])
print(df["region"].to_list())        # ['North', 'South', 'South', 'East', 'West', 'North']
print(dk.na_tag(df["income"]).to_list())  # [None, '.d', None, None, '.r', None]
```

**What `factors=True` loses:** the codes are gone from the frame, and
codes that share a label (two codes both labelled "Yes") become one
level that cannot be told apart again. Saving does not bring them back:
`save_parquet` writes the Enum as a categorical of its levels, and
`save_dta` writes it as Stata's `encode` would, codes 1 to k labelled
with the levels. To keep the file's codes, read with `factors=False`,
the default. An Enum cannot hold `.a` to `.z` either: in a column made
an Enum they become nulls, with one warning naming the columns, as R's
datakit does; `factors=False` keeps them. A categorical that a file
stores with letters stays its level numbers, as in R.

Other tools do not read labels: they see the codes. A file from another
tool has none, unless it has a `dta` entry in its metadata (written by
`save_parquet`, by R's datakit, by Julia's Datakit, or by another
library writing the same entry; see
[docs/parquet.md](parquet.md#the-profile)).

### Dates and time zones in Parquet files

A polars `Date` is written as a Parquet DATE and a `Datetime` as a
TIMESTAMP in its own unit; a `Datetime` with a zone is stored as an
instant (adjusted to UTC) with its zone kept, and one without as a
clock time:

```python
from datetime import date, datetime

visits = pl.DataFrame({
    "day": [date(2024, 3, 1), None],
    "at": [datetime(2024, 3, 1, 9, 30), datetime(2024, 3, 1, 17, 5)],
    "local": [datetime(2024, 3, 1, 9, 30, 0, 1), None],
}).with_columns(pl.col("at").dt.replace_time_zone("America/New_York"))
dk.save_parquet(visits, "visits.parquet")
v, _ = dk.read_parquet("visits.parquet")
print(v.schema)
# Schema({'day': Date, 'at': Datetime(time_unit='us', time_zone='America/New_York'), 'local': Datetime(time_unit='us', time_zone=None)})
print(v["at"][0])                    # 2024-03-01 09:30:00-05:00
```

| polars | written as | read back as |
|---|---|---|
| `Date` | DATE | `Date` |
| `Datetime(unit)` | TIMESTAMP in that unit, not adjusted to UTC (a clock time) | the same |
| `Datetime(unit, zone)` | TIMESTAMP in that unit, adjusted to UTC (an instant), the zone in the profile and `ARROW:schema` | the same, in that zone |
| `Time` | TIME(NANOS) | `Time` |

Dates and timestamps from other files: DATE is `Date`; a TIMESTAMP is
`Datetime` in the file's unit, with the zone the file's dta profile or
`ARROW:schema` gives, else UTC when it stores instants, else none; a
profile's `"unit": "s"`, which polars lacks, reads as `"ms"`. INT96 is
`Datetime("ns")`. A date or timestamp that R wrote as a DOUBLE (days or
seconds since 1970, because it holds `.a` to `.z` or a fraction) reads
as `Date` or `Datetime("us")`; a value with a fraction of a day, or
seconds that no whole number of microseconds gives back, is an error
naming the column and row, and `timestamps="truncate"` drops the
fraction. A value outside polars' Date or Datetime range is an error
either way.

A `.dta` `%tc` time reads as `Datetime("ms")`, while R's timestamps
read from Parquet are `Datetime("us")`; cast one before joining or
comparing the two.

### Write a Parquet file

`save_parquet(df, path=None, meta=None, *, compression="snappy",
compression_level=None, row_group_size=None, missing_letters=True,
timestamps="error")` writes a polars `DataFrame`. With a path it returns
`None`; without one it returns the file as `bytes`:

```python
df, meta = dk.read_parquet("survey.parquet")
dk.save_parquet(df, "small.parquet", meta=meta, compression="zstd", compression_level=3, row_group_size=2)
print(dk.read_parquet_info("small.parquet").row_groups["rows"].to_list())   # [2, 2, 2]
data = dk.save_parquet(df, meta=meta)
print(type(data).__name__, data[:4])                                         # bytes b'PAR1'
```

`compression` is `"snappy"` by default, which pyarrow, polars and DuckDB
read fastest; `"zstd"`, `"gzip"`, `"lz4_raw"` and `"none"` are the
others, and `compression_level` sets zstd's (1 to 22, default 3) or
gzip's (0 to 9, default 6). zstd makes survey files about a sixth
smaller, and slower to read. Row groups hold up to 262,144 rows and
about 1 GiB of values unless `row_group_size` gives the rows.
[docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)
gives the measurements behind these defaults. The file is written
beside the target and renamed, so a failed write leaves an existing
file as it was. A `LazyFrame` is a `TypeError`: call `.collect()` first.

What each dtype becomes:

| polars | Parquet |
|---|---|
| `Int8`, `Int16`, `Int32`, `Int64` | INT(8), INT(16), INT32, INT64 |
| `UInt8`, `UInt16`, `UInt32`, `UInt64` | INT(8, unsigned) to INT(64, unsigned), with unsigned statistics; they read back as themselves |
| `Float32`, `Float64` | FLOAT, DOUBLE; NaN is a value, null is null, and a tagged NaN is `.a` to `.z` ([Keep .a to .z](#keep-a-to-z-in-a-parquet-file)) |
| `Boolean` | BOOLEAN |
| `String`, `Binary` | BYTE_ARRAY, as STRING or without a type |
| `Date`, `Datetime`, `Time` | DATE, TIMESTAMP, TIME(NANOS) ([Dates](#dates-and-time-zones-in-parquet-files)) |
| `Enum` | a dictionary-encoded STRING whose dictionary is every level, in order; `meta.columns[name].ordered` is kept |
| `Categorical` | the same, with the levels its rows use; it reads back as an `Enum` of them |
| `Null` (an all-null column, as `pl.lit(None)` makes) | an all-null DOUBLE, as Stata's `gen x = .` makes a numeric column |

`Decimal` raises `TypeError` naming the column and saying to cast it to
`Float64` or `String` (writing DECIMAL needs an encoder no `.dta` or R
type needs). `Duration`, `List`, `Array`, `Struct`, `Object` and any
other dtype (`Int128` among them) raise `TypeError` naming the column.
An unknown `compression` raises `ValueError` listing the codecs.
Column names may be any text, unlike in `.dta` files.

### Write labels to a Parquet file

Build or change a `Meta` and pass it as `meta=`. Every field is a plain
value to set:

```python
smoking = pl.DataFrame({"smoker": [1.0, 0.0, dk.tagged_na(".d")]})
meta = dk.Meta(
    label="Smoking",
    notes=["Wave 2 only."],
    columns={"smoker": dk.Column(label="Smokes daily", format="%8.0g", value_labels="yesno")},
    value_labels={"yesno": {0: "No", 1: "Yes", ".d": "Don't know"}},
    rows=3,
)
dk.save_parquet(smoking, "smoking.parquet", meta=meta)
s, s_meta = dk.read_parquet("smoking.parquet")
print(s_meta.label, s_meta.notes)          # Smoking ['Wave 2 only.']
print(s_meta.columns["smoker"])
# Column(label='Smokes daily', format='%8.0g', value_labels='yesno', ordered=None)
print(s_meta.labels("smoker"))             # {0: 'No', 1: 'Yes', '.d': "Don't know"}
print(dk.na_tag(s["smoker"]).to_list())    # [None, None, '.d']
```

The data label, notes, characteristics, sort order, time stamp, each
column's label, format and set, and every set (used or not) are
written. Entries for columns not in the frame are dropped without a
warning, so a `meta` from a wider read can be passed after
`df.select(...)`. Value label codes keep their type: whole numbers come
back as `int`, others as `float`, and missing codes as `".d"` text.
Unlike `.dta` files, a Parquet file can label codes that are not
integers, such as `1.5`. Writing is strict: a code that is not finite or
is beyond ±2^53, or a column naming a set `meta.value_labels` lacks, is
an error. An Enum's levels are its text, so its `value_labels` name is
not written. `meta.sort` is checked against the rows
([below](#labels-through-polars-operations)).

### .a to .z in the frame

Every read keeps `.a` to `.z` in the frame. A column holding any of
them in the rows read is `Float64`, and each letter is a NaN tagged
with it: R's `NA_real_` with the letter's code in its fifth byte, as
haven's `tagged_na()` and R's dtaparser hold it. `.` stays a null. An
integer or `Float32` column holding letters is cast to `Float64`, and
`meta` keeps its type, so that saving writes it back as byte, int, long
or float when its values still fit. Three functions read and make
letters:

- `dk.na_tag(x)`: the letter of each row of `x` (a column name, an
  expression or a Series) as `dk.LETTERS`, polars' Enum of `".a"` to
  `".z"`, null where the row has none;
- `dk.is_tagged_na(x, letter=None)`: true where a row holds a letter,
  or the letter given;
- `dk.tagged_na(".d")`: the float that holds `.d`, for anywhere polars
  takes a number.

```python
df, meta = dk.read_parquet("survey.parquet")
print(df.schema["income"], df["income"].null_count(), df["income"].is_nan().sum())   # Float64 1 2
print(df.select(dk.na_tag("income"))["income"].to_list())   # [None, '.d', None, None, '.r', None]
print(df.filter(dk.is_tagged_na("income", ".d"))["id"].to_list())   # [2]
```

A letter is a value in its row, so it follows the row through `filter`,
`sort`, `join`, `concat`, `slice` and `group_by`. It also survives
arithmetic: `x * 2` keeps `.d` where `x` held it, as Stata's
`gen y = x * 2` does.

**What polars counts.** polars treats NaN as a number. `is_null()` and
`null_count()` see only `.`, `count()` counts the letters, and `mean()`
is NaN. Call `fill_nan(None)` first to make every letter a null, which
is how Stata treats them:

```python
income = df["income"]
print(income.mean(), income.fill_nan(None).mean())     # nan 2383.3333333333335
print(income.count(), income.fill_nan(None).count())   # 5 3
```

Comparisons already work as in Stata. NaN is greater than every number
in polars, and Stata's missing values are greater than every number
too, so `pl.col("income") > 3000` is true for a letter, as Stata's
`income > 3000` is. `.` is null, so a comparison is null there and
`filter` drops the row, which Stata would keep; `ne_missing` and
`eq_missing` keep it.

**Set a letter** (Stata's `replace income = .r if age > 60`):

```python
df = df.with_columns(
    pl.when(pl.col("age") > 60).then(dk.tagged_na(".r")).otherwise(pl.col("income")).alias("income"))
print(dk.na_tag(df["income"]).to_list())   # [None, '.d', None, '.r', '.r', None]
```

In an integer column polars makes the result `Float64`, and the letter
is kept. To replace a letter with a value, test for it:
`pl.when(dk.is_tagged_na("income", ".d")).then(0.0).otherwise(pl.col("income"))`.
A new column (Stata's `gen y = .a`) is `pl.lit(dk.tagged_na(".a"))`.

**Sort as Stata does** (values, then `.`, then `.a` to `.z`):

```python
df, meta = dk.read_parquet("survey.parquet")
stata = df.sort(pl.col("income").fill_nan(None), dk.na_tag("income"), nulls_last=[True, False],
                maintain_order=True)
print(stata["income"].to_list())              # [1850.0, 2100.0, 3200.0, None, nan, nan]
print(dk.na_tag(stata["income"]).to_list())   # [None, None, None, None, '.d', '.r']
```

polars' own `df.sort("income")` puts `.` first and the letters last,
with no order among the letters.

**What loses them.** Only `Float64` holds a letter: a cast to `Float32`
or an integer type loses it, and so does `fill_nan`. When two letters
meet in arithmetic (`x + y`, both holding one), the result keeps one of
the two.

**Dates, timestamps and categoricals.** A polars `Date`, `Datetime` or
`Enum` cannot hold NaN. A column of one of these types that holds `.a`
to `.z` in the rows read is read as numbers instead. A date becomes
Stata's count of days since 1960 (format `%td`), a timestamp its
milliseconds since 1960 (`%tc`), and a categorical its level numbers
from 1, labelled by its value label set, which is how R's and Julia's
datakits read a categorical with letters. `letters=False` gives the
`Date`, `Datetime` or `Enum`, with the letters as nulls. To make dates
of the numbers, use
`pl.date(1960, 1, 1) + pl.duration(days=pl.col("d").fill_nan(None))`.

### Keep .a to .z in a Parquet file

`save_parquet` and `save_dta` write the tagged NaNs of every `Float64`
column as `.a` to `.z`. A NaN without a tag is written as NaN, a value.

```python
df, meta = dk.read_parquet("survey.parquet")
dk.save_parquet(df, "kept.parquet", meta=meta)
print(dk.na_tag(dk.read_parquet("kept.parquet")[0]["income"]).to_list())   # [None, '.d', None, None, '.r', None]
```

In the file, a letter is a tagged NaN in a DOUBLE column, in the bits R
holds it in, so R reads the letters as its tagged NAs. The profile
records the storage type of a column that a read made `Float64`
(`income` was always a double), so `x` in a byte column comes back as a
byte column in R and Julia, and as `Int8` here when the rows read hold
no letters. Other tools see `NaN`. pandas counts it as missing, but
DuckDB SQL and polars count `NaN` as a value: `IS NULL` is false for it,
`count(x)` counts it and `mean(x)` is `NaN`. To treat `.a` to `.z` as
missing there, test for both:

```python
income = pl.read_parquet("survey.parquet")["income"]   # polars' own reader
print((income.is_null() | income.is_nan()).to_list())   # [False, True, False, True, True, False]
import importlib.util
if importlib.util.find_spec("duckdb"):
    import duckdb
    print(duckdb.sql("SELECT count(*) FILTER (WHERE income IS NULL OR isnan(income)) "
                     "FROM 'survey.parquet'").fetchall())   # [(3,)]
```

For files meant for such tools, `missing_letters=False` writes `.a` to
`.z` as plain nulls, and the letters are then lost:

```python
df, meta = dk.read_parquet("survey.parquet")
dk.save_parquet(df, "nulls.parquet", meta=meta, missing_letters=False)
print(pl.read_parquet("nulls.parquet")["income"].null_count())   # 3
```

Only `Float64` holds letters. To give another column letters, cast it
to `Float64` first; `pl.when(...).then(dk.tagged_na(...))` does that
for an integer column.

### Parquet files from other tools

`read_parquet` reads the files pyarrow, pandas, polars, DuckDB, R's
arrow and nanoparquet, fastparquet and others write: the encodings
dictionary, PLAIN, RLE, the DELTA encodings and BYTE_STREAM_SPLIT, data
pages v1 and v2, and the codecs none, snappy, gzip, zstd, lz4_raw and
brotli. The one encoding not read is BIT_PACKED for values, which the
format has deprecated and current writers do not use (BIT_PACKED
repetition and definition levels are read).
A column that pandas, polars or arrow wrote as a category or factor (a
dictionary of text in the file's `ARROW:schema`) reads as a
`Categorical`:

```python
pl.DataFrame({
    "size": pl.Series(["b", "a", "b"], dtype=pl.Categorical),
    "n": [1, None, 3],
}).write_parquet("from_polars.parquet")
other, other_meta = dk.read_parquet("from_polars.parquet")
print(other.schema)            # Schema({'size': Categorical, 'n': Int64})
print(other_meta.label, other_meta.columns["n"])   # None Column(label=None, format=None, value_labels=None, ordered=None)
```

A file without a `dta` profile reads with an empty `Meta`, and there are
no letters (a NaN is a value). DECIMAL columns of up to 38 digits read
as `Decimal(precision, scale)`, exactly; longer ones as `String`, every
digit kept. Unsigned integers, INT96 and TIME are read too (see the
table below), and so are the files' other types: text annotated ENUM or
JSON as `String`, UUID and fixed-length bytes as `Binary`.

What is not read, each an error that names the column and its type:
FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, and encrypted files.
Values encoded BIT_PACKED are an error too. Nested columns (lists, maps, structs) raise an error unless `columns`
leaves them out or `nested="skip"` is given; `read_parquet_info` lists
them with role `"nested"`. Datasets of many files, Hive partitions and
filters on values are not part of datakit: use `pl.scan_parquet`.

### What each Parquet type becomes in Python

| Parquet | polars |
|---|---|
| INT32: INT(8), INT(16) or none; INT64 | `Int8`, `Int16`, `Int32`, `Int64`, with nulls |
| unsigned 8 to 64 bits | `UInt8` to `UInt64` |
| a DOUBLE written so for `.a` to `.z` (profile `storage`) | `Float64` with tagged NaNs when the rows read hold letters, the storage type kept for saving; else its storage type again: `Int8` byte, `Int16` int, `Int32` long, `Float32` float |
| a DOUBLE with profile `logical` `date` | `Date`; a fraction of a day is an error unless `timestamps="truncate"`. With letters in the rows read, `Float64` days since 1960 with tagged NaNs, format `%td` |
| a DOUBLE with profile `logical` `timestamp` | `Datetime("us", zone)`; a value no whole number of microseconds gives back is an error unless `timestamps="truncate"`. With letters in the rows read, `Float64` milliseconds since 1960 with tagged NaNs, format `%tc` |
| FLOAT, DOUBLE | `Float32`, `Float64`; NaN stays a value, not a null, and a tagged NaN in a DOUBLE is `.a` to `.z` |
| DECIMAL, precision up to 38 | `Decimal(precision, scale)`, exact (`save_parquet` does not write it: cast first) |
| DECIMAL, precision above 38 | `String`, every digit kept |
| DATE | `Date` |
| TIMESTAMP | `Datetime` in the file's unit (`"ms"` for the profile's `"unit": "s"`), with the profile's zone, else `ARROW:schema`'s, else `"UTC"` for instants |
| INT96 | `Datetime("ns")` |
| TIME | `Time` |
| STRING, ENUM, JSON | `String` |
| BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text type, UUID | `Binary` |
| a categorical the profile lists | `Enum` of every level, in order, unused ones too |
| a DOUBLE with profile `logical` `categorical` (a categorical holding `.a` to `.z`) | the same `Enum` when the rows read hold no letters, with `factors` true or false. With letters, its level numbers (1 to k) as `Float64` with tagged NaNs, as R and Julia read it, `meta.columns[name].value_labels` naming the set that labels them. A value that is not a level number reads as null, with one warning per read naming the column and the first such row |
| a dictionary of text in `ARROW:schema`, with no profile entry | `Categorical` |
| BOOLEAN | `Boolean` |
| FLOAT16, INTERVAL | not read: an error naming the column and type |
| nested (LIST, MAP, groups) | an error naming them, or left out with `nested="skip"` |

Every value is exact or an error; unlike R, Julia and TypeScript, which
read DECIMAL as the nearest double by default, polars' `Decimal` holds
it exactly. polars' Enum always compares and
sorts by level order, so an unordered factor from R reads as an Enum
that still sorts by level; `meta.columns[name].ordered` keeps the
file's `ordered` and writes it back, to Parquet and to `.dta`.

**What a round trip does not keep.** A frame and `Meta` that a read
gave come back from `save_parquet` and `read_parquet` equal, except: a
`Categorical` comes back as an `Enum` of the levels it used; an all-null
`Null` column comes back as `Float64`; an Enum that `factors=True` made
comes back without its `value_labels` name; a date, timestamp or
categorical that held `.a` to `.z` comes back as the numbers it was read
as; and `Decimal` is not written. `.dta`'s release and encoding are not kept.

### Labels through polars operations

`.a` to `.z` are in the frame, so they follow every row operation.
`Meta` does not follow polars operations. Labels describe columns, not
rows, so a filter or a sort leaves them right, but a join, a rename, a
new column or an aggregation is yours to mirror.

**Joins.** polars renames a right-hand column whose name is taken
(`income_right`); copy the right frame's labels into `meta` yourself:

```python
df, meta = dk.read_parquet("survey.parquet")
right, right_meta = dk.read_parquet("survey.parquet", columns=["id", "income"])
joined = df.join(right, on="id", maintain_order="left")
meta.columns["income_right"] = right_meta.columns["income"]
dk.save_parquet(joined, "joined.parquet", meta=meta)
print(dk.na_tag(dk.read_parquet("joined.parquet")[0]["income_right"]).to_list())
# [None, '.d', None, None, '.r', None]
```

**Aggregation** (`group_by().agg()`): a mean or a count of `x` is a new
value, so use `fill_nan(None)` first
([What polars counts](#a-to-z-in-the-frame)), and make `meta` for the
new frame with `meta.select([...])`.

**`Meta`'s methods.** `meta.rename(mapping)` and `meta.select(names)`
return a new `Meta` for `df.rename(mapping)` and `df.select(names)`;
`meta.copy()` is a deep copy; `meta == other` compares every field.
`select` keeps `meta.sort` up to its first column not selected.
`meta.sort` is checked when saving: if the rows are no longer in that
order as Stata orders them (values, then `.`, then `.a` to `.z`),
`save_parquet` and `save_dta` leave it out with one warning. polars'
`df.sort("x")` puts nulls first, so it fails the check; the
[Stata sort](#a-to-z-in-the-frame) passes.

```python
by_region = df.sort("region", maintain_order=True)
region_meta = meta.select(["id", "region"])
region_meta.sort = ["region"]
dk.save_parquet(by_region.select("id", "region"), "regions.parquet", meta=region_meta)
print(dk.read_parquet("regions.parquet")[1].sort)   # ['region']
```

### .dta files into polars

`dk.read_dta(path, columns=None, skip=0, n_max=None, factors=False,
letters=True, encoding=None, timestamps="error")` and `dk.save_dta(df, path, meta=None, *,
missing_letters=True, timestamps="error")` read and write `.dta` files
with the same `(df, meta)`, without pandas:

```python
df, meta = dk.read_dta("survey.dta")
print(df.schema["interviewed"], meta.timestamp is not None)   # Date True
dk.save_dta(df, "again.dta", meta=meta)
back = dp.read_dta("again.dta")                                  # dta_parser's pandas reader
print(back["income"].tolist())   # [2100.0, .d, 1850.0, nan, .r, 3200.0]
```

`read_dta` reads releases 104 to 119, as `dta_parser` does. byte, int,
long, float and double are `Int8`, `Int16`, `Int32`, `Float32` and
`Float64`, and a column holding `.a` to `.z` in the rows read is
`Float64` with them as tagged NaNs
([.a to .z in the frame](#a-to-z-in-the-frame)); strN and text strLs
`String`, binary strLs `Binary` (a strL
column mixing text and binary values is `Binary`, its text as UTF-8
bytes). `%td` is `Date`, and a value with a fraction of a day is an
error naming the column and row unless `timestamps="truncate"`. `%tc`
is `Datetime("ms")`, and a value with a fraction of a millisecond is an
error unless `timestamps="truncate"`. A value outside polars' range is
an error either way. `%tC` and the other `%t` formats stay numbers, with
their format in `meta`. `encoding` decodes text in files before release
118, as in `dp.read_dta`.

`save_dta` writes release 118 with the storage types `dp.write_dta`
chooses: the smallest of byte, int and long that holds an integer
column's values (double past long, an error past ±2^53), `Float32` as
float, `Float64` as double, `Boolean` as byte, `String` as strN or
strL. `Date` is `%td`; `Datetime` is `%tc`, which holds milliseconds,
so a finer value is an error unless `timestamps="truncate"`, and a time
zone is an error. An `Enum` or `Categorical` is written as Stata's
`encode` makes one: codes 1 to k, stored as long, labelled with its
levels. `Time`, `Duration`, `Decimal` and nested
dtypes are errors naming the column, as is a name Stata cannot hold.
`.a` to `.z` are the tagged NaNs of `Float64` columns, as in
`save_parquet`. A column that a read made `Float64` for its letters is
written in its file's storage type again when its values still fit it,
and as double when they do not.

**Categoricals.** `save_dta` writes each `Enum` and `Categorical` with
a value label set named after the column (replacing `meta`'s set of
that name, or `name_2`, `name_3`, ... when another column's labels use
that name), and marks it with a characteristic, `dtaparser_categorical`
= `ordered <set>` or `unordered <set>` (from
`meta.columns[name].ordered`). The set labels the levels at codes 1 to
k, and keeps the labels on `.a` to `.z` of the set that
`meta.columns[name].value_labels` names, so "Refused" on `.r` survives
whatever that set is called. A `dtaparser_factor` or `dtaparser_categorical` in
`meta.characteristics` is not written, for any column: it describes
what was written before, and the column may be integers now.

`read_dta` gives a marked column back as an `Enum` of its set's texts in
code order, unused ones included, whatever `factors` says, with
`meta.columns[name].ordered` from the mark and
`meta.columns[name].value_labels` naming its set, which
`meta.value_labels` keeps, and the mark leaves `meta.characteristics`:

```python
grades = pl.DataFrame({"grade": pl.Series(["low", None, "high"], dtype=pl.Enum(["low", "mid", "high"]))})
gmeta = dk.Meta(columns={"grade": dk.Column(value_labels="gl", ordered=True)},
                value_labels={"gl": {".r": "Refused"}}, rows=3)
dk.save_dta(grades, "grades.dta", meta=gmeta)
g, gm = dk.read_dta("grades.dta")
print(g["grade"].dtype, g["grade"].to_list())   # Enum(categories=['low', 'mid', 'high']) ['low', None, 'high']
print(gm.columns["grade"].ordered, gm.labels("grade"))
# True {1: 'low', 2: 'mid', 3: 'high', '.r': 'Refused'}
```

An Enum cannot hold `.a` to `.z`. A marked column that holds them in
the rows read, as TypeScript's `saveDta` writes one, reads as its codes:
`Float64` with tagged NaNs, labelled by its set, its mark kept in
`meta.characteristics`. `letters=False` gives the Enum, with the
letters as nulls.

Through `.dta`, then, a categorical keeps its levels, their order,
unused levels and letter labels, but its codes become 1 to k:
a file whose set has codes 10, 20, 30 is written back with 1, 2, 3 and
the same texts. A `Categorical` comes back as an `Enum`. The mark is
checked as `dta_parser` checks it ([Columns written from
categoricals](#columns-written-from-categoricals)), except that
`read_dta` always converts dates: a marked `%td` or `%d` column, read as
a `Date`, fails. A column that fails, or has both marks, is read as if unmarked
(an `Enum` with `factors=True`, as any labelled column), with one
`UserWarning` per read naming such columns. `dtaparser_factor` alone,
which R's `save_dta` writes, is not read as a mark: such a column reads
as labelled numbers, as before.

### Coming from pyarrow, pandas or polars

| polars | pyarrow | pandas | datakit | what changes |
|---|---|---|---|---|
| `pl.read_parquet(p)` | `pq.read_table(p)` | `pd.read_parquet(p)` | `df, meta = dk.read_parquet(p)` | a polars frame and a `Meta`; labels, `.a` to `.z`, formats and notes kept |
| `pl.read_parquet(p, columns=["a", 1])` | `pq.read_table(p, columns=["a", "b"])` | `pd.read_parquet(p, columns=[...])` | `dk.read_parquet(p, columns=["a", 1])` | names or positions; an unknown name is a `KeyError` listing the file's columns |
| `pl.scan_parquet(p).slice(100, 50).collect()` | `pq.ParquetFile(p).read_row_groups([...])` | none; `.iloc[100:150]` after reading | `dk.read_parquet(p, skip=100, n_max=50)` | only the pages that hold the rows are read |
| `pl.scan_parquet(p).filter(...)` | `pq.read_table(p, filters=...)` | `filters=` | none: read, then `df.filter(...)` | no predicate pushdown; use polars for that |
| `pl.read_parquet_schema(p)`, `pl.read_parquet_metadata(p)` | `pq.read_metadata(p)`, `pq.read_schema(p)` | none | `dk.read_parquet_info(p)` | rows, row groups, codecs, key-value entries, labels, and the polars dtype each column gets |
| `df.write_parquet(p)` (zstd) | `pq.write_table(df.to_arrow(), p)` (snappy) | `df.to_parquet(p)` (snappy) | `dk.save_parquet(df, p, meta=meta)` (snappy) | labels and letters written in the `dta` profile, which R's and Julia's datakits read |
| `df.write_parquet(io.BytesIO())` | `pq.write_table(t, buf)` | `df.to_parquet(None)` | `dk.save_parquet(df)` | returns `bytes` |
| `compression="zstd", compression_level=3` | the same | the same | the same | |
| `row_group_size=n` | the same | the same | the same | |
| `write_parquet(metadata={...})` | `schema.with_metadata(...)` | `df.attrs` | `meta` | value label codes stay numbers and `.a` ... `.z` |
| `POLARS_MAX_THREADS=1` | `use_threads=False` | | `DTA_THREADS=1` | |
| `.to_pandas()` | `.to_pandas()` | | `df.to_pandas()` (pyarrow needed) | `.a` to `.z` become NaN, which pandas counts as missing, without their letters; for `DtaArray` columns save as `.dta` and use `dp.read_dta` |

What changes in the values: an integer column with nulls stays an
integer column (pandas would make it float), unless it holds `.a` to
`.z`; those are tagged NaNs in `Float64` columns, as R holds them
(polars' own reader, pyarrow and DuckDB see NaN); a categorical keeps every level and its order; and a profile's
`Date`, `Datetime` and storage types come back as the writer gave them.

## Threads

Reading and writing large files uses up to three threads: workers decode the rows and fill numeric columns, released from the GIL, while the calling thread makes the strings. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work.

datakit's reads and writes, of Parquet and of `.dta`, decode or encode on worker threads with the GIL released, straight into or out of polars' memory. Parquet reads of 256 KiB or more use one thread per 32 MiB of values, at least four and at most twelve; writes one per 8 MiB, at least four and at most sixteen. These counts were chosen against polars, which uses every core, for wall time with CPU time in proportion. The rule and the numbers are in [docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them).

Set the `DTA_THREADS` environment variable to `1` to use one thread, or to another number to change the most; it is read at each call. While `write_dta` runs, nothing may change the DataFrame's arrays, from Python or from another thread.

## Troubleshooting

**`ImportError: cannot import name '_native'`.** Python is importing the
source directory instead of the installed package; this happens when
you run Python from inside `dta-parser/python`. Change directory.

**`pip install` fails with "cargo not found" or a Rust error.** Install
Rust from [rustup.rs](https://rustup.rs) and open a new shell.

**`pip install` fails compiling zstd (an error from `cc`, `clang` or
`link.exe`).** Install a C compiler: Xcode's command line tools on
macOS (`xcode-select --install`), `build-essential` on Debian and
Ubuntu, the Visual Studio Build Tools on Windows.

**`pip install` cannot reach PyPI.** pip downloads maturin to build the
extension. Without network access, install maturin some other way and
build without isolation:
`pip install --no-build-isolation ./dta-parser/python ./dta-parser/python/datakit`
(setuptools 77 or later, numpy, pandas and polars must then be
installed already). cargo also fetches Rust crates from crates.io, so
they must be in its cache from an earlier build.

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
categories.** Pass `key=dp.dta_keys`.

**Labels disappeared after `merge`.** pandas dropped `attrs`; set
`merged.attrs = left.attrs`.

**`AttributeError: dta_parser.read_parquet moved to datakit.read_parquet`.**
Parquet and fixed-width text are datakit's from dta_parser 0.3. Install
it (`pip install ./dta-parser/python ./dta-parser/python/datakit`) and see
[the migration notes](migration.md#dta_parser-02-to-03).

**`ImportError: datakit 0.3.0 needs dta_parser's native functions at
ABI version 1`.** datakit and dta_parser come from different
checkouts. Reinstall both from one:
`pip install --force-reinstall ./dta-parser/python ./dta-parser/python/datakit`.

**`AttributeError: 'tuple' object has no attribute 'filter'`.** Every
datakit read returns `(df, meta)`; unpack it first.

**`read_parquet` raises "the file has nested columns, which are not
read".** The file has a list, map or struct column. Pass `columns=` with
the flat columns, or `nested="skip"`; for the nested data, use polars.

**`mean()` is NaN, or `count()` and `is_null()` miss values that are
missing.** The column holds `.a` to `.z`, which polars counts as NaN
values. Call `fill_nan(None)` first
([.a to .z in the frame](#a-to-z-in-the-frame)).

**A column read as `Float64` that is an integer, a date or a
categorical in the file.** It holds `.a` to `.z` in the rows read, and
only `Float64` can hold them. Pass `letters=False` to read the letters
as nulls and keep the type.

**A warning "meta.sort (x) does not describe the order of the frame's
rows".** The rows were reordered, or sorted with polars' nulls first.
Sort as the [recipe](#a-to-z-in-the-frame) does, or clear `meta.sort`.

**A warning "dropped ... from the dta profile".** The file's `dta`
entry was damaged or edited by hand. The values are read; that entry
is not. [docs/parquet.md](parquet.md#errors-and-warnings) lists every
error and warning.

## API reference

The docstrings (`help(dp.read_dta)`, `help(dk.read_parquet)`) are the
reference. `dta_parser` exports:

- `read_dta(path, columns=None, skip=0, n_max=None, encoding=None, dates=True)`:
  read a file into a DataFrame.
- `read_meta(source, encoding=None)`: the metadata dictionary and `nobs`,
  without data, of a `.dta` file.
- `write_dta(df, path, *, label=None, variable_labels=None, timestamp=None)`:
  write release 118.
- `DtaArray(values, codes=None, storage="double", copy=False)`: numbers
  with missing codes; `.codes` gives them.
- `DtaDtype(storage="double")`: its dtype, `dta[byte]` ... `dta[double]`.
- `missing`: the module holding `missing.a` ... `missing.z`, and
  `missing.from_code(code)`.
- `MissingValue`: the class of `missing.a` ... `missing.z`; `.code` and
  `.name`.
- `missing_codes(column)`: the code of each value of any column.
- `dta_key(value)`, `dta_keys(column)`: floats that sort as Stata does.

`datakit` exports:

- `read_parquet(source, columns=None, skip=0, n_max=None, factors=False, letters=True, timestamps="error", nested="error")`:
  read a Parquet file into `(df, meta)` ([Parquet files](#parquet-files)).
- `read_parquet_info(source)`: a `ParquetInfo` from the footer alone
  ([Schema and metadata](#a-parquet-files-schema-and-metadata)).
- `save_parquet(df, path=None, meta=None, *, compression="snappy", compression_level=None, row_group_size=None, missing_letters=True, timestamps="error")`:
  write a polars frame as Parquet; returns `bytes` without a path.
- `read_dta(path, columns=None, skip=0, n_max=None, factors=False, letters=True, encoding=None, timestamps="error")`
  and `save_dta(df, path, meta=None, *, missing_letters=True, timestamps="error")`:
  `.dta` files and polars ([.dta files into polars](#dta-files-into-polars)).
- `read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None, commented_formats=True, letters=True)`:
  fixed-width text through its SAS setup file, given as one path or a
  list of paths ([Fixed-width files](#fixed-width-files-with-a-sas-setup-file)).
- `tagged_na(letter)`, `na_tag(x)`, `is_tagged_na(x, letter=None)`:
  make `.a` to `.z` as tagged NaNs, and read them from a column name,
  expression or Series ([.a to .z in the frame](#a-to-z-in-the-frame)).
- `Meta`, `Column`: the labels, formats and notes beside a frame
  ([Labels](#labels-in-parquet-files)); `Meta` has `labels`, `rename`,
  `select` and `copy`.
- `ParquetInfo`: what `read_parquet_info` returns.
- `LETTERS`: the polars Enum of `".a"` to `".z"`, the dtype of what
  `na_tag` returns.
- `FixedWidthWarning`: the warning `read_fixed_width` gives for
  statements it skipped; `messages` lists them.
