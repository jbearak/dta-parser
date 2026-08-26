#' Tabulate vectors using Stata value labels
#'
#' Creates one-way or multidimensional frequency tables while using the value
#' labels and extended missing codes carried by vectors returned by [read_dta()].
#' Ordinary unlabelled vectors retain the familiar behavior of [base::table()].
#'
#' @param x A vector, or a data frame whose columns should be tabulated. When
#'   `data` is supplied, an unquoted column name. The argument may be omitted
#'   when `data` is supplied or named vectors are passed through `...`.
#' @param ... Additional vectors or, when `x` or `data` is a data frame,
#'   unquoted column names. All selected vectors must have the same length.
#' @param data Optional data frame in which to evaluate `x` and `...`.
#' @param missing How missing values should be handled. `FALSE` and
#'   `"exclude"` omit them; `TRUE` and `"distinguish"` give Stata system
#'   missing (`.`), every observed extended missing (`.a` through `.z`), and R
#'   `NaN` separate categories; `"combine"` creates one base-R missing
#'   category.
#' @param display How labelled values should be named: by `"label"` (the
#'   default), underlying `"value"`, or `"both"`. An absent label always falls
#'   back to the underlying value. Duplicate displayed labels are qualified by
#'   their values.
#'
#' Numeric factorization is shared with [factor_from_labels()] and does not
#' materialize compact numeric columns returned by [read_dta()].
#'
#' @return A standard `table` object.
#' @export
#' @examples
#' x <- set_value_labels(
#'     c(1, 2, 1, NA_real_, tagged_missing(c("a", "b"))),
#'     Yes = 1, No = 2, Refused = tagged_missing("a")
#' )
#'
#' table(unclass(x), useNA = "ifany")
#' table(factor_from_labels(x), useNA = "ifany")
#' tab(x, missing = TRUE)
#' tab(x, missing = TRUE, display = "both")
#'
#' mtcars |>
#'     tab(cyl, gear)
tab <- function(x, ..., data = NULL, missing = FALSE,
                display = c("label", "value", "both")) {
    caller <- rlang::caller_env()
    x_is_missing <- missing(x)
    x_quo <- if (x_is_missing) NULL else rlang::enquo(x)
    dots <- rlang::enquos(...)

    missing <- .normalize_tab_missing(missing)
    display <- match.arg(display)
    inputs <- .tab_inputs(x_quo, dots, data, caller)
    x <- data <- x_quo <- dots <- NULL
    for (index in seq_along(inputs$values)) {
        inputs$values[[index]] <- .prepare_tab_argument(
            inputs$values[[index]],
            missing = missing,
            display = display
        )
    }
    names(inputs$values) <- inputs$names

    base::table(
        inputs$values,
        useNA = if (identical(missing, "exclude")) "no" else "ifany"
    )
}

.normalize_tab_missing <- function(value) {
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
    match.arg(value, c("exclude", "distinguish", "combine"))
}

.tab_inputs <- function(x, dots, data, caller) {
    if (!is.null(data)) {
        if (!is.data.frame(data)) {
            stop("`data` must be a data frame", call. = FALSE)
        }
        quosures <- c(if (is.null(x)) list() else list(x), dots)
        if (length(quosures) == 0L) {
            return(list(values = as.list(data), names = names(data)))
        }
        return(.eval_tab_quosures(quosures, data = data, caller = caller))
    }

    if (is.null(x)) {
        if (length(dots) == 0L) stop("nothing to tabulate", call. = FALSE)
        return(.eval_tab_quosures(dots, caller = caller))
    }

    first <- rlang::eval_tidy(x, env = caller)
    if (is.data.frame(first)) {
        if (length(dots) == 0L) {
            return(list(values = as.list(first), names = names(first)))
        }
        return(.eval_tab_quosures(dots, data = first, caller = caller))
    }
    if (is.list(first) && !is.object(first) && length(dots) == 0L) {
        input_names <- names(first)
        if (is.null(input_names)) {
            input_names <- paste0(
                .tab_quo_name(x), ".", seq_along(first)
            )
        }
        return(list(values = first, names = input_names))
    }

    rest <- if (length(dots) == 0L) {
        list(values = list(), names = character())
    } else {
        .eval_tab_quosures(dots, caller = caller)
    }
    list(
        values = c(list(first), rest$values),
        names = c(.tab_quo_name(x), rest$names)
    )
}

.eval_tab_quosures <- function(quosures, data = NULL, caller) {
    values <- if (is.null(data)) {
        lapply(quosures, rlang::eval_tidy, env = caller)
    } else {
        column_names <- vapply(quosures, function(value) {
            expression <- rlang::quo_get_expr(value)
            if (!rlang::is_symbol(expression)) {
                stop("data-frame tabulation requires column names", call. = FALSE)
            }
            rlang::as_name(expression)
        }, character(1))
        unknown <- !column_names %in% names(data)
        if (any(unknown)) {
            stop(
                "unknown column `", column_names[which(unknown)[[1L]]], "`",
                call. = FALSE
            )
        }
        duplicate_names <- names(data)[
            duplicated(names(data)) | duplicated(names(data), fromLast = TRUE)
        ]
        ambiguous <- column_names %in% duplicate_names
        if (any(ambiguous)) {
            stop(
                "column `", column_names[which(ambiguous)[[1L]]],
                "` is ambiguous because its name is duplicated",
                call. = FALSE
            )
        }
        lapply(column_names, function(name) data[[name]])
    }
    supplied_names <- names(quosures)
    if (is.null(supplied_names)) supplied_names <- rep("", length(quosures))
    inferred_names <- vapply(quosures, .tab_quo_name, character(1))
    use_supplied <- nzchar(supplied_names)
    inferred_names[use_supplied] <- supplied_names[use_supplied]
    list(values = values, names = inferred_names)
}

.tab_quo_name <- function(value) {
    expression <- rlang::quo_get_expr(value)
    if (rlang::is_symbol(expression)) rlang::as_name(expression) else ""
}

.prepare_tab_argument <- function(value, missing, display) {
    labels <- attr(value, "labels", exact = TRUE)
    numeric_data <- typeof(value) %in% c("double", "integer") &&
        !is.factor(value)
    labelled <- numeric_data && .valid_tab_labels(labels)
    needs_missing <- !identical(missing, "exclude") && numeric_data

    if (!labelled && !needs_missing) return(value)

    restore_to <- if (is.object(value) &&
        !inherits(value, "haven_labelled")) value else NULL
    if (labelled) labels <- .tab_label_values(labels, value)
    .tab_factor(
        value,
        if (labelled) labels else NULL,
        missing,
        display,
        restore_to,
        drop_unused = TRUE
    )
}

.valid_tab_labels <- function(labels) {
    !is.null(labels) &&
        typeof(labels) %in% c("double", "integer") &&
        length(labels) == length(names(labels))
}

.tab_label_values <- function(labels, value) {
    format <- attr(value, "format.stata", exact = TRUE)
    if (!is.character(format) || length(format) != 1L || is.na(format)) {
        return(labels)
    }
    observed <- !is.na(labels)
    if (inherits(value, "POSIXct") && grepl("^%t[cC]", format)) {
        labels[observed] <- labels[observed] / 1000 - 315619200
    } else if (inherits(value, "Date") && grepl("^%(td|d)", format)) {
        labels[observed] <- labels[observed] - 3653
    }
    labels
}

.tab_factor <- function(value, labels, missing, display, restore_to,
                        drop_unused) {
    seeds <- if (drop_unused) NULL else labels
    grouped <- .factorize_numeric(value, seeds, missing)
    factor_codes <- grouped$codes
    observed_values <- grouped$values
    observed_missing_codes <- grouped$missing_codes
    level_values <- if (is.null(restore_to)) {
        as.character(observed_values)
    } else {
        as.character(vctrs::vec_restore(observed_values, restore_to))
    }
    if (length(observed_missing_codes) > 0L) {
        level_values <- c(
            level_values,
            vapply(
                observed_missing_codes,
                .tab_missing_name,
                character(1)
            )
        )
    }

    label_names <- .tab_level_labels(
        labels,
        observed_values,
        observed_missing_codes
    )
    level_names <- switch(display,
        value = level_values,
        label = ifelse(is.na(label_names), level_values, label_names),
        both = ifelse(
            is.na(label_names),
            level_values,
            paste0("[", level_values, "] ", label_names)
        )
    )
    level_names <- as.character(level_names)
    level_names <- .disambiguate_tab_levels(level_names, level_values)

    structure(
        factor_codes,
        levels = level_names,
        class = "factor"
    )
}

.factorize_numeric <- function(value, seeds, missing) {
    missing_mode <- switch(missing,
        exclude = 0L,
        distinguish = 1L,
        combine = 2L
    )
    result <- .Call(C_dtaparser_factorize_numeric, value, seeds, missing_mode)
    if (typeof(value) == "integer") {
        result$values <- as.integer(result$values)
    }
    result
}

.tab_level_labels <- function(labels, observed_values, missing_codes) {
    count <- length(observed_values) + length(missing_codes)
    result <- rep(NA_character_, count)
    if (is.null(labels) || length(labels) == 0L) return(result)

    label_names <- names(labels)
    usable <- !is.na(label_names) & nzchar(label_names)
    if (!any(usable)) return(result)
    labels <- labels[usable]
    label_names <- label_names[usable]
    label_missing_codes <- .tab_missing_codes(labels)

    if (length(observed_values) > 0L) {
        observed_labels <- is.na(label_missing_codes)
        if (any(observed_labels)) {
            matches <- match(observed_values, labels[observed_labels])
            found <- !is.na(matches)
            result[which(found)] <-
                label_names[observed_labels][matches[found]]
        }
    }

    if (length(missing_codes) > 0L) {
        missing_labels <- !is.na(label_missing_codes)
        if (any(missing_labels)) {
            matches <- match(missing_codes, label_missing_codes[missing_labels])
            found <- !is.na(matches)
            positions <- length(observed_values) + which(found)
            result[positions] <- label_names[missing_labels][matches[found]]
        }
    }
    result
}

.disambiguate_tab_levels <- function(names, values) {
    duplicated_names <- duplicated(names) | duplicated(names, fromLast = TRUE)
    names[duplicated_names] <- paste0(
        names[duplicated_names], " [", values[duplicated_names], "]"
    )
    make.unique(names, sep = " #")
}

.tab_missing_name <- function(code) {
    if (code == 0L) return(".")
    if (code == 256L) return("NaN")
    if (code >= utf8ToInt("a") && code <= utf8ToInt("z")) {
        return(paste0(".", intToUtf8(code)))
    }
    paste0(".<tag ", code, ">")
}

.tab_missing_codes <- function(value) {
    .Call(C_dtaparser_missing_codes, value)
}
