#' Read a Stata .dta file
#'
#' @param file Path to a `.dta` file.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `tidyselect::all_of(names)`. All
#'   columns when `NULL`. Columns come back in the order selected.
#' @param encoding Text encoding of files older than release 118:
#'   `"windows-1252"` (the default), `"latin1"` or `"utf-8"`.
#' @param skip Rows to skip at the start.
#' @param n_max The most rows to read; `Inf` for all.
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
#'
#'   The file's metadata is in attributes, each `NULL` when the file has
#'   none: `label` (the data label), `timestamp` (as the file has it, such
#'   as `"28 Oct 2026 14:38"`), `notes` (a character vector),
#'   `characteristics` (a data frame of character columns `variable`,
#'   `name` and `value`; `variable` is `"_dta"` for the dataset's own;
#'   notes are not among them) and `sort_order` (the names of the columns
#'   the data is sorted by). With `col_select`, characteristics keep only
#'   those of the columns read and `_dta`'s, and the sort order only its
#'   leading keys that were read. [save_dta()] writes them all back.
#' @seealso [save_dta()] to write. The repository's `docs/r.md` is a
#'   guide with recipes.
#' @examples
#' path <- tempfile(fileext = ".dta")
#' save_dta(dibble(id = 1:3, income = c(2100, .d, NA)), path)
#' df <- read_dta(path)
#' df$income
#' read_dta(path, col_select = income, skip = 1, n_max = 1)
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf) {
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0")
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0")
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
  values <- .Call(C_dta_read, file, as.integer(cols - 1L), floor(skip), floor(n_max), encoding)
  names(values) <- names[cols]
  rows <- min(max(meta$nobs - floor(skip), 0), floor(n_max))
  out <- tibble::new_tibble(values, nrow = rows, class = "dibble")
  attr(out, "label") <- nonempty(meta$label)
  attr(out, "timestamp") <- nonempty(meta$timestamp)
  attr(out, "notes") <- if (length(meta$notes)) meta$notes
  chars <- as.data.frame(meta$characteristics, stringsAsFactors = FALSE)
  attr(out, "characteristics") <- kept_characteristics(chars, names(out))
  attr(out, "sort_order") <- kept_sort_order(names[meta$sort_order], names(out))
  out
}

# The characteristics of the variables in `names`, and the dataset's
# other than notes (the `notes` attribute holds those); NULL if none.
kept_characteristics <- function(chars, names) {
  if (is.null(chars)) return(NULL)
  if (!is.data.frame(chars) || !all(c("variable", "name", "value") %in% names(chars))) {
    stop("characteristics must be a data frame with columns variable, name and value")
  }
  note <- chars$variable == "_dta" & grepl("^note[0-9]+$", chars$name)
  chars <- chars[chars$variable %in% c("_dta", names) & !note, c("variable", "name", "value"), drop = FALSE]
  rownames(chars) <- NULL
  if (nrow(chars)) chars
}

# The leading keys of a sort order that are among `names`: data sorted
# by a, b, c is still sorted by a once b is dropped, but not by a then c.
# NULL if none.
kept_sort_order <- function(keys, names) {
  gone <- which(!(keys %in% names))
  if (length(gone)) keys <- keys[seq_len(gone[[1]] - 1)]
  if (length(keys)) keys
}

nonempty <- function(x) if (nzchar(x)) x
