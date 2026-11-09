# A `DtaArray` compares as missing, and holds every numeric column with a missing value

Amends ADR 0015's last paragraph ("Comparisons and arithmetic use the
float values") and its rule that a column with only `.` missing reads
as `float32` or `float64` with NaN.

Plan 0024 found that a frame library which holds `.a` to `.z` as NaNs
treats them as values: in pandas, polars and arrow, `x != 1` is true on
a letter, so `df[df.x != 1]` keeps it. R's `NA` is missing in every
comparison. The user wants Python to behave as R does, and Python's
datakit to move to pandas (plan 0024, stage 4; that move was dropped,
ADR 0041), so dta_parser's
`DtaArray`, which already keeps a code per row, takes R's rules.

**Comparisons return a pandas `BooleanArray`.** The other operand is
read element by element: a number is itself; NaN, `None` and `pd.NA`
are `.`; a `MissingValue` names its letter; a nullable array's `<NA>` is
`.`; another `DtaArray` gives its values and codes. Then, row by row:
where the other side names a letter, `==` and `!=` compare letters and
an ordering is `<NA>`; otherwise, where either side is missing, `<NA>`;
otherwise the numbers. Text is never equal to a number and cannot be
ordered against one. `MissingValue` hands a comparison with an array
or Series to it, so `missing.a == s` works as `s == missing.a` does.

**Arithmetic returns a `DtaArray` (`double`).** A row missing on the
left keeps its code, else one missing on the right keeps the right's,
whatever the numbers give (`x ** 0` stays missing). A NaN the operation
makes is `.`. Unary `-`, `+` and `abs()`, `round`, `clip` and the
cumulative functions keep codes too.

**Every numeric column holding a missing value in the rows read is a
`DtaArray`**, `.` alone included, so that filters and groups do not
change with the rows read. A column with none keeps its numpy type.
`DtaDtype._get_common_dtype` joins numpy and nullable types whose range
a double holds exactly (bool, 8-, 16- and 32-bit integers, floats) as
the narrowest storage that holds them, so `pd.concat` of two reads
stays a `DtaArray`; int64 and uint64 give `object`, which keeps every
digit.

## Considered options

- **Keep false comparisons** (ADR 0015). `df[df.x != 1]` keeps the
  missing rows, which the user rejected in polars and arrow.
- **Nullable `Float64` for `.`-only columns, `DtaArray` for letters.**
  Both compare as `<NA>`, but `groupby` drops a nullable column's `<NA>`
  group by default and keeps a `DtaArray`'s `.` group, so a script's
  groups would change with the rows read.
- **Arithmetic gives `.` for a missing operand, as Stata's `gen` does.**
  R's doubles, and Python's datakit until now, keep the letter; this
  keeps the languages alike.
- **An `__array_ufunc__` of our own.** pandas' `ExtensionArray` already
  sends ufuncs with an operator (`np.add`, `np.abs`) to the operator;
  the rest give `float64`, which the docs list.

## Consequences

- dta_parser 0.4.0; `docs/migration.md` says what changes.
- A `byte` column with a missing value takes 9 bytes a row instead of 4.
- `np.where` and `bool()` refuse `<NA>`; pandas' `where` and `mask`
  treat a `<NA>` condition as "replace". The docs give `fillna(False)`
  and `loc` assignment.
- A `merge` on a `DtaArray` key and a key of another type is not
  supported; the docs say to give both keys one dtype first.
- `DataFrame.to_numpy()` of a frame holding a `DtaArray` is `object`, as
  for any extension type; `to_numpy(dtype=float)` gives floats.
