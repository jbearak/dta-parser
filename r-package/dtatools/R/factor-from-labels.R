#' Convert Stata-labelled values to an ordinary factor
#'
#' `factor_from_labels()` performs a one-way conversion from a numeric vector
#' and its Stata value-label metadata to an ordinary R factor. Unlike a
#' reversible labelled-vector class, the result is intended for modeling,
#' plotting, and data manipulation after import. It does not retain enough
#' metadata to reconstruct the source numeric vector.
#'
#' Distinct source codes always remain distinct levels, even when they share
#' the same label text. By default, all missing values become factor `NA` and
#' all valid nonmissing value-label entries become levels, including unused
#' entries. Missing-label entries become levels only when missing codes are
#' distinguished.
#' Conversion and [tab()] share a native grouping implementation that does not
#' materialize compact numeric columns returned by [read_dta()].
#'
#' @param x An undimensioned numeric-storage vector, including `Date` and
#'   `POSIXct`.
#' @param missing How missing values should be handled. `FALSE` and
#'   `"exclude"` make them factor `NA`; `TRUE` and `"distinguish"` give
#'   observed missing payloads separate levels for Stata system missing (`.`),
#'   extended missing codes, and R `NaN`. Labelled extended-missing entries
#'   absent from `x` also remain as levels unless `drop_unused = TRUE`.
#' @param display How labelled levels should be named: by `"label"` (the
#'   default), underlying `"value"`, or `"both"`. Unlabelled values always
#'   fall back to the underlying value.
#' @param drop_unused Whether value-label entries absent from `x` should be
#'   omitted from the factor levels.
#' @param ordered Whether to return an ordered factor.
#' @return An ordinary factor. Names and the variable `label` are retained;
#'   value labels, Stata formats, and other source attributes are not.
#' @examples
#' status <- structure(
#'     c(1, 2, 1, tagged_missing("a")),
#'     labels = c(Complete = 1, Refused = 2),
#'     label = "Interview status"
#' )
#' factor_from_labels(status)
#' factor_from_labels(status, missing = TRUE, display = "both")
#' @export
factor_from_labels <- function(x, missing = FALSE,
                               display = c("label", "value", "both"),
                               drop_unused = FALSE, ordered = FALSE) {
    temporal <- inherits(x, "Date") || inherits(x, "POSIXct")
    if (!typeof(x) %in% c("integer", "double") ||
        (!is.numeric(x) && !temporal) || is.factor(x) || !is.null(dim(x))) {
        stop("`x` must be an undimensioned numeric vector", call. = FALSE)
    }
    missing <- .normalize_factor_missing(missing)
    display <- match.arg(display)
    drop_unused <- .normalize_factor_flag(drop_unused, "drop_unused")
    ordered <- .normalize_factor_flag(ordered, "ordered")

    labels <- .normalize_value_labels(
        attr(x, "labels", exact = TRUE),
        "attr(x, \"labels\")"
    )
    .warn_stata_metadata_limits(.value_label_violations(labels))
    if (temporal && !is.null(labels)) {
        labels <- .tab_label_values(labels, x)
    }
    variable_label <- attr(x, "label", exact = TRUE)
    input_names <- names(x)
    result <- .tab_factor(
        x,
        labels,
        missing,
        display,
        restore_to = if (temporal) x else NULL,
        drop_unused = drop_unused
    )

    names(result) <- input_names
    if (!is.null(variable_label)) attr(result, "label") <- variable_label
    if (ordered) class(result) <- c("ordered", "factor")
    result
}

.normalize_factor_missing <- function(value) {
    if (is.logical(value)) {
        if (length(value) != 1L || is.na(value)) {
            stop("`missing` must be one non-missing logical or string",
                 call. = FALSE)
        }
        return(if (value) "distinguish" else "exclude")
    }
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
        stop("`missing` must be one non-missing logical or string",
             call. = FALSE)
    }
    match.arg(value, c("exclude", "distinguish"))
}

.normalize_factor_flag <- function(value, argument) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        stop(sprintf("`%s` must be one non-missing logical value", argument),
             call. = FALSE)
    }
    value
}
