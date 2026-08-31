#' Read and edit Stata notes and characteristics
#'
#' These helpers expose the metadata stored in Stata characteristic records.
#' Notes retain their Stata numbers, including gaps. Numeric `note*` keys are
#' reserved for the note API and never appear in characteristic results.
#'
#' Setters return a copy of `x`. Supply `variable` as one column name or
#' one-based position to work at variable scope. A missing variable is an
#' error. Empty note text and characteristic values are retained; `NULL`
#' removes a note or characteristic. Adding a note uses one more than the
#' highest existing number, matching Stata's next-number behavior.
#'
#' `renumber_stata_notes()` preserves the current number order and assigns
#' consecutive numbers beginning at `start`. R differs from Stata's command
#' language by returning the changed object instead of modifying a dataset in
#' place.
#'
#' Arrow can retain metadata on a variable named `_dta`. DTA reserves that
#' target spelling for dataset metadata, so `save_dta()` rejects notes or
#' characteristics on such a variable rather than changing their scope.
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
#' @return `stata_notes()` and `stata_characteristics()` return named character
#'   vectors. Singular getters return one string or `NULL`. Mutation helpers
#'   return the changed object.
#' @examples
#' survey <- data.frame(age = c(20, 30))
#' survey <- set_stata_note(survey, 2, "Cleaned after interview")
#' survey <- add_stata_note(survey, "Checked by supervisor", variable = "age")
#' survey <- set_stata_characteristic(survey, "source", "baseline")
#' stata_notes(survey)
#' stata_characteristics(survey)
#' @export
stata_notes <- function(x, variable = NULL) {
    target <- .stata_metadata_target(x, variable)
    notes <- attr(target$value, "notes", exact = TRUE)
    if (is.null(notes)) return(stats::setNames(character(), character()))
    numbers <- attr(target$value, "stata.note.numbers", exact = TRUE)
    if (is.null(numbers)) numbers <- seq_along(notes)
    valid <- is.character(notes) && !anyNA(notes) &&
        is.numeric(numbers) && length(numbers) == length(notes) &&
        !anyNA(numbers) && all(numbers == floor(numbers)) &&
        all(numbers >= 1 & numbers <= 9999) && !anyDuplicated(numbers) &&
        all(vapply(notes, .valid_stata_metadata_value, logical(1)))
    if (!valid) {
        stop("The object contains malformed Stata note metadata", call. = FALSE)
    }
    order <- order(numbers)
    stats::setNames(notes[order], as.character(numbers[order]))
}

#' @rdname stata_notes
#' @export
stata_note <- function(x, number, variable = NULL) {
    number <- .stata_note_number(number)
    notes <- stata_notes(x, variable)
    match <- match(as.character(number), names(notes))
    if (is.na(match)) NULL else unname(notes[[match]])
}

#' @rdname stata_notes
#' @export
set_stata_note <- function(x, number, value, variable = NULL) {
    number <- .stata_note_number(number)
    value <- .stata_metadata_value(value)
    notes <- stata_notes(x, variable)
    key <- as.character(number)
    if (is.null(value)) {
        notes <- notes[names(notes) != key]
    } else if (key %in% names(notes)) {
        notes[[match(key, names(notes))]] <- value
    } else {
        notes <- c(notes, stats::setNames(value, key))
        notes <- notes[order(as.integer(names(notes)))]
    }
    .stata_set_notes(x, variable, notes)
}

#' @rdname stata_notes
#' @export
add_stata_note <- function(x, value, variable = NULL) {
    if (is.null(value)) {
        stop("`value` must be one non-missing string", call. = FALSE)
    }
    notes <- stata_notes(x, variable)
    number <- if (length(notes)) max(as.integer(names(notes))) + 1L else 1L
    if (number > 9999L) stop("Stata note number 9,999 is already in use", call. = FALSE)
    set_stata_note(x, number, value, variable)
}

#' @rdname stata_notes
#' @export
drop_stata_notes <- function(x, numbers = NULL, variable = NULL) {
    if (is.null(numbers)) {
        notes <- stats::setNames(character(), character())
    } else {
        numbers <- vapply(numbers, .stata_note_number, integer(1))
        notes <- stata_notes(x, variable)
        notes <- notes[!(as.integer(names(notes)) %in% numbers)]
    }
    .stata_set_notes(x, variable, notes)
}

#' @rdname stata_notes
#' @export
renumber_stata_notes <- function(x, start = 1L, variable = NULL) {
    start <- .stata_note_number(start)
    notes <- stata_notes(x, variable)
    if (length(notes) && start + length(notes) - 1L > 9999L) {
        stop("Renumbered notes would exceed Stata note number 9,999", call. = FALSE)
    }
    names(notes) <- if (length(notes)) seq.int(start, length.out = length(notes)) else character()
    .stata_set_notes(x, variable, notes)
}

#' @rdname stata_notes
#' @export
stata_characteristics <- function(x, variable = NULL) {
    target <- .stata_metadata_target(x, variable)
    characteristics <- attr(target$value, "stata.characteristics", exact = TRUE)
    if (is.null(characteristics)) return(stats::setNames(character(), character()))
    valid <- is.character(characteristics) && !anyNA(characteristics) &&
        !is.null(names(characteristics)) && !anyNA(names(characteristics)) &&
        !anyDuplicated(names(characteristics)) &&
        all(vapply(
            names(characteristics), .valid_stata_characteristic_name,
            logical(1)
        )) && all(vapply(
            characteristics, .valid_stata_metadata_value, logical(1)
        ))
    if (!valid) {
        stop("The object contains malformed Stata characteristic metadata", call. = FALSE)
    }
    characteristics
}

#' @rdname stata_notes
#' @export
stata_characteristic <- function(x, name, variable = NULL) {
    name <- .stata_characteristic_name(name)
    values <- stata_characteristics(x, variable)
    match <- match(name, names(values))
    if (is.na(match)) NULL else unname(values[[match]])
}

#' @rdname stata_notes
#' @export
set_stata_characteristic <- function(x, name, value, variable = NULL) {
    name <- .stata_characteristic_name(name)
    value <- .stata_metadata_value(value)
    characteristics <- stata_characteristics(x, variable)
    match <- match(name, names(characteristics))
    if (is.null(value)) {
        if (!is.na(match)) characteristics <- characteristics[-match]
    } else if (is.na(match)) {
        characteristics <- c(characteristics, stats::setNames(value, name))
    } else {
        characteristics[[match]] <- value
    }
    .stata_set_characteristics(x, variable, characteristics)
}

#' @rdname stata_notes
#' @export
drop_stata_characteristics <- function(x, names = NULL, variable = NULL) {
    if (is.null(names)) {
        characteristics <- stats::setNames(character(), character())
    } else {
        if (!is.character(names) || anyNA(names)) {
            stop("`names` must be a character vector or NULL", call. = FALSE)
        }
        names <- vapply(names, .stata_characteristic_name, character(1))
        characteristics <- stata_characteristics(x, variable)
        characteristics <- characteristics[!(base::names(characteristics) %in% names)]
    }
    .stata_set_characteristics(x, variable, characteristics)
}

.stata_note_number <- function(number) {
    valid <- is.numeric(number) && length(number) == 1L && !is.na(number) &&
        is.finite(number) && number == floor(number) && number >= 1 && number <= 9999
    if (!valid) stop("A note number must be one whole number from 1 through 9,999", call. = FALSE)
    as.integer(number)
}

.valid_stata_metadata_value <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) &&
        nchar(value, type = "chars") <= 67784L &&
        nchar(enc2utf8(value), type = "bytes") <= 67784L
}

.stata_metadata_value <- function(value) {
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

.stata_characteristic_name <- function(name) {
    if (!.valid_stata_characteristic_name(name)) {
        stop(paste0(
            "A characteristic name must be a valid Stata name with at most 32 Unicode ",
            "characters and cannot be a numeric `note*` key or language-control key"
        ), call. = FALSE)
    }
    enc2utf8(name)
}

.valid_stata_characteristic_name <- function(name) {
    is.character(name) && length(name) == 1L && !is.na(name) &&
        .valid_stata_name_syntax(name, 32L) &&
        nchar(name, type = "bytes") <= 128L && !grepl("^note[0-9]+$", name) &&
        !(name %in% c("_lang_list", "_lang_c")) &&
        !grepl("^_lang_[vl]_", name)
}

.stata_metadata_target <- function(x, variable) {
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

.stata_update_target <- function(x, variable, update) {
    target <- .stata_metadata_target(x, variable)
    changed <- .metadata_copy(target$value)
    changed <- update(changed)
    if (is.null(target$index)) return(changed)
    result <- .metadata_copy(x)
    result[[target$index]] <- changed
    result
}

.stata_set_notes <- function(x, variable, notes) {
    .stata_update_target(x, variable, function(target) {
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

.stata_set_characteristics <- function(x, variable, characteristics) {
    .stata_update_target(x, variable, function(target) {
        attr(target, "stata.characteristics") <- if (length(characteristics)) {
            characteristics
        } else NULL
        target
    })
}

.copy_stata_metadata_attributes <- function(from, to) {
    for (name in c("notes", "stata.note.numbers", "stata.characteristics")) {
        value <- attr(from, name, exact = TRUE)
        if (!is.null(value)) attr(to, name) <- value
    }
    to
}

.stata_metadata_payload <- function(notes, characteristics) {
    note_count <- length(notes)
    characteristic_count <- length(characteristics)
    field_count <- 3 + 2 * note_count + 2 * characteristic_count
    if (!is.finite(field_count) || field_count > .Machine$integer.max) {
        stop("Stata metadata contains too many entries", call. = FALSE)
    }
    result <- character(as.integer(field_count))
    result[[1L]] <- paste0(intToUtf8(30L), "dtatools:stata-metadata:1")
    result[[2L]] <- as.character(note_count)
    cursor <- 3L
    if (note_count) {
        note_positions <- seq.int(cursor, length.out = note_count, by = 2L)
        result[note_positions] <- enc2utf8(names(notes))
        result[note_positions + 1L] <- enc2utf8(unname(notes))
        cursor <- cursor + 2L * note_count
    }
    result[[cursor]] <- as.character(characteristic_count)
    if (characteristic_count) {
        characteristic_positions <- seq.int(
            cursor + 1L, length.out = characteristic_count, by = 2L
        )
        result[characteristic_positions] <- enc2utf8(names(characteristics))
        result[characteristic_positions + 1L] <- enc2utf8(unname(characteristics))
    }
    result
}
