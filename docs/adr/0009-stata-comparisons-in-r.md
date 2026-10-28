# In R, dta_num compares as Stata does, through one order key

The downstream tests are written in Stata's terms. `==` and `!=` never
return NA. A missing value is greater than every number. `.` < `.a` <
... < `.z`. `x == NA` is TRUE exactly for `.`. So every comparison, sort,
match, set and group operation in dtatools works on one key per value:
the number itself, or, for `.` to `.z`, the double Stata stores for that
code. Those doubles are finite, increasing, and above every number Stata
stores, so base R's own `<`, `order()`, `match()` and `duplicated()` on
the keys give Stata's answers. One C function computes the keys from the
NaN payload. It reads plain doubles as well as `dta_num`, which is how
`c(NA, .i)` (whose class base `c()` drops) still works in
`dta_setdiff()` and friends.

For `match()` (`%in%`), `.` keeps the key `NA`, so `x %in% NA` finds `.`
as base R would, and `.a` never matches `NA`.

Arithmetic, math functions and logic follow Stata too; see ADR 0012.

`tab()` returns a named integer vector of counts in Stata's order. The
names are the values as Stata writes them (`1`, `1.5`, `.`, `.a`), not
their value labels, so a failure message names the code.

One limit follows from base R and cannot be fixed inside dtatools.
`match()` transforms only classed values, and `c()` takes its class
from its first argument. So in `x %in% c(1, .a)` the table is a plain
double whose `.a` is just `NA`. Putting a code first (`c(.a, 1)`) keeps
the table a `dta_num`. `dta_setdiff()` and the other helpers read codes
from plain doubles and are not affected. The downstream tests match
against plain numbers or against tables that begin with a code, and
both work.
