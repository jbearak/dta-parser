# Locations have already been checked by the entry point. Native numeric
# gathering and public vctrs fallback operate on plain column lists, so neither
# grouping nor reference-container dispatch can occur inside this module.
.gather_dta_columns <- function(columns, locations, fallback = "vctrs") {
    if (!length(columns)) return(columns)
    storage <- vapply(columns, function(column) {
        value <- .declared_dta_storage(column)
        if (is.null(value)) "" else value
    }, character(1))
    native <- vapply(columns, .dta_merge_has_compact_storage, logical(1)) |
        storage == "double"
    result <- vector("list", length(columns))
    names(result) <- names(columns)
    if (any(native)) {
        gathered <- .Call(C_dtatools_gather_numeric_columns,
                          unname(columns[native]), NULL, locations, NULL)
        positions <- which(native)
        for (offset in seq_along(gathered)) {
            index <- positions[[offset]]
            if (is.null(gathered[[offset]])) native[[index]] <- FALSE else
                result[[index]] <- gathered[[offset]]
        }
    }
    positions <- which(!native)
    if (length(positions)) {
        frame <- vctrs::new_data_frame(columns[positions],
                                       n = NROW(columns[[positions[[1L]]]]))
        result[positions] <- .plain_data_columns(if (identical(fallback, "base")) {
            frame[locations, , drop = FALSE]
        } else vctrs::vec_slice(frame, locations))
    }
    result
}

.ungrouped_result_frame <- function(columns, metadata, row_names) {
    metadata$names <- names(columns)
    metadata$row.names <- row_names
    metadata$groups <- NULL
    metadata$class <- setdiff(metadata$class, c("grouped_df", "rowwise_df"))
    attributes(columns) <- metadata
    columns
}

.row_slice_names <- function(context, locations) {
    shell <- .ungrouped_result_frame(list(), context$metadata,
                                      context$metadata$row.names)
    attr(vctrs::vec_slice(shell, locations), "row.names", exact = TRUE)
}

.dibble_take_rows <- function(context, locations, template,
                              policy = "rebuild", preserve = FALSE,
                              row_names = .set_row_names(length(locations))) {
    result <- .ungrouped_result_frame(
        .gather_dta_columns(context$columns, locations), context$metadata, row_names)
    .finish_dibble_result(context, result, sources = list(template),
        grouping = function(value) .restore_group_metadata(
            value, template, policy, locations, preserve))
}

# Public reconstruction accepts unknown columns. The finalizer isolates and
# types them conservatively; template attributes do not certify their storage.
.reconstruct_dibble <- function(data, template) {
    .as_mutation_data(template, allow_grouped = TRUE)
    context <- .begin_dibble_result(template, "dplyr_reconstruct()", "unknown")
    result <- .ungrouped_result_frame(.data_columns(data), context$metadata,
                                      attr(data, "row.names", exact = TRUE))
    .finish_dibble_result(context, result, grouping = function(value)
        .restore_group_metadata(value, template))
}

# Bracket planning uses the container's public index rules on one integer row
# column. Column selection is shallow. Only the resulting locations reach the
# shared gatherer, avoiding one integer planning vector per dataset column.
.reference_bracket <- function(data, call, environment, one_dimension) {
    .as_mutation_data(data, allow_grouped = TRUE)
    snapshot <- .reference_snapshot(data)
    grouped <- inherits(snapshot, "grouped_df")
    rowwise <- inherits(snapshot, "rowwise_df")
    attr(snapshot, "groups") <- NULL
    class(snapshot) <- setdiff(class(snapshot), c("grouped_df", "rowwise_df"))
    # Matrix extraction returns the underlying container's non-table result.
    # data.table's expressions have their own environment and remain its API.
    if (inherits(snapshot, "data.table")) {
        call[[1L]] <- quote(`[`)
        call[[2L]] <- snapshot
        return(.close_dibble(data, eval(call, environment)))
    }
    metadata_selected <- NULL
    if (inherits(snapshot, "dtatools_dta_metadata")) {
        # The metadata wrapper selects indices before NextMethod matches the
        # container method's arguments. Force its subscript once, then retain
        # the value as a quoted argument for subsequent container planning.
        metadata_call <- match.call(`[.dtatools_dta_metadata`, call, expand.dots = FALSE)
        metadata_selected <- stats::setNames(seq_along(snapshot), names(snapshot))
        subscript <- if (one_dimension) "i" else "j"
        if (subscript %in% names(metadata_call)) {
            value <- eval(metadata_call[[subscript]], environment)
            metadata_selected <- metadata_selected[value]
            where <- if (subscript %in% names(call)) match(subscript, names(call)) else
                if (one_dimension) 3L else 4L
            call[[where]] <- call("quote", value)
        }
    }
    method <- if (grouped || rowwise) {
        # These two dplyr bracket methods have no dots argument. Keep their
        # argument-matching errors without loading either implementation.
        function(x, i, j, drop = FALSE) NULL
    } else if (inherits(snapshot, "tbl_df"))
        utils::getS3method("[", "tbl_df") else `[.data.frame`
    matched <- match.call(method, call, expand.dots = TRUE)
    supplied_i <- "i" %in% names(matched)
    supplied_j <- "j" %in% names(matched)
    supplied_drop <- "drop" %in% names(matched)
    if (one_dimension) {
        i <- if (supplied_i) eval(matched$i, environment) else NULL
        call[[1L]] <- quote(`[`)
        call[[2L]] <- snapshot
        if (supplied_i) {
            where <- if ("i" %in% names(call)) match("i", names(call)) else 3L
            call[[where]] <- call("quote", i)
        }
        # Keep ordinary one-dimensional extraction, including matrix indices
        # and tibble's warning for an ignored drop argument.
        result <- eval(call, environment)
        if (!is.data.frame(result)) return(result)
        if (grouped && supplied_drop && eval(matched$drop, environment)) {
            return(.close_dibble(data, result))
        }
        result <- .restore_group_metadata(result, data, "columns")
        return(.close_dibble(data, result))
    }
    if (!inherits(snapshot, "tbl_df")) {
        return(.reference_base_rows(snapshot, matched, call, environment, metadata_selected))
    }
    i <- if (supplied_i) eval(matched$i, environment) else NULL
    j <- if (supplied_j) eval(matched$j, environment) else NULL
    # Evaluate extra arguments just as the underlying method does. Tibble
    # accepts unused dots; base data frames report their own unused arguments.
    column_call <- as.call(list(quote(`[`), snapshot, rlang::missing_arg(),
        if (supplied_j) call("quote", j) else rlang::missing_arg(), drop = FALSE))
    # Base warns for user-supplied named indices. Synthesized arguments must
    # not introduce that warning into originally positional calls.
    explicit <- intersect(c("x", "i", "j"), names(call))
    for (name in explicit) names(column_call)[match(name, c("", "x", "i", "j", "drop"))] <- name
    selected <- eval(column_call, environment)
    row_frame <- tibble::new_tibble(list(.row = seq_len(nrow(snapshot))), nrow = nrow(snapshot))
    attr(row_frame, "row.names") <- attr(snapshot, "row.names", exact = TRUE)
    row_plan <- if (supplied_i) row_frame[i, , drop = FALSE] else row_frame
    locations <- row_plan[[1L]]
    columns <- if (supplied_i) .gather_dta_columns(.data_columns(selected), locations) else
        .data_columns(selected)
    metadata <- attributes(selected)
    result <- .ungrouped_result_frame(columns, metadata,
        if (supplied_i) attr(row_plan, "row.names", exact = TRUE) else
            attr(selected, "row.names", exact = TRUE))
    drop <- if (supplied_drop) eval(matched$drop, environment) else FALSE
    result <- result[, , drop = drop]
    if (!is.data.frame(result)) return(result)
    policy_template <- data
    if (grouped && drop) {
        policy_template <- snapshot
    }
    if (is_dibble(data)) {
        context <- .begin_dibble_result(data, "`[`", "rows")
        # With no row subscript, the selected columns still belong to the source.
        return(.finish_dibble_result(context, result, sources = list(data),
            grouping = function(value) .restore_group_metadata(value, policy_template,
                if (supplied_i) "bracket" else "columns")))
    }
    .restore_group_metadata(result, policy_template,
                            if (supplied_i) "bracket" else "columns")
}


# Base subsetting policy adapted from R 4.6.1 [.data.frame, modified 2026-09-06.
# Copyright (C) 1998-2025 The R Core Team; Statlib code by John Chambers,
# Bell Labs, 1994. GPL-2-or-later; incorporated under GPL-3. See installed NOTICE.
# Base data frames can return a vector, a list with duplicate names, or a frame
# from the same two-index call. Plan columns as a list so frame name repair does
# not change a later list result. The one-column row frame supplies base row
# names and locations, and the shared gatherer applies base fallback semantics.
.reference_base_rows <- function(snapshot, matched, original_call, environment, selected) {
    has_i <- "i" %in% names(matched)
    has_j <- "j" %in% names(matched)
    has_drop <- "drop" %in% names(matched)
    if (any(names(original_call) %in% c("x", "i", "j"))) {
        warning("named arguments other than 'drop' are discouraged", call. = FALSE)
    }
    metadata_first <- inherits(snapshot, "dtatools_dta_metadata")
    restore <- function(result) {
        if (metadata_first) .restore_subset_dta_metadata(snapshot, result, selected) else result
    }
    if (!has_i) {
        drop <- if (has_drop) eval(matched$drop, environment) else TRUE
        if (drop && !has_j && length(snapshot) == 1L) return(restore(snapshot[[1L]]))
    }
    if (!exists("j", inherits = FALSE)) {
        j <- if (has_j) eval(matched$j, environment) else seq_along(snapshot)
    }
    columns <- .subset(snapshot, j)
    single <- FALSE
    if (has_i && has_j) {
        drop <- if (has_drop) eval(matched$drop, environment) else length(columns) == 1L
        if (drop && length(columns) == 1L) single <- TRUE
    }
    if (!single && anyNA(names(columns))) stop("undefined columns selected", call. = FALSE)
    if (!has_i && drop && length(columns) == 1L) return(restore(columns[[1L]]))
    i <- if (has_i) eval(matched$i, environment) else NULL
    # Dropping to one vector has that vector's indexing and NULL semantics.
    # It does not publish a table or require a multi-column gather.
    if (single) {
        if (is.character(i)) i <- pmatch(i, attr(snapshot, "row.names"), duplicates.ok = TRUE)
        column <- columns[[1L]]
        return(restore(if (length(dim(column)) == 2L) column[i, , drop = FALSE] else column[i]))
    }
    row_frame <- vctrs::new_data_frame(list(.row = seq_len(nrow(snapshot))), n = nrow(snapshot))
    attr(row_frame, "row.names") <- attr(snapshot, "row.names", exact = TRUE)
    row_plan <- if (has_i) row_frame[i, , drop = FALSE] else row_frame
    if (has_i) columns <- .gather_dta_columns(columns, row_plan[[1L]], fallback = "base")
    if (!exists("drop", inherits = FALSE)) {
        drop <- if (has_drop) eval(matched$drop, environment) else length(columns) == 1L
    }
    if (has_i) {
        drop_list <- FALSE
        if (drop) {
            if (length(columns) == 1L) return(restore(columns[[1L]]))
            drop_list <- has_drop && length(columns) > 1L && nrow(row_plan) == 1L
        }
    } else drop_list <- drop && has_drop && nrow(row_plan) == 1L
    metadata <- if (has_j) attributes(columns) else attributes(snapshot)
    metadata$class <- class(snapshot)
    metadata$names <- names(columns)
    metadata$row.names <- attr(row_plan, "row.names", exact = TRUE)
    if ((!has_i || !drop_list) && anyDuplicated(names(columns))) {
        metadata$names <- make.unique(names(columns))
    }
    if (drop_list) {
        metadata$class <- NULL
        metadata$row.names <- NULL
    }
    attributes(columns) <- metadata
    restore(columns)
}
