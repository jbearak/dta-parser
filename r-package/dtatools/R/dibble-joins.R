# Table assembly follows dplyr 1.2.1 join.R and join-cross.R policies while
# collecting columns through dtatools' shared gather/publication boundaries.
# No whole-table join implementation is called on the dibble path.
.dibble_join_publish <- function(columns, size, template, caller, sources = NULL) {
    if (!is_dibble(template)) {
        return(dplyr::dplyr_reconstruct(vctrs::new_data_frame(columns, n = size), template))
    }
    context <- .begin_dibble_result(template, caller, "unknown")
    result <- .ungrouped_result_frame(columns, context$metadata, .set_row_names(size))
    .finish_dibble_result(context, result, sources = sources,
        grouping = function(value) .restore_group_metadata(value, template))
}

.dibble_join_view <- function(data) {
    known <- c("dtatools_ref_data", "dibble", "dtatools_dta_metadata",
               "grouped_df", "rowwise_df", "tbl_df", "tbl", "data.frame")
    if (is_dibble(data) && all(class(data) %in% known)) {
        return(list(columns = .data_columns(data), size = nrow(data)))
    }
    # Foreign/custom conversion is a public extension boundary. It can change
    # values or size, and can signal conditions before common key casting.
    converted <- tibble::as_tibble(data, .name_repair = "minimal")
    list(columns = .data_columns(converted), size = nrow(converted))
}

.dibble_join_inputs <- function(x, y, by, suffix, keep, call, user_env) {
    x_names <- dplyr::tbl_vars(x)
    y_names <- dplyr::tbl_vars(y)
    by <- .dibble_join_by(by, x_names, y_names, call, user_env)
    vars <- .dibble_join_columns(x_names, y_names, by, suffix, keep, call)
    # Shape/group validation is separate from key casting, which can execute
    # extension callbacks. Unknown columns remain subject to final capture.
    .as_mutation_data(x, allow_grouped = TRUE)
    if (is_dibble(y)) .as_mutation_data(y, allow_grouped = TRUE)
    x_view <- .dibble_join_view(x)
    y_view <- .dibble_join_view(y)
    keys <- .dibble_join_keys(x_view$columns, y_view$columns, vars,
                              x_view$size, y_view$size, call)
    list(x = x_view$columns, y = y_view$columns, x_size = x_view$size,
         y_size = y_view$size, by = by, vars = vars, keys = keys)
}

.dibble_join_mutate <- function(x, y, by, type, suffix, keep, na_matches,
                                 multiple, unmatched, relationship, call, user_env) {
    na_matches <- rlang::arg_match0(na_matches, c("na", "never"), error_call = call)
    .dibble_join_keep(keep, call)
    plan <- .dibble_join_inputs(x, y, by, suffix, keep, call, user_env)
    rows <- .dibble_join_matches(plan$keys$x, plan$keys$y, type, plan$by,
        na_matches, multiple, unmatched, relationship, call, user_env)
    vars <- plan$vars
    x_out <- stats::setNames(plan$x[vars$x$out], names(vars$x$out))
    y_out <- stats::setNames(plan$y[vars$y$out], names(vars$y$out))
    out <- .gather_dta_columns(x_out, rows$x)
    out[names(y_out)] <- .gather_dta_columns(y_out, rows$y)
    if (!identical(keep, TRUE)) {
        merge <- if (is.null(keep)) plan$by$x[plan$by$condition == "=="] else plan$by$x
        cast <- vctrs::vec_cast(vctrs::new_data_frame(out[merge], n = length(rows$x)),
                                plan$keys$x[merge], call = call)
        out[merge] <- .plain_data_columns(cast)
        if (type %in% c("right", "full") && anyNA(rows$x)) {
            new_rows <- which(is.na(rows$x))
            replacements <- .gather_dta_columns(.data_columns(plan$keys$y[merge]),
                                                 rows$y[new_rows])
            for (name in merge) out[[name]] <- vctrs::vec_assign(out[[name]],
                new_rows, replacements[[name]], x_arg = paste0("x$", name))
        }
    }
    .dibble_join_publish(out, length(rows$x), x, paste0(type, "_join()"), list(x, y))
}

.dibble_join_filter <- function(x, y, by, type, na_matches, call, user_env) {
    na_matches <- rlang::arg_match0(na_matches, c("na", "never"), error_call = call)
    plan <- .dibble_join_inputs(x, y, by, c(".x", ".y"), NULL, call, user_env)
    rows <- .dibble_join_matches(plan$keys$x, plan$keys$y, type, plan$by,
        na_matches, "any", "drop", NULL, call, user_env)
    locations <- if (type == "semi") rows$x else rows$x[is.na(rows$y)]
    # This public extension dispatch reaches our shared direct row hook for
    # dibbles and preserves subclass slice callbacks and grouped remapping.
    dplyr::dplyr_row_slice(x, locations)
}

#' @export
inner_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE,
    suffix = c(".x", ".y"), ..., keep = NULL, na_matches = c("na", "never"),
    multiple = "all", unmatched = "drop", relationship = NULL) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_join_mutate(x, y, by, "inner", suffix, keep, na_matches,
        multiple, unmatched, relationship, rlang::current_env(), rlang::caller_env())
}
#' @export
left_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE,
    suffix = c(".x", ".y"), ..., keep = NULL, na_matches = c("na", "never"),
    multiple = "all", unmatched = "drop", relationship = NULL) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_join_mutate(x, y, by, "left", suffix, keep, na_matches,
        multiple, unmatched, relationship, rlang::current_env(), rlang::caller_env())
}
#' @export
right_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE,
    suffix = c(".x", ".y"), ..., keep = NULL, na_matches = c("na", "never"),
    multiple = "all", unmatched = "drop", relationship = NULL) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_join_mutate(x, y, by, "right", suffix, keep, na_matches,
        multiple, unmatched, relationship, rlang::current_env(), rlang::caller_env())
}
#' @export
full_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE,
    suffix = c(".x", ".y"), ..., keep = NULL, na_matches = c("na", "never"),
    multiple = "all", relationship = NULL) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_join_mutate(x, y, by, "full", suffix, keep, na_matches,
        multiple, "drop", relationship, rlang::current_env(), rlang::caller_env())
}
#' @export
semi_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE, ...,
                                       na_matches = c("na", "never")) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_join_filter(x, y, by, "semi", na_matches, rlang::current_env(), rlang::caller_env())
}
#' @export
anti_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE, ...,
                                       na_matches = c("na", "never")) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    .dibble_join_filter(x, y, by, "anti", na_matches, rlang::current_env(), rlang::caller_env())
}
#' @export
cross_join.dtatools_ref_data <- function(x, y, ..., copy = FALSE, suffix = c(".x", ".y")) {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    y <- dplyr::auto_copy(x, y, copy = copy)
    call <- rlang::current_env()
    by <- list(x = character(), y = character(), condition = character())
    vars <- .dibble_join_columns(dplyr::tbl_vars(x), dplyr::tbl_vars(y), by, suffix, FALSE, call)
    .as_mutation_data(x, allow_grouped = TRUE)
    if (is_dibble(y)) .as_mutation_data(y, allow_grouped = TRUE)
    x_view <- .dibble_join_view(x); y_view <- .dibble_join_view(y)
    x_columns <- stats::setNames(x_view$columns[vars$x$out], names(vars$x$out))
    y_columns <- stats::setNames(y_view$columns[vars$y$out], names(vars$y$out))
    # Public replication validates size multiplication before any payload gather.
    x_rows <- vctrs::vec_rep_each(seq_len(x_view$size), times = y_view$size)
    y_rows <- vctrs::vec_rep(seq_len(y_view$size), times = x_view$size)
    out <- .gather_dta_columns(x_columns, x_rows)
    out[names(y_columns)] <- .gather_dta_columns(y_columns, y_rows)
    .dibble_join_publish(out, length(x_rows), x, "cross_join()", list(x, y))
}
#' @export
nest_join.dtatools_ref_data <- function(x, y, by = NULL, copy = FALSE, keep = NULL,
    name = NULL, ..., na_matches = c("na", "never"), unmatched = "drop") {
    if (!is_dibble(x)) return(NextMethod())
    rlang::check_dots_empty()
    call <- rlang::current_env()
    user_env <- rlang::caller_env()
    .dibble_join_keep(keep, call)
    na_matches <- rlang::arg_match0(na_matches, c("na", "never"), error_call = call)
    if (is.null(name)) name <- rlang::as_label(rlang::enexpr(y)) else
        if (!rlang::is_string(name)) rlang::abort("`name` must be a string.", call = call)
    by <- .dibble_join_by(by, dplyr::tbl_vars(x), dplyr::tbl_vars(y), call, user_env)
    vars <- .dibble_join_columns(dplyr::tbl_vars(x), dplyr::tbl_vars(y), by, c("", ""), keep, call)
    y <- dplyr::auto_copy(x, y, copy = copy)
    .as_mutation_data(x, allow_grouped = TRUE)
    if (is_dibble(y)) .as_mutation_data(y, allow_grouped = TRUE)
    x_view <- .dibble_join_view(x); y_view <- .dibble_join_view(y)
    x_columns <- x_view$columns; y_columns <- y_view$columns
    keys <- .dibble_join_keys(x_columns, y_columns, vars, x_view$size, y_view$size, call)
    rows <- .dibble_join_matches(keys$x, keys$y, "nest", by, na_matches,
                                 "all", unmatched, NULL, call, user_env)
    locations <- vctrs::vec_split(rows$y, rows$x)$val
    out <- stats::setNames(x_columns[vars$x$out], names(vars$x$out))
    key_names <- names(keys$x)
    cast <- vctrs::vec_cast(vctrs::new_data_frame(out[key_names], n = x_view$size), keys$x, call = call)
    out[key_names] <- .plain_data_columns(cast)
    nested_columns <- stats::setNames(y_columns[vars$y$out], names(vars$y$out))
    nested <- lapply(locations, function(location) {
        # The matcher's nest-only zero sentinel means an empty nested frame.
        location <- location[location != 0L]
        .dibble_join_publish(.gather_dta_columns(nested_columns, location), length(location),
                             y, "nest_join()", list(y))
    })
    out[[name]] <- nested
    .dibble_join_publish(out, x_view$size, x, "nest_join()", list(x, y))
}
