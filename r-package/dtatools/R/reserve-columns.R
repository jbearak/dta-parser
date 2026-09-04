#' Reserve spare column slots
#'
#' `reserve_columns()` shallow-copies a table and reserves `n` spare column
#' pointer slots without copying its column payloads. Assign the returned
#' table. The container and column storage are preserved. Legacy tables with
#' columns stored outside their physical list are rebuilt into one complete
#' list, and serialized dibbles get fresh current-object bookkeeping.
#'
#' Constructors and readers reserve 5,000 spare slots by default. Set
#' `options(dtatools.alloccol = 5000L)` to change this default. Structural
#' operations keep the outer object while capacity remains. When preparation
#' or reallocation is needed, they warn, shallow-copy the table, and rebind
#' the mutation target. Other aliases retain the old complete table.
#'
#' Automatic rebinding supports a symbol, simple `$` or `[[` extraction,
#' and `get()` or `get0()`. Otherwise assign the returned result yourself.
#' Rebinding a function parameter changes only that local parameter: return
#' and assign the rebuilt table in the caller when capacity changes.
#'
#' Base R serialization discards spare capacity. After `readRDS()` or
#' `unserialize()`, assign `data <- reserve_columns(data)` before relying on
#' dibble replacement aliases. `read_dta()` and `read_arrow()` return
#' prepared tables.
#'
#' @param data A dibble, tibble, base data frame, or data table.
#' @param n A finite, nonnegative whole number of spare column-pointer slots.
#' @return A rebuilt table with the same container and `n` spare slots.
#' @export
#' @examples
#' data <- reserve_columns(data.frame(x = 1:3))
#' gen(data, y = x + 1)
reserve_columns <- function(data, n = getOption("dtatools.alloccol", 5000L)) {
    .reject_data_table_subclass(data)
    .as_mutation_data(data, allow_grouped = TRUE)
    n <- .validate_alloccol(n, length(data))
    dibble <- is_dibble(data)
    marked <- !is.null(.reference_state(data))
    snapshot <- .reference_snapshot(data)
    if (.ordinary_data_table(data)) {
        # Remove runtime self-reference on a shallow attribute copy. setalloccol
        # rebuilds both the list and its resizable names, retaining payloads.
        snapshot <- .Call(C_dtatools_metadata_copy, snapshot)
        attr(snapshot, ".internal.selfref") <- NULL
        return(data.table::setalloccol(snapshot, n = n))
    }
    result <- .reserve_column_capacity(snapshot, n)
    if (marked) {
        result <- .mark_reference_data(
            result, .new_reference_state(result, dibble = dibble)
        )
    }
    result
}

.validate_alloccol <- function(n, columns = 0) {
    if (!is.numeric(n) || length(n) != 1L || is.na(n) ||
        !is.finite(n) || n < 0 || n != floor(n) ||
        n > 2^52 - 1 - columns) {
        stop("`n` (or `dtatools.alloccol`) must be a finite, nonnegative whole number within R vector limits", call. = FALSE)
    }
    as.double(n)
}

.has_column_overlay <- function(data) {
    state <- .reference_state(data)
    !is.null(state) &&
        (isTRUE(state$physical_overlay) || state$generated_count > 0L)
}

.prepare_column_operation <- function(data, columns) {
    if (!.has_column_overlay(data) && isTRUE(.Call(
        C_dtatools_can_select_data_columns, data, as.double(columns)
    ))) return(data)
    spare <- .validate_alloccol(getOption("dtatools.alloccol", 5000L), columns)
    warning(
        "Column reallocation may separate the mutation target from aliases; assign the returned table when used through a function parameter or unsupported target.",
        call. = FALSE
    )
    reserve_columns(data, n = max(0, columns - length(data)) + spare)
}

# Return and rebind only after a successful operation. Simple extraction
# targets deliberately exclude calls in indices and nested replacement
# expressions, which might rerun user code while writing the result.
.return_mutation <- function(before, result, target, env) {
    if (identical(rlang::obj_address(before), rlang::obj_address(result))) {
        return(invisible(result))
    }
    if (is.symbol(target)) {
        assign(as.character(target), result, envir = env)
    } else if (is.call(target) && is.symbol(target[[1L]])) {
        head <- as.character(target[[1L]])
        if (head %in% c("$", "[[") && length(target) == 3L &&
            is.symbol(target[[2L]]) &&
            (is.symbol(target[[3L]]) || is.atomic(target[[3L]]))) {
            eval(as.call(list(quote(`<-`), target, result)), envir = env)
        } else if (head %in% c("get", "get0")) {
            fun <- get(head, envir = baseenv())
            call <- match.call(fun, target)
            name <- eval(call$x, env)
            where <- if (!is.null(call$envir)) {
                eval(call$envir, env)
            } else if (!is.null(call$pos)) {
                pos <- eval(call$pos, env)
                if (identical(pos, -1L) || identical(pos, -1)) env else as.environment(pos)
            } else env
            inherits <- if (is.null(call$inherits)) TRUE else eval(call$inherits, env)
            if (is.character(name) && length(name) == 1L && is.environment(where)) {
                if (isTRUE(inherits)) {
                    while (!exists(name, envir = where, inherits = FALSE) &&
                           !identical(where, emptyenv())) where <- parent.env(where)
                }
                if (!identical(where, emptyenv())) assign(name, result, envir = where)
            }
        }
    }
    invisible(result)
}
