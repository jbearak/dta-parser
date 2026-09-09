# Construction adapted from dplyr 1.2.1 R/generics.R; see installed NOTICE.
# Standard frame/grouped/rowwise assembly is owned here. A selected external
# method retains its public generic context, as on the predecessor snapshot.
.dibble_col_modify_external <- function(data) {
    for (name in class(data)) {
        method <- utils::getS3method("dplyr_col_modify", name, optional = TRUE,
                                    envir = asNamespace("dplyr"))
        if (!is.null(method)) return(!name %in% c("data.frame", "grouped_df", "rowwise_df"))
    }
    FALSE
}

.dibble_col_modify <- function(data, cols) {
    before <- .data_columns(data)
    plain <- .reference_snapshot(data)
    if (.dibble_col_modify_external(plain)) return(.typed_reference_replacement(
        data, dplyr::dplyr_col_modify(plain, cols), "`dplyr_col_modify()`"))
    context <- .begin_dibble_result(data, "`dplyr_col_modify()`", "computed")
    grouped <- inherits(plain, "grouped_df")
    rowwise <- inherits(plain, "rowwise_df")
    working <- if (grouped || rowwise) tibble::as_tibble(plain) else plain
    cols <- vctrs::vec_recycle_common(!!!cols, .size = nrow(working))
    columns <- .data_columns(vctrs::vec_data(working))
    new_names <- enc2utf8(rlang::names2(cols))
    names(columns) <- enc2utf8(rlang::names2(columns))
    for (index in seq_along(cols)) columns[[new_names[[index]]]] <- cols[[index]]
    # Reconstruction is a separate public extension, even when the table
    # inherits standard column modification. It may change values or signal.
    result <- dplyr::dplyr_reconstruct(vctrs::new_data_frame(columns,
        n = nrow(working), row.names = .row_names_info(working, 0L)), working)
    keys <- .group_vars(plain)
    if (grouped && any(names(cols) %in% keys)) {
        if (length(setdiff(keys, names(result)))) rlang::abort(paste0(
            "`vars` missing from `data`: ", paste(encodeString(keys, quote = "`"), collapse = ", "), "."))
        groups <- .build_group_metadata(.data_columns(result), keys, nrow(result),
            drop = .group_drop_default(plain), signal_regroup = TRUE)
        attr(result, "groups") <- groups
        class(result) <- c("grouped_df", "tbl_df", "tbl", "data.frame")
    } else if (grouped) {
        attr(result, "groups") <- attr(plain, "groups", exact = TRUE)
        class(result) <- c("grouped_df", "tbl_df", "tbl", "data.frame")
    } else if (rowwise) {
        # Public tibble selection supplies the same missing-key rejection as
        # rowwise_df before the shared rowwise group builder runs.
        group_data <- tibble::as_tibble(result)[keys]
        if (".rows" %in% names(group_data)) rlang::abort(
            "`group_data` must be a tibble without a `.rows` column.")
        attr(result, "groups") <- .build_group_metadata(
            .data_columns(group_data), keys, nrow(result), rowwise = TRUE)
        class(result) <- c("rowwise_df", "tbl_df", "tbl", "data.frame")
    }
    result <- .retype_changed_columns(result, before, context$caller)
    .finish_dibble_result(context, result)
}

#' @export
dplyr_col_modify.dtatools_ref_data <- function(data, cols) {
    if (!is_dibble(data)) return(dplyr::dplyr_col_modify(.reference_snapshot(data), cols))
    .dibble_col_modify(data, cols)
}
