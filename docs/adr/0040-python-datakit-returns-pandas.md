# Python's datakit returns pandas, with `.a` to `.z` in `DtaArray` columns

Supersedes ADR 0036 for Python (its tagged NaNs in polars `Float64`
columns), and the paragraph of ADR 0034 that has Python's datakit
return polars.

Plan 0024 found that a frame library holding `.a` to `.z` as NaNs
treats them as values. In polars a NaN is equal to every other NaN and
greater than every number, so `x != 1` and `x > 3000` are true on a
letter, `df.filter(x != 1)` keeps it, and `group_by`, `unique` and joins
put `.a` and `.b` in one group. The user decided that polars was the
wrong choice for Python's datakit (plan 0024, decision 3). Stage 3 made
dta_parser's `DtaArray` compare as R's doubles do, `<NA>` on every
missing row, and made it the type of every numeric column holding a
missing value (ADR 0039).

**Python's datakit returns pandas.** `df, meta = read_parquet(path)`,
`read_dta` and `read_fixed_width` give a `pandas.DataFrame` and the same
`Meta`; `save_parquet` and `save_dta` take one. The functions, their
arguments and the files they write do not change.

- **Columns.** A numeric column (INT32 of 8, 16 or 32 bits, FLOAT,
  DOUBLE, `.dta` numbers) with any missing value in the rows read (a
  null, a NaN, `.`, a letter) is a `DtaArray` of its storage type, which
  replaces `Meta._storage`; without one, its numpy type. So `.` alone
  and the letters behave alike, and a script's filters and groups do not
  depend on which rows it read. INT64, unsigned and BOOLEAN columns with
  nulls are pandas' nullable types, which cannot hold a letter. A NaN is
  `.`: pandas' nullable types do not keep a NaN apart from a null, and
  `.dta` has no NaN. A date, timestamp or categorical holding letters is
  read as Stata's numbers or level numbers, as before, now a
  `DtaArray`. With default arguments, `datakit.read_dta` gives the
  columns `dta_parser.read_dta` gives, except that a `dtaparser_factor`
  column stays labelled numbers (plan 0023).
- **Letters in the API.** `tagged_na(".a")` returns
  `dta_parser.missing.a`; `na_tag(x)` returns a Series of `LETTERS`, a
  pandas `CategoricalDtype` of `".a"` to `".z"`, reading a `DtaArray`'s
  codes or a plain float column's tagged NaNs; `is_tagged_na` a numpy
  bool array. The polars expression forms go. A tagged NaN in a plain
  float column is still written as its letter.
- **Native code.** datakit keeps calling the same native reads and
  writes, so every rule in them stays in one place. A read returns a
  native frame whose buffers numpy adopts without a copy through
  `__array_interface__` (which works in the abi3 build for Python 3.10,
  where the buffer protocol does not), each column converted once
  natively where pandas needs another layout (a `DtaArray`'s codes, a
  nullable mask, DATE as seconds, `NaT` under nulls, pandas' category
  codes). Writes take numpy arrays, checked for type, length, layout
  and alignment, and build the Arrow arrays the writers already read.
  The Arrow C stream and its polars-only code go. `ABI_VERSION` is 2.
- **Dependencies.** datakit depends on dta-parser 0.4, pandas and numpy,
  and no longer on polars. Nothing needs pyarrow.

## Considered options

- **Keep polars and document the comparisons.** Rejected by the user:
  filters and groups would be wrong by default.
- **pandas with plain `float64` tagged NaNs.** Fast, and `isna()`,
  `count()` and `mean()` treat letters as missing, but comparisons are
  false on a letter and grouping merges the letters.
- **pandas nullable `Float64` with letters under the mask.** Comparisons
  are right, but pandas overwrites masked values, even in an input
  column (`cumsum`).
- **Nullable types for `.`-only columns, `DtaArray` only for letters.**
  `groupby` drops a nullable column's `<NA>` group by default and keeps
  a `DtaArray`'s `.` group, so groups would change with the rows read.
- **pandas through pyarrow** (`pd.DataFrame.from_arrow`). A large new
  dependency for what the native code does without one.
- **Restore the pandas Parquet bridge removed in #69.** It predates
  plans 0020 to 0023, whose rules would then be written twice.

## Consequences

- A `DtaArray`'s operations run through Python-level methods, and it
  takes 9 bytes a row: a `byte` column with a missing value takes 9
  where `int8` takes 1. The datakit benchmark records the cost.
- Dates, timestamps and categoricals that hold letters change type with
  the rows read, since no pandas date or categorical type can hold a
  letter.
- numpy functions without an operator, `to_numpy()` and `apply` give
  `float64` with NaN for every missing value; the guide lists them.
- pandas' `where` and `mask` treat a `<NA>` condition as "replace"; the
  guide sets letters with `loc`, or `cond.fillna(False)`.
- datakit 0.4.0. The downstream translator that writes polars must
  switch to pandas; that is outside this repository.
