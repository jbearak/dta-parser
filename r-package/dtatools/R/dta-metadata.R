#' Read and edit Stata notes and characteristics
#'
#' These helpers expose the metadata stored in Stata characteristic records.
#' Notes retain their Stata numbers, including gaps. Numeric `note*` keys are
#' reserved for the note API and never appear in characteristic results.
#'
#' On every supported data frame, setters modify `x` by reference and return
#' it invisibly, including calls inside functions. Vectors return an assigned
#' copy. Use [copy_data()] first when table metadata should be independent.
#' Supply `variable` as one column name or
#' one-based position to work at variable scope. A missing variable is an
#' error. Empty note text and characteristic values are retained; `NULL`
#' removes a note or characteristic. Adding a note uses one more than the
#' highest existing number, matching Stata's next-number behavior.
#'
#' `renumber_dta_notes()` preserves the current number order and assigns
#' consecutive numbers beginning at `start`.
#'
#' Arrow can retain metadata on a variable named `_dta`. DTA reserves that
#' target spelling for dataset metadata, so `save_dta()` rejects notes or
#' characteristics on such a variable rather than changing their scope.
#'
#' Legacy single-byte DTA metadata may expand from at most 67,784 source bytes
#' to at most 203,352 UTF-8 bytes when read. Getters and Arrow round trips retain
#' that decoded form. Setters and DTA output keep Stata's 67,784-byte target
#' limit.
#'
#' Data frames carrying notes or characteristics use an internal restoration
#' class. Data-frame-preserving `[` subsets retain dataset metadata and the
#' metadata of every retained variable for both base data frames and tibbles.
#' A base subset that drops one column to a vector retains that variable's
#' metadata; tibbles retain their usual non-dropping behavior. Metadata-bearing
#' plain character, logical, factor, raw, integer, and double vectors also use
#' an internal class so [vctrs::vec_c()] and [vctrs::vec_ptype2()] retain the
#' first input's metadata, falling back to the next input that has metadata.
#'
#' @param x A data frame or vector carrying Stata metadata.
#' @param variable `NULL` for dataset or vector metadata, or one column name or
#'   one-based position in a data frame.
#' @param number One note number from 1 through 9,999.
#' @param numbers Note numbers to drop. `NULL` drops all notes.
#' @param value One non-missing string. For setters, `NULL` removes the key.
#' @param start First number assigned while renumbering.
#' @param name One characteristic name.
#' @param names Characteristic names to drop. `NULL` drops all characteristics.
#' @return `dta_notes()` and `dta_characteristics()` return named character
#'   vectors. Singular getters return one string or `NULL`. Mutation helpers
#'   return the changed object, invisibly for data frames.
#' @examples
#' survey <- data.frame(age = c(20, 30))
#' survey <- set_dta_note(survey, 2, "Cleaned after interview")
#' survey <- add_dta_note(survey, "Checked by supervisor", variable = "age")
#' survey <- set_dta_characteristic(survey, "source", "baseline")
#' dta_notes(survey)
#' dta_characteristics(survey)
#' @export
dta_notes <- function(x, variable = NULL) {
    target <- .dta_metadata_target(x, variable)
    notes <- attr(target$value, "notes", exact = TRUE)
    if (is.null(notes)) return(stats::setNames(character(), character()))
    numbers <- attr(target$value, "stata.note.numbers", exact = TRUE)
    if (is.null(numbers)) numbers <- seq_along(notes)
    valid <- is.character(notes) && !anyNA(notes) &&
        is.numeric(numbers) && length(numbers) == length(notes) &&
        !anyNA(numbers) && all(numbers == floor(numbers)) &&
        all(numbers >= 1 & numbers <= 9999) && !anyDuplicated(numbers) &&
        all(vapply(notes, .valid_dta_metadata_value, logical(1)))
    if (!valid) {
        stop("The object contains malformed Stata note metadata", call. = FALSE)
    }
    order <- order(numbers)
    stats::setNames(notes[order], as.character(numbers[order]))
}

#' @rdname dta_notes
#' @export
dta_note <- function(x, number, variable = NULL) {
    number <- .dta_note_number(number)
    notes <- dta_notes(x, variable)
    match <- match(as.character(number), names(notes))
    if (is.na(match)) NULL else unname(notes[[match]])
}

#' @rdname dta_notes
#' @export
set_dta_note <- function(x, number, value, variable = NULL) {
    number <- .dta_note_number(number)
    value <- .dta_metadata_value(value)
    notes <- dta_notes(x, variable)
    key <- as.character(number)
    if (is.null(value)) {
        notes <- notes[names(notes) != key]
    } else if (key %in% names(notes)) {
        notes[[match(key, names(notes))]] <- value
    } else {
        notes <- c(notes, stats::setNames(value, key))
        notes <- notes[order(as.integer(names(notes)))]
    }
    .dta_set_notes(x, variable, notes)
}

#' @rdname dta_notes
#' @export
add_dta_note <- function(x, value, variable = NULL) {
    if (is.null(value)) {
        stop("`value` must be one non-missing string", call. = FALSE)
    }
    notes <- dta_notes(x, variable)
    number <- if (length(notes)) max(as.integer(names(notes))) + 1L else 1L
    if (number > 9999L) stop("Stata note number 9,999 is already in use", call. = FALSE)
    set_dta_note(x, number, value, variable)
}

#' @rdname dta_notes
#' @export
drop_dta_notes <- function(x, numbers = NULL, variable = NULL) {
    if (is.null(numbers)) {
        notes <- stats::setNames(character(), character())
    } else {
        numbers <- vapply(numbers, .dta_note_number, integer(1))
        notes <- dta_notes(x, variable)
        notes <- notes[!(as.integer(names(notes)) %in% numbers)]
    }
    .dta_set_notes(x, variable, notes)
}

#' @rdname dta_notes
#' @export
renumber_dta_notes <- function(x, start = 1L, variable = NULL) {
    start <- .dta_note_number(start)
    notes <- dta_notes(x, variable)
    if (length(notes) && start + length(notes) - 1L > 9999L) {
        stop("Renumbered notes would exceed Stata note number 9,999", call. = FALSE)
    }
    names(notes) <- if (length(notes)) seq.int(start, length.out = length(notes)) else character()
    .dta_set_notes(x, variable, notes)
}

#' @rdname dta_notes
#' @export
dta_characteristics <- function(x, variable = NULL) {
    target <- .dta_metadata_target(x, variable)
    characteristics <- attr(target$value, "stata.characteristics", exact = TRUE)
    if (is.null(characteristics)) return(stats::setNames(character(), character()))
    valid <- is.character(characteristics) && !anyNA(characteristics) &&
        !is.null(names(characteristics)) && !anyNA(names(characteristics)) &&
        !anyDuplicated(names(characteristics)) &&
        all(vapply(
            names(characteristics), .valid_dta_characteristic_name,
            logical(1)
        )) && all(vapply(
            characteristics, .valid_dta_metadata_value, logical(1)
        ))
    if (!valid) {
        stop("The object contains malformed Stata characteristic metadata", call. = FALSE)
    }
    characteristics
}

#' @rdname dta_notes
#' @export
dta_characteristic <- function(x, name, variable = NULL) {
    name <- .dta_characteristic_name(name)
    values <- dta_characteristics(x, variable)
    match <- match(name, names(values))
    if (is.na(match)) NULL else unname(values[[match]])
}

#' @rdname dta_notes
#' @export
set_dta_characteristic <- function(x, name, value, variable = NULL) {
    name <- .dta_characteristic_name(name)
    value <- .dta_metadata_value(value)
    characteristics <- dta_characteristics(x, variable)
    match <- match(name, names(characteristics))
    if (is.null(value)) {
        if (!is.na(match)) characteristics <- characteristics[-match]
    } else if (is.na(match)) {
        characteristics <- c(characteristics, stats::setNames(value, name))
    } else {
        characteristics[[match]] <- value
    }
    .dta_set_characteristics(x, variable, characteristics)
}

#' @rdname dta_notes
#' @export
drop_dta_characteristics <- function(x, names = NULL, variable = NULL) {
    if (is.null(names)) {
        characteristics <- stats::setNames(character(), character())
    } else {
        if (!is.character(names) || anyNA(names)) {
            stop("`names` must be a character vector or NULL", call. = FALSE)
        }
        names <- vapply(names, .dta_characteristic_name, character(1))
        characteristics <- dta_characteristics(x, variable)
        characteristics <- characteristics[!(base::names(characteristics) %in% names)]
    }
    .dta_set_characteristics(x, variable, characteristics)
}

.dta_note_number <- function(number) {
    valid <- is.numeric(number) && length(number) == 1L && !is.na(number) &&
        is.finite(number) && number == floor(number) && number >= 1 && number <= 9999
    if (!valid) stop("A note number must be one whole number from 1 through 9,999", call. = FALSE)
    as.integer(number)
}

.valid_dta_metadata_value <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) &&
        nchar(value, type = "chars") <= 67784L &&
        nchar(enc2utf8(value), type = "bytes") <= 203352L
}

.dta_metadata_value <- function(value) {
    if (is.null(value)) return(NULL)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
        stop("`value` must be one non-missing string or NULL", call. = FALSE)
    }
    if (nchar(value, type = "chars") > 67784L) {
        stop("`value` exceeds Stata's 67,784-byte metadata limit", call. = FALSE)
    }
    value <- enc2utf8(value)
    if (nchar(value, type = "bytes") > 67784L) {
        stop("`value` exceeds Stata's 67,784-byte metadata limit", call. = FALSE)
    }
    value
}

.dta_characteristic_name <- function(name) {
    if (!.valid_dta_characteristic_name(name)) {
        stop(paste0(
            "A characteristic name must be a valid Stata name with at most 32 Unicode ",
            "characters and cannot be a numeric `note*` key, language-control key, ",
            "or alias structural key"
        ), call. = FALSE)
    }
    enc2utf8(name)
}

.valid_dta_characteristic_name <- function(name) {
    is.character(name) && length(name) == 1L && !is.na(name) &&
        .valid_dta_name_syntax(name, 32L) &&
        nchar(name, type = "bytes") <= 128L && !grepl("^note[0-9]+$", name) &&
        !(name %in% c(
            "_lang_list", "_lang_c", "fralias_from", "fralias_varname"
        )) &&
        !grepl("^_lang_[vl]_", name)
}

.dta_metadata_target <- function(x, variable) {
    .validate_label_object(x)
    if (is.null(variable)) return(list(value = x, index = NULL))
    if (!is.data.frame(x)) stop("`variable` requires a data frame", call. = FALSE)
    valid <- (is.character(variable) || is.numeric(variable)) && length(variable) == 1L &&
        !is.na(variable)
    if (!valid) stop("`variable` must be one column name or position", call. = FALSE)
    index <- if (is.character(variable)) match(variable, names(x)) else {
        if (!is.finite(variable) || variable != floor(variable)) NA_integer_ else as.integer(variable)
    }
    if (is.na(index) || index < 1L || index > ncol(x)) {
        stop("The requested variable does not exist", call. = FALSE)
    }
    list(value = x[[index]], index = index)
}

.dta_update_target <- function(x, variable, update) {
    if (!is.data.frame(x)) {
        target <- .dta_metadata_target(x, variable)
        return(.as_dta_metadata_vector(update(target$value)))
    }
    staged <- .metadata_table_snapshot(x)
    target <- .dta_metadata_target(staged, variable)
    changed <- update(target$value)
    if (is.null(target$index)) {
        staged <- changed
    } else {
        .Call(C_dtatools_set_data_column, staged, target$index,
              .as_dta_metadata_vector(changed))
    }
    staged <- .metadata_frame_class(staged)
    .commit_metadata_table(x, staged, target$index,
                           .dta_metadata_attribute_names)
}

.dta_set_notes <- function(x, variable, notes) {
    .dta_update_target(x, variable, function(target) {
        target <- .metadata_copy(target)
        if (!length(notes)) {
            attr(target, "notes") <- NULL
            attr(target, "stata.note.numbers") <- NULL
        } else {
            attr(target, "notes") <- unname(notes)
            attr(target, "stata.note.numbers") <- as.integer(names(notes))
        }
        target
    })
}

.dta_set_characteristics <- function(x, variable, characteristics) {
    .dta_update_target(x, variable, function(target) {
        target <- .metadata_copy(target)
        attr(target, "stata.characteristics") <- if (length(characteristics)) {
            characteristics
        } else NULL
        target
    })
}

.copy_dta_metadata_attributes <- function(from, to, mark = TRUE) {
    for (name in .dta_metadata_attribute_names) {
        value <- attr(from, name, exact = TRUE)
        if (!is.null(value)) attr(to, name) <- value
    }
    if (mark) .as_dta_metadata_frame(to) else to
}

.dta_metadata_attribute_names <- c(
    "notes", "stata.note.numbers", "stata.characteristics"
)

.reconcile_dta_metadata_attributes <- function(result, x, y) {
    x_has_notes <- !is.null(attr(x, "notes", exact = TRUE)) ||
        !is.null(attr(x, "stata.note.numbers", exact = TRUE))
    note_source <- if (x_has_notes) x else y
    characteristics <- attr(x, "stata.characteristics", exact = TRUE)
    if (is.null(characteristics)) {
        characteristics <- attr(y, "stata.characteristics", exact = TRUE)
    }
    desired <- list(
        notes = attr(note_source, "notes", exact = TRUE),
        note_numbers = attr(note_source, "stata.note.numbers", exact = TRUE),
        characteristics = characteristics
    )
    current <- list(
        notes = attr(result, "notes", exact = TRUE),
        note_numbers = attr(result, "stata.note.numbers", exact = TRUE),
        characteristics = attr(result, "stata.characteristics", exact = TRUE)
    )
    if (identical(current, desired)) return(result)
    attr(result, "notes") <- desired$notes
    attr(result, "stata.note.numbers") <- desired$note_numbers
    attr(result, "stata.characteristics") <- desired$characteristics
    result
}

.has_dta_metadata <- function(value) {
    any(vapply(.dta_metadata_attribute_names, function(name) {
        !is.null(attr(value, name, exact = TRUE))
    }, logical(1)))
}

.dta_metadata_vector_class <- "dtatools_dta_metadata_vector"

.set_dta_metadata_class <- function(value, present) {
    marker <- if (is.data.frame(value)) {
        "dtatools_dta_metadata"
    } else {
        .dta_metadata_vector_class
    }
    classes <- setdiff(attr(value, "class", exact = TRUE), marker)
    if (is.data.frame(value) && "data.table" %in% classes) {
        # data.table's `[` evaluates `i` and `j` with its own non-standard
        # evaluation, so the frame marker's `[` method must never intercept
        # it, and the mutation functions require ordinary data.tables.
        # Dataset metadata stays in plain attributes on the container.
        present <- FALSE
    }
    if (!is.data.frame(value) && any(classes %in% c(
        "dta_numeric", "dta_temporal"
    ))) {
        present <- FALSE
    }
    classes <- if (present) c(marker, classes) else classes
    if (is.data.frame(value) && "dtatools_ref_data" %in% classes) {
        # A reference dataset dispatches `[` for bracket mutation, so its
        # class must stay first; the marker's `[` runs from the snapshot.
        # The state's own class vector carries the marker so a snapshot
        # keeps dataset metadata behavior.
        classes <- c("dtatools_ref_data", setdiff(classes, "dtatools_ref_data"))
        state <- .reference_state(value)
        if (!is.null(state)) {
            state$classes <- setdiff(classes, "dtatools_ref_data")
        }
    }
    if (!is.data.frame(value)) {
        # A shared metadata proxy needs another compact wrapper before class
        # replacement; R's default duplicate would decode its string backing.
        value <- .metadata_copy(value)
    }
    if (length(classes)) {
        class(value) <- classes
    } else {
        attr(value, "class") <- NULL
    }
    value
}

.as_dta_metadata_vector <- function(value) {
    .set_dta_metadata_class(value, .has_dta_metadata(value))
}

.as_dta_metadata_frame <- function(value) {
    if (!is.data.frame(value)) return(.as_dta_metadata_vector(value))
    variable_metadata <- vapply(value, .has_dta_metadata, logical(1))
    if (any(variable_metadata)) {
        locations <- which(variable_metadata)
        marked <- lapply(
            locations, function(k) .as_dta_metadata_vector(value[[k]])
        )
        if (inherits(value, "data.table")) {
            # `[<-` on a data.table with a logical index selects rows, and
            # list-style column replacement invalidates its self-reference,
            # so install marked columns through data.table's own setter.
            for (k in seq_along(locations)) {
                data.table::set(value, j = locations[[k]], value = marked[[k]])
            }
        } else {
            value[locations] <- marked
        }
    }
    .repair_data_table_container(.set_dta_metadata_class(
        value, .has_dta_metadata(value) || any(variable_metadata)
    ))
}

.dta_metadata_vector_base <- function(value) {
    for (name in .dta_metadata_attribute_names) attr(value, name) <- NULL
    .set_dta_metadata_class(value, FALSE)
}

#' @export
vec_proxy.dtatools_dta_metadata_vector <- function(x, ...) {
    vctrs::vec_proxy(.dta_metadata_vector_base(x), ...)
}

#' @export
vec_restore.dtatools_dta_metadata_vector <- function(x, to, ...) {
    restored <- vctrs::vec_restore(
        x, .dta_metadata_vector_base(to), ...
    )
    .copy_dta_metadata_attributes(to, restored)
}

.dta_metadata_vector_ptype2 <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    result <- vctrs::vec_ptype2(
        .dta_metadata_vector_base(x),
        .dta_metadata_vector_base(y),
        ...,
        x_arg = x_arg,
        y_arg = y_arg
    )
    .as_dta_metadata_vector(
        .reconcile_dta_metadata_attributes(result, x, y)
    )
}

#' @export
vec_ptype2.dtatools_dta_metadata_vector.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2

#' @export
vec_ptype2.dtatools_dta_metadata_vector.character <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.character.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dtatools_dta_metadata_vector.logical <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.logical.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dtatools_dta_metadata_vector.integer <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.integer.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dtatools_dta_metadata_vector.double <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.double.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dtatools_dta_metadata_vector.raw <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.raw.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dtatools_dta_metadata_vector.factor <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.factor.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dtatools_dta_metadata_vector.ordered <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.ordered.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2

.dta_metadata_vector_cast <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    result <- vctrs::vec_cast(
        .dta_metadata_vector_base(x),
        .dta_metadata_vector_base(to),
        ...,
        x_arg = x_arg,
        to_arg = to_arg,
        call = call
    )
    .copy_dta_metadata_attributes(to, result)
}

#' @export
vec_cast.dtatools_dta_metadata_vector.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.character <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.logical <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.integer <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.double <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.raw <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.factor <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dtatools_dta_metadata_vector.ordered <-
    .dta_metadata_vector_cast

.dta_metadata_vector_cast_base <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    vctrs::vec_cast(
        .dta_metadata_vector_base(x),
        .dta_metadata_vector_base(to),
        ...,
        x_arg = x_arg,
        to_arg = to_arg,
        call = call
    )
}

#' @export
vec_cast.character.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
#' @export
vec_cast.logical.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
#' @export
vec_cast.integer.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
#' @export
vec_cast.double.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
#' @export
vec_cast.raw.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
#' @export
vec_cast.factor.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
#' @export
vec_cast.ordered.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base

#' @export
`[.dtatools_dta_metadata` <- function(x, i, j, ..., drop) {
    argument_count <- nargs() - !missing(drop)
    one_dimensional <- argument_count < 3L
    indices <- stats::setNames(seq_along(x), names(x))
    selected <- if (one_dimensional) {
        if (missing(i)) indices else indices[i]
    } else if (missing(j)) {
        indices
    } else {
        indices[j]
    }

    result <- NextMethod("[")
    if (!is.data.frame(result)) {
        if (length(selected) == 1L) {
            result <- .copy_dta_metadata_attributes(
                x[[unname(selected[[1L]])]], result
            )
        }
        return(result)
    }

    result <- .copy_dta_metadata_attributes(x, result, mark = FALSE)
    if (length(selected) != ncol(result)) {
        stop("Could not restore Stata metadata after subsetting", call. = FALSE)
    }
    source_columns <- unclass(x)[unname(selected)]
    variable_metadata <- vapply(
        source_columns, .has_dta_metadata, logical(1)
    )
    if (any(variable_metadata)) {
        locations <- which(variable_metadata)
        replacements <- Map(
            .copy_dta_metadata_attributes,
            source_columns[locations],
            unclass(result)[locations]
        )
        result[locations] <- replacements
    }
    .set_dta_metadata_class(
        result, .has_dta_metadata(x) || any(variable_metadata)
    )
}

.dta_metadata_payload <- function(
    notes, characteristics, inputs_are_utf8 = FALSE
) {
    note_count <- length(notes)
    characteristic_count <- length(characteristics)
    if (!note_count && !characteristic_count) return(NULL)
    field_count <- 3 + 2 * note_count + 2 * characteristic_count
    if (!is.finite(field_count) || field_count > .Machine$integer.max) {
        stop("Stata metadata contains too many entries", call. = FALSE)
    }
    result <- character(as.integer(field_count))
    result[[1L]] <- paste0(intToUtf8(30L), "dtatools:dta-metadata:1")
    result[[2L]] <- as.character(note_count)
    cursor <- 3L
    if (note_count) {
        note_positions <- seq.int(cursor, length.out = note_count, by = 2L)
        note_numbers <- names(notes)
        note_texts <- notes
        if (!inputs_are_utf8) {
            note_numbers <- enc2utf8(note_numbers)
            note_texts <- enc2utf8(note_texts)
        }
        result[note_positions] <- note_numbers
        result[note_positions + 1L] <- note_texts
        cursor <- cursor + 2L * note_count
    }
    result[[cursor]] <- as.character(characteristic_count)
    if (characteristic_count) {
        characteristic_positions <- seq.int(
            cursor + 1L, length.out = characteristic_count, by = 2L
        )
        characteristic_names <- names(characteristics)
        characteristic_values <- characteristics
        if (!inputs_are_utf8) {
            characteristic_names <- enc2utf8(characteristic_names)
            characteristic_values <- enc2utf8(characteristic_values)
        }
        result[characteristic_positions] <- characteristic_names
        result[characteristic_positions + 1L] <- characteristic_values
    }
    result
}

# `dta_string` declares coercion pairs only with itself and `character`,
# but read_dta() wraps a labelled or noted string column in the metadata
# vector class. Combining a bare owned string with a wrapped one - which
# happens whenever ragged sources are appended - therefore had no common
# type. Delegating to the shared metadata helpers strips the marker and
# lets the `dta_string` pair resolve the storage width, then restores
# the notes and characteristics.

#' @export
vec_ptype2.dtatools_dta_metadata_vector.dta_string <-
    .dta_metadata_vector_ptype2
#' @export
vec_ptype2.dta_string.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_ptype2

#' @export
vec_cast.dtatools_dta_metadata_vector.dta_string <-
    .dta_metadata_vector_cast
#' @export
vec_cast.dta_string.dtatools_dta_metadata_vector <-
    .dta_metadata_vector_cast_base
