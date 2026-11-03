# A dibble takes `d[i, name] <- value`, with `i` among the columns

ADR 0019 made `d[i, name := value]` return a new dibble, so every
recode needs `d <-` in front. The user asked for a form without it.
`[<-.dibble` now handles `d[i, name] <- value` and `d[, name] <- value`,
with `i` evaluated among the columns, and does what
`d <- d[i, name := value]` does. R reassigns `d` itself, as it does
for any replacement function, so the form works inside functions and
on nested targets (`l$d[i, x] <- v`).

R evaluates `value` in the caller before the method runs, so it cannot
use the columns, and there is no `by` and only one column at a time.
`:=` remains the form for those cases.

## Considered options

- **`d$z[x == y] := v`.** R parses this as a call to `:=`, not as an
  assignment, so dtatools would have to export a `:=` that takes its
  left side apart and rebinds `d` with `assign()` in the caller.
  rlang and data.table both export `:=`, so whichever package is
  attached last wins. Each form of the left side (`l$d$z`, `d[["z"]]`)
  would need its own parsing, and `d$z[x == y]` reads as base R, where
  `x` and `y` are the caller's.
- **`d$z[x == y] <- v`.** The inner `[<-` dispatches on the column,
  not on the dibble, so it cannot find `x` and `y` among the columns.
  For a new column `d$z` is `NULL` and no method runs at all.
- **Leave `[<-` to tibble.** Recodes would then always need `d <-`.

## Consequences

- `i` in `d[i, name] <- value` now finds columns before the caller's
  variables, as in dplyr. Code written for tibble's `[<-` that uses a
  variable with the same name as a column, such as
  `for (i in 1:3) d[i, "x"] <- 0` on a dibble with a column `i`, now
  gets the column.
- In tibble, a bare `j` is a variable holding a column name, and in
  `:=` it is the column itself. Here, a bare name that is a column
  means that column. A bare name that is not a column but is a
  non-function variable in the caller is an error, so the loop idiom
  `d[x > 0, nm] <- 1` cannot silently make a column named `nm`. The
  same error stops helpers that take a column name, as in
  `function(d, col, v) { d[d$x > 1, col] <- v; d }`, until they write
  `(col)`. It also stops a new column named like a non-function object
  in base R (`pi`, `T`, `letters`); `d[, "pi"] <- v` works.
- `d[nrow(d) + 1, "x"] <- v`, which adds a row in tibble, is an error
  pointing to `d[nrow(d) + 1, ] <- list(...)`.
- The value is converted and the storage widens as with `:=`, where
  tibble's `[<-` stored values as given. `d[i] <- v`, numeric `j` and
  several columns are still tibble's, with `i` evaluated in the caller.
