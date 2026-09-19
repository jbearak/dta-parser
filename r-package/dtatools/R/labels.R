#' Get and set Stata label metadata
#'
#' See [mutation-containers] for supported classes, grouping and conversion.
#' Dependency-free helpers for dataset labels, variable labels, and numeric
#' value-label tables. The getter and replacement names and their common call
#' forms are compatible with `labelled`; the `set_*()` functions and
#' `dataset_label()` are dtatools additions. Validation and mutation follow
#' Stata's metadata model and preserve the dtatools package's compact columns
#' and unrelated attributes.
#'
#' @section Getter results:
#' `var_label(data, variable)` returns one column's character label or
#' `NULL`, and `val_labels(data, variable)` returns its value-label table
#' or `NULL`. The `variable` argument follows the same rule as in
#' `gen()` and `replace_values()`, so `var_label(data, hh1)`,
#' `var_label(data, "hh1")`, `var_label(data, !!name)`, and
#' `var_label(data, .(name))` are equivalent. Asking for a column that
#' does not exist is an error.
#'
#' Without `variable`: for a vector, `var_label()` returns one character
#' value or `NULL`, and `val_labels()` returns a value-label table or
#' `NULL`. For a data frame, each returns a named list with one element
#' per column, including `NULL` entries. `dataset_label()` accepts only a
#' data frame or tibble and returns one character value or `NULL`.
#'
#' A value-label table is a named Stata numeric, a [dta_double()], or a
#' [dta_long()] when `haven` stored integer codes: the names are the
#' displayed text and the values are the Stata codes. Because the codes
#' are a Stata numeric, a tagged missing prints as `.a` rather than `NA`,
#' and comparisons follow Stata, so `names(labels)[labels == .a]` finds
#' the label of `.a`. The table can be passed back to any setter; the
#' `labels` attribute itself holds the bare named vector `haven` stores,
#' and the table's storage records that vector's type, so reading a table
#' and setting it back changes nothing.
#'
#' @section Looking up one label or code:
#' `val_label(x, v)` returns the label text of each code in `v`, and
#' `val_code(x, label)` the code of each label text, from `x`'s value-label
#' table. `x` is a labelled vector, a value-label table as `val_labels()`
#' returns it, or a data frame with `variable` naming the column, so
#' `val_label(data, status, 1)` and `val_label(data$status, 1)` agree. Both
#' are vectorised lookups: `val_label()` returns a character vector with
#' `NA` where a code has no label, and `val_code()` a Stata numeric of the
#' table's storage with system missing `.` where no label matches. A code
#' matches as Stata compares it: an observed value by equality and a
#' tagged missing by its tag, so `val_label(x, .a)` finds the label of
#' `.a`; system missing matches nothing. Label text matches exactly, and
#' when a table repeats a text the first code wins. On a vector without a
#' table, or with one Stata could not hold, every lookup is unmatched. `val_label()` shares its name and
#' `v` argument with `labelled::val_label()`, which looks up one code and
#' returns `NULL` when it is unlabelled; dtatools returns `NA` there so the
#' result keeps the length of `v`.
#'
#' @section Setting labels:
#' Replacement functions modify the supplied metadata. On a data frame,
#' replacement values must be a named list; a bare `NULL` clears that metadata
#' from every column. `set_var_labels()` and `set_val_labels()` support
#' named column updates in `...` and a programmatic named list in `.labels`.
#' They also accept vectors for pipeline use. Unknown, duplicate, unnamed, or
#' overlapping column updates fail atomically.
#'
#' `set_var_label()` sets the variable label of one column, mirroring Stata's
#' `label variable`. Its `variable` argument follows the same rule as in
#' `gen()` and `replace_values()`: one unquoted name, or one nonempty,
#' non-missing string. A name known only at run time therefore needs only the
#' tidy-evaluation escape, as in
#' `set_var_label(data, !!name, "Cluster number")`; no `rlang::inject()`
#' wrapper is required, and `rlang::sym()` is optional, so the older
#' `!!rlang::sym(name)` spelling remains equivalent. A `.(name)` call reaches
#' the same place: `set_var_label(data, .(name), "Cluster number")`. There is
#' no `.data` pronoun for this argument, because it names a target rather
#' than reading a column. On a bare vector, `set_var_label(x, label)` sets the
#' vector's label, as the non-data-frame branch of `set_var_labels()` does.
#' `set_var_labels()` and `set_val_labels()` name a runtime column with a
#' `.(name) := value` tag in `...` or a programmatic named list through
#' `.labels`, and `keep_vars()`, `drop_vars()`, and
#' `rename_vars()` take `tidyselect::all_of()` or `.names`.
#'
#' `set_var_labels(data, variable, label)` and
#' `set_val_labels(data, variable, labels)` also accept the positional
#' shape of `gen()` and `replace_values()`. It is recognized only when
#' `.labels` is `NULL`, `.data` is a data frame, and `...` holds exactly
#' two untagged arguments whose first is syntactically a name: a bare
#' symbol, one string literal, `.(name)`, or `!!name`, which unquotes to
#' a string literal at capture. The symbol is taken as the column name
#' literally, never resolved against caller variables, and the second
#' argument is evaluated in the caller's environment as that column's
#' new metadata. A first argument that is any other expression, and
#' every tagged call, keeps today's path and today's errors.
#'
#' The data-frame forms of `set_var_label()`, `set_var_labels()`, and
#' `set_val_labels()` mutate by reference, as `gen()` and `replace_values()` do.
#' The caller and every other binding to the same data frame see the new
#' metadata. Use `copy_data()` first when isolation is required. Replacement
#' syntax applies R's assignment semantics to the metadata it changes: it
#' updates the binding on its left-hand side but not another binding to the
#' original data frame. Later explicit value writes to these separate tables
#' remain isolated, including writes to columns the replacement left unchanged. Vector
#' forms cannot mutate by reference and return a copy. Whole-table label
#' replacement also returns a copy and preserves a dibble's type.
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
#' An imported nondefault or shared Stata table name may be carried separately
#' in `attr(x, "value.label.name")`. The attribute is a serialization hint, not
#' shared semantic state. Each vector's `labels` mapping is authoritative in R.
#' Value-label setters retain the hint while value labels remain and remove
#' it when the mapping is cleared. Use [set_dta_metadata()] to set the hint and
#' raw mapping together. That helper preserves an explicitly named zero-length
#' mapping and its hint as an empty table, and the value-label setters keep
#' such a table when it is set back; clearing with `NULL` or an unnamed
#' `numeric()` removes both. This does not create a shared table registry.
#'
#' See the
#' \href{https://github.com/jbearak/dta-parser/blob/main/docs/r-label-metadata.md}{R label metadata guide}
#' for the supported call surface and the version-specific comparison with
#' `labelled`.
#'
#' @param x A vector or data frame.
#' @param data A dibble for `set_var_label()`; a data frame or tibble for the
#'   getters.
#' @param value New label metadata. Data-frame replacement forms require a
#'   named list or `NULL`.
#' @param .data A vector, or a dibble for the table forms of `set_var_labels()`
#'   and `set_val_labels()`.
#' @param ... Named column updates for a data frame. A column named at run
#'   time takes a `.(name) := value` tag. For a vector, supply one variable
#'   label or one or more named value-label codes.
#' @param .labels A programmatic label value for a vector, or a named list of
#'   column updates for a data frame.
#' @param variable One unquoted column name, or one nonempty, non-missing
#'   character string, which is what `!!name` unquotes to and what a
#'   `.(name)` call supplies in place. Optional in `var_label()` and
#'   `val_labels()`: when supplied, `x` must be a data frame and only that
#'   column's metadata is returned.
#' @param label One variable label, or `NULL` to remove it. In the vector
#'   shape `set_var_label(x, label)` the label is the second argument. For
#'   `val_code()`, a character vector of label texts to look up.
#' @param v A numeric vector of value-label codes to look up, Stata missings
#'   included. In the vector shape `val_label(x, v)` it is the second
#'   argument, as in `labelled::val_label()`.
#' @return Getters return the metadata described above. Replacement functions
#'   and `set_*()` functions return the updated vector or data frame. Data-frame
#'   `set_*()` forms return it invisibly because they already mutated it by
#'   reference.
#' @examples
#' status <- c(1, 2, 1)
#' var_label(status) <- "Interview status"
#' val_labels(status) <- c(Complete = 1, Refused = 2)
#'
#' survey <- dibble(status = status, stratum = c(1, 1, 2))
#' dataset_label(survey) <- "Baseline survey"
#' set_var_labels(
#'     survey,
#'     status = "Interview status",
#'     .labels = list(stratum = "Sampling stratum")
#' )
#' # One column at a time, in the (data, variable) shape of gen()
#' var_label(survey, status)
#' val_labels(survey, status)
#' set_var_label(survey, status, "Interview status")
#' set_val_labels(survey, status, c(Complete = 1, Refused = 2))
#' set_var_labels(survey, stratum, "Sampling stratum")
#'
#' var_label(survey)
#' val_labels(survey$status)
#'
#' # One label or code at a time, in either direction
#' val_label(survey$status, 2)
#' val_label(survey, status, c(1, 2, 3))
#' val_code(survey$status, "Refused")
#'
#' # A column name known only at run time
#' stratum_name <- "stratum"
#' set_var_label(survey, !!stratum_name, "Sampling stratum")
#' var_label(survey, !!stratum_name)
#' @export
var_label <- function(x, variable) {
    .validate_label_object(x)
    variable <- rlang::enquo(variable)
    if (!rlang::quo_is_missing(variable)) {
        column <- .label_lookup_column(x, variable)
        return(attr(column, "label", exact = TRUE))
    }
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
val_labels <- function(x, variable) {
    .validate_label_object(x)
    variable <- rlang::enquo(variable)
    if (!rlang::quo_is_missing(variable)) {
        column <- .label_lookup_column(x, variable)
        return(.value_label_table(attr(column, "labels", exact = TRUE)))
    }
    if (is.data.frame(x)) {
        return(stats::setNames(
            lapply(x, function(column) {
                .value_label_table(attr(column, "labels", exact = TRUE))
            }),
            names(x)
        ))
    }

    .value_label_table(attr(x, "labels", exact = TRUE))
}

#' @rdname var_label
#' @export
val_label <- function(x, variable, v) {
    .validate_label_object(x)
    if (is.data.frame(x)) {
        if (missing(v)) {
            stop("`v` must be supplied after `variable` when `x` is a data frame",
                 call. = FALSE)
        }
        column <- .label_lookup_column(x, rlang::enquo(variable))
        table <- .stata_value_label_table(attr(column, "labels", exact = TRUE))
    } else {
        # `val_label(x, v)`: the vector shape, as `set_var_label(x, label)`
        # takes its label in the second position.
        if (missing(v)) {
            if (missing(variable)) stop("`v` must be supplied", call. = FALSE)
            v <- variable
        } else if (!missing(variable)) {
            stop("`variable` applies only when `x` is a data frame", call. = FALSE)
        }
        table <- .lookup_value_label_table(x)
    }
    # An `integer64` stores bit patterns, not Stata values, and a factor's
    # codes are positions, so neither can be looked up as a code.
    if (!is.numeric(v) || !is.null(dim(v)) || is.factor(v) ||
        inherits(v, "integer64")) {
        stop("`v` must be a numeric vector of value-label codes", call. = FALSE)
    }
    if (is.null(table)) return(rep(NA_character_, length(v)))
    text <- names(table)[.match_value_label_codes(v, table)]
    text[!is.na(text) & !nzchar(text)] <- NA_character_
    text
}

#' @rdname var_label
#' @export
val_code <- function(x, variable, label) {
    .validate_label_object(x)
    if (is.data.frame(x)) {
        if (missing(label)) {
            stop(paste(
                "`label` must be supplied after `variable` when `x` is a",
                "data frame"
            ), call. = FALSE)
        }
        column <- .label_lookup_column(x, rlang::enquo(variable))
        table <- .stata_value_label_table(attr(column, "labels", exact = TRUE))
    } else {
        if (missing(label)) {
            if (missing(variable)) stop("`label` must be supplied", call. = FALSE)
            label <- variable
        } else if (!missing(variable)) {
            stop("`variable` applies only when `x` is a data frame", call. = FALSE)
        }
        table <- .lookup_value_label_table(x)
    }
    if (!is.character(label) || !is.null(dim(label))) {
        stop("`label` must be a character vector of value-label text", call. = FALSE)
    }
    if (is.null(table)) return(dta_double(rep(NA_real_, length(label))))
    # A table in hand keeps its storage; a raw mapping is wrapped as
    # `val_labels()` wraps it. Blank text is no label, so it matches nothing.
    codes <- if (inherits(table, "dta_numeric")) table else .value_label_table(table)
    text <- names(table)
    text[is.na(text) | !nzchar(text)] <- NA_character_
    unname(codes[match(label, text, incomparables = NA_character_)])
}

# The table a lookup reads: a labelled vector's own `labels` attribute, or
# the vector itself when it is a table in hand, a named numeric with no
# table of its own, as `val_labels()` returns one. Anything else has no
# table, and every lookup on it is unmatched. So is a table Stata could
# not hold, character codes or a number outside `long`, which
# `val_labels()` returns bare: it has no Stata codes to look up.
.lookup_value_label_table <- function(x) {
    table <- attr(x, "labels", exact = TRUE)
    if (is.null(table) && is.numeric(x) && !is.null(names(x)) &&
        is.null(dim(x))) {
        table <- x
    }
    .stata_value_label_table(table)
}

.stata_value_label_table <- function(table) {
    if (is.null(table) || !is.numeric(table) || !is.null(dim(table)) ||
        is.null(names(table)) || inherits(table, "integer64") ||
        !all(.dta_value_label_code_info(table)$valid)) {
        return(NULL)
    }
    table
}

# Which table entry each value matches, as Stata compares: an observed
# value by equality, a tagged missing by its tag, and system missing, an
# R `NaN`, or an unrepresentable value nothing. Integer and double codes
# meet as doubles, so a `long` table matches a double value.
.match_value_label_codes <- function(values, table) {
    values <- as.double(.dta_snapshot(values))
    table_values <- as.double(.dta_snapshot(table))
    codes <- .tab_missing_codes(values)
    table_codes <- .tab_missing_codes(table_values)
    matched <- rep(NA_integer_, length(values))
    observed <- is.na(codes)
    observed_table <- which(is.na(table_codes))
    matched[observed] <- observed_table[
        match(values[observed], table_values[observed_table])
    ]
    tagged <- !observed & codes >= utf8ToInt("a") & codes <= utf8ToInt("z")
    matched[tagged] <- match(codes[tagged], table_codes)
    matched
}

# The stored `labels` attribute is the bare named vector haven writes, so
# files and `labelled` see what they expect. Read back through
# `val_labels()`, the codes are a Stata numeric, so `.a` prints as `.a`
# and `labels == .a` is Stata's comparison (ADR 0040). The storage
# records the codes' own type, `long` for haven's integer codes and
# `double` otherwise, so a setter can store the table back exactly as it
# was. A table haven wrote that Stata could not hold, a character code, an
# infinity, an integer outside `long`, or an `integer64`, whose doubles
# are bit patterns rather than values, is returned bare as haven stores
# it, since a Stata numeric could not carry it.
.value_label_table <- function(labels) {
    if (is.null(labels) || !is.numeric(labels) ||
        inherits(labels, "integer64") ||
        !all(.dta_value_label_code_info(labels)$valid)) {
        return(labels)
    }
    storage <- if (is.integer(labels)) "long" else "double"
    result <- as.double(labels)
    names(result) <- names(labels)
    attr(result, "stata.storage") <- storage
    attr(result, "class") <- .dta_storage_class(storage)
    result
}

# `var_label(data, variable)` and `val_labels(data, variable)` read one
# column's metadata. The name follows the same rule as in `gen()`: one
# unquoted name, one string, `!!name`, or `.(name)`. A symbol is taken
# as the column name literally, never resolved against caller variables.
.label_lookup_column <- function(x, variable) {
    if (!is.data.frame(x)) {
        stop("`x` must be a data frame when `variable` is supplied",
             call. = FALSE)
    }
    name <- .unquoted_variable_name(variable)
    location <- match(name, names(x))
    if (is.na(location)) {
        stop(sprintf("Column `%s` does not exist", name), call. = FALSE)
    }
    x[[location]]
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

.validate_column_updates <- function(data_names, value, normalize, argument) {
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
    unknown <- setdiff(update_names, data_names)
    if (length(unknown) > 0L) {
        stop(sprintf(
            "Unknown column%s: %s",
            if (length(unknown) == 1L) "" else "s",
            paste(unknown, collapse = ", ")
        ), call. = FALSE)
    }
    duplicated_data_names <- unique(data_names[
        duplicated(data_names) | duplicated(data_names, fromLast = TRUE)
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

.warn_dta_metadata_limits <- function(violations) {
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
    .repair_data_table_container(.Call(C_dtatools_metadata_copy, value))
}

.metadata_view <- function(value) {
    .Call(C_dtatools_metadata_view, value)
}

.dta_value_label_code_info <- function(value) {
    missing_codes <- .tab_missing_codes(value)
    tagged <- !is.na(missing_codes) &
        missing_codes >= utf8ToInt("a") & missing_codes <= utf8ToInt("z")
    observed <- is.na(missing_codes)
    observed <- observed & !.invalid_dta_observed(
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
    label_text <- names(value)
    if (length(value) == 0L) {
        # `numeric()` clears the table; a named empty table, as
        # `set_dta_metadata()` declares and `val_labels()` returns, is kept
        # so a read-and-set round trip leaves it in place.
        if (is.null(label_text)) return(NULL)
        codes <- .bare_value_label_codes(value)
        names(codes) <- character()
        return(codes)
    }
    if (is.null(label_text) || length(label_text) != length(value)) {
        stop(sprintf("`%s` must name every value-label code", argument),
             call. = FALSE)
    }
    keep <- !is.na(label_text) & label_text != ""
    value <- value[keep]
    label_text <- label_text[keep]
    if (length(value) == 0L) return(NULL)

    code_info <- .dta_value_label_code_info(value)
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

    value <- .bare_value_label_codes(value)
    names(value) <- label_text
    value
}

# The codes as haven's bare vector, in their own type. A table read
# through `val_labels()` recorded integer codes as `long`, so setting it
# back is exact (ADR 0040); a `long` table that was edited to hold a
# tagged missing has to stay double, since an R integer cannot carry the
# tag and `as.integer()` would turn `.a` into `.`.
.bare_value_label_codes <- function(value) {
    integer_codes <- is.integer(value) || (
        identical(.declared_dta_storage(value), "long") &&
            all(is.na(.tab_missing_codes(value)))
    )
    codes <- if (integer_codes) as.integer(value) else as.double(value)
    as.vector(codes)
}

# The bundle setter keeps a mapping's blank text, so it bypasses
# `.normalize_value_labels()`; this applies the same type rule to what it
# stores, so a `val_labels()` table lands as the bare vector it came from.
.stored_value_labels <- function(labels) {
    if (is.null(labels)) return(NULL)
    label_text <- names(labels)
    codes <- .bare_value_label_codes(labels)
    names(codes) <- label_text
    codes
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
        if (inherits(value, "dta_numeric")) {
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

.label_replacement_data <- function(data) {
    if (is.null(.reference_state(data))) {
        .metadata_copy(data)
    } else {
        .reference_snapshot(data)
    }
}

.check_variable_label_updates <- function(updates) {
    .warn_dta_metadata_limits(
        .text_label_violations(updates, "variable label for")
    )
}

.check_value_label_updates <- function(access, updates) {
    locations <- match(names(updates), access$names)
    for (index in seq_along(updates)) {
        column <- .data_column_at(access, locations[[index]])
        .validate_value_label_target(
            column, updates[[index]], paste0("x$", names(updates)[[index]])
        )
    }
    .warn_dta_metadata_limits(.value_label_violations(updates))
}

.apply_variable_label_updates <- function(access, updates) {
    data <- access$data
    staged <- .metadata_table_snapshot(data)
    locations <- match(names(updates), names(staged))
    for (index in seq_along(updates)) {
        location <- locations[[index]]
        column <- .metadata_copy(.subset2(staged, location))
        attr(column, "label") <- updates[[index]]
        .Call(C_dtatools_set_data_column, staged, location, column)
    }
    .commit_metadata_table(data, staged, locations)
}

.apply_value_label_updates <- function(access, updates) {
    data <- access$data
    staged <- .metadata_table_snapshot(data)
    locations <- match(names(updates), names(staged))
    for (index in seq_along(updates)) {
        location <- locations[[index]]
        column <- .metadata_copy(.subset2(staged, location))
        attr(column, "labels") <- updates[[index]]
        if (is.null(updates[[index]])) {
            attr(column, "value.label.name") <- NULL
        }
        column <- .apply_haven_labelled_class(column, !is.null(updates[[index]]))
        .Call(C_dtatools_set_data_column, staged, location, column)
    }
    .commit_metadata_table(data, staged, locations)
}

#' @rdname var_label
#' @export
`var_label<-` <- function(x, value) {
    original <- x
    .validate_label_object(x)
    if (is.data.frame(x)) {
        .reject_data_table_subclass(x, "x")
        if (is.null(value)) {
            x <- .label_replacement_data(x)
            access <- .column_access(x)
            for (index in seq_along(access$names)) {
                column <- .metadata_copy(.data_column_at(access, index))
                attr(column, "label") <- NULL
                .set_data_column_at(access, index, column)
            }
            return(invisible(.close_dibble(original, x)))
        }
        source <- .column_access(x)
        updates <- .validate_column_updates(
            source$names, value, .normalize_text_label, "value"
        )
        .check_variable_label_updates(updates)
        x <- .label_replacement_data(x)
        access <- .column_access(x)
        return(.close_dibble(original, .apply_variable_label_updates(access, updates)))
    }

    value <- .normalize_text_label(value)
    .warn_dta_metadata_limits(
        .text_label_violations(value, "variable label")
    )
    x <- .metadata_copy(x)
    attr(x, "label") <- value
    x
}

#' @rdname var_label
#' @export
`dataset_label<-` <- function(data, value) {
    original <- data
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame", call. = FALSE)
    }
    .reject_data_table_subclass(data)
    value <- .normalize_text_label(value)
    .warn_dta_metadata_limits(
        .text_label_violations(value, "dataset label")
    )
    data <- .label_replacement_data(data)
    attr(data, "label") <- value
    .close_dibble(original, .repair_data_table_container(data))
}

#' @rdname var_label
#' @export
`val_labels<-` <- function(x, value) {
    original <- x
    .validate_label_object(x)
    if (is.data.frame(x)) {
        .reject_data_table_subclass(x, "x")
        if (is.null(value)) {
            x <- .label_replacement_data(x)
            access <- .column_access(x)
            for (index in seq_along(access$names)) {
                column <- .metadata_copy(.data_column_at(access, index))
                attr(column, "labels") <- NULL
                attr(column, "value.label.name") <- NULL
                column <- .apply_haven_labelled_class(column, FALSE)
                .set_data_column_at(access, index, column)
            }
            return(invisible(.close_dibble(original, x)))
        }
        source <- .column_access(x)
        updates <- .validate_column_updates(
            source$names, value, .normalize_value_labels, "value"
        )
        .check_value_label_updates(source, updates)
        x <- .label_replacement_data(x)
        access <- .column_access(x)
        return(.close_dibble(original, .apply_value_label_updates(access, updates)))
    }

    value <- .normalize_value_labels(value)
    .validate_value_label_target(x, value)
    .warn_dta_metadata_limits(.value_label_violations(value))
    x <- .metadata_copy(x)
    attr(x, "labels") <- value
    if (is.null(value)) attr(x, "value.label.name") <- NULL
    .apply_haven_labelled_class(x, !is.null(value))
}

#' @rdname var_label
#' @export
set_var_label <- function(data, variable, label) {
    .require_metadata_target(data)
    if (!is.data.frame(data)) {
        # `set_var_label(x, label)`: the vector shape, mirroring the
        # non-data-frame branch of `set_var_labels()`. Any other
        # non-data-frame call keeps its existing error.
        if (!missing(variable) && missing(label)) {
            return(`var_label<-`(data, variable))
        }
        stop("`data` must be a data frame", call. = FALSE)
    }
    .reject_data_table_subclass(data)
    name <- .unquoted_variable_name(rlang::enquo(variable))
    access <- .column_access(data)
    updates <- .validate_column_updates(
        access$names, stats::setNames(list(label), name),
        .normalize_text_label, "label"
    )
    .check_variable_label_updates(updates)
    .apply_variable_label_updates(access, updates)
}

.is_runtime_name_tag <- function(argument) {
    is.call(argument) && length(argument) == 3L &&
        identical(argument[[1L]], quote(`:=`)) &&
        .is_runtime_name_call(argument[[2L]])
}

# `.(name) := value` in the plural setters. rlang rejects a call on the
# left of `:=` before it evaluates anything, so the tags are resolved here
# first: each `.()` left-hand side becomes an ordinary argument name, then
# `rlang::dots_list()` runs on the rewritten argument and keeps its own
# handling of `!!!`, `:=`, homonyms and empty arguments unchanged.
#
# Dots forwarded from an enclosing function belong to that function's
# caller, not to the setter's immediate caller, so a single evaluation
# environment cannot be right for every argument. `rlang::enquos0()`
# captures each dot's own expression and environment without injection
# processing, which also lets a `.()` call survive on the left of `:=`.
# Each argument is then handed to its own `rlang::dots_list()` call,
# evaluated in its own frame, so `!!!` and `:=` inside it behave exactly
# as they do on the ordinary path. `.homonyms = "keep"` makes the
# per-argument results concatenate without loss.
.dots_list_with_runtime_names <- function(quoted, plain, quosures) {
    if (!any(vapply(as.list(quoted), .is_runtime_name_tag, logical(1L)))) {
        # No `.()` tag, so nothing needs rewriting. Taking the ordinary
        # path here keeps every existing call byte-identical in behavior,
        # including dots forwarded from an enclosing function, whose
        # promises belong to that caller rather than to this frame.
        return(plain())
    }
    quosures <- quosures()
    labels <- names(quosures)
    if (is.null(labels)) labels <- rep("", length(quosures))
    pieces <- vector("list", length(quosures))
    for (index in seq_along(quosures)) {
        quosure <- quosures[[index]]
        if (rlang::quo_is_missing(quosure)) {
            stop(sprintf("Argument %d can't be empty.", index), call. = FALSE)
        }
        expression <- rlang::quo_get_expr(quosure)
        frame <- rlang::quo_get_env(quosure)
        label <- labels[[index]]
        if (.is_runtime_name_tag(expression)) {
            label <- .runtime_name_call_value(expression[[2L]], frame)
            expression <- expression[[3L]]
        }
        # The function object heads the call, because a constant's
        # quosure carries the empty environment, where `::` is unbound.
        call <- as.call(c(
            list(rlang::dots_list), stats::setNames(list(expression), label),
            list(.homonyms = "keep", .ignore_empty = "none")
        ))
        pieces[[index]] <- eval(call, frame)
    }
    do.call(c, pieces)
}

# `!!name` before rlang's quasiquotation runs: the parsed call
# `!(!name)`. `rlang::enquos()` unquotes it to a string literal at
# capture, which is why it counts as syntactically a name below.
.is_double_bang_call <- function(expression) {
    is.call(expression) && length(expression) == 2L &&
        identical(expression[[1L]], quote(`!`)) &&
        is.call(expression[[2L]]) && length(expression[[2L]]) == 2L &&
        identical(expression[[2L]][[1L]], quote(`!`))
}

# `set_var_labels(data, variable, label)` and
# `set_val_labels(data, variable, labels)`: the positional shape that
# mirrors `gen(data, variable, ...)`. It is recognized on the defused
# dots, before anything is evaluated, and only when `.labels` is NULL,
# `.data` is a data frame, and `...` is exactly two untagged, nonempty
# arguments whose first is syntactically a name: a bare symbol, one
# string literal, `.(name)`, or `!!name`. Any other first argument
# falls through to the existing path and its existing errors, and a
# symbol is taken as the column name literally, never resolved against
# caller variables. No call that succeeds today matches: two untagged
# dots on a data frame have always been an error, because column
# updates in `...` must be named.
.is_positional_label_dots <- function(quoted) {
    if (length(quoted) != 2L) return(FALSE)
    tags <- names(quoted)
    if (!is.null(tags) && any(nzchar(tags))) return(FALSE)
    if (identical(quoted[[1L]], quote(expr = )) ||
        identical(quoted[[2L]], quote(expr = ))) {
        return(FALSE)
    }
    first <- quoted[[1L]]
    is.symbol(first) ||
        (is.character(first) && length(first) == 1L) ||
        .is_runtime_name_call(first) ||
        .is_double_bang_call(first)
}

#' @rdname var_label
#' @export
set_var_labels <- function(.data, ..., .labels = NULL) {
    .require_metadata_target(.data)
    quoted <- substitute(...())
    dots <- if (is.data.frame(.data) && is.null(.labels) &&
        .is_positional_label_dots(quoted)) {
        pair <- rlang::enquos(...)
        stats::setNames(
            list(rlang::eval_tidy(pair[[2L]])),
            .unquoted_variable_name(pair[[1L]])
        )
    } else {
        .dots_list_with_runtime_names(
            quoted,
            function() {
                rlang::dots_list(
                    ..., .homonyms = "keep", .ignore_empty = "none"
                )
            },
            function() rlang::enquos0(...)
        )
    }
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
    .reject_data_table_subclass(.data, ".data")
    if (!is.null(.labels) && !is.list(.labels)) {
        stop("`.labels` must be a named list or NULL", call. = FALSE)
    }

    updates <- c(if (is.null(.labels)) list() else .labels, dots)
    access <- .column_access(.data)
    updates <- .validate_column_updates(
        access$names, updates, .normalize_text_label, "labels"
    )
    .check_variable_label_updates(updates)
    .apply_variable_label_updates(access, updates)
}

#' @rdname var_label
#' @export
set_val_labels <- function(.data, ..., .labels = NULL) {
    .require_metadata_target(.data)
    quoted <- substitute(...())
    dots <- if (is.data.frame(.data) && is.null(.labels) &&
        .is_positional_label_dots(quoted)) {
        pair <- rlang::enquos(...)
        stats::setNames(
            list(rlang::eval_tidy(pair[[2L]])),
            .unquoted_variable_name(pair[[1L]])
        )
    } else {
        .dots_list_with_runtime_names(
            quoted,
            function() {
                rlang::dots_list(
                    ..., .homonyms = "keep", .ignore_empty = "none"
                )
            },
            function() rlang::enquos0(...)
        )
    }
    if (!is.data.frame(.data)) {
        if (!is.null(.labels) && length(dots) > 0L) {
            stop(
                "Supply vector value labels in either `...` or `.labels`, not both",
                call. = FALSE
            )
        }
        value <- if (!is.null(.labels)) {
            .labels
        } else if (length(dots) == 0L) {
            NULL
        } else if (length(dots) == 1L &&
                   (is.null(names(dots)) || !nzchar(names(dots)[1L]))) {
            # A single unnamed argument is a whole table, kept as supplied so
            # a `val_labels()` result carries its storage back unchanged.
            dots[[1L]]
        } else {
            unlist(dots, recursive = FALSE, use.names = TRUE)
        }
        return(`val_labels<-`(.data, value))
    }
    .reject_data_table_subclass(.data, ".data")
    if (!is.null(.labels) && !is.list(.labels)) {
        stop("`.labels` must be a named list or NULL", call. = FALSE)
    }

    updates <- c(if (is.null(.labels)) list() else .labels, dots)
    access <- .column_access(.data)
    updates <- .validate_column_updates(
        access$names, updates, .normalize_value_labels, "labels"
    )
    .check_value_label_updates(access, updates)
    .apply_value_label_updates(access, updates)
}
