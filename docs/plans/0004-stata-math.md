# Plan: arithmetic, math and logic on dta_num as Stata does them

Status: draft, revised after review round 1.

## Problem

Comparisons on a `dta_num` already follow Stata (ADR 0009): never NA,
missing values above every number, `.` < `.a` < ... < `.z`. Arithmetic,
math functions and `&`/`|`/`!` do not:

| with `x <- dta_num(c(3, NA, .a, 0))` | today | Stata |
|---|---|---|
| `x + 1` | a plain double, so `(x + 1) > 5` is `NA` for missing rows | `.`, and `. > 5` is true |
| `x / 0` | `Inf`, `NaN` | `.` |
| `.a + 1` | NaN that may keep `.a`'s payload | `.` |
| `abs(x)`, `round(x)` | one keeps `.a`, the other drops it | `.` |
| `x & TRUE`, `!x` | `NA` | missing counts as true: `. & 1` is true, `!.` false |

The user wants dtatools to handle math and comparisons with missing
values the way Stata does, performant and without over-engineering. The
downstream suite only compares, combines comparisons with `&`, `|`, `!`,
and counts them; it does no arithmetic on columns. So this is about
making the class safe for the next test, kept small.

Strings need nothing: `is_missing()` already treats `""` as missing, and
string comparisons are the same in R and Stata.

## The rule

If either operand of an operation is a `dta_num`, the operation follows
Stata, and R's missing values on the other side (`NA` of any type,
`NaN`) mean `.`. If neither is, R's rules apply (dtatools' methods do
not run). Concretely:

- **Arithmetic** (`+ - * / ^ %% %/%`, unary `-` and `+`): R's operation
  on the numbers (`%%` and `%/%` are R's; Stata has `mod()` and `int()`
  instead), but wherever either operand is missing the result is `.`
  (R alone gives `NA^0 == 1` and `1^NA == 1`), and every result that is
  NaN or ±Inf becomes `.` (canonical `NA_real_`, no letter). Names are
  kept as R would. The result is a `dta_num` with storage
  `double` and no labels, label or format (a new value, like a Stata
  `generate`). Later comparisons are then Stata's.
- **Math functions** (R's `Math` group: `abs`, `sign`, `sqrt`, `floor`,
  `ceiling`, `trunc`, `round`, `signif`, `exp`, `log` and the rest):
  R's function on the numbers, so `round(x, 1)` is R's (to digits,
  half to even), not Stata's `round()` (to a unit); only the missing
  values follow Stata, by the same rule as arithmetic. R's "NaNs
  produced" warning is not given, as Stata gives `.` silently. The cumulative ones (`cumsum`, `cumprod`,
  `cummax`, `cummin`) follow it too, so a missing value makes every
  later result `.`; Stata's running `sum()` treats missing as 0 instead,
  which ADR 0012 records as a known difference.
- **Logic** (`&`, `|`, `!`): an operand is true where it is nonzero or
  missing, false where it is 0; R's `NA` counts as missing, so as true.
  The result is an R logical without NAs, ready for `[` and `sum()`.
  A string or factor operand is an error.
- **Comparisons**: unchanged (ADR 0009).
- **Not changed, documented as R's:** the `Summary` group (`sum`, `min`,
  `max`, `range`, `prod`, `any`, `all`) and `mean()`: Stata has no
  single meaning (`summarize`, `egen`, `collapse` each skip missing
  values their own way), so they keep R's rules on the numbers.
- **Mixing with another class that has its own operators** (`Date`,
  haven's `labelled`, factors): R warns about incompatible methods and
  uses its own rules (the result may keep the first operand's class);
  documented, not changed.
- **Limits:** finite values above Stata's largest double (about
  8.99e307) stay numbers here; Stata would hold them as missing. A
  matrix operand gives a plain `dta_num` vector (no `dim`).

The facts about Stata used here are general knowledge about its
missing values (arithmetic and functions of missing give `.`, missing
is true in logical contexts); per AGENTS.md no Stata output or
documentation is used. That a function of `.a` gives `.` rather than
`.a` is the least certain of them; the plan follows it because it is
what arithmetic does.

## Design

In `r/dtatools/R/dta_num.R`, about 30 lines, plain vectorised R:

- `Ops.dta_num`: comparisons as today; `&`, `|`, `!` through
  `truthy(e) = is.na(v) | v != 0` on `v = as.double(numbers-or-e)`;
  arithmetic through `stata_number(r)`, which sets non-finite results to
  `NA_real_` and returns `dta_num(r)`.
- `Math.dta_num`: `stata_number(get(.Generic)(numbers(x), ...))`.

Cost: one extra pass (`is.finite` and an assignment) per arithmetic or
math result; no new C.

ADR 0012 replaces ADR 0009's "arithmetic is not Stata's" paragraph and
states the rule above.

Considered and declined: replacing `get(.Generic)` with a `switch`; it
is one lookup per vectorised call.

## Tests

`tests/testthat/test-stata-math.R`, one expectation per rule, written
as Stata-rule tables (expected codes as `.`, `.a`, numbers):

- arithmetic with a number, with `NA`, with another `dta_num`, with
  integers and logicals; `.a + 1` is `.`; `x / 0`, `log(0)`, `sqrt(-1)`,
  overflow (`1e308 * 10`) are `.`; the result is a `dta_num` without
  labels and compares Stata's way (`(x + 1) > 5` true for missing);
- unary minus and plus keep missing as `.`; `.^0`, `1^.` are `.`,
  `0^0` is 1; a plain operand on the left (`2 - x`, `6 / x`, `2^x`,
  `NA < x`) keeps the operation's direction; names are kept;
- `abs`, `round(x, 1)` (pinned as R's, including `round(2.5) == 2`),
  `floor`, `exp` on numbers and codes;
- `&`, `|`, `!` with `dta_num`, logical (including `NA`, on either side)
  and numeric operands; `!.a` is false; results have no NAs; a string
  or factor operand is an error;
- `mutate()` makes a `dta_num` column whose comparison is Stata's;
- mixing with haven's `labelled` warns and uses R's rules;
- character with arithmetic is an error; with comparisons, unchanged;
- `sum(x)` and `max(x)` keep R's NA (a test pins the documented
  behaviour).
- The existing tests and the downstream suite pass.
