# dta_parser for Python

Reads and writes Stata `.dta` files with pandas, on the same Rust core as
the R and npm packages. It reads releases 104 to 119 in either byte
order, writes release 118, and keeps Stata's missing values `.a` to `.z`.

## Install from source

You need Python 3.10 or later and a Rust toolchain
([rustup](https://rustup.rs)). From a checkout of this repository:

    pip install ./python

That builds the extension with maturin. For development, install it in
place and run the tests:

    pip install maturin pytest pyreadstat
    cd python && maturin develop --release && pytest

## Reading

```python
import dta_parser as dp

df = dp.read_dta("survey.dta")
df = dp.read_dta("survey.dta", columns=["id", "age"], skip=1000, n_max=500)
meta = dp.read_meta("survey.dta")   # no data; meta["nobs"] is the row count
```

`columns` takes names or 0-based indices, read in the order given.
`encoding` decodes text in files older than release 118
(`"windows-1252"` by default, `"latin1"` or `"utf-8"`).

What each column becomes:

- numbers with no missing value keep their storage width: byte `int8`,
  int `int16`, long `int32`, float `float32`, double `float64`;
- numbers whose only missing value is `.` become `float32` (byte, int,
  float) or `float64` (long, double), with `.` as NaN;
- numbers with any of `.a` to `.z` become a `StataArray` (dtype
  `stata[byte]` ... `stata[double]`), which keeps each row's missing code;
- `%td` dates become `datetime64[s]` and `%tc` times `datetime64[ms]`,
  with `.` as NaT, unless you pass `dates=False`. A column stays numbers if
  any value is not a whole day (or millisecond) or is `.a` to `.z`. `%tC`
  (which counts leap seconds) always stays numbers;
- text is pandas' default string dtype (`str` on pandas 3, `object`
  before); a strL column with binary values is `object`, holding `bytes`
  for those.

Labels, display formats, storage types, value labels, notes,
characteristics and the sort order are in `df.attrs["dta"]`:

```python
info = df.attrs["dta"]
info["label"]                       # the data label
info["columns"]["age"]              # {"storage", "format", "label", "value_labels"}
info["value_labels"]["yesno"]       # {1: "Yes", 0: "No", dp.missing.d: "Don't know"}
info["notes"], info["characteristics"], info["sort_order"]
```

## Missing values

`.` is NaN, as elsewhere in pandas. `.a` to `.z` are `dp.missing.a` to
`dp.missing.z`:

```python
s = df["income"]                    # a StataArray column
s[3]                                # 1520.0, nan, or e.g. dp.missing.r
s.array.codes                       # uint8: 0 not missing, 1 ., 2 to 27 .a to .z
df.loc[s == dp.missing.r, "income"] = dp.missing.d
```

These keep the codes: boolean and positional selection, `loc`, `iloc`,
`sort_values`, `concat` and `merge` of `StataArray` columns, `reindex`
(new rows are `.`), `copy`, and `groupby` on the column, where `.`, `.a`,
... are separate groups, as in Stata. Arithmetic and anything else may
turn `.a` to `.z` into NaN.

`sort_values` on one `StataArray` column puts missing values after every
number, in the order `.`, `.a`, ..., `.z`. To sort by several columns
that way, pass `key=dp.stata_keys`. `dp.stata_key(value)` and
`dp.stata_keys(column)` give floats that sort and compare as Stata does.

## Writing

```python
dp.write_dta(df, "out.dta")
dp.write_dta(df, "out.dta", label="My data", variable_labels={"age": "Age in years"})
```

A frame from `read_dta` writes back with its values, missing codes,
storage types, labels, value labels, formats, notes, characteristics and
sort order. pandas keeps `attrs` through most operations but drops them
in some (`merge`, `concat` of frames with different `attrs`), and a
renamed column loses its entry; the writer uses what is there and
chooses the rest from the dtypes:

| pandas | Stata |
|---|---|
| bool | byte |
| integers | the smallest of byte, int, long that holds every value; else double (an error beyond ±2^53) |
| float32, float64 | float, double; NaN is `.` |
| nullable integers, booleans, floats | as above, NA is `.` |
| `StataArray` | its storage and codes |
| category | its codes as long, its categories as value labels |
| datetime64 | `%td` (long) if every value is midnight, else `%tc` (double, milliseconds); NaT is `.` |
| text | strN up to 2045 bytes, else strL; None, NaN and pd.NA become "" |
| bytes | binary strL |

Anything else is an error naming the column, as is a column name Stata
cannot hold (1 to 32 letters, digits or `_`, not starting with a digit,
not a reserved word). The index is not written.
