#' Read a Stata .dta file
#'
#' @param file Path to a `.dta` file.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `tidyselect::all_of(names)`. All
#'   columns when `NULL`. Columns come back in the order selected.
#' @param encoding Text encoding of files older than release 118:
#'   `"windows-1252"` (the default), `"latin1"` or `"utf-8"`.
#' @return A data frame. Numeric columns are `dta_num` vectors; string
#'   columns are character vectors.
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL) {
  file <- normalizePath(file, mustWork = TRUE)
  meta <- .Call(C_dta_meta, file, encoding)
  names <- meta$names
  cols <- seq_along(names)
  select <- rlang::enquo(col_select)
  if (!rlang::quo_is_null(select)) {
    cols <- unname(tidyselect::eval_select(select, stats::setNames(as.list(cols), names)))
  }
  values <- .Call(C_dta_read, file, as.integer(cols - 1L), encoding)
  names(values) <- names[cols]
  structure(values, class = "data.frame", row.names = .set_row_names(meta$nobs),
            label = nonempty(meta$label), notes = if (length(meta$notes)) meta$notes)
}

nonempty <- function(x) if (nzchar(x)) x
