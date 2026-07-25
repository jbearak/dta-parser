#' Read a Stata DTA file
#'
#' Reads releases 113--115 and 117--119 through the native Rust parser.
#' Numeric and character columns are created directly by native code. Dataset
#' and variable labels, Stata display formats, value labels, `strL` content,
#' and Stata system/extended missing values are retained.
#'
#' @param file A single path to a `.dta` file. Connections, URLs, and compressed
#'   paths are not supported.
#' @param encoding Must be `NULL`. Legacy files are decoded as Windows-1252 and
#'   modern files as UTF-8 according to their storage format.
#' @param col_select One or more tidyselect expressions. Predicates see Stata
#'   string storage as character and numeric storage as double. If a source
#'   variable is selected more than once, its first selection and alias win.
#'   Selection is resolved from metadata before observation data are read.
#' @param skip Number of observations to skip.
#' @param n_max Maximum observations to read. `Inf` reads all remaining rows.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @return A tibble. `%td` columns have class `Date`; `%tc` and `%tC` columns
#'   have classes `POSIXct` and `POSIXt` in UTC. Other Stata temporal formats
#'   remain numeric with their `format.stata` attribute.
#' @export
read_dta <- function(file, encoding = NULL, col_select = NULL, skip = 0,
                     n_max = Inf, .name_repair = "unique") {
    if (!is.character(file) || length(file) != 1L || is.na(file)) {
        stop("`file` must be one non-missing path", call. = FALSE)
    }
    if (!is.null(encoding)) {
        stop("`encoding` overrides are not supported; use NULL", call. = FALSE)
    }
    .validate_count(skip, "skip", infinite = FALSE)
    .validate_count(n_max, "n_max", infinite = TRUE)

    file <- normalizePath(file, mustWork = TRUE)
    selection <- rlang::enquo(col_select)
    metadata_names <- .Call(C_dtaparser_metadata, file)

    if (rlang::quo_is_null(selection)) {
        column_indices <- NULL
        selected_names <- metadata_names
    } else {
        storage <- attr(metadata_names, "dta_storage", exact = TRUE)
        selection_proxy <- stats::setNames(
            lapply(storage, function(type) {
                if (identical(type, "character")) character() else double()
            }),
            metadata_names
        )
        selected <- tidyselect::eval_select(selection, selection_proxy)
        selected <- selected[!duplicated(unname(selected))]
        column_indices <- as.integer(unname(selected) - 1L)
        selected_names <- names(selected)
    }

    native <- .Call(
        C_dtaparser_read,
        file,
        column_indices,
        as.double(skip),
        as.double(n_max)
    )
    if (!is.null(column_indices)) {
        names(native) <- selected_names
    }

    dataset_label <- attr(native, "label", exact = TRUE)
    format_version <- attr(native, "dta_format_version", exact = TRUE)
    result <- tibble::as_tibble(native, .name_repair = .name_repair)
    if (!is.null(dataset_label)) attr(result, "label") <- dataset_label
    if (!is.null(format_version)) {
        attr(result, "dta_format_version") <- format_version
    }
    result
}

.validate_count <- function(value, argument, infinite) {
    valid_infinite <- infinite && is.numeric(value) && length(value) == 1L &&
        is.infinite(value) && value > 0
    valid_finite <- is.numeric(value) && length(value) == 1L && !is.na(value) &&
        is.finite(value) && value >= 0 && value == floor(value) && value <= 2^53
    if (!valid_infinite && !valid_finite) {
        stop(sprintf("`%s` must be one non-negative whole number%s", argument,
            if (infinite) " or Inf" else ""), call. = FALSE)
    }
}
