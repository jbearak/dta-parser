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
#' @param col_select,skip,n_max,warn_extended_missing As in [read_dta()].
#'   `skip` and `n_max` apply after the whole file is read.
#' @param factors Whether columns with value labels become factors. A
#'   factor cannot hold tagged NAs, so this is `FALSE` by default with
#'   `recodes = "tagged"`, which keeps numbers, tagged NAs and a `labels`
#'   attribute naming both.
#' @param commented_formats Whether to read a `PROC FORMAT` step or a
#'   `FORMAT` statement that the setup has put in a block comment
#'   (`/* ... */`) as code. CDC's setups from 2006-2010 on comment both
#'   out so that SAS users without CDC's format catalog can run the file
#'   as published; the value labels are still there, so this is `TRUE` by
#'   default. Only a comment that holds nothing but such a step or
#'   statement is read; one that mentions `PROC FORMAT` in prose stays a
#'   comment. `FALSE` reads every comment as a comment, so those files
#'   have no value labels.
#' @return A tibble, as [read_dta()] returns. Numeric columns take the
#'   smallest type that holds their values: integers when every value is
#'   a whole number within R's integer range, doubles otherwise (and
#'   doubles when they hold tagged NAs). Value labels on recoded codes
#'   move to their tagged NA, or go when the code becomes a plain `NA`.
#'
#'   Statements the reader does not run (other data-step code, ranges in
#'   `VALUE`) are skipped with one warning of class
#'   `dtaparser_fixed_width_warning`; the tibble's `warnings` attribute
#'   lists them all. A variable label with stray quotes inside it, such as
#'   `X = "WHETHER " SAME AS LAST MONTH" WAS ANSWERED"` in CDC's
#'   2011-2013 to 2015-2017 setups, is read from its first quote to its
#'   last, with a warning naming its line.
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
#' haven::na_tag(df$KIDS)
#' @export
read_fixed_width <- function(file, setup, recodes = c("setup", "tagged", "none"), col_select = NULL,
                             skip = 0, n_max = Inf, factors = recodes != "tagged",
                             warn_extended_missing = TRUE, commented_formats = TRUE) {
  recodes <- match.arg(recodes)
  force(factors)
  if (!is.character(setup) || length(setup) == 0) stop("`setup` must be one or more paths")
  if (!isTRUE(commented_formats) && !isFALSE(commented_formats)) {
    stop("`commented_formats` must be TRUE or FALSE")
  }
  file <- normalizePath(file, mustWork = TRUE)
  setup <- normalizePath(setup, mustWork = TRUE)
  dir <- tempfile("dtaparser")
  if (!dir.create(dir, mode = "0700")) stop("could not create a temporary directory: ", dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- file.path(dir, "data.dta")
  warnings <- .Call(C_dta_fixed_width, file, setup, out, recodes, commented_formats)
  df <- read_dta(out, col_select = {{ col_select }}, skip = skip, n_max = n_max, factors = factors,
                 dates = FALSE, warn_extended_missing = warn_extended_missing)
  if (length(warnings)) {
    attr(df, "warnings") <- warnings
    warn_fixed_width(warnings)
  }
  df
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
  rlang::warn(c("The setup file was read with warnings:", lines), class = "dtaparser_fixed_width_warning")
}
