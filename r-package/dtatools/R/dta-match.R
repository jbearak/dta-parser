#' Compare, match, and combine values using Stata identity
#'
#' These functions compare finite values and Stata missing codes using Stata's
#' identity rules. `dta_identical()` compares corresponding elements without
#' recycling and ignores storage, class, names, and metadata. Unlike
#' [base::match()] and `%in%`, `dta_match()` and `dta_in()` recognize bare values
#' returned by [tagged_missing()] on either side. System missing `.` and
#' extended missings `.a` through `.z` are distinct values.
#'
#' `dta_identical()` requires equal lengths and preserves element order. It
#' accepts compatible bare and Stata-backed vectors, ignores storage width,
#' compact representation, class, names, labels, formats, and other metadata,
#' and returns `FALSE` for incompatible kinds. Strings use exact character
#' identity, including `""` as Stata string missing. Dates compare only with
#' dates and datetimes only with datetimes. Two `NULL` inputs are identical;
#' `NULL` and any vector are not. Noncanonical NaN payloads are errors. This
#' function does not change [base::identical()] or its structural R semantics.
#'
#' The set functions keep first-occurrence order and remove names.
#' `dta_union()` returns unique values from `x`, followed by values found only
#' in `y`, using a lossless common Stata storage type. `dta_intersect()` and
#' `dta_setdiff()` retain `x`'s type and metadata. Incompatible kinds, such as
#' strings and numerics or dates and datetimes, are errors.
#'
#' @param x Values to compare, match, or use as the left input to a set
#'   operation.
#' @param table Values against which to match.
#' @param nomatch Integer value returned for unmatched elements.
#' @param incomparables Values that must not match. Stata missing codes may be
#'   excluded separately. `NULL` means that every value is comparable.
#' @param y Values to compare or use as the right input to a set operation.
#' @return `dta_identical()` returns one nonmissing logical value.
#'   `dta_match()` returns integer locations and `dta_in()` returns a logical
#'   vector without missing values. `dta_union()`, `dta_intersect()`, and
#'   `dta_setdiff()` return vectors without names. `dta_setequal()` returns one
#'   logical value.
#' @examples
#' x <- c(1, tagged_missing("a"), NA_real_)
#' column <- dta_byte(c(1, NA_real_, tagged_missing("a")))
#' dta_in(x, column)
#' dta_match(x, column)
#' dta_identical(column, x)
#' dta_union(column, dta_int(c(2, tagged_missing("b"))))
#' @name dta_match
#' @export
dta_identical <- function(x, y) {
    if (is.null(x) || is.null(y)) return(is.null(x) && is.null(y))
    if (length(x) != length(y)) return(FALSE)

    x_kind <- .dta_identity_kind(x, "x")
    y_kind <- .dta_identity_kind(y, "y")
    if (!identical(x_kind, y_kind)) {
        .dta_identity_key(x, x_kind, "x")
        .dta_identity_key(y, y_kind, "y")
        return(FALSE)
    }

    x_key <- unname(.dta_identity_key(x, x_kind, "x"))
    y_key <- unname(.dta_identity_key(y, y_kind, "y"))
    identical(x_key, y_key)
}

#' @rdname dta_match
#' @export
dta_match <- function(x, table, nomatch = NA_integer_, incomparables = NULL) {
    kind <- .dta_common_identity_kind(x, table, "x", "table")
    x_key <- .dta_identity_key(x, kind, "x")
    table_key <- .dta_identity_key(table, kind, "table")
    incomparable_key <- if (is.null(incomparables)) {
        NULL
    } else {
        incomparable_kind <- .dta_common_identity_kind(
            x, incomparables, "x", "incomparables"
        )
        if (!identical(kind, incomparable_kind)) {
            stop("`incomparables` must have the same kind as `x` and `table`",
                 call. = FALSE)
        }
        .dta_identity_key(incomparables, kind, "incomparables")
    }
    result <- base::match(
        x_key, table_key, nomatch = nomatch, incomparables = incomparable_key
    )
    names(result) <- names(x)
    result
}

#' @rdname dta_match
#' @export
dta_in <- function(x, table) {
    result <- dta_match(x, table, nomatch = 0L) > 0L
    names(result) <- names(x)
    result
}

#' @rdname dta_match
#' @export
dta_union <- function(x, y) {
    if (is.null(x)) return(.dta_unique_result(y))
    if (is.null(y)) return(.dta_unique_result(x))
    kind <- .dta_common_identity_kind(x, y, "x", "y")
    x_key <- .dta_identity_key(x, kind, "x")
    y_key <- .dta_identity_key(y, kind, "y")
    x_keep <- !duplicated(x_key)
    y_keep <- !duplicated(y_key) & !(y_key %in% x_key)
    result <- .dta_union_values(
        x, y, which(x_keep), which(y_keep), kind
    )
    names(result) <- NULL
    result
}

.dta_union_values <- function(x, y, x_locations, y_locations, kind) {
    unknown <- unique(c(.dta_unknown_attributes(x), .dta_unknown_attributes(y)))
    conflicts <- character()

    sliced <- suppressWarnings(list(
        vctrs::vec_slice(x, x_locations),
        vctrs::vec_slice(y, y_locations)
    ))
    if (identical(kind, "numeric") &&
        (inherits(x, "stata_numeric") || inherits(y, "stata_numeric"))) {
        storage <- .dta_union_numeric_storage(x, y)
        values <- c(as.double(sliced[[1L]]), as.double(sliced[[2L]]))
        prototype <- if (inherits(x, "stata_numeric")) x else y
        result <- .construct_stata_numeric(values, NULL, storage)
        result <- suppressWarnings(.restore_stata_metadata(
            result, prototype, storage
        ))
    } else if (kind %in% c("date", "datetime") &&
               (inherits(x, "stata_temporal") ||
                inherits(y, "stata_temporal"))) {
        storage <- .dta_union_numeric_storage(x, y)
        values <- c(as.double(sliced[[1L]]), as.double(sliced[[2L]]))
        prototype <- if (inherits(x, "stata_temporal")) x else y
        result <- suppressWarnings(.restore_stata_temporal(
            values, prototype, storage
        ))
    } else if (identical(kind, "string") &&
               (inherits(x, "stata_string") || inherits(y, "stata_string"))) {
        storage <- .stata_string_common_storage(x, y)
        prototype <- if (inherits(x, "stata_string")) x else y
        result <- suppressWarnings(.new_stata_string(
            c(as.character(sliced[[1L]]), as.character(sliced[[2L]])),
            storage,
            prototype
        ))
    } else {
        result <- suppressWarnings(vctrs::vec_c(sliced[[1L]], sliced[[2L]]))
    }

    if (inherits(result, "stata_numeric") ||
        inherits(result, "stata_temporal") ||
        inherits(result, "stata_string")) {
        reconciled <- .dta_union_metadata(result, x, y, kind)
        result <- reconciled$result
        conflicts <- reconciled$conflicts
    }
    if (length(unknown)) {
        conflicts <- c(conflicts, sprintf(
            "unknown attributes dropped (%s)", paste(unknown, collapse = ", ")
        ))
    }
    conflicts <- unique(conflicts)
    if (length(conflicts)) {
        warning(sprintf(
            "`dta_union()` reconciled conflicting metadata: %s",
            paste(conflicts, collapse = "; ")
        ), call. = FALSE)
    }
    result
}

.dta_union_numeric_storage <- function(x, y) {
    storages <- vapply(list(x, y), function(value) {
        storage <- .declared_stata_storage(value)
        if (!is.null(storage)) return(storage)
        if (is.double(value)) return("double")
        observed <- value[!is.na(value)]
        if (!length(observed) || all(observed >= -127 & observed <= 100)) {
            return("byte")
        }
        if (all(observed >= -32767 & observed <= 32740)) return("int")
        "long"
    }, character(1))
    .stata_promote(storages[[1L]], storages[[2L]])
}

.dta_unknown_attributes <- function(x) {
    setdiff(
        names(attributes(x)),
        c("names", "class", .stata_variable_attribute_names)
    )
}

.dta_union_metadata <- function(result, x, y, kind) {
    conflicts <- character()
    left_first <- function(name, category = name) {
        left <- attr(x, name, exact = TRUE)
        right <- attr(y, name, exact = TRUE)
        if (!is.null(left) && !is.null(right) && !identical(left, right)) {
            conflicts <<- c(conflicts, category)
        }
        if (!is.null(left)) left else right
    }

    x_labels <- attr(x, "labels", exact = TRUE)
    y_labels <- attr(y, "labels", exact = TRUE)
    labels <- x_labels
    if (is.null(labels)) {
        labels <- y_labels
    } else if (!is.null(y_labels)) {
        x_keys <- .stata_value_label_keys(x_labels)
        y_keys <- .stata_value_label_keys(y_labels)
        shared <- match(y_keys, x_keys, nomatch = 0L)
        differing <- shared > 0L &
            names(y_labels) != names(x_labels)[pmax(shared, 1L)]
        if (any(differing)) conflicts <- c(conflicts, "value labels")
        labels <- c(x_labels, y_labels[shared == 0L])
    }

    format <- .dta_union_format(x, y, result, kind)
    x_format <- attr(x, "format.stata", exact = TRUE)
    y_format <- attr(y, "format.stata", exact = TRUE)
    if (!is.null(x_format) && !is.null(y_format) &&
        !identical(x_format, y_format)) {
        conflicts <- c(conflicts, "display format")
    }

    attr(result, "format.stata") <- format
    attr(result, "label") <- left_first("label", "variable label")
    attr(result, "labels") <- labels
    attr(result, "value.label.name") <- if (is.null(labels)) NULL else {
        left_first("value.label.name", "value-label name")
    }
    x_has_notes <- !is.null(attr(x, "notes", exact = TRUE)) ||
        !is.null(attr(x, "stata.note.numbers", exact = TRUE))
    y_has_notes <- !is.null(attr(y, "notes", exact = TRUE)) ||
        !is.null(attr(y, "stata.note.numbers", exact = TRUE))
    if (x_has_notes && y_has_notes && (!identical(
        attr(x, "notes", exact = TRUE), attr(y, "notes", exact = TRUE)
    ) || !identical(
        attr(x, "stata.note.numbers", exact = TRUE),
        attr(y, "stata.note.numbers", exact = TRUE)
    ))) conflicts <- c(conflicts, "notes")
    note_source <- if (x_has_notes) x else y
    attr(result, "notes") <- attr(note_source, "notes", exact = TRUE)
    attr(result, "stata.note.numbers") <-
        attr(note_source, "stata.note.numbers", exact = TRUE)
    attr(result, "stata.characteristics") <- left_first(
        "stata.characteristics", "characteristics"
    )
    result <- .apply_haven_labelled_class(result, !is.null(labels))
    list(result = result, conflicts = conflicts)
}

.dta_union_format <- function(x, y, result, kind) {
    compatible <- function(format) {
        if (is.null(format)) return(FALSE)
        if (identical(kind, "string")) return(.valid_stata_string_format(format))
        if (identical(kind, "date")) {
            return(.valid_stata_calendar_format(format, "d"))
        }
        if (identical(kind, "datetime")) {
            return(.valid_stata_calendar_format(format, c("c", "C")))
        }
        .valid_stata_decimal_format(format) ||
            .valid_stata_calendar_format(format, c("w", "m", "q", "h", "y", "g", "b"))
    }
    x_format <- attr(x, "format.stata", exact = TRUE)
    y_format <- attr(y, "format.stata", exact = TRUE)
    if (compatible(x_format)) return(x_format)
    if (compatible(y_format)) return(y_format)
    if (identical(kind, "string")) {
        storage <- attr(result, "stata.string.storage", exact = TRUE)
        return(.default_stata_format(
            if (identical(storage, "strL")) "strL" else "fixed",
            .stata_string_storage_width(storage)
        ))
    }
    if (identical(kind, "date")) return("%td")
    if (identical(kind, "datetime")) return("%tc")
    .default_stata_format(.declared_stata_storage(result))
}

#' @rdname dta_match
#' @export
dta_intersect <- function(x, y) {
    if (is.null(x) || is.null(y)) return(NULL)
    kind <- .dta_common_identity_kind(x, y, "x", "y")
    x_key <- .dta_identity_key(x, kind, "x")
    y_key <- .dta_identity_key(y, kind, "y")
    keep <- !duplicated(x_key) & x_key %in% y_key
    .dta_slice_set_result(x, which(keep))
}

#' @rdname dta_match
#' @export
dta_setdiff <- function(x, y) {
    if (is.null(x)) return(NULL)
    if (is.null(y)) return(.dta_unique_result(x))
    kind <- .dta_common_identity_kind(x, y, "x", "y")
    x_key <- .dta_identity_key(x, kind, "x")
    y_key <- .dta_identity_key(y, kind, "y")
    keep <- !duplicated(x_key) & !(x_key %in% y_key)
    .dta_slice_set_result(x, which(keep))
}

#' @rdname dta_match
#' @export
dta_setequal <- function(x, y) {
    if (is.null(x) || is.null(y)) return(length(x) == 0L && length(y) == 0L)
    kind <- .dta_common_identity_kind(x, y, "x", "y")
    x_key <- unique(.dta_identity_key(x, kind, "x"))
    y_key <- unique(.dta_identity_key(y, kind, "y"))
    length(x_key) == length(y_key) && all(x_key %in% y_key)
}

# R 4.5 and later use mtfrm() when matching classed vectors. Keep ordinary
# values on the real axis so matching works when only one operand is
# Stata-backed. Extended missing codes use distinct imaginary components. A
# bare tagged-missing operand still needs
# dta_match() because its class carries no dispatch information.
.mtfrm_stata_numeric <- function(x) {
    parts <- .stata_identity_parts(x, "matching")
    result <- as.complex(parts$value)
    result[parts$rank == 1L] <- NA_complex_
    extended <- parts$rank >= 2L
    result[extended] <- complex(
        real = 0, imaginary = parts$rank[extended]
    )
    result
}

#' @export
mtfrm.stata_numeric <- function(x) {
    .mtfrm_stata_numeric(x)
}

#' @export
mtfrm.stata_string <- function(x) {
    as.character(x)
}

#' @export
mtfrm.stata_temporal <- function(x) {
    .mtfrm_stata_numeric(x)
}

.dta_unique_result <- function(x) {
    if (is.null(x)) return(NULL)
    kind <- .dta_identity_kind(x, "x")
    key <- .dta_identity_key(x, kind, "x")
    .dta_slice_set_result(x, which(!duplicated(key)))
}

.dta_slice_set_result <- function(x, locations) {
    result <- vctrs::vec_slice(x, locations)
    names(result) <- NULL
    result
}

.dta_common_identity_kind <- function(x, y, x_arg, y_arg) {
    x_kind <- .dta_identity_kind(x, x_arg)
    y_kind <- .dta_identity_kind(y, y_arg)
    if (!identical(x_kind, y_kind)) {
        stop(sprintf(
            "`%s` and `%s` have incompatible kinds (%s and %s)",
            x_arg, y_arg, x_kind, y_kind
        ), call. = FALSE)
    }
    x_kind
}

.dta_identity_kind <- function(x, arg) {
    if (is.null(x)) return("null")
    if (inherits(x, "POSIXct")) return("datetime")
    if (inherits(x, "Date")) return("date")
    if (is.character(x) && !is.factor(x) && is.null(dim(x))) return("string")
    if ((is.logical(x) || is.integer(x) || is.double(x)) &&
        !is.factor(x) && is.null(dim(x))) return("numeric")
    stop(sprintf(
        "`%s` must be a numeric, string, date, or datetime vector", arg
    ), call. = FALSE)
}

.dta_identity_key <- function(x, kind, arg) {
    if (identical(kind, "string")) {
        if (anyNA(x)) {
            stop(sprintf(
                "`%s` contains `NA_character_`; use \"\" for Stata string missing",
                arg
            ), call. = FALSE)
        }
        return(paste0("s:", enc2utf8(as.character(x))))
    }
    values <- as.double(x)
    codes <- .tab_missing_codes(values)
    valid_missing <- !is.na(codes) &
        (codes == 0L | (codes >= utf8ToInt("a") & codes <= utf8ToInt("z")))
    invalid_missing <- !is.na(codes) & !valid_missing
    if (any(invalid_missing)) {
        stop(sprintf(
            paste0(
                "`%s` contains a noncanonical NaN; use `NA_real_` for `.`, ",
                "or `tagged_missing()` for `.a` through `.z`"
            ),
            arg
        ), call. = FALSE)
    }
    key <- character(length(values))
    observed <- is.na(codes)
    if (any(observed & !is.finite(values))) {
        stop(sprintf(
            "`%s` contains an infinite value, which has no Stata identity", arg
        ), call. = FALSE)
    }
    values[observed & values == 0] <- 0
    key[observed] <- paste0("n:", sprintf("%a", values[observed]))
    key[!observed] <- paste0("m:", codes[!observed])
    key
}
