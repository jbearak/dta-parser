# Missing values: `.` and `.a` to `.z`

A Stata numeric variable has 27 missing values. `.` is *system
missing*: what Stata gives for 1/0 or an empty cell. `.a`, `.b`, ...,
`.z` are *extended missing values*, which surveys use to record why a
value is missing: `.d` for "don't know", `.r` for "refused", `.s` for
"skipped". A value label set can give each one a text (see
[Value labels](value-labels.md)). Strings have no missing value; the
empty string `""` plays that part.

dta-parser calls each one a *missing code*: 0 for a value that is not
missing, 1 for `.`, 2 for `.a`, ..., 27 for `.z`. The codes are the same
in every language.

## Order

Stata sorts missing values after every number, in the order `.` < `.a` <
`.b` < ... < `.z`. So in Stata, `income > 1000` is true for every missing
income. dta-parser gives each language a *Stata key*: a number that
sorts and compares the way Stata orders values. A number's key is the
number itself; the 27 missing values get the 27 doubles Stata itself
stores for them, which are larger than any number Stata stores. Sorting
or grouping on the keys follows Stata.

| language | key of one value | keys of a column |
|---|---|---|
| R | `dta_num` comparisons and `order()` already use it | |
| Python | `dta_parser.stata_key(v)` | `dta_parser.stata_keys(col)` |
| Julia | `stata_key(x)`, `stata_key(".a")` | `stata_key(col)` |
| TypeScript | `stataKey(cell)` | `stataKeys(column)` |

The keys are equal across languages, so a key computed in Python
matches one computed in Julia.

## How each language holds them

Each language has its own idea of "missing", and none of them has 27
kinds. dta-parser keeps a code next to each value, in a form that the
language's own tools carry along.

**R.** Numeric columns are `dta_num` vectors: doubles where `.` is
`NA` and `.a` to `.z` are `NA` values carrying the letter inside the
bits of the NA (the layout haven's `tagged_na()` uses, so haven and
dtatools agree). Anything that copies doubles keeps the letter:
subsetting, `c()`, `ifelse()`, dplyr verbs. `dtatools::.a` ... `.z` are
the values themselves, so `c(1, NA, .d)` is a valid column. Comparisons
on a `dta_num` follow Stata (missing values are larger than every
number, and never give `NA`).

**Python.** A column with `.` as its only missing value is a float
column with `NaN`, as pandas expects. A column with any of `.a` to `.z`
is a `StataArray`, a pandas extension array that stores a code per row.
`.` reads as `NaN`; the letters read as `dta_parser.missing.a` to
`.z`, one object per letter. `isna()` is true for all 27. The codes
follow their rows through boolean and positional selection, `loc` and
`iloc`, `sort_values`, `concat` and `merge` of `StataArray` columns,
`reindex` (new rows are `.`), `copy`, and `groupby` on the column (where
`.`, `.a`, ... are separate groups, as in Stata). Arithmetic and other
operations may turn the letters into `NaN`.

**Julia.** A column with any missing value is a `DtaColumn{T}`, an
`AbstractVector{Union{Missing,T}}` that stores a code per row. Every
missing value reads as `missing`; `stata_code(col, i)` gives the code,
and `set_stata_code!(col, i, code)` sets it. Bulk operations keep the
codes: slicing, `view`, `copy`, `similar`, `sort`, `permute!`, `vcat`
and `append!` of `DtaColumn`s, and DataFrames' row selection, `sort`,
`subset`, `filter` and `copy`. Assigning one element (`b[i] = a[i]`)
copies `missing`, which becomes `.`. DataFrames' `combine` and `vcat`
of DataFrames build plain vectors: `.` stays, the letters become `.`.

**TypeScript.** `readColumns` gives a `NumberColumn` with `values`
(`Float64Array`, `NaN` where missing) and `missing` (`Uint8Array` of
codes). `readRows` gives each missing cell as a frozen object such as
`MISSING[".a"]`, so `cell === MISSING[".a"]` works.

## Writing them back

Every language writes the codes it holds. Read a file, filter or sort
it with the operations above, and write it: `.a` to `.z` are still
there. Where a language has lost a letter (Python arithmetic, Julia
element-wise copying), the value is written as `.`.

Before release 113, files have no extended missing values; each type
has one missing value, read as `.`.

## How other readers compare

- haven (R) keeps `.a` to `.z` as tagged NAs on read and write;
  dtatools uses the same bits, so values move between the two.
- readstata13 (R) reads them as `NA`, with the codes in an attribute
  when `missing.type = TRUE`; it does not write them.
- pandas reads them as `NaN`, or as `StataMissingValue` objects in an
  `object` column with `convert_missing=True`; it writes only `.`.
- pyreadstat reads them as `NaN`, or as letters with `user_missing=True`.
- ReadStatTables.jl reads them as `missing`.
- @irbisadm/statfmt reads them as `null`.
