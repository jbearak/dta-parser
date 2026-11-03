# `d[i, name := value]` is an error; `d[i, name] := value` is the form

ADR 0019 gave dibbles data.table's `d[i, name := value]`, but returning
a changed copy rather than changing `d` by reference as data.table
does. ADR 0021 added `d[i, name] := value`, which changes `d`. The two
forms then differed only by where the `]` goes, and the first, written
on its own line as a data.table user would, did nothing: in a test, a
fixture went unrecoded and the test could still pass.

`[.dibble` now stops on `:=` in `j` (or in `i`) with an error that
shows the line to write, built from the call:
`d[x == y, z := v]` gives "write `d[x == y, z] := v` to change d". The
`` `:=`(a = 1, b = 2) `` form gets one suggested line per column.
`d[i, name] := value` calls the assignment code directly.

## Considered options

- **Keep both forms** and lead the docs with `d[i, name] := value`.
  The silent no-op stays.
- **Change `d` by reference in `d[i, name := value]`**, as data.table
  does. ADR 0019 rejected rebinding from inside `[`, and
  `e <- d[i, name := value]` would then change `d` as well as `e`.

## Consequences

- A copy takes two statements: `e <- d; e[i, name] := value`.
- Several columns take one line each. Each line sees the columns the
  previous one made, as `` `:=`(a = , b = ) `` did, but `i` is
  evaluated again on each line.
- Every recode that uses the columns now goes through dtatools' `:=`,
  so the load-order rule of ADR 0021 applies to all of them: with rlang
  or data.table attached after dtatools, or dtatools not attached,
  write `` `:=` <- dtatools::`:=` `` (in a test helper) first.
  `d[i, name] <- value` still needs nothing attached, for values that
  do not use the columns.
- dtatools' tests recode fixtures on copies through a test helper,
  `recoded(d[i, name] := value)`.
