#' Read a Stata .dta file into standard R types
#'
#' @param file Path to a `.dta` file.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `tidyselect::all_of(names)`. All
#'   columns when `NULL`. Columns come back in the order selected.
#' @param encoding Text encoding of files older than release 118:
#'   `"windows-1252"` (the default), `"latin1"` or `"utf-8"`.
#' @param skip Rows to skip at the start.
#' @param n_max The most rows to read; `Inf` for all.
#' @param factors Whether columns with value labels become factors.
#' @param dates Whether columns with date and datetime formats become
#'   `Date` and `POSIXct`.
#' @return A tibble. Byte, int and long columns are integers; float and
#'   double columns are doubles; string columns are character. Every
#'   missing value, `.` and `.a` to `.z` alike, is `NA`, so R's rules
#'   apply (`x > 5` is `NA` where `x` is missing). Strings are as stored:
#'   Stata's missing string is `""`.
#'
#'   With `factors = TRUE`, a column with value labels on any non-missing
#'   value is a factor whose
#'   levels are, in order of value, the labelled codes and the unlabelled
#'   values read (as `as.character()` of the integer or double); codes
#'   with the same text share a level, and labelled missing values are
#'   `NA`. With `factors = FALSE` it keeps its numbers and has a `labels`
#'   attribute: the codes named by their text.
#'
#'   Labels on missing values alone are dropped, since those values are
#'   `NA`.
#'
#'   With `dates = TRUE`, a column without such value labels whose format
#'   starts with `%td`, `%-td` or `%d` is a `Date`, and one whose format
#'   starts with `%tc` or `%-tc` is a `POSIXct` in UTC. `%tC`, which
#'   counts leap seconds, and the other `%t` formats stay numbers.
#'
#'   Columns carry their variable label as attribute `label`; the tibble
#'   carries the dataset label as `label` and its notes as `notes`.
#'
#'   String columns come back packed: R makes each string when it is
#'   first used, so reading is fast and the first operation over every
#'   value of a column pays the cost instead. A column with few distinct
#'   values is kept as those values and a code per row.
#'
#'   haven differs in a few places: it reads every number as a double,
#'   reads `%-td` and `%-tc` as numbers and `%tC` as `POSIXct`, and its
#'   `as_factor()` keeps labelled missing values as levels.
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf,
                     factors = TRUE, dates = TRUE) {
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0")
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0")
  if (!rlang::is_bool(factors)) stop("factors must be TRUE or FALSE")
  if (!rlang::is_bool(dates)) stop("dates must be TRUE or FALSE")
  file <- normalizePath(file, mustWork = TRUE)
  meta <- .Call(C_dta_meta, file, encoding)
  names <- meta$names
  cols <- seq_along(names)
  select <- rlang::enquo(col_select)
  if (!rlang::quo_is_null(select)) {
    # A variable holding names, as in col_select = cols, goes through
    # all_of(), which is what tidyselect asks for, unless a column has
    # the variable's name (tidyselect's precedence).
    expr <- rlang::quo_get_expr(select)
    if (rlang::is_symbol(expr) && !(rlang::as_string(expr) %in% names)) {
      value <- tryCatch(rlang::eval_tidy(select), error = function(e) NULL)
      if (is.character(value)) select <- rlang::quo(tidyselect::all_of(!!value))
    }
    cols <- unname(tidyselect::eval_select(select, stats::setNames(as.list(cols), names)))
  }
  mode <- if (dates) 2L else 0L
  values <- .Call(C_dta_read, file, as.integer(cols - 1L), floor(skip), floor(n_max), encoding, mode)
  if (factors) {
    for (i in seq_along(values)) {
      if (!is.null(attr(values[[i]], "labels", exact = TRUE))) values[[i]] <- labelled_factor(values[[i]])
    }
  }
  names(values) <- names[cols]
  rows <- min(max(meta$nobs - floor(skip), 0), floor(n_max))
  out <- tibble::new_tibble(values, nrow = rows)
  attr(out, "label") <- nonempty(meta$label)
  attr(out, "notes") <- if (length(meta$notes)) meta$notes
  out
}

# A factor from a labelled integer or double column: levels in order of
# value, labelled codes by their text and other values by
# as.character(); repeated texts are one level.
labelled_factor <- function(x) {
  labels <- attr(x, "labels", exact = TRUE)
  values <- sort(unique(c(unname(labels), as.double(unique(x[!is.na(x)])))))
  text <- if (is.integer(x)) as.character(as.integer(values)) else as.character(values)
  text[match(labels, values)] <- names(labels)
  levels <- unique(text)
  out <- match(text, levels)[match(x, values)]
  attr(out, "levels") <- levels
  class(out) <- "factor"
  attr(out, "label") <- attr(x, "label", exact = TRUE)
  out
}

nonempty <- function(x) if (nzchar(x)) x
