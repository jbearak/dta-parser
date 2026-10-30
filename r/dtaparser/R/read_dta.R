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
#' @param warn_extended_missing Whether to warn when `factors = TRUE`
#'   turns `.a` to `.z` into plain `NA`.
#' @return A tibble. Byte, int and long columns are integers; float and
#'   double columns are doubles; string columns are character. Every
#'   missing value, `.` and `.a` to `.z` alike, is `NA`, so R's rules
#'   apply (`x > 5` is `NA` where `x` is missing). In doubles, `.a` to
#'   `.z` keep their letter as haven's tagged NAs do: `haven::na_tag()`
#'   gives it back. An integer column holding any of them in the rows
#'   read is a double instead, so its type can depend on `skip` and
#'   `n_max`. Strings are as stored: Stata's missing string is `""`.
#'
#'   With `factors = TRUE`, a column with value labels on any non-missing
#'   value is a factor whose
#'   levels are, in order of value, the labelled codes and the unlabelled
#'   values read (as `as.character()` of the integer or double); codes
#'   with the same text share a level, and missing values, labelled or
#'   not, are `NA`. A factor cannot keep `.a` to `.z`, so this warns
#'   when it loses them (see `warn_extended_missing`). With
#'   `factors = FALSE` the column keeps its numbers and has a `labels`
#'   attribute: the codes, `.a` to `.z` among them, named by their text.
#'
#'   A column whose labels are all on missing values keeps its numbers
#'   and its `labels` attribute either way (a date column stays a date
#'   and drops them).
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
#'   gives labelled columns class `haven_labelled`,
#'   reads `%-td` and `%-tc` as numbers and `%tC` as `POSIXct`, and its
#'   `as_factor()` keeps labelled missing values as levels.
#' @export
read_dta <- function(file, col_select = NULL, encoding = NULL, skip = 0, n_max = Inf,
                     factors = TRUE, dates = TRUE, warn_extended_missing = TRUE) {
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0")
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0")
  if (!rlang::is_bool(factors)) stop("factors must be TRUE or FALSE")
  if (!rlang::is_bool(dates)) stop("dates must be TRUE or FALSE")
  if (!rlang::is_bool(warn_extended_missing)) stop("warn_extended_missing must be TRUE or FALSE")
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
  names(values) <- names[cols]
  if (factors) {
    lost <- character()
    for (i in seq_along(values)) {
      if (!any(!is.na(attr(values[[i]], "labels", exact = TRUE)))) next
      if (warn_extended_missing && .Call(C_dta_has_letters, values[[i]])) lost <- c(lost, names(values)[i])
      values[[i]] <- labelled_factor(values[[i]], meta$storage[cols[i]] %in% c("byte", "int", "long"))
    }
    if (length(lost)) warn_lost(lost)
  }
  rows <- min(max(meta$nobs - floor(skip), 0), floor(n_max))
  out <- tibble::new_tibble(values, nrow = rows)
  attr(out, "label") <- nonempty(meta$label)
  attr(out, "notes") <- if (length(meta$notes)) meta$notes
  out
}

# One warning naming the columns whose factors lost .a to .z.
warn_lost <- function(cols) {
  shown <- paste0("`", utils::head(cols, 5), "`")
  if (length(cols) > 5) shown <- c(shown, paste(length(cols) - 5, "more"))
  if (length(shown) > 1) shown <- paste(paste(shown[-length(shown)], collapse = ", "), "and", shown[length(shown)])
  rlang::warn(
    paste0("Extended missing values (.a to .z) in ", shown, " are plain NA in their factors; ",
           "read with factors = FALSE to keep them, or warn_extended_missing = FALSE to silence this."),
    class = "dtaparser_extended_missing"
  )
}

# A factor from a labelled integer or double column: levels in order of
# value, labelled codes by their text and other values by
# as.character() (of the integer when `integer`, the file's storage
# being byte, int or long, though x is double when it held .a to .z);
# repeated texts are one level. Missing values, labelled or not, are NA.
labelled_factor <- function(x, integer) {
  labels <- attr(x, "labels", exact = TRUE)
  labels <- labels[!is.na(labels)]
  values <- sort(unique(c(unname(labels), as.double(unique(x[!is.na(x)])))))
  text <- if (integer) as.character(as.integer(values)) else as.character(values)
  text[match(labels, values)] <- names(labels)
  levels <- unique(text)
  out <- match(text, levels)[match(x, values)]
  attr(out, "levels") <- levels
  class(out) <- "factor"
  attr(out, "label") <- attr(x, "label", exact = TRUE)
  out
}

nonempty <- function(x) if (nzchar(x)) x
