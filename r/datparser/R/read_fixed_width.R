#' Read a fixed-width text file through its SAS setup file
#'
#' Reads fixed-width ASCII data, such as the National Survey of Family
#' Growth files of 1973 to 2017-2019 that CDC publishes as `.dat` files,
#' using the SAS setup file (`.sas`) that describes it: each variable's
#' columns from `INPUT`, its label from `LABEL`, its value labels from
#' `PROC FORMAT` and `FORMAT`, record-type selection
#' (`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`) and the setup's
#' missing-value recodes (`IF (X = 98 OR X = 99) THEN X = .;`).
#'
#' @param file Path to the fixed-width data file.
#' @param setup Path to the SAS setup file, or several paths read in order
#'   as one setup, such as CDC's 2002 files
#'   `c("2002FemPregInput.sas", "2002FemPregVarLabel.sas",
#'   "2002FemPregValueLabel.sas")`. A statement may not run from one file
#'   into the next. With several, errors and warnings name a file by its
#'   place in `setup` (`"file 2 line 8"`).
#' @param recodes What to do with the setup's missing-value recodes:
#'   `"setup"` applies them as written (a code recoded to `.` is `NA`;
#'   one recoded to `.A` is a tagged NA); `"tagged"` keeps why each value
#'   is missing: per variable, the codes recoded to `.` become tagged NAs
#'   `.a`, `.b`, ... in the order the setup names them, each with its
#'   code's label (`"(98) DK"`); `"none"` ignores them, so the codes stay
#'   numbers.
#' @param col_select Columns to read: a character vector of names, or a
#'   tidyselect expression such as `tidyselect::all_of(names)`. All
#'   columns when `NULL`. Columns come back in the order selected. Only
#'   these are read, and only they are warned about.
#' @param skip Rows to skip at the start, after records are selected.
#' @param n_max The most rows to read; `Inf` for all.
#' @param factors Whether columns with value labels become factors. A
#'   factor cannot hold the tagged NAs that `recodes = "tagged"` makes,
#'   so the default keeps the numbers.
#' @param warn_extended_missing Whether to warn when `factors = TRUE`
#'   turns tagged NAs into plain `NA`. The warning has class
#'   `datparser_extended_missing` (and `dtaparser_extended_missing`, as
#'   `dtaparser::read_dta()` gives).
#' @param commented_formats Whether to read a `PROC FORMAT` step or a
#'   `FORMAT` statement that the setup has put in a block comment
#'   (`/* ... */`) as code. CDC's setups from 2006-2010 on comment both
#'   out so that SAS users without CDC's format catalog can run the file
#'   as published; the value labels are still there, so this is `TRUE` by
#'   default. Only a comment that holds nothing but such a step or
#'   statement is read; one that mentions `PROC FORMAT` in prose stays a
#'   comment. `FALSE` reads every comment as a comment, so those files
#'   have no value labels.
#' @return A tibble. Numeric columns take the smallest type that holds
#'   their values: integers when every value is a whole number within
#'   -2,147,483,647 to 2,147,483,620, doubles otherwise, and doubles when
#'   the rows read hold tagged NAs, so a column's type can depend on
#'   `skip` and `n_max`. String columns are character, a blank field
#'   `""`. Every missing value is `NA`; the setup's `.A` to `.Z` and the
#'   letters `recodes = "tagged"` gives are tagged NAs, as haven makes
#'   them (`haven::na_tag()` and `dtaparser::na_tag()` read the letter).
#'
#'   A column's label is its attribute `label`. A numeric column with
#'   value labels has attribute `labels`: the codes, tagged NAs among
#'   them, named by their text, in code order. Value labels on recoded
#'   codes move to their tagged NA, or go when the code becomes a plain
#'   `NA`. The column is a plain integer or double vector, which keeps
#'   the attribute through `filter()` and `arrange()` but not through
#'   `x[i]` or `bind_rows()`. datakit's `read_fixed_width()` gives such
#'   columns as `dtaparser_labelled` instead, which keeps them (see
#'   `dtaparser::with_labels()`).
#'
#'   With `factors = TRUE`, a column with value labels on any number is
#'   a factor whose levels are, in order of value, the labelled codes and
#'   the unlabelled values read; codes with the same text share a level,
#'   and every missing value is `NA`.
#'
#'   Statements the reader does not run (other data-step code, ranges in
#'   `VALUE`) are skipped with one warning of class
#'   `datparser_fixed_width_warning` (and `datakit_fixed_width_warning`,
#'   its class before datparser); the tibble's `warnings` attribute
#'   lists them all. A `LENGTH` statement for numbers, which sets only
#'   how SAS stores them, is skipped without one. A variable label with
#'   stray quotes inside it, such as
#'   `X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"` in CDC's
#'   2011-2013 to 2015-2017 setups, is read from its first quote to its
#'   last, without a warning.
#' @examples
#' dir <- tempfile()
#' dir.create(dir)
#' writeLines(c(
#'   "PROC FORMAT; VALUE kidsf 0='None' 98='DK' 99='Not ascertained';",
#'   "DATA; INPUT ID 1-3 KIDS 4-5;",
#'   "LABEL KIDS = 'Number of children';",
#'   "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
#'   "FORMAT KIDS kidsf.;"
#' ), file.path(dir, "survey.sas"))
#' writeLines(c("001 2", "00298", "00399", "004 0"), file.path(dir, "survey.dat"))
#' df <- read_fixed_width(file.path(dir, "survey.dat"), file.path(dir, "survey.sas"),
#'                        recodes = "tagged")
#' attr(df$KIDS, "labels")
#' @export
read_fixed_width <- function(file, setup, recodes = c("setup", "tagged", "none"), col_select = NULL,
                             skip = 0, n_max = Inf, factors = FALSE,
                             warn_extended_missing = TRUE, commented_formats = TRUE) {
  recodes <- match.arg(recodes)
  if (!is.character(setup) || length(setup) == 0) stop("`setup` must be one or more paths")
  if (!isTRUE(commented_formats) && !isFALSE(commented_formats)) {
    stop("`commented_formats` must be TRUE or FALSE")
  }
  if (!is.numeric(skip) || length(skip) != 1 || is.na(skip) || skip < 0) stop("skip must be a number >= 0")
  if (!is.numeric(n_max) || length(n_max) != 1 || is.na(n_max) || n_max < 0) stop("n_max must be a number >= 0")
  if (!rlang::is_bool(factors)) stop("factors must be TRUE or FALSE")
  if (!rlang::is_bool(warn_extended_missing)) stop("warn_extended_missing must be TRUE or FALSE")
  file <- normalizePath(file, mustWork = TRUE)
  setup <- normalizePath(setup, mustWork = TRUE)
  parsed <- .Call(C_fw_setup, setup, commented_formats)
  names <- .Call(C_fw_names, parsed)
  cols <- select_columns(rlang::enquo(col_select), names)
  read <- .Call(C_fw_read, parsed, file, recodes, as.integer(cols - 1L), floor(skip), floor(n_max))
  values <- read$columns
  names(values) <- names[cols]
  if (factors) {
    lost <- character()
    for (i in seq_along(values)) {
      if (!any(!is.na(attr(values[[i]], "labels", exact = TRUE)))) next
      if (warn_extended_missing && read$letters[i]) lost <- c(lost, names(values)[i])
      values[[i]] <- labelled_factor(values[[i]])
    }
    if (length(lost)) warn_lost(lost)
  }
  df <- tibble::new_tibble(values, nrow = read$nrow)
  if (length(read$warnings)) {
    attr(df, "warnings") <- read$warnings
    warn_fixed_width(read$warnings)
  }
  df
}

# The 1-based indices of the columns `select` picks from `names`, as
# dtaparser's read_dta picks them: all when it is NULL; a variable holding
# names goes through all_of(), unless a column has the variable's name
# (tidyselect's precedence).
select_columns <- function(select, names) {
  cols <- seq_along(names)
  if (rlang::quo_is_null(select)) return(cols)
  expr <- rlang::quo_get_expr(select)
  if (rlang::is_symbol(expr) && !(rlang::as_string(expr) %in% names)) {
    value <- tryCatch(rlang::eval_tidy(select), error = function(e) NULL)
    if (is.character(value)) select <- rlang::quo(tidyselect::all_of(!!value))
  }
  unname(tidyselect::eval_select(select, stats::setNames(as.list(cols), names)))
}

# A factor from a labelled integer or double column: levels in order of
# value, labelled codes by their text and other values by
# as.character() (of the integer when every value and code is a whole
# number); repeated texts are one level. Missing values, labelled or not,
# are NA.
labelled_factor <- function(x) {
  labels <- attr(x, "labels", exact = TRUE)
  labels <- labels[!is.na(labels)]
  values <- sort(unique(c(unname(labels), as.double(unique(x[!is.na(x)])))))
  integer <- is.integer(x) || (all(values == trunc(values)) && all(abs(values) <= .Machine$integer.max))
  text <- if (integer) as.character(as.integer(values)) else as.character(values)
  text[match(labels, values)] <- names(labels)
  levels <- unique(text)
  out <- match(text, levels)[match(x, values)]
  attr(out, "levels") <- levels
  class(out) <- "factor"
  attr(out, "label") <- attr(x, "label", exact = TRUE)
  out
}

# One warning naming the columns whose factors lost tagged NAs.
warn_lost <- function(cols) {
  shown <- paste0("`", utils::head(cols, 5), "`")
  if (length(cols) > 5) shown <- c(shown, paste(length(cols) - 5, "more"))
  if (length(shown) > 1) shown <- paste(paste(shown[-length(shown)], collapse = ", "), "and", shown[length(shown)])
  rlang::warn(
    paste0("Extended missing values (.a to .z) in ", shown, " are plain NA in their factors; ",
           "read with factors = FALSE to keep them, or warn_extended_missing = FALSE to silence this."),
    class = c("datparser_extended_missing", "dtaparser_extended_missing")
  )
}

# One warning with the first few messages, each cut short, so it fits in
# R's warning.length.
warn_fixed_width <- function(messages) {
  shown <- utils::head(messages, 8)
  long <- nchar(shown) > 100
  shown[long] <- paste0(substr(shown[long], 1, 97), "...")
  lines <- stats::setNames(shown, rep("*", length(shown)))
  if (length(messages) > 8) {
    lines <- c(lines, i = paste(length(messages) - 8, "more; see attr(x, \"warnings\")"))
  }
  rlang::warn(c("The setup file was read with warnings:", lines), class = c("datparser_fixed_width_warning", "datakit_fixed_width_warning"))
}
