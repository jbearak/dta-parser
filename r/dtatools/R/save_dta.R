#' Write a dibble as a Stata .dta file (release 118)
#'
#' `save_dta()` is dtaparser's, re-exported (see `?dtaparser::save_dta`
#' for every rule). It writes from the columns' types and attributes, so
#' a dibble comes back as [read_dta()] read it: each `dta_num` column
#' keeps its `storage`, `format`, `label`, `labels` and `label_set`, and
#' `.a` to `.z` keep their letters.
#'
#' A numeric column without a `storage` attribute is written as long
#' (integers), double (doubles) or byte (logicals). Character columns are
#' strN, or strL beyond 2045 bytes; `NA` is written as `""`. A value that
#' does not fit its storage type is an error.
#'
#' The data frame's attributes give the file's metadata, as [read_dta()]
#' leaves them: `label`, `notes`, `characteristics`, `sort_order` and
#' `timestamp`. Without a `timestamp` attribute the file is stamped with
#' the current time, so a file read without a timestamp comes back with
#' one.
#'
#' @usage save_dta(data, file)
#' @param data A data frame, such as one `read_dta` returned.
#' @param file Path to write.
#' @return `file`, invisibly.
#' @examples
#' df <- dibble(
#'   id = 1:3,
#'   smoker = dta_num(c(1, 0, .d), storage = "byte", label = "Smokes daily",
#'                    labels = c(No = 0, Yes = 1, "Don't know" = .d))
#' )
#' attr(df, "label") <- "Smoking"
#' path <- tempfile(fileext = ".dta")
#' save_dta(df, path)
#' val_label(read_dta(path)$smoker, c(0, 1, .d))
#' @name save_dta
NULL
