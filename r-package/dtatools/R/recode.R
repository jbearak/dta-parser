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
#' [dta_byte()].
#'
#' A recode from numeric to a non-numeric type cannot retain tagged-NA
#' payloads. If `.x` contains missing values and the result is non-numeric,
#' supply `.missing` explicitly to choose their new representation. Numeric
#' widening from integer to double preserves missing values automatically.
#' `dtatools::recode()` rejects classed replacements such as `Date` or factor
#' values for bare numeric sources rather than silently dropping the replacement
#' class. Stata date and datetime sources accept `Date` and `POSIXct`
#' replacements, respectively. For other class changes, apply the desired class
#' after recoding.
#'
#' Character recoding uses character values and does not restore source labels
#' or Stata string-width declarations. Character-backed `haven_labelled` inputs
#' follow this rule. Factor recoding changes levels in their existing order;
#' character replacements retain factor attributes, while non-character
#' replacements return the corresponding replacement vector. Factor replacement
#' lengths are checked against the number of levels, including unused levels.
#' Metadata-vector notes and characteristics are restored by their transparent
#' wrapper. The wrapper's numeric route retains the legacy numeric policy.
#'
#' Character and factor recoding is implemented by dtatools. Existing visible
#' S3 `recode` methods and methods registered with an already loaded dplyr
#' namespace keep their dispatch context. Numeric inputs to this public function
#' continue to use the Stata-preserving policy above.
#'
#' When the dtatools namespace is loaded, `dplyr::recode()` dispatches here
#' for bare numeric, `haven_labelled`, `Date`, and `POSIXct` vectors. This also
#' applies when `recode()` is called inside `dplyr::mutate()`, regardless of
#' package attachment order. For numeric vectors without tags, this method
#' retains dplyr's exact legacy behavior. Tagged numeric vectors use
#' `dtatools::recode()` and preserve unmatched tag payloads and numeric metadata.
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
        return(.recode_dispatch(
            .x, ..., .default = .default, .missing = .missing
        ))
    }

    if (typeof(.x) %in% c("double", "integer")) {
        return(.recode_numeric_like(
            .x, ..., .default = .default, .missing = .missing
        ))
    }

    .recode_dispatch(
        .x, ..., .default = .default, .missing = .missing
    )
}

# Keep real S3 call context for existing external methods, including NextMethod().
# The generic is private: the public numeric branch above retains its stronger
# Stata policy. Only public S3 lookup and base dispatch APIs are used; dplyr's recode
# implementation is never called and this does not load an optional namespace.
.recode_dispatch <- function(.x, ..., .default = NULL, .missing = NULL) {
    recode <- function(.x, ..., .default = NULL, .missing = NULL) {
        UseMethod("recode")
    }
    methods <- list(
        character = .recode_character,
        factor = .recode_factor,
        numeric = recode.numeric,
        dta_numeric = recode.dta_numeric,
        haven_labelled = recode.haven_labelled,
        Date = recode.Date,
        POSIXct = recode.POSIXct,
        dtatools_dta_metadata_vector = recode.dtatools_dta_metadata_vector
    )
    if ("dplyr" %in% loadedNamespaces()) {
        namespace <- asNamespace("dplyr")
        # getS3method normally checks visible functions before the registry.
        # The former wrapper called the generic from our namespace, where the
        # registry wins over methods visible above that namespace. Isolate the
        # public generic binding to query its registry without global shadowing.
        lookup <- new.env(parent = emptyenv())
        lookup$recode <- getExportedValue("dplyr", "recode")
        for (class in c(class(.x), "default")) {
            # These methods were already visible in the old wrapper's namespace
            # and therefore preceded any foreign registration for the same slot.
            if (class %in% c("numeric", "dta_numeric", "haven_labelled",
                             "Date", "POSIXct", "dtatools_dta_metadata_vector")) {
                next
            }
            method <- utils::getS3method(
                "recode", class, optional = TRUE, envir = lookup
            )
            builtin <- NULL
            if (class %in% c("character", "factor")) {
                builtin <- utils::getS3method(
                    "recode", class, optional = TRUE, envir = namespace
                )
            }
            is_builtin <- !is.null(builtin) && identical(method, builtin) &&
                identical(environment(builtin), namespace)
            if (!is.null(method) && !is_builtin) {
                methods[[class]] <- method
            }
        }
    }
    # Call-local method bindings participate in both UseMethod and NextMethod.
    # A table registered in this frame would not: R searches the top environment.
    for (class in names(methods)) {
        assign(paste0("recode.", class), methods[[class]], envir = environment())
    }
    recode(.x, ..., .default = .default, .missing = .missing)
}

# Adapted from dplyr 1.2.1 R/recode.R at
# 95740975c465c29cdb2abdfa13effddb948444dc; MIT notice in inst/NOTICE.
# Keep template selection, named duplicates/NULLs, promise forcing, factor-level
# replacement, and asymmetric replacement-class checks. Helpers are owned here.
.recode_character <- function(.x, ..., .default = NULL, .missing = NULL) {
    .x <- as.character(.x)
    values <- rlang::list2(...)
    .recode_check_names(values)
    template <- .recode_template(values, .default, .missing)
    out <- template[rep(NA_integer_, length(.x))]
    replaced <- rep(FALSE, length(.x))
    for (name in names(values)) {
        out <- .recode_replace_character_factor(
            out, .x == name, values[[name]], paste0("`", name, "`")
        )
        replaced[.x == name] <- TRUE
    }
    .default <- .recode_default(.default, .x, out, replaced)
    out <- .recode_replace_character_factor(
        out, !replaced & !is.na(.x), .default, "`.default`"
    )
    .recode_replace_character_factor(out, is.na(.x), .missing, "`.missing`")
}

.recode_factor <- function(.x, ..., .default = NULL, .missing = NULL) {
    values <- rlang::list2(...)
    if (length(values) == 0L) {
        rlang::abort("No replacements provided.")
    }
    .recode_check_names(values)
    if (!is.null(.missing)) {
        rlang::abort("`.missing` is not supported for factors.")
    }
    template <- .recode_template(values, .default, .missing)
    out <- template[rep(NA_integer_, length(levels(.x)))]
    replaced <- rep(FALSE, length(out))
    for (name in names(values)) {
        out <- .recode_replace_character_factor(
            out, levels(.x) == name, values[[name]], paste0("`", name, "`")
        )
        replaced[levels(.x) == name] <- TRUE
    }
    .default <- .recode_default(.default, .x, out, replaced)
    out <- .recode_replace_character_factor(out, !replaced, .default, "`.default`")
    if (is.character(out)) {
        levels(.x) <- out
        .x
    } else {
        out[as.integer(.x)]
    }
}

.recode_check_names <- function(values) {
    bad <- which(!rlang::have_name(values)) + 1L
    if (length(bad)) {
        positions <- as.character(bad)
        if (length(positions) > 6L) {
            positions <- c(positions[seq_len(5L)], "...")
        }
        rlang::abort(paste0(
            if (length(bad) == 1L) "Argument " else "Arguments ",
            paste(positions, collapse = ", "), " must be named."
        ))
    }
}

.recode_template <- function(values, .default, .missing) {
    candidates <- Filter(Negate(is.null), c(values, .default, .missing))
    if (!length(candidates)) {
        rlang::abort("No replacements provided.")
    }
    candidates[[1L]]
}

.recode_default <- function(default, x, out, replaced) {
    if (is.null(default)) {
        if (is.factor(x)) {
            default <- if (is.character(out) || is.factor(out)) levels(x) else out[NA_integer_]
        } else if (identical(typeof(x), typeof(out))) {
            default <- x
        }
    }
    if (is.null(default) && sum(replaced & !is.na(x)) < length(out[!is.na(x)])) {
        rlang::warn(c(
            "Unreplaced values treated as NA as `.x` is not compatible. ",
            "Please specify replacements exhaustively or supply `.default`."
        ))
    }
    default
}

.recode_replace_character_factor <- function(output, locations, value, name) {
    if (is.null(value)) {
        return(output)
    }
    size <- length(output)
    if (!(length(value) %in% c(1L, size))) {
        rlang::abort(paste0(
            name, " must be length ", size,
            if (size == 1L) "" else " or one", ", not ", length(value), "."
        ))
    }
    if (!identical(typeof(value), typeof(output))) {
        rlang::abort(paste0(
            name, " must have type ", typeof(output), ", not ", typeof(value), "."
        ))
    }
    if (is.object(value) && !identical(class(value), class(output))) {
        rlang::abort(paste0(
            name, " must have class `", paste(class(output), collapse = "/"),
            "`, not class `", paste(class(value), collapse = "/"), "`."
        ))
    }
    locations[is.na(locations)] <- FALSE
    if (length(value) == 1L) {
        output[locations] <- value
    } else {
        output[locations] <- value[locations]
    }
    output
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
    if (inherits(source, "dta_date") && inherits(value, "Date")) {
        return(TRUE)
    }
    inherits(source, "dta_datetime") && inherits(value, "POSIXct")
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
recode.dta_numeric <- function(
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
    .Call(C_dtatools_has_tagged_na, value)
}

recode.haven_labelled <- function(.x, ..., .default = NULL, .missing = NULL) {
    if (is.character(.x)) {
        return(.recode_character(
            .x, ..., .default = .default, .missing = .missing
        ))
    }
    recode(.x, ..., .default = .default, .missing = .missing)
}

recode.Date <- function(.x, ..., .default = NULL, .missing = NULL) {
    recode(.x, ..., .default = .default, .missing = .missing)
}

recode.POSIXct <- function(.x, ..., .default = NULL, .missing = NULL) {
    recode(.x, ..., .default = .default, .missing = .missing)
}

#' @export
recode.dtatools_dta_metadata_vector <- function(
    .x, ..., .default = NULL, .missing = NULL
) {
    result <- .recode_dispatch(
        .dta_metadata_vector_base(.x), ...,
        .default = .default, .missing = .missing
    )
    .copy_dta_metadata_attributes(.x, result)
}
