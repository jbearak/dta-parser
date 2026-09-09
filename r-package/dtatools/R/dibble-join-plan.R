# Join naming and key policy adapted from dplyr 1.2.1 join-cols.R and
# join-by.R. Matching and publication are separate package-owned modules.
# Full source attribution and MIT license are retained in inst/NOTICE.
.dibble_join_type <- function(value) {
    type <- if (is.object(value)) paste(class(value), collapse = "/") else typeof(value)
    paste0("a <", type, "> value of length ", length(value))
}
.dibble_join_vars_label <- function(value) {
    if (is.logical(value)) value <- which(value)
    if (is.character(value)) value <- encodeString(value, quote = "`")
    if (length(value) < 2L) return(paste(value, collapse = ", "))
    paste0(paste(utils::head(value, -1L), collapse = ", "),
           if (length(value) == 2L) " and " else ", and ", value[[length(value)]])
}
.dibble_join_duplicate_names <- function(names, side, call) {
    duplicate <- duplicated(names)
    if (any(duplicate)) rlang::abort(c(
        sprintf("Input columns in `%s` must be unique.", side),
        x = paste0("Problem with ", .dibble_join_vars_label(names[duplicate]), ".")), call = call)
}

.dibble_join_keep <- function(keep, call) {
    if (!is.null(keep) && !rlang::is_bool(keep)) {
        rlang::abort(paste0("`keep` must be `TRUE`, `FALSE`, or `NULL`, not ",
                            .dibble_join_type(keep), "."), call = call)
    }
}

.dibble_join_by <- function(by, x_names, y_names, call, user_env) {
    cross <- (is.character(by) && !length(by)) ||
        (is.list(by) && length(by) == 2L &&
         is.character(by[["x"]]) && !length(by[["x"]]) &&
         is.character(by[["y"]]) && !length(by[["y"]]))
    if (cross) {
        lifecycle::deprecate_warn("1.1.0",
            I("Using `by = character()` to perform a cross join"),
            with = "cross_join()", env = call, user_env = user_env,
            id = "dplyr-by-for-cross-join")
        return(list(x = character(), y = character(), condition = character(),
                    filter = character(), cross = TRUE))
    }
    if (is.null(by)) {
        by <- intersect(x_names, y_names)
        if (!length(by)) rlang::abort(c(
            "`by` must be supplied when `x` and `y` have no common variables.",
            i = "Use `cross_join()` to perform a cross-join."), call = call)
        labels <- vapply(by, function(name) {
            if (is.na(name)) "NA" else if (identical(make.names(name), name)) name else
                paste0("`", gsub("`", "\\`", name, fixed = TRUE), "`")
        }, character(1))
        rlang::inform(paste0("Joining with `by = join_by(",
            paste(labels, collapse = ", "), ")`"))
    }
    if (inherits(by, "dplyr_join_by")) {
        by$cross <- FALSE
        return(by)
    }
    if (is.character(by)) {
        x <- names(by)
        y <- unname(by)
        if (is.null(x)) x <- y else x[x == ""] <- y[x == ""]
    } else if (is.list(by)) {
        x <- by[["x"]]; y <- by[["y"]]
        if (!is.character(x)) rlang::abort("`by$x` must evaluate to a character vector.")
        if (!is.character(y)) rlang::abort("`by$y` must evaluate to a character vector.")
        # The upstream expression construction recycles only for its validation;
        # the original key vectors retain their lengths for later policy checks.
        vctrs::vec_recycle_common(x, y)
    } else rlang::abort(paste0("`by` must be a (named) character vector, list, ",
                               "`join_by()` result, or NULL."), call = call)
    list(x = x, y = y, condition = rep.int("==", length(x)),
         filter = rep.int("none", length(x)), cross = FALSE)
}

.dibble_join_names <- function(vars, all_names, condition, side, call) {
    if (!is.character(vars)) rlang::abort(paste0(
        "Join columns in `", side, "` must be character vectors."), call = call)
    if (anyNA(vars)) rlang::abort(c(
        sprintf("Join columns in `%s` can't be `NA`.", side),
        x = paste0("Problem at position ", .dibble_join_vars_label(is.na(vars)), ".")), call = call)
    non_equi <- condition != "=="
    checked <- c(vars[!non_equi], unique(vars[non_equi]))
    if (anyDuplicated(checked)) rlang::abort(c(
        sprintf("Join columns in `%s` must be unique.", side),
        x = paste0("Problem with ", .dibble_join_vars_label(unique(checked[duplicated(checked)])), ".")), call = call)
    missing <- setdiff(checked, all_names)
    if (length(missing)) rlang::abort(c(paste0(
        "Join columns in `", side, "` must be present in the data."),
        x = paste0("Problem with ", .dibble_join_vars_label(missing), ".")), call = call)
}

.dibble_join_suffix <- function(x, y, suffix) {
    if (identical(suffix, "")) return(x)
    all <- c(y, x)
    duplicate <- duplicated(all)
    while (any(duplicate)) {
        all[duplicate] <- paste0(all[duplicate], suffix)
        duplicate <- duplicated(all)
    }
    all[seq_along(x) + length(y)]
}

.dibble_join_columns <- function(x_names, y_names, by, suffix, keep, call) {
    if (identical(keep, FALSE) && any(by$condition != "==")) {
        rlang::abort(paste0("Can't set `keep = FALSE` when using an inequality, ",
                           "rolling, or overlap join."), call = call)
    }
    # Duplicate input names precede checks of either side's key specification.
    .dibble_join_duplicate_names(x_names, "x", call)
    .dibble_join_duplicate_names(y_names, "y", call)
    .dibble_join_names(by$x, x_names, by$condition, "x", call)
    .dibble_join_names(by$y, y_names, by$condition, "y", call)
    if (!is.character(suffix) || length(suffix) != 2L) {
        rlang::abort(paste0("`suffix` must be a character vector of length 2, not ",
                            .dibble_join_type(suffix), "."), call = call)
    }
    if (anyNA(suffix)) rlang::abort("`suffix` can't be `NA`.", call = call)
    x_key <- stats::setNames(match(by$x, x_names), by$x)
    y_key <- stats::setNames(match(by$y, y_names), by$y)
    x_out <- stats::setNames(seq_along(x_names), x_names)
    if (is.null(keep) || identical(keep, FALSE)) {
        equality <- if (is.null(keep)) by$condition == "==" else rep.int(TRUE, length(by$x))
        ignored <- by$x[equality]
        check <- !x_names %in% ignored
        y_aux <- setdiff(y_names, c(by$x[equality], by$y[equality]))
        names(x_out)[check] <- .dibble_join_suffix(x_names[check],
                                                   c(ignored, y_aux), suffix[[1L]])
    } else names(x_out) <- .dibble_join_suffix(x_names, y_names, suffix[[1L]])
    y_out <- stats::setNames(seq_along(y_names),
                            .dibble_join_suffix(y_names, x_names, suffix[[2L]]))
    if (is.null(keep)) y_out <- y_out[!y_names %in% by$y[by$condition == "=="]] else
        if (identical(keep, FALSE)) y_out <- y_out[!y_names %in% by$y]
    list(x = list(key = x_key, out = x_out), y = list(key = y_key, out = y_out))
}

.dibble_join_keys <- function(x, y, vars, x_size, y_size, call) {
    x <- vctrs::new_data_frame(stats::setNames(x[vars$x$key], names(vars$x$key)), n = x_size)
    y <- vctrs::new_data_frame(stats::setNames(y[vars$y$key], names(vars$x$key)), n = y_size)
    ptype <- rlang::try_fetch(vctrs::vec_ptype2(x, y, x_arg = "", y_arg = "", call = call),
        vctrs_error_incompatible_type = function(cnd) {
            x_name <- cnd$x_arg
            y_name <- names(vars$y$key)[[match(cnd$y_arg, names(vars$x$key))]]
            .dibble_join_abort(c(sprintf("Can't join `x$%s` with `y$%s` due to incompatible types.",
                                          x_name, y_name),
                i = sprintf("`x$%s` is a <%s>.", x_name, vctrs::vec_ptype_full(cnd$x)),
                i = sprintf("`y$%s` is a <%s>.", y_name, vctrs::vec_ptype_full(cnd$y))),
                "dplyr_error_join_incompatible_type", call)
        })
    vctrs::vec_cast_common(x = x, y = y, .to = vctrs::vec_ptype_finalise(ptype), .call = call)
}
