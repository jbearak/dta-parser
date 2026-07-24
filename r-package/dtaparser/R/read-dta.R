#' Read a Stata DTA file with dta-parser
#'
#' Reads a Stata dataset through the bundled TypeScript parser and returns a
#' tibble. Variable labels, Stata display formats, and numeric value
#' labels are attached as attributes. Extended missing values are represented
#' as `NA_real_`; their original `.`, `.a` through `.z` tags are retained in a
#' parallel `dta_missing_tags` attribute on each numeric column.
#'
#' @param file Path to a `.dta` file.
#' @param encoding Character encoding override. `NULL` and `"UTF-8"` are
#'   accepted; other encodings are not yet supported by dta-parser.
#' @param col_select One or more selection expressions using
#'   [tidyselect::language()].
#' @param skip Number of rows to skip.
#' @param n_max Maximum number of rows to read. `Inf` reads all remaining rows.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @return A tibble with dataset and variable metadata attributes.
#' @export
read_dta <- function(file, encoding = NULL, col_select = NULL, skip = 0,
                     n_max = Inf, .name_repair = "unique") {
    selection <- rlang::enquo(col_select)
    if (!is.character(file) || length(file) != 1L || is.na(file)) {
        stop("`file` must be one non-missing path", call. = FALSE)
    }
    if (!is.null(encoding) && !toupper(encoding) %in% c("", "UTF-8", "UTF8")) {
        stop("dta-parser currently supports UTF-8 input only", call. = FALSE)
    }
    if (!is.numeric(skip) || length(skip) != 1L || is.na(skip) ||
        skip < 0 || skip != as.integer(skip)) {
        stop("`skip` must be one non-negative integer", call. = FALSE)
    }
    if (!is.numeric(n_max) || length(n_max) != 1L || is.na(n_max) ||
        n_max < 0) {
        stop("`n_max` must be one non-negative number", call. = FALSE)
    }
    skip <- as.integer(skip)
    row_limit <- if (is.infinite(n_max)) -1L else as.integer(n_max)
    file <- normalizePath(file, mustWork = TRUE)
    size <- file.info(file)$size
    bytes <- readBin(file, what = "raw", n = size)
    context <- .dtaparser_context()
    context$assign("__dtaparser_input", bytes)
    context$assign("__dtaparser_skip", skip)
    context$assign("__dtaparser_n_max", row_limit)
    context$eval(paste0(
        "__dtaparser_result = dtaParserRead(",
        "__dtaparser_input, __dtaparser_skip, __dtaparser_n_max)"
    ))
    parsed <- context$get(
        "__dtaparser_result", simplifyVector = FALSE
    )

    data <- .dtaparser_as_tibble(parsed, .name_repair)
    if (!rlang::quo_is_null(selection)) {
        selected <- tidyselect::eval_select(selection, data)
        data <- data[unname(selected)]
    }
    attr(data, "label") <- parsed$dataset_label
    attr(data, "dta_format_version") <- parsed$format_version
    data
}

.dtaparser_as_tibble <- function(parsed, name_repair = "unique") {
    variables <- parsed$variables
    columns <- Map(.dtaparser_column, parsed$columns, variables)
    names(columns) <- vapply(variables, `[[`, character(1), "name")
    data <- tibble::as_tibble(columns, .name_repair = name_repair)
    attr(data, "label") <- parsed$dataset_label
    attr(data, "dta_format_version") <- parsed$format_version
    data
}

.dtaparser_column <- function(values, variable) {
    is_string <- identical(variable$kind, "string")
    missing_tags <- rep.int(NA_character_, length(values))
    if (is_string) {
        column <- vapply(values, function(value) {
            if (is.null(value)) "" else as.character(value)
        }, character(1))
    } else {
        column <- vapply(seq_along(values), function(index) {
            value <- values[[index]]
            if (is.list(value) && !is.null(value$missing_type)) {
                missing_tags[[index]] <<- value$missing_type
                NA_real_
            } else {
                as.numeric(value)
            }
        }, numeric(1))
        attr(column, "dta_missing_tags") <- missing_tags
    }

    attr(column, "label") <- variable$label
    attr(column, "format.stata") <- variable$format
    if (length(variable$labels)) {
        labels <- vapply(
            variable$labels, `[[`, numeric(1), "value"
        )
        names(labels) <- vapply(
            variable$labels, `[[`, character(1), "label"
        )
        attr(column, "labels") <- labels
    }
    column
}

#' Recover Stata missing-value tags
#'
#' @param x A numeric column returned by [read_dta()].
#' @return A character vector containing `NA` for observed values and `.`,
#'   `.a` through `.z` for Stata missing values.
#' @export
dta_missing_tags <- function(x) {
    tags <- attr(x, "dta_missing_tags", exact = TRUE)
    if (is.null(tags)) rep.int(NA_character_, length(x)) else tags
}
