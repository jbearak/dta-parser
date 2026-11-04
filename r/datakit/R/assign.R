#' Make and change columns with `:=`
#'
#' `d[i, name] := value` sets column `name` to `value` on the rows `i`
#' selects, making the column if it is new, and changes `d` itself, as
#' a do-file's `generate` and `replace ... if` change the data in
#' memory. `d[i, name, by = g] := value` computes `value` within groups,
#' as `bysort g:` does. Each line of a do-file stays one line of R.
#'
#' On a data frame or tibble, R's rules apply:
#'
#' - `i` is evaluated among the columns. A logical `i` selects the rows
#'   where it is `TRUE`, so `NA` selects no row, as in data.table and
#'   `dplyr::filter()`; numbers are row numbers. Without `i`, every row.
#'   Missing values compare as `NA`, unlike in Stata, where they are
#'   larger than every number: `d[income > 3000, high] := 1` leaves out
#'   the rows whose income is missing.
#' - `value` is evaluated among the columns of the selected rows only (of
#'   each group, with `by`) and is recycled from length 1. `.N` is the
#'   number of rows it sees, so without `i`,
#'   `d[, n, by = g] := seq_len(.N)` is `by g: gen n = _n`; the rows keep
#'   their order, where `bysort` sorts. A column hides a variable of the
#'   same name in the caller.
#' - A new column is `NA` on the other rows. `NaN` and `Inf` stay.
#' - An existing logical, integer or double column widens when it cannot
#'   hold the new values, as Stata's `replace` promotes a variable's
#'   storage: logical to integer to double. An integer column given
#'   whole numbers stays integer. Its attributes, such as `label` and
#'   `labels`, stay.
#' - A factor column takes labels: strings that are levels, or a factor,
#'   matched by label, never by its codes. A string that is not a level
#'   is an error, so a misspelt label cannot add a category; add a level
#'   first with `levels(d$x) <- c(levels(d$x), "new")`. A number is an
#'   error too, since factor codes are not the file's codes. `NA` is
#'   allowed.
#' - Other columns, such as character or `Date`, take values vctrs can
#'   convert to their type.
#' - `by` names grouping columns: `by = g`, `by = c("g", "h")` or
#'   `by = .(g, h)`. All `NA`s are one group. A `by` column cannot be
#'   changed.
#' - A value of `NULL` drops the column (not with `i` or `by`).
#' - When `i` picks no rows, an existing column is left as it is and its
#'   value is not evaluated.
#'
#' `name` is one column: a bare name (the column, even if a variable has
#' that name), a string (`"a"`), or, in parentheses, a variable holding
#' one (`(nm)`). For several columns, write one line each. `d` may be any
#' target `<-` takes, such as `l$d`; inside a function, as with `<-`, it
#' changes the function's copy. To keep `d` as it was, copy it first:
#' `e <- d; e[i, name] := value`. The result has `d`'s class. A
#' data.table is an error: use its own `d[i, name := value]`.
#'
#' dtatools re-exports this `:=` and gives its dibbles Stata's rules
#' through `colon_equals()`, so attaching both packages, in either order,
#' changes nothing. rlang and data.table each export a `:=` too, only to
#' report misuse, and the package attached last is the one R finds:
#' attach datakit after them, as in
#' `library(dplyr); library(dtaparser); library(datakit)`, or bind it
#' with `` `:=` <- datakit::`:=` ``. Their own uses of `:=`, such as
#' data.table's `dt[, b := 1]` or dplyr's `mutate(d, !!nm := 1)`, keep
#' working, as they read `:=` without calling it.
#'
#' @usage lhs := rhs
#' @param lhs `d[i, name]` or `d[i, name, by = g]`.
#' @param rhs The new values, evaluated among the columns.
#' @return `d`, changed, invisibly.
#' @examples
#' d <- tibble::tibble(age = c(25L, 41L, NA, 37L), g = c(1, 1, 2, 2),
#'                     region = factor(c("North", "South", "North", "East")))
#' d[age > 35, older] := TRUE            # NA age: not selected
#' d[, n_in_g, by = g] := .N
#' d[age < 30, age] := age + 0.5         # age widens to double
#' d[region == "East", region] := "South"
#' d
#' @name colon-equals
#' @export
`:=` <- function(lhs, rhs) {
  lhs <- substitute(lhs)
  usage <- "`:=`: write d[i, name] := value"
  if (!is.call(lhs) || !identical(lhs[[1]], as.name("[")) || length(lhs) < 2) stop(usage, call. = FALSE)
  arg_names <- if (is.null(names(lhs))) rep("", length(lhs)) else names(lhs)
  arg_names <- arg_names[-(1:2)]
  unnamed <- which(!nzchar(arg_names)) + 2L
  if (length(unnamed) != 2 || any(arg_names[nzchar(arg_names)] != "by") || sum(arg_names == "by") > 1 ||
      identical(lhs[[unnamed[[2]]]], quote(expr = ))) {
    stop(usage, call. = FALSE)
  }
  env <- parent.frame()
  target <- lhs[[2]]
  x <- eval(target, env)
  # NULL stands for no i; an i written as NULL picks no rows, so it
  # goes on as (NULL).
  i <- if (!identical(lhs[[unnamed[[1]]]], quote(expr = ))) lhs[[unnamed[[1]]]] %||% quote((NULL))
  by <- if ("by" %in% arg_names) by_names(lhs[["by"]], env, names(x)) else character()
  new <- colon_equals(x, i, assign_name(lhs[[unnamed[[2]]]], env), substitute(rhs), by, env)
  eval(call("<-", target, new), env)
  invisible(new)
}

#' The methods behind `:=`
#'
#' `colon_equals()` does the work of `d[i, name, by = g] := value`
#' once `:=` has taken its left side apart. datakit's method for data
#' frames follows R's rules; dtatools' method for dibbles follows
#' Stata's. Call `:=`, not this.
#'
#' @param x The data frame.
#' @param i The expression picking rows, or `NULL` for all.
#' @param name The column's name.
#' @param value The expression for the new values.
#' @param by The names of the grouping columns.
#' @param env The caller's environment.
#' @return `x` with the column set.
#' @keywords internal
#' @export
colon_equals <- function(x, i, name, value, by, env) UseMethod("colon_equals")

#' @export
colon_equals.default <- function(x, i, name, value, by, env) {
  stop("`:=`: d[i, name] := value needs a data frame, not ", class(x)[[1]], call. = FALSE)
}

#' @export
colon_equals.data.table <- function(x, i, name, value, by, env) {
  stop("`:=`: on a data.table, use its own d[i, name := value]", call. = FALSE)
}

#' @export
colon_equals.data.frame <- function(x, i, name, value, by, env) {
  n <- nrow(x)
  columns <- column_env(x)
  rows <- if (!is.null(i)) picked(eval_columns(i, columns, NULL, env), n)
  all_rows <- is.null(rows)
  if (all_rows) rows <- seq_len(n)
  if (!all(by %in% names(x))) stop("`:=`: no column ", setdiff(by, names(x))[[1]], " to group by", call. = FALSE)
  if (name %in% by) stop("`:=`: cannot change ", name, ", a by column", call. = FALSE)
  old <- x[[name]]
  if (!length(rows) && !all_rows && !is.null(old)) return(x)
  groups <- if (length(by) && length(rows)) {
    keys <- vctrs::new_data_frame(lapply(unclass(x)[by], unattributed), n = n)
    vctrs::vec_group_loc(vctrs::vec_slice(keys, rows))$loc
  }
  new <- if (!length(rows)) {
    # Evaluated once on zero rows only for the new column's type.
    tryCatch(suppressWarnings(eval_columns(value, columns, rows, env)), error = function(e) logical())
  } else if (is.null(groups)) {
    recycled(eval_columns(value, columns, rows, env), length(rows), name)
  } else {
    parts <- lapply(groups, function(loc) eval_columns(value, columns, rows[loc], env))
    if (any(vapply(parts, is.null, NA))) {
      stop("`:=`: ", name, " is NULL in a group; NULL drops the whole column, without i or by", call. = FALSE)
    }
    parts <- Map(function(p, loc) recycled(p, length(loc), name), parts, groups)
    vctrs::list_unchop(parts, indices = groups)
  }
  if (is.null(new)) {
    if (!all_rows || length(by)) stop("`:=`: NULL drops the whole column; write d[, ", name, "] := NULL, with no i or by", call. = FALSE)
    x[[name]] <- NULL
    return(x)
  }
  x[[name]] <- if (is.null(old)) made(new, rows, n) else replaced(old, new, rows, name)
  x
}

# x without its class and attributes, so that vctrs groups any column
# by its values (a labelled integer as integers).
unattributed <- function(x) {
  if (inherits(x, "dtaparser_labelled")) return(vctrs::vec_data(x))
  if (is.factor(x) || !is.atomic(x)) x else as.vector(x)
}

recycled <- function(value, size, name) {
  if (is.null(value)) return(NULL)
  vctrs::vec_recycle(value, size, x_arg = name)
}

# The rows the evaluated `i` selects, as row numbers.
picked <- function(i, n) {
  if (is.logical(i)) {
    if (length(i) != n && length(i) != 1) stop("`:=`: i has ", length(i), " values for ", n, " rows", call. = FALSE)
    return(which(rep_len(i, n)))
  }
  vctrs::vec_as_location(i, n, missing = "error")
}

# A new column of n rows: NA, with `value` on `rows`.
made <- function(value, rows, n) {
  out <- vctrs::vec_init(value, n)
  if (is.atomic(value) && !is.object(value)) {
    for (a in setdiff(names(attributes(value)), c("names", "dim", "dimnames"))) attr(out, a) <- attr(value, a)
  }
  replaced(out, value, rows, "")
}

# The column `old` with `value` on `rows`.
replaced <- function(old, value, rows, name) {
  if (is.factor(old)) return(into_factor(old, value, rows, name))
  if (inherits(old, "dtaparser_labelled") && is.character(value)) value <- label_codes(value, old)
  if (inherits(old, "dtaparser_labelled") && (is.logical(value) || is.numeric(value)) &&
      (!is.object(value) || inherits(value, "dtaparser_labelled"))) {
    return(into_labelled(old, value, rows))
  }
  if ((is.logical(old) || is.numeric(old)) && !is.object(old) && (is.logical(value) || is.numeric(value)) &&
      !is.object(value)) {
    old <- widened(old, value)
    old[rows] <- if (is.integer(old)) as.integer(value) else value
    return(old)
  }
  vctrs::vec_assign(old, rows, vctrs::vec_cast(value, old, x_arg = "value", to_arg = name))
}

# The labelled column `old` with `value` on `rows`: its codes widen as
# an unclassed column's do, and a labelled value's labels join `old`'s
# (vec_ptype2() makes the union, and stops when a code has two texts).
into_labelled <- function(old, value, rows) {
  labels <- if (inherits(value, "dtaparser_labelled")) {
    dtaparser::val_labels(vctrs::vec_ptype2(old, value))
  } else {
    dtaparser::val_labels(old)
  }
  if (inherits(value, "dtaparser_labelled")) value <- vctrs::vec_data(value)
  codes <- widened(vctrs::vec_data(old), value)
  codes[rows] <- if (is.integer(codes)) as.integer(value) else value
  out <- dtaparser::with_labels(codes, labels, label = attr(old, "label", exact = TRUE))
  attr(out, "format") <- attr(old, "format", exact = TRUE)
  out
}

# The codes the strings `text` label in the labelled column `old`, as
# doubles, since a label may be of .a to .z. dtaparser's cast from text
# stops on a string that labels no code, or two.
label_codes <- function(text, old) {
  to <- dtaparser::with_labels(double(), dtaparser::val_labels(old))
  vctrs::vec_data(vctrs::vec_cast(text, to))
}

# `old` as the narrowest of logical, integer and double that holds both
# its values and `value`, with its attributes.
widened <- function(old, value) {
  type <- if (is.double(old) || (is.double(value) && !fits_integer(value))) {
    "double"
  } else if (is.integer(old) || !is.logical(value)) {
    "integer"
  } else {
    "logical"
  }
  if (typeof(old) == type) return(old)
  attrs <- attributes(old)
  old <- if (type == "double") as.double(old) else as.integer(old)
  attributes(old) <- attrs
  old
}

# Whether the doubles `v` are whole numbers an integer holds, with no
# NaN or .a to .z, which only a double keeps.
fits_integer <- function(v) {
  known <- v[!is.na(v)]
  all(known == trunc(known) & abs(known) <= .Machine$integer.max) && !any(is.nan(v)) &&
    !any(dtaparser::is_tagged_na(v[is.na(v)]))
}

into_factor <- function(old, value, rows, name) {
  if (is.logical(value) && all(is.na(value))) value <- as.character(value)
  if (!is.character(value) && !is.factor(value)) {
    stop("`:=`: ", name, " is a factor; give a label such as \"", levels(old)[1], "\", not a number", call. = FALSE)
  }
  value <- as.character(value)
  unknown <- setdiff(value[!is.na(value)], levels(old))
  if (length(unknown)) {
    stop("`:=`: \"", unknown[[1]], "\" is not a level of ", name, " (", paste0("\"", levels(old), "\"", collapse = ", "),
         "); add it first with levels(d$", name, ") <- c(levels(d$", name, "), \"", unknown[[1]], "\")", call. = FALSE)
  }
  old[rows] <- value
  old
}

# The grouping column names: g, c("g", "h"), .(g, h) or list(g, h), or a
# variable holding names (NULL for none).
by_names <- function(expr, env, columns) {
  if (is.call(expr) && (identical(expr[[1]], as.name(".")) || identical(expr[[1]], as.name("list")))) {
    args <- as.list(expr)[-1]
    if (!all(vapply(args, is.name, NA))) stop("`:=`: by takes column names", call. = FALSE)
    return(vapply(args, as.character, ""))
  }
  if (is.name(expr) && as.character(expr) %in% columns) return(as.character(expr))
  names <- eval(expr, env)
  if (is.null(names)) return(character())
  if (!is.character(names)) stop("`:=`: by takes column names", call. = FALSE)
  names
}

# The column name in d[i, name] := value: a name, a string, or (expr)
# giving one.
assign_name <- function(lhs, env) {
  if (is.call(lhs) && identical(lhs[[1]], as.name("("))) lhs <- eval(lhs[[2]], env)
  if (is.name(lhs)) lhs <- as.character(lhs)
  if (!is.character(lhs) || length(lhs) != 1 || is.na(lhs) || !nzchar(lhs)) {
    stop("`:=`: name in d[i, name] := value must be one column name", call. = FALSE)
  }
  lhs
}

# The columns of `x`, to evaluate expressions among: every column is an
# active binding that gives it at the current rows (all rows until
# set), slicing it on first use, so an expression pays only for the
# columns it uses. Made once; each group only sets the rows.
column_env <- function(x) {
  state <- new.env(parent = emptyenv())
  state$rows <- NULL
  state$sliced <- new.env(parent = emptyenv())
  cols <- new.env(parent = emptyenv())
  for (name in names(x)) bind_column(cols, state, name, x[[name]])
  list(cols = cols, state = state, pronoun = rlang::as_data_pronoun(cols), n = nrow(x))
}

bind_column <- function(cols, state, name, col) {
  force(name)
  force(col)
  makeActiveBinding(name, function(value) {
    if (!missing(value)) stop("`:=`: cannot assign to column ", name, " inside :=; use another name", call. = FALSE)
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
