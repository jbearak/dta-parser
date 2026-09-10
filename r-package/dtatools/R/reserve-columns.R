#' Reserve spare column slots
#'
#' See [mutation-containers] for supported classes, grouping and conversion.
#' `reserve_columns()` returns an isolated table with `n` spare column
#' pointer slots. Compact columns and owned ordinary doubles share backing
#' until a write needs isolation. Other ordinary columns are copied. Assign the returned
#' table. The container and column storage are preserved. Legacy tables with
#' columns stored outside their physical list are rebuilt into one complete
#' list, and serialized dibbles get fresh current-object bookkeeping.
#'
#' Package-controlled allocation reserves 1,024 spare slots by default.
#' Set `options(dtatools.alloccol = 2048L)` to request a different default.
#' Paths that delegate allocation to data.table use its own allocation option.
#' By default, [gen()], [egen()] and dibble `:=` automatically call this
#' preparation when adding columns needs more room. They warn when rebuilding,
#' and reserve all requested additions plus the configured spare slots. The
#' updated result must be returned from a function and assigned by its caller;
#' aliases keep the old table after growth. Set `options(dtatools.auto_grow = FALSE)`
#' to require assigned preparation before values, selection or sorting run.
#' Dropping columns and other nongrowth helpers keep their strict preparation
#' requirements regardless of the automatic-growth option.
#'
#' Adding columns consumes spare slots. Dropping columns also requires a
#' resizable allocation. `keep_vars()` and `drop_vars()` validate their column
#' selections first, then check capacity before a commit. A validated keep-all
#' selection does not resize the table. Renaming, ordering,
#' and overwriting existing columns and editing metadata need no spare slots.
#' Column-name edits on a data.table also need its valid self-reference;
#' assign preparation after copying or serialization if that check fails.
#' Inspect [column_capacity()] and [can_add_columns()] before growth.
#'
#' Base R serialization discards spare capacity. After `readRDS()` or
#' `unserialize()`, assign `data <- reserve_columns(data)` before relying on
#' explicit structural mutation through existing aliases. Automatic growth
#' prepares a separate table and therefore does not preserve those aliases. `read_dta()` and `read_arrow()` return
#' prepared tables.
#'
#' @param data A dibble, tibble, base data frame, or data table. data.table
#'   support requires data.table 1.18.2.1 or newer.
#' @param n A finite, nonnegative whole number of spare column-pointer slots.
#' @return A rebuilt table with the same container and `n` spare slots.
#' @export
#' @examples
#' data <- reserve_columns(data.frame(x = 1:3))
#' gen(data, y = x + 1)
reserve_columns <- function(data, n = getOption("dtatools.alloccol", 1024L)) {
    .as_mutation_data(data, allow_grouped = TRUE)
    n <- .validate_alloccol(n, length(data))
    dibble <- is_dibble(data)
    marked <- !is.null(.reference_state(data))
    snapshot <- .isolate_shared_columns(.reference_snapshot(data), NULL)
    if (.ordinary_data_table(data)) {
        # Remove runtime self-reference on a shallow attribute copy. setalloccol
        # rebuilds both the list and its resizable names, retaining payloads.
        snapshot <- .Call(C_dtatools_metadata_copy, snapshot)
        attr(snapshot, ".internal.selfref") <- NULL
        return(data.table::setalloccol(snapshot, n = n))
    }
    result <- .reserve_column_capacity(snapshot, n)
    if (marked || dibble) {
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

.column_operation_ready <- function(data, columns, names_change = TRUE) {
    if (.ordinary_data_table(data)) .require_data_table()
    !.has_column_overlay(data) &&
        (!(names_change && .ordinary_data_table(data)) || .data_table_reference_ready(data)) &&
        (columns == length(data) || .column_resize_ready(data)) && isTRUE(.Call(
        C_dtatools_can_select_data_columns, data, as.double(columns)
    ))
}

.prepare_column_operation <- function(data, columns, names_change = TRUE) {
    if (.column_operation_ready(data, columns, names_change)) return(invisible(data))
    extra <- max(0, columns - length(data))
    stop(sprintf(
        paste0("The supplied table needs column preparation for this operation. ",
               "Assign `data <- reserve_columns(data, n = %s)` before calling ",
               "this helper or passing the table to a function; `n` is the ",
               "number of extra columns to allow."),
        format(extra, scientific = FALSE, trim = TRUE)
    ), call. = FALSE)
}

.mutation_auto_grow <- function() {
    value <- getOption("dtatools.auto_grow", TRUE)
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        stop("`dtatools.auto_grow` must be `TRUE` or `FALSE`", call. = FALSE)
    }
    value
}

# Growth has a separate policy: dropping or renaming does not silently repair
# a supplied table. Reserve before any value/selection/sorting callback runs.
.prepare_column_growth <- function(data, columns, auto_grow) {
    if (.column_operation_ready(data, columns)) return(data)
    if (!auto_grow || columns <= length(data)) {
        return(.prepare_column_operation(data, columns))
    }
    spare <- .validate_alloccol(getOption("dtatools.alloccol", 1024L), columns)
    result <- reserve_columns(data, n = columns - length(data) + spare)
    warning(paste0(
        "Column reallocation created an isolated table; existing aliases keep the old table. ",
        "Return the updated table from functions and assign it in the caller."),
        call. = FALSE)
    result
}

.mutation_binding_environment <- function(name, env, inherits = TRUE) {
    while (!identical(env, emptyenv())) {
        if (exists(name, env, inherits = FALSE)) return(env)
        if (!inherits) break
        env <- parent.env(env)
    }
    NULL
}

.mutation_plain_binding <- function(name, env) {
    !is.null(env) && exists(name, env, inherits = FALSE) &&
        !bindingIsActive(name, env) && !bindingIsLocked(name, env) &&
        !rlang::env_binding_are_lazy(env, name)[[1L]]
}

# gen/egen can capture supported targets instead of forcing their data promise.
# Primitive `[` already forced x: only literal selectors can be recovered there.
.capture_mutation_binding <- function(target, env, value) {
    forced <- !missing(value)
    if (!is.call(target) || !is.symbol(target[[1L]])) return(NULL)
    head <- as.character(target[[1L]])
    if (!head %in% c("$", "[[", "get", "get0")) return(NULL)
    fun_env <- .mutation_binding_environment(head, env)
    if (is.null(fun_env) || bindingIsActive(head, fun_env) ||
        rlang::env_binding_are_lazy(fun_env, head)[[1L]] ||
        !identical(get(head, fun_env, inherits = FALSE), get(head, baseenv()))) return(NULL)
    if (head %in% c("$", "[[")) {
        if (length(target) != 3L || !is.symbol(target[[2L]])) return(NULL)
        container_name <- as.character(target[[2L]])
        container_env <- .mutation_binding_environment(container_name, env)
        if (is.null(container_env) || bindingIsActive(container_name, container_env) ||
            rlang::env_binding_are_lazy(container_env, container_name)[[1L]]) return(NULL)
        if (head == "$" && !is.symbol(target[[3L]]) && !is.character(target[[3L]])) return(NULL)
        if (forced && head == "[[" && !is.atomic(target[[3L]])) return(NULL)
        container <- get(container_name, container_env, inherits = FALSE)
        if (is.object(container) || !(is.list(container) || is.environment(container))) return(NULL)
        key <- if (head == "$") as.character(target[[3L]]) else eval(target[[3L]], env)
        if (forced) {
            if (length(key) != 1L || !typeof(key) %in% c("character", "integer", "double") || is.na(key)) return(NULL)
        } else {
            value <- if (head == "$") .subset2(container, key, exact = FALSE) else .subset2(container, key)
        }
        # Ambiguous/recursive/partial indices can still return a result but
        # cannot name one stable destination for automatic publication.
        location <- if (is.character(key) && length(key) == 1L) match(key, names(container)) else key
        if (is.environment(container)) location <- key
        eligible <- length(location) == 1L && !is.na(location) &&
            (is.character(location) || (is.numeric(location) && location == floor(location) && location > 0 && location <= length(container)))
        if (is.environment(container)) eligible <- is.character(location) && length(location) == 1L &&
            .mutation_plain_binding(location, container)
        return(list(kind = "extraction", data = value, name = container_name,
            env = env, binding_env = container_env, original_container = container,
            key = location, publish = eligible))
    }
    fun <- get(head, baseenv())
    call <- match.call(fun, target)
    args <- as.list(call)[-1L]
    if (!"x" %in% names(args) || any(!names(args) %in% c("x", "envir", "inherits"))) return(NULL)
    if (forced && (!is.character(args$x) || length(args$x) != 1L ||
        (!is.null(args$inherits) && !is.logical(args$inherits)))) return(NULL)
    name <- eval(args$x, env)
    where <- if (is.null(args$envir)) env else {
        if (forced && !is.symbol(args$envir)) return(NULL)
        if (forced) {
            e <- .mutation_binding_environment(as.character(args$envir), env)
            if (is.null(e) || bindingIsActive(as.character(args$envir), e) ||
                rlang::env_binding_are_lazy(e, as.character(args$envir))[[1L]]) return(NULL)
        }
        eval(args$envir, env)
    }
    inherit <- if (is.null(args$inherits)) TRUE else eval(args$inherits, env)
    destination <- .mutation_binding_environment(name, where, inherit)
    stable <- !is.null(destination) && !bindingIsActive(name, destination)
    if (!forced) value <- fun(name, envir = where, inherits = inherit)
    list(kind = "get", data = value, name = name, env = destination,
         publish = stable && .mutation_plain_binding(name, destination))
}

.return_mutation <- function(before, result, target, env) {
    .rebind_mutation(before, result, target, env)
    invisible(result)
}

.rebind_mutation <- function(before, result, target, env) {
    if (.same_mutation_object(before, result)) return(target)
    changed <- function() warning(
        "Mutation target changed or cannot be rebound safely; assign the returned table.",
        call. = FALSE)
    if (is.symbol(target)) {
        name <- as.character(target)
        current_env <- .mutation_binding_environment(name, env)
        if (!.mutation_plain_binding(name, current_env) ||
            (environmentIsLocked(env) && !exists(name, env, inherits = FALSE)) ||
            (exists(name, env, inherits = FALSE) && bindingIsLocked(name, env)) ||
            !.same_mutation_object(get(name, current_env, inherits = FALSE), before)) {
            changed()
        } else assign(name, result, envir = env)
    } else if (is.list(target) && identical(target$kind, "get")) {
        if (!isTRUE(target$publish) || !.mutation_plain_binding(target$name, target$env) ||
            !.same_mutation_object(get(target$name, target$env, inherits = FALSE), before)) {
            changed()
        } else assign(target$name, result, envir = target$env)
    } else if (is.list(target) && identical(target$kind, "extraction")) {
        current_env <- .mutation_binding_environment(target$name, target$env)
        if (!isTRUE(target$publish) || !identical(current_env, target$binding_env) ||
            !.mutation_plain_binding(target$name, current_env) ||
            (environmentIsLocked(target$env) && !exists(target$name, target$env, inherits = FALSE))) { changed(); return(target) }
        container <- get(target$name, current_env, inherits = FALSE)
        if (!.same_mutation_object(container, target$original_container) ||
            (is.environment(container) && !.mutation_plain_binding(target$key, container)) ||
            !.same_mutation_object(.subset2(container, target$key), before)) { changed(); return(target) }
        container[[target$key]] <- result
        if (!is.environment(container)) assign(target$name, container, envir = target$env)
        target$original_container <- container
        target$binding_env <- .mutation_binding_environment(target$name, target$env)
    }
    target
}

.same_mutation_object <- function(x, y) {
    identical(rlang::obj_address(x), rlang::obj_address(y))
}

#' Inspect physical column capacity
#'
#' `column_capacity()` reports the total number of columns the supplied table
#' can hold in its current resizable allocation. It returns `NA_real_` when
#' that allocation is absent, including after base R serialization. For a
#' data.table both its list and its names must have resizable capacity and
#' its self-reference must be valid. A zero-column table reserved with
#' `n = 0` has no resizable allocation and also reports `NA_real_`.
#'
#' `can_add_columns(data, n)` reports whether an explicit helper can append
#' `n` columns without rebuilding the supplied table. A prepared table with
#' zero spare slots accepts `n = 0` but rejects `n = 1`. An ordinary unprepared
#' table also accepts `n = 0`, because no additions are requested. This does
#' not promise readiness for every structural helper: column-name edits on
#' a data.table also need its valid self-reference. Nor does it promise that
#' columns can be dropped. Shrinking requires a resizable allocation too. Legacy tables
#' with columns outside their physical list always return `FALSE`.
#'
#' These queries do not repair a table, test its dibble type, or validate its
#' dibble reference-ownership bookkeeping. A copied or serialized dibble can retain
#' its type while losing capacity. Assign [reserve_columns()] before dropping
#' columns or relying on shared aliases. Automatic additions can rebuild the
#' table, so functions must return it for assignment by their caller. Readers, [dibble()],
#' and [copy_data()] return prepared tables. [as_dibble()] prepares conversions
#' from other containers; an ordinary dibble without additional container
#' classes is returned as is.
#'
#' @param data A dibble, tibble, base data frame, or data table. data.table
#'   support requires data.table 1.18.2.1 or newer.
#' @param n A finite, nonnegative whole number of additional columns.
#' @return `column_capacity()` returns one double, the total usable column
#'   capacity or `NA_real_` for an unprepared allocation. Subtract `ncol(data)`
#'   for spare slots. `can_add_columns()` returns one logical value.
#' @export
#' @examples
#' data <- reserve_columns(data.frame(x = 1:3), n = 2)
#' column_capacity(data) # three total slots
#' can_add_columns(data, 2) # TRUE
#' gen(data, y = x + 1)
#' can_add_columns(data, 2) # FALSE
column_capacity <- function(data) {
    .as_mutation_data(data, allow_grouped = TRUE)
    capacity <- .Call(C_dtatools_column_capacity, data)
    if (capacity < 0 || !.column_resize_ready(data)) NA_real_ else capacity
}

#' @rdname column_capacity
#' @export
can_add_columns <- function(data, n = 1L) {
    .as_mutation_data(data, allow_grouped = TRUE)
    n <- .validate_alloccol(n, length(data))
    !.has_column_overlay(data) && (n == 0 || .column_resize_ready(data)) && isTRUE(.Call(
        C_dtatools_can_select_data_columns, data, length(data) + n
    ))
}

.column_resize_ready <- function(data) {
    if (.ordinary_data_table(data)) {
        # A staged data.table column commit requires matching table and names
        # identities, even when the physical list still has spare slots.
        if (!.data_table_reference_ready(data)) return(FALSE)
    }
    .Call(C_dtatools_column_capacity, data) >= 0
}

.data_table_reference_ready <- function(data) {
    isTRUE(.Call(C_dtatools_data_table_reference_valid, data))
}
