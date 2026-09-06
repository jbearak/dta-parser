#' Slice data-frame rows through Stata storage
#'
#' Gathers compact Stata numeric columns together in native code instead of
#' dispatching through `[` once per column. This is useful for wide data where
#' ordinary data-frame, tibble, or data.table row slicing is dominated by
#' per-column dispatch. Other columns use vctrs slicing, and the result keeps
#' the input's base data-frame, tibble, or data.table container and Stata
#' metadata.
#'
#' `rows` follows [vctrs::vec_as_location()] semantics. Positive, negative,
#' logical, and character locations are supported, as are repeated and missing
#' locations. Character locations match row names.
#'
#' For a dibble with at least ten rows, `slice_dta_rows(survey, 1:10)` and
#' `survey[1:10, ]` both return the first ten rows with all columns, preserving
#' Stata metadata and leaving `survey` unchanged. Both share the batched row
#' gatherer. Brackets retain tibble indexing rules; `slice_dta_rows()` uses
#' vctrs location rules, including errors for unknown row names or out-of-range
#' positive locations. Grouped dibbles rebuild groups from the selected rows,
#' retaining `.drop`; rowwise dibbles retain their identifier variables. Missing
#' string rows become Stata's empty string before grouping is rebuilt.
#'
#' @param data An ordinary base data frame, tibble, data.table, or
#'   [dibble][dibble()]. Other data-frame subclasses are not supported.
#' @param rows A row subscript accepted by [vctrs::vec_as_location()].
#' @return The selected rows in the same base data-frame, tibble,
#'   data.table, or dibble container. A data.table result is a new over-allocated
#'   data.table; the input is left untouched, and any `sorted` marker or
#'   secondary indexes are dropped because a row selection invalidates
#'   them.
#' @export
slice_dta_rows <- function(data, rows) {
    if (!is.data.frame(data)) {
        stop(
            "`data` must be a base data frame, tibble, or data.table",
            call. = FALSE
        )
    }
    if (inherits(data, "dtatools_ref_data")) {
        .as_mutation_data(data, allow_grouped = TRUE)
        if (is_dibble(data)) {
            context <- .begin_dibble_result(data, "slice_dta_rows()", "rows")
            locations <- vctrs::vec_as_location(rows, n = nrow(data),
                names = if (is.character(rows)) row.names(data) else NULL,
                missing = "propagate", arg = "rows")
            return(.dibble_take_rows(context, locations, data))
        }
        snapshot <- .reference_snapshot(data)
        attr(snapshot, "groups") <- NULL
        class(snapshot) <- setdiff(class(snapshot), c("grouped_df", "rowwise_df"))
        return(.restore_group_metadata(slice_dta_rows(snapshot, rows), data))
    }

    base_classes <- setdiff(class(data), "dtatools_dta_metadata")
    data_table <- .ordinary_data_table(data)
    ordinary <- data_table ||
        identical(base_classes, "data.frame") ||
        identical(base_classes, c("tbl_df", "tbl", "data.frame"))
    if (!ordinary) {
        stop(
            paste0(
                "`data` must be an ordinary base data frame, tibble, ",
                "or data.table"
            ),
            call. = FALSE
        )
    }

    row_names <- if (is.character(rows)) row.names(data) else NULL
    locations <- vctrs::vec_as_location(
        rows,
        n = nrow(data),
        names = row_names,
        missing = "propagate",
        arg = "rows"
    )
    source_columns <- if (data_table) {
        # data.table's single-argument `[` selects rows, so the shared
        # gatherer must see the columns as a base data frame instead.
        vctrs::new_data_frame(as.list(data), n = nrow(data))
    } else {
        data
    }
    columns <- .gather_dta_columns(.data_columns(source_columns), locations)

    source_attributes <- attributes(data)
    structural <- c("names", "row.names", "class")

    if (data_table) {
        custom <- source_attributes[setdiff(
            names(source_attributes),
            c(structural, ".internal.selfref", "sorted", "index")
        )]
        result_attributes <- c(
            list(
                names = names(data),
                row.names = .set_row_names(length(locations))
            ),
            custom,
            list(class = class(data))
        )
        attributes(columns) <- result_attributes
        return(data.table::setalloccol(columns))
    }

    if (length(columns) == 0L) {
        return(data[locations, , drop = FALSE])
    }
    shell <- data[locations, integer(), drop = FALSE]

    custom <- source_attributes[setdiff(
        names(source_attributes), structural
    )]
    if (inherits(shell, "tbl_df")) {
        result_attributes <- c(
            list(
                names = names(data),
                row.names = attr(shell, "row.names", exact = TRUE)
            ),
            custom,
            list(class = class(data))
        )
    } else {
        leading <- source_attributes[setdiff(
            names(source_attributes), c("row.names", "class")
        )]
        leading$names <- names(data)
        result_attributes <- c(
            leading,
            list(
                row.names = attr(shell, "row.names", exact = TRUE),
                class = class(data)
            )
        )
    }
    attributes(columns) <- result_attributes
    columns
}
