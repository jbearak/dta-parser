# dtatools exports `:=`, for `d[i, name] := value`

ADR 0022 makes `d[i, name := value]` an error, so this is now the only
`:=` form. ADR 0027 gave data frames the same `:=`, and ADR 0032 moved
it to datakit; dtatools re-exports it.

ADR 0020 gave dibbles `d[i, name] <- value`, which changes `d` without
`d <-`. R evaluates the value in the caller before the method runs, so
`d[x == y, z] <- v` cannot use the column `v`: it stops with
`object 'v' not found`, or, if the caller has a variable `v`, silently
uses that. The user asked for `d[x == y, z] := v`.

R reads `a := b` as a call to a function `:=` at the precedence of
`<-`, and base R defines none. dtatools now exports one. It takes
`d[i, name]` (with an optional `by =`) unevaluated and runs
`d <- d[i, name := value]` in the caller, so the value is evaluated
among the columns and everything `:=` in `[` does applies. ADR 0020
rejected an exported `:=` for `d$z[x == y] := v`, a form that needed its
own parsing for each kind of left side. Here the left side is always
`target[...]`, and R's `<-` assigns to whatever `target` is (`d`,
`l$d`, `l[["d"]]`).

## Considered options

- **A `%op%` operator** (`d[i, z] %:=% v`). R gives every `%op%` a
  precedence above `*`, `+`, `==`, `&` and `%in%`, so
  `d[i, z] %:=% v * 2` runs `(d[i, z] %:=% v) * 2`: it assigns `v` and
  raises no error. Every value with an operator would need parentheses.
  A guard that errors on any use of the return value missed `%in%` and
  `|>`, and fired only after `d` had changed.
- **A function**, such as `recode_where(d[x == y, z], v * 2)`. No
  precedence or masking problems, but it does not read as an
  assignment.
- **Keep `d <- d[i, name := value]`** for values that use the columns.

## Consequences

- rlang and data.table each export a `:=` that only reports misuse.
  Whichever of the three packages is attached last is the `:=` that
  `d[i, z] := v` finds. With rlang or data.table attached after
  dtatools, the line stops with their error; it never assigns wrongly.
  Code that calls `dtatools::` without attaching it, or a package that
  imports rlang's `:=`, must bind ours: `` `:=` <- dtatools::`:=` ``.
  Their own `:=` syntax keeps working with ours attached, since neither
  calls `:=`.
- `d[i, name] := value` changes `d` and `d[i, name := value]` returns a
  copy; they differ only by where the `]` goes.
- A bare name in `d[i, nm] := v` is the column, as in `:=` in `[`,
  where `d[i, nm] <- v` errors when `nm` is a caller variable.
- `d[i, name] <- value` stays, for constants, since it needs no
  attached package.
