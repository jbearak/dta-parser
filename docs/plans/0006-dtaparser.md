# Plan: dtaparser, an R reader that returns plain R types

Status: approved by Sonnet 5.5 (three rounds) and GPT-6.1 Terra (four rounds).

## Problem

dtatools exists for a testthat suite that checks a Stata pipeline. Its
`read_dta` returns a dibble whose numeric columns are `dta_num`, so
`x > 5` is TRUE for a missing value and `x == .a` works, as in Stata.
That is what the tests need. Someone importing a `.dta` file to analyse
it in R wants the opposite: R's rules, where `x > 5` is `NA` for a
missing `x`, and the types the rest of R expects (integers, factors,
`Date`). Today they must use haven or readstata13 and give up the speed
of the Rust reader and its packed strings.

The user wants a second, simpler R package, `dtaparser`, whose
`read_dta` always returns standard R types. A setting on
`dtatools::read_dta` was considered and rejected: one function whose
results follow Stata's rules or R's depending on an argument makes the
mistake easy to miss in a test suite, and an analyst should not need to
learn about dibbles to read a file.

## Package layout

`dtaparser` owns everything that touches the file. `dtatools` depends on
it and adds Stata's rules on top.

```
r/dtaparser   NEW. The Rust bridge (src/rust/lib.rs), the packed string
              columns (src/strings.c), init.c; the core copied in by
              configure, as dtatools does today. Exports read_dta.
r/dtatools    No Rust and no cargo any more. Keeps keys.c (codes and
              order keys) and its R code. Imports dtaparser and calls
              its reader, writer and dictionary access through C
              callables.
```

The bridge moves with `git mv`, so its history follows it. Inside it,
besides plain mode (below), everything named for dtatools is renamed
for dtaparser: the C and Rust symbols (`dtatools_*`), the crate name
and `-ldtatools` in `Makevars`, the environment variables
`DTATOOLS_DICT_WINDOW` and `DTATOOLS_DICT_LIMIT`, and messages such as
"which dtatools does not read".

**The seam.** dtaparser registers C functions with
`R_RegisterCCallable` in `R_init_dtaparser`:

| callable | what dtatools uses it for |
|---|---|
| `dtaparser_abi()` | an integer; dtatools refuses to load with a different one |
| `dtaparser_meta(path, encoding)` | `read_dta`'s metadata, as today's `C_dta_meta` |
| `dtaparser_read(path, cols, skip, n_max, encoding, mode)` | `read_dta`; mode is below |
| `dtaparser_write(path, spec)` | `save_dta`, unchanged spec |
| `dtaparser_dictionary(x)` | `tab`, `dta_group_id`, `is_missing` on dictionary columns |

`mode` is an integer: `1` gives exactly today's dtatools columns, `0`
plain columns with dates kept as numbers, `2` plain columns with dates
converted. Mode 1 means dtaparser knows dtatools' column layout (tagged
doubles, class `dta_num`); that is the price of filling each column once.

The packed-state routine the dtatools tests use stays a registered
`.Call` routine of dtaparser, not a callable; dtatools' test helper calls
`dtaparser:::C_dta_packed_state`.

**Loading.** dtatools' `.onLoad` calls `loadNamespace("dtaparser")`, then
a dtatools C routine that fetches every pointer with `R_GetCCallable`
and returns dtaparser's ABI number. An older dtaparser without
`dtaparser_abi` makes `R_GetCCallable` fail; the routine looks for
`dtaparser_abi` first, inside `R_tryCatchError`, and either failure
becomes one error: "dtatools needs dtaparser built from the same
release; reinstall dtaparser". dtatools' own `.Call` routines keep their
names (`C_dta_read` and so on) and forward to the pointers.

R errors raised inside a callable unwind through dtatools' C frame and
dtaparser's C frames only, never through Rust; the Rust code still
returns a status and dtaparser's C entry point raises the error, as
now (ADR 0007).

**DESCRIPTION.** dtatools: `Imports: dtaparser (>= 0.1.0)` and no
`SystemRequirements`; dtaparser gets `SystemRequirements: Cargo`. The
docs say dtaparser must be installed before dtatools, since neither is
on a registry.

The packed string class is registered by dtaparser, so its ALTREP class
is `packed_strings` from package `dtaparser`. Serialized columns are
plain character vectors (ADR 0010), so no `.rds` file needs either
package to load.

`read_dta`'s argument checks and `col_select` handling (about 25 lines)
are copied into dtaparser rather than shared: sharing would need another
export or `:::`, for little gain.

## dtaparser::read_dta

```r
read_dta(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf,
         factors = TRUE, dates = TRUE)
```

`file`, `col_select`, `encoding`, `skip` and `n_max` mean what they mean
in dtatools. It returns a tibble. Every numeric missing value, `.` and
`.a` to `.z` alike, is R's `NA`; there is no way to get the letters
back (dtatools is the package for that). Strings stay as stored: Stata
has no missing string other than `""`, and haven also reads `""` as
`""`.

| Stata column | R column |
|---|---|
| byte, int, long | `integer` (every non-missing long fits; R's `NA_integer_` is below Stata's smallest long) |
| float, double | `double`, missing as `NA_real_` with no payload |
| strN, strL (text) | `character`, packed or dictionary (ADR 0010, 0011) |
| binary strL | an error naming the column, as in dtatools |
| a date format (below), no value labels, `dates = TRUE` | `Date`, always a double whatever the storage (days since 1960 minus 3653) |
| a datetime format (below), no value labels, `dates = TRUE` | `POSIXct`, a double, `tzone = "UTC"` (milliseconds since 1960 to seconds since 1970) |
| `%tC` and every other `%t` format | numbers, as stored |
| value labels on a non-missing value, `factors = TRUE` | `factor` (below) |
| value labels on a non-missing value, `factors = FALSE` | numbers with a `labels` attribute: the non-missing codes, named by their text |

A set that labels only missing values (`.d` "Don't know") labels
nothing plain mode returns, since those values are `NA`; such a column
is read as if it had no value labels. (Found while writing the docs:
otherwise a continuous column with labelled missing codes became a
factor of its numbers. haven's `as_factor()` does make that factor.)

A date format starts with `%td`, `%-td` or `%d` (the old name for
`%td`, as in `%dDlY`); a datetime format starts with `%tc` or `%-tc`.

haven differs on purpose in these places:

- It reads every numeric column as a double; dtaparser reads byte, int
  and long as integers, which take half the memory.
- It reads `%-td` and `%-tc` as numbers; the `-` only left-aligns the
  display, so dtaparser converts them.
- It reads `%tC` as `POSIXct`. `%tC` counts leap seconds, so a UTC
  timestamp would be off by up to 27 seconds; it stays numeric, as in
  plan 0005.
- Factor level text for unlabelled integers that R prints differently
  as doubles, such as 100000 and -100000 (below).

**Factors.** The levels are, in increasing order of value, every
non-missing labelled code and every non-missing value read that has no
label. "Read" means the rows `skip` and `n_max` select, so the levels
of a column can depend on them, as with haven's `as_factor()` on the
same rows. A labelled code's level is its text; an unlabelled value's
level is `as.character()` of the value as read: of the integer for
byte, int and long (`"100000"`), of the double for float and double.
haven reads every column as a double, so its levels for 100000 and
-100000 are `"1e+05"` and `"-1e+05"`. Levels that would repeat (two codes with the same
text) are one level, at the position of the smallest code. Missing
values are `NA` even when the file labels them (`.d` "Don't know").
Otherwise haven's `as_factor(zap_missing(x), levels = "default")` gives
the same factor, which makes it the oracle.

**Attributes.** Each column has `label` (the variable label) when the
file gives one and nothing else Stata-specific: no `format`, `storage`
or `label_set`. The tibble has `label` (the dataset label) and `notes`,
as in dtatools.

**Dependencies.** Imports rlang, tibble, tidyselect. Suggests haven and
testthat.

## What changes in the bridge

Today's code decides everything while it fills each column, so R never
copies a column to change it. Plain mode keeps that:

- A byte, int or long column is filled as an R integer vector, every
  missing value `NA_integer_`; float and double as doubles with every
  missing value `NA_real_`.
- In mode 2, a column with a date or datetime format and no value
  labels is filled as doubles, converted as in the table, with class
  `Date`, or class `c("POSIXct", "POSIXt")` and `tzone` `"UTC"`.
- Attributes: `label` when non-empty; for a labelled column, `labels`
  (the non-missing codes, as doubles, named by their text). No
  `format`, `storage`, `label_set` or class otherwise.

`read_dta` turns a labelled column into a factor in R when `factors =
TRUE`: the factor's integer codes are a new vector anyway (`match()` on
the codes), so nothing is copied that would not be. With `factors =
FALSE` the column comes back as filled.

## Tests

dtaparser gets its own `tests/testthat`. Expected values come from haven
only (AGENTS.md). dtaparser's tests cannot use dtatools, which depends
on dtaparser, so fixtures come from two places:

- haven's `write_dta`, at test time, for what haven can write (long,
  double, strings, labels, tagged missing values, `Date`, `POSIXct`).
- dtaparser's own writer, through its registered routine
  (`dtaparser:::C_dta_write` with a spec built by a test helper), for
  what haven cannot: byte and int storage, the extremes of each integer
  type, formats such as `%d`, `%-td`, `%tC` and `%tdDD/NN/CCYY`.

The cases:

- Every compat fixture that haven reads (skipped outside a checkout,
  as in dtatools): numeric values equal haven's as doubles
  (`as.double()` of ours; haven's NAs made plain with
  `x[is.na(x)] <- NA` and its `label` and `format.stata` attributes
  removed); labelled columns equal haven's
  `as_factor(zap_missing(x), levels = "default")`; date columns equal
  haven's `Date` and `POSIXct`. Columns with `%tC` or `%-t` formats, and
  labelled integer columns with an unlabelled value whose
  `as.character()` differs as an integer and as a double, are left out of the comparison and tested on their own.
- Types: byte, int and long are `integer`; float and double `double`;
  a column of only missing values; the extremes of each integer type.
- Missing values: `.` and `.a` to `.z` are all `NA`, with no payload
  (`haven::is_tagged_na()` is FALSE); `x > 5` is `NA` where `x` is
  missing (the behaviour this package exists for).
- Factors: unlabelled values become levels in order; unlabelled longs
  of 100000 and -100000 have levels `"100000"` and `"-100000"`;
  duplicate texts merge; labelled missing codes are `NA`; `n_max`
  changes which unlabelled values become levels; `factors = FALSE`
  gives the `labels` attribute.
- Dates: `%td` on a long column is a double `Date`; `%tc` has `tzone`
  `"UTC"`; `%d`, `%dDlY`, `%-td` and `%tdDD/NN/CCYY` are `Date`;
  `%-tc` is `POSIXct`; `%tC` stays numeric; `dates = FALSE` keeps numbers; a date column with
  value labels is a factor.
- `col_select`, `skip`, `n_max`, encoding before 118, and the error
  for binary strLs: the same cases as dtatools' tests, on the plain
  types.
- Packed and dictionary strings: a string column is packed after the
  read; a tibble saved with `saveRDS` reads back in a fresh R process
  without dtaparser loaded.

dtatools' existing tests run against the layered package; only the
helper changes (`DTAPARSER_DICT_*`, `dtaparser:::C_dta_packed_state`).
`test-r_errors.R` already checks that R errors from a read propagate,
now across the forwarder. Two tests are added for the seam:

- In a fresh R process, `library(dtatools)` and a read work without
  dtaparser attached, and a failing read followed by a good one works.
- The ABI check: the R function that compares the numbers is called
  with two different ones and gives the reinstall message.

## Build and CI

- `r/dtaparser/configure` copies the core, as dtatools' does now;
  dtatools loses `configure`, `src/rust` and its cargo step.
- `scripts/build-r-package.sh` builds both source packages.
- CI's `r` job runs `setup-r-dependencies` on `r/dtaparser` only, with
  `any::vctrs, any::haven, any::testthat, any::dplyr, any::readstata13`
  as extra packages (dtatools' other imports and both packages' test
  dependencies), because pak cannot resolve `dtaparser` from a registry.
  It then installs the dtaparser tarball, then dtatools', from outside
  the checkout, and runs both test suites. The `readback` job does the
  same.
- `bench/`, `compat/` and the docs that call `dtatools::read_dta` keep
  working without change.

## Docs

- ADR 0016: the package split and the C callable seam. ADRs 0007 and
  0010 get a line pointing to it, since they name dtatools as the
  package that holds the bridge and the packed strings.
- `CONTEXT.md`: add *dtaparser* and *plain mode*.
- README: one paragraph per R package saying which to use and that
  dtaparser installs first.

## Out of scope

- `dtaparser::write_dta`. The writer lives in dtaparser for dtatools'
  `save_dta`, but writing factors, `Date` and `POSIXct` needs its own
  type rules (plan 0005 has them for Python); a follow-up.
- Benchmarks for dtaparser. Plain mode does the same work as dtatools'
  read plus factor conversion; one timing goes in the PR as a check.
- Publishing either package anywhere (AGENTS.md: ask first).

## Proof

- Both packages build from their tarballs and install from outside the
  checkout, dtatools after dtaparser, as CI does.
- `R CMD check` on both tarballs, dtaparser installed first, with no
  errors, no NOTE about dtaparser as an unused import, and no warnings
  beyond those dtatools already has (no Rd files; Rust's standard
  library links `abort`).
- dtaparser's tests and dtatools' tests pass.
- `cargo test --workspace`, clippy and the npm tests still pass (the
  core is not touched).
- One read of a large file with each package, to show plain mode costs
  about what dtatools' read does.
