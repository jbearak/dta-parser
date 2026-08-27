#' Recode values while preserving Stata missing tags
#'
#' Provides the familiar `dplyr::recode()` interface while retaining the exact
#' payload of every unmatched Stata system or extended missing value. It also
#' supports the numeric classes returned by [read_dta()], including
#' `haven_labelled`, `Date`, and `POSIXct`.
#'
#' @param .x A numeric, character, or factor vector. Numeric storage may carry
#'   Stata missing tags and Stata metadata attributes.
#' @param ... Replacements in the legacy `dplyr::recode()` form. Numeric
#'   replacements may be named by source value or supplied positionally;
#'   character and factor replacements must be named.
#' @param .default Optional replacement for unmatched non-missing values. The
#'   default `NULL` retains compatible source values.
#' @param .missing Optional replacement for missing values. The default `NULL`
#'   preserves the exact system, extended, or `NaN` payload from `.x`. A
#'   supplied value intentionally replaces every missing kind. Following
#'   dplyr, factor inputs do not support a non-`NULL` `.missing`.
#'
#' @details
#' Recoding materializes a numeric ALTREP vector because it creates a writable
#' result. When the result remains numeric, the original class and Stata
#' metadata attributes are restored. Value-label definitions are not rewritten
#' when their associated numeric codes change.
#' Unmatched `NaN` values in a bare numeric `.x` retain their payload. A
#' storage-bearing Stata vector cannot contain `NaN`, so inserting one through
#' a replacement, `.default`, or `.missing` errors. Use `NA_real_` for system
#' missing or [tagged_missing()] for an extended missing value. Arithmetic is
#' different: undefined results become system missing as described in
#' [stata_byte()].
#'
#' A recode from numeric to a non-numeric type cannot retain tagged-NA
#' payloads. If `.x` contains missing values and the result is non-numeric,
#' supply `.missing` explicitly to choose their new representation. Numeric
#' widening from integer to double preserves missing values automatically.
#' Bare numeric sources reject classed replacements such as `Date` or factor
#' values rather than silently dropping the replacement class. Stata date and
#' datetime sources accept `Date` and `POSIXct` replacements, respectively.
#' For other class changes, apply the desired class after recoding.
#'
#' When the dtaparser namespace is loaded, `dplyr::recode()` dispatches here
#' for bare numeric, `haven_labelled`, `Date`, and `POSIXct` vectors. This also
#' applies when `recode()` is called inside `dplyr::mutate()`, regardless of
#' package attachment order. Numeric vectors without tags retain dplyr's exact
#' legacy behavior; tagged vectors preserve unmatched tag payloads and numeric
#' metadata.
#'
#' @return A recoded vector. Unmatched numeric missing values retain their exact
#'   payload unless `.missing` is supplied.
#' @examples
#' x <- c(1, 2, NA_real_, tagged_missing(c("a", "z")))
#' y <- recode(x, `1` = 10)
#' missing_tag(y)
#'
#' recode(x, `1` = 10, .missing = -99)
#' @export
recode <- function(.x, ..., .default = NULL, .missing = NULL) {
    if (is.factor(.x)) {
        return(dplyr::recode(
            .x, ..., .default = .default, .missing = .missing
        ))
    }

    if (typeof(.x) %in% c("double", "integer")) {
        return(.recode_numeric_like(
            .x, ..., .default = .default, .missing = .missing
        ))
    }

    if (is.character(.x)) {
        return(dplyr::recode(
            .x, ..., .default = .default, .missing = .missing
        ))
    }

    dplyr::recode(
        .x, ..., .default = .default, .missing = .missing
    )
}

.recode_numeric_like <- function(.x, ..., .default = NULL, .missing = NULL) {
    prepared <- .prepare_numeric_recode(
        .x,
        lapply(rlang::list2(...), .recode_data, source = .x),
        .recode_data(.default, source = .x),
        .recode_data(.missing, source = .x)
    )
    result <- .recode_numeric_legacy(
        prepared$source,
        prepared$replacements,
        .default = prepared$default,
        .missing = prepared$missing
    )

    missing_positions <- is.na(prepared$source)
    if (is.null(.missing) && any(missing_positions)) {
        if (typeof(result) != typeof(prepared$source)) {
            stop(
                "A non-numeric recode cannot preserve numeric missing ",
                "payloads; supply `.missing` explicitly.",
                call. = FALSE
            )
        }
        result[missing_positions] <- prepared$source[missing_positions]
    }

    if (typeof(result) == typeof(prepared$source)) {
        result <- vctrs::vec_restore(result, prepared$restore_to)
    }
    result
}

.prepare_numeric_recode <- function(.x, replacements, default, missing) {
    source <- vctrs::vec_data(.x)
    values <- c(replacements, list(default, missing))
    numeric_values <- Filter(
        function(value) {
            !is.null(value) && typeof(value) %in% c("double", "integer")
        },
        values
    )

    if (is.double(source)) {
        cast <- as.double
        restore_to <- .x
    } else {
        lossless_integer <- all(vapply(
            numeric_values,
            function(value) {
                if (is.double(value) && any(is.na(value))) {
                    return(FALSE)
                }
                tryCatch(
                    {
                        vctrs::vec_cast(value, integer())
                        TRUE
                    },
                    error = function(condition) FALSE
                )
            },
            logical(1)
        ))
        if (lossless_integer) {
            cast <- as.integer
            restore_to <- .x
        } else {
            cast <- as.double
            source <- as.double(source)
            restore_to <- .promote_integer_restore_target(.x)
        }
    }

    cast_numeric <- function(value) {
        if (!is.null(value) &&
            typeof(value) %in% c("double", "integer")) {
            return(cast(value))
        }
        value
    }

    list(
        source = source,
        replacements = lapply(replacements, cast_numeric),
        default = cast_numeric(default),
        missing = cast_numeric(missing),
        restore_to = restore_to
    )
}

.promote_integer_restore_target <- function(value) {
    target <- as.double(vctrs::vec_data(value))
    target_attributes <- attributes(value)
    classes <- target_attributes$class
    if (length(classes) > 0L &&
        classes[[length(classes)]] == "integer") {
        classes[[length(classes)]] <- "double"
        target_attributes$class <- classes
    }
    labels <- target_attributes$labels
    if (!is.null(labels) && is.integer(labels)) {
        double_labels <- as.double(labels)
        names(double_labels) <- names(labels)
        target_attributes$labels <- double_labels
    }
    attributes(target) <- target_attributes
    target
}

.recode_data <- function(value, source) {
    if (!is.null(value) && typeof(value) %in% c("double", "integer")) {
        if (is.object(value) &&
            (!is.object(source) ||
             !.compatible_recode_classes(value, source))) {
            stop(
                "Class-changing numeric replacements are not supported; ",
                "apply the desired class after recoding.",
                call. = FALSE
            )
        }
        return(vctrs::vec_data(value))
    }
    value
}

.compatible_recode_classes <- function(value, source) {
    if (identical(class(value), class(source))) return(TRUE)
    if (inherits(source, "stata_date") && inherits(value, "Date")) {
        return(TRUE)
    }
    inherits(source, "stata_datetime") && inherits(value, "POSIXct")
}

recode.numeric <- function(.x, ..., .default = NULL, .missing = NULL) {
    # Tagged missings are special NA payloads in otherwise ordinary R doubles.
    # Keep dplyr's exact legacy behavior for vectors without any tags, and take
    # the preserving path only when one of those payloads is present.
    if (!.has_tagged_na(.x)) {
        return(.recode_numeric_legacy(
            .x, rlang::list2(...), .default = .default, .missing = .missing
        ))
    }
    recode(.x, ..., .default = .default, .missing = .missing)
}

#' @export
recode.stata_numeric <- function(
    .x, ..., .default = NULL, .missing = NULL
) {
    .recode_numeric_like(
        .x, ..., .default = .default, .missing = .missing
    )
}

# Package-owned implementation of the legacy dplyr numeric contract. Calling
# dplyr's generic from recode.numeric() would dispatch straight back here, and
# its original numeric method is deliberately not part of dplyr's public API.
.recode_numeric_legacy <- function(
    .x, replacements, .default = NULL, .missing = NULL
) {
    named <- rlang::have_name(replacements)
    if (all(named)) {
        replaced_values <- as.double(names(replacements))
    } else if (all(!named)) {
        replaced_values <- seq_along(replacements)
    } else {
        stop(
            "Either all values must be named, or none must be named.",
            call. = FALSE
        )
    }

    candidates <- Filter(
        Negate(is.null), c(replacements, .default, .missing)
    )
    if (length(candidates) == 0L) {
        stop("No replacements provided.", call. = FALSE)
    }

    size <- length(.x)
    output <- candidates[[1L]][rep(NA_integer_, size)]
    replaced <- rep(FALSE, size)
    for (index in seq_along(replacements)) {
        matches <- .x == replaced_values[[index]]
        output <- .recode_replace_with(
            output,
            matches,
            replacements[[index]],
            paste0("Vector ", index)
        )
        replaced[matches] <- TRUE
    }

    if (is.null(.default) && identical(typeof(.x), typeof(output))) {
        .default <- .x
    }
    observed <- !is.na(.x)
    if (is.null(.default) && sum(replaced & observed) < sum(observed)) {
        warning(
            "Unreplaced values treated as NA as `.x` is not compatible.\n",
            "Please specify replacements exhaustively or supply `.default`.",
            call. = FALSE
        )
    }

    output <- .recode_replace_with(
        output, !replaced & observed, .default, "`.default`"
    )
    .recode_replace_with(output, !observed, .missing, "`.missing`")
}

.recode_replace_with <- function(output, locations, value, name) {
    if (is.null(value)) {
        return(output)
    }

    output_size <- length(output)
    if (!(length(value) %in% c(1L, output_size))) {
        stop(
            name, " must be length ", output_size,
            " or one, not ", length(value), ".",
            call. = FALSE
        )
    }
    if (!identical(typeof(value), typeof(output))) {
        stop(
            name, " must have type ", typeof(output),
            ", not ", typeof(value), ".",
            call. = FALSE
        )
    }
    if (is.object(value) && !identical(class(value), class(output))) {
        stop(
            name, " must have class `", paste(class(output), collapse = "/"),
            "`, not class `", paste(class(value), collapse = "/"), "`.",
            call. = FALSE
        )
    }

    locations[is.na(locations)] <- FALSE
    if (length(value) == 1L) {
        output[locations] <- value
    } else {
        output[locations] <- value[locations]
    }
    output
}

.has_tagged_na <- function(value) {
    .Call(C_dtaparser_has_tagged_na, value)
}

recode.haven_labelled <- function(.x, ..., .default = NULL, .missing = NULL) {
    recode(.x, ..., .default = .default, .missing = .missing)
}

recode.Date <- function(.x, ..., .default = NULL, .missing = NULL) {
    recode(.x, ..., .default = .default, .missing = .missing)
}

recode.POSIXct <- function(.x, ..., .default = NULL, .missing = NULL) {
    recode(.x, ..., .default = .default, .missing = .missing)
}
