#' Reorder a data.table's rows in place through Stata storage
#'
#' Gathers every column the way [slice_stata_rows()] does — compact
#' Stata numeric columns through the native kernel, other columns
#' through vctrs — then replaces the table's column pointers in
#' place, so the table object keeps its identity and every reference
#' to it sees the new row order. Unlike `data.table::set()`, the
#' gathered columns are installed without copying, so compact numeric
#' columns stay unmaterialized.
#'
#' @param data An ordinary data.table, modified by reference.
#' @param rows A permutation of `seq_len(nrow(data))` following
#'   [vctrs::vec_as_location()] semantics, without missing locations.
#'   Every row must be selected exactly once: an in-place reorder
#'   cannot change the row count.
#' @return `data`, invisibly. The data.table `sorted` marker and
#'   secondary indexes are cleared because a permutation invalidates
#'   them.
#' @export
reorder_stata_rows <- function(data, rows) {
    if (!.ordinary_data_table(data)) {
        stop("`data` must be an ordinary data.table", call. = FALSE)
    }
    count <- nrow(data)
    locations <- vctrs::vec_as_location(
        rows, n = count, missing = "error", arg = "rows"
    )
    if (length(locations) != count || anyDuplicated(locations) > 0L) {
        stop("`rows` must select every row exactly once", call. = FALSE)
    }
    columns <- .dta_merge_slice_columns(
        vctrs::new_data_frame(as.list(data), n = count),
        locations, fill_string_missing = FALSE
    )
    .Call(C_dtatools_replace_table_columns, data, columns)
    data.table::setattr(data, "sorted", NULL)
    data.table::setattr(data, "index", NULL)
    invisible(data)
}
