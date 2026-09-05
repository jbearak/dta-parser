#' Stata numeric calculations
#'
#' These ordinary vector functions ignore Stata system and extended missing
#' values and return unrounded doubles without source labels or date classes.
#' Date and datetime inputs contribute their encoded Stata numeric values.
#' Use them in [egen()], [gen()], or a dibble `:=` assignment; assignment
#' chooses storage. Wrap the result in [dta_double()] to request double storage.
#'
#' `dta_mean()`, `dta_min()`, and `dta_max()` return system missing when
#' there are no observed values. Totals return zero in that case unless
#' `missing = TRUE`. For extrema, `missing = TRUE` instead includes missing
#' codes in Stata order: all numbers, then system missing, then `.a` to `.z`.
#'
#' Row functions accept vectors of equal length or one list or data frame
#' of columns. At least one column is required; scalar recycling is not used.
#' `dta_row_max()` returns system missing for an all-missing row.
#'
#' @param x A numeric or logical vector, including Stata numeric vectors,
#'   labelled numerics, dates, or datetimes. `NaN`, infinities, values outside
#'   Stata's double range, factors, matrices, and other numeric classes are
#'   rejected.
#' @param missing A single logical value controlling missing-value treatment.
#' @param ... Numeric vectors, or one list or data frame of numeric columns.
#' @return A bare double scalar for summary functions, or a bare double
#'   vector with one value per input row for row functions.
#' @name dta-calculations
#' @export
dta_mean <- function(x) .dta_egen_summary(x, 0L, FALSE)

#' @rdname dta-calculations
#' @export
dta_min <- function(x, missing = FALSE) .dta_egen_summary(x, 1L, missing)

#' @rdname dta-calculations
#' @export
dta_max <- function(x, missing = FALSE) .dta_egen_summary(x, 2L, missing)

#' @rdname dta-calculations
#' @export
dta_total <- function(x, missing = FALSE) .dta_egen_summary(x, 3L, missing)

#' @rdname dta-calculations
#' @export
dta_row_max <- function(...) .dta_egen_rows(list(...), 2L, FALSE)

#' @rdname dta-calculations
#' @export
dta_row_total <- function(..., missing = FALSE) {
    .dta_egen_rows(list(...), 3L, missing)
}

.dta_egen_flag <- function(value, name = "missing") {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        stop(sprintf("`%s` must be TRUE or FALSE", name), call. = FALSE)
    }
    value
}

.dta_egen_evaluation <- new.env(parent = emptyenv())
.dta_egen_evaluation$allow_nan <- FALSE

.dta_egen_columns <- function(...) {
    columns <- list(...)
    if (length(columns) == 1L &&
        (is.data.frame(columns[[1L]]) ||
         (is.list(columns[[1L]]) && !is.object(columns[[1L]])))) {
        columns <- as.list(columns[[1L]])
    }
    if (!length(columns)) {
        stop("At least one column is required", call. = FALSE)
    }
    if (length(unique(lengths(columns))) != 1L) {
        stop("Columns must have equal lengths", call. = FALSE)
    }
    columns
}

.dta_egen_numeric_supported <- function(x) {
    classes <- class(x)
    identical(classes, c("stata_temporal", "stata_date", "Date")) ||
        identical(classes, c("stata_temporal", "stata_datetime", "POSIXct",
                             "POSIXt")) ||
        .generated_numeric_class_supported(x)
}

.dta_egen_numeric <- function(x) {
    supported <- .dta_egen_numeric_supported(x)
    if (!typeof(x) %in% c("double", "integer", "logical") ||
        !supported || is.factor(x) || inherits(x, "integer64") ||
        inherits(x, "difftime") || !is.null(dim(x))) {
        stop("Calculation inputs must be numeric or logical vectors",
             call. = FALSE)
    }
    invisible(NULL)
}

.dta_egen_summary <- function(x, operation, missing) {
    missing <- .dta_egen_flag(missing)
    .dta_egen_numeric(x)
    .Call(C_dtatools_egen_summary, x, operation, missing,
          .dta_egen_evaluation$allow_nan)
}

.dta_egen_rows <- function(columns, operation, missing) {
    missing <- .dta_egen_flag(missing)
    columns <- do.call(.dta_egen_columns, columns)
    for (column in columns) .dta_egen_numeric(column)
    .Call(C_dtatools_egen_rows, columns, operation, missing,
          .dta_egen_evaluation$allow_nan)
}
