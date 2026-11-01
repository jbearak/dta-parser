#' Read a fixed-width text file through its SAS setup file
#'
#' Reads fixed-width ASCII data, such as the National Survey of Family
#' Growth cycles of 1973 to 1995 that CDC publishes as `.dat` files,
#' using the SAS setup file (`.sas`) that describes it: each variable's
#' columns from `INPUT`, its label from `LABEL`, its value labels from
#' `PROC FORMAT` and `FORMAT`, record-type selection
#' (`IF rec_type < 5 THEN DELETE; ELSE INPUT ...`) and the setup's
#' missing-value recodes (`IF (X = 98 OR X = 99) THEN X = .;`).
#'
#' @param file Path to the fixed-width data file.
#' @param setup Path to the SAS setup file.
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
#' @return A tibble, as [read_dta()] returns. Numeric columns take the
#'   smallest type that holds their values: integers when every value is
#'   a whole number within R's integer range, doubles otherwise (and
#'   doubles when they hold tagged NAs). Value labels on recoded codes
#'   move to their tagged NA, or go when the code becomes a plain `NA`.
#'
#'   Statements the reader does not run (other data-step code, ranges in
#'   `VALUE`) are skipped with one warning of class
#'   `dtaparser_fixed_width_warning`; the tibble's `warnings` attribute
#'   lists them all.
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
                             warn_extended_missing = TRUE) {
  recodes <- match.arg(recodes)
  force(factors)
  file <- normalizePath(file, mustWork = TRUE)
  setup <- normalizePath(setup, mustWork = TRUE)
  dir <- tempfile("dtaparser")
  if (!dir.create(dir, mode = "0700")) stop("could not create a temporary directory: ", dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  out <- file.path(dir, "data.dta")
  warnings <- .Call(C_dta_fixed_width, file, setup, out, recodes)
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
