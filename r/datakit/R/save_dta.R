#' Write a data frame or a polars frame as a Stata .dta file
#'
#' For a data frame, `save_dta()` is dtaparser's [dtaparser::save_dta()],
#' called with the same arguments: see its help page for what each column
#' becomes.
#'
#' For a polars DataFrame, as [read_dta_pl()] or [read_parquet_pl()]
#' returns, it writes release 118 with what `meta` says, as Python
#' datakit's `dk.save_dta()` does. Each column gets the smallest storage
#' type that holds its values: integers byte, int or long (double past
#' long, an error past +/-2^53), Float32 float, Float64 double, Boolean
#' byte, String strN or strL, Binary strL. A Date is `%td`; a Datetime
#' `%tc`, in milliseconds: a value with a fraction of one is an error
#' naming the column and row unless `timestamps = "truncate"`, and a time
#' zone is an error. An Enum or Categorical is written as codes 1 to k,
#' labelled with its levels in a value label set named after the column,
#' with a `dtaparser_categorical` characteristic so that [read_dta_pl()]
#' gives the Enum back. `.a` to `.z` are the tagged NaNs of Float64
#' columns; a column a read made Float64 to hold them gets its storage
#' type back when its values still fit it. Time, Duration, Decimal and
#' nested dtypes are errors naming the column, as is a name Stata cannot
#' hold. A LazyFrame is an error: call `$collect()` on it first.
#'
#' Neither polars nor nanoarrow is needed to save a data frame.
#'
#' @param data A data frame, or a polars DataFrame.
#' @param file Path to write.
#' @param ... For a data frame, nothing (dtaparser's `save_dta()` takes
#'   `data` and `file`). For a polars DataFrame, `meta`,
#'   `missing_letters` and `timestamps`, by name.
#' @param meta The [`datakit_meta`][datakit_meta] a read gave with
#'   the frame, or `NULL`.
#' @param missing_letters `FALSE` writes `.a` to `.z` as `.`, and a
#'   categorical's set without letter labels.
#' @param timestamps `"error"` (the default) or `"truncate"`.
#' @return `data`, invisibly, for a polars DataFrame; what
#'   [dtaparser::save_dta()] returns for a data frame.
#' @seealso [save_parquet()], [read_dta_pl()].
#' @examples
#' path <- tempfile(fileext = ".dta")
#' save_dta(data.frame(id = 1:3, x = c(1, NA, tagged_na("a"))), path)
#' na_tag(read_dta(path)$x)
#' @export
save_dta <- function(data, file, ...) UseMethod("save_dta")

#' @rdname save_dta
#' @export
save_dta.default <- function(data, file, ...) dtaparser::save_dta(data, file, ...)

#' @rdname save_dta
#' @export
save_dta.polars_data_frame <- function(data, file, ..., meta = NULL, missing_letters = TRUE, timestamps = "error") {
  check_polars("save_dta")
  rlang::check_dots_empty()
  if (!is.character(file) || length(file) != 1 || is.na(file)) stop("file must be a path", call. = FALSE)
  timestamps <- one_of(timestamps, c("error", "truncate"), "timestamps")
  prep <- prepare_pl(data, meta, missing_letters, "save_dta")
  reserved_warning(prep$df$columns)
  .Call(C_dta_dta_write_arrow, nanoarrow::as_nanoarrow_array_stream(prep$df), path.expand(file), prep$meta,
        list(missing_letters, timestamps))
  invisible(data)
}

#' @rdname save_dta
#' @export
save_dta.polars_lazy_frame <- function(data, file, ...) check_frame(data, "save_dta")

# As dtaparser's save_dta: one warning naming the columns called by a
# word Stata reserves (or str and digits).
RESERVED_NAMES <- c("_all", "_b", "byte", "_coef", "_cons", "double", "float", "if", "in", "int", "long",
                    "_n", "_N", "_pi", "_pred", "_rc", "_skip", "strL", "using", "with")

reserved_warning <- function(names) {
  reserved <- names[names %in% RESERVED_NAMES | grepl("^str[0-9]+$", names)]
  if (length(reserved)) {
    warning("save_dta: ", paste0("\"", reserved, "\"", collapse = ", "),
            if (length(reserved) == 1) " is a word" else " are words",
            " Stata reserves; rename ", if (length(reserved) == 1) "it" else "them",
            " before using the file in Stata", call. = FALSE)
  }
}
