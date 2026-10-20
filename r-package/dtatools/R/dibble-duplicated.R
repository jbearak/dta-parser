# Base compares data frame rows by building a list of cells for each row,
# which dispatches `[[` once per Stata cell: about 50 microseconds each, or
# over an hour for a survey file. These methods give base's answer from one
# integer key per row and fall back to base for anything else.
#
# `match()` applies the equality `duplicated()` applies to the cells: every
# `NA` matches every other, tagged missings included, `NaN` matches only
# `NaN`, `-0` matches `0`, and strings compare after translation to UTF-8.
# A Stata numeric cell is the value its `[[` method passes through the
# constructor, so a column whose values do not all fit its storage exactly
# is constructed whole the same way: a float rounds to float precision, and
# an invalid value leaves base to signal the error. Other columns, such as
# factors, dates, lists, matrices, strings marked "bytes", or a class
# another package gives a `[[`, `dim` or `length` method, take base's
# comparison.

#' @export
duplicated.dibble <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
    # Base sends a single column to that column's own method.
    key <- if (length(x) > 1L) {
        .dibble_row_key(
            x, incomparables, fromLast, "duplicated", parent.frame(), .Class[-1L]
        )
    }
    if (is.null(key)) return(NextMethod())
    duplicated(key, fromLast = fromLast)
}

#' @export
anyDuplicated.dibble <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
    key <- if (length(x) > 0L) {
        .dibble_row_key(
            x, incomparables, fromLast, "anyDuplicated", parent.frame(),
            .Class[-1L]
        )
    }
    if (is.null(key)) return(NextMethod())
    anyDuplicated(key, fromLast = fromLast)
}

#' @export
unique.dibble <- function(x, incomparables = FALSE, fromLast = FALSE, ...) {
    if (!isFALSE(incomparables) ||
        !.dibble_next_method_base(.Class[-1L], "unique", parent.frame())) {
        return(NextMethod())
    }
    # Base's method subsets with `x[!duplicated(x, ...), , drop = FALSE]`,
    # where a dibble's bracket would read a column named `x` or `fromLast`
    # in place of the argument. A lone symbol stays the caller's index.
    rows <- !duplicated(x, fromLast = fromLast, ...)
    x[rows, , drop = FALSE]
}

# For each row, the first row equal to it, as `match()` over the rows' cell
# lists would give it, or NULL when base must compare. `caller` is where the
# generic was called and `chain` the classes after the dibble method's, which
# `NextMethod()` follows even when the method before changed `class(x)`.
.dibble_row_key <- function(x, incomparables, fromLast, generic,
                            caller = parent.frame(), chain = class(x)[-1L]) {
    if (!isFALSE(incomparables) || !(isTRUE(fromLast) || isFALSE(fromLast)) ||
        !.dibble_next_method_base(chain, generic, caller)) {
        return(NULL)
    }
    columns <- .plain_data_columns(x)
    values <- vector("list", length(columns))
    checked <- character()
    # Read every column first: base reads every cell, so an invalid value
    # in a later column must still reach base.
    for (index in seq_along(columns)) {
        column <- columns[[index]]
        if (is.object(column)) {
            classes <- paste(class(column), collapse = "\r")
            if (!classes %in% checked) {
                if (!.dibble_cell_methods_owned(column)) return(NULL)
                checked <- c(checked, classes)
            }
        }
        found <- .dibble_row_values(column)
        if (is.null(found)) return(NULL)
        values[[index]] <- found
    }
    rows <- length(values[[1L]])
    # The combined key below is exact while rows^2 fits in 53 bits.
    if (rows > 94906265 || any(lengths(values) != rows)) return(NULL)
    first <- seq_len(rows)
    active <- NULL
    key <- NULL
    for (found in values) {
        if (!is.null(active)) found <- found[active]
        ids <- match(found, found)
        key <- if (is.null(key)) ids else {
            combined <- (key - 1) * length(ids) + ids
            match(combined, combined)
        }
        # A row alone in its group stays unique whatever later columns
        # hold, so only rows that still share a group are compared again.
        shared <- tabulate(key, length(key))[key] > 1L
        if (!all(shared)) {
            if (!any(shared)) return(first)
            active <- if (is.null(active)) which(shared) else active[shared]
            key <- key[shared]
            key <- match(key, key)
        }
    }
    if (is.null(active)) return(key)
    first[active] <- active[key]
    first
}

# The values whose equality decides cell equality, or NULL.
.dibble_row_values <- function(column) {
    if (!is.null(attr(column, "dim", exact = TRUE))) return(NULL)
    if (!is.object(column)) {
        if (!typeof(column) %in% c("logical", "integer", "double", "character") ||
            (is.character(column) && "bytes" %in% Encoding(column))) {
            return(NULL)
        }
        return(column)
    }
    # Restoring a cell warns about any other attribute, which the key would
    # not.
    known <- c("names", "class", .dta_variable_attribute_names)
    if (!all(names(attributes(column)) %in% known)) return(NULL)
    classes <- class(column)
    if (identical(classes, c("dta_string", "vctrs_vctr", "character"))) {
        values <- .dibble_row_bare(column)
        return(if (!"bytes" %in% Encoding(values)) values)
    }
    storage <- .declared_dta_storage(column)
    if (!identical(typeof(column), "double") || !is.character(storage) ||
        length(storage) != 1L || !storage %in% .dta_storage) {
        return(NULL)
    }
    plain <- .dta_storage_class(storage)
    if (!identical(classes, plain) &&
        !identical(classes, append(plain, "haven_labelled", after = 2L))) {
        return(NULL)
    }
    # Values that fit their storage exactly come back from the constructor
    # unchanged. Compact backing read from a file can still hold values the
    # constructor rejects, such as a byte of -128.
    values <- .dibble_row_bare(column)
    kind <- match(storage, .dta_storage) - 1L
    if (.Call(C_dtatools_numeric_values_fit, values, kind)) return(values)
    column <- tryCatch(
        .construct_dta_numeric(values, NULL, storage),
        error = function(condition) NULL
    )
    if (is.null(column)) NULL else .dibble_row_bare(column)
}

# Whether `NextMethod()` would reach base's data frame method, which the
# key reproduces, rather than a method another class brings.
.dibble_next_method_base <- function(chain, generic, caller) {
    expected <- .dibble_s3_method(
        generic, "data.frame", .BaseNamespaceEnv, .BaseNamespaceEnv
    )
    for (name in chain) {
        method <- .dibble_s3_method(generic, name, caller, .BaseNamespaceEnv)
        if (!is.null(method)) return(identical(method, expected))
    }
    FALSE
}

# The method S3 dispatch finds for a call from `caller` to a generic that
# `home` defines, searched in R's order: the frames from `caller` to its top
# environment, the methods registered in `home`, then the frames above the
# top environment, with the base environment after the global one.
# `utils::getS3method()` costs more than base's whole comparison of a small
# table.
.dibble_s3_method <- function(generic, class, caller, home) {
    name <- paste0(generic, ".", class)
    top <- topenv(caller)
    method <- .dibble_s3_frames(name, caller, top)
    if (is.null(method)) {
        method <- get0(
            name, envir = home[[".__S3MethodsTable__."]], inherits = FALSE
        )
    }
    if (is.null(method)) {
        above <- if (identical(top, globalenv())) baseenv() else parent.env(top)
        method <- .dibble_s3_frames(name, above, baseenv())
    }
    method
}

# The first function named `name` in the frames from `frame` to `last`.
.dibble_s3_frames <- function(name, frame, last) {
    while (!identical(frame, emptyenv())) {
        method <- get0(name, envir = frame, mode = "function", inherits = FALSE)
        if (!is.null(method) || identical(frame, last) ||
            identical(frame, baseenv())) {
            return(method)
        }
        frame <- if (identical(frame, globalenv())) baseenv() else parent.env(frame)
    }
    NULL
}

# A view keeps compact backing compact.
.dibble_row_bare <- function(column) {
    value <- .metadata_view(column)
    attributes(value) <- NULL
    value
}

# Whether base's comparison reaches only the methods above for this class:
# vctrs' `[[`, which restores numerics through dtatools' `vec_restore()`,
# or dtatools' string `[[`, and no `dim` or `length` method. Base calls
# these from its own closures, so the search starts in the base namespace.
.dibble_cell_methods_owned <- function(column) {
    classes <- class(column)
    string <- identical(classes[[1L]], "dta_string")
    vctrs <- asNamespace("vctrs")
    expected <- if (string) {
        list(dta_string = `[[.dta_string`)
    } else {
        list(vctrs_vctr = get0("[[.vctrs_vctr", envir = vctrs, inherits = FALSE))
    }
    for (name in classes) {
        method <- .dibble_s3_method(
            "[[", name, .BaseNamespaceEnv, .BaseNamespaceEnv
        )
        if (!identical(method, expected[[name]])) return(FALSE)
        # dtatools' string `[[` does not call the next method.
        if (string) break
    }
    for (generic in c("dim", "length")) {
        for (name in classes) {
            if (!is.null(.dibble_s3_method(
                generic, name, .BaseNamespaceEnv, .BaseNamespaceEnv
            ))) {
                return(FALSE)
            }
        }
    }
    string || identical(
        .dibble_s3_method("vec_restore", "dta_numeric", vctrs, vctrs),
        vec_restore.dta_numeric
    )
}
