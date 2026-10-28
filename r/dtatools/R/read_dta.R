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
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL) {
  file <- normalizePath(file, mustWork = TRUE)
  meta <- .Call(C_dta_meta, file, encoding)
  names <- meta$names
  cols <- seq_along(names)
  select <- rlang::enquo(col_select)
  if (!rlang::quo_is_null(select)) {
    # A character vector, literal or in a variable, selects by name;
    # anything else (all_of(), starts_with(), ...) goes to tidyselect.
    chosen <- tryCatch(rlang::eval_tidy(select), error = function(e) NULL, warning = function(w) NULL)
    if (is.character(chosen)) {
      cols <- match(chosen, names)
      if (anyNA(cols)) stop("read_dta: no column named ", paste(chosen[is.na(cols)], collapse = ", "))
    } else {
      cols <- unname(tidyselect::eval_select(select, stats::setNames(as.list(cols), names)))
    }
  }
  values <- .Call(C_dta_read, file, as.integer(cols - 1L), encoding)
  names(values) <- names[cols]
  out <- tibble::new_tibble(values, nrow = meta$nobs, class = "dibble")
  attr(out, "label") <- nonempty(meta$label)
  attr(out, "notes") <- if (length(meta$notes)) meta$notes
  out
}

nonempty <- function(x) if (nzchar(x)) x
