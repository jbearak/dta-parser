# dtatools adds dta_pmax and dta_pmin rather than masking pmax and pmin

Base `pmax()` and `pmin()` on a `dta_num` keep a letter where every
argument is missing, chosen by the order of the arguments, and copy the
first argument's labels onto the result (plan 0014). They are not
generics, so dtatools cannot give them a method. It exports
`dta_pmax()` and `dta_pmin()`: base's functions on the plain numbers,
with the result made a `dta_num` by ADR 0012's rule for arithmetic
(every missing or infinite result is `.`, no labels).

## Considered options

- **Export `pmax` and `pmin`, masking base's,** and call base's when no
  argument is a `dta_num`. An unchanged `pmax(x, y)` would then be
  right, but only with dtatools attached after anything else that
  exports the names, and never in code that calls `dtatools::` without
  attaching it, as the suite dtatools exists for does. `:=` (ADR 0021)
  is masked for a syntax base R lacks; here base has the function, and
  masking it would change every bare call in an attached session.
  dtatools already names its versions of base functions with `dta_`
  (`dta_setequal`, `dta_setdiff`) rather than masking them.
- **A loop of our own in C or Rust.** Base's C code, reached by
  removing the class, takes about 8 ms on two columns of a million
  rows, against 5 ms on plain doubles and 29 ms for base's R loop
  today. Rust would mean a new dtaparser callable and an ABI bump (ADR
  0016) for semantics only dtatools has.
- **Documentation only.** It would leave no way to get `.` short of a
  second line that resets the codes.

## Consequences

- `pmax()` and `pmin()` on a `dta_num` still behave as described
  above; `docs/r.md` and `?dta_pmax` say so and point to the new names.
- `max()`, `min()` and the rest of R's Summary group keep R's rules
  (ADR 0012).
- An infinite argument is compared as a number before the result is
  made `.`, so `dta_pmin(1, Inf)` is 1 and `dta_pmax(1, Inf)` is `.`.
