#' Reorder a table's rows in place through Stata storage
#'
#' Gathers every column the way [slice_dta_rows()] does — compact
#' Stata numeric columns through the native kernel, other columns
#' through vctrs — then replaces the table's column pointers in
#' place when no legacy rebuild is needed, so the table object keeps its
#' identity and every reference sees the new row order. Unlike `data.table::set()`, the
#' gathered columns are installed without copying, so compact numeric
#' columns stay unmaterialized.
#'
#' Legacy tables with columns outside their physical list are rebuilt first.
#' This warns and may separate aliases; see [reserve_columns()].
#'
#' @param data An ordinary base data frame, tibble, dibble, or data.table,
#'   modified by reference, or rebuilt when a legacy table requires it.
#' @param rows A permutation of `seq_len(nrow(data))` following
#'   [vctrs::vec_as_location()] semantics, without missing locations.
#'   Every row must be selected exactly once: an in-place reorder
#'   cannot change the row count.
#' @return `data`, invisibly. For a data.table the `sorted` marker and
#'   secondary indexes are cleared because a permutation invalidates
#'   them.
#' @export
reorder_dta_rows <- function(data, rows) {
    target_expr <- substitute(data)
    binding <- .capture_mutation_binding(target_expr, parent.frame())
    if (!is.null(binding)) data <- binding$data
    original_data <- data
    if (.has_column_overlay(data)) {
        data <- .prepare_column_operation(data, length(.reference_names(data)))
    }
    plan <- .reorder_column_plan(data)
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
    .return_mutation(original_data, data, if (is.null(binding)) target_expr else binding, parent.frame())
}

# Validate the supported container and stage the current physical columns.
# All commits target positions in the supplied table; no state store is written.
.reorder_column_plan <- function(data) {
    if (!is.data.frame(data)) {
        stop(
            "`data` must be a base data frame, tibble, or data.table",
            call. = FALSE
        )
    }
    state <- .reference_state(data)
    classes <- setdiff(class(data), "dtatools_ref_data")
    base_classes <- setdiff(classes, "dtatools_dta_metadata")
    data_table <- identical(base_classes, c("data.table", "data.frame"))
    if (!data_table &&
        !identical(base_classes, "data.frame") &&
        !identical(base_classes, c("tbl_df", "tbl", "data.frame"))) {
        stop(
            paste0(
                "`data` must be an ordinary base data frame, tibble, ",
                "or data.table"
            ),
            call. = FALSE
        )
    }
    columns <- .data_columns(data)
    count <- length(columns)
    list(
        columns = columns,
        store = NULL,
        locations = seq_len(count),
        names = rep(NA_character_, count),
        nrow = abs(.row_names_info(data, 2L)),
        data_table = data_table
    )
}
