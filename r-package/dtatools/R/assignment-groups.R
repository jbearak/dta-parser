# The group plan for group-wise assignment: `gen()`, `repl()`, the `:=`
# bracket, and `egen()` all form their groups here. The plan carries each
# group's rows and keys. `by` visits the groups in order of first
# appearance, the dataset's current row order; `bysort` visits them in
# Stata's total key order, which is the order the sort produces. Within
# a group the rows are in dataset order. Group identity is Stata value
# identity for `dta_*()` columns, so `.` and each extended missing code
# form their own groups, and vctrs identity otherwise.
#
# `bysort` is settled in two steps. The plan records the permutation that
# sorts the dataset, and the consumer applies it with
# `.apply_group_order()` before evaluating `where` and `values`, so they
# see the sorted dataset, and undoes it with `.undo_group_order()` if
# the call fails before its first write. So an assignment that fails
# leaves the dataset in its original order. The plan is an environment
# because the permutation is applied at most once: the assignments of
# one `data[i, j, bysort = ]` call share a plan and sort with the first
# of them that writes.
#
# Returns `NULL` when the call is ungrouped or the dataset has no rows,
# after validating the group names.
.assignment_groups <- function(data, original, by, bysort, grouped_input) {
    if (!is.null(by) && rlang::quo_is_null(by)) by <- NULL
    if (!is.null(bysort) && rlang::quo_is_null(bysort)) bysort <- NULL
    if (!is.null(by) && !is.null(bysort)) {
        stop("supply either `by` or `bysort`, not both", call. = FALSE)
    }
    if (grouped_input) {
        if (!is.null(by) || !is.null(bysort)) {
            stop(.MUTATION_GROUPED_MESSAGE, call. = FALSE)
        }
        if (original$nrow == 0L) return(NULL)
        groups <- attr(data, "groups", exact = TRUE)
        if (!is.data.frame(groups) || !".rows" %in% names(groups)) {
            stop("`data` has grouped-tibble metadata without groups",
                 call. = FALSE)
        }
        # dplyr's own partition, including the empty groups `.drop = FALSE`
        # records; consumers skip a group without rows.
        rows <- lapply(seq_len(nrow(groups)), function(index) {
            as.integer(groups$.rows[[index]])
        })
        return(.new_assignment_groups(
            rows, groups[setdiff(names(groups), ".rows")], NULL
        ))
    }
    if (is.null(by) && is.null(bysort)) return(NULL)
    argument <- if (is.null(by)) "bysort" else "by"
    names <- .mutation_group_names(
        if (is.null(by)) bysort else by, original$columns, argument
    )
    if (original$nrow == 0L) return(NULL)
    keys <- lapply(names, .mutation_column, columns = original$columns)
    if (isTRUE(attr(original$columns, ".dtatools_mutation_views", exact = TRUE))) {
        keys <- lapply(keys, .metadata_copy)
    }
    names(keys) <- names
    keys <- vctrs::new_data_frame(keys, n = original$nrow)
    order <- NULL
    if (is.null(bysort)) {
        # `vec_group_loc()` lists the groups by first appearance, each
        # group's rows in dataset order.
        located <- vctrs::vec_group_loc(keys)
        rows <- lapply(located$loc, as.integer)
    } else {
        # `vec_order()` is the stable sort of the rows by the keys, in
        # Stata's total order through `vec_proxy_order()` for Stata
        # numeric columns: finite values, then `.`, then `.a` through
        # `.z`. The groups are then read off the sorted keys, so they
        # are visited in sort order with each group's rows in sort order,
        # whatever ties the key's equality and order proxies disagree on.
        order <- vctrs::vec_order(keys)
        located <- vctrs::vec_group_loc(vctrs::vec_slice(keys, order))
        rows <- lapply(located$loc, function(loc) order[loc])
        if (identical(order, seq_len(original$nrow))) order <- NULL
    }
    .new_assignment_groups(rows, located$key, order)
}

# Counts the by-reference row reorders of the session: `reorder_dta_rows()`,
# a `bysort` sort, and egen's sorted install each bump it in the same
# uninterruptible step as their native commit, so a count never records
# a reorder that did not happen. The undo of a `bysort` sort compares the count with the
# one it recorded: a change means user code reordered rows by reference
# in between, and the saved inverse no longer describes the dataset. The
# undo then stands down and the last committed order stays, as it does
# once a write has committed. A sort that is itself undone puts the
# count back with the rows, so it does not stand down an enclosing undo. The count is one per session, not per
# table, so a reorder of another table inside `where` or `values` also
# stands the undo down: the failed call then leaves its sort in place,
# which is a state a bracket with a failing later assignment leaves too,
# never a misaligned one.
.row_order_epoch <- new.env(parent = emptyenv())
.row_order_epoch$count <- 0L

.note_row_reorder <- function() {
    .row_order_epoch$count <- .row_order_epoch$count + 1L
    invisible(.row_order_epoch$count)
}

.new_assignment_groups <- function(rows, keys, order) {
    plan <- new.env(parent = emptyenv())
    plan$rows <- rows
    plan$keys <- keys
    plan$order <- order
    plan
}

# Sorts the dataset by reference into the plan's `bysort` order, once,
# before the consumer evaluates user code. `staged` is the consumer's
# environment for undoing the sort: everything the undo needs, the
# column pointers before and after the sort, the plan and its rows and
# permutation, is recorded there together with the sort, so a handler
# that finds `staged$restore` set can always put the dataset back. The plan's rows are then remapped to the sorted positions and
# the permutation cleared, so the plan describes the sorted dataset and
# a repeated call does nothing. `TRUE` when the dataset was sorted.
.apply_group_order <- function(plan, data, staged) {
    order <- plan$order
    if (is.null(order)) return(FALSE)
    inverse <- integer(length(order))
    inverse[order] <- seq_along(order)
    remapped <- lapply(plan$rows, function(rows) inverse[rows])
    # Everything that can fail runs before the dataset is touched: the
    # sorted columns are gathered first, as `reorder_dta_rows()` gathers
    # them, and nothing is armed if that fails. The install and the
    # capture of the undo state are then one uninterruptible step, so the
    # undo is never half-armed: either the dataset is unsorted and there
    # is nothing to undo, or it is sorted and the undo knows it.
    restore <- .reorder_column_plan(data)
    .prepare_column_operation(data, length(restore$columns))
    columns <- .dta_merge_slice_columns(
        vctrs::new_data_frame(restore$columns, n = restore$nrow),
        order, fill_string_missing = FALSE
    )
    staged$plan <- plan
    staged$order <- order
    staged$rows <- plan$rows
    suspendInterrupts({
        .Call(
            C_dtatools_replace_reference_columns, data, restore$store,
            restore$locations, restore$names, unname(columns)
        )
        staged$epoch <- .note_row_reorder()
        # The pointers the sort installed: the undo tells a slot user
        # code has since replaced from one it has not by comparing
        # against them.
        staged$sorted <- .plain_data_columns(data)
        staged$restore <- restore
    })
    plan$rows <- remapped
    plan$order <- NULL
    TRUE
}

# Puts the dataset back as it was before `.apply_group_order()`, slot
# by slot. A slot that still holds the pointer the sort installed gets
# its saved pre-sort pointer back, not a re-slice, so aliased slots keep
# their identity. A slot user code has replaced meanwhile, by reaching
# back into the dataset from `where` or `values`, and any slot it added,
# is put back through the inverse permutation, so its committed values
# stay and stay aligned. The plan is restored with the rows. A no-op
# when nothing is staged, and when user code has reordered rows by
# reference since the sort (see `.row_order_epoch`): that order was
# committed and stands. A consumer disarms the undo with
# `.disarm_group_order()` once its first write has committed.
.undo_group_order <- function(data, staged) {
    restore <- staged$restore
    if (is.null(restore)) return(invisible(FALSE))
    if (!identical(staged$epoch, .row_order_epoch$count)) {
        .disarm_group_order(staged)
        return(invisible(FALSE))
    }
    current <- .plain_data_columns(data)
    names_now <- attr(data, "names", exact = TRUE)
    saved <- restore$columns
    names(saved) <- restore$saved_names
    sorted <- staged$sorted
    names(sorted) <- restore$saved_names
    untouched <- vapply(seq_along(current), function(index) {
        name <- names_now[[index]]
        !is.null(sorted[[name]]) &&
            .same_mutation_object(current[[index]], sorted[[name]])
    }, logical(1))
    columns <- vector("list", length(current))
    columns[untouched] <- saved[names_now[untouched]]
    if (any(!untouched)) {
        inverse <- integer(length(staged$order))
        inverse[staged$order] <- seq_along(staged$order)
        columns[!untouched] <- .dta_merge_slice_columns(
            vctrs::new_data_frame(current[!untouched], n = length(inverse)),
            inverse, fill_string_missing = FALSE
        )
    }
    .prepare_column_operation(data, length(columns))
    suspendInterrupts({
        .Call(
            C_dtatools_replace_reference_columns, data, NULL,
            seq_along(columns), rep(NA_character_, length(columns)), columns
        )
        # The dataset is as it was before the sort, so the epoch is too:
        # a sort undone inside another call's `where` or `values` leaves
        # that call's undo armed, as its dataset has not moved.
        .row_order_epoch$count <- staged$epoch - 1L
    })
    staged$plan$rows <- staged$rows
    staged$plan$order <- staged$order
    .disarm_group_order(staged)
    invisible(TRUE)
}

# Drops the undo state: the sort stands. Called by the consumer's first
# write, and by the undo once it has run, so a bracket with many
# assignments does not carry the pre-sort plan through the rest of them.
.disarm_group_order <- function(staged) {
    staged$restore <- NULL
    staged$sorted <- NULL
    staged$epoch <- NULL
    staged$order <- NULL
    staged$rows <- NULL
    staged$plan <- NULL
    invisible(NULL)
}

