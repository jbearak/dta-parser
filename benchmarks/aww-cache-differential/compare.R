aww_empty_disputes <- function() data.frame(
    kind = character(), category = character(), reader = character(),
    column = integer(), row = numeric(), skip = numeric(), n_max = integer(),
    attribute = character(), dtaparser = I(list()), haven = I(list()),
    stringsAsFactors = FALSE
)

aww_dispute <- function(kind, category, reader = "both",
                        column = NA_integer_, row = NA_real_,
                        skip = NA_real_, n_max = NA_integer_, attribute = "",
                        dtaparser = NULL, haven = NULL) {
    data.frame(
        kind = kind, category = category, reader = reader,
        column = as.integer(column), row = as.double(row),
        skip = as.double(skip), n_max = as.integer(n_max), attribute = attribute,
        dtaparser = I(list(dtaparser)), haven = I(list(haven)),
        stringsAsFactors = FALSE
    )
}

aww_bind_disputes <- function(parts) {
    parts <- parts[vapply(parts, nrow, integer(1)) > 0L]
    if (!length(parts)) return(aww_empty_disputes())
    result <- do.call(rbind, parts)
    rownames(result) <- NULL
    result
}

aww_simplify_private <- function(value) {
    if (is.null(value)) return(NULL)
    if (length(value) > 10000L) return(list(digest = aww_sha256_raw(paste(capture.output(dput(value)), collapse = "\n"))))
    value
}

aww_label_entries <- function(labels) {
    if (is.null(labels)) return(list())
    result <- lapply(seq_along(labels), function(index) {
        value <- unname(labels[[index]])
        tag <- if (is.double(value)) haven::na_tag(value) else NA_character_
        code <- if (!is.na(tag)) paste0(".", tag) else if (is.na(value)) "." else
            format(value, scientific = FALSE, trim = TRUE, digits = 17)
        list(code = code, text = names(labels)[[index]])
    })
    keys <- vapply(result, function(entry) {
        if (startsWith(entry$code, ".")) {
            tag <- substring(entry$code, 2L)
            return(1e100 + if (nzchar(tag)) match(tag, letters) else 0)
        }
        suppressWarnings(as.numeric(entry$code))
    }, numeric(1))
    result[order(keys)]
}

aww_compare_indexed_attribute <- function(left, right, key, category, column) {
    if (identical(left, right)) return(aww_empty_disputes())
    if (identical(key, "labels")) {
        left <- aww_label_entries(left)
        right <- aww_label_entries(right)
    }
    count <- max(length(left), length(right))
    if (!count) return(aww_empty_disputes())
    aww_bind_disputes(lapply(seq_len(count), function(index) {
        actual <- if (index <= length(left)) left[[index]] else NULL
        expected <- if (index <= length(right)) right[[index]] else NULL
        if (identical(actual, expected)) return(aww_empty_disputes())
        aww_dispute(
            "metadata", category, column = column,
            attribute = paste0(key, ":", index),
            dtaparser = aww_simplify_private(actual),
            haven = aww_simplify_private(expected)
        )
    }))
}

aww_compare_attributes <- function(left, right, column = NA_integer_, frame = FALSE) {
    left_attributes <- attributes(left)
    right_attributes <- attributes(right)
    ignored <- if (frame) c("names", "row.names") else character()
    keys <- setdiff(sort(unique(c(names(left_attributes), names(right_attributes)))), ignored)
    aww_bind_disputes(lapply(keys, function(key) {
        if (identical(left_attributes[[key]], right_attributes[[key]])) return(aww_empty_disputes())
        category <- if (key %in% c("label", "notes", "labels")) "label" else
            if (identical(key, "format.stata")) "format" else
            if (key %in% c("class", "tzone")) "class" else "attribute"
        if (key %in% c("notes", "labels")) {
            return(aww_compare_indexed_attribute(
                left_attributes[[key]], right_attributes[[key]], key, category, column
            ))
        }
        aww_dispute(
            "metadata", category, column = column, attribute = key,
            dtaparser = aww_simplify_private(left_attributes[[key]]),
            haven = aww_simplify_private(right_attributes[[key]])
        )
    }))
}

aww_compare_metadata <- function(left, right, column_offset = 0L,
                                 compare_frame = TRUE, compare_dimensions = TRUE) {
    parts <- list()
    if (compare_dimensions && !identical(ncol(left), ncol(right))) {
        parts[[length(parts) + 1L]] <- aww_dispute(
            "metadata", "dimension", attribute = "ncol",
            dtaparser = ncol(left), haven = ncol(right)
        )
    }
    count <- max(length(names(left)), length(names(right)))
    if (count > 0L) for (local_column in seq_len(count)) {
        actual <- if (local_column <= ncol(left)) names(left)[[local_column]] else NULL
        expected <- if (local_column <= ncol(right)) names(right)[[local_column]] else NULL
        if (!identical(actual, expected)) {
            parts[[length(parts) + 1L]] <- aww_dispute(
                "metadata", "name", column = column_offset + local_column,
                attribute = "name", dtaparser = actual, haven = expected
            )
        }
    }
    if (compare_frame) {
        parts[[length(parts) + 1L]] <- aww_compare_attributes(left, right, frame = TRUE)
    }
    shared <- min(ncol(left), ncol(right))
    if (shared > 0L) for (local_column in seq_len(shared)) {
        column <- column_offset + local_column
        if (!identical(typeof(left[[local_column]]), typeof(right[[local_column]]))) {
            parts[[length(parts) + 1L]] <- aww_dispute(
                "metadata", "storage", column = column, attribute = "typeof",
                dtaparser = typeof(left[[local_column]]), haven = typeof(right[[local_column]])
            )
        }
        parts[[length(parts) + 1L]] <- aww_compare_attributes(
            left[[local_column]], right[[local_column]], column
        )
    }
    aww_bind_disputes(parts)
}

aww_cell_kind <- function(value) {
    if (length(value) != 1L) return("invalid")
    if (is.double(value) && is.nan(value)) return("nan")
    if (is.na(value)) {
        tag <- if (is.double(value)) haven::na_tag(value) else NA_character_
        if (!is.na(tag)) return(paste0(".", tag))
        return(".")
    }
    if (is.character(value)) return("string")
    if (is.infinite(value)) return(if (value > 0) "+inf" else "-inf")
    "value"
}

aww_cell_kinds <- function(value) {
    kinds <- rep.int("value", length(value))
    if (!length(value)) return(kinds)
    missing <- is.na(value)
    if (is.character(value)) {
        kinds[] <- "string"
        kinds[missing] <- "."
        return(kinds)
    }
    if (is.double(value)) {
        nan <- is.nan(value)
        kinds[nan] <- "nan"
        missing <- missing & !nan
        if (any(missing)) {
            tags <- haven::na_tag(value[missing])
            kinds[missing] <- ifelse(is.na(tags), ".", paste0(".", tags))
        }
    } else {
        kinds[missing] <- "."
    }
    raw_value <- unclass(value)
    infinite <- !missing & is.infinite(raw_value)
    kinds[infinite & raw_value > 0] <- "+inf"
    kinds[infinite & raw_value < 0] <- "-inf"
    kinds
}

aww_compare_values <- function(left, right, column_offset, row_offset,
                               n_max = NA_integer_, storage = character(),
                               tolerance = 1e-7) {
    parts <- list()
    if (!identical(nrow(left), nrow(right))) {
        parts[[length(parts) + 1L]] <- aww_dispute(
            "metadata", "dimension", row = row_offset + 1,
            skip = row_offset, n_max = n_max, attribute = "tile-nrow",
            dtaparser = nrow(left), haven = nrow(right)
        )
    }
    if (!identical(names(left), names(right))) {
        parts[[length(parts) + 1L]] <- aww_dispute(
            "metadata", "name", attribute = "projection",
            dtaparser = names(left), haven = names(right)
        )
    }
    count <- min(ncol(left), ncol(right))
    rows <- min(nrow(left), nrow(right))
    if (!count || !rows) return(aww_bind_disputes(parts))
    for (local_column in seq_len(count)) {
        actual <- left[[local_column]][seq_len(rows)]
        expected <- right[[local_column]][seq_len(rows)]
        actual_kind <- aww_cell_kinds(actual)
        expected_kind <- aww_cell_kinds(expected)
        mismatch <- actual_kind != expected_kind
        comparable <- !mismatch & actual_kind == "value"
        date_like <- inherits(actual, c("Date", "POSIXct", "POSIXt")) ||
            inherits(expected, c("Date", "POSIXct", "POSIXt"))
        if (any(comparable)) {
            left_values <- unclass(actual[comparable])
            right_values <- unclass(expected[comparable])
            if (is.numeric(left_values) && is.numeric(right_values)) {
                delta <- abs(left_values - right_values)
                source_storage <- if (local_column <= length(storage)) storage[[local_column]] else NA_character_
                limit <- if (date_like || source_storage %in% c("byte", "int", "long")) 0 else
                    if (source_storage %in% c("float", "double")) tolerance else 0
                numeric_mismatch <- is.na(delta) | delta > limit
                both_zero <- left_values == 0 & right_values == 0
                numeric_mismatch[both_zero] <- (1 / left_values[both_zero]) !=
                    (1 / right_values[both_zero])
                mismatch[which(comparable)] <- numeric_mismatch
            } else {
                mismatch[which(comparable)] <- left_values != right_values |
                    xor(is.na(left_values), is.na(right_values))
            }
        }
        string_rows <- !mismatch & actual_kind == "string"
        if (any(string_rows)) {
            mismatch[which(string_rows)] <- actual[string_rows] != expected[string_rows]
        }
        indices <- which(mismatch)
        if (length(indices)) for (index in indices) {
            category <- if (actual_kind[[index]] != expected_kind[[index]]) "missing" else
                if (date_like) "date" else if (is.character(actual)) "string" else "value"
            parts[[length(parts) + 1L]] <- aww_dispute(
                "cell", category,
                column = column_offset + local_column,
                row = row_offset + index,
                dtaparser = list(kind = actual_kind[[index]], value = aww_simplify_private(actual[index])),
                haven = list(kind = expected_kind[[index]], value = aww_simplify_private(expected[index]))
            )
        }
    }
    aww_bind_disputes(parts)
}
