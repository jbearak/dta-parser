#' Reorder a table's rows in place through Stata storage
#'
#' See [mutation-containers] for supported classes, grouping and conversion.
#' Gathers every column the way [slice_dta_rows()] does — compact
#' Stata numeric columns through the native kernel, other columns
#' through vctrs — then replaces the table's column pointers in
#' place, so the table object keeps its
#' identity and every reference sees the new row order. Unlike `data.table::set()`, the
#' gathered columns are installed without copying, so compact numeric
#' columns stay unmaterialized.
#'
#' Legacy tables with columns outside their physical list require assigned
#' [reserve_columns()] before this call. Reordering needs no spare slots.
#'
#' @param data An ordinary base data frame, tibble, dibble, or data.table,
#'   modified by reference.
#' @param rows A permutation of `seq_len(nrow(data))` following
#'   [vctrs::vec_as_location()] semantics, without missing locations.
#'   Every row must be selected exactly once: an in-place reorder
#'   cannot change the row count.
#' @return `data`, invisibly. For a data.table the `sorted` marker and
#'   secondary indexes are cleared because a permutation invalidates
#'   them.
#' @export
reorder_dta_rows <- function(data, rows) {
    plan <- .reorder_column_plan(data)
    .prepare_column_operation(data, length(data), names_change = FALSE)
    count <- plan$nrow
    locations <- vctrs::vec_as_location(
        rows, n = count, missing = "error", arg = "rows"
    )
    if (length(locations) != count || anyDuplicated(locations) > 0L) {
        stop("`rows` must select every row exactly once", call. = FALSE)
    }
    columns <- .dta_merge_slice_columns(
        vctrs::new_data_frame(plan$columns, n = count),
        locations, fill_string_missing = FALSE
    )
    .Call(
        C_dtatools_replace_reference_columns, data, plan$store,
        plan$locations, plan$names, unname(columns)
    )
    if (plan$data_table) {
        data.table::setattr(data, "sorted", NULL)
        data.table::setattr(data, "index", NULL)
    }
    invisible(data)
}

# Validate the supported container and stage the current physical columns.
# All commits target positions in the supplied table; no state store is written.
.reorder_column_plan <- function(data) {
    original <- .as_mutation_data(data)
    columns <- original$columns
    data_table <- .data_table_container(data)
    count <- length(columns)
    list(
        columns = columns,
        store = NULL,
        locations = seq_len(count),
        names = rep(NA_character_, count),
        nrow = original$nrow,
        data_table = data_table
    )
}
