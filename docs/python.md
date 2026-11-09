# Python: dta_parser and datakit

`dta_parser` reads Stata `.dta` files into pandas DataFrames and writes
DataFrames back as `.dta` files. It reads every release from 104 to 119
and writes release 118. Unlike `pandas.read_stata` and pyreadstat, it
keeps Stata's extended missing values `.a` to `.z` per value, through
filtering, sorting, merging and writing.

`datakit` is data preparation in pandas that keeps Stata's labels and
`.a` to `.z`: it reads and saves Parquet files, `.dta` files, and
fixed-width text with a SAS setup file as a pandas `DataFrame`, with
`.a` to `.z` in `DtaArray` columns and a `Meta` of labels beside it
([datakit](#datakit-parquet-dta-and-fixed-width-files-in-pandas)).
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
[datakit](#datakit-parquet-dta-and-fixed-width-files-in-pandas) ·
[Fixed-width files](#fixed-width-files-with-a-sas-setup-file) ·
[Parquet files](#parquet-files) ·
[.dta files into pandas](#dta-files-into-pandas) ·
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
  pandas, and keeps labels beside the frame
  ([datakit](#datakit-parquet-dta-and-fixed-width-files-in-pandas)).
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
later (pandas 3 works); datakit needs nothing more. The extension works with
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
| byte, int, long, float, double with no missing value in the rows read | `int8`, `int16`, `int32`, `float32`, `float64` |
| the same with any missing value (`.` or `.a` to `.z`) | `DtaArray`, dtype `dta[byte]` ... `dta[double]` |
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

A column that has any missing value in the rows read is a `DtaArray`,
which stores a missing code per row: 0 for a number, 1 for `.`, 2 to 27
for `.a` to `.z`. It takes 9 bytes a row (a float64 and a code), so a
`byte` column with a missing value takes more memory than its storage
type suggests. A column with none keeps its numpy type, so the dtype of
a column can depend on the rows read; `pd.concat` of two such reads
gives a `DtaArray` again.

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

**Comparisons give `<NA>` for a missing value**, as R's do:
`income > 1000`, `income != 1000` and `income == np.nan` are `<NA>`
where `income` is `.`, `.d` or `.r`, in a pandas `boolean` column.
`df[mask]`, `df.loc[mask]` and `query` drop those rows, as dplyr's
`filter()` does. To test for one letter, compare with it:
`income == missing.r` is true on the `.r` rows and false elsewhere, and
`missing.r == income` is the same. Two `DtaArray` columns compare `<NA>`
where either is missing, even where both hold `.r`. Text is never equal
to a number (`==` false, `!=` true) and cannot be ordered against one.

```python
print((income != 1850).tolist())   # [True, <NA>, False, <NA>, <NA>, True]
print(df[income != 1850]["id"].tolist())   # [1, 6]
```

`np.where(mask, ...)` and `if mask[i]:` refuse `<NA>`; fill it first,
`mask.fillna(False)`. pandas' `where` and `mask` treat a `<NA>`
condition as "replace", so `income.mask(income > 3000, 0)` replaces the
missing rows too; write `income.mask((income > 3000).fillna(False), 0)`
or assign with `loc`, which leaves them alone:
`df.loc[income > 3000, "income"] = 0`.

For Stata's rule, where missing values are larger than every number,
compare keys: `dp.dta_keys(df["income"]) > 1000`.

**What keeps the codes.** Boolean and positional selection, `loc` and
`iloc`, `sort_values`, `concat` (with numpy and nullable columns too,
except int64 and uint64, which give `object` rather than round values
above 2^53), `merge` when both keys are `DtaArray`s (give a key of
another type the same dtype first, `astype("dta[double]")`),
`reindex` (new rows are `.`), `copy`, scalar get and set, `groupby` on
the column, where `.`, `.a`, ... are separate groups as in Stata,
`clip`, `round`, `cumsum`, `cumprod`, `cummin` and `cummax` (which skip
missing rows; with `skipna=False` every row from the first missing one
on has its code), and arithmetic: `income * 2` keeps `.d` and `.r`
(where both sides are missing, the left side's code), and a NaN the
arithmetic makes, such as `0 / 0`, is `.`. numpy functions with an
operator (`np.add`, `np.abs`) keep the codes too. `fillna(v)` fills
every missing row, letters included. **What loses them.** `astype(float)`,
`to_numpy()`, numpy functions without an operator (`np.log`, `np.sqrt`),
`rolling`, `expanding` and `ewm`: the result is `float64` with `NaN` for
every missing value. `map` and `apply` see `missing.a` for a letter and
`NaN` for `.`. `DataFrame.to_numpy()` of a frame with a `DtaArray`
column is `object`, as pandas makes it for any extension type; write
`df.to_numpy(dtype=float)`.

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

## datakit: Parquet, .dta and fixed-width files in pandas

`datakit` is the data-preparation package beside `dta_parser`. It reads
Parquet files, `.dta` files, and fixed-width text with a SAS setup file
into a pandas `DataFrame`, and keeps what a pandas frame does not hold
in a `Meta` beside it: variable labels, value labels, display formats
and notes. It saves both back as Parquet or `.dta`. The Parquet files
carry the same `dta` profile R's and Julia's datakits write, so a file
goes between the three languages with its labels and letters.

```python
import datakit as dk

df, meta = dk.read_dta("survey.dta")      # every read returns (frame, Meta)
print(type(df).__name__, list(df.columns))
# DataFrame ['id', 'region', 'age', 'income', 'interviewed', 'comment']
print(df["income"].tolist())              # [2100.0, .d, 1850.0, nan, .r, 3200.0]
print(dk.na_tag(df["income"]).tolist())   # [nan, '.d', nan, nan, '.r', nan]
print(meta.columns["income"].label)       # Monthly income
```

Its columns are the ones `dp.read_dta` gives: each numeric column with a
missing value in the rows read is a `DtaArray`, which keeps `.` and `.a`
to `.z` and compares as missing, as R's `NA` does
([Missing values](#missing-values)). `df["income"] != 2100` is `<NA>` on
the missing rows, so a filter drops them, and `groupby` keeps `.`, `.a`
and `.b` apart ([.a to .z in the frame](#a-to-z-in-the-frame)).

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
`.`:

```python
df, meta = dk.read_fixed_width("survey.dat", "survey.sas")
print(df["KIDS"].tolist())              # [2.0, nan, nan, 0.0]
print(meta.columns["KIDS"].label)       # Number of children
print(meta.labels("KIDS"))              # {0: '(0) None'}
```

`recodes="tagged"` keeps why each value is missing: per variable, the
codes recoded to `.` become `.a`, `.b`, ... in the order the setup names
them, and each code's value label moves to its letter:

```python
df, meta = dk.read_fixed_width("survey.dat", "survey.sas", recodes="tagged")
print(dk.na_tag(df["KIDS"]).tolist())   # [nan, '.a', '.b', nan]
print(meta.labels("KIDS"))              # {0: '(0) None', '.a': '(98) DK', '.b': '(99) Not ascertained'}
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes="none"` ignores the recodes, keeping the codes as
numbers. The letters are in the column's `DtaArray`, as in every read
([.a to .z in the frame](#a-to-z-in-the-frame)); `letters=False` reads
them as `.`.

Numeric columns take the smallest storage type that holds their values
(`byte` for these: `int8`, or `dta[byte]` with a missing value), and
records shorter than the setup's columns read as blank (`.`). Statements
the reader does not run, such as other data-step code or a range in
`VALUE`, are skipped with one `dk.FixedWidthWarning`, whose `messages`
attribute lists them all. A `LENGTH` statement for numbers, which sets
only how SAS stores them, is skipped without one. A variable label with
stray quotes inside it, such as
`X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"` in CDC's 2011-2013 to
2015-2017 setups, is read from its first quote to its last, without a
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

## Parquet files

**When to use another reader.** For a Parquet file without a `dta`
profile, or for lazy queries, predicate pushdown, many files, cloud
paths, or nested columns, use `pd.read_parquet` with pyarrow, polars or
DuckDB. datakit is for files that carry labels and `.a` to `.z`, which
those drop, and for files a script reads and saves for R, Julia, or
Stata users.

`dk.read_parquet` and `dk.save_parquet` read and write Parquet files
that keep what a `.dta` file says: variable labels, value labels,
display formats, `.a` to `.z`, the data label, notes, and
characteristics, and also categories and time zones. The files are
plain Parquet that pyarrow, pandas, polars, DuckDB, and R's arrow read;
what Parquet has no place for goes into one JSON entry of the file's
metadata, the `dta` profile ([docs/parquet.md](parquet.md)). Only flat
tables are read and written: for lists, maps, or structs, use pyarrow
or polars.

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
[Labels through pandas operations](#labels-through-pandas-operations) ·
[.dta files into pandas](#dta-files-into-pandas) ·
[Memory and copies](#memory-and-copies) ·
[Coming from pyarrow, pandas or polars](#coming-from-pyarrow-pandas-or-polars)

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

That installs pandas (2.2 or later; pandas 3 works) and numpy. The
codecs (snappy, zstd, gzip, lz4, brotli) are built in, so neither
pyarrow nor polars is needed. Neither package is on PyPI. datakit's
distribution name is `dta-datakit` (`pip show dta-datakit`) and its
import name `datakit`; an unrelated PyPI package called `datakit` uses
the same import name, so do not install both in one environment.

If `import datakit` stops with "needs dta_parser's native functions at
ABI version 2", the two packages come from different checkouts;
reinstall both from one, with the same paths as above:
`pip install --force-reinstall ./dta-parser/python ./dta-parser/python/datakit`.

### Read a Parquet file

This writes the example file as Parquet and reads it back:

```python
import datakit as dk
import pandas as pd

df, meta = dk.read_dta("survey.dta")
dk.save_parquet(df, "survey.parquet", meta=meta)
back, back_meta = dk.read_parquet("survey.parquet")
pd.testing.assert_frame_equal(back, df)  # no error: the same values and dtypes
print(back_meta == meta)                 # True: labels, formats, notes
print(back.dtypes.astype(str).tolist())
# ['int8', 'int8', 'int8', 'dta[double]', 'datetime64[s]', 'str']
```

`read_parquet(source, columns=None, skip=0, n_max=None, factors=False,
letters=True, timestamps="error", nested="error")` takes a path (`str` or `os.PathLike`), the file as
`bytes`, or a binary file object with `read` and `seek`, and returns a
tuple `(df, meta)`. Unpack it: `dk.read_parquet(p).query(...)` fails,
because a tuple has no `query`.

```python
with open("survey.parquet", "rb") as f:
    print(len(dk.read_parquet(f)[0]))                       # 6
raw = open("survey.parquet", "rb").read()
print(dk.read_parquet(raw)[0]["id"].tolist())               # [1, 2, 3, 4, 5, 6]
```

Each column gets a pandas dtype. Stata's byte, int, long, float and
double are `int8`, `int16`, `int32`, `float32` and `float64` when the
rows read hold no missing value, and otherwise a `DtaArray` of that
storage type, `dta[byte]` ... `dta[double]`, as `dp.read_dta` gives
them; dates and timestamps are `datetime64`; text is pandas' text dtype
(`str` from pandas 3, `object` before); a categorical is a `category`.
[What each type becomes](#what-each-parquet-type-becomes-in-python)
gives every Parquet type, including those of files other tools write,
and what is refused. No value is rounded: each is exact or an error.

### Read some columns of a Parquet file

`columns` takes names or 0-based positions (of the file's data
columns), or a mix, and returns them in the order given; only those
columns are read from the file, and `meta` describes only them:

```python
part, part_meta = dk.read_parquet("survey.parquet", columns=["income", 0])
print(list(part.columns), list(part_meta.columns))   # ['income', 'id'] ['income', 'id']
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
print(part["id"].tolist(), part_meta.rows)   # [3, 4] 2
```

Only the row groups that hold the rows are read, and within them only
the pages that do (through the file's offset index, or, where a file has
none, by walking the page headers), so a window of a large file is
quick. Rows past the end give fewer rows, or an empty frame with the
right columns; it is not an error. `meta.rows` describes the rows read.
A numeric column is a `DtaArray` only when the rows read hold a missing
value, so two windows of one column can differ in dtype; they filter
and group alike, and `pd.concat` of them gives a `DtaArray`
([Missing values](#missing-values)).

### A Parquet file's schema and metadata

`dk.read_parquet_info(source)` reads the footer only and returns a
`ParquetInfo`: the row count, row groups, codecs, the writer, every
key-value entry of the footer, the `Meta` a whole-file read gives, and
a pandas frame of the columns:

```python
info = dk.read_parquet_info("survey.parquet")
print(info.rows, info.compression, info.created_by)   # 6 ['snappy'] dta-parquet version 0.1.0
print(info.row_groups["rows"].tolist())                # [6]
print(info.columns.loc[3, ["name", "dtype", "physical_type", "storage"]].tolist())
# ['income', 'dta[double]', 'DOUBLE', nan]
print(info.meta.label, sorted(info.key_value))        # Household survey (example) ['ARROW:schema', 'dta']
```

`info.columns` has one row per Parquet column:

| column | holds |
|---|---|
| `name` | the column's name |
| `role` | `"data"`, or `"nested"` for a list, map or struct, which is not read |
| `dtype` | the pandas dtype `read_parquet` gives it when the rows read hold no `.a` to `.z`, as text (`"int8"`, `"dta[byte]"`, `"datetime64[us, UTC]"`, `"category"`); missing for a column it does not read. A numeric column the footer says may hold a null is `dta[...]`; a NaN or a letter in the rows read makes any numeric column one too, which the footer cannot tell |
| `physical_type`, `logical_type` | Parquet's types, such as `"INT32"` and `"INT(8, signed)"`, `"DOUBLE"` and none, `"BYTE_ARRAY"` and `"STRING"` |
| `label`, `value_labels` | the variable label and the value label set's name, from the `dta` profile |
| `storage` | for a DOUBLE column written so because it holds `.a` to `.z`, the Stata storage type it has (`"byte"`, `"int"`, `"long"`, `"float"`) |

`info.row_groups` has `rows`, `compressed_bytes` and
`uncompressed_bytes` per row group. `info.key_value` is a `dict` of every
key-value entry in the footer, key to value as text: the `dta` profile,
`ARROW:schema`, pandas' metadata, anything another writer put there.

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
print(df["region"].map(meta.labels("region")).tolist())
# ['North', 'South', 'South', 'East', 'West', 'North']
```

A code is an `int` or `float`, or a missing code as text: `"."`, `".a"`
to `".z"`. `meta.labels(name)` returns `{}` for a column without a set
and raises `KeyError` for a name `meta.columns` lacks.

`factors=True` makes each column with value labels a `category`, as R's
datakit does with `factors = TRUE`: its levels are the column's values
and the set's codes, in order of value, each labelled code as its label
and any other value as its number in text:

```python
df, meta = dk.read_parquet("survey.parquet", factors=True)
print(df["region"].cat.categories.tolist())   # ['North', 'South', 'East', 'West']
print(df["region"].tolist())        # ['North', 'South', 'South', 'East', 'West', 'North']
print(dk.na_tag(df["income"]).tolist())  # [nan, '.d', nan, nan, '.r', nan]
```

**What `factors=True` loses:** the codes are gone from the frame, and
codes that share a label (two codes both labelled "Yes") become one
level that cannot be told apart again. Saving does not bring them back:
`save_parquet` writes the category as a categorical of its levels, and
`save_dta` writes it as Stata's `encode` would, codes 1 to k labelled
with the levels. To keep the file's codes, read with `factors=False`,
the default. A category cannot hold `.a` to `.z` either: in a column
made one they become NaN, with one warning naming the columns, as R's
datakit does; `factors=False` keeps them. A categorical that a file
stores with letters stays its level numbers, as in R.

Other tools do not read labels: they see the codes. A file from another
tool has none, unless it has a `dta` entry in its metadata (written by
`save_parquet`, by R's datakit, by Julia's Datakit, or by another
library writing the same entry; see
[docs/parquet.md](parquet.md#the-profile)).

### Dates and time zones in Parquet files

A `datetime64` column is written as a TIMESTAMP in its own unit; a
tz-aware one is stored as an instant (adjusted to UTC) with its zone
kept, and a naive one as a clock time. A column `meta` gives the format
`%td` whose values are all at midnight is written as a DATE, and a
DATE reads as `datetime64[s]` with that format:

```python
visits = pd.DataFrame({
    "day": pd.Series(["2024-03-01", None], dtype="datetime64[s]"),
    "at": pd.Series(["2024-03-01 09:30", "2024-03-01 17:05"],
                    dtype="datetime64[us]").dt.tz_localize("America/New_York"),
    "local": pd.Series(["2024-03-01 09:30:00.000001", None], dtype="datetime64[us]"),
})
dk.save_parquet(visits, "visits.parquet", meta=dk.Meta(columns={"day": dk.Column(format="%td")}))
v, vm = dk.read_parquet("visits.parquet")
print(v.dtypes.astype(str).tolist())   # ['datetime64[s]', 'datetime64[us, America/New_York]', 'datetime64[us]']
print(v["at"][0], vm.columns["day"].format)   # 2024-03-01 09:30:00-05:00 %td
```

| pandas | written as | read back as |
|---|---|---|
| `datetime64[unit]` with `%td` in meta, every value at midnight | DATE | `datetime64[s]`, format `%td` |
| `datetime64[unit]` | TIMESTAMP in that unit, not adjusted to UTC (a clock time) | the same |
| `datetime64[unit, zone]` | TIMESTAMP in that unit, adjusted to UTC (an instant), the zone in the profile and `ARROW:schema` | the same, in that zone |
| `timedelta64` | TIME(NANOS), when every value is within a day | `timedelta64[ns]` |

Dates and timestamps from other files: DATE is `datetime64[s]`; a
TIMESTAMP is `datetime64` in the file's unit, with the zone the file's
dta profile or `ARROW:schema` gives, else UTC when it stores instants,
else none; a profile's `"unit": "s"` reads as `"ms"`. INT96 is
`datetime64[ns]`. TIME in milliseconds, microseconds or nanoseconds is
`timedelta64[ns]`, and is written back as TIME(NANOS). A null is `NaT`.
A date or timestamp that R wrote as a DOUBLE (days or seconds since
1970, because it holds `.a` to `.z` or a fraction) reads as
`datetime64[s]` or `datetime64[us]`; a value with a fraction of a day,
or seconds that no whole number of microseconds gives back, is an error
naming the column and row, and `timestamps="truncate"` drops the
fraction. A value outside the range is an error either way.

A `.dta` `%tc` time reads as `datetime64[ms]`, while R's timestamps
read from Parquet are `datetime64[us]`; pandas compares them across
units.

### Write a Parquet file

`save_parquet(df, path=None, meta=None, *, compression="snappy",
compression_level=None, row_group_size=None, missing_letters=True,
timestamps="error")` writes a pandas `DataFrame`. With a path it returns
`None`; without one it returns the file as `bytes`:

```python
df, meta = dk.read_parquet("survey.parquet")
dk.save_parquet(df, "small.parquet", meta=meta, compression="zstd", compression_level=3, row_group_size=2)
print(dk.read_parquet_info("small.parquet").row_groups["rows"].tolist())   # [2, 2, 2]
data = dk.save_parquet(df, meta=meta)
print(type(data).__name__, data[:4])                                        # bytes b'PAR1'
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
file as it was. The index is not written: call `df.reset_index()` first
to keep it.

What each dtype becomes:

| pandas | Parquet |
|---|---|
| `int8`, `int16`, `int32`, `int64` | INT(8), INT(16), INT32, INT64 |
| `uint8`, `uint16`, `uint32`, `uint64` | INT(8, unsigned) to INT(64, unsigned), with unsigned statistics; they read back as themselves |
| `float32`, `float64` | FLOAT, DOUBLE; a NaN is written as `.` (a null), and a tagged NaN as its letter ([Keep .a to .z](#keep-a-to-z-in-a-parquet-file)) |
| `bool` | BOOLEAN |
| nullable `Int8` ... `Int64`, `UInt8` ... `UInt64`, `Float32`, `Float64`, `boolean` | the same as the numpy type of that name, `<NA>` written as `.` |
| `DtaArray` (`dta[byte]` ... `dta[double]`) | its storage type with its codes: byte, int and long as INT(8), INT(16) and INT32, float as FLOAT, double as DOUBLE; with `.a` to `.z`, a DOUBLE with its storage type in the profile. When a value no longer fits that type exactly, the next of byte, int, long, float and double that holds every value |
| text (`str`, or `object` holding only text and missing values) | BYTE_ARRAY as STRING |
| `object` of `bytes` | BYTE_ARRAY without a type |
| `datetime64`, `timedelta64` | TIMESTAMP or DATE, TIME(NANOS) ([Dates](#dates-and-time-zones-in-parquet-files)) |
| `category` (of text) | a dictionary-encoded STRING whose dictionary is every category, in order, the dtype's `ordered` kept |

`object` of `decimal.Decimal` raises `TypeError` naming the column and
saying to make it float or text (writing DECIMAL needs an encoder no
`.dta` or R type needs). A category of numbers, `object` holding mixed
values, complex, interval, period and any other dtype raise
`TypeError` naming the column. An `object` column holding a
`MissingValue` (as pandas makes when `.a` is assigned into a numpy
column; see [Set a letter](#a-to-z-in-the-frame)) is refused with the
conversion to make. An unknown `compression` raises `ValueError`
listing the codecs. Column names may be any text, unlike in `.dta`
files, but must be text and appear once.

### Write labels to a Parquet file

Build or change a `Meta` and pass it as `meta=`. Every field is a plain
value to set:

```python
smoking = pd.DataFrame({"smoker": pd.Series([1.0, 0.0, dk.tagged_na(".d")], dtype="dta[byte]")})
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
print(dk.na_tag(s["smoker"]).tolist())     # [nan, nan, '.d']
```

The data label, notes, characteristics, sort order, time stamp, each
column's label, format and set, and every set (used or not) are
written. Entries for columns not in the frame are dropped without a
warning, so a `meta` from a wider read can be passed after
`df[[...]]`. Value label codes keep their type: whole numbers come
back as `int`, others as `float`, and missing codes as `".d"` text.
Unlike `.dta` files, a Parquet file can label codes that are not
integers, such as `1.5`. Writing is strict: a code that is not finite or
is beyond ±2^53, or a column naming a set `meta.value_labels` lacks, is
an error. A category's levels are its text, so its `value_labels` name
is not written. `meta.sort` is checked against the rows
([below](#labels-through-pandas-operations)).

### .a to .z in the frame

Every read keeps `.a` to `.z` in the frame. Each numeric column with a
missing value in the rows read is a `DtaArray`: float64 values and a
code per row, 1 for `.` and 2 to 27 for `.a` to `.z`
([Missing values](#missing-values) describes it). It compares as R's
doubles do: `x == 1`, `x != 1` and `x > 3000` are `<NA>` on every missing
row, `.` and each letter alike, so a filter drops them, and `groupby`
keeps `.`, `.a` and `.b` apart. Three functions read and make letters:

- `dk.na_tag(x)`: the letter of each row of `x` (a Series or array) as
  a Series of `dk.LETTERS`, a pandas `CategoricalDtype` of `".a"` to
  `".z"`, NaN where the row holds none;
- `dk.is_tagged_na(x, letter=None)`: a numpy bool array, true where a
  row holds a letter, or the letter given;
- `dk.tagged_na(".d")`: `dta_parser.missing.d`, the value a `DtaArray`
  gives back for `.d` and takes in assignment and comparison.

```python
df, meta = dk.read_parquet("survey.parquet")
income = df["income"]
print(income.dtype, income.isna().sum(), dk.is_tagged_na(income).sum())   # dta[double] 3 2
print(dk.na_tag(income).tolist())              # [nan, '.d', nan, nan, '.r', nan]
print(df[income == dk.tagged_na(".d")]["id"].tolist())   # [2]
print(df[income != 2100]["id"].tolist())       # [3, 6]
print(income.mean(), income.count())           # 2383.3333333333335 3
print(df.groupby("income", dropna=False).size().tolist())   # [1, 1, 1, 1, 1, 1]
```

A letter follows its row through filtering, sorting, `merge`, `concat`
and `groupby`, and arithmetic keeps it: `x * 2` is `.d` where `x` is, as
in R; where both sides are missing, the left one's code is kept.
`mean()`, `count()`, `isna()` and `dropna()` treat every letter as
missing.

**Set a letter** (Stata's `replace income = .r if age > 60`):

```python
df.loc[df["age"] > 60, "income"] = dk.tagged_na(".r")
print(dk.na_tag(df["income"]).tolist())   # [nan, '.d', nan, '.r', '.r', nan]
```

`loc` drops the rows where the condition is `<NA>`. pandas' `where` and
`mask` instead treat a `<NA>` condition as "replace", so give them
`cond.fillna(False)`: `df["income"].mask((df["income"] > 3000).fillna(False), dk.tagged_na(".r"))`.
To replace a letter with a value, test for it:
`df.loc[dk.is_tagged_na(df["income"], ".d"), "income"] = 0.0`.
`fillna(v)` fills every missing row, `.` and letters alike. A new column
(Stata's `gen y = .a`) is
`pd.Series([dk.tagged_na(".a")] * len(df), dtype="dta[double]", index=df.index)`.

Only a `DtaArray` holds a letter. A column of a numpy type does not:
pandas 3 refuses `df.loc[rows, "age"] = dk.tagged_na(".r")` with a
`TypeError`, and pandas 2.2 turns the column into `object` with a
warning, which `save_parquet` and `save_dta` then refuse. Convert it
first, `df["age"] = df["age"].astype("dta[byte]")` (or `dta[double]`).
A Series built from a list holding `MissingValue`s needs the dtype too,
`pd.Series([1, dk.tagged_na(".a")], dtype="dta[double]")`, since pandas
otherwise makes it `object`.

**Sort as Stata does** (values, then `.`, then `.a` to `.z`): a
`DtaArray` sorts so with `sort_values`; with several columns, pass
`key=dp.dta_keys`.

```python
df, meta = dk.read_parquet("survey.parquet")
stata = df.sort_values("income", kind="stable")
print(stata["income"].tolist())                # [1850.0, 2100.0, 3200.0, nan, .d, .r]
```

**What loses them.** numpy functions without an operator (`np.log`,
`np.sqrt`), `Series.to_numpy()`, `astype(float)` and `apply` with a
function that returns floats give `float64` with NaN for every missing
value ([Missing values](#missing-values) lists them); `fillna` replaces
them. A plain `float64` column may hold a letter as a tagged NaN (R's
bit pattern, which `na_tag` and saving read), but most pandas
operations make that a plain NaN, so a `DtaArray` is the way to keep a
letter.

**Dates, timestamps and categoricals.** A pandas `datetime64` or
`category` cannot hold a letter. A column of one of these types that
holds `.a` to `.z` in the rows read is read as numbers instead, a
`DtaArray`: a date becomes Stata's count of days since 1960 (format
`%td`), a timestamp its milliseconds since 1960 (`%tc`), and a
categorical its level numbers from 1, labelled by its value label set,
which is how R's and Julia's datakits read a categorical with letters.
So these columns, unlike numbers, change type with the rows read.
`letters=False` gives the `datetime64` or `category`, with the letters
as `NaT` or NaN. To make dates of the numbers, use
`pd.to_datetime(d.to_numpy(), unit="D", origin="1960-01-01")`.

### Keep .a to .z in a Parquet file

`save_parquet` and `save_dta` write the letters of every `DtaArray`
column, and the tagged NaNs of a plain float column, as `.a` to `.z`.
Any other NaN is `.`.

```python
df, meta = dk.read_parquet("survey.parquet")
dk.save_parquet(df, "kept.parquet", meta=meta)
print(dk.na_tag(dk.read_parquet("kept.parquet")[0]["income"]).tolist())   # [nan, '.d', nan, nan, '.r', nan]
```

In the file, a letter is a tagged NaN in a DOUBLE column, in the bits R
holds it in, so R reads the letters as its tagged NAs. The profile
records the column's storage type, so a byte column with letters comes
back as a byte column in R and Julia, and as `dta[byte]` here. Other
tools see `NaN`. pandas counts it as missing, but DuckDB SQL and polars
count `NaN` as a value: `IS NULL` is false for it, `count(x)` counts it
and `mean(x)` is `NaN`. To treat `.a` to `.z` as missing there, test for
both:

```python
import importlib.util
if importlib.util.find_spec("duckdb"):
    import duckdb
    print(duckdb.sql("SELECT count(*) FILTER (WHERE income IS NULL OR isnan(income)) "
                     "FROM 'survey.parquet'").fetchall())   # [(3,)]
```

For files meant for such tools, `missing_letters=False` writes `.a` to
`.z` as `.`, a null, and the letters are then lost:

```python
dk.save_parquet(df, "nulls.parquet", meta=meta, missing_letters=False)
print(dk.read_parquet("nulls.parquet")[0]["income"].array.codes.tolist())   # [0, 1, 0, 1, 1, 0]
```

### Parquet files from other tools

`read_parquet` reads the files pyarrow, pandas, polars, DuckDB, R's
arrow and nanoparquet, fastparquet and others write: the encodings
dictionary, PLAIN, RLE, the DELTA encodings and BYTE_STREAM_SPLIT, data
pages v1 and v2, and the codecs none, snappy, gzip, zstd, lz4_raw and
brotli. The one encoding not read is BIT_PACKED for values, which the
format has deprecated and current writers do not use (BIT_PACKED
repetition and definition levels are read).
A column that pandas, polars or arrow wrote as a category or factor (a
dictionary of text in the file's `ARROW:schema`) reads as a `category`
of the distinct values in the rows read, in order of first appearance,
unordered.

A file without a `dta` profile reads with an empty `Meta`, and there are
no letters. A NaN in a float column is read as `.`, as a null is:
pandas' nullable types do not keep a NaN apart from a null, and `.dta`
has no NaN. DECIMAL columns of up to 15 digits read as `float64` (the
nearest double), longer ones as `decimal.Decimal` objects, every digit
kept. Unsigned integers, INT96 and TIME are read too (see the table
below), and so are the files' other types: text annotated ENUM or JSON
as text, UUID and fixed-length bytes as `bytes`.

What is not read, each an error that names the column and its type:
FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, and encrypted files.
Values encoded BIT_PACKED are an error too. Nested columns (lists, maps, structs) raise an error unless `columns`
leaves them out or `nested="skip"` is given; `read_parquet_info` lists
them with role `"nested"`. Datasets of many files, Hive partitions and
filters on values are not part of datakit: use pyarrow, polars or
DuckDB.

### What each Parquet type becomes in Python

| Parquet | pandas |
|---|---|
| INT32: INT(8), INT(16) or none, FLOAT, DOUBLE, and `.dta` numbers, with a missing value (a null, a NaN, `.`, a letter) in the rows read | `DtaArray` of the storage type: `dta[byte]`, `dta[int]`, `dta[long]`, `dta[float]`, `dta[double]` |
| the same with no missing value | `int8`, `int16`, `int32`, `float32`, `float64` |
| a DOUBLE written so for `.a` to `.z` (profile `storage`) | as its storage type, by the two rows above |
| INT64; unsigned 8 to 64 bits; BOOLEAN | `int64`; `uint8` ... `uint64`; `bool`. With nulls: nullable `Int64`; `UInt8` ... `UInt64`; `boolean` (these cannot hold a letter) |
| a DOUBLE with profile `logical` `date` | `datetime64[s]`; a fraction of a day is an error unless `timestamps="truncate"`. With letters in the rows read, a `DtaArray` of days since 1960, format `%td` |
| a DOUBLE with profile `logical` `timestamp` | `datetime64[us]`, with its zone; a value no whole number of microseconds gives back is an error unless `timestamps="truncate"`. With letters in the rows read, a `DtaArray` of milliseconds since 1960, format `%tc` |
| DECIMAL, precision up to 15 | `float64` (a `DtaArray` with a null) |
| DECIMAL, precision above 15 | `object` of `decimal.Decimal`, every digit kept (`save_parquet` does not write it: convert first) |
| DATE | `datetime64[s]`, `NaT` for a null; `meta` gives it the format `%td` when the file names none |
| TIMESTAMP | `datetime64` in the file's unit (`"ms"` for the profile's `"unit": "s"`), with the profile's zone, else `ARROW:schema`'s, else `"UTC"` for instants |
| INT96 | `datetime64[ns]` |
| TIME | `timedelta64[ns]`, whatever the file's unit |
| STRING, ENUM, JSON | pandas' text dtype (`str` from pandas 3, `object` before) |
| BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text type, UUID | `object` of `bytes` |
| a categorical the profile lists | `category` of every level, in order, unused ones too, ordered as the file says |
| a DOUBLE with profile `logical` `categorical` (a categorical holding `.a` to `.z`) | the same `category` when the rows read hold no letters, with `factors` true or false. With letters, its level numbers (1 to k) as a `DtaArray`, as R and Julia read it, `meta.columns[name].value_labels` naming the set that labels them. A value that is not a level number reads as `.`, with one warning per read naming the column and the first such row |
| a dictionary of text in `ARROW:schema`, with no profile entry | `category`, unordered |
| FLOAT16, INTERVAL | not read: an error naming the column and type |
| nested (LIST, MAP, groups) | an error naming them, or left out with `nested="skip"` |

Every value is exact or an error, except DECIMAL of up to 15 digits,
which is the nearest double, as in R, Julia and TypeScript.

**What a round trip does not keep.** A frame and `Meta` that a read
gave come back from `save_parquet` and `read_parquet` equal, except: a
category that `factors=True` made comes back without its
`value_labels` name; a date, timestamp or categorical that held `.a` to
`.z` comes back as the numbers it was read as; a TIME in milliseconds
or microseconds comes back in nanoseconds; and `Decimal` objects are
not written. `.dta`'s release and encoding are not kept.

### Labels through pandas operations

`.a` to `.z` are in the frame, so they follow every row operation.
`Meta` does not follow pandas operations. Labels describe columns, not
rows, so a filter or a sort leaves them right, but a merge, a rename, a
new column or an aggregation is yours to mirror.

**Merges.** pandas renames a column both sides have (`income_y`); copy
the right frame's labels into `meta` yourself. Merge keys must have one
dtype: make both `dta[double]` first if one side is a `DtaArray`:

```python
df, meta = dk.read_parquet("survey.parquet")
right, right_meta = dk.read_parquet("survey.parquet", columns=["id", "income"])
joined = df.merge(right, on="id", how="left", suffixes=("", "_right"))
meta.columns["income_right"] = right_meta.columns["income"]
dk.save_parquet(joined, "joined.parquet", meta=meta)
print(dk.na_tag(dk.read_parquet("joined.parquet")[0]["income_right"]).tolist())
# [nan, '.d', nan, nan, '.r', nan]
```

**Aggregation** (`groupby().agg()`): a mean or a count of `x` is a new
value, which skips every missing row; make `meta` for the new frame
with `meta.select([...])`.

**`Meta`'s methods.** `meta.rename(mapping)` and `meta.select(names)`
return a new `Meta` for `df.rename(columns=mapping)` and `df[names]`;
`meta.copy()` is a deep copy; `meta == other` compares every field.
`select` keeps `meta.sort` up to its first column not selected.
`meta.sort` is checked when saving: if the rows are no longer in that
order as Stata orders them (values, then `.`, then `.a` to `.z`),
`save_parquet` and `save_dta` leave it out with one warning.

```python
by_region = df.sort_values("region", kind="stable")
region_meta = meta.select(["id", "region"])
region_meta.sort = ["region"]
dk.save_parquet(by_region[["id", "region"]], "regions.parquet", meta=region_meta)
print(dk.read_parquet("regions.parquet")[1].sort)   # ['region']
```

### .dta files into pandas

`dk.read_dta(path, columns=None, skip=0, n_max=None, factors=False,
letters=True, encoding=None, timestamps="error")` and `dk.save_dta(df, path, meta=None, *,
missing_letters=True, timestamps="error")` read and write `.dta` files
with the same `(df, meta)`:

```python
df, meta = dk.read_dta("survey.dta")
print(df["interviewed"].dtype, meta.timestamp is not None)   # datetime64[s] True
dk.save_dta(df, "again.dta", meta=meta)
back = dp.read_dta("again.dta")                                # dta_parser's reader
print(back["income"].tolist())   # [2100.0, .d, 1850.0, nan, .r, 3200.0]
```

`read_dta` reads releases 104 to 119 and gives the columns
`dp.read_dta` gives: byte, int, long, float and double are `int8`,
`int16`, `int32`, `float32` and `float64` without a missing value in
the rows read, and a `DtaArray` of that storage type with one; strN and
text strLs are pandas' text dtype, binary strLs `object` of `bytes` (a
strL column mixing text and binary values is all `bytes`, its text as
UTF-8, where `dp.read_dta` gives its text rows as `str`). `%td` is
`datetime64[s]`, and a value with a fraction of a day is an error
naming the column and row unless `timestamps="truncate"` (`dp.read_dta`
leaves such a column as numbers). `%tc` is `datetime64[ms]`, and a value
with a fraction of a millisecond is an error unless
`timestamps="truncate"`. A value outside the range is an error either
way. A date or timestamp holding `.a` to `.z` is a `DtaArray` of its
numbers, of its storage type. `%tC` and the other `%t` formats stay
numbers, with their format in `meta`. `encoding` decodes text in files
before release 118, as in `dp.read_dta`. Two arguments are datakit's
own: `letters=False` and `factors=True`.

`save_dta` writes release 118 with the storage types `dp.write_dta`
chooses: the smallest of byte, int and long that holds an integer
column's values (double past long, an error past ±2^53), `float32` as
float, `float64` as double, `bool` as byte, text as strN or strL,
`bytes` as a binary strL; nullable types the same, `<NA>` as `.`. A
`DtaArray` is written in its storage type, or the next type that holds
every value when one no longer fits. A `datetime64` column is `%td`
when `meta` gives it `%td` and every value is at midnight, else `%tc`,
which holds milliseconds, so a finer value is an error unless
`timestamps="truncate"`, and a time zone is an error. A `category` is
written as Stata's `encode` makes one: codes 1 to k, stored as long,
labelled with its categories. `timedelta64`, `Decimal` objects and
other types are errors naming the column, as is a name Stata cannot
hold. `.a` to `.z` are kept, as in `save_parquet`.

**Categoricals.** `save_dta` writes each `category` with a value label
set named after the column (replacing `meta`'s set of that name, or
`name_2`, `name_3`, ... when another column's labels use that name),
and marks it with a characteristic, `dtaparser_categorical` =
`ordered <set>` or `unordered <set>` (from the dtype's `ordered`). The
set labels the levels at codes 1 to k, and keeps the labels on `.a` to
`.z` of the set that `meta.columns[name].value_labels` names, so
"Refused" on `.r` survives whatever that set is called. A
`dtaparser_factor` or `dtaparser_categorical` in `meta.characteristics`
is not written, for any column: it describes what was written before,
and the column may be integers now.

`read_dta` gives a marked column back as a `category` of its set's texts
in code order, unused ones included, whatever `factors` says, ordered
as the mark says (and `meta.columns[name].ordered` too), with
`meta.columns[name].value_labels` naming its set, which
`meta.value_labels` keeps, and the mark leaves `meta.characteristics`:

```python
grades = pd.DataFrame({"grade": pd.Categorical(["low", None, "high"], categories=["low", "mid", "high"],
                                               ordered=True)})
gmeta = dk.Meta(columns={"grade": dk.Column(value_labels="gl")}, value_labels={"gl": {".r": "Refused"}}, rows=3)
dk.save_dta(grades, "grades.dta", meta=gmeta)
g, gm = dk.read_dta("grades.dta")
print(g["grade"].cat.categories.tolist(), g["grade"].tolist())   # ['low', 'mid', 'high'] ['low', nan, 'high']
print(gm.columns["grade"].ordered, gm.labels("grade"))
# True {1: 'low', 2: 'mid', 3: 'high', '.r': 'Refused'}
```

A category cannot hold `.a` to `.z`. A marked column that holds them in
the rows read, as TypeScript's `saveDta` writes one, reads as its codes,
a `DtaArray` labelled by its set, its mark kept in
`meta.characteristics`. `letters=False` gives the category, with the
letters as NaN.

Through `.dta`, then, a categorical keeps its levels, their order,
unused levels and letter labels, but its codes become 1 to k:
a file whose set has codes 10, 20, 30 is written back with 1, 2, 3 and
the same texts. The mark is checked as `dta_parser` checks it ([Columns
written from categoricals](#columns-written-from-categoricals)),
except that `read_dta` always converts dates: a marked `%td` or `%d`
column, read as a `datetime64`, fails. A column that fails, or has both
marks, is read as if unmarked (a `category` with `factors=True`, as any
labelled column), with one `UserWarning` per read naming such columns.
`dtaparser_factor` alone, which R's `save_dta` and `dp.write_dta`
write, is not read as a mark: such a column reads as labelled numbers,
where `dp.read_dta` gives a `category`.

### Memory and copies

A read lays every column out in one allocation and hands each buffer to
numpy without a copy: numbers, booleans, timestamps and times, a
`DtaArray`'s values when the file stores doubles, and a category's
codes, which the read writes in place. The buffer lives as long as any
column, slice or frame uses it. Some kinds are converted once, natively,
into new buffers handed over the same way: a `DtaArray`'s codes, and its
values when the storage type is byte, int, long or float; a nullable
column's mask; DATE as int64 seconds. Text is a `str` per row (one per
distinct value of a column's recent rows), decimals `Decimal` objects.
A tz-aware timestamp is made from the int64 values without a copy on
pandas 3 and with one on pandas 2.2. Saving reads the frame's numpy
arrays in place, after making each C-contiguous and aligned
(`np.require`), and copies text into the file's layout.

A `DtaArray` takes 9 bytes a row (a float64 and a code), so a `byte`
column with a missing value takes 9 bytes a row where an `int8` one
takes 1.

### Coming from pyarrow, pandas or polars

| pandas | pyarrow | polars | datakit | what changes |
|---|---|---|---|---|
| `pd.read_parquet(p)` | `pq.read_table(p)` | `pl.read_parquet(p)` | `df, meta = dk.read_parquet(p)` | a pandas frame and a `Meta`; labels, `.a` to `.z`, formats and notes kept; no pyarrow needed |
| `pd.read_parquet(p, columns=[...])` | `pq.read_table(p, columns=["a", "b"])` | `pl.read_parquet(p, columns=["a", 1])` | `dk.read_parquet(p, columns=["a", 1])` | names or positions; an unknown name is a `KeyError` listing the file's columns |
| none; `.iloc[100:150]` after reading | `pq.ParquetFile(p).read_row_groups([...])` | `pl.scan_parquet(p).slice(100, 50).collect()` | `dk.read_parquet(p, skip=100, n_max=50)` | only the pages that hold the rows are read |
| `filters=` | `pq.read_table(p, filters=...)` | `pl.scan_parquet(p).filter(...)` | none: read, then `df[...]` | no predicate pushdown |
| none | `pq.read_metadata(p)`, `pq.read_schema(p)` | `pl.read_parquet_schema(p)` | `dk.read_parquet_info(p)` | rows, row groups, codecs, key-value entries, labels, and the pandas dtype each column gets |
| `df.to_parquet(p)` (snappy) | `pq.write_table(t, p)` (snappy) | `df.write_parquet(p)` (zstd) | `dk.save_parquet(df, p, meta=meta)` (snappy) | labels and letters written in the `dta` profile, which R's and Julia's datakits read; the index is not written |
| `df.to_parquet(None)` | `pq.write_table(t, buf)` | `df.write_parquet(io.BytesIO())` | `dk.save_parquet(df)` | returns `bytes` |
| `compression="zstd"` | the same | the same, with `compression_level=3` | the same | |
| `row_group_size=n` | the same | the same | the same | |
| `df.attrs` | `schema.with_metadata(...)` | `write_parquet(metadata={...})` | `meta` | value label codes stay numbers and `.a` ... `.z` |
| | `use_threads=False` | `POLARS_MAX_THREADS=1` | `DTA_THREADS=1` | |

What changes in the values, against `pd.read_parquet`: a numeric
column with a missing value is a `DtaArray`, which compares as missing,
and an integer one is not made float; a NaN is `.`; a categorical keeps
every level and its order; and a profile's dates, timestamps and
storage types come back as the writer gave them.

## Threads

Reading and writing large files uses up to three threads: workers decode the rows and fill numeric columns, released from the GIL, while the calling thread makes the strings. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work.

datakit's reads and writes, of Parquet and of `.dta`, decode or encode on worker threads with the GIL released, straight into memory numpy then adopts, or out of the frame's numpy arrays. Parquet reads of 256 KiB or more use one thread per 32 MiB of values, at least four and at most twelve; writes one per 8 MiB, at least four and at most sixteen. These counts were chosen against polars, which uses every core, for wall time with CPU time in proportion. The rule and the numbers are in [docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them).

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
(setuptools 77 or later, numpy and pandas must then be
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

**`ImportError: datakit 0.4.0 needs dta_parser's native functions at
ABI version 2`.** datakit and dta_parser come from different
checkouts. Reinstall both from one:
`pip install --force-reinstall ./dta-parser/python ./dta-parser/python/datakit`.

**`AttributeError: 'tuple' object has no attribute 'query'`.** Every
datakit read returns `(df, meta)`; unpack it first.

**`read_parquet` raises "the file has nested columns, which are not
read".** The file has a list, map or struct column. Pass `columns=` with
the flat columns, or `nested="skip"`; for the nested data, use pyarrow
or polars.

**A column read as `dta[...]` in one window and `int8` in another.** A
numeric column is a `DtaArray` when the rows read hold a missing value.
Both filter and group alike, and `pd.concat` gives a `DtaArray`.

**A column read as `dta[double]` that is a date or a categorical in the
file.** It holds `.a` to `.z` in the rows read, which no `datetime64` or
`category` can hold. Pass `letters=False` to read the letters as `.`
and keep the type.

**`TypeError` assigning `dk.tagged_na(...)` into a column, or a column
that became `object`.** Only a `DtaArray` holds a letter; convert the
column first with `astype("dta[double]")`
([Set a letter](#a-to-z-in-the-frame)).

**`ValueError: cannot convert NA to bool` or "boolean value of NA is
ambiguous".** A comparison with a missing row is `<NA>`. Filter with
`df[cond]` or `df.loc[cond]`, which drop those rows, or use
`cond.fillna(False)`.

**A warning "meta.sort (x) does not describe the order of the frame's
rows".** The rows were reordered. Sort as the
[recipe](#a-to-z-in-the-frame) does, or clear `meta.sort`.

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
  write a pandas frame as Parquet; returns `bytes` without a path.
- `read_dta(path, columns=None, skip=0, n_max=None, factors=False, letters=True, encoding=None, timestamps="error")`
  and `save_dta(df, path, meta=None, *, missing_letters=True, timestamps="error")`:
  `.dta` files and pandas ([.dta files into pandas](#dta-files-into-pandas)).
- `read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None, commented_formats=True, letters=True)`:
  fixed-width text through its SAS setup file, given as one path or a
  list of paths ([Fixed-width files](#fixed-width-files-with-a-sas-setup-file)).
- `tagged_na(letter)`, `na_tag(x)`, `is_tagged_na(x, letter=None)`:
  make `.a` to `.z` (`dta_parser.missing.a` ...), and read them from a
  Series or array ([.a to .z in the frame](#a-to-z-in-the-frame)).
- `Meta`, `Column`: the labels, formats and notes beside a frame
  ([Labels](#labels-in-parquet-files)); `Meta` has `labels`, `rename`,
  `select` and `copy`.
- `ParquetInfo`: what `read_parquet_info` returns.
- `LETTERS`: the pandas `CategoricalDtype` of `".a"` to `".z"`, the
  dtype of what `na_tag` returns.
- `FixedWidthWarning`: the warning `read_fixed_width` gives for
  statements it skipped; `messages` lists them.
