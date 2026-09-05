# A metadata edit never follows the reference state's recorded object. Stage
# the supplied physical table without its state, then attach new bookkeeping
# at commit. R copies and serialized tables may still share an old state.
.metadata_table_snapshot <- function(data) {
    .reject_data_table_subclass(data)
    state <- .reference_state(data)
    if (!is.null(state) && (isTRUE(state$physical_overlay) ||
        !identical(state$generated_count, 0L))) {
        stop("Assign `data <- reserve_columns(data)` before editing metadata on a legacy table",
             call. = FALSE)
    }
    result <- .metadata_copy(data)
    attr(result, ".dtatools_ref_state") <- NULL
    class(result) <- setdiff(class(data), "dtatools_ref_data")
    result
}

.commit_metadata_table <- function(data, staged, locations = integer(),
                                   attributes = character()) {
    old_state <- .reference_state(data)
    # Construct all bookkeeping before the first write. No shared environment
    # is updated, including when the supplied table is the old state's owner.
    state <- if (!is.null(old_state)) {
        .new_reference_state(staged, dibble = is_dibble(data))
    } else NULL
    for (location in locations) {
        .Call(C_dtatools_set_data_column, data, as.integer(location),
              .subset2(staged, location))
    }
    for (name in attributes) {
        .Call(C_dtatools_set_attribute, data, name,
              attr(staged, name, exact = TRUE))
    }
    if (is.null(state)) {
        .Call(C_dtatools_set_attribute, data, "class", class(staged))
    } else {
        .mark_reference_data(data, state)
    }
    invisible(data)
}

#' Set Stata display formats by reference
#'
#' `set_var_format()` edits one column's `format.stata` metadata.
#' `set_var_formats()` edits several columns atomically, using named arguments
#' or a named list in `.formats`. On data frames, both return the table invisibly
#' and edit it by reference, including inside functions, on dibbles,
#' tibbles, base data frames, and ordinary data tables. No column values,
#' storage types, or container classes change. Use [copy_data()] for isolation.
#'
#' Target names follow [set_var_label()]: a bare name, a quoted string,
#' `!!name`, or `.(name)`. The plural form also accepts two positional arguments
#' `set_var_formats(data, variable, format)` and runtime tags `.(name) := format`.
#' For a vector, `set_var_format(x, "%9.0g")`,
#' `set_var_format(x, format = "%9.0g")`, and
#' `set_var_formats(x, .formats = format)` return a copy that must be assigned.
#' Both vector forms require exactly one format value; use an explicit `NULL`
#' to remove it. The plural form accepts that value in `...` or `.formats`,
#' never both.
#'
#' A format is a nonempty string beginning with `%`, with at most 56 UTF-8
#' bytes. The setter records display metadata; it does not interpret Stata's
#' format language, change values, or convert a vector to a date or string.
#' `NULL` removes the format.
#'
#' @param data,.data A data frame, or a vector for the assigned vector form.
#' @param variable One column name using the forms described above. On a
#'   vector, the second argument is its new format.
#' @param format One Stata display format or `NULL`.
#' @param ... Named column updates, or one format for a vector.
#' @param .formats A named list of column formats, or one format for a vector.
#' @return The updated object, invisibly for data frames.
#' @examples
#' survey <- dibble(age = 20:21, income = c(100, 200))
#' set_var_format(survey, age, "%8.0g")
#' name <- "income"
#' set_var_format(survey, .(name), "%12.2fc")
#' set_var_formats(survey, age = "%9.0g", .formats = list(income = "%10.0g"))
#' @export
set_var_format <- function(data, variable, format) {
    if (!is.data.frame(data)) {
        if (missing(variable) && missing(format)) {
            stop("Supply a vector `format`, or NULL to remove it", call. = FALSE)
        }
        if (!missing(variable) && !missing(format)) {
            stop("Supply a vector format in the second argument or `format`, not both",
                 call. = FALSE)
        }
        value <- if (missing(variable)) format else variable
        return(set_dta_metadata(data, format.stata = value))
    }
    name <- .unquoted_variable_name(rlang::enquo(variable))
    .set_format_updates(data, stats::setNames(list(format), name))
}

#' @rdname set_var_format
#' @export
set_var_formats <- function(.data, ..., .formats = NULL) {
    quoted <- substitute(...())
    dots <- if (is.data.frame(.data) && is.null(.formats) &&
        .is_positional_label_dots(quoted)) {
        pair <- rlang::enquos(...)
        stats::setNames(list(rlang::eval_tidy(pair[[2L]])),
                       .unquoted_variable_name(pair[[1L]]))
    } else {
        .dots_list_with_runtime_names(
            quoted,
            function() rlang::dots_list(..., .homonyms = "keep", .ignore_empty = "none"),
            function() rlang::enquos0(...)
        )
    }
    if (!is.data.frame(.data)) {
        supplied_formats <- !missing(.formats)
        if (length(dots) > 1L || (supplied_formats && length(dots)) ||
            (!supplied_formats && !length(dots))) {
            stop("Supply one vector format in either `...` or `.formats`", call. = FALSE)
        }
        value <- if (length(dots)) dots[[1L]] else .formats
        return(set_dta_metadata(.data, format.stata = value))
    }
    if (!is.null(.formats) && !is.list(.formats)) {
        stop("`.formats` must be a named list or NULL", call. = FALSE)
    }
    .set_format_updates(.data, c(.formats, dots))
}

.normalize_dta_format <- function(value, argument = "format") {
    if (is.null(value)) return(NULL)
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !startsWith(value, "%") || nchar(enc2utf8(value), type = "bytes") > 56L) {
        stop(sprintf("`%s` must be a Stata format beginning with %% with at most 56 UTF-8 bytes, or NULL",
                     argument), call. = FALSE)
    }
    enc2utf8(value)
}

.set_format_updates <- function(data, updates) {
    staged <- .metadata_table_snapshot(data)
    updates <- .validate_column_updates(names(staged), updates,
                                        .normalize_dta_format, "formats")
    locations <- match(names(updates), names(staged))
    for (index in seq_along(updates)) {
        column <- .metadata_copy(.subset2(staged, locations[[index]]))
        attr(column, "format.stata") <- updates[[index]]
        .Call(C_dtatools_set_data_column, staged, locations[[index]], column)
    }
    .commit_metadata_table(data, staged, locations)
}

#' Set a bundle of metadata attributes by reference
#'
#' Set named metadata attributes on a table, or on one column selected with
#' an evaluated `variable` string or position. Every data-frame form edits
#' the supplied table by reference and returns it invisibly. Vector forms
#' return a copy and must be assigned. Column payloads and capacity are
#' preserved. Unsupported data.table subclasses are rejected.
#'
#' `label`, `labels`, `value.label.name`, `format.stata`, `notes`,
#' `stata.note.numbers`, and `stata.characteristics` validate their supported
#' metadata shapes. Unlike [set_val_labels()], a `labels` bundle preserves raw
#' mappings exactly, including empty display text and named zero-length mappings.
#' It applies DTA output validation to codes, text, and size limits and rejects
#' duplicate codes. Use it to restore imported mappings without normalization.
#' The value-label name is one valid Stata name
#' of at most 32 Unicode characters and requires a `labels` mapping. An
#' explicitly named zero-length numeric mapping can declare an empty table.
#' Set both attributes in one call to restore a named mapping atomically.
#' It remains a serialization hint, not a shared value-label registry.
#'
#' Supply `notes` and `stata.note.numbers` together to preserve numbering gaps.
#' Setting `notes = NULL` also removes note numbers; new notes without explicit
#' numbers get consecutive numbers beginning at one. Notes and characteristics
#' may also be edited individually with [set_dta_note()] and
#' [set_dta_characteristic()]. A named `NULL` removes an attribute.
#'
#' Custom metadata attributes are allowed, but structural attributes such as
#' `class`, `names`, `dim`, `row.names`, `levels`, `tzone`, `units`, and `tsp`, runtime state,
#' and storage declarations are protected. Unknown `stata.*`, `dta.*`,
#' `dtatools.*`, and dot-prefixed attributes are reserved. Use the package's
#' storage and table operations to change those properties. Arbitrary custom
#' metadata is retained in R; file writers may omit unsupported attributes.
#' Validation completes before mutation, including all attributes in a bundle.
#'
#' @param x A supported data frame or vector.
#' @param ... Named metadata attributes.
#' @param .metadata A programmatic named list of metadata attributes.
#'   Duplicate or overlapping names are errors.
#' @param variable `NULL` for table or vector metadata, or one evaluated
#'   column name or one-based position. A runtime string works directly here.
#' @return The updated object, invisibly for data frames.
#' @examples
#' survey <- dibble(status = c(1, 2))
#' name <- "status"
#' set_dta_metadata(survey, variable = name,
#'                  labels = c(Complete = 1, Refused = 2),
#'                  value.label.name = "interview_status")
#' set_dta_metadata(survey, variable = name,
#'                  notes = c("First note", "Fourth note"),
#'                  stata.note.numbers = c(1L, 4L))
#' set_dta_metadata(survey, label = "Baseline", source = "interviews")
#' @export
set_dta_metadata <- function(x, ..., .metadata = NULL, variable = NULL) {
    dots <- rlang::dots_list(..., .homonyms = "keep", .ignore_empty = "none")
    if (!is.null(.metadata) && !is.list(.metadata)) {
        stop("`.metadata` must be a named list or NULL", call. = FALSE)
    }
    updates <- c(.metadata, dots)
    keys <- names(updates)
    if (length(updates) && (is.null(keys) || anyNA(keys) ||
        any(!nzchar(keys)) || anyDuplicated(keys))) {
        stop("Metadata updates must have unique, nonempty names", call. = FALSE)
    }
    known <- c("label", "labels", "value.label.name", "format.stata",
               .dta_metadata_attribute_names)
    protected <- c("class", "names", "dim", "dimnames", "row.names", "levels",
                   "tzone", "units", "tsp", "contrasts", "sorted", "index",
                   "groups", "srcref", "srcfile")
    if (any(keys %in% protected | (grepl("^(\\.|stata\\.|dta\\.|dtatools\\.)", keys) &
        !keys %in% known))) {
        stop("Structural, runtime, and storage attributes cannot be set as metadata",
             call. = FALSE)
    }
    table <- is.data.frame(x)
    staged <- if (table) .metadata_table_snapshot(x) else x
    target <- .dta_metadata_target(staged, variable)
    changed <- .metadata_copy(target$value)
    if (is.data.frame(changed) && any(keys %in% c("labels", "value.label.name", "format.stata"))) {
        stop("Value labels and formats require a vector or `variable`", call. = FALSE)
    }
    for (key in keys) attr(changed, key) <- updates[[key]]
    if ("label" %in% keys) {
        attr(changed, "label") <- .normalize_text_label(updates$label)
        .warn_dta_metadata_limits(.text_label_violations(attr(changed, "label"), "label"))
    }
    if ("format.stata" %in% keys) {
        attr(changed, "format.stata") <- .normalize_dta_format(updates$format.stata)
    }
    if ("labels" %in% keys) {
        .validate_value_label_target(changed, updates$labels)
        .prepare_write_value_labels(changed, "metadata target")
        if (!is.null(updates$labels)) {
            # Use nonempty temporary text only for the existing uniqueness
            # check. The original mapping, including blank text, stays intact.
            .normalize_value_labels(stats::setNames(
                updates$labels, rep("label", length(updates$labels))
            ))
        } else {
            attr(changed, "value.label.name") <- NULL
        }
        changed <- .apply_haven_labelled_class(changed, !is.null(updates$labels))
    }
    if ("value.label.name" %in% keys) {
        attr(changed, "value.label.name") <- updates$value.label.name
    }
    if (any(c("labels", "value.label.name") %in% keys)) {
        hint <- attr(changed, "value.label.name", exact = TRUE)
        if (!is.null(hint) && (!is.character(hint) || length(hint) != 1L ||
            is.na(hint) || !.valid_dta_name_syntax(hint, 32L) ||
            nchar(enc2utf8(hint), type = "bytes") > 128L ||
            is.null(attr(changed, "labels", exact = TRUE)))) {
            stop("`value.label.name` requires a labels mapping and one valid Stata name",
                 call. = FALSE)
        }
    }
    if ("notes" %in% keys && !"stata.note.numbers" %in% keys) {
        attr(changed, "stata.note.numbers") <- NULL
    }
    if (any(.dta_metadata_attribute_names %in% keys)) {
        if (is.null(attr(changed, "notes", exact = TRUE)) &&
            !is.null(attr(changed, "stata.note.numbers", exact = TRUE))) {
            stop("Note numbers require notes", call. = FALSE)
        }
        notes <- dta_notes(changed)
        for (value in notes) .dta_metadata_value(value)
        for (value in dta_characteristics(changed)) .dta_metadata_value(value)
        changed <- if (is.data.frame(changed)) .metadata_frame_class(changed) else
            .as_dta_metadata_vector(changed)
    }
    if (!table) return(changed)
    if (is.null(target$index)) {
        # Labels alone need no restoration marker. Recompute it nonetheless:
        # a base attribute copy may have removed the last note or
        # characteristic while retaining its old restoration class.
        staged <- .metadata_frame_class(changed)
    } else {
        .Call(C_dtatools_set_data_column, staged, target$index, changed)
        staged <- .metadata_frame_class(staged)
    }
    # Normalization may clear paired note or label-name attributes.
    committed <- unique(c(keys, if ("notes" %in% keys) "stata.note.numbers",
                          if ("labels" %in% keys) "value.label.name"))
    .commit_metadata_table(x, staged, target$index, if (is.null(target$index)) committed)
}

.metadata_frame_class <- function(data) {
    .set_dta_metadata_class(data, .has_dta_metadata(data) ||
        any(vapply(data, .has_dta_metadata, logical(1))))
}
