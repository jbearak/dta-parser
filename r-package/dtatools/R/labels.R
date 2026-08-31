#' Get and set Stata label metadata
#'
#' Dependency-free helpers for dataset labels, variable labels, and numeric
#' value-label tables. The variable- and value-label function names and common
#' call forms are compatible with `labelled`; `dataset_label()` is a dtatools
#' addition. Validation and mutation follow Stata's metadata model and preserve
#' the dtatools package's compact columns and unrelated attributes.
#'
#' @section Getter results:
#' For a vector, `var_label()` returns one character value or `NULL`, and
#' `val_labels()` returns a named numeric vector or `NULL`. For a data frame,
#' each returns a named list with one element per column, including `NULL`
#' entries. `dataset_label()` accepts only a data frame or tibble and returns
#' one character value or `NULL`.
#'
#' @section Setting labels:
#' Replacement functions modify the supplied metadata. On a data frame,
#' replacement values must be a named list; a bare `NULL` clears that metadata
#' from every column. `set_var_labels()` and `set_val_labels()` support
#' named column updates in `...` and a programmatic named list in `.labels`.
#' They also accept vectors for pipeline use. Unknown, duplicate, unnamed, or
#' overlapping column updates fail atomically.
#'
#' `set_var_label()` sets the variable label of one column named without
#' quotes, mirroring Stata's `label variable`.
#'
#' `set_var_label()`, `set_var_labels()`, `set_val_labels()`, and the data-frame
#' replacement forms mutate the data frame by reference, as `gen()` and
#' `replace_values()` do: the caller sees the new metadata whether or not it
#' reassigns the result, and so does any other binding to the same data frame.
#' Use `copy_data()` first when isolation is required. The vector forms cannot
#' mutate by reference and still return a copy.
#'
#' `NULL`, `NA_character_`, and `""` all remove a variable or dataset label.
#' Empty or missing value-label text is discarded. If no entries remain, the
#' `labels` attribute is removed. Duplicate display text is allowed, but every
#' numeric code must be unique.
#'
#' @section Stata 19 compatibility:
#' Value-label codes must be whole, nonmissing values in Stata's `long` range,
#' -2,147,483,647 through 2,147,483,620, or tagged missings `.a` through `.z`.
#' System missing `.`, ordinary R `NA`/`NaN`, fractions, and infinities cannot
#' be value-label codes.
#'
#' Metadata beyond Stata 19's documented limits is stored unchanged in R with
#' one aggregated warning: 80 Unicode characters for dataset and variable
#' labels, 65,536 entries per value-label table, and 32,000 UTF-8 bytes per
#' value-label text. `save_dta()` rejects over-limit metadata rather than
#' truncating it.
#'
#' Adding a value-label table to an ordinary numeric vector adds the
#' dependency-free classes `haven_labelled`, `vctrs_vctr`, and its storage type.
#' Date and POSIXct classes, time zones, Stata formats, and unrelated attributes
#' are preserved. Removing the table removes only compatibility classes added
#' for the label table and retains unrelated classes.
#'
#' See the
#' \href{https://github.com/jbearak/dta-parser/blob/main/docs/r-label-metadata.md}{R label metadata guide}
#' for the supported call surface and the version-specific comparison with
#' `labelled`.
#'
#' @param x A vector or data frame.
#' @param data A data frame or tibble.
#' @param value New label metadata. Data-frame replacement forms require a
#'   named list or `NULL`.
#' @param .data A vector or data frame to update.
#' @param ... Named column updates for a data frame. For a vector, supply one
#'   variable label or one or more named value-label codes.
#' @param .labels A programmatic label value for a vector, or a named list of
#'   column updates for a data frame.
#' @param variable One unquoted column name.
#' @param label One variable label, or `NULL` to remove it.
#' @return Getters return the metadata described above. Replacement functions
#'   and `set_*()` functions return the updated vector or data frame; the
#'   data-frame forms return it invisibly, because they have already mutated
#'   it by reference.
#' @examples
#' status <- c(1, 2, 1)
#' var_label(status) <- "Interview status"
#' val_labels(status) <- c(Complete = 1, Refused = 2)
#'
#' survey <- data.frame(status = status, stratum = c(1, 1, 2))
#' dataset_label(survey) <- "Baseline survey"
#' survey <- set_var_labels(
#'     survey,
#'     status = "Interview status",
#'     .labels = list(stratum = "Sampling stratum")
#' )
#' var_label(survey)
#' val_labels(survey$status)
#' @export
var_label <- function(x) {
    .validate_label_object(x)
    if (is.data.frame(x)) {
        return(stats::setNames(
            lapply(x, attr, which = "label", exact = TRUE),
            names(x)
        ))
    }

    attr(x, "label", exact = TRUE)
}

#' @rdname var_label
#' @export
val_labels <- function(x) {
    .validate_label_object(x)
    if (is.data.frame(x)) {
        return(stats::setNames(
            lapply(x, attr, which = "labels", exact = TRUE),
            names(x)
        ))
    }

    attr(x, "labels", exact = TRUE)
}

#' @rdname var_label
#' @export
dataset_label <- function(data) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame", call. = FALSE)
    }

    attr(data, "label", exact = TRUE)
}

.validate_label_object <- function(value, argument = "x") {
    vector_types <- c(
        "logical", "integer", "double", "complex", "character", "raw",
        "list", "expression"
    )
    if (!is.data.frame(value) && !typeof(value) %in% vector_types) {
        stop(sprintf("`%s` must be a vector or data frame", argument),
             call. = FALSE)
    }
    invisible(NULL)
}

.normalize_text_label <- function(value, argument = "value") {
    if (is.null(value)) return(NULL)
    if (!is.character(value) || length(value) != 1L) {
        stop(sprintf("`%s` must be one character value or NULL", argument),
             call. = FALSE)
    }
    if (is.na(value) || identical(value, "")) NULL else value
}

.validate_column_updates <- function(data, value, normalize, argument) {
    if (!is.list(value)) {
        stop(sprintf("`%s` must be a named list or NULL", argument),
             call. = FALSE)
    }
    update_names <- names(value)
    if (length(value) > 0L &&
        (is.null(update_names) || anyNA(update_names) ||
         any(update_names == ""))) {
        stop(sprintf("`%s` must have one non-empty name per update", argument),
             call. = FALSE)
    }
    if (anyDuplicated(update_names)) {
        stop(sprintf("`%s` must not contain duplicate column names", argument),
             call. = FALSE)
    }
    unknown <- setdiff(update_names, names(data))
    if (length(unknown) > 0L) {
        stop(sprintf(
            "Unknown column%s: %s",
            if (length(unknown) == 1L) "" else "s",
            paste(unknown, collapse = ", ")
        ), call. = FALSE)
    }
    duplicated_data_names <- unique(names(data)[
        duplicated(names(data)) | duplicated(names(data), fromLast = TRUE)
    ])
    ambiguous <- intersect(update_names, duplicated_data_names)
    if (length(ambiguous) > 0L) {
        stop(sprintf(
            "ambiguous column name%s: %s",
            if (length(ambiguous) == 1L) "" else "s",
            paste(ambiguous, collapse = ", ")
        ), call. = FALSE)
    }

    stats::setNames(
        lapply(seq_along(value), function(index) {
            normalize(value[[index]], sprintf("%s$%s", argument,
                                               update_names[[index]]))
        }),
        update_names
    )
}

.warn_stata_metadata_limits <- function(violations) {
    if (length(violations) == 0L) return(invisible(NULL))

    warning(
        paste0(
            "Stored unchanged in R, but exceeds Stata 19's documented ",
            "limits: ", paste(violations, collapse = "; "), ". the dtatools package's ",
            "writer will reject this metadata rather than truncate it."
        ),
        call. = FALSE
    )
    invisible(NULL)
}

.text_label_violations <- function(values, kind, limit = 80L) {
    if (!is.list(values)) values <- list(values)
    locations <- names(values)
    if (is.null(locations)) locations <- rep("value", length(values))

    lengths <- vapply(values, function(value) {
        if (is.null(value)) 0L else nchar(value, type = "chars")
    }, integer(1))
    over_limit <- which(lengths > limit)
    if (length(over_limit) == 0L) return(character())

    sprintf(
        "%s `%s` has %d Unicode characters (limit: %d Unicode characters)",
        kind, locations[over_limit], lengths[over_limit], limit
    )
}

.metadata_copy <- function(value) {
    .Call(C_dtatools_metadata_copy, value)
}

.metadata_view <- function(value) {
    .Call(C_dtatools_metadata_view, value)
}

.stata_value_label_code_info <- function(value) {
    missing_codes <- .tab_missing_codes(value)
    tagged <- !is.na(missing_codes) &
        missing_codes >= utf8ToInt("a") & missing_codes <= utf8ToInt("z")
    observed <- is.na(missing_codes)
    observed <- observed & !.invalid_stata_observed(
        value, observed, "long"
    )
    list(
        valid = tagged | observed,
        missing_codes = missing_codes,
        tagged = tagged,
        observed = observed
    )
}

.normalize_value_labels <- function(value, argument = "value") {
    if (is.null(value)) return(NULL)
    if (!is.numeric(value) ||
        !(typeof(value) %in% c("integer", "double")) ||
        !is.null(dim(value))) {
        stop(sprintf("`%s` must be a named numeric vector or NULL", argument),
             call. = FALSE)
    }
    if (length(value) == 0L) return(NULL)

    label_text <- names(value)
    if (is.null(label_text) || length(label_text) != length(value)) {
        stop(sprintf("`%s` must name every value-label code", argument),
             call. = FALSE)
    }
    keep <- !is.na(label_text) & label_text != ""
    value <- value[keep]
    label_text <- label_text[keep]
    if (length(value) == 0L) return(NULL)

    code_info <- .stata_value_label_code_info(value)
    if (any(!code_info$valid)) {
        stop(
            sprintf(
                paste0(
                    "`%s` codes must be nonmissing integers in Stata's long ",
                    "range or extended missings `.a` through `.z`"
                ),
                argument
            ),
            call. = FALSE
        )
    }

    keys <- character(length(value))
    keys[code_info$observed] <- paste0("number:", format(
        value[code_info$observed], scientific = FALSE, trim = TRUE
    ))
    keys[code_info$tagged] <- paste0(
        "missing:", code_info$missing_codes[code_info$tagged]
    )
    if (anyDuplicated(keys)) {
        stop(sprintf("`%s` must not contain duplicate value-label codes",
                     argument), call. = FALSE)
    }

    value <- if (is.integer(value)) as.integer(value) else as.double(value)
    names(value) <- label_text
    value
}

.value_label_limit_violations <- function(count, text, location) {
    violations <- character()
    if (count > 65536L) {
        violations <- c(violations, sprintf(
            "value-label table for `%s` has %s entries (limit: 65,536 entries)",
            location, format(count, big.mark = ",", scientific = FALSE)
        ))
    }

    text_lengths <- nchar(enc2utf8(text), type = "bytes")
    if (any(text_lengths > 32000L)) {
        violations <- c(violations, sprintf(
            paste0(
                "value-label text for `%s` has %s UTF-8 bytes ",
                "(limit: 32,000 UTF-8 bytes)"
            ),
            location,
            format(max(text_lengths), big.mark = ",", scientific = FALSE)
        ))
    }
    violations
}

.value_label_violations <- function(values) {
    if (!is.list(values)) values <- list(value = values)
    locations <- names(values)
    if (is.null(locations)) locations <- rep("value", length(values))
    violations <- character()

    for (index in seq_along(values)) {
        value <- values[[index]]
        if (is.null(value)) next
        violations <- c(violations, .value_label_limit_violations(
            length(value), names(value), locations[[index]]
        ))
    }
    violations
}

.validate_value_label_target <- function(value, labels, argument = "x") {
    if (!is.null(labels) &&
        (!(typeof(value) %in% c("integer", "double")) ||
         is.factor(value) || !is.null(dim(value)))) {
        stop(sprintf(
            "`%s` must be a numeric Stata variable to receive value labels",
            argument
        ), call. = FALSE)
    }
    invisible(NULL)
}

.apply_haven_labelled_class <- function(value, has_labels) {
    classes <- attr(value, "class", exact = TRUE)
    temporal <- inherits(value, "Date") || inherits(value, "POSIXct")

    if (has_labels && !temporal &&
        typeof(value) %in% c("integer", "double") &&
        !inherits(value, "haven_labelled")) {
        if (inherits(value, "stata_numeric")) {
            location <- match("vctrs_vctr", classes)
            classes <- append(classes, "haven_labelled", after = location - 1L)
        } else if (is.null(classes)) {
            storage_class <- typeof(value)
            classes <- c("haven_labelled", "vctrs_vctr", storage_class)
        } else {
            return(value)
        }
        value <- .metadata_copy(value)
        attr(value, "class") <- classes
    }

    if (!has_labels && "haven_labelled" %in% classes) {
        compatibility <- c("haven_labelled", "vctrs_vctr", typeof(value))
        classes <- if (identical(classes, compatibility)) {
            NULL
        } else {
            classes[classes != "haven_labelled"]
        }
        value <- .metadata_copy(value)
        attr(value, "class") <- if (length(classes) == 0L) NULL else classes
    }
    value
}

.get_data_column <- function(data, name) {
    state <- .reference_state(data)
    if (is.null(state)) return(.subset2(data, name))
    state$columns[[name]]
}

# Stores `column` under `name` without copying `data`. The physical frame is
# patched in place, so the caller sees the new metadata whether or not it
# reassigns the result. Reference data holds its generated columns outside
# the physical frame, so those are stored in the reference state instead.
# Positional siblings of the two helpers above, for the branches that clear
# metadata from every column. Those cannot key on the name, because a data
# frame is allowed duplicated names there.
.data_column_at <- function(data, index) {
    state <- .reference_state(data)
    if (is.null(state) || index <= state$physical_count) {
        return(.subset2(data, index))
    }
    state$columns[[.reference_names(data)[[index]]]]
}

.set_data_column_at <- function(data, index, column) {
    state <- .reference_state(data)
    if (!is.null(state)) {
        state$columns[[.reference_names(data)[[index]]]] <- column
        if (index > state$physical_count) return(invisible(NULL))
    }
    .Call(C_dtatools_set_data_column, data, as.integer(index), column)
    invisible(NULL)
}

.set_data_column <- function(data, name, column) {
    state <- .reference_state(data)
    if (is.null(state)) {
        location <- match(name, names(data))
        .Call(C_dtatools_set_data_column, data, as.integer(location), column)
        return(invisible(NULL))
    }
    state$columns[[name]] <- column
    location <- state$locations[[name]]
    if (location <= state$physical_count) {
        .Call(C_dtatools_set_data_column, data, as.integer(location), column)
    }
    invisible(NULL)
}

.apply_variable_label_updates <- function(data, updates) {
    .warn_stata_metadata_limits(
        .text_label_violations(updates, "variable label for")
    )
    for (name in names(updates)) {
        column <- .metadata_copy(.get_data_column(data, name))
        attr(column, "label") <- updates[[name]]
        .set_data_column(data, name, column)
    }
    invisible(data)
}

.apply_value_label_updates <- function(data, updates) {
    for (name in names(updates)) {
        .validate_value_label_target(
            .get_data_column(data, name), updates[[name]],
            paste0("x$", name)
        )
    }
    .warn_stata_metadata_limits(.value_label_violations(updates))
    for (name in names(updates)) {
        column <- .metadata_copy(.get_data_column(data, name))
        attr(column, "labels") <- updates[[name]]
        column <- .apply_haven_labelled_class(
            column, !is.null(updates[[name]])
        )
        .set_data_column(data, name, column)
    }
    invisible(data)
}

#' @rdname var_label
#' @export
`var_label<-` <- function(x, value) {
    .validate_label_object(x)
    if (is.data.frame(x)) {
        if (is.null(value)) {
            for (index in seq_along(names(x))) {
                column <- .metadata_copy(.data_column_at(x, index))
                attr(column, "label") <- NULL
                .set_data_column_at(x, index, column)
            }
            return(invisible(x))
        }
        updates <- .validate_column_updates(
            x, value, .normalize_text_label, "value"
        )
        return(.apply_variable_label_updates(x, updates))
    }

    value <- .normalize_text_label(value)
    .warn_stata_metadata_limits(
        .text_label_violations(value, "variable label")
    )
    x <- .metadata_copy(x)
    attr(x, "label") <- value
    x
}

#' @rdname var_label
#' @export
`dataset_label<-` <- function(data, value) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame", call. = FALSE)
    }
    value <- .normalize_text_label(value)
    .warn_stata_metadata_limits(
        .text_label_violations(value, "dataset label")
    )
    attr(data, "label") <- value
    data
}

#' @rdname var_label
#' @export
`val_labels<-` <- function(x, value) {
    .validate_label_object(x)
    if (is.data.frame(x)) {
        if (is.null(value)) {
            for (index in seq_along(names(x))) {
                column <- .metadata_copy(.data_column_at(x, index))
                attr(column, "labels") <- NULL
                column <- .apply_haven_labelled_class(column, FALSE)
                .set_data_column_at(x, index, column)
            }
            return(invisible(x))
        }
        updates <- .validate_column_updates(
            x, value, .normalize_value_labels, "value"
        )
        return(.apply_value_label_updates(x, updates))
    }

    value <- .normalize_value_labels(value)
    .validate_value_label_target(x, value)
    .warn_stata_metadata_limits(.value_label_violations(value))
    x <- .metadata_copy(x)
    attr(x, "labels") <- value
    .apply_haven_labelled_class(x, !is.null(value))
}

#' @rdname var_label
#' @export
set_var_label <- function(data, variable, label) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame", call. = FALSE)
    }
    variable <- rlang::enquo(variable)
    target <- .mutation_name(
        variable, FALSE,
        list(state = .reference_state(data), names = names(data))
    )
    updates <- .validate_column_updates(
        data, stats::setNames(list(label), target$name),
        .normalize_text_label, "label"
    )
    .apply_variable_label_updates(data, updates)
}

#' @rdname var_label
#' @export
set_var_labels <- function(.data, ..., .labels = NULL) {
    dots <- rlang::dots_list(
        ..., .homonyms = "keep", .ignore_empty = "none"
    )
    if (!is.data.frame(.data)) {
        if (!is.null(.labels) && length(dots) > 0L) {
            stop("Supply a vector label in either `...` or `.labels`, not both",
                 call. = FALSE)
        }
        if (is.null(.labels)) {
            if (length(dots) > 1L) {
                stop("Supply at most one variable label for a vector",
                     call. = FALSE)
            }
            value <- if (length(dots) == 0L) NULL else dots[[1L]]
        } else {
            value <- .labels
        }
        return(`var_label<-`(.data, value))
    }
    if (!is.null(.labels) && !is.list(.labels)) {
        stop("`.labels` must be a named list or NULL", call. = FALSE)
    }

    updates <- c(if (is.null(.labels)) list() else .labels, dots)
    updates <- .validate_column_updates(
        .data, updates, .normalize_text_label, "labels"
    )
    .apply_variable_label_updates(.data, updates)
}

#' @rdname var_label
#' @export
set_val_labels <- function(.data, ..., .labels = NULL) {
    dots <- rlang::dots_list(
        ..., .homonyms = "keep", .ignore_empty = "none"
    )
    if (!is.data.frame(.data)) {
        if (!is.null(.labels) && length(dots) > 0L) {
            stop(
                "Supply vector value labels in either `...` or `.labels`, not both",
                call. = FALSE
            )
        }
        value <- if (is.null(.labels)) {
            if (length(dots) == 0L) NULL else unlist(
                dots, recursive = FALSE, use.names = TRUE
            )
        } else {
            .labels
        }
        return(`val_labels<-`(.data, value))
    }
    if (!is.null(.labels) && !is.list(.labels)) {
        stop("`.labels` must be a named list or NULL", call. = FALSE)
    }

    updates <- c(if (is.null(.labels)) list() else .labels, dots)
    updates <- .validate_column_updates(
        .data, updates, .normalize_value_labels, "labels"
    )
    .apply_value_label_updates(.data, updates)
}
