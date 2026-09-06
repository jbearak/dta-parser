# Locations have already been checked by the entry point. Native numeric
# gathering and public vctrs fallback operate on plain column lists, so neither
# grouping nor reference-container dispatch can occur inside this module.
.gather_dta_columns <- function(columns, locations) {
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
        for (offset in seq_along(gathered)) {
            index <- which(native)[[offset]]
            result[[index]] <- if (is.null(gathered[[offset]]))
                vctrs::vec_slice(columns[[index]], locations) else gathered[[offset]]
        }
    }
    fallback <- which(!native)
    if (length(fallback)) {
        frame <- vctrs::new_data_frame(columns[fallback],
                                       n = NROW(columns[[fallback[[1L]]]]))
        result[fallback] <- .plain_data_columns(vctrs::vec_slice(frame, locations))
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
        call <- matched
        call[[1L]] <- quote(`[`)
        call[[2L]] <- snapshot
        if (supplied_i) call["i"] <- list(call("quote", i))
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
    if (inherits(snapshot, "tbl_df")) {
        i <- if (supplied_i) eval(matched$i, environment) else NULL
        j <- if (supplied_j) eval(matched$j, environment) else NULL
    } else {
        j <- if (supplied_j) eval(matched$j, environment) else NULL
    }
    # Evaluate extra arguments just as the underlying method does. Tibble
    # accepts unused dots; base data frames report their own unused arguments.
    column_call <- matched
    column_call[[1L]] <- quote(`[`)
    column_call[[2L]] <- snapshot
    column_call["i"] <- list(rlang::missing_arg())
    column_call["j"] <- if (supplied_j) list(call("quote", j)) else list(rlang::missing_arg())
    column_call$drop <- FALSE
    selected <- eval(column_call, environment)
    if (!inherits(snapshot, "tbl_df")) {
        if (supplied_drop && (supplied_j || !supplied_i)) {
            drop <- eval(matched$drop, environment)
        }
        i <- if (supplied_i) eval(matched$i, environment) else NULL
    }
    row_frame <- if (inherits(snapshot, "tbl_df"))
        tibble::new_tibble(list(.row = seq_len(nrow(snapshot))), nrow = nrow(snapshot)) else
        vctrs::new_data_frame(list(.row = seq_len(nrow(snapshot))), n = nrow(snapshot))
    attr(row_frame, "row.names") <- attr(snapshot, "row.names", exact = TRUE)
    row_plan <- if (supplied_i) row_frame[i, , drop = FALSE] else row_frame
    locations <- row_plan[[1L]]
    columns <- if (supplied_i) .gather_dta_columns(.data_columns(selected), locations) else
        .data_columns(selected)
    metadata <- attributes(selected)
    result <- .ungrouped_result_frame(columns, metadata,
        if (supplied_i) attr(row_plan, "row.names", exact = TRUE) else
            attr(selected, "row.names", exact = TRUE))
    if (!exists("drop", inherits = FALSE)) {
        drop <- if (supplied_drop) eval(matched$drop, environment) else FALSE
    }
    if (!inherits(snapshot, "tbl_df") && !supplied_drop) drop <- length(columns) == 1L
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
