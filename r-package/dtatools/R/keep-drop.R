#' Keep or drop variables by reference
#'
#' `keep_vars()` retains selected columns and `drop_vars()` removes selected
#' columns. Both functions mutate the supplied data frame or tibble by
#' reference and return it invisibly. Other bindings to the same dataset see
#' the structural change. Use `copy_data()` first when isolation is required.
#'
#' Selections accept bare names, `first:last` ranges, `c()`, and
#' `tidyselect::all_of()` for a character vector. Every requested name must
#' exist. Permissive or custom selection helpers are rejected so that absent
#' names cannot be discarded before validation. An empty selection is an
#' error. `keep_vars()` treats the selection as a Stata varlist: it preserves
#' the surviving columns' original relative order rather than reordering them
#' to match the selection expression.
#'
#' Physical columns and columns created by `gen()` share one visible namespace.
#' Callers do not need to inspect or change dtatools reference state. Surviving
#' columns keep their vectors unchanged, including Stata storage declarations,
#' tagged missing values, variable labels, and value-label tables.
#' A `data.table` restored by `readRDS()` or `unserialize()` must first have its
#' by-reference column capacity restored with `data.table::setalloccol()`.
#' `keep_vars()` and `drop_vars()` reject a non-resizable `data.table` before
#' mutation because R cannot shrink that object itself by reference.
#'
#' @param data An ungrouped data frame or tibble to mutate.
#' @param ... Column names, name ranges, `c()`, or
#'   `tidyselect::all_of()` character vectors to keep or drop.
#' @return `data`, invisibly.
#' @examples
#' survey <- data.frame(id = 1:2, age = c(20, 30), temporary = 0)
#' gen(survey, age_next_year, age + 1)
#' drop_vars(survey, temporary)
#' keep_vars(survey, age_next_year, id)
#' names(survey)
#' @export
keep_vars <- function(data, ...) {
    dots <- rlang::enquos(...)
    .select_vars_by_reference(data, dots, keep = TRUE)
}

#' @rdname keep_vars
#' @export
drop_vars <- function(data, ...) {
    dots <- rlang::enquos(...)
    .select_vars_by_reference(data, dots, keep = FALSE)
}

#' Reorder variables by reference
#'
#' `order_vars()` moves the selected columns to the front of the table in
#' the order they were selected, as Stata's `order` does. Columns that were
#' not selected follow, keeping their existing relative order. Selecting
#' every column therefore permutes the whole table. The data frame or
#' tibble is mutated by reference and returned invisibly, so other bindings
#' to the same dataset see the new order.
#'
#' Selections follow the same rules as `keep_vars()`, and the column
#' vectors themselves are untouched: storage declarations, tagged missing
#' values, labels, and compact representations all survive the move.
#' Columns created by `gen()` may be reordered alongside physical ones.
#'
#' @param data An ungrouped data frame or tibble to mutate.
#' @param ... Column names, name ranges, `c()`, or
#'   `tidyselect::all_of()` character vectors to move to the front.
#' @return `data`, invisibly.
#' @examples
#' survey <- data.frame(id = 1:2, age = c(20, 30), region = c("n", "s"))
#' order_vars(survey, region)
#' names(survey)
#' @export
order_vars <- function(data, ...) {
    dots <- rlang::enquos(...)
    .order_vars_by_reference(data, dots)
}

#' Rename variables by reference
#'
#' `rename_vars()` renames columns in place, as Stata's `rename` does.
#' Each argument names the replacement on the left and the existing column
#' on the right, matching `dplyr::rename()`. The data frame or tibble is
#' mutated by reference and returned invisibly, so other bindings to the
#' same dataset see the new names. Column positions and vectors are
#' untouched, including columns created by `gen()`.
#'
#' Every right-hand side must name an existing column. A replacement name
#' may not collide with a column that survives the rename, and the same
#' column may not be renamed twice.
#'
#' Pass `.names` instead of `...` to replace every name at once, as
#' `names<-` would, but by reference. The vector must give one name per
#' visible column, in order.
#'
#' @param data An ungrouped data frame or tibble to mutate.
#' @param ... Replacements of the form `new_name = old_name`, where
#'   `old_name` is a bare name or a string.
#' @param .names A character vector of replacement names, one per column,
#'   used instead of `...`.
#' @return `data`, invisibly.
#' @examples
#' survey <- data.frame(id = 1:2, v1 = c(20, 30))
#' rename_vars(survey, age_years = v1)
#' names(survey)
#' rename_vars(survey, .names = toupper(names(survey)))
#' names(survey)
#' @export
rename_vars <- function(data, ..., .names = NULL) {
    dots <- rlang::enquos(...)
    if (!is.null(.names)) {
        if (length(dots) > 0L) {
            stop(
                "supply either `...` or `.names`, not both", call. = FALSE
            )
        }
        return(.rename_all_vars_by_reference(data, .names))
    }
    .rename_vars_by_reference(data, dots)
}

.rename_all_vars_by_reference <- function(data, new_names) {
    .reject_data_table_subclass(data)
    original <- .as_mutation_data(data)
    columns <- if (is.null(original$state)) {
        original$columns
    } else {
        .data_columns(data)
    }
    if (!is.character(new_names) || anyNA(new_names)) {
        stop("`.names` must be a character vector", call. = FALSE)
    }
    if (length(new_names) != length(columns)) {
        stop(
            sprintf(
                "`.names` must give %d names, not %d",
                length(columns), length(new_names)
            ),
            call. = FALSE
        )
    }
    if (anyDuplicated(new_names) > 0L) {
        stop("`.names` must be distinct", call. = FALSE)
    }
    source_names <- names(columns)
    if (identical(new_names, source_names)) return(invisible(data))
    names(columns) <- new_names
    .install_column_selection(data, original, columns, source_names)
}

.rename_vars_by_reference <- function(data, replacements) {
    .reject_data_table_subclass(data)
    if (length(replacements) == 0L) {
        stop("`...` must name at least one variable", call. = FALSE)
    }
    new_names <- names(replacements)
    if (is.null(new_names) || any(!nzchar(new_names))) {
        stop(
            "every replacement must be named, as `new_name = old_name`",
            call. = FALSE
        )
    }
    original <- .as_mutation_data(data)
    columns <- if (is.null(original$state)) {
        original$columns
    } else {
        .data_columns(data)
    }
    current_names <- names(columns)
    locations <- vapply(
        replacements,
        function(quosure) .resolve_selections(list(quosure), current_names),
        integer(1)
    )
    if (anyDuplicated(locations) > 0L) {
        stop("each variable may be renamed only once", call. = FALSE)
    }
    if (anyDuplicated(new_names) > 0L) {
        stop("replacement names must be distinct", call. = FALSE)
    }
    final_names <- current_names
    final_names[locations] <- new_names
    if (anyDuplicated(final_names) > 0L) {
        stop(
            "a replacement name collides with a surviving variable",
            call. = FALSE
        )
    }
    if (identical(final_names, current_names)) return(invisible(data))
    names(columns) <- final_names
    .install_column_selection(data, original, columns, current_names)
}

.selection_call_is <- function(
    head, name, namespace, allow_unqualified = TRUE
) {
    if (is.symbol(head)) {
        return(
            allow_unqualified && identical(as.character(head), name)
        )
    }
    is.call(head) && length(head) == 3L &&
        identical(head[[1L]], quote(`::`)) &&
        is.symbol(head[[2L]]) &&
        identical(as.character(head[[2L]]), namespace) &&
        is.symbol(head[[3L]]) &&
        identical(as.character(head[[3L]]), name)
}

.selection_error <- function() {
    stop(
        "Selections must use column names, name ranges, `c()`, or `tidyselect::all_of()`; permissive and custom helpers are not supported",
        call. = FALSE
    )
}

.selection_range_endpoint <- function(expression) {
    if (is.symbol(expression)) return(as.character(expression))
    if (is.character(expression) && length(expression) == 1L &&
        !is.na(expression)) {
        return(expression)
    }
    .selection_error()
}

.selection_call_is_all_of <- function(head, environment) {
    if (.selection_call_is(
        head, "all_of", "tidyselect", allow_unqualified = FALSE
    )) {
        return(TRUE)
    }
    is.symbol(head) && identical(as.character(head), "all_of") &&
        identical(
            get0("all_of", envir = environment, inherits = TRUE),
            tidyselect::all_of
        )
}

.selection_range_endpoints <- function(expression) {
    if (!is.call(expression)) return(character())
    head <- expression[[1L]]
    if (.selection_call_is(head, ":", "base") && length(expression) == 3L) {
        return(vapply(
            as.list(expression)[-1L],
            .selection_range_endpoint,
            character(1)
        ))
    }
    if (!.selection_call_is(head, "c", "base")) return(character())
    unlist(lapply(
        as.list(expression)[-1L],
        .selection_range_endpoints
    ), use.names = FALSE)
}

.resolve_selection_expression <- function(
    expression, environment, names, range_cursor
) {
    if (is.symbol(expression)) return(as.character(expression))
    if (is.character(expression)) return(expression)
    if (!is.call(expression)) .selection_error()

    head <- expression[[1L]]
    if (.selection_call_is_all_of(head, environment)) {
        if (length(expression) != 2L) {
            stop("`all_of()` must receive one character vector", call. = FALSE)
        }
        value <- tryCatch(
            rlang::eval_bare(expression[[2L]], environment),
            error = function(error) {
                stop(
                    "Could not evaluate the `all_of()` character vector: ",
                    conditionMessage(error),
                    call. = FALSE
                )
            }
        )
        if (!is.character(value)) {
            stop("`all_of()` must receive a character vector", call. = FALSE)
        }
        return(value)
    }
    if (.selection_call_is(head, "c", "base")) {
        arguments <- as.list(expression)[-1L]
        if (length(arguments) == 0L) return(character())
        return(unlist(lapply(
            arguments,
            .resolve_selection_expression,
            environment = environment,
            names = names,
            range_cursor = range_cursor
        ), use.names = FALSE))
    }
    if (.selection_call_is(head, ":", "base") && length(expression) == 3L) {
        first <- range_cursor$index + 1L
        locations <- range_cursor$locations[first:(first + 1L)]
        range_cursor$index <- first + 1L
        return(names[seq(locations[[1L]], locations[[2L]])])
    }
    .selection_error()
}

.resolve_selections <- function(selections, names) {
    range_endpoints <- unlist(lapply(
        selections,
        function(selection) {
            .selection_range_endpoints(rlang::quo_get_expr(selection))
        }
    ), use.names = FALSE)
    range_cursor <- new.env(parent = emptyenv())
    range_cursor$index <- 0L
    range_cursor$locations <- integer()
    if (length(range_endpoints) > 0L) {
        locations <- match(range_endpoints, names)
        if (anyNA(locations)) {
            absent <- range_endpoints[is.na(locations)][[1L]]
            stop(sprintf("Column `%s` does not exist", absent), call. = FALSE)
        }
        range_cursor$locations <- locations
    }
    resolved <- vector("list", length(selections))
    index <- 0L
    for (selection in selections) {
        index <- index + 1L
        resolved[[index]] <- .resolve_selection_expression(
            rlang::quo_get_expr(selection),
            rlang::quo_get_env(selection),
            names,
            range_cursor
        )
    }
    requested <- unlist(resolved, use.names = FALSE)
    if (length(requested) == 0L) {
        stop("Select at least one variable", call. = FALSE)
    }
    locations <- match(requested, names)
    if (anyNA(locations)) {
        absent <- requested[is.na(locations)][[1L]]
        stop(sprintf("Column `%s` does not exist", absent), call. = FALSE)
    }
    unique(unname(locations))
}

.select_vars_by_reference <- function(data, selections, keep) {
    .reject_data_table_subclass(data)
    original <- .as_mutation_data(data)
    columns <- if (is.null(original$state)) {
        original$columns
    } else {
        .data_columns(data)
    }
    selected_locations <- .resolve_selections(selections, names(columns))
    if (keep && length(selected_locations) == length(columns)) {
        return(invisible(data))
    }
    locations <- seq_along(columns)
    retained <- if (keep) {
        locations %in% selected_locations
    } else {
        !locations %in% selected_locations
    }
    .install_column_selection(data, original, columns[locations[retained]])
}

.order_vars_by_reference <- function(data, selections) {
    .reject_data_table_subclass(data)
    original <- .as_mutation_data(data)
    columns <- if (is.null(original$state)) {
        original$columns
    } else {
        .data_columns(data)
    }
    moved_locations <- .resolve_selections(selections, names(columns))
    locations <- seq_along(columns)
    ordered_locations <- c(
        moved_locations, locations[!locations %in% moved_locations]
    )
    if (identical(ordered_locations, locations)) return(invisible(data))
    .install_column_selection(data, original, columns[ordered_locations])
}

# Commits `retained_columns` as the table's complete column set, by
# reference. The caller has already resolved which columns survive and
# in which order; this installs them, materializing when the physical
# object can be resized and falling back to a structural reference
# state when it cannot.
.install_column_selection <- function(
    data, original, retained_columns, source_names = names(retained_columns)
) {
    state <- original$state
    dibble_input <- is_dibble(data)
    source_classes <- if (is.null(state)) class(data) else state$classes
    can_materialize <- .Call(
        C_dtatools_can_select_data_columns,
        data,
        as.double(length(retained_columns))
    )
    final_state <- if (can_materialize) {
        NULL
    } else {
        .new_structural_reference_state(
            retained_columns,
            original$nrow,
            source_classes
        )
    }
    reference_classes <- unique(c("dtatools_ref_data", source_classes))

    select <- function() .Call(
        C_dtatools_select_data_columns, data, unname(retained_columns),
        names(retained_columns), final_state, source_classes, reference_classes
    )
    if (.ordinary_data_table(data)) {
        # The native selection clears `sorted` and `index`, so the key
        # and indices are reinstated afterwards. They are recorded
        # under the column names the table had on entry, which a
        # rename replaces, so translate them to the surviving names.
        renamed <- names(retained_columns)
        # The selection renames by reference and may write through the
        # very vector `source_names` points at, so the translation is
        # resolved into fresh vectors before `select()` runs.
        names(renamed) <- as.character(source_names)
        key_columns <- data.table::key(data)
        new_key <- if (length(key_columns) > 0L &&
            all(key_columns %in% names(renamed))) {
            unname(renamed[key_columns])
        } else {
            NULL
        }
        the_indexes <- data.table::indices(data, vectors = TRUE)
        new_indexes <- list()
        for (my_columns in the_indexes) {
            if (all(my_columns %in% names(renamed))) {
                new_indexes[[length(new_indexes) + 1L]] <-
                    unname(renamed[my_columns])
            }
        }
        suspendInterrupts({
            select()
            if (!is.null(new_key)) data.table::setkeyv(data, new_key)
            for (my_columns in new_indexes) {
                data.table::setindexv(data, my_columns)
            }
        })
    } else {
        select()
    }
    # A dibble whose list could be resized has lost its mark to the
    # materialization; it is a dibble still, over the new column set.
    if (dibble_input && is.null(.reference_state(data))) {
        .mark_reference_data(data, .new_reference_state(data))
    }
    invisible(data)
}
