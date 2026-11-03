# `d[i, name] := value` run on a copy of d (any target expression), so a
# test can recode a fixture and keep it: recoded(d[x > 1, y] := 2).
recoded <- function(expr) {
  expr <- substitute(expr)
  env <- new.env(parent = parent.frame())
  env$.recoded <- eval(expr[[2]][[2]], parent.frame())
  expr[[2]][[2]] <- quote(.recoded)
  eval(expr, env)
  env$.recoded
}
