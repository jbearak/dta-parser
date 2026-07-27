fertility_mismatch <- function(classification, component = NA_integer_) {
    list(ok = FALSE, classification = classification, component = component)
}

fertility_match <- function() {
    list(ok = TRUE, classification = "match", component = NA_integer_)
}

fertility_compare_internal <- function(direct, rust_vectors) {
    if (identical(direct, rust_vectors)) return(fertility_match())
    fertility_mismatch("internal-collector-mismatch")
}

fertility_compare_attributes <- function(actual, expected, component) {
    if (identical(attributes(actual), attributes(expected))) return(NULL)
    fertility_mismatch("attribute-mismatch", component)
}

fertility_compare_values <- function(actual, expected, component,
                                     tolerance = 1e-7) {
    if (!identical(is.na(actual), is.na(expected))) {
        return(fertility_mismatch("missing-position-mismatch", component))
    }
    if (is.numeric(actual) && is.numeric(expected) &&
        !identical(is.nan(actual), is.nan(expected))) {
        return(fertility_mismatch("missing-kind-mismatch", component))
    }
    if (is.numeric(actual) && is.numeric(expected)) {
        if (!identical(haven::na_tag(actual), haven::na_tag(expected))) {
            return(fertility_mismatch("tagged-missing-mismatch", component))
        }
        present <- !is.na(actual)
        actual_values <- unclass(actual[present])
        expected_values <- unclass(expected[present])
        if (is.double(actual) || is.double(expected)) {
            actual_finite <- is.finite(actual_values)
            expected_finite <- is.finite(expected_values)
            if (!identical(actual_finite, expected_finite) ||
                !identical(actual_values[!actual_finite],
                           expected_values[!expected_finite])) {
                equal <- FALSE
            } else {
                differences <- abs(actual_values[actual_finite] -
                                   expected_values[expected_finite])
                equal <- all(differences <= tolerance)
            }
        } else {
            equal <- identical(actual_values, expected_values)
        }
    } else {
        equal <- identical(unclass(actual), unclass(expected))
    }
    if (!equal) fertility_mismatch("value-mismatch", component) else NULL
}

fertility_compare_haven <- function(actual, expected, tolerance = 1e-7) {
    if (!identical(dim(actual), dim(expected))) {
        return(fertility_mismatch("dimension-mismatch"))
    }
    if (!identical(names(actual), names(expected))) {
        return(fertility_mismatch("name-mismatch"))
    }
    frame_attributes <- function(value) {
        attributes(value)[setdiff(names(attributes(value)), c("names", "row.names"))]
    }
    if (!identical(frame_attributes(actual), frame_attributes(expected))) {
        return(fertility_mismatch("data-frame-attribute-mismatch"))
    }
    for (i in seq_along(actual)) {
        if (!identical(typeof(actual[[i]]), typeof(expected[[i]]))) {
            return(fertility_mismatch("storage-type-mismatch", i))
        }
        mismatch <- fertility_compare_attributes(actual[[i]], expected[[i]], i)
        if (!is.null(mismatch)) return(mismatch)
        mismatch <- fertility_compare_values(actual[[i]], expected[[i]], i, tolerance)
        if (!is.null(mismatch)) return(mismatch)
    }
    fertility_match()
}
