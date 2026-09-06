# A context retains the actual source vectors while their addresses identify
# lineage. Identity is never a validity or ownership claim. Only operation-local
# isolated, normalized columns are reused, including repeated output slots.
.begin_dibble_result <- function(data, caller, operation) {
    stopifnot(operation %in% c("columns", "rows", "computed", "unknown"))
    columns <- .data_columns(data)
    metadata <- attributes(data)
    metadata$.dtatools_ref_state <- NULL
    metadata$class <- .reference_base_classes(class(data))
    if (.has_column_overlay(data)) {
        if (.row_names_info(data, 1L) < 0L) {
            metadata$row.names <- .set_row_names(.reference_state(data)$nrow)
        }
        metadata$names <- names(columns)
    }
    addresses <- vapply(columns, rlang::obj_address, character(1))
    lineage <- new.env(hash = TRUE, parent = emptyenv())
    for (address in addresses) lineage[[address]] <- TRUE
    list(columns = columns, metadata = metadata, caller = caller,
         operation = operation, lineage = lineage)
}

.finish_dibble_result <- function(context, result, sources = NULL, grouping = NULL) {
    result <- .prepare_dibble_frame(result)
    source_addresses <- if (!is.null(sources)) {
        unlist(lapply(sources, function(source) {
            if (is.data.frame(source)) {
                vapply(.data_columns(source), rlang::obj_address, character(1))
            } else rlang::obj_address(source)
        }))
    }
    completed <- new.env(hash = TRUE, parent = emptyenv())
    # Retain the original result list throughout the loop. This keeps every
    # address in completed rooted even after the output slot has been replaced.
    columns <- .data_columns(result)
    for (index in seq_along(columns)) {
        column <- columns[[index]]
        address <- rlang::obj_address(column)
        if (!exists(address, envir = completed, inherits = FALSE)) {
            unchanged <- exists(address, context$lineage, inherits = FALSE)
            # Even an unchanged source can be borrowed or externally writable.
            # Isolate before validation; never cache validity on the table.
            isolate <- is.null(sources) || address %in% source_addresses ||
                (identical(context$operation, "columns") && unchanged)
            completed[[address]] <- .prepare_dibble_result_column(
                column, isolate, nrow(result), context$caller,
                names(columns)[[index]])
        }
        .Call(C_dtatools_set_data_column, result, as.integer(index),
              completed[[address]])
    }
    if (!is.null(grouping)) result <- grouping(result)
    .validate_group_metadata(result)
    .new_validated_dibble(result)
}

.prepare_dibble_result_column <- function(column, isolate, row_count, caller, name) {
    if (isolate && is.character(column) && !.is_altrep(column) &&
        is.null(dim(column)) && .valid_string_declaration(
            attr(column, "stata.string.storage", exact = TRUE))) {
        # The existing generation kernel validates width while allocating the
        # isolated result. It preserves every attribute supplied here. It also
        # normalizes NA, which a valid declaration cannot contain, so reuse the
        # result only if all values and attributes are identical to the source.
        # Stale declarations and encodings unsupported by that kernel retain
        # the established normalization path below.
        copied <- tryCatch(.Call(
            C_dtatools_generate_character, column, NULL, as.double(row_count),
            attr(column, "stata.string.storage", exact = TRUE), attributes(column)
        ), error = function(condition) {
            message <- conditionMessage(condition)
            if (identical(message,
                "Generated values do not fit their declared Stata string storage") ||
                identical(message,
                    gettext('translating strings with "bytes" encoding is not allowed',
                            domain = "R"))) {
                return(NULL)
            }
            stop(condition)
        })
        if (!is.null(copied) && identical(column, copied)) return(copied)
    }
    value <- if (isolate) .metadata_copy(column) else column
    .typed_column_named(value, row_count, caller, name)
}

# Selector planning is adapted from dplyr 1.2.1's select.R, rename.R and
# relocate.R. The full provenance and MIT notice are installed in NOTICE.
.dibble_ensure_group_columns <- function(context, locations) {
    groups <- context$metadata$groups
    if (!any(context$metadata$class %in% c("grouped_df", "rowwise_df"))) {
        return(locations)
    }
    group_names <- setdiff(names(groups), ".rows")
    missing <- setdiff(match(group_names, names(context$columns)), locations)
    added_names <- names(context$columns)[missing]
    added <- stats::setNames(missing, added_names)
    # Selecting g = x shadows, rather than also retaining, an omitted group g.
    added <- added[!added_names %in% names(locations)]
    if (length(added)) {
        rlang::inform(paste0("Adding missing grouping variables: ",
            paste0("`", names(added), "`", collapse = ", ")))
    }
    c(added, locations)
}

.dibble_select_columns <- function(context, locations) {
    columns <- context$columns[unname(locations)]
    names(columns) <- if (length(locations)) names(locations) else character()
    metadata <- context$metadata
    metadata$names <- names(columns)
    attributes(columns) <- metadata
    # Tibble column subsetting resets row names. Grouped/rowwise names<-
    # reconstructs the frame and does so too; plain rename preserves them.
    if (!identical(context$caller, "rename()") ||
        any(metadata$class %in% c("grouped_df", "rowwise_df"))) {
        attr(columns, "row.names") <- .set_row_names(nrow(columns))
    }
    columns <- .dibble_select_groups(context, columns, locations)
    .finish_dibble_result(context, columns)
}

# Match dplyr's column-only grouped/rowwise subset and subsequent names<- rules.
# Keep a complete grouped partition without regrouping; dropping a key can merge
# groups and rebuilds their keys and indices with the shared grouping module. Rowwise key order follows the selected column order.
.dibble_select_groups <- function(context, result, locations) {
    classes <- context$metadata$class
    grouped <- "grouped_df" %in% classes
    rowwise <- "rowwise_df" %in% classes
    if (!grouped && !rowwise) return(result)
    groups <- context$metadata$groups
    group_names <- setdiff(names(groups), ".rows")
    selected_names <- names(context$columns)[unname(locations)]
    kept <- if (rowwise && !identical(context$caller, "rename()"))
        intersect(selected_names, group_names) else
        intersect(group_names, selected_names)
    new_names <- names(locations)[match(kept, selected_names)]
    if (grouped && !identical(kept, group_names)) {
        attr(result, "groups") <- NULL
        class(result) <- setdiff(classes, "grouped_df")
        attr(result, "groups") <- .build_group_metadata(
            .data_columns(result), new_names, nrow(result),
            drop = !identical(attr(groups, ".drop"), FALSE))
        class(result) <- if (length(kept)) classes else setdiff(classes, "grouped_df")
        return(result)
    }
    groups <- groups[c(kept, ".rows")]
    names(groups) <- c(new_names, ".rows")
    attr(result, "groups") <- groups
    result
}

.dibble_relocate_locations <- function(data, expression, before, after, env) {
    selected <- tidyselect::eval_select(expression, data, env = env)
    # A relocation cannot duplicate a source slot. Its last new name wins.
    selected <- selected[!duplicated(selected, fromLast = TRUE)]
    has_before <- !rlang::quo_is_null(before)
    has_after <- !rlang::quo_is_null(after)
    if (has_before && has_after) {
        rlang::abort("Can't supply both `.before` and `.after`.")
    }
    count <- length(data)
    if (has_before) {
        destination <- tidyselect::eval_select(before, data, env = env)
        where <- if (length(destination)) min(destination) else 1L
    } else if (has_after) {
        destination <- tidyselect::eval_select(after, data, env = env)
        where <- (if (length(destination)) max(destination) else count) + 1L
    } else where <- 1L
    all <- seq_len(count)
    left <- setdiff(all[all < where], selected)
    right <- setdiff(all[all >= where], selected)
    c(stats::setNames(left, names(data)[left]), selected,
      stats::setNames(right, names(data)[right]))
}
