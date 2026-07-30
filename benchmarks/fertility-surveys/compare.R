fertility_mismatch_record <- function(category, detail, component = NA_integer_) {
    data.frame(
        category = category, detail = detail, component = as.integer(component),
        pair = NA_character_, stringsAsFactors = FALSE
    )
}

fertility_bind_mismatches <- function(parts) {
    parts <- parts[vapply(parts, nrow, integer(1)) > 0L]
    if (!length(parts)) {
        return(data.frame(
            category = character(), detail = character(), component = integer(),
            pair = character(), stringsAsFactors = FALSE
        ))
    }
    result <- do.call(rbind, parts)
    rownames(result) <- NULL
    unique(result)
}

fertility_mismatch <- function(classification, component = NA_integer_) {
    list(ok = FALSE, classification = classification, component = component,
         mismatches = fertility_mismatch_record(
             fertility_public_mismatch_category(classification), classification, component
         ))
}

fertility_match <- function() {
    list(ok = TRUE, classification = "match", component = NA_integer_,
         mismatches = fertility_bind_mismatches(list()))
}

fertility_public_mismatch_category <- function(detail) {
    if (grepl("tagged|missing-tag", detail)) return("tag-mismatch")
    if (grepl("date|posix|tzone", detail)) return("date-mismatch")
    if (grepl("character|string|encoding", detail)) return("encoding-mismatch")
    if (grepl("attribute|label|format|storage|class|name|dimension|row-count|column-count",
              detail)) return("metadata-mismatch")
    if (grepl("value|missing|nonfinite", detail)) return("value-mismatch")
    "unresolved"
}

fertility_compare_attribute_set <- function(actual, expected, component,
                                              frame = FALSE) {
    ignored <- if (frame) c("names", "row.names", "class") else character()
    actual_attributes <- attributes(actual)
    expected_attributes <- attributes(expected)
    names_union <- sort(unique(c(names(actual_attributes), names(expected_attributes))))
    names_union <- setdiff(names_union, ignored)
    parts <- lapply(names_union, function(name) {
        if (identical(actual_attributes[[name]], expected_attributes[[name]])) {
            return(fertility_bind_mismatches(list()))
        }
        detail <- if (identical(name, "tzone")) "tzone-mismatch" else
            if (identical(name, "class") &&
                any(c(actual_attributes[[name]], expected_attributes[[name]]) %in%
                    c("Date", "POSIXct", "POSIXt"))) "date-class-mismatch" else
            paste0("attribute-", name, "-mismatch")
        fertility_mismatch_record(fertility_public_mismatch_category(detail),
                                  detail, component)
    })
    fertility_bind_mismatches(parts)
}

fertility_compare_column_values <- function(actual, expected, component,
                                             tolerance = 1e-7) {
    parts <- list()
    actual_missing <- is.na(actual)
    expected_missing <- is.na(expected)
    if (!identical(actual_missing, expected_missing)) {
        parts[[length(parts) + 1L]] <- fertility_mismatch_record(
            "value-mismatch", "missing-position-mismatch", component
        )
    }
    if (is.numeric(actual) && is.numeric(expected)) {
        if (!identical(is.nan(actual), is.nan(expected))) {
            parts[[length(parts) + 1L]] <- fertility_mismatch_record(
                "value-mismatch", "missing-kind-mismatch", component
            )
        }
        if (is.double(actual) && is.double(expected) &&
            !identical(haven::na_tag(actual), haven::na_tag(expected))) {
            parts[[length(parts) + 1L]] <- fertility_mismatch_record(
                "tag-mismatch", "tagged-missing-mismatch", component
            )
        }
    }
    comparable <- !actual_missing & !expected_missing
    if (!any(comparable)) return(fertility_bind_mismatches(parts))
    actual_values <- unclass(actual[comparable])
    expected_values <- unclass(expected[comparable])
    date_like <- inherits(actual, c("Date", "POSIXct", "POSIXt")) ||
        inherits(expected, c("Date", "POSIXct", "POSIXt"))
    detail <- if (date_like) "date-value-mismatch" else
        if (is.character(actual) || is.character(expected)) "encoding-value-mismatch" else
        "value-mismatch"
    equal <- TRUE
    if (is.numeric(actual_values) && is.numeric(expected_values)) {
        actual_finite <- is.finite(actual_values)
        expected_finite <- is.finite(expected_values)
        if (!identical(actual_finite, expected_finite) ||
            !identical(actual_values[!actual_finite],
                       expected_values[!expected_finite])) {
            parts[[length(parts) + 1L]] <- fertility_mismatch_record(
                if (date_like) "date-mismatch" else "value-mismatch",
                if (date_like) "date-nonfinite-mismatch" else "nonfinite-mismatch",
                component
            )
        }
        finite_both <- actual_finite & expected_finite
        if (any(finite_both)) {
            value_tolerance <- if (date_like) 0 else tolerance
            equal <- if (is.double(actual_values) || is.double(expected_values)) {
                all(abs(actual_values[finite_both] - expected_values[finite_both]) <=
                    value_tolerance)
            } else identical(actual_values[finite_both], expected_values[finite_both])
        }
    } else {
        equal <- identical(actual_values, expected_values)
    }
    if (!equal) {
        parts[[length(parts) + 1L]] <- fertility_mismatch_record(
            fertility_public_mismatch_category(detail), detail, component
        )
    }
    fertility_bind_mismatches(parts)
}

fertility_compare_pair <- function(actual, expected, tolerance = 1e-7) {
    parts <- list()
    if (!identical(nrow(actual), nrow(expected))) {
        parts[[length(parts) + 1L]] <- fertility_mismatch_record(
            "metadata-mismatch", "row-count-mismatch"
        )
    }
    if (!identical(ncol(actual), ncol(expected))) {
        parts[[length(parts) + 1L]] <- fertility_mismatch_record(
            "metadata-mismatch", "column-count-mismatch"
        )
    }
    if (!identical(names(actual), names(expected))) {
        parts[[length(parts) + 1L]] <- fertility_mismatch_record(
            "metadata-mismatch", "name-mismatch"
        )
    }
    parts[[length(parts) + 1L]] <- fertility_compare_attribute_set(
        actual, expected, NA_integer_, frame = TRUE
    )
    count <- min(length(actual), length(expected))
    if (count > 0L) for (i in seq_len(count)) {
        if (!identical(typeof(actual[[i]]), typeof(expected[[i]]))) {
            parts[[length(parts) + 1L]] <- fertility_mismatch_record(
                "metadata-mismatch", "storage-type-mismatch", i
            )
        }
        parts[[length(parts) + 1L]] <- fertility_compare_attribute_set(
            actual[[i]], expected[[i]], i
        )
        common_length <- min(length(actual[[i]]), length(expected[[i]]))
        if (common_length > 0L) {
            parts[[length(parts) + 1L]] <- fertility_compare_column_values(
                actual[[i]][seq_len(common_length)],
                expected[[i]][seq_len(common_length)], i, tolerance
            )
        }
    }
    fertility_bind_mismatches(parts)
}

fertility_first_result <- function(mismatches, internal = FALSE) {
    if (!nrow(mismatches)) return(fertility_match())
    classification <- if (internal) "internal-collector-mismatch" else
        mismatches$detail[[1L]]
    list(ok = FALSE, classification = classification,
         component = mismatches$component[[1L]], mismatches = mismatches)
}

fertility_compare_internal <- function(direct, rust_vectors, tolerance = 0) {
    fertility_first_result(
        fertility_compare_pair(direct, rust_vectors, tolerance), internal = TRUE
    )
}

fertility_compare_haven <- function(actual, expected, tolerance = 1e-7) {
    fertility_first_result(fertility_compare_pair(actual, expected, tolerance))
}
