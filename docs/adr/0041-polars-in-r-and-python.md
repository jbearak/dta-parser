# polars in R and Python, with `is_missing()` and `is_na()`

Supersedes in part ADR 0038 (R's datakit gains polars functions;
`datakit_by()` stands) and plan 0024's stage 4 (Python's datakit does
not move to pandas). Plan 0025 is the plan.

Plan 0024 found that polars holds `.a` to `.z` as NaNs and treats a NaN
as a value, and moved Python's datakit to pandas, where a `DtaArray`
compares a missing value as `<NA>`. The pandas datakit was built and
measured on a DHS file of 4,962 columns: polars read it in 20 ms and the
pandas datakit in 155 ms, and pandas sorted it in 103 ms against
polars' 6 ms. Most of the read could be fixed; the per-column cost of
pandas operations on wide frames could not. The user chose polars for
both languages, "so long as we understand the rules".

**The rules**, for the rows `1, 5000, .a, .b, .` in polars 2.1 (`.` a
null, each letter a tagged NaN):

| expression | rows a filter keeps |
|---|---|
| `x != 1` | 3: `5000`, `.a`, `.b` |
| `(x != 1) & x.is_not_null()`, R's `x != 1 & !is.na(x)` written naively | 3 |
| `(x != 1) & x.is_not_nan()` | 1 |
| `x.fill_nan(None) != 1` | 1 |
| `x.is_null() \| x.is_nan()`, R's `is.na(x)` | `.`, `.a`, `.b` |

polars also makes every NaN equal to every other (so `group_by`,
`unique` and `is_in` merge `.a` with `.b`), and orders NaN above every
number (`x > 3000` is true on a letter).

**Decisions.**

1. Python's datakit stays on polars, letters as tagged NaNs (ADR 0036).
2. R's datakit gains `read_parquet_pl()`, `read_dta_pl()` and
   `read_fixed_width_pl()`, returning `list(df, meta)`, and
   `save_parquet()` and `save_dta()` take a polars frame with `meta`.
   The tibble functions stay.
3. R's polars frames come from the native Arrow C stream code, shared
   with Python, so both languages get the same columns.
4. Both languages get `is_missing()` and its alias `is_na()`: true for
   `.` and `.a` to `.z`, as R's `is.na()` is. Python also gets `dk.by()`
   and R `datakit_by_pl()`, which add a letter column beside each key so
   grouping and `unique` keep the letters apart. Joins keyed on columns
   holding letters are not a use case (the user, 2026-11-09).

## Considered options

- **pandas for Python** (plan 0024, stage 4). Built; dropped for speed.
- **R on tibbles only** (ADR 0038). The user wants polars in R too.
- **Letters as nulls by default.** Comparisons would be right, but the
  letters would be lost; `letters = FALSE` stays for that.
- **An alias `is_mi`** (Stata's `mi()`). The user chose `is_na`.

## Consequences

- Code on polars must use `is_missing()` / `is_na()`, or
  `fill_nan(None)`, where R would use `is.na()`, and `dk.by()` /
  `datakit_by_pl()` where it groups on a column holding letters. The
  guides lead with the table above.
- rlang also exports `is_na()` and `is_missing()`, with other meanings;
  a script that attaches rlang after datakit gets rlang's.
- dta_parser's `DtaArray` (ADR 0040) stays as it is, for pandas users of
  dta_parser.
