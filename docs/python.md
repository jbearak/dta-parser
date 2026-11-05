# Python: dta_parser

`dta_parser` reads Stata `.dta` files into pandas DataFrames and writes
DataFrames back as `.dta` files. It reads every release from 104 to 119
and writes release 118. It also reads and writes Parquet files that keep
the same labels and missing values ([Parquet files](#parquet-files)). Unlike `pandas.read_stata` and pyreadstat, it
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
[Fixed-width files](#fixed-width-files-with-a-sas-setup-file) ·
[Parquet files](#parquet-files) ·
[Threads](#threads) ·
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

**Comparisons.** `>`, `<` and `==` on a `StataArray` follow pandas, not
Stata: a missing value compares false with everything (`income > 1000`
is false where `income` is `.a`). For Stata's rule, where missing values
are larger than every number, compare keys:
`dp.stata_keys(df["income"]) > 1000`.

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
| `meta.original_variable_types` (display formats) | `attrs["dta"]["columns"][c]["format"]` |
| `meta.readstat_variable_types` | `attrs["dta"]["columns"][c]["storage"]` (Stata's own names: `byte`, `int`, `long`, `float`, `double`, `strN`, `strL`) |
| `pyreadstat.write_dta(df, path, file_label=..., column_labels=...)` | `dp.write_dta(df, path, label=..., variable_labels=...)` |
| `variable_value_labels={"col": {1: "a"}}` | `attrs["dta"]["value_labels"]` and each column's `value_labels` |
| `missing_user_values` | write a `StataArray` with the codes |
| `pyreadstat.read_file_in_chunks(...)` | a loop over `skip` and `n_max`; see [Read some rows](#read-some-rows) |

## Fixed-width files with a SAS setup file

Some surveys are published as fixed-width text with a SAS program, the
*setup file*, that says where each variable sits. CDC publishes the
National Survey of Family Growth this way, from 1973 to 2017-2019.
`read_fixed_width` reads such data through its setup file: columns from
`INPUT`, variable labels from `LABEL`, value labels from `PROC FORMAT`
and `FORMAT`, record types from
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
`NaN`, and the columns are as `read_dta` returns them:

```python
df = dp.read_fixed_width("survey.dat", "survey.sas")
print(df["KIDS"].tolist())                            # [2.0, nan, nan, 0.0]
print(df.attrs["dta"]["columns"]["KIDS"]["label"])    # Number of children
```

`recodes="tagged"` keeps why each value is missing: per variable, the
codes recoded to `.` become `missing.a`, `missing.b`, ... in the order
the setup names them, and each code's value label moves to its letter:

```python
df = dp.read_fixed_width("survey.dat", "survey.sas", recodes="tagged")
print(df["KIDS"].tolist())                     # [2.0, .a, .b, 0.0]
print(df["KIDS"][1] is missing.a)              # True
print(df.attrs["dta"]["value_labels"]["kidsf"])
# {0: '(0) None', .a: '(98) DK', .b: '(99) Not ascertained'}
```

A letter means what that variable's labels say: `.a` is 98 "DK" here,
but in a variable whose setup recodes 97 "Refused" first, `.a` is
"Refused". `recodes="none"` ignores the recodes, keeping the codes as
numbers.

Numeric columns take the smallest storage type that holds their values,
and records shorter than the setup's columns read as blank (`.`).
Statements the reader does not run, such as other data-step code or a
range in `VALUE`, are skipped with one `FixedWidthWarning`;
`df.attrs["warnings"]` lists them all. A `LENGTH` statement for numbers, which sets only how SAS stores them, is skipped without one. A variable label with stray
quotes inside it, such as `X = "WHETHER " SAME AS LAST MONTH" WAS
ANSWERED"` in CDC's 2011-2013 to 2015-2017 setups, is read from its
first quote to its last, without a warning. `columns`,
`skip` and `n_max` work as in `read_dta`, after the whole file is read.

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
df = dp.read_fixed_width("survey.dat", ["input.sas", "labels.sas"], recodes="none")
print(df.attrs["dta"]["value_labels"]["kidsf"])   # {0: '(0) None', 98: '(98) DK'}
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
df = dp.read_fixed_width("survey.dat", "commented.sas", recodes="none")
print(df.attrs["dta"]["value_labels"])   # {'kidsf': {0: '(0) None', 98: '(98) DK'}}
df = dp.read_fixed_width("survey.dat", "commented.sas", recodes="none", commented_formats=False)
print(df.attrs["dta"]["value_labels"])   # {}
```

## Parquet files

`read_parquet` and `write_parquet` read and write Parquet files that
keep what a `.dta` file says: variable labels, value labels, display
formats, `.a` to `.z`, the data label, notes and characteristics, and
also categories and time zones. `read_parquet` returns the DataFrame
`read_dta` returns, so a script that reads a `.dta` file can switch to
Parquet by changing one name, and a frame `read_dta` gave comes back
from `write_parquet` and `read_parquet` equal (`assert_frame_equal`),
with the same `attrs["dta"]`. The files are plain Parquet that pyarrow,
pandas, polars, DuckDB and R's arrow read;
[docs/parquet.md](parquet.md) says what each of them sees and gives the
file's specification. Only flat tables are read and written: for lists,
maps or structs, use pyarrow or polars. And if you want a pyarrow
`Table` or a polars `DataFrame` rather than pandas, read with pyarrow or
polars: `read_parquet` returns pandas only.

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
[Keep .a to .z](#keep-a-to-z-in-a-parquet-file) ·
[Files from other tools](#parquet-files-from-other-tools) ·
[What each type becomes](#what-each-parquet-type-becomes-in-python) ·
[The index](#the-index-and-parquet-files) ·
[Coming from pyarrow, pandas or polars](#coming-from-pyarrow-pandas-or-polars)

### Parquet: install

Parquet needs nothing beyond `dta_parser` ([Install](#install)): the
reader and writer are in its Rust core, with the codecs (snappy, zstd,
gzip, lz4, brotli) built in, so pyarrow is not needed. Where pyarrow is
installed, pandas 3 keeps text in Arrow memory, and `read_parquet` fills
that memory directly. A build from source also compiles the zstd C
library, with the C compiler the build already uses.

### Read a Parquet file

This writes the example file as Parquet and reads it back:

```python
import dta_parser as dp
import pandas as pd

df = dp.read_dta("survey.dta")
dp.write_parquet(df, "survey.parquet")
back = dp.read_parquet("survey.parquet")
pd.testing.assert_frame_equal(back, df)   # no error: the same values and dtypes
print(back["income"].array.codes)         # [ 0  5  0  1 19  0]
print([str(t) for t in back.dtypes])
# ['int8', 'int8', 'int8', 'stata[double]', 'datetime64[s]', 'str']
```

`read_parquet(source, columns=None, skip=0, n_max=None, nested="error")`
takes a path (`str` or `os.PathLike`), the file as `bytes`, or a binary
file object with `read` and `seek`, and returns a DataFrame with a
default `RangeIndex`:

```python
with open("survey.parquet", "rb") as f:
    print(len(dp.read_parquet(f)))                       # 6
raw = open("survey.parquet", "rb").read()
print(dp.read_parquet(raw)["id"].tolist())               # [1, 2, 3, 4, 5, 6]
```

Columns get `read_dta`'s types: numbers in their storage type's width,
`NaN` for `.`, a `StataArray` where a column holds `.a` to `.z`,
`datetime64` for dates and pandas' default text dtype for text.
[What each type becomes](#what-each-parquet-type-becomes-in-python)
gives the type of every Parquet column, including those of files
other tools write.

### Read some columns of a Parquet file

`columns` takes names or 0-based positions (of the file's data
columns), or a mix, and returns them in the order given; only those
columns are read from the file:

```python
part = dp.read_parquet("survey.parquet", columns=["income", 0])
print(list(part.columns))      # ['income', 'id']
```

A name the file does not have raises `KeyError`, listing the file's
columns (`column "weight" is not in the file; its columns are "id",
"region", ...`); a position out of range raises `IndexError`. Naming a
column twice reads it once.

### Read a range of rows of a Parquet file

`skip` rows are skipped, then at most `n_max` are read (all when
`None`), as in `read_dta`:

```python
print(dp.read_parquet("survey.parquet", skip=2, n_max=2)["id"].tolist())   # [3, 4]
```

Only the row groups that hold the rows are read, and within them only
the pages that do (through the file's offset index, or, where a file has
none, by walking the page headers), so a window of a large file is
quick. Rows past the end give fewer rows, or an empty frame with the
right columns; it is not an error. A column's dtype follows the rows
read, as in `read_dta`: an integer column with a missing value only
outside the window comes back as integers.

### A Parquet file's schema and metadata

`read_meta(source)` reads the footer only, for a Parquet file or a
`.dta` file (it tells them apart by their first bytes). For Parquet it
gives what `read_parquet` puts in `attrs["dta"]` for every column, and
also the row count, the row groups, the codecs, the writer and, per
column, Parquet's types and the pandas dtype `read_parquet` will give:

```python
meta = dp.read_meta("survey.parquet")
print(meta["nobs"], meta["format"], meta["compression"])      # 6 parquet ['snappy']
print(meta["row_groups"])
# [{'rows': 6, 'compressed_bytes': 329, 'uncompressed_bytes': 329}]
print(meta["created_by"])                                     # dta-parquet version 0.1.0
print(meta["columns"]["region"])
# {'storage': 'byte', 'format': '%8.0g', 'label': 'Region', 'value_labels': 'region',
#  'role': 'data', 'physical_type': 'INT32', 'logical_type': 'INT(8, signed)', 'dtype': 'int8'}
print(meta["label"], meta["notes"])
# Household survey (example) ['Made up for the dta_parser documentation.']
```

Each column's entry has:

| key | holds |
|---|---|
| `role` | `"data"`, or `"nested"` for a list, map or struct, which is not read |
| `physical_type`, `logical_type` | Parquet's types, such as `"INT32"` and `"INT(8, signed)"`, `"DOUBLE"` and `None`, `"BYTE_ARRAY"` and `"STRING"` |
| `dtype` | the pandas dtype `read_parquet` gives when it reads every row, judged from the footer's null counts (`"float32"` for an `INT(8)` column with nulls; as if there were none where a writer gave no counts). A DOUBLE column holding `.a` to `.z` shows `"float64"` unless it was written wider (`"stata[byte]"` for a byte column), since the footer does not count them |
| `storage` | the Stata storage type the column has in `attrs["dta"]`: `"byte"`, `"int"`, `"long"`, `"float"`, `"double"`, `"str"` (text), `"strL"` (bytes); `None` for types Stata has no storage type for (64-bit and unsigned integers, booleans, categories, times) |
| `format`, `label`, `value_labels` | the display format, variable label and value label set's name, from the file's dta profile (`""` if none) |

The other keys are those of `attrs["dta"]` (`label`, `notes`,
`characteristics`, `sort_order`, `value_labels`, `timestamp`), plus
`nobs`, `format` (`"parquet"`), `row_groups`, `compression` and
`created_by`. Other key-value metadata in the file is not returned; use
`pyarrow.parquet.read_metadata(path).metadata` for it.

### Labels in Parquet files

Labels are where `read_dta` puts them, in `df.attrs["dta"]`, and are
used the same way ([Value labels](#value-labels)):

```python
back = dp.read_parquet("survey.parquet")
info = back.attrs["dta"]
print(info["columns"]["age"]["label"])               # Age in years
labels = info["value_labels"][info["columns"]["region"]["value_labels"]]
print(back["region"].map(labels).tolist())           # ['North', 'South', 'South', 'East', 'West', 'North']
print(info["value_labels"]["nonresponse"][missing.d])   # Don't know
```

Other tools do not read labels: they see the codes. A file from another
tool has none, unless it has a `dta` entry in its metadata (written by
`write_parquet`, by R's datakit, or by another library writing the same
entry; see [docs/parquet.md](parquet.md#the-profile)). pandas' own
`df.attrs`, which `DataFrame.to_parquet` keeps in its `PANDAS_ATTRS`
entry, is not read.

### Dates and time zones in Parquet files

A `%td` column (`datetime64[s]` from `read_dta`) is written as a
Parquet DATE and reads back as `datetime64[s]`. Any other `datetime64`
column is a TIMESTAMP in its own unit, and a tz-aware one is stored as
an instant with its zone kept:

```python
visits = pd.DataFrame({
    "at": pd.to_datetime(["2024-03-01 09:30", "2024-03-01 17:05"]).tz_localize("America/New_York"),
    "local": pd.to_datetime(["2024-03-01 09:30:00.000001", None]),
})
dp.write_parquet(visits, "visits.parquet")
v = dp.read_parquet("visits.parquet")
print(v["at"].dtype, v["local"].dtype)    # datetime64[us, America/New_York] datetime64[us]
print(v["at"][0])                         # 2024-03-01 09:30:00-05:00
```

| pandas | written as | read back as |
|---|---|---|
| `datetime64` with a `%td` format in `attrs` | DATE | `datetime64[s]` |
| `datetime64[s]` | TIMESTAMP(MILLIS), with `"unit": "s"` in the profile | `datetime64[s]` |
| `datetime64[ms]`, `[us]`, `[ns]` | TIMESTAMP in that unit, not adjusted to UTC (a clock time) | the same, without a zone |
| `datetime64[unit, tz]` | TIMESTAMP in that unit, adjusted to UTC (an instant), the zone in the profile and `ARROW:schema` | the same, in that zone |

A `%td` column with a time of day, or with a time zone, is an error
naming the column and the first such row, which says to drop the format
from `attrs["dta"]["columns"]` to write it as a timestamp. pyarrow and
polars read our zones too.

Dates and timestamps from other tools: DATE is `datetime64[s]`; a
TIMESTAMP is `datetime64` in its own unit (pandas holds every unit
Parquet has, so nothing is rounded), tz-aware when the file stores
instants (adjusted to UTC), in the zone the file's dta profile or
`ARROW:schema` gives, else UTC; INT96 timestamps are `datetime64[ns]`; a
TIME is `timedelta64` in its unit. Null is `NaT`. `datetime64[s]` holds
dates far beyond any a Parquet DATE can hold, so no date is out of
range.

### Write a Parquet file

`write_parquet(df, path=None, *, label=None, variable_labels=None, compression="snappy", compression_level=None, row_group_size=None, missing_letters=True)`
writes what `write_dta` writes, and also categories, booleans, tz-aware
times, 64-bit integers, nullable dtypes and text of any length. With a
path it returns `None`; without one it returns the file as `bytes`:

```python
dp.write_parquet(df, "small.parquet", compression="zstd", compression_level=3, row_group_size=2)
print([g["rows"] for g in dp.read_meta("small.parquet")["row_groups"]])   # [2, 2, 2]
data = dp.write_parquet(df)
print(type(data).__name__, data[:4])                                     # bytes b'PAR1'
```

`compression` is `"snappy"` by default, which pyarrow, polars and
DuckDB read fastest; `"zstd"`, `"gzip"`, `"lz4_raw"` and `"none"` are
the others, and `compression_level` sets zstd's (1 to 22, default 3) or
gzip's (0 to 9, default 6). zstd makes survey files about a sixth
smaller, and slower to read. Row groups hold up to 262,144 rows and
about 1 GiB of values unless `row_group_size` gives the rows.
[docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them)
gives the measurements behind these defaults. The file is written
beside the target and renamed, so a failed write leaves an existing
file as it was.

What each dtype becomes:

| pandas | Parquet |
|---|---|
| `int8`, `int16`, `int32`, `int64` | INT(8), INT(16), INT32, INT64 |
| `uint8`, `uint16`, `uint32`, `uint64` | INT(16), INT32, INT64, INT64 (a value of 2^63 or more is an error) |
| `float32`, `float64` (also `float16`) | FLOAT, DOUBLE; `NaN` is null. A float column whose `attrs` storage is byte, int or long (as `read_dta` gives one holding `.`) is that integer type, where every value fits it |
| `StataArray` | its storage type; `.` is null, `.a` to `.z` tagged NaNs in a DOUBLE column ([below](#keep-a-to-z-in-a-parquet-file)) |
| nullable `Int*`, `UInt*`, `Float*`, `boolean` | as the plain dtype, `pd.NA` null |
| `bool` | BOOLEAN |
| `category` with text categories | a dictionary-encoded STRING whose dictionary is every category, in order; whether it is ordered is kept |
| `datetime64`, tz-aware or not | DATE or TIMESTAMP ([Dates](#dates-and-time-zones-in-parquet-files)) |
| `str`, `object` of `str` | STRING; `None`, `NaN` and `pd.NA` are null |
| `object` of `bytes` | BYTE_ARRAY |
| `object` mixing `str` and `bytes` | BYTE_ARRAY; every value reads back as `bytes` |

`timedelta64`, a category of numbers or dates, and `object` columns of
anything else raise `TypeError` naming the column (convert them first,
for example with `.astype(str)`), and an unknown `compression` a
`ValueError` listing the codecs. Column names must be text; any text
will do, unlike in `.dta` files.

### Write labels to a Parquet file

Labels are written from `attrs["dta"]`, as `write_dta` takes them
([Write a file](#write-a-file)), with `label=` and `variable_labels=`
over them:

```python
smoking = pd.DataFrame({"smoker": pd.Series([1, 0, missing.d], dtype="stata[byte]")})
smoking.attrs["dta"] = {
    "columns": {"smoker": {"value_labels": "yesno", "format": "%8.0g"}},
    "value_labels": {"yesno": {0: "No", 1: "Yes", missing.d: "Don't know"}},
    "notes": ["Wave 2 only."],
}
dp.write_parquet(smoking, "smoking.parquet", label="Smoking", variable_labels={"smoker": "Smokes daily"})
s = dp.read_parquet("smoking.parquet")
print(s.attrs["dta"]["label"], s.attrs["dta"]["notes"])     # Smoking ['Wave 2 only.']
print(s.attrs["dta"]["columns"]["smoker"])
# {'storage': 'byte', 'format': '%8.0g', 'label': 'Smokes daily', 'value_labels': 'yesno'}
print(s.attrs["dta"]["value_labels"]["yesno"])              # {0: 'No', 1: 'Yes', .d: "Don't know"}
```

Value label codes keep their type: whole numbers come back as `int`,
others as `float`, and `.a` to `.z` as `missing.a` ... `missing.z`
(the file stores them as JSON numbers and `".d"`, not as text keys).
Unlike `.dta` files, a Parquet file can label codes that are not
integers, such as `1.5`. The data label, notes, characteristics, sort
order and time stamp go into the file too. Categories need no value
labels: their text is the data.

### Keep .a to .z in a Parquet file

`.a` to `.z` are written as tagged NaNs, the bits R holds them in, in a
DOUBLE column whose storage type the file records; they come back with
their letters, and as R's tagged NAs in R's arrow and nanoparquet:

```python
back = dp.read_parquet("survey.parquet")
print(back["income"].tolist())            # [2100.0, .d, 1850.0, nan, .r, 3200.0]
print(back["income"][1] is missing.d)     # True
```

Other tools see `NaN`. pandas counts it as missing, but DuckDB SQL and
polars count `NaN` as a value: `IS NULL` is false for it, `count(x)`
counts it and `mean(x)` is `NaN`. To treat `.a` to `.z` as missing
there, test for both:

```python
import importlib.util
if importlib.util.find_spec("polars"):
    import polars as pl
    income = pl.read_parquet("survey.parquet")["income"]
    print((income.is_null() | income.is_nan()).to_list())   # [False, True, False, True, True, False]
if importlib.util.find_spec("duckdb"):
    import duckdb
    print(duckdb.sql("SELECT count(*) FILTER (WHERE income IS NULL OR isnan(income)) "
                     "FROM 'survey.parquet'").fetchall())   # [(3,)]
```

For files meant for such tools, `missing_letters=False` writes `.a` to
`.z` as plain nulls; the letters are then lost:

```python
dp.write_parquet(df, "nulls.parquet", missing_letters=False)
print(dp.read_parquet("nulls.parquet")["income"].tolist())   # [2100.0, nan, 1850.0, nan, nan, 3200.0]
```

### Parquet files from other tools

`read_parquet` reads the files pyarrow, pandas, polars, DuckDB, R's
arrow and nanoparquet, fastparquet and others write: every encoding
(dictionary, PLAIN, the DELTA encodings, BYTE_STREAM_SPLIT), data pages
v1 and v2, and the codecs none, snappy, gzip, zstd, lz4_raw and brotli.
A column that pandas, polars or arrow wrote as a category or factor (a
dictionary of text in the file's `ARROW:schema`) reads as `category`:

```python
if importlib.util.find_spec("pyarrow"):
    pd.DataFrame({
        "size": pd.Categorical(["b", "a", "b"], categories=["a", "b", "c"]),
        "n": pd.array([1, None, 3], dtype="Int64"),
    }).to_parquet("from_pandas.parquet")
    other = dp.read_parquet("from_pandas.parquet")
    print(other["size"].cat.categories.tolist())       # ['b', 'a']
    print(dp.read_parquet("from_pandas.parquet", skip=2)["size"].cat.categories.tolist())   # ['b']
    print(other["n"].dtype)                            # Int64
```

Its categories are the distinct values of the rows read, in the order
they first appear, and it is not ordered: the file does not say which
categories the writer had, or in what order. Reading another window of
rows can give other categories; reading every row gives all that are
used. A file `write_parquet` wrote has every category, in order,
whatever rows are read.

DECIMAL columns of up to 15 digits read as `float64`, the nearest double
to each value; longer ones as `decimal.Decimal` objects, every digit
kept. Unsigned integers, INT96 and TIME are read too (see the table
below), and so are the files' other types: text annotated ENUM or JSON
as text, UUID and fixed-length bytes as `bytes`.

What is not read, each an error that names the column and its type:
FLOAT16, INTERVAL, the Hadoop framing of LZ4, LZO, and encrypted files.
Nested columns (lists, maps, structs) raise an error unless `columns`
leaves them out or `nested="skip"` is given; `read_meta` lists them
with role `"nested"`. Datasets of many files, Hive partitions and
filters on values are not part of `dta_parser`: read each file, or use
pyarrow's `dataset` or DuckDB. pandas' `PANDAS_ATTRS` and the `pandas`
metadata entry are not read, so an index pandas stored is an ordinary
column ([below](#the-index-and-parquet-files)).

### What each Parquet type becomes in Python

| Parquet | pandas |
|---|---|
| INT32: INT(8), INT(16) or none | `int8`, `int16`, `int32` (Stata's byte, int and long); where the rows read hold a null, `float32` (8 and 16 bits) or `float64`, with `NaN`, as `read_dta` gives `.` |
| INT64 | `int64`; with nulls `Int64` |
| unsigned 8 and 16 bits | `uint8`, `uint16`; with nulls `float32` |
| unsigned 32 and 64 bits | `uint32`, `uint64`; with nulls `float64` (32 bits) or `UInt64` (64 bits) |
| FLOAT, DOUBLE | `float32`, `float64`; null is `NaN` |
| DOUBLE holding `.a` to `.z` (tagged NaNs) in the rows read | `StataArray` of the storage type the file records; any other NaN is `.` |
| DOUBLE written wider for `.a` to `.z`, none in the rows read | the storage type's dtype, as `read_dta` gives it |
| DECIMAL, precision 15 or less | `float64`, the nearest double to each value |
| DECIMAL, precision above 15 | `object` of `decimal.Decimal`, every digit kept; `None` for null |
| BOOLEAN | `bool`; with nulls `boolean` |
| DATE | `datetime64[s]` |
| TIMESTAMP (milli-, micro-, nanoseconds) | `datetime64` in the file's unit (`[s]` where `write_parquet` wrote `datetime64[s]`), tz-aware where adjusted to UTC: in the zone the profile records, else the one in `ARROW:schema`, else UTC |
| INT96 | `datetime64[ns]` |
| TIME (milli-, micro-, nanoseconds) | `timedelta64` in the file's unit |
| STRING, ENUM, JSON | pandas' default text dtype (`str` on pandas 3, `object` before); null is `NaN` |
| BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY without a text type, UUID | `object` of `bytes`; `None` for null |
| a category `write_parquet` wrote | `category`, every category in order, ordered if it was |
| a dictionary of text in `ARROW:schema`, with no categories in the profile (pandas `category`, polars `Categorical`, an arrow factor) | `category`, unordered; categories are the distinct values of the rows read, in order of first appearance |
| a dictionary of another type in `ARROW:schema` | its values' type, by the rows above |
| a DOUBLE R wrote for a date or time holding `.a` to `.z` | Stata's days or milliseconds since 1960 with a `%td` or `%tc` format, as `read_dta` gives such a column |
| FLOAT16, INTERVAL | not read: an error naming the column and type |

Every conversion is exact: no value is rounded. A timestamp whose value
is numpy's `NaT` (-2^63) is an error naming the column and row.

**What a round trip does not keep.** A frame `read_dta` gave comes back
equal, values, dtypes and `attrs["dta"]` alike, except: `attrs` has no
`release`, `byte_order` or `encoding` (they describe a `.dta` file, not
the data); a string column's storage type is `"str"`, its strN width or
strL being chosen again when it is written to `.dta`; and a `%td` or
`%tc` column's storage type is `"long"` or `"double"`, whatever the
`.dta` file used, since a Parquet DATE or TIMESTAMP has no Stata
storage type. A column mixing text and binary values comes back as
`bytes` throughout.

### The index and Parquet files

`write_parquet` writes columns only, as `write_dta` does. When the
index is anything but a default `RangeIndex` (named, or of another
kind), it warns once, naming the index and saying to call
`df.reset_index()` first to keep it; `read_parquet` always returns a
default `RangeIndex`:

```python
keyed = df.set_index("id")
import warnings
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("always")
    dp.write_parquet(keyed, "keyed.parquet")
print(caught[0].message)
# write_parquet writes columns only, not the index 'id'; call df.reset_index() first to keep it
dp.write_parquet(keyed.reset_index(), "keyed.parquet")
print(dp.read_parquet("keyed.parquet").set_index("id").index.tolist())   # [1, 2, 3, 4, 5, 6]
```

A file pandas wrote with an index (`df.to_parquet` stores any index but
a default `RangeIndex` as a column) reads with that index as an
ordinary column, named after the index or `__index_level_0__`; restore
it with `set_index`, as above.

### Coming from pyarrow, pandas or polars

| pyarrow | pandas | polars | dta_parser | what changes |
|---|---|---|---|---|
| `pq.read_table(p).to_pandas()` | `pd.read_parquet(p)` | `pl.read_parquet(p).to_pandas()` | `dp.read_parquet(p)` | labels, `.a` to `.z`, formats and notes kept; `read_dta`'s dtypes; decoded straight into pandas, with no Arrow table in between |
| `pq.read_table(p, columns=["a", "b"])` | `pd.read_parquet(p, columns=["a", "b"])` | `pl.read_parquet(p, columns=["a", 1])` | `dp.read_parquet(p, columns=["a", 1])` | names or positions; an unknown name is a `KeyError` listing the file's columns |
| `pq.ParquetFile(p).read_row_groups([...])`, `.iter_batches()`, or `read_table(p).slice(100, 50)` | none; read, then `.iloc[100:150]` | `pl.scan_parquet(p).slice(100, 50).collect()` | `dp.read_parquet(p, skip=100, n_max=50)` | only the pages that hold the rows are read |
| `pq.read_metadata(p)`, `pq.read_schema(p)` | none | `pl.read_parquet_schema(p)`, `pl.read_parquet_metadata(p)` | `dp.read_meta(p)` | one dictionary: rows, row groups, codecs, labels, and the pandas dtype of each column |
| `df.to_parquet(p)`, or `pq.write_table(pa.Table.from_pandas(df), p)` (snappy) | `df.to_parquet(p)` (snappy) | `pl.from_pandas(df).write_parquet(p)` (zstd) | `dp.write_parquet(df, p)` (snappy) | labels, `StataArray` columns and their letters written; `attrs` with missing-value keys, which `to_parquet` cannot write, is fine |
| `df.to_parquet(None)` | `df.to_parquet(None)` | `write_parquet(io.BytesIO())` | `dp.write_parquet(df)` | returns `bytes` |
| `compression="zstd", compression_level=3` | the same | the same | the same | |
| `row_group_size=n` | the same (passed to pyarrow) | the same | the same | |
| `df.to_parquet(p, index=True)` | the same | (no index) | `dp.write_parquet(df.reset_index(), p)` | the index is never written; a warning says so |
| `df.attrs` in `PANDAS_ATTRS` (JSON, keys become text) | the same | `write_parquet(metadata={...})` | `attrs["dta"]` in the `dta` entry | value label codes stay numbers and `.a` ... `.z`; R's datakit reads it too |
| `read_table(p, use_threads=False)` | | `POLARS_MAX_THREADS=1` | `DTA_THREADS=1` | |
| `to_pandas(types_mapper=...)`, `dtype_backend=` | `dtype_backend="pyarrow"` | `to_pandas(use_pyarrow_extension_array=True)` | none | the dtypes are fixed, by the table above |
| `pq.read_table(p)` (an Arrow `Table`) | | `pl.read_parquet(p)` (a polars `DataFrame`) | none | `dta_parser` returns pandas only; read with pyarrow or polars for those |

What changes in the values: integer columns with nulls are `float32`
or `float64`, as `read_dta` gives them (pyarrow gives `float64`, polars
and pandas' nullable backends `Int*`); dates are `datetime64[s]` (pyarrow
gives `datetime.date` objects); timestamps keep their unit (pyarrow
turns seconds into milliseconds); `.a` to `.z` are kept (the others
give `NaN` or drop them).

## Threads

Reading and writing large files uses up to three threads: workers decode the rows and fill numeric columns, released from the GIL, while the calling thread makes the strings. On x86, where processors pair their hardware threads, the most is half the processor count, up to three. Reads that need a strL column, small reads and writes (under 16 MB of selected data) and every read on Windows use one thread. In our measurements the threads together used at most 15% more CPU time than one thread doing the same work.

Parquet reads and writes of 16 MB or more use two threads or more, which decode or compress column chunks with the GIL released while the calling thread gathers the text. Survey files use two: a third added less than half a thread's worth of speed. Larger work uses more: a read one thread per 176 MiB of values, up to eight, and a write one per 256 MiB, up to six. The rule and the numbers are in [docs/parquet.md](parquet.md#defaults-and-the-measurements-behind-them).

Set the `DTA_THREADS` environment variable to `1` to use one thread, or to another number to change the most; it is read at each call. While `write_dta` or `write_parquet` runs, nothing may change the DataFrame's arrays, from Python or from another thread.

## Troubleshooting

**`ImportError: cannot import name '_native'`.** Python is importing the
source directory instead of the installed package; this happens when
you run Python from inside `dta-parser/python`. Change directory.

**`pip install` fails with "cargo not found" or a Rust error.** Install
Rust from [rustup.rs](https://rustup.rs) and open a new shell.

**`pip install` cannot reach PyPI.** pip downloads maturin to build the
extension. Without network access, install maturin some other way and
build without isolation:
`pip install --no-build-isolation ./dta-parser/python`.

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

**`read_parquet` raises "the file has nested columns, which are not
read".** The file has a list, map or struct column. Pass `columns=` with
the flat columns, or `nested="skip"`; for the nested data, use pyarrow
or polars.

**`write_parquet` warns "writes columns only, not the index".** The
frame has an index other than a default `RangeIndex`. Call
`df.reset_index()` first to keep it as a column, or
`df.reset_index(drop=True)` to drop it and silence the warning.

**`write_parquet` raises "row 2 is not midnight, but the column's
format '%td' says it is a date".** A `datetime64` column whose `attrs`
format is a date holds a time of day. Remove the format
(`del df.attrs["dta"]["columns"]["x"]["format"]`) to write it as a
timestamp.

**A warning "dropped ... from the dta profile".** The file's `dta`
entry was damaged or edited by hand. The values are read; that entry
is not. [docs/parquet.md](parquet.md#errors-and-warnings) lists every
error and warning.

## API reference

The docstrings (`help(dp.read_dta)`) are the reference. Exports:

- `read_dta(path, columns=None, skip=0, n_max=None, encoding=None, dates=True)`:
  read a file into a DataFrame.
- `read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None, commented_formats=True)`:
  read fixed-width text through its SAS setup file, given as one path
  or a list of paths (see
  [Fixed-width files](#fixed-width-files-with-a-sas-setup-file)).
- `FixedWidthWarning`: the warning `read_fixed_width` gives for
  statements it skipped.
- `read_meta(source, encoding=None)`: the metadata dictionary and `nobs`,
  without data, of a `.dta` or Parquet file.
- `read_parquet(source, columns=None, skip=0, n_max=None, nested="error")`:
  read a Parquet file into a DataFrame (see [Parquet files](#parquet-files)).
- `write_parquet(df, path=None, *, label=None, variable_labels=None, compression="snappy", compression_level=None, row_group_size=None, missing_letters=True)`:
  write a DataFrame as Parquet; returns `bytes` without a path.
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
