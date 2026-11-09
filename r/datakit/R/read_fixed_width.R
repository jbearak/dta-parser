#' Read a fixed-width text file through its SAS setup file
#'
#' datparser's [datparser::read_fixed_width()], whose columns with value
#' labels come back as a [`dtaparser_labelled`][dtaparser::with_labels],
#' as [read_dta()] gives them, rather than as plain vectors with a
#' `labels` attribute: so their labels survive `x[i]`, `bind_rows()`,
#' `case_when()` and `if_else()`, and [val_label()], [na_tag()] and `:=`
#' work on them.
#'
#' @inheritParams datparser::read_fixed_width
#' @return As [datparser::read_fixed_width()] returns, with each numeric
#'   column that has value labels a `dtaparser_labelled`.
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
#' na_tag(df$KIDS)
#' val_label(df$KIDS)
#' @export
read_fixed_width <- function(file, setup, recodes = c("setup", "tagged", "none"), col_select = NULL,
                             skip = 0, n_max = Inf, factors = FALSE,
                             warn_extended_missing = TRUE, commented_formats = TRUE) {
  df <- datparser::read_fixed_width(file, setup, recodes = recodes, col_select = {{ col_select }}, skip = skip,
                                    n_max = n_max, factors = factors, warn_extended_missing = warn_extended_missing,
                                    commented_formats = commented_formats)
  # Through the list, since assigning tibble columns one by one is slow
  # for files of thousands of columns.
  values <- unclass(df)
  for (i in seq_along(values)) {
    x <- values[[i]]
    if (is.numeric(x) && !is.object(x) && !is.null(attr(x, "labels", exact = TRUE))) values[[i]] <- as_labelled(x)
  }
  tibble::new_tibble(values, nrow = nrow(df))
}

# The class read_dta() gives a column with value labels, made as
# dtaparser makes it from a file's labels: without with_labels()' checks,
# since a setup may label a code with empty text, which a .dta file holds
# too. datparser gives the labels in code order already.
as_labelled <- function(x) {
  labels <- attr(x, "labels", exact = TRUE)
  label <- attr(x, "label", exact = TRUE)
  attributes(x) <- NULL
  vctrs::new_vctr(x, labels = labels, label = label, class = "dtaparser_labelled")
}
