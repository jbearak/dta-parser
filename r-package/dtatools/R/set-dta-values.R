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
#' [repl()] with `promote = FALSE`. `data.table::set()` also checks types
#' and ranges, but permits some lossy conversions with warnings. dtatools
#' also enforces Stata ranges, missing tags, and declared storage. A loop that widened its column mid-way would rebuild the whole
#' column on that iteration and change its type without a word, so the
#' assigner refuses instead, and the caller declares the storage up front,
#' with `dta_int()`, `dta_double()`, or `set_dta_metadata()`. Character
#' `NA` is written as `""`, Stata's string missing.
#'
#' @section Cost:
#' On the recorded 100,000-row ungrouped fixture, a single-row scalar write
#' took 1.8 microseconds, a whole-column scalar fill 10.0 microseconds, and
#' 1,000 row writes 2.0 to 2.1 milliseconds. The baseline on the same host
#' took 14.0 microseconds, 22.1 microseconds, and 16.7 to 17.0 milliseconds.
#' Eligible numeric scalar writes use native validation and commit without
#' private target views. Single-row writes and whole-column scalar fills
#' stage their values on the stack, with zero native scratch heap bytes in
#' the recorded private-write cases. Expressions, classed or foreign ALTREP
#' inputs, temporal targets, and strings use the general path. The
#' [cell-assignment benchmark](https://github.com/jbearak/dta-parser/blob/main/benchmarks/r-cell-assignment/results-2026-09-20-shared-mutation.md)
#' records revisions, methods, width and sharing effects, and fallback
#' variation. These timings are not guarantees. A grouped dibble rebuilds
#' its groups after every write, which costs time and memory in proportion
#' to the row count, so `dplyr::ungroup()` before a loop and group again
#' after it.
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
    # Native inspection never forces an argument. A decline leaves the
    # established evaluation order below untouched.
    fast <- .Call(C_dtatools_set_values_fast, data, environment())
    if (!is.null(fast)) return(invisible(fast))
    .require_mutation_target(data)
    # The order every mutation helper keeps: the table is validated before
    # any argument is evaluated, and capacity for a new column is checked
    # before the values that fill it are. Each argument is an ordinary R
    # value, but an argument expression, a vector with methods, or a foreign
    # ALTREP object can run caller code whenever it is read, and that code
    # can edit this table by reference. So every argument is evaluated and
    # settled, the value cast or built into the column it becomes, before
    # the layout the write relies on is read. Reordering the columns
    # meanwhile is honoured, since the target is found again by name; adding
    # or removing the target, or changing the row count, is refused.
    row_count <- .set_values_preflight(data)
    variable <- .set_values_plain(variable)
    create <- .set_values_plain(create)
    if (!is.logical(create) || length(create) != 1L || is.na(create)) {
        stop("`create` must be `TRUE` or `FALSE`", call. = FALSE)
    }
    target <- .set_values_target(data, variable, create)
    creating <- is.na(target$location)
    if (creating) {
        data <- .prepare_column_growth(data, length(data) + 1L, .mutation_auto_grow())
    }
    rows <- .set_values_settled_input(.set_values_rows(rows, row_count))
    # The size rule reads only the value's length, so a foreign value that
    # cannot fit is refused before its elements are copied.
    value_mode <- .mutation_value_mode(value, rows, row_count)
    if (.is_altrep(value)) {
        value <- .set_values_settled_input(value)
        value_mode <- .mutation_value_mode(value, rows, row_count)
    }
    # The arguments have run; the target is found again by name for the
    # cast, and once more after it, since the cast can run a value's methods.
    target <- .set_values_target(data, target$name, create)
    if (is.na(target$location) != creating) .set_values_changed()
    view <- if (!creating) .Call(C_dtatools_mutation_column_view, data, target$location)
    on.exit(.Call(C_dtatools_release_mutation_views, view), add = TRUE)
    column <- .set_values_column(view, value, value_mode, rows, row_count)
    # Nothing evaluates caller code from here to the commit: the name and
    # the flag are plain values, the names and row count are attribute
    # reads, and the slot is compared by address.
    target$location <- match(target$name, attr(data, "names", exact = TRUE))
    if (abs(.row_names_info(data, 2L)) != row_count ||
        is.na(target$location) != creating ||
        (!creating &&
         !.Call(C_dtatools_mutation_column_current, data, target$location, view))) {
        .set_values_changed()
    }
    if (creating) {
        .prepare_column_operation(data, length(data) + 1L)
        .append_generated_column(data, target$name, column)
    } else if (!is.null(column) || .mutation_selected_count(rows, row_count) > 0L) {
        # The commit `repl()` makes with `promote = FALSE`, with the cast
        # already done: release the view, then patch the slot, which
        # detaches it first when another table holds the column.
        .Call(C_dtatools_release_mutation_views, view)
        shared <- .Call(C_dtatools_shared_columns, data)
        .Call(
            C_dtatools_patch_slot, data, target$location, rows, column,
            shared[[target$location]]
        )
    }
    if (inherits(data, "grouped_df")) .regroup_after_replacement(data)
    invisible(data)
}

.set_values_changed <- function() {
    stop(paste0(
        "`data` changed while `set_dta_values()` evaluated its arguments; ",
        "nothing was written"
    ), call. = FALSE)
}

# Validates the table before any argument is evaluated and returns its row
# count. An ungrouped dibble with no extra classes takes the native shape
# check, which certifies the names and column lengths; every other table
# takes the full validation `repl()` uses.
.set_values_preflight <- function(data) {
    if (.ungrouped_dibble_classes(class(data))) {
        rows <- abs(.row_names_info(data, 2L))
        if (isTRUE(.Call(C_dtatools_mutation_shape, data, rows))) return(rows)
    }
    # Through private views, released at once: a plain list of the columns
    # would count as a second holder of each until this frame is cleaned
    # up, and the write would detach and copy the target for no reason.
    original <- .as_mutation_data(data, allow_grouped = TRUE, allow_rowwise = FALSE,
                                  private_views = TRUE)
    .Call(C_dtatools_release_mutation_views, original$columns)
    original$nrow
}

# `variable` and `create` as plain vectors: a foreign ALTREP object is
# copied, and a class and other attributes are dropped, so that reading
# either later dispatches no method. Both are scalars, so the copy is
# trivial, and neither carries metadata the assigner would keep.
.set_values_plain <- function(value) {
    value <- .set_values_settled_input(value)
    if (!is.null(attributes(value))) attributes(value) <- NULL
    value
}

# An ALTREP object of a class this package did not define runs its own
# code whenever an element is read, which the native patch does after the
# layout is taken. It is copied into an ordinary vector once, here; the
# package's own compact and dictionary vectors read without callbacks and
# pass through, as does every ordinary vector.
.set_values_settled_input <- function(value) {
    .Call(C_dtatools_settle_foreign_altrep, value)
}

# The value in the form the commit writes: cast to
# the target's declared storage for a replacement, since the cast is where
# a vector with methods runs them; or built into the column `gen()` would
# make for a creation. The cast reads the target through a private view,
# never the column itself, so a method the value runs cannot observe or
# alias the column. Casting here rather than in the commit means the
# commit's native patch reads a vector that carries only package or base
# classes, and the storage a value cannot fit is reported before the
# table's layout is read.
.set_values_column <- function(view, value, value_mode, rows, row_count) {
    if (is.null(view)) {
        return(.generated_column(
            value, rows, row_count, caller = "set_dta_values()",
            generate = TRUE, carry_metadata = FALSE
        ))
    }
    .set_values_settled_input(.cast_replacement(value, view[[1L]], rows, value_mode))
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

# The two class chains an ungrouped dibble carries: with and without the
# dataset-metadata marker a reader adds. Distinct from `.plain_dibble_classes()`
# in dibble.R, which also admits grouped and rowwise chains.
.ungrouped_dibble_classes <- function(classes) {
    identical(classes, c("dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame")) ||
        identical(classes, c("dibble", "dtatools_ref_data", "dtatools_dta_metadata",
                             "tbl_df", "tbl", "data.frame"))
}
