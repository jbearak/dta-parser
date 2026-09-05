#' Reserve spare column slots
#'
#' See [mutation-containers] for supported classes, grouping and conversion.
#' `reserve_columns()` returns an isolated table with `n` spare column
#' pointer slots. Compact columns use copy-on-write backing; ordinary columns
#' are copied. Assign the returned
#' table. The container and column storage are preserved. Legacy tables with
#' columns stored outside their physical list are rebuilt into one complete
#' list, and serialized dibbles get fresh current-object bookkeeping.
#'
#' Constructors, readers, and [copy_data()] reserve 5,000 spare slots by
#' default. Set `options(dtatools.alloccol = 5000L)` to change this default.
#' Explicit helpers preserve the supplied outer object. If it cannot hold
#' the requested column count, they stop before evaluating values or sorting
#' rows. Assign preparation before calling a function that adds or drops
#' columns. The same rule applies to symbols, function parameters, extracted
#' tables, and computed targets; helpers never rebind a caller's variable.
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
#' explicit structural mutation through aliases. `read_dta()` and `read_arrow()` return
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
reserve_columns <- function(data, n = getOption("dtatools.alloccol", 5000L)) {
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

.prepare_column_operation <- function(data, columns, names_change = TRUE) {
    if (.ordinary_data_table(data)) .require_data_table()
    if (!.has_column_overlay(data) &&
        (!(names_change && .ordinary_data_table(data)) || .data_table_reference_ready(data)) &&
        (columns == length(data) || .column_resize_ready(data)) && isTRUE(.Call(
        C_dtatools_can_select_data_columns, data, as.double(columns)
    ))) return(invisible(data))
    extra <- max(0, columns - length(data))
    stop(sprintf(
        paste0("The supplied table needs column preparation for this operation. ",
               "Assign `data <- reserve_columns(data, n = %s)` before calling ",
               "this helper or passing the table to a function; `n` is the ",
               "number of extra columns to allow."),
        format(extra, scientific = FALSE, trim = TRUE)
    ), call. = FALSE)
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
#' its type while losing capacity. Assign [reserve_columns()] before passing
#' such a table to a function that adds or drops columns. Readers, [dibble()],
#' and [copy_data()] return prepared tables. [as_dibble()] prepares conversions
#' from other containers; an input that is already a dibble is returned as is.
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
