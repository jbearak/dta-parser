# Column export classification shared by save_dta(), save_arrow(), and
# datasig() (ADR 0037).
#
# One ladder decides what an R column is; each writer then decides only
# whether its target can hold that kind and how to lay it out. save_dta()
# refuses `difftime` and `raw`, save_arrow() and datasig() export every kind.
# The kinds are the Arrow profile's vocabulary because it is the wider one:
# a column with a `stata.storage` declaration is a Stata-typed column before
# it is a date or a number, so the declared storage, not the R type, is what
# every target honours.
#
# The per-column facts both writers read the same way live here too: the
# variable label, the string declaration, the temporal kind, and the
# display-format category. Value layout (epoch shifts, string plans, factor
# levels) differs between targets and stays with each writer.

.write_column_kinds <- c(
    "factor", "stata", "date", "datetime", "difftime", "character",
    "raw", "logical", "integer", "double"
)

# The kinds save_dta() exports. A DTA file has no duration or byte type.
.dta_write_kinds <- setdiff(.write_column_kinds, c("difftime", "raw"))

.write_numeric_classes <- function() {
    c(
        .dta_metadata_vector_class, "haven_labelled", "vctrs_vctr",
        "dta_numeric", paste0("dta_", .dta_storage),
        "double", "integer", "logical"
    )
}

# One of `.write_column_kinds`, or `NA` for a column no writer exports: a
# matrix, a list, a complex vector, a calendar class on a payload that is
# not numeric, or a classed vector whose class set is not one dtatools or
# haven produces for that kind. A generic `vctrs_vctr`
# is such a vector: only a haven-labelled or Stata-typed numeric carries
# that class with a meaning the writers know, and haven labels only
# integers and doubles.
.write_column_kind <- function(column) {
    if (!is.null(dim(column))) return(NA_character_)
    classes <- attr(column, "class", exact = TRUE)
    admits <- function(allowed) is.null(classes) || all(classes %in% allowed)
    known_numeric <- function() {
        if (identical(typeof(column), "logical")) {
            return(admits(.dta_metadata_vector_class))
        }
        admits(.write_numeric_classes()) && (
            !("vctrs_vctr" %in% classes) ||
                inherits(column, c("haven_labelled", "dta_numeric"))
        )
    }
    if (is.factor(column)) {
        if (admits(c(.dta_metadata_vector_class, "ordered", "factor"))) {
            return("factor")
        }
        return(NA_character_)
    }
    numeric_payload <- typeof(column) %in% c("logical", "integer", "double")
    if (numeric_payload &&
        !is.null(attr(column, "stata.storage", exact = TRUE))) {
        allowed <- if (is.null(.write_temporal_kind(column))) {
            .write_numeric_classes()
        } else {
            c(
                .dta_metadata_vector_class, "dta_temporal", "dta_date",
                "dta_datetime", "Date", "POSIXct", "POSIXt"
            )
        }
        if (admits(allowed)) return("stata")
        return(NA_character_)
    }
    if (inherits(column, "Date")) {
        if (numeric_payload && admits(c(
            .dta_metadata_vector_class, "dta_temporal", "dta_date", "Date"
        ))) return("date")
        return(NA_character_)
    }
    if (inherits(column, "POSIXct")) {
        if (numeric_payload && admits(c(
            .dta_metadata_vector_class, "dta_temporal", "dta_datetime",
            "POSIXct", "POSIXt"
        ))) return("datetime")
        return(NA_character_)
    }
    if (inherits(column, "difftime")) {
        if (numeric_payload &&
            admits(c(.dta_metadata_vector_class, "difftime"))) {
            return("difftime")
        }
        return(NA_character_)
    }
    if (is.character(column)) {
        if (admits(c(
            .dta_metadata_vector_class, "dta_string", "vctrs_vctr",
            "character"
        ))) return("character")
        return(NA_character_)
    }
    if (identical(typeof(column), "raw")) {
        if (admits(.dta_metadata_vector_class)) return("raw")
        return(NA_character_)
    }
    if (numeric_payload && known_numeric()) {
        return(typeof(column))
    }
    NA_character_
}

.write_column_description <- function(column) {
    classes <- attr(column, "class", exact = TRUE)
    if (is.null(classes)) typeof(column) else paste(classes, collapse = "/")
}

# Classifies every column and refuses the ones the target cannot export,
# naming each with its class so the caller can see why.
.write_column_kinds_for <- function(data, supported = .write_column_kinds) {
    kinds <- vapply(data, .write_column_kind, character(1))
    unsupported <- is.na(kinds) | !(kinds %in% supported)
    if (any(unsupported)) {
        details <- sprintf(
            "`%s` (%s)", names(data)[unsupported],
            vapply(data[unsupported], .write_column_description, character(1))
        )
        .dta_write_abort(sprintf(
            "Unsupported columns: %s", paste(details, collapse = ", ")
        ))
    }
    kinds
}

# "date", "datetime", or NULL: the calendar a numeric column's values count.
.write_temporal_kind <- function(column) {
    if (inherits(column, "Date")) return("date")
    if (inherits(column, "POSIXct")) return("datetime")
    NULL
}

# The display-format family an exported column's `format.stata` must
# belong to.
.write_format_category <- function(kind) {
    switch(kind,
        character = "string",
        date = "date",
        datetime = "datetime",
        "numeric"
    )
}

# The display format Stata assigns a numeric variable of this storage, or
# the calendar format when the values are dates or datetimes.
.write_default_numeric_format <- function(storage, temporal = NULL) {
    switch(temporal %||% "numeric",
        date = "%td",
        datetime = "%tc",
        .default_dta_format(storage)
    )
}

# The Stata storage a Stata-typed column declares, or an abort when the
# declaration is not one of the five numeric storage types.
.write_stata_storage <- function(column, name) {
    storage <- attr(column, "stata.storage", exact = TRUE)
    if (!is.character(storage) || length(storage) != 1L ||
        !(storage %in% .dta_storage)) {
        .dta_write_abort(sprintf(
            "Column `%s` has an invalid `stata.storage` declaration", name
        ))
    }
    storage
}

# A character column's `stata.string.storage` declaration as
# `list(storage, width)`, where `width` is `NULL` for `strL`, or `NULL`
# when the column declares none. A malformed declaration aborts.
.write_string_declaration <- function(column, name) {
    declared <- attr(column, "stata.string.storage", exact = TRUE)
    if (is.null(declared)) return(NULL)
    if (!.valid_string_declaration(declared)) {
        .dta_write_abort(sprintf(
            "Column `%s` has an invalid `stata.string.storage` declaration",
            name
        ))
    }
    list(
        storage = declared,
        width = if (identical(declared, "strL")) NULL else {
            as.integer(sub("^str", "", declared))
        }
    )
}

.write_variable_label <- function(column, name) {
    .write_text(
        attr(column, "label", exact = TRUE),
        sprintf("variable label for `%s`", name)
    )
}
