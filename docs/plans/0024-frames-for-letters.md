# Plan: frames where `.a` to `.z` compare as missing

Status: approved at Gate 1 (revision 5; Claude Sonnet and GPT Sol;
record in `docs/judging/frames-for-letters/`).

## Problem

On 2026-11-09 the user asked for polars support in R's datakit. The
research (`docs/research/polars-2.md`) and the probes after it showed
that keeping `.a` to `.z` in a column is only half of the job. The
other half is how the frame library treats them once they are there.

Python's datakit holds them as tagged NaNs in `Float64` columns
(ADR 0036). TypeScript does too (ADR 0037), and so would polars or
arrow in R. A columnar engine treats a NaN as a value, not as missing.
For the rows `1, 5000, .a, .b, .`:

| expression | polars 2.1 | arrow 26 | R double (tibble) |
|---|---|---|---|
| `x == 1` | T F F F null | T F F F NA | T F NA NA NA |
| `x != 1` | F T **T T** null | F T **T T** NA | F T NA NA NA |
| `x > 3000` | F T **T T** null | F T F F NA | F T NA NA NA |
| `x == .a` | F F T **T** null | F F **F** F NA | NA everywhere |
| rows `filter(x != 1)` keeps | 3 | 3 | 1 |
| `group_by(x)`, `unique`, join keys | `.a` and `.b` merged | kept apart | `.`, `.a` and `.b` merged |

Polars treats every NaN as equal to every other NaN and greater than
any number. Arrow follows IEEE 754, so a NaN compares false with
everything. Only a null compares as null, and in either engine a null
cannot carry a letter: polars writes zeros under nulls in sort, gather
and join (ADR 0036), and arrow did so in `arrange` and `Take`. R is the
only one of the three where one value holds the letter and still
behaves as missing, because R's `NA` is itself a NaN that R treats as
missing in every comparison.

The user decided, on 2026-11-09:

1. **R's datakit stays on tibbles**, with no polars or arrow frames. "If
   someone wants high performance then they need to write idiomatic R."
2. **R's grouping gets a helper, not a class.** R's `unique()`,
   `duplicated()`, `match()`, `%in%`, `table()`, `factor()`, `split()`,
   vctrs' `vec_unique()`, `vec_group_id()` and `vec_in()`, and dplyr's
   `group_by()`, `distinct()`, `count()` and joins all put `.` and
   `.a` to `.z` in one group. A class whose vctrs proxies tell them
   apart (as dtatools' `dta_num` has) slowed grouping, sorting and
   `distinct` on every later call. The user asked instead for a
   function, `datakit_by()`, to use in tidy verbs when the letters
   should be told apart.
3. **Polars was the wrong choice for Python's datakit.** Its comparisons
   and grouping get the letters wrong, as above.

## Proposal

Four stages, each its own pull request, merged in order.

### Stage 1: record the decisions (docs only)

- **ADR 0038, R's datakit stays on tibbles.** States decision 1, the
  comparison table above, and the options considered: polars through
  nanoarrow, arrow, a proxy class, and the helper. It keeps the
  benchmark: on 10 million rows with 1,000 values, proxies made
  `group_by()` 1.4 times, `arrange()` 1.6 times and `distinct()` 2.8
  times slower, and `filter(x > 500)` five times slower through
  vctrs' comparison; `group_by()` by a column and its letter column took
  256 ms against 136 ms for the column alone.
- **`docs/research/polars-2.md`** gains a section for each probe made
  after it was written, with the probe code and versions (the scripts
  now in `docs/judging/frames-for-letters/probes/` move there):
  - arrow 26 with letters as non-null tagged NaNs: `unique`,
    `value_counts`, `group_by`, `distinct`, joins and `is_in` kept `.a`
    and `.b` apart. `==` was false on every letter. A letter that had
    been through arithmetic (quiet bit set) formed a separate group
    from one that had not. Arrow `arrange` and `Take` zeroed the bits
    under nulls.
  - The comparison table above, for polars, arrow and R.
  - R: which base, vctrs and dplyr functions merge the letters, and
    which keep them. `collect()` keeps them bit for bit.
  - The proxy-class benchmark and the `datakit_by()` shapes.
  - pandas 3.1.1: plain `float64` with tagged NaNs compares as arrow
    does. A nullable `Float64` compares as R does (`<NA>`), but pandas
    treats the bits under its mask as free space: `astype`,
    `groupby().transform()`, `apply()`, `fillna` and `where` lose the
    letters, and `cumsum()` overwrote the letters in its **input**
    column with zeros. A nullable `Float64` cannot keep a NaN value
    apart from a null either: `x * 2` turned an unmasked NaN into
    `<NA>`.
- **`docs/r.md`**, in the section on missing values: the full list of R
  functions that put `.` and `.a` to `.z` in one group, replacing the
  single mention of `count()`, with `na_tag()` and `datakit_by()`
  (stage 2) as the ways to tell them apart.

### Stage 2: `datakit_by()` in R's datakit

```r
d |> group_by(datakit_by(x)) |> summarise(n = n(), .groups = "drop")
d |> count(datakit_by(x, y))
d |> distinct(datakit_by(x))
d |> mutate(datakit_by(x)) |> left_join(lookup, by = c("x", "x_letter"))
```

- **Signature.** `datakit_by(..., .suffix = "_letter")`. The arguments
  are data-masking, as `group_by()`'s are, and are named the way
  `group_by()` names them: a given name (`datakit_by(inc = income)`),
  else `rlang::as_label()` of the expression, so a bare column keeps
  its name, `{{ var }}` forwards its column's name, and `.data$x` and
  `.data[["x"]]` give `x`. `.suffix` must be one non-empty string, not
  `NA`.
- **Result.** A tibble with, for each argument in order, the column
  under its name and, right after each column of a type that can hold a
  letter, a character column `<name><.suffix>` holding
  `dtaparser::na_tag()` of it: `"a"` to `"z"` for a letter, `NA`
  otherwise. The types that can hold a letter are listed, not inferred
  from `typeof()`: a double with no class, `dtaparser_labelled` and
  `haven_labelled` over doubles, `Date` and `POSIXct`. Every other type
  (`integer64`, `difftime`, integers, text, factors) gets no letter
  column. The letter column is added even when no row holds a letter,
  so a script gives the same columns for every file.
- **Names.** Two outputs of one call with the same name (for example
  `datakit_by(x, x_letter = y)`) are an error naming them. An existing
  column of the frame with the name of an output is replaced, as dplyr
  replaces a column for any named result of `group_by()` or `mutate()`;
  the help page says so.
- **Verbs.** dplyr splices an unnamed tibble into columns, so the helper
  works in `group_by()`, `count()`, `distinct()` and `mutate()`. In
  `summarise()`'s output the original column keeps its letters, since
  dplyr keeps each group's first row's value. `summarise()` drops the
  last grouping column by default, which is the letter column, so the
  result is grouped by `x` alone and a later grouped step merges the
  letters again: the docs and examples use `.groups = "drop"`, and say
  why. `.by = datakit_by(x)` and `join_by()` take column names, not
  expressions; the docs show dplyr's error for `.by` and the way round
  it (`mutate()` first, then name both columns). A join must keep
  dplyr's default `na_matches = "na"`: with `"never"`, every row whose
  letter column is `NA` (every number) fails to match.
- **Dependencies.** None new: `datakit_by()` builds a tibble. The tests
  use dplyr, already in `Suggests`, raised to `dplyr (>= 1.1.0)`, and
  skip without it.
- **Tests.** Grouping, `count()`, `distinct()` and a join keep `.`, `.a`
  and `.b` apart; `summarise()` keeps the letters in `x`, and its
  `group_vars()` with and without `.groups = "drop"`; types other than
  those listed get no letter column; `.suffix` and its errors;
  duplicate output names; an existing column replaced; `{{ var }}`,
  `.data$x` and `.data[[v]]` names; a labelled double keeps its labels.
- **Docs.** `docs/r.md` and the function's help page; `NEWS`; datakit's
  minor version.

### Stage 3: `DtaArray` compares as missing, everywhere in Python

Python's `dta_parser.DtaArray` (ADR 0015) already keeps `.` and `.a` to
`.z` in a code per row beside the values, and pandas' `groupby`,
`unique` and joins already keep the codes apart (its factorize key).
This stage makes it compare and compute as R's doubles do, and makes
it the type of every numeric column that holds a missing value, so
that a script's filters and groups do not depend on which rows or
which file it read. Because such columns become common, it also makes
`DtaArray` work in the pandas operations a numeric column meets. ADR
0039 records it and amends ADR 0015.

**Which columns are a `DtaArray`.** dta_parser's `read_dta` today
reads a column with only `.` missing as `float32` or `float64` with
NaN, where `x != 1` is true on the `.` rows and `groupby` drops them,
and a column with any letter as a `DtaArray`. From this stage, a
numeric column (`byte`, `int`, `long`, `float`, `double`) holding any
missing value in the rows read is a `DtaArray` of its storage type; a
column with none keeps its numpy type, where no comparison or group
meets a missing value. `_read.py` changes this rule and its docstring;
`write_dta` already writes `DtaArray` columns. A `DtaArray` stores
float64 values and a byte of code per row, so a `byte` column with a
missing value takes 9 bytes a row instead of 4 as `float32`.

**Comparisons** (`==`, `!=`, `<`, `<=`, `>`, `>=`, in either operand
order) return a pandas `BooleanArray`. They work in two steps.

*The other operand becomes values and codes:*

| other operand | becomes |
|---|---|
| a number | that number |
| NaN, `None`, `pd.NA` | `.` (code 1) |
| a `MissingValue` (`missing.a` ... `missing.z`) | that letter, *named* |
| a list, numpy array or pandas array (nullable ones included) | element by element, by the rows above; a nullable array's `<NA>` is `.` |
| another `DtaArray`, or a Series of one | its values and codes; its letters are not *named* |
| text, or a list or array holding text | text, element by element (row rule 2) |

*Then, row by row:*

1. Where the other side holds a named letter: `==` is true when this
   side holds the same letter, false otherwise; `!=` is its negation;
   an ordering comparison is `<NA>`.
2. Otherwise, where either side is missing (`.` or a letter): `<NA>`.
   Where the other side holds text and this side a number: `==` is
   false and `!=` true, as pandas' nullable `Int64` gives
   (`Series([1, None], dtype="Int64") == "x"` is `[False, <NA>]`), and
   an ordering comparison raises `TypeError`.
3. Otherwise: the comparison of the two numbers.

So `x == missing.a` is true exactly on the `.a` rows, the way a script
tests for one letter (as `is_tagged_na(x, "a")` does in R). `x == np.nan`
and `x != 1` are `<NA>` on every missing row, as R's `x == NA` and
`x != 1` are. `x == y` for two `DtaArray` columns is `<NA>` on a row
where both hold `.a`, as in R. pandas drops `<NA>` rows in `df[mask]`,
`df.loc[mask]` and `query`, as dplyr's `filter()` does, and refuses
`<NA>` in `np.where` and `bool()`. That was checked on pandas 3.0.5 and
3.1.1; the tests check it on pandas 2.2 as well.

`MissingValue`'s comparison methods return `NotImplemented` when the
other operand is a list, a numpy or pandas array, a `Series` or an
`Index`, so Python hands the comparison to the array: today
`missing.a == s` is a single `False` (`__eq__` is `self is other`)
and `missing.a < s` raises `TypeError`. Between two scalars, a
`MissingValue` compares as now.

**Arithmetic** (`+`, `-`, `*`, `/`, `//`, `%`, `**`, in either operand
order, and unary `-`, `+` and `abs()`) returns a `DtaArray` of storage
`double` when either operand is one. The other operand becomes values
and codes as above (text raises `TypeError`). A row missing on the left
keeps its code; else one missing on the right keeps the right's code;
whatever the numbers would give (so `x ** 0` is missing where `x` is,
unlike R's `NA ^ 0`, which is 1). A NaN that the operation itself makes
(`0 / 0`, `inf - inf`) is `.`. Today these return `float64`, with every
letter a plain NaN.

**numpy functions.** pandas' `ExtensionArray.__array_ufunc__`, which
`DtaArray` inherits, sends a ufunc that has an operator (`np.add`,
`np.multiply`, `np.abs`, `np.negative`, the comparison ufuncs) to that
operator, so those follow the rules above. Other ufuncs (`np.log`,
`np.sqrt`, `np.exp`) go through `__array__`: `float64`, every missing
value NaN. `Series.map` and `apply` with a Python function see a
`MissingValue` for a letter and NaN for `.`. The tests pin each of
these on both pandas versions, and the docs list them.

**pandas operations.** `DtaArray` gains what a numeric column needs,
each tested, including between a `DtaArray` and a numpy column:

| operation | rule |
|---|---|
| `pd.concat` (rows) | `DtaDtype._get_common_dtype` gives a `DtaDtype` when every other dtype is a `DtaDtype` or one whose whole range a double holds exactly, numpy or nullable: bool → `byte`; int8 and uint8 → `int`; int16 and uint16 → `long`; int32, uint32 and float64 → `double`; float32 → `float`. With int64 or uint64 it gives `None`, so pandas makes the result `object` rather than round values above 2^53; the docs say to convert such a column first. Today any non-`DtaDtype` gives `None`. pandas infers `object` for `pd.Series([1, missing.a, None])` without asking the hook, so the docs build such a Series with `dtype="dta[double]"` |
| `merge` on a `DtaArray` key and a key of another dtype | not supported: pandas does not apply the common dtype to merge keys (a mixed-key merge raised `KeyError` with the rule above, on pandas 3.0.5). The docs say to give both keys one dtype first, `astype("dta[double]")`; a merge of two `DtaArray` keys matches letters to the same letter, `.` to `.`, and leaves unmatched rows unmatched |
| `to_numpy()`, `__array__`, `astype(float)` | float64, NaN for every missing value, as now. `DataFrame.to_numpy()` of a frame with a `DtaArray` column stays `object`, as pandas makes it for any extension type; the docs say `df.to_numpy(dtype=float)` |
| `cumsum`, `cumprod`, `cummin`, `cummax` (`_accumulate`) | `skipna=True`: missing rows keep their codes and are skipped; `skipna=False`: from the first missing row on, that row's code. Today these raise `NotImplementedError` |
| `rolling`, `expanding`, `ewm` | on float64 values with NaN for missing, through `to_numpy`; a `float64` result. Today they give all NaN |
| `quantile`, `describe`, `corr`, `cov` | on the numbers, missing values skipped |
| `fillna(v)`, `where`, `mask` | a `DtaArray`; `v` and the other values may be numbers or `MissingValue`s |
| `clip`, `round` | a `DtaArray`, missing rows keep their codes |
| `isin(values)` | true where the value is among `values`; a `MissingValue` in `values` matches its letter; `<NA>`-free, as pandas' `isin` |

**Release.** dta_parser 0.4.0. `docs/python.md` (Missing values, Read
a file) and `docs/migration.md` say that a column with only `.`
missing is now a `DtaArray`, that comparisons give `<NA>`, and what that
costs in memory.

**Tests** (`python/tests/test_array.py`, `test_read.py`): each
comparison operator in both orders with each operand kind and each row
rule, including `missing.a == s`, `missing.a < s`, `x == np.nan`, text
operands and `DtaArray == DtaArray` on shared letters; filtering,
`query` and `loc` with the result; `np.where` and `bool()` raising;
arithmetic codes (left first, right second, `.` for a NaN the operation
makes, `x ** 0`), unary operators and both operand orders; the ufuncs,
`map` and `apply`; each row of the operations table; `read_dta` giving
a `DtaArray` for a `.`-only column and the numpy type for a column
without missing values, in a window of each, and `pd.concat` of the two
windows giving a `DtaArray`; `pd.concat` with each numpy and nullable
dtype of the common-dtype row, and with int64 and uint64 giving
`object` in which `2**53` and `2**53 + 1` stay apart; text operands
with a missing row (`<NA>`); a merge of two `DtaArray` keys (letters,
`.`, unmatched rows); a frame read, filtered, sorted, merged,
grouped and written keeps every code. CI runs the suite on pandas 2.2
and on the latest pandas.

### Stage 4: Python's datakit returns pandas

Python's datakit returns pandas frames instead of polars ones. Its API
otherwise stays as it is: the same functions (`read_parquet`,
`read_parquet_info`, `save_parquet`, `read_dta`, `save_dta`,
`read_fixed_width`, `tagged_na`, `na_tag`, `is_tagged_na`), the same
arguments, and `df, meta = read_parquet(path)` with the same `Meta`.
`read_fixed_width` still converts to a `.dta` file and reads it with
`read_dta`. `ParquetInfo.row_groups` and `.columns` become pandas
frames, and `Meta`'s comparison and copy helpers (`_same`, `_deep`)
compare and copy pandas frames and Series in place of polars ones. The
files datakit writes do not change.

**Columns read.** For every type plan 0018's Exactness table lists,
its "Python (pandas)" column, with these rules over it:

| column | pandas |
|---|---|
| INT32 (8, 16, 32 bits), FLOAT, DOUBLE, and `.dta` numbers, holding any missing value (null, NaN, `.`, a letter) in the rows read | `DtaArray` of the storage type (`dta[byte]` ... `dta[double]`; `int` for INT(16), `long` for INT32), the rule of stage 3; the dtype replaces `Meta._storage` |
| the same with no missing value; and INT64, unsigned and BOOLEAN with no nulls | numpy int8, int16, int32, float32, float64; int64, uint8 ... uint64, bool |
| INT64, unsigned 8 to 64 bits, BOOLEAN, with nulls | nullable `Int64`, `UInt8` ... `UInt64`, `boolean`; these cannot hold a letter |
| a NaN value in a numeric column | `.`, as a null is: pandas' nullable types do not keep a NaN apart from a null (stage 1's probe), and `.dta` has no NaN |
| a categorical without letters | `category`, ordered kept, unused levels kept |
| a categorical holding letters | `DtaArray` of level numbers 1 to k, labelled by its value label set, as R and Julia read it |
| DATE | `datetime64[s]`; `meta` gives it the format `%td` when the file names none |
| TIMESTAMP, INT96 | `datetime64` in the file's unit (INT96: `ns`), tz-aware when adjusted to UTC, in the zone the file names |
| TIME | `timedelta64[ns]`: the native read gives every TIME in nanoseconds (`python/src/arrow/read.rs`), which corrects plan 0018's "in the file's unit" for datakit |
| a date or timestamp holding letters | `DtaArray` of Stata's days or milliseconds since 1960, format `%td` or `%tc` (ADR 0036) |
| a labelled column with `factors=True` | `category`; letters become NaN, with the warning datakit gives now |
| DECIMAL | `float64` up to 15 digits; above, `decimal.Decimal` objects (plan 0018) |

`letters=False` reads every letter as `.`. Text is pandas' default text
dtype (`str` from pandas 3, `object` before). Dates, timestamps and
categoricals that hold letters change type with the rows read, since no
pandas date or categorical type can hold a letter; the docs say so
beside the numeric rule.

**Missing values in the API.**

- `tagged_na(".a")` (or `"a"`) returns `dta_parser.missing.a`, a
  `MissingValue`, in place of a tagged float.
- `na_tag(x)` takes a Series or array and returns a Series of `LETTERS`,
  now a pandas `CategoricalDtype` of `".a"` to `".z"`. It reads the
  codes of a `DtaArray` and the bits of tagged NaNs in a plain float
  array, and gives NaN for numbers and `.` and for every other type.
- `is_tagged_na(x, letter=None)` returns a numpy bool array on the same
  sources.
- The polars `Expr` forms go.
- **Setting a letter.** `df.loc[rows, "x"] = dk.tagged_na(".r")` and
  `df["x"].mask(cond, dk.tagged_na(".r"))` work on a `DtaArray`. On a
  column of a numpy type, pandas 3 refuses a `MissingValue` with
  `TypeError`, and pandas 2.2 turns the column into `object` with a
  warning. The docs say to convert first,
  `df["x"] = df["x"].astype("dta[double]")`, and `save_parquet` and
  `save_dta` refuse an `object` column holding a `MissingValue`, with a
  message that says so.
- **Writing.** A tagged NaN in a plain float column is written as its
  letter, as datakit writes one today. pandas operations may turn it
  into a plain NaN, so the docs name `DtaArray` as the way to keep a
  letter.
- **Tests.** Construction, assignment (into a `DtaArray`, and the error
  for a numpy column on each pandas version), `na_tag`, `is_tagged_na`
  and a save and read back of `.a` made through these functions.

**Columns written** (`save_parquet` and `save_dta`):

| pandas | written as |
|---|---|
| numpy ints, floats, bool | as the polars type of the same name is written today |
| nullable `Int*`, `UInt*`, `Float*`, `boolean` | the same, `<NA>` written as `.` |
| plain `float32`/`float64` | numbers; a tagged NaN as its letter, any other NaN as `.` |
| `DtaArray` | its storage type with its codes; when a value no longer fits that type exactly, the next type that holds every value, else double (as `stored()` and dta_parser's `_choose` do today) |
| `category` | a categorical with the `dtaparser_categorical` marker in `.dta` (plan 0023), ordered kept |
| `str`, or `object` holding only text and missing values | STRING / `str` |
| `object` of `bytes` | BYTE_ARRAY in Parquet; a binary strL in `.dta`, as datakit writes a polars `Binary` today (`dta.rs`), so a binary strL read keeps round-tripping |
| `object` of `decimal.Decimal` | an error naming the column and suggesting float or text, as datakit refuses a polars `Decimal` today (`write.rs`) |
| `datetime64[unit]`, naive | TIMESTAMP in that unit, not adjusted to UTC; `%td` in `meta` with every value at midnight: DATE; `%tc` in `.dta` as today |
| `datetime64[unit, tz]` | TIMESTAMP adjusted to UTC, its zone in the profile |
| `timedelta64` (Parquet only) | TIME(NANOS) when every value is in [0, 24 h), otherwise an error naming the column and row; a TIME(MILLIS) or TIME(MICROS) column read and saved comes back as TIME(NANOS), and the docs say so |
| anything else (mixed `object`, complex, interval, period) | an error naming the column and its dtype |

**Native code.** datakit keeps calling the same native reads and
writes, so every rule in them (profiles, categoricals with letters,
markers, windows, time zones) stays in one place. The final step
changes:

- **One table per read.** Each read returns its own table; nothing in
  it is shared with another read or cached.
- **Without a copy.** A numeric column with no missing value, and a
  timestamp or time column with no null, are handed to numpy as they
  are. Each is a native
  object holding the table's `Arc`, with `__array_interface__`
  (version 3, writable). numpy keeps that object as the array's `base`,
  so the buffer lives as long as any array or slice of it. Writing to
  it is safe because no other read holds the buffer and the native side
  never reads a table's buffers after handing them out. The pointer
  given is the array's own start, offset included, for windowed reads.
  pandas copies numpy arrays into a new frame by default
  (`pd.DataFrame({"a": a})` did not share memory on pandas 3.1.1), so
  Series and frames are built with `copy=False` where that shares
  memory without a warning, and otherwise with whatever construction
  does on that pandas version (a judge saw `Pandas4Warning` from one
  pandas 3 constructor; another saw none from `pd.DataFrame(...,
  copy=False)` on 3.0.5); the `np.shares_memory` test decides on each
  version CI runs, and no warning is left to the user. A tz-aware
  timestamp is built from the int64 view with `astype` to UTC, which
  shares memory, then `tz_convert` to the file's zone; if that last
  step copies on a pandas version, tz-aware timestamps are among the
  copied kinds the docs and benchmark name. This needs no
  numpy C API and works in the abi3 build for Python 3.10, which the
  buffer protocol does not (`lib.rs`'s header).
- **Converted natively, once, into new buffers handed over the same
  way:**
  - a column with a missing value: float64 values and a uint8 code
    array for a `DtaArray`, or values and a bool mask (true where
    missing) for a nullable `Int64`, `UInt*` or `boolean`;
  - BOOLEAN, whose values and validity are bit-packed: one byte per
    row;
  - DATE, days as int32: int64 seconds for `datetime64[s]`, with
    int64's minimum (`NaT`) for a null;
  - a TIMESTAMP, INT96 or TIME column with a null: the values in their
    unit with int64's minimum for each null, since the Arrow buffers
    hold zeros there, which numpy would read as the epoch or midnight.
- **Copied into Python objects.** Text, one `str` per row of a PLAIN
  page and one per distinct value of a dictionary chunk; dictionary
  levels; DECIMAL objects. None of these alias the table.
- **Writes.** A new native entry point per writer takes, for each
  column, its kind, and either numpy arrays (values; codes or a mask)
  or a list of Python objects. It builds the same input the Arrow C
  stream gives the writers today. Python passes only C-contiguous
  and aligned arrays of the declared dtype (`np.require(a,
  requirements=["C", "A"])`), made by the write table above, and holds
  them for the call. The native side reads each array's
  `__array_interface__`, and checks its type string, its shape (the
  frame's row count), that it is contiguous, and that its pointer is
  aligned for its type, before reading: `write.rs` reads values through
  typed pointers, and an unaligned one (a valid numpy array over a
  buffer at an odd offset) would be undefined behaviour.
- `ABI_VERSION` (`python/src/arrow/mod.rs`, checked by
  `datakit/_native.py`) goes up, since the entry points change.
- Nothing needs pyarrow. pandas imports and exports Arrow streams only
  through pyarrow (checked on pandas 3.1.1), and the packages have
  never depended on it.
- The Arrow C stream entry points and their polars-only code go, once
  no caller is left.

**Dependencies.** datakit depends on dta-parser (0.4), pandas and
numpy, and no longer on polars. `requires-python` stays at 3.10: pandas
2.2 supports it, and pip picks a pandas that does. CI's step that
imports datakit without pandas is replaced by one that imports it
without polars. datakit becomes 0.4.0.

**Docs and checks.** `docs/python.md`'s datakit sections, the README,
`docs/migration.md` (polars to pandas), and ADR 0040, which supersedes
ADR 0036 and ADR 0034's paragraph on Python. The cross-language checks
(`compat/parquet/`) read and write through the pandas datakit. The
datakit benchmark (`bench/results/parquet-datakit.md`) is re-run and
the results recorded. There is no speed target: the user wants
correctness first.

**Tests.**

- **Ported.** The datakit suite, ported to pandas. The tests of polars
  `Expr` forms, `Enum`, `Meta._storage`, `LETTERS` as an `Enum` and the
  Arrow stream import go, each replaced where pandas has a counterpart
  (`category`, the `DtaArray` dtype, `LETTERS` as a `CategoricalDtype`).
  Text assertions accept both `object` (pandas 2.2) and `str`
  (pandas 3).
- **Columns.** Each read table row and write table row. A `.`-only
  column and a lettered one are both `DtaArray` and filter and group
  alike, in windows with and without letters, and `pd.concat` of
  windows keeps a `DtaArray`. Storage types round-trip through
  `save_dta` and `save_parquet`, and a value that no longer fits
  widens. BOOLEAN with nulls, and DATE, TIMESTAMP, INT96 and TIME with
  nulls (`NaT`, not the epoch), read correctly. A binary strL survives
  `read_dta` and `save_dta`. TIME in
  milliseconds, microseconds and nanoseconds, with nulls, reads as
  `timedelta64[ns]` and writes back as TIME. A `timedelta64` outside a
  day is refused, as are `Decimal` objects and an unsupported dtype.
- **Behaviour.** Comparisons and filtering give `<NA>`. `groupby` keeps
  `.`, `.a` and `.b` apart. A frame read, filtered, sorted, joined and
  saved keeps its letters and labels.
- **Native arrays.** They stay valid after the native table is deleted
  and `gc.collect()` runs: whole arrays, slices, and columns of a frame
  built from them, on a whole read and on a `skip`/`n_max` window.
  Writing into one changes only that frame. Both writers take a column
  over an unaligned buffer (normalised by `np.require`) and the native
  check refuses one passed past it. `np.shares_memory` holds
  between a native buffer and the frame's column for each column kind
  read without a copy, on pandas 2.2 and the latest pandas, and the
  docs and benchmark name the kinds that are copied. The write
  entry points refuse an array of the wrong type string, length or
  layout.
- **Same columns as dta_parser.** With default arguments,
  `datakit.read_dta` and `dta_parser.read_dta` give the same dtypes,
  codes, categories and dates on the same fixtures, `dtaparser_categorical`
  markers and windows included. Two differences are expected and
  tested: a `dtaparser_factor` column is a `category` in dta_parser and
  labelled numbers in datakit, which leaves that marker alone (plan
  0023); and `letters=False` and `factors=True`, which only datakit
  has, are tested against stated results.
- **Cross-language.** The cross-language round trips.

## Out of scope

- TypeScript keeps tagged NaNs (ADR 0037). JavaScript compares a NaN
  false with everything, as arrow does. table-viewer reads columns and
  does not filter with them, so this is a follow-up, not part of this
  plan.
- Julia: `missing == 1` is `missing`, and `DtaColumn` keeps its codes,
  so Julia already behaves as R.
- dtatools' `dta_num` and its Stata rules (ADR 0009, 0012) are
  unchanged.
- The downstream translator that writes polars (plan 0019) must switch
  to pandas. That is outside this repository.
- Publishing. Nothing here is published.

## Considered options

- **R: polars through nanoarrow, or arrow.** Rejected (decision 1).
- **R: a vctrs class with comparison proxies on every double that can
  hold a letter.** Correct grouping in every verb, but slower
  grouping, sorting and comparisons from then on (decision 2).
- **R: `datakit_by()` returning one column with a proxy class.**
  Slightly faster than a letter column, but the class stays on the
  column in the grouped frame and its result, so later filters and
  sorts pay for it.
- **Python: keep polars and document the comparisons.** Rejected
  (decision 3).
- **Python: pandas with plain `float64` tagged NaNs.** Fast, and
  `isna()`, `count()` and `mean()` treat letters as missing, but
  comparisons are false as in arrow, and grouping merges the letters.
- **Python: pandas nullable `Float64` for every column, letters under
  the mask.** Comparisons are right, but pandas overwrites the masked
  values, even in an input column (stage 1).
- **Python: nullable types for `.`-only columns, `DtaArray` only for
  letters.** Both compare as missing, but `groupby` drops `<NA>` by
  default and keeps a `DtaArray`'s `.` group, so a script's groups
  would still change with the rows read.
- **Python: pandas through pyarrow** (`pd.DataFrame.from_arrow`). A
  large new dependency for what the native adapter does without one.
- **Python: restore the pandas Parquet bridge removed in #69.** It
  predates plans 0020 to 0023, so their rules would be written twice.

## Risks

- **pandas changes `ExtensionArray` behaviour between releases.** CI
  runs the suite on pandas 2.2 and the latest pandas.
- **Some pandas operations turn an extension array into float64**
  (numpy ufuncs, `apply`), losing the letters. The docs list them; the
  result has `.` for every missing value.
- **Speed and memory.** Every numeric column with a missing value is
  now an extension array, whose operations run through Python-level
  methods, and which takes 9 bytes a row (a `byte` column took 4 as
  `float32`). The benchmark records both.
