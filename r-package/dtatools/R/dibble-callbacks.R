# Callback validation, key assembly and nesting policies adapt dplyr 1.2.1
# group-map.R, group-split.R, group-nest.R and nest-by.R at 95740975.
# Package gathering and publication retain the stronger mutation isolation.
# See installed NOTICE for the complete provenance and MIT notice.
.dibble_callback_chunk <- function(context, rows, keep, group_names) {
    columns <- context$columns
    if (!isTRUE(keep)) columns <- columns[setdiff(names(columns), group_names)]
    # Group splitting constructs plain tibbles and drops dataset attributes;
    # column metadata remains attached to the gathered values.
    tibble::new_tibble(.gather_dta_columns(columns, rows), nrow = length(rows))
}

.dibble_group_modify <- function(.data, .f, ..., .keep = FALSE) {
    data <- .data
    fun <- .f
    dots <- match.call(expand.dots = FALSE)$...
    if ("keep" %in% names(dots)) lifecycle::deprecate_stop(
        "1.0.0", "group_modify(keep = )", "group_modify(.keep = )")
    fun <- rlang::as_function(fun)
    if (length(formals(fun)) < 2L && !"..." %in% names(formals(fun))) {
        rlang::abort(c("`.f` must accept at least two arguments.",
            i = "You can use `...` to absorb unused components."))
    }
    context <- .begin_dibble_result(data, "group_modify()", "unknown")
    groups <- .dibble_expression_groups(data)
    if (!inherits(data, "grouped_df")) {
        # Plain and rowwise callbacks receive the whole input exactly once.
        input <- .capture_dibble_nested(.reference_snapshot(data))
        result <- fun(input, .capture_dibble_nested(groups$keys), ...)
        return(.close_dibble(data, .retype_changed_columns(
            result, context$columns, "`group_modify()`"), "group_modify()"))
    }
    # Upstream completes splitting before the first callback. Retain an
    # independent input generation even when a callback writes the source.
    context$columns <- lapply(context$columns, .capture_dibble_nested)
    groups$keys <- .capture_dibble_nested(groups$keys)
    count <- nrow(groups$keys)
    chunks <- vector("list", max(1L, count))
    for (id in seq_along(chunks)) {
        rows <- if (count) groups$rows[[id]] else integer()
        key <- vctrs::vec_slice(groups$keys, if (count) id else integer())
        input <- .capture_dibble_nested(.dibble_callback_chunk(
            context, rows, .keep, groups$names))
        result <- fun(input, .capture_dibble_nested(key), ...)
        if (!is.data.frame(result)) rlang::abort("The result of `.f` must be a data frame.")
        bad <- intersect(names(result), groups$names)
        if (length(bad)) rlang::abort(paste0(
            "The returned data frame cannot contain the original grouping variables: ",
            paste(bad, collapse = ", "), "."))
        # Capture now: a later callback may explicitly mutate the same foreign
        # table that supplied this callback's return value.
        result <- .capture_dibble_nested(.reference_snapshot(result))
        # The prototype callback can return rows even when there were no real
        # groups. Match tibble's padded key subset, not strict out-of-bounds.
        key <- vctrs::vec_slice(key, rep.int(if (nrow(key)) 1L else NA_integer_, nrow(result)))
        chunks[[id]] <- vctrs::vec_cbind(key, result, .name_repair = "unique")
    }
    result <- if (count) vctrs::vec_rbind(!!!chunks) else chunks[[1L]]
    result <- .retype_changed_columns(result, context$columns, "`group_modify()`")
    .finish_dibble_result(context, result, grouping = function(result) {
        class(result) <- c("grouped_df", setdiff(class(result), c("grouped_df", "rowwise_df")))
        attr(result, "groups") <- .build_group_metadata(.data_columns(result),
            groups$names, nrow(result), .group_drop_default(data))
        result
    })
}

.dibble_nest <- function(data, dots, key = "data", keep = FALSE,
                         rowwise = FALSE, dots_supplied = length(dots) > 0L) {
    caller <- if (rowwise) "nest_by()" else "group_nest()"
    grouped <- inherits(data, "grouped_df")
    if (grouped && dots_supplied) {
        if (rowwise) rlang::abort(c("Can't re-group while nesting",
            i = "Either `ungroup()` first or don't supply arguments to `nest_by()`"))
        rlang::warn("Calling `group_nest()` on a grouped_df ignores `...`. Please use `group_by(..., .add = TRUE) |> group_nest()`.")
    }
    context <- .begin_dibble_result(data, caller, "unknown")
    if (!rowwise && !grouped && !length(dots)) {
        result <- tibble::tibble(!!key := list(.reference_snapshot(data)))
        return(.finish_dibble_result(context, result))
    }
    if (!grouped) data <- .dibble_group_by(data, dots, FALSE, .group_drop_default(data))
    context <- .begin_dibble_result(data, caller, "unknown")
    groups <- .dibble_expression_groups(data)
    chunks <- lapply(groups$rows, function(rows)
        .dibble_callback_chunk(context, rows, keep, groups$names))
    prototype <- .dibble_callback_chunk(context, integer(), keep, groups$names)
    nested <- vctrs::new_list_of(chunks, ptype = prototype)
    # Dynamic name handling follows the same named-assignment contract as the
    # upstream key-frame mutate, including replacement of a colliding key.
    named <- tibble::tibble(!!key := nested)
    columns <- .data_columns(groups$keys)
    for (name in names(named)) columns[name] <- list(named[[name]])
    result <- tibble::new_tibble(columns, nrow = nrow(groups$keys))
    .finish_dibble_result(context, result, grouping = function(result) {
        if (rowwise) {
            class(result) <- c("rowwise_df", class(result))
            attr(result, "groups") <- .build_group_metadata(.data_columns(result),
                groups$names, nrow(result), rowwise = TRUE)
        }
        result
    })
}
