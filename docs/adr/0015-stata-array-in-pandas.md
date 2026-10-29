# StataArray: `.` is NaN, the dtype carries the storage type

Plan 0005 makes a numeric column with any of `.a` to `.z` a pandas
ExtensionArray holding values and a code per row. Three choices it left
open:

- **`.` reads as NaN; `.a` to `.z` as `dta_parser.missing.a` ... `.z`.**
  A column whose only missing value is `.` is already a float column
  with NaN, so `.` means the same in both, and pandas' own NA handling
  (`isna`, `fillna`, `reindex`, `merge`) fills with `.`. The letters have
  no pandas meaning, so they are objects of their own, one per letter,
  which assignment accepts and which compare equal only to themselves.
  `isna()` is true for all 27 codes.
- **The dtype names the storage type**: `stata[byte]` ... `stata[double]`.
  `attrs` is lost in `merge` and some `concat`s, and the codes alone
  cannot say whether `1` was a byte or a double; with the storage in the
  dtype, `write_dta` writes such a column back as it came. Concatenating
  different storage types gives the narrowest type holding both.
- **Factorising uses the Stata key**, so `groupby` keeps `.`, `.a`, ...
  as separate groups even with pandas' default `dropna=True`, and sorts
  them after the numbers, as Stata does. The cost: pandas sorts by
  several columns through `Categorical`, which refuses missing
  categories, so `sort_values([...])` over a `StataArray` with missing
  values needs `key=dta_parser.stata_keys`. Sorting by one column
  needs nothing. Making `isna()` false for the letters would avoid that
  but break `fillna`, `dropna` and NA-aware reductions.

Comparisons and arithmetic use the float values (NaN for every missing
value); comparing with a `missing` letter compares codes. Stata's
comparison and arithmetic rules stay in R (ADR 0009, 0012), as the plan
says.
