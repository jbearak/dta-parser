# Plan: recode dibble columns with `d[i, name] := value`

Status: approved by Sonnet 5.5 and GPT-6.1 Terra (round 1; Sonnet's
empty-`j`, test and help-page points folded in); implemented.

## Problem

Plan 0011 added `d[i, name] <- value`, which changes `d` without
`d <-` in front. R evaluates the right side of `<-` in the caller
before `[<-.dibble` runs, so the value cannot use the columns:

- `d[x == y, z] <- v`, with `v` a column and no variable `v` in the
  caller, stops with R's `object 'v' not found`;
- with a variable `v` in the caller, it silently uses that variable;
- `d[x == y, z] <- d$v` is a length error unless `i` picks every row.

For a value that uses the columns, the user must still write
`d <- d[x == y, z := v]`. The user wants `d[x == y, z] := v`.

R parses `a := b` as a call to a function named `:=`, at the same
precedence as `<-`, and base R defines no such function. A `:=`
exported by dtatools receives `d[x == y, z]` and `v` unevaluated. It can
rewrite them as `d <- d[x == y, z := v]` and run that in the caller. A
throwaway prototype did so: the value used the column `v` even when the
caller had a `v`, inside a function the caller's `d` was unchanged, and
`l$d[, w] := x + v` changed `l$d`.

ADR 0020 rejected exporting `:=` for `d$z[x == y] := v`, mostly because
that form needed its own parsing of each kind of left side. That reason
does not hold here: the left side is always `target[...]`, and R's own
`<-` assigns to whatever `target` is. The other reason, masking, still
holds and is the cost of this plan (see "Masking").

## Design

dtatools exports `` `:=` <- function(lhs, rhs) ``:

1. `lhs <- substitute(lhs)`. It must be a call to `[` with a target and
   exactly two unnamed arguments after it (`i`, possibly empty, and
   `j`), plus at most a named `by`. Otherwise an error:
   - not a `[` call (`x := 1` outside any `[`): "write `d[i, name] :=
     value`, or `name := value` inside `d[...]`";
   - `d[i] := v`, `d[i, ] := v` (empty `j`), `d[i, j, k] := v`, or
     another named argument: "write
     `d[i, name] := value`" (named arguments other than `by` reach
     `[.dibble`'s existing error if we pass them on; simpler to reject
     here with one message).
2. `env <- parent.frame()`; `x <- eval(target, env)`. If `x` is not a
   dibble, an error: "`d[i, name] := value` needs a dibble; convert with
   `as_dibble()`". (A data frame would otherwise reach `[.data.frame`,
   which evaluates `j` and calls `:=` again with a bare name.)
3. Build `x[i, j := rhs, by = ...]` from `lhs` by replacing the target
   with the evaluated `x` and the `j` argument with
   `call(":=", j, rhs)`, keeping an empty `i` empty, and evaluate it in
   `env`. `[.dibble` does all the work as today: `i` and `rhs` among
   the columns, Stata comparisons, conversion, widening, `by`, `.N`,
   `NULL` dropping a column (only without `i`), no rows picked.
4. `eval(call("<-", target, new), env)`, with the new dibble embedded in
   the call, so R's `<-` assigns to `d`, `l$d`, `l[["d"]]` or any other
   target `<-` accepts, in the caller's frame (inside a function that
   makes a local copy, as `<-` does).
5. Return the new dibble invisibly, as `<-` returns its value
   invisibly.

The target is evaluated twice, by step 2 and by `<-`, as R's own complex
assignment evaluates it. A target `<-` cannot assign to (`f()[i, z] :=
v`) fails in step 4 with R's error, after `[.dibble` has run; that is
loud, so it is not checked for.

The column name `j` follows `:=` in `[`: a bare name is the column
itself, `"z"` is a string, and `(nm)` is a variable holding one. Unlike
`d[i, nm] <- v`, a bare name that is also a caller variable is not an
error. That error in `[<-` protects tibble's loop idiom
`for (nm in vars) d[i, nm] <- v`, which has no counterpart for a new
operator, and `d[i, nm] := v` should mean what `d <- d[i, nm := v]`
means.

Several columns (`d[i, c(a, b)] := ...`) are not supported; `j` given
to `:=` in `[` gives the existing "must be one column name" error.

`d[i, name] <- value` stays as it is: it needs no attached package (S3
methods are registered when the namespace loads), and it is enough for
constants.

## Masking

rlang and data.table each export a `:=` whose only job is to raise an
error, since both read `:=` from unevaluated code and never call it.
Whichever package is attached last is the `:=` that `d[i, z] := v`
finds:

- dtatools attached after rlang or data.table: our `:=` hides theirs.
  Their own uses keep working (data.table's `dt[, b := 1]`, rlang's and
  dplyr's `mutate(d, !!nm := 1)`), because none calls `:=`.
- rlang or data.table attached after dtatools: `d[i, z] := v` stops
  with their error ("Check that is.data.table(DT) == TRUE..." or
  "`:=` can only be used within dynamic dots"). Loud, not wrong.
- dtatools not attached (code that calls `dtatools::read_dta()` and so
  on): `:=` is not found, unless a helper binds it with
  `` `:=` <- dtatools::`:=` ``, which then wins over every attached
  package.

R prints "The following object is masked..." on attach in each case.
The docs say: attach dtatools after rlang and data.table, or bind `:=`
in a test helper. Code in a package namespace that imports rlang's `:=`
finds that one through its imports whatever is attached, so it must
bind dtatools' itself. No `.onAttach` hook: it cannot see later attaches.

The testthat suite that dibbles serve calls dtatools through
`dtatools::` and attaches nothing, so its tests would need one helper
line to use the form. This plan does not change that suite.

## Tests

In `tests/testthat/test-assign.R`:

- `d[x == y, z] := v` with `v` a column, while the caller also has a
  `v`, is identical to `d[x == y, z := v]`, and changes `d`;
- `d[, z] := v`, `d[i, "z"] := 1`, `d[i, (nm)] := 1`, `by`
  (`d[, n, by = g] := .N`), `d[, z] := NULL` dropping a column, `i`
  picking no rows, the result invisible;
- a bare name that is also a caller variable (`nm <- "q"; d[1, nm] :=
  1`) makes the column `nm`, where `d[1, nm] <- 1` is an error;
- inside a function (the outer `d` unchanged), on `l$d[...]`;
- errors: `x := 1`, `d[i] := 1`, `d[i, ] := 1`, `d[i, a, b] := 1`, `d[i, a, keyby = g]
  := 1`, a data frame target;
- a fresh R session (as `test-seam.R` runs one), attaching dtatools then
  checking `d[x == 1, y] := x + 1`, and with rlang attached after it,
  that the call fails with rlang's error (documents the load-order
  rule); data.table's `dt[, b := 1]` still working with dtatools
  attached last (`skip_if_not_installed("data.table")`, as it is not in
  Suggests).

The docs test runs `docs/r.md`'s R blocks with dtatools attached, so
the new example there runs.

## Docs

- `?"dibble-assign"`: intro and a section on `d[i, name] := value`,
  with the masking rule; `:=` documented there (`@rdname dibble-assign`,
  so `help(":=", package = "dtatools")` finds it) with an example.
- `docs/r.md`: lead "Make and change columns" with the form that changes
  `df` in place where it fits, keep `:=` returning a copy and `<-` for
  constants; masking rule; exports list.
- ADR 0021, revisiting ADR 0020's rejection of an exported `:=`.

## Out of scope

Several columns in one `:=` call; a `%op%` operator (binds tighter than
`*`, `+`, `==` and `%in%`, so `d[i, z] %op% v * 2` would silently assign
`v`); changing that suite; any change to `[<-.dibble`.
