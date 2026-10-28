#' Read a Stata .dta file
#'
#' @param file Path to a `.dta` file.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `tidyselect::all_of(names)`. All
#'   columns when `NULL`. Columns come back in the order selected.
#' @param encoding Text encoding of files older than release 118:
#'   `"windows-1252"` (the default), `"latin1"` or `"utf-8"`.
#' @return A dibble (see [dibble()]): numeric columns are `dta_num`
#'   vectors; string columns are character vectors.
#'
#'   String columns come back packed: they hold the text as read and
#'   make each R string when it is first used. Reading is fast and
#'   looking at, slicing or filtering a few rows stays cheap; the first
#'   operation over every value of a column with many distinct values
#'   (`==`, `unique()`, sorting, grouping) pays the cost of making them.
#'   A column with few distinct values is kept as those values and a
#'   code per row, so R makes one string per distinct value, and [tab()],
#'   [dta_group_id()] and [is_missing()] work on the codes.
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL) {
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
  values <- .Call(C_dta_read, file, as.integer(cols - 1L), encoding)
  names(values) <- names[cols]
  out <- tibble::new_tibble(values, nrow = meta$nobs, class = "dibble")
  attr(out, "label") <- nonempty(meta$label)
  attr(out, "notes") <- if (length(meta$notes)) meta$notes
  out
}

nonempty <- function(x) if (nzchar(x)) x
