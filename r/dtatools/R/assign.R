#' Make and change columns with `:=`
#'
#' `d[i, name := value, by = g]` returns `d` with column `name` set to
#' `value` on the rows `i` selects, as data.table's `:=` does, but as a
#' new dibble. `d` itself is unchanged: write `d <- d[i, ...]`. A line
#' `d[i, name := value]` on its own does nothing, even in a test.
#'
#' - `i` is evaluated among the columns. Comparisons follow Stata's rules
#'   (see [dta_num()]), so `d[age > 30, ...]` includes rows whose age is
#'   missing. A `dta_num` is true where nonzero or missing, as in Stata's
#'   `if`; logical `NA` selects no row; other numbers are row numbers.
#'   Without `i`, every row.
#' - `value` is evaluated, as in data.table, among the columns of the
#'   selected rows only (of each group, with `by`), and is recycled from
#'   length 1. `.N` is the number of rows it sees. Stata's `if` does not
#'   narrow `_n`, `_N` or `x[1]` that way, so `d[, n := seq_len(.N), by
#'   = g]` is `by g: gen n = _n` only without `i`; and the rows keep
#'   their order, where `bysort` sorts.
#' - Values are converted as [dibble()] converts columns. `Inf`, `-Inf`
#'   and `NaN` become `.`, and string `NA` becomes `""`, since Stata
#'   holds neither.
#' - A new column is `.` (or `""` for strings) on the other rows, and
#'   takes the value's attributes, so `b := a` copies `a`'s labels while
#'   `b := a + 1` has none; with `by`, the first group's.
#' - An existing column keeps its labels, label and format, as `replace`
#'   does. If its storage cannot hold the new values it widens to the
#'   narrowest of `int` and `long` that holds them, else to `double`
#'   (not `float`, so no digits are lost). A `float` column stays
#'   `float` within its range, so its values round as floats do.
#'   Strings cannot go into a numeric column, nor numbers into a string
#'   column.
#' - `by` names grouping columns: `by = g`, `by = c("g", "h")` or
#'   `by = .(g, h)`. `.`, `.a`, ..., `.z` are each their own group. A
#'   `by` column cannot be changed.
#' - Several columns at once: `` d[, `:=`(a = 1, b = a + 1)] ``. Each is
#'   made in turn, so `b` sees the new `a`; `i` and the groups are
#'   computed once, before the first.
#' - A value of `NULL` drops the column (not with `i` or `by`).
#' - When `i` picks no rows, an existing column is left as it is and its
#'   value is not evaluated. A new column is evaluated once on zero rows
#'   only for its type; if that fails, it is `.`, and the error is not
#'   shown.
#'
#' The name may be a string (`"a" := 1`) or, in parentheses, a variable
#' holding one (`(nm) := 1`). A column that was a sort key ends the sort
#' order there. `.N` and `.data` hide columns of those names. data.table's
#' other arguments (`keyby`, `on`, ...) are
#' errors. Any `[` without `:=` is tibble's.
#'
#' @param x A dibble.
#' @param i Rows: a condition or row numbers.
#' @param j `name := value`, or `` `:=`(name = value, ...) ``.
#' @param ... Passed to tibble's `[` when `j` is not `:=`.
#' @param by Grouping columns.
#' @return A dibble.
#' @examples
#' d <- dibble(age = c(25, 41, NA, 37), kids = c(0, 2, 1, .d), g = c(1, 1, 2, 2))
#' d <- d[age > 35, older := TRUE]       # missing age counts as > 35
#' d <- d[kids == .d, kids := .r]
#' d <- d[, n_in_g := .N, by = g]
#' d
#' @name dibble-assign
NULL

#' @export
`[.dibble` <- function(x, i, j, ..., by) {
  if (missing(j) || !is_assign(substitute(j))) {
    if (!missing(i) && is_assign(substitute(i))) stop("dibble: write d[, name := value], with a comma", call. = FALSE)
    if (!missing(by)) stop("dibble: by needs := in j", call. = FALSE)
    return(NextMethod())
  }
  if (...length()) stop("dibble: [ with := takes only i, j and by", call. = FALSE)
  env <- parent.frame()
  steps <- assign_steps(substitute(j), env)
  n <- nrow(x)
  rows <- if (missing(i)) seq_len(n) else assign_rows(eval_columns(substitute(i), column_env(x), NULL, env), n)
  by <- if (missing(by)) character() else by_names(substitute(by), env, names(x))
  if (!all(by %in% names(x))) stop("dibble: no column ", setdiff(by, names(x))[[1]], " to group by", call. = FALSE)
  # With no rows there are no groups; the value, evaluated once on zero
  # rows, still gives the column's type.
  groups <- if (length(by) && length(rows)) {
    vctrs::vec_group_loc(vctrs::vec_slice(vctrs::new_data_frame(unclass(x)[by], n = n), rows))$loc
  }
  for (step in steps) {
    name <- step$name
    columns <- column_env(x)
    if (name %in% by) stop("dibble: cannot change ", name, ", a by column", call. = FALSE)
    # When i picks no rows, an existing column stays as it is, and a new
    # one needs the value only for its type.
    if (!length(rows) && !missing(i) && !is.null(x[[name]]) && !is.null(step$value)) next
    value <- if (!length(rows)) {
      # Best effort: a value that fails on zero rows (`x[[1]]`) gives `.`.
      tryCatch(suppressWarnings(group_value(step, columns, rows, env)), error = function(e) logical())
    } else if (is.null(groups)) {
      group_value(step, columns, rows, env)
    } else {
      parts <- lapply(groups, function(loc) group_value(step, columns, rows[loc], env))
      if (any(vapply(parts, is.null, NA))) {
        stop("dibble: ", name, " is NULL in a group; NULL drops the whole column, without i or by", call. = FALSE)
      }
      combined(parts, groups, length(rows))
    }
    if (is.null(value)) {
      if (!missing(i) || length(by)) stop("dibble: ", name, " := NULL drops the whole column; no i or by", call. = FALSE)
      x <- set_column(x, name, NULL)
      next
    }
    x <- set_column(x, name, assigned(x[[name]], value, rows, n, name))
  }
  x
}

is_assign <- function(expr) is.call(expr) && identical(expr[[1]], as.name(":="))

# `a := v` or `:=`(a = v, b = w): a list of list(name, value), each value
# an unevaluated expression, in order (a name may come twice).
assign_steps <- function(expr, env) {
  args <- as.list(expr)[-1]
  if (is.null(names(args))) {
    if (length(args) != 2) stop("dibble: write name := value or `:=`(name = value, ...)", call. = FALSE)
    return(list(list(name = assign_name(args[[1]], env), value = args[[2]])))
  }
  if (!all(nzchar(names(args)))) stop("dibble: every value in `:=`(...) needs a name", call. = FALSE)
  lapply(seq_along(args), function(k) list(name = names(args)[[k]], value = args[[k]]))
}

# The groups' values as one column over the selected rows, with the
# attributes of the first group that has a type (a group of logical NAs
# takes the others' type) and storage that holds every group's: the
# widest, but double for long with float, which rounds past 2^24.
# (vctrs::list_unchop() would restore the class once per group; it is
# left the mixed types, to report.)
combined <- function(parts, groups, m) {
  typed <- !vapply(parts, is.logical, NA)
  if (!any(typed)) return(rep(NA, m))  # assigned() gives it the column's type
  first <- parts[[which(typed)[[1]]]]
  parts[!typed] <- lapply(parts[!typed], missing_like, first)
  same <- if (is.character(first)) vapply(parts, is.character, NA) else vapply(parts, inherits, NA, "dta_num")
  if (!all(same)) return(vctrs::list_unchop(parts, indices = groups))
  if (is.character(first)) {
    out <- character(m)
    for (k in seq_along(parts)) out[groups[[k]]] <- parts[[k]]
    return(text_attributes(out, first))
  }
  out <- double(m)
  for (k in seq_along(parts)) out[groups[[k]]] <- numbers(parts[[k]])
  out <- restore(out, first)
  storages <- vapply(parts, function(p) attr(p, "storage", exact = TRUE) %||% "double", "")
  storage <- STORAGE_ORDER[[max(match(storages, STORAGE_ORDER))]]
  if (storage == "float" && "long" %in% storages) storage <- "double"
  attr(out, "storage") <- storage
  out
}

STORAGE_ORDER <- c("byte", "int", "long", "float", "double")

# Logical NAs as the missing value of `like`'s type: "" or `.`.
missing_like <- function(x, like) if (is.character(like)) rep("", length(x)) else dta_column(x, "")

# `x` with the label and format of the string column `from`.
text_attributes <- function(x, from) {
  for (a in c("label", "format")) attr(x, a) <- attr(from, a, exact = TRUE)
  x
}

# The column name on the left of :=: a name, a string, or (expr) giving one.
assign_name <- function(lhs, env) {
  if (is.call(lhs) && identical(lhs[[1]], as.name("("))) lhs <- eval(lhs[[2]], env)
  if (is.name(lhs)) lhs <- as.character(lhs)
  if (!is.character(lhs) || length(lhs) != 1 || is.na(lhs) || !nzchar(lhs)) {
    stop("dibble: the left side of := must be one column name", call. = FALSE)
  }
  lhs
}

# The rows `i` selects, as row numbers.
assign_rows <- function(i, n) {
  if (inherits(i, "dta_num")) {
    v <- numbers(i)
    i <- is.na(v) | v != 0
  }
  if (is.logical(i)) {
    if (length(i) != n && length(i) != 1) stop("dibble: i has ", length(i), " values for ", n, " rows", call. = FALSE)
    return(which(rep_len(i, n)))
  }
  vctrs::vec_as_location(i, n, missing = "error")
}

# The grouping column names: g, c("g", "h"), .(g, h) or list(g, h), or a
# variable holding names (NULL for none).
by_names <- function(expr, env, columns) {
  if (is.call(expr) && (identical(expr[[1]], as.name(".")) || identical(expr[[1]], as.name("list")))) {
    args <- as.list(expr)[-1]
    if (!all(vapply(args, is.name, NA))) stop("dibble: by takes column names", call. = FALSE)
    return(vapply(args, as.character, ""))
  }
  if (is.name(expr) && as.character(expr) %in% columns) return(as.character(expr))
  names <- eval(expr, env)
  if (is.null(names)) return(character())
  if (!is.character(names)) stop("dibble: by takes column names", call. = FALSE)
  names
}

# The columns of `x`, to evaluate expressions among: every column is an
# active binding that gives it at the current rows (all rows until
# set), slicing it on first use, so an expression pays only for the
# columns it uses, however it finds them (a name, `.data[[v]]`, `get()`).
# Made once per step; each group only sets the rows.
column_env <- function(x) {
  state <- new.env(parent = emptyenv())
  state$rows <- NULL
  state$sliced <- new.env(parent = emptyenv())
  cols <- new.env(parent = emptyenv())
  for (name in names(x)) bind_column(cols, state, name, x[[name]])
  list(cols = cols, state = state, pronoun = rlang::as_data_pronoun(cols), n = nrow(x))
}

bind_column <- function(cols, state, name, col) {
  force(name)  # else each binding would see the caller's last column
  force(col)
  makeActiveBinding(name, function(value) {
    if (!missing(value)) stop("dibble: cannot assign to column ", name, " inside :=; use another name", call. = FALSE)
    if (is.null(state$rows)) return(col)
    sliced <- state$sliced[[name]]
    if (is.null(sliced)) {
      sliced <- vctrs::vec_slice(col, state$rows)
      assign(name, sliced, envir = state$sliced)
    }
    sliced
  }, cols)
}

# `expr` evaluated among the columns at `rows` (all rows if NULL), with
# `.N` the number of rows and `.data` the columns.
eval_columns <- function(expr, columns, rows, env) {
  columns$state$rows <- rows
  columns$state$sliced <- new.env(parent = emptyenv())
  mask <- rlang::new_data_mask(columns$cols)
  mask$.data <- columns$pronoun
  mask$.N <- if (is.null(rows)) columns$n else length(rows)
  rlang::eval_tidy(expr, mask, env)
}

# One step's value on `rows`, as a dibble column of length(rows) (NULL
# if the value is NULL).
group_value <- function(step, columns, rows, env) {
  value <- eval_columns(step$value, columns, rows, env)
  if (is.null(value)) return(NULL)
  # Logical NAs stay logical until the column they go into gives a type.
  if (is.logical(value) && all(is.na(value))) return(vctrs::vec_recycle(value, length(rows), x_arg = step$name))
  value <- dta_column(value, step$name)
  if (is.character(value)) {
    value[is.na(value)] <- ""
  } else {
    v <- numbers(value)
    bad <- is.infinite(v) | is.nan(v)
    if (any(bad)) {
      v[bad] <- NA_real_
      value <- restore(v, value)
    }
  }
  vctrs::vec_recycle(value, length(rows), x_arg = step$name)
}

# The column `old` (NULL if new) after `value` goes into `rows`.
assigned <- function(old, value, rows, n, name) {
  if (is.logical(value)) value <- missing_like(value, if (is.character(old)) "" else 0)
  if (is.null(old)) {
    old <- if (is.character(value)) text_attributes(rep("", n), value) else restore(rep(NA_real_, n), value)
  } else if (is.character(old) != is.character(value)) {
    stop("dibble: cannot put ", if (is.character(value)) "strings" else "numbers", " into ",
         if (is.character(old)) "string" else "numeric", " column ", name, call. = FALSE)
  }
  if (is.character(old)) {
    old[rows] <- value
    return(old)
  }
  storage <- widened(attr(old, "storage", exact = TRUE) %||% "double", numbers(value))
  out <- numbers(old)
  out[rows] <- numbers(value)
  out <- restore(out, old)
  attr(out, "storage") <- storage
  out
}

# The storage that holds `values` as well as what `storage` held: the
# same if they fit, else the narrowest of int and long that holds them,
# else double. Bounds are the writer's.
widened <- function(storage, values) {
  v <- values[!is.na(values)]
  if (storage == "double" || !length(v)) return(storage)
  if (storage == "float") {
    max <- 2^127 * (1 - 2^-24)  # the largest float below `.`
    return(if (all(abs(v) <= max)) "float" else "double")
  }
  if (any(v != round(v))) return("double")
  bounds <- list(byte = c(-127, 100), int = c(-32767, 32740), long = c(-2147483647, 2147483620))
  for (type in names(bounds)[match(storage, names(bounds)):3]) {
    if (min(v) >= bounds[[type]][[1]] && max(v) <= bounds[[type]][[2]]) return(type)
  }
  "double"
}

# `x` with column `name` set to `col` (NULL drops it), keeping the
# dibble's attributes; a sort key that changes ends the sort order.
set_column <- function(x, name, col) {
  cls <- class(x)
  keys <- attr(x, "sort_order", exact = TRUE)
  out <- unclass(x)
  out[[name]] <- col
  if (name %in% keys) {
    keys <- keys[seq_len(match(name, keys) - 1)]
    attr(out, "sort_order") <- if (length(keys)) keys
  }
  class(out) <- cls
  out
}
