#' Make and change columns with `:=` or `[<-`
#'
#' `d[i, name] := value` sets column `name` to `value` on the rows `i`
#' selects, making the column if it is new, and changes `d` itself, as
#' Stata's `generate` and `replace` change the data in memory.
#' `d[i, name, by = g] := value` computes `value` within groups.
#'
#' - `i` is evaluated among the columns. Comparisons follow Stata's rules
#'   (see [dta_num()]), so `d[age > 30, ...]` includes rows whose age is
#'   missing. A `dta_num` is true where nonzero or missing, as in Stata's
#'   `if`; logical `NA` selects no row; other numbers are row numbers.
#'   Without `i`, every row.
#' - `value` is evaluated, as in data.table, among the columns of the
#'   selected rows only (of each group, with `by`), and is recycled from
#'   length 1. `.N` is the number of rows it sees. Stata's `if` does not
#'   narrow `_n`, `_N` or `x[1]` that way, so
#'   `d[, n, by = g] := seq_len(.N)` is `by g: gen n = _n` only without
#'   `i`; and the rows keep their order, where `bysort` sorts. A column
#'   hides a variable of the same name in the caller.
#' - Values are converted as [dibble()] converts columns. `Inf`, `-Inf`
#'   and `NaN` become `.`, and string `NA` becomes `""`, since Stata
#'   holds neither.
#' - A new column is `.` (or `""` for strings) on the other rows, and
#'   takes the value's attributes, so `d[, b] := a` copies `a`'s labels
#'   while `d[, b] := a + 1` has none; with `by`, the first group's.
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
#' - A value of `NULL` drops the column (not with `i` or `by`).
#' - When `i` picks no rows, an existing column is left as it is and its
#'   value is not evaluated. A new column is evaluated once on zero rows
#'   only for its type; if that fails, it is `.`, and the error is not
#'   shown.
#'
#' `name` is one column: a bare name (the column, even if a variable has
#' that name), a string (`"a"`), or, in parentheses, a variable holding
#' one (`(nm)`). For several columns, write one line each. `d` may be any
#' target `<-` takes, such as `l$d`; inside a function, as with `<-`, it
#' changes the function's copy. To keep `d` as it was, copy it first:
#' `e <- d; e[i, name] := value`. A column that was a sort key ends the
#' sort order there. `.N` and `.data` hide columns of those names.
#'
#' data.table's `d[i, name := value]`, with `:=` inside the brackets, is
#' an error that shows the `d[i, name] := value` line to write instead:
#' on a dibble it used to return a changed copy and leave `d` as it was,
#' so on its own line it did nothing. Any other `[` is tibble's.
#'
#' @section Where R finds `:=`:
#' rlang and data.table each export a `:=` too, only to report misuse,
#' and the package attached last is the one R finds. Attach dtatools
#' after them, or, in tests that call `dtatools::` functions without
#' attaching it, bind it in a helper file:
#' `` `:=` <- dtatools::`:=` ``. Code in a package that imports rlang's
#' `:=` must bind dtatools' the same way. Their own uses of `:=`, such
#' as data.table's `dt[, b := 1]` or dplyr's `mutate(d, !!nm := 1)`,
#' keep working, as they read `:=` without calling it.
#'
#' @section Assigning with `<-`:
#' `d[i, name] <- value` also changes `d`, and needs no attached
#' package, as R finds `[<-` by the dibble's class. It does what
#' `d[i, name] := value` does, with `i` evaluated among the columns
#' as there, except for the following:
#'
#' - R evaluates `value` before the dibble sees it, in the caller's
#'   environment, so it cannot use the columns: `d[x == 1, y] <- 0` works,
#'   but for `d[x == 1, y] <- z * 2`, write `d[x == 1, y] := z * 2`.
#'   `value` has one element, or one per row `i` picks (not one per row
#'   of `d`). It is evaluated even when `i` picks no rows.
#' - There is no `by`.
#' - `name` is a column name, a string (`"a"`), or a variable in
#'   parentheses (`(nm)`). A bare name that is not a column but is a
#'   variable in the caller, as in `for (nm in vars) d[x > 0, nm] <- 1`
#'   or a helper's `d[i, col] <- v`, is an error, since tibble would read
#'   it as the variable and `:=` as the column; write `(nm)` or `"nm"`.
#' - It cannot add rows: write `d[nrow(d) + 1, ] <- list(...)`.
#' - `d[, name] <- NULL` drops the column; with `i` it is an error.
#'
#' Any other `[<-` (`d[i] <- v`, a numeric `j`, or several columns) is
#' tibble's, with `i` evaluated in the caller.
#'
#' @aliases [.dibble [<-.dibble
#' @usage
#' \method{[}{dibble}(x, i, j, ..., by)
#'
#' \method{[}{dibble}(x, i, j, ...) <- value
#'
#' lhs := rhs
#' @param x A dibble.
#' @param i Rows: a condition or row numbers.
#' @param j With `<-`, the column name. `name := value` here is an
#'   error that shows the `d[i, name] := value` line to write.
#' @param ... Passed to tibble's `[` and `[<-`.
#' @param by Not taken by `[`: write `d[i, name, by = g] := value`.
#' @param value With `<-`, the new values.
#' @param lhs `d[i, name]` or `d[i, name, by = g]`.
#' @param rhs The new values, evaluated among the columns.
#' @return A dibble; `d[i, name] := value` returns it invisibly.
#' @examples
#' d <- dibble(age = c(25, 41, NA, 37), kids = c(0, 2, 1, .d), g = c(1, 1, 2, 2))
#' d[age > 35, older] := TRUE            # missing age counts as > 35
#' d[kids == .d, kids] := .r
#' d[, n_in_g, by = g] := .N
#' d[, months] := age * 12
#' d[age < 30, young] <- 1               # <- for a value without columns
#' d
#' @name dibble-assign
NULL

#' @export
`[.dibble` <- function(x, i, j, ..., by) {
  # d[i, name := value] would return a recoded copy and leave d as it
  # was, unlike data.table; it is an error that shows the line to write.
  in_i <- !missing(i) && is_assign(substitute(i))
  if (in_i || (!missing(j) && is_assign(substitute(j)))) {
    target <- deparse1(substitute(x), backtick = TRUE)
    rows <- if (in_i || missing(i)) "" else deparse1(substitute(i), backtick = TRUE)
    by <- if (missing(by)) "" else paste0(", by = ", deparse1(substitute(by), backtick = TRUE))
    lines <- assign_lines(target, rows, if (in_i) substitute(i) else substitute(j), by)
    stop("dibble: write ", paste(lines, collapse = "; "), " to change ", target, ". The form ", target,
         "[i, name := value] is retired, since on its own it left ", target, " unchanged; to keep ", target,
         ", copy it first: e <- ", target, call. = FALSE)
  }
  if (!missing(by)) stop("dibble: by goes with :=; write d[i, name, by = g] := value", call. = FALSE)
  NextMethod()
}

#' @export
`[<-.dibble` <- function(x, i, j, ..., value) {
  # Only d[i, name] <- value and d[, name] <- value; d[i] <- value,
  # d[[name]], numeric or several j are tibble's.
  if (nargs() != 4 || missing(j)) return(NextMethod())
  env <- parent.frame()
  name <- target_name(substitute(j), names(x), env)
  if (is.null(name)) return(NextMethod())
  if (is.null(value) && !missing(i)) stop("dibble: NULL drops the whole column; write d[, ", name, "] <- NULL", call. = FALSE)
  if (is.data.frame(value) && length(value) == 1) value <- value[[1]]
  rows <- if (!missing(i)) {
    picked <- eval_columns(substitute(i), column_env(x), NULL, env)
    if (is.numeric(picked) && !inherits(picked, "dta_num") && any(picked > nrow(x), na.rm = TRUE)) {
      stop("dibble: d[i, ", name, "] <- value cannot add rows; write d[nrow(d) + 1, ] <- list(...)", call. = FALSE)
    }
    assign_rows(picked, nrow(x))
  }
  assign_columns(x, rows, list(list(name = name, value = value, evaluated = TRUE)), character(), env)
}

#' @rdname dibble-assign
#' @usage NULL
#' @export
`:=` <- function(lhs, rhs) {
  # d[i, name, by = g] := value: d with `name` set to `value` on the rows
  # i picks, assigned back to d in the caller.
  lhs <- substitute(lhs)
  if (!is.call(lhs) || !identical(lhs[[1]], as.name("[")) || length(lhs) < 2) {
    stop("dibble: write d[i, name] := value", call. = FALSE)
  }
  arg_names <- names(lhs) %||% rep("", length(lhs))
  arg_names <- arg_names[-(1:2)]
  unnamed <- which(!nzchar(arg_names)) + 2L
  if (length(unnamed) != 2 || any(arg_names[nzchar(arg_names)] != "by") || sum(arg_names == "by") > 1 ||
      identical(lhs[[unnamed[[2]]]], quote(expr = ))) {
    stop("dibble: write d[i, name] := value", call. = FALSE)
  }
  env <- parent.frame()
  target <- lhs[[2]]
  x <- eval(target, env)
  if (!inherits(x, "dibble")) stop("dibble: d[i, name] := value needs a dibble; convert with as_dibble()", call. = FALSE)
  rows <- if (!identical(lhs[[unnamed[[1]]]], quote(expr = ))) picked_rows(x, lhs[[unnamed[[1]]]], env)
  by <- if ("by" %in% arg_names) by_names(lhs[["by"]], env, names(x)) else character()
  steps <- list(list(name = assign_name(lhs[[unnamed[[2]]]], env), value = substitute(rhs)))
  new <- assign_columns(x, rows, steps, by, env)
  eval(call("<-", target, new), env)
  invisible(new)
}

# The rows the expression `i` picks, evaluated among the columns of `x`.
picked_rows <- function(x, i, env) assign_rows(eval_columns(i, column_env(x), NULL, env), nrow(x))

# The column named by `j` in d[i, j] <- value: a name, a string, or
# (expr) giving one; NULL for any other `j`, which tibble handles. A
# name that is neither a column nor free in the caller, where it may
# hold a column name as tibble reads it, is an error rather than a guess.
target_name <- function(j, columns, env) {
  if (is.character(j) && length(j) == 1) return(assign_name(j, env, "d[i, name] <- value"))
  if (is.call(j) && identical(j[[1]], as.name("("))) {
    name <- eval(j[[2]], env)
    if (!is.character(name)) stop("dibble: (name) in d[i, (name)] <- value must give a string", call. = FALSE)
    return(assign_name(name, env, "d[i, (name)] <- value"))
  }
  if (!is.name(j)) return(NULL)
  name <- as.character(j)
  if (!name %in% columns && exists(name, envir = env) && !is.function(get(name, envir = env))) {
    stop("dibble: ", name, " is a variable, not a column; write d[i, (", name, ")] <- value for the column it names, ",
         "or d[i, \"", name, "\"] <- value for a new column ", name, call. = FALSE)
  }
  name
}

# Each step (list(name, value), the value an expression, or the value
# itself if `evaluated`) into `x` on `rows` (NULL for all), within the
# groups of the `by` columns.
assign_columns <- function(x, rows, steps, by, env) {
  n <- nrow(x)
  picked <- !is.null(rows)
  if (!picked) rows <- seq_len(n)
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
    if (!length(rows) && picked && !is.null(x[[name]]) && !is.null(step$value)) {
      # A value given with <- still has to fit the rows it would fill.
      if (isTRUE(step$evaluated)) vctrs::vec_recycle(step$value, 0L, x_arg = name)
      next
    }
    value <- if (!length(rows) && !isTRUE(step$evaluated)) {
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
      if (picked || length(by)) stop("dibble: NULL drops the whole column; write d[, ", name, "] := NULL, with no i or by", call. = FALSE)
      x <- set_column(x, name, NULL)
      next
    }
    x <- set_column(x, name, assigned(x[[name]], value, rows, n, name))
  }
  x
}

is_assign <- function(expr) is.call(expr) && identical(expr[[1]], as.name(":="))

# The `d[i, name] := value` lines that do what the retired
# d[i, name := value] (or `:=`(a = v, b = w)) would have, as text.
assign_lines <- function(target, rows, expr, by) {
  args <- as.list(expr)[-1]
  pairs <- if (is.null(names(args)) && length(args) == 2) {
    list(c(deparse1(args[[1]], backtick = TRUE), deparse1(args[[2]], backtick = TRUE)))
  } else if (!is.null(names(args)) && all(nzchar(names(args)))) {
    lapply(seq_along(args), function(k) c(deparse1(as.name(names(args)[[k]]), backtick = TRUE), deparse1(args[[k]], backtick = TRUE)))
  } else {
    list(c("name", "value"))
  }
  vapply(pairs, function(p) paste0(target, "[", rows, ", ", p[[1]], by, "] := ", p[[2]]), "")
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

# The column name in d[i, name] := value: a name, a string, or (expr)
# giving one.
assign_name <- function(lhs, env, form = "d[i, name] := value") {
  if (is.call(lhs) && identical(lhs[[1]], as.name("("))) lhs <- eval(lhs[[2]], env)
  if (is.name(lhs)) lhs <- as.character(lhs)
  if (!is.character(lhs) || length(lhs) != 1 || is.na(lhs) || !nzchar(lhs)) {
    stop("dibble: name in ", form, " must be one column name", call. = FALSE)
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
  value <- if (isTRUE(step$evaluated)) step$value else eval_columns(step$value, columns, rows, env)
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
