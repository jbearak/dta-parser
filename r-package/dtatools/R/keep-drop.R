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
    retained_locations <- locations[retained]

    retained_columns <- columns[retained_locations]

    state <- original$state
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
        retained_names <- names(retained_columns)
        key_columns <- data.table::key(data)
        preserve_key <- length(key_columns) > 0L &&
            all(key_columns %in% retained_names)
        index_columns <- data.table::indices(data, vectors = TRUE)
        preserve_indexes <- vapply(
            index_columns,
            function(columns) all(columns %in% retained_names),
            logical(1)
        )
        suspendInterrupts({
            select()
            if (preserve_key) data.table::setkeyv(data, key_columns)
            for (columns in index_columns[preserve_indexes]) {
                data.table::setindexv(data, columns)
            }
        })
    } else {
        select()
    }
    invisible(data)
}
