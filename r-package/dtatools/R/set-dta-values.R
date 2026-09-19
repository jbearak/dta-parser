#' Assign values into one column by reference, cheaply enough for a loop
#'
#' `set_dta_values()` writes `value` into column `variable` of a dibble at
#' `rows`, by reference, the way [data.table::set()] writes into a data
#' table. It is the loop-friendly form of [repl()]: the column is a name or
#' a position held in an ordinary R value, `rows` and `value` are ordinary
#' R values, nothing is quoted or evaluated against the data, and one call
#' costs microseconds rather than the fixed cost of tidy evaluation that
#' `repl()` pays. Use it inside a `for` loop over rows or columns; use
#' `repl()` for a vectorised Stata-style replacement with a `where`
#' condition, grouping, or storage promotion.
#'
#' @param data A dibble to mutate; assign `data <- as_dibble(data)` to
#'   convert another container first.
#' @param variable One column name as a string, or one column position.
#' @param value The values to write: one value for every selected row, one
#'   value per selected row, or one value per row of the data, from which
#'   the selected rows are taken.
#' @param rows `NULL` for every row, a logical vector with one entry per
#'   row, or row positions.
#' @param create `TRUE` adds the column when `variable` names one that does
#'   not exist, filled with `value` at `rows` and Stata missing elsewhere,
#'   at the storage [gen()] would give it. By default a missing column is
#'   an error, as Stata's `replace` makes it, so a typo cannot add a stray
#'   column. A column cannot be created by position.
#'
#' @section One storage rule:
#' The target keeps its declared storage. A value the storage cannot hold
#' is an error naming the storage that would, and nothing changes; this is
#' [repl()] with `promote = FALSE`, and it is what `data.table::set()` does
#' too. A loop that widened its column mid-way would rebuild the whole
#' column on that iteration and change its type without a word, so the
#' assigner refuses instead, and the caller declares the storage up front,
#' with `dta_int()`, `dta_double()`, or `set_dta_metadata()`. Character
#' `NA` is written as `""`, Stata's string missing.
#'
#' @section Cost:
#' On a 100,000-row table a single-row write costs about thirteen
#' microseconds on a numeric column and a whole-column write about twenty;
#' a Stata string column costs more, since every write checks the string
#' width. `repl()` costs over a hundred microseconds for the same writes,
#' and `data.table::set()` about two. The
#' [cell-assignment benchmark](https://github.com/jbearak/dta-parser/tree/main/benchmarks/r-cell-assignment)
#' records the numbers and how to reproduce them.
#'
#' @return `data`, invisibly. When `create = TRUE` had to grow the table,
#'   an isolated table is returned and must be assigned, as with [gen()].
#' @seealso [repl()] for the Stata verb with `where`, `by`, and promotion;
#'   [gen()] for creating a column from an expression; [dta-storage-defaults]
#'   for the storage a created column takes.
#' @export
#' @examples
#' survey <- dibble(id = 1:4, score = dta_int(c(10L, 20L, 30L, 40L)))
#' set_dta_values(survey, "score", 0L, rows = 2)
#' set_dta_values(survey, 2, c(1L, 2L), rows = c(TRUE, FALSE, TRUE, FALSE))
#' for (i in seq_len(nrow(survey))) set_dta_values(survey, "score", i * 100L, rows = i)
#' survey
#'
#' # A value the storage cannot hold is refused; declare wider storage first.
#' try(set_dta_values(survey, "score", 1e9, rows = 1))
#' survey <- set_dta_values(survey, "flag", TRUE, rows = c(1, 3), create = TRUE)
#' survey
set_dta_values <- function(data, variable, value, rows = NULL, create = FALSE) {
    .require_mutation_target(data)
    # Every argument is an ordinary R value, so all of them are forced here,
    # before anything about the table is read: an argument expression that
    # edits the table by reference, or errors, has done so before the
    # layout, the sharing, and the views are taken, and they describe the
    # table that is written. The container check comes first, cheaply,
    # so a table no writer accepts is refused with no argument evaluated.
    .set_values_preflight(data)
    force(variable); force(value); force(rows)
    if (!rlang::is_bool(create)) {
        stop("`create` must be `TRUE` or `FALSE`", call. = FALSE)
    }
    target <- .set_values_target(data, variable, create)
    if (is.na(target$location)) {
        # Capacity is checked before the column is built, as `gen()` does.
        data <- .prepare_column_growth(data, length(data) + 1L, .mutation_auto_grow())
    }
    # Inspect sharing before the views add temporary column references,
    # as `repl()` does.
    shared <- .Call(C_dtatools_shared_columns, data)
    original <- .set_values_open(data)
    on.exit(.Call(C_dtatools_release_mutation_views, original$columns), add = TRUE)
    rows <- .set_values_rows(rows, original$nrow)
    if (is.na(target$location)) {
        return(invisible(.set_values_create(data, original, target$name, value, rows)))
    }
    resolved <- .resolved_assignment(value, rows, original$nrow)
    .commit_replacement(
        data, original, target, resolved, shared,
        promote = FALSE, report_promotion = FALSE,
        grouped_input = inherits(data, "grouped_df")
    )
    invisible(data)
}

# The container check every mutation helper runs before it evaluates an
# argument, without the column views the full preflight opens: an
# ungrouped dibble with no extra classes passes on its class vector alone.
.set_values_preflight <- function(data) {
    if (.ungrouped_dibble_classes(class(data))) return(invisible(NULL))
    .validate_mutation_container(data, allow_grouped = TRUE, allow_rowwise = FALSE)
}

# The column as name and location. A position must exist; a name must
# exist unless `create` allows adding it, in which case its location is
# `NA` and the caller appends.
.set_values_target <- function(data, variable, create) {
    names <- attr(data, "names", exact = TRUE)
    if (is.character(variable) && length(variable) == 1L && !is.na(variable) &&
        nzchar(variable)) {
        location <- match(variable, names)
        if (is.na(location) && !create) {
            stop(sprintf(
                "Column `%s` does not exist; pass `create = TRUE` to add it",
                variable
            ), call. = FALSE)
        }
        return(list(name = variable, location = location))
    }
    if (is.numeric(variable) && length(variable) == 1L && !is.na(variable) &&
        is.finite(variable) && variable == floor(variable) &&
        variable >= 1 && variable <= length(names)) {
        return(list(name = names[[variable]], location = as.integer(variable)))
    }
    stop("`variable` must be one existing column name or position", call. = FALSE)
}

# `rows` normalized as `where` is, with the errors naming this function's
# argument: the shared normalizer speaks of `where`, the only spelling the
# Stata verbs have.
.set_values_rows <- function(rows, row_count) {
    tryCatch(
        .mutation_rows(rows, row_count),
        error = function(condition) {
            stop(sub("^`where`", "`rows`", conditionMessage(condition)), call. = FALSE)
        }
    )
}

# The table's columns as private views with the row count, through the
# native shape check when the table is one it certifies, since that check
# is what keeps a call at microseconds; otherwise through the full
# validation `repl()` uses, which also covers a grouped dibble.
.set_values_open <- function(data) {
    row_count <- if (.ungrouped_dibble_classes(class(data))) {
        # An ungrouped dibble with no extra classes is what the native
        # shape check certifies; the generic container validation it would
        # otherwise run costs more than the write itself.
        rows <- abs(.row_names_info(data, 2L))
        if (isTRUE(.Call(C_dtatools_mutation_shape, data, rows))) rows else NULL
    } else {
        .mutation_fast_shape(data)
    }
    if (!is.null(row_count)) {
        return(list(columns = .Call(C_dtatools_mutation_views, data),
                    names = attr(data, "names", exact = TRUE), nrow = row_count))
    }
    .as_mutation_data(data, allow_grouped = TRUE, allow_rowwise = FALSE,
                      private_views = TRUE)
}

# The two class chains an ungrouped dibble carries: with and without the
# dataset-metadata marker a reader adds. Distinct from `.plain_dibble_classes()`
# in dibble.R, which also admits grouped and rowwise chains.
.ungrouped_dibble_classes <- function(classes) {
    identical(classes, c("dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame")) ||
        identical(classes, c("dibble", "dtatools_ref_data", "dtatools_dta_metadata",
                             "tbl_df", "tbl", "data.frame"))
}

# `create = TRUE` on a missing column: the column `gen()` would make from
# `value` at `rows`, appended to a table whose capacity the caller has
# already secured, so `data` may be the isolated table growth returned.
.set_values_create <- function(data, original, name, value, rows) {
    # The size rule the write path applies, before the native fill sees a
    # value it cannot spread over the rows.
    .mutation_value_mode(value, rows, original$nrow)
    column <- .generated_column(
        value, rows, original$nrow, caller = "set_dta_values()",
        generate = TRUE, carry_metadata = FALSE
    )
    .prepare_column_operation(data, length(data) + 1L)
    .append_generated_column(data, name, column)
    if (inherits(data, "grouped_df")) .regroup_after_replacement(data)
    data
}
