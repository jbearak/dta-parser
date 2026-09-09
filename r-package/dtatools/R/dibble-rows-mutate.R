# Row mutation policies adapted from dplyr 1.2.1 R/rows.R. Matching keys and
# destination casts have separate contracts; common keys do not widen payloads.
# Public matching/casting and table extension dispatch remain explicit boundaries.
.dibble_rows_select <- function(data, columns, call) {
    locations <- vctrs::vec_as_location(columns, n = length(data), names = names(data))
    out <- data[locations]
    if (!is.data.frame(out) || length(out) != length(locations)) {
        rlang::abort("The `[` method must return a data frame with the selected number of columns.",
                     call = call)
    }
    # The public bracket method is an extension boundary. Base/data.table
    # selection drops attributes that the upstream helper restores explicitly.
    if (identical(class(data), "data.frame") ||
        identical(class(data), c("data.table", "data.frame"))) {
        out <- dplyr::dplyr_reconstruct(out, data)
    }
    out
}

.dibble_rows_by <- function(by, y, call) {
    if (is.null(by)) {
        if (!length(y)) rlang::abort("`y` must have at least one column.", call = call)
        by <- names(y)[[1L]]
        rlang::inform(paste0("Matching, by = \"", by, "\""),
            class = c("dplyr_message_matching_by", "dplyr_message"))
    }
    if (!is.character(by)) rlang::abort("`by` must be a character vector.", call = call)
    if (!length(by)) rlang::abort("`by` must specify at least 1 column.", call = call)
    if (!all(rlang::names2(by) == "")) rlang::abort("`by` must be unnamed.", call = call)
    by
}

.dibble_rows_columns <- function(x, y, by, call, subset = TRUE) {
    bad <- if (subset) setdiff(names(y), names(x)) else character()
    if (length(bad)) rlang::abort(c("All columns in `y` must exist in `x`.",
        i = paste0("The following columns only exist in `y`: ",
                   .dibble_join_vars_label(bad), ".")), call = call)
    for (side in c("x", "y")) {
        missing <- setdiff(by, names(if (side == "x") x else y))
        if (length(missing)) rlang::abort(c(
            "All columns specified through `by` must exist in `x` and `y`.",
            i = paste0("The following columns are missing from `", side, "`: ",
                       .dibble_join_vars_label(missing), ".")), call = call)
    }
}

.dibble_rows_unique <- function(key, call) {
    if (vctrs::vec_duplicate_any(key)) rlang::abort(c(
        "`y` key values must be unique.",
        i = paste0("The following rows contain duplicate key values: ",
            .dibble_join_vars_label(which(vctrs::vec_duplicate_detect(key))), ".")),
        call = call)
}

.dibble_rows_keep <- function(x_key, y_key, policy, conflict, call) {
    policy <- rlang::arg_match0(policy, c("error", "ignore"),
        arg_nm = if (conflict) "conflict" else "unmatched", error_call = call)
    matched <- vctrs::vec_in(y_key, x_key)
    bad <- if (conflict) matched else !matched
    if (!any(bad)) return(NULL)
    if (policy == "error") {
        argument <- if (conflict) "conflict" else "unmatched"
        rlang::abort(c(
            if (conflict) "`y` can't contain keys that already exist in `x`." else
                "`y` must contain keys that already exist in `x`.",
            i = paste0("The following rows in `y` have keys that ",
                if (conflict) "already exist" else "don't exist", " in `x`: ",
                .dibble_join_vars_label(which(bad)), "."),
            i = paste0("Use `", argument, " = \"ignore\"` if you want to ignore these `y` rows.")),
            call = call)
    }
    which(!bad)
}

.dibble_rows_cast <- function(y, x, call) {
    vctrs::vec_cast(y, x, x_arg = "y", to_arg = "x", call = call)
}

.dibble_rows_append <- function(x, y, call) {
    # Public vctrs binding retains table prototype/cast/restore callbacks and
    # row names. The final public extension dispatch reaches our shared,
    # conservative dibble reconstruction, rather than a whole rows verb.
    dplyr::dplyr_reconstruct(vctrs::vec_rbind(x, y), x)
}

.dibble_rows_change <- function(x, y, by, type, unmatched, call) {
    by <- .dibble_rows_by(by, y, call)
    .dibble_rows_columns(x, y, by, call, subset = type != "delete")
    x_key <- .dibble_rows_select(x, by, call)
    y_key <- .dibble_rows_select(y, by, call)
    if (type != "delete") .dibble_rows_unique(y_key, call)
    keys <- vctrs::vec_cast_common(x = x_key, y = y_key)
    x_key <- keys$x; y_key <- keys$y
    if (type != "delete") {
        value_names <- setdiff(names(y), names(y_key))
        x_values <- .dibble_rows_select(x, value_names, call)
        y_values <- .dibble_rows_cast(.dibble_rows_select(y, value_names, call), x_values, call)
    }
    if (type != "upsert") {
        keep <- .dibble_rows_keep(x_key, y_key, unmatched, FALSE, call)
        if (!is.null(keep)) {
            y_key <- dplyr::dplyr_row_slice(y_key, keep)
            if (type != "delete") y_values <- dplyr::dplyr_row_slice(y_values, keep)
        }
    }
    if (type == "delete") {
        extra <- setdiff(names(y), names(y_key))
        if (length(extra)) rlang::inform(
            paste0("Ignoring extra `y` columns: ", paste(extra, collapse = ", ")),
            class = c("dplyr_message_delete_extra_cols", "dplyr_message"))
    }
    locations <- vctrs::vec_match(x_key, y_key)
    matched <- !is.na(locations)
    if (type == "delete") return(dplyr::dplyr_row_slice(x, which(!matched)))
    x_locations <- which(matched)
    y_locations <- locations[matched]
    if (type == "patch") {
        selected <- .data_columns(dplyr::dplyr_row_slice(x_values, x_locations))
        replacement <- .data_columns(dplyr::dplyr_row_slice(y_values, y_locations))
        # This public vector operation retains typed missing proxies and custom
        # common-type/restore callbacks. It does not construct a table.
        replacement <- vctrs::new_data_frame(
            Map(dplyr::coalesce, selected, replacement), n = length(x_locations))
    } else replacement <- dplyr::dplyr_row_slice(y_values, y_locations)
    changed <- vctrs::vec_assign(x_values, x_locations, replacement)
    x <- dplyr::dplyr_col_modify(x, .data_columns(changed))
    if (type == "upsert") {
        unused <- if (!length(y_locations)) seq_len(nrow(y_key)) else
            vctrs::vec_as_location(-y_locations, nrow(y_key))
        added <- dplyr::dplyr_row_slice(y, unused)
        added <- .dibble_rows_cast(added, x, call)
        x <- .dibble_rows_append(x, added, "rows_upsert()")
    }
    x
}

.dibble_rows_in_place <- function(in_place, call) {
    if (rlang::is_true(in_place))
        rlang::abort("Data frames only support `in_place = FALSE`.", call = call)
}

#' @export
rows_insert.dtatools_ref_data <- function(x, y, by = NULL, ...,
    conflict = c("error", "ignore"), copy = FALSE, in_place = FALSE) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    .dibble_rows_in_place(in_place, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    by <- .dibble_rows_by(by, y, call)
    .dibble_rows_columns(x, y, by, call)
    y <- .dibble_rows_cast(y, x, call)
    keep <- .dibble_rows_keep(.dibble_rows_select(x, by, call), .dibble_rows_select(y, by, call),
                              conflict, TRUE, call)
    if (!is.null(keep)) y <- dplyr::dplyr_row_slice(y, keep)
    .dibble_rows_append(x, y, "rows_insert()")
}

#' @export
rows_append.dtatools_ref_data <- function(x, y, ..., copy = FALSE, in_place = FALSE) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    .dibble_rows_in_place(in_place, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_rows_columns(x, y, character(), call)
    y <- .dibble_rows_cast(y, x, call)
    .dibble_rows_append(x, y, "rows_append()")
}

#' @export
rows_update.dtatools_ref_data <- function(x, y, by = NULL, ...,
    unmatched = c("error", "ignore"), copy = FALSE, in_place = FALSE) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    .dibble_rows_in_place(in_place, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_rows_change(x, y, by, "update", unmatched, call)
}

#' @export
rows_patch.dtatools_ref_data <- function(x, y, by = NULL, ...,
    unmatched = c("error", "ignore"), copy = FALSE, in_place = FALSE) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    .dibble_rows_in_place(in_place, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_rows_change(x, y, by, "patch", unmatched, call)
}

#' @export
rows_upsert.dtatools_ref_data <- function(x, y, by = NULL, ..., copy = FALSE, in_place = FALSE) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    .dibble_rows_in_place(in_place, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_rows_change(x, y, by, "upsert", NULL, call)
}

#' @export
rows_delete.dtatools_ref_data <- function(x, y, by = NULL, ...,
    unmatched = c("error", "ignore"), copy = FALSE, in_place = FALSE) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    .dibble_rows_in_place(in_place, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_rows_change(x, y, by, "delete", unmatched, call)
}
