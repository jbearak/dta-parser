#' Slice data-frame rows through Stata storage
#'
#' Gathers compact Stata numeric columns together in native code instead of
#' dispatching through `[` once per column. This is useful for wide data where
#' ordinary data-frame or tibble row slicing is dominated by per-column vctrs
#' dispatch. Other columns use vctrs slicing, and the result keeps the input's
#' base data-frame or tibble container and Stata metadata.
#'
#' `rows` follows [vctrs::vec_as_location()] semantics. Positive, negative,
#' logical, and character locations are supported, as are repeated and missing
#' locations. Character locations match row names.
#'
#' @param data An ordinary base data frame or tibble. Data-frame subclasses,
#'   including data.table, are not supported.
#' @param rows A row subscript accepted by [vctrs::vec_as_location()].
#' @return The selected rows in the same base data-frame or tibble container.
#' @export
slice_stata_rows <- function(data, rows) {
    if (!is.data.frame(data)) {
        stop("`data` must be a base data frame or tibble", call. = FALSE)
    }
    base_classes <- setdiff(class(data), "dtatools_stata_metadata")
    ordinary <- identical(base_classes, "data.frame") ||
        identical(base_classes, c("tbl_df", "tbl", "data.frame"))
    if (!ordinary) {
        stop(
            "`data` must be an ordinary base data frame or tibble",
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
    columns <- .dta_merge_slice_columns(
        data, locations, fill_string_missing = FALSE
    )

    if (length(columns) == 0L) {
        return(data[locations, , drop = FALSE])
    }
    shell <- data[locations, integer(), drop = FALSE]

    source_attributes <- attributes(data)
    structural <- c("names", "row.names", "class")
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
