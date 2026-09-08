# Row planning adapts dplyr 1.2.1 at 95740975: filter.R/src/filter.cpp,
# arrange.R, distinct.R and slice.R. See installed NOTICE for provenance.
# Every public row result passes one validated location vector to the gatherer.

.dibble_ungrouped_expressions <- function(size) {
    list(rows = list(seq_len(size)), names = character(),
         keys = tibble::new_tibble(list(), nrow = 1L), type = "ungrouped")
}

.dibble_with_row_mask <- function(context, groups, size, caller, action,
                                  warning_policy = "immediate", error_class = NULL) {
    mask <- .new_dibble_expression_mask(context$columns, groups, size, caller)
    on.exit(mask$forget(), add = TRUE)
    adapter <- .dibble_dplyr_context()
    original <- rlang::quo(NULL)
    original_name <- ""
    warnings <- list()
    track <- function(quo, name = "") {
        original <<- quo
        original_name <<- name
    }
    flush_warnings <- function() {
        if (length(warnings)) {
            records <- warnings
            warnings <<- list()
            adapter$warnings(records, str2lang(caller))
        }
    }
    evaluate_warnings <- function(action) {
        if (identical(warning_policy, "immediate")) return(action())
        value <- withCallingHandlers(action(), warning = function(condition) {
            id <- mask$current_id()
            type <- if (size) groups$type else "ungrouped"
            group_data <- if (!id) NULL else switch(type,
                grouped = list(id = id, group = mask$helpers$current_key()),
                rowwise = list(id = id), list())
            warnings[[length(warnings) + 1L]] <<- list(cnd = condition,
                name = original_name, expr = rlang::quo_get_expr(original),
                type = type, has_group_data = id != 0L, group_data = group_data,
                call = str2lang(caller))
            invokeRestart("muffleWarning")
        })
        if (identical(warning_policy, "expression")) flush_warnings()
        value
    }
    result <- tryCatch(adapter$run(mask$helpers, function() {
        value <- action(mask, adapter, track, evaluate_warnings)
        flush_warnings()
        value
    }), error = function(condition) {
            .dibble_expression_condition(condition, original, original_name, mask, caller,
                                         error_class = error_class)
        })
    result
}

.dibble_filter_locations <- function(context, groups, size, dots, invert = FALSE) {
    caller <- if (invert) "filter_out()" else "filter()"
    for (index in which(nzchar(rlang::names2(dots)))) {
        if (!is.logical(rlang::quo_get_expr(dots[[index]]))) {
            rlang::abort(c("We detected a named input.",
                i = "This usually means that you've used `=` instead of `==`."))
        }
    }
    .dibble_with_row_mask(context, groups, size, caller, function(mask, adapter, track, warn_eval) {
        expanded <- lapply(seq_along(dots), function(index) {
            track(dots[[index]], rlang::names2(dots)[[index]])
            adapter$expand_filter(dots[[index]], mask$helpers, index)
        })
        keep <- .Call(C_dtatools_filter_start, size)
        contiguous <- identical(groups$type, "ungrouped")
        for (id in seq_along(mask$rows)) {
            rows <- mask$rows[[id]]
            # Only the group planner's explicit ungrouped policy covers every
            # physical row. Keep its compact rows for n()/cur_group_rows(),
            # without forcing a full integer vector merely for reduction.
            reduction_rows <- if (contiguous) NULL else rows
            mask$with_group(id, function(evaluate) {
                for (index in seq_along(expanded)) {
                    track(dots[[index]], rlang::names2(dots)[[index]])
                    value <- warn_eval(function() evaluate(expanded[[index]]))
                    actual <- vctrs::vec_size(value)
                    if (actual != length(rows) && actual != 1L) {
                        rlang::abort(paste0("Predicate must be size ", length(rows),
                                           " or 1, not ", actual, "."))
                    }
                    dimensions <- dim(value)
                    matrix <- length(dimensions) == 2L && dimensions[[2L]] == 1L
                    if (!is.logical(value) || (length(dimensions) > 1L && !matrix)) {
                        rlang::abort("Predicate must be a logical vector.")
                    }
                    if (matrix && id == 1L) lifecycle::deprecate_warn(
                        "1.1.0", I("Using one column matrices in `filter()` or `filter_out()`"),
                        with = I("one dimensional logical vectors"),
                        user_env = globalenv(), always = TRUE,
                        id = "dplyr-filter-one-column-matrix")
                    # Reduction reads logical payloads without class/dim
                    # dispatch or temporary copies of the predicate.
                    .Call(C_dtatools_filter_reduce, keep, reduction_rows, value)
                }
            })
        }
        .Call(C_dtatools_filter_finish, keep, invert)
    }, warning_policy = "call")
}

.dibble_filter <- function(data, dots, by, preserve, invert = FALSE) {
    caller <- if (invert) "filter_out()" else "filter()"
    context <- .begin_dibble_result(data, caller, "rows")
    groups <- .dibble_expression_groups(data, by)
    locations <- .dibble_filter_locations(context, groups, nrow(data), dots, invert)
    .dibble_take_rows(context, locations, data, "slice", preserve)
}

.dibble_slice_locations <- function(context, groups, size, dots) {
    .dibble_with_row_mask(context, groups, size, "slice()", function(mask, adapter, track, warn_eval) {
        chunks <- lapply(seq_along(mask$rows), function(id) mask$with_group(id, function(evaluate) {
            values <- lapply(dots, function(quo) {
                track(quo)
                value <- evaluate(quo)
                if (is.matrix(value) && ncol(value) == 1L) {
                    lifecycle::deprecate_warn("1.1.0", I("Slicing with a 1-column matrix"),
                        user_env = globalenv(), always = TRUE,
                        id = "dplyr-slice-one-column-matrix")
                    value <- value[, 1L]
                }
                vctrs::vec_as_subscript(value, logical = "error", character = "error",
                    arg = .mask_expression_label(quo), call = NULL)
            })
            rlang::exec(vctrs::vec_c, !!!values, .ptype = integer())
        }))
        # All dots/groups evaluate before the combined sign/bounds policy.
        locations <- lapply(seq_along(chunks), function(id) {
            mask$set_group(id)
            rows <- mask$rows[[id]]
            local <- vctrs::num_as_location(chunks[[id]], length(rows),
                zero = "remove", oob = "remove", missing = "remove", call = NULL)
            rows[local]
        })
        rlang::exec(vctrs::vec_c, !!!locations, .ptype = integer())
    })
}

.dibble_slice <- function(data, dots, by, preserve) {
    if (any(nzchar(rlang::names2(dots)))) rlang::abort("Arguments in `...` must be unnamed.")
    context <- .begin_dibble_result(data, "slice()", "rows")
    groups <- .dibble_expression_groups(data, by)
    locations <- .dibble_slice_locations(context, groups, nrow(data), dots)
    .dibble_take_rows(context, locations, data, "slice", preserve)
}

.dibble_slice_size <- function(n, prop, allow_outsize = FALSE) {
    constant <- function(value, name) tryCatch(force(value), error = function(condition)
        rlang::abort(paste0("`", name, "` must be a constant."), parent = condition))
    if (missing(n) && missing(prop)) n <- 1L
    if (!missing(n) && !missing(prop)) rlang::abort("Must supply `n` or `prop`, but not both.")
    if (!missing(n)) {
        value <- constant(n, "n")
        if (!rlang::is_integerish(value, n = 1L) || is.na(value)) {
            rlang::abort("`n` must be a round number.")
        }
        proportional <- FALSE
    } else {
        value <- constant(prop, "prop")
        if (!is.numeric(value) || length(value) != 1L || is.na(value)) {
            rlang::abort("`prop` must be a number.")
        }
        proportional <- TRUE
    }
    force(value); force(allow_outsize); force(proportional)
    function(size) {
        amount <- if (proportional) value * size else value
        if (value < 0) return(max(0, min(size, ceiling(size + amount))))
        amount <- floor(amount)
        if (allow_outsize) amount else max(0, min(size, amount))
    }
}

.dibble_slice_helper <- function(data, by, size, kind, order_by = rlang::quo(NULL),
                                 weight_by = rlang::quo(NULL), with_ties = TRUE,
                                 na_rm = FALSE, replace = FALSE) {
    force(size); force(kind); force(with_ties); force(na_rm); force(replace)
    caller <- paste0("slice_", kind, "()")
    context <- .begin_dibble_result(data, caller, "rows")
    groups <- .dibble_expression_groups(data, by)
    locations <- .dibble_with_row_mask(context, groups, nrow(data), caller,
        function(mask, adapter, track, warn_eval) {
            chunks <- lapply(seq_along(mask$rows), function(id) mask$with_group(id, function(evaluate) {
                rows <- mask$rows[[id]]
                n <- length(rows)
                if (kind %in% c("min", "max")) {
                    track(order_by)
                    key <- evaluate(order_by)
                    vctrs::vec_check_size(key, n)
                    direction <- if (kind == "min") "asc" else "desc"
                    ranks <- vctrs::vec_rank(key,
                        ties = if (with_ties) "min" else "sequential",
                        direction = direction,
                        na_value = if (kind == "min") "largest" else "smallest")
                    keep <- ranks <= size(n)
                    if (na_rm) keep[!vctrs::vec_detect_complete(key)] <- FALSE
                    local <- which(keep)
                    local <- local[order(ranks[local])]
                } else if (kind == "sample") {
                    track(weight_by)
                    weights <- evaluate(weight_by)
                    if (!is.null(weights)) vctrs::vec_check_size(weights, n)
                    count <- size(n)
                    local <- if (count == 0L) integer() else
                        sample.int(n, count, prob = weights, replace = replace)
                } else {
                    count <- size(n)
                    local <- if (kind == "head") seq_len(count) else
                        if (count) seq.int(n - count + 1L, n) else integer()
                }
                rows[local]
            }))
            rlang::exec(vctrs::vec_c, !!!chunks, .ptype = integer())
        })
    .dibble_take_rows(context, locations, data, "slice")
}

.dibble_locale_proxy <- function(locale) {
    if (is.null(locale) || identical(locale, "C")) return(NULL)
    if (!rlang::is_string(locale)) rlang::abort("`.locale` must be a string or NULL.")
    if (!requireNamespace("stringi", quietly = TRUE) ||
        utils::packageVersion("stringi") < "1.5.3") {
        rlang::abort("stringi >=1.5.3 is required to arrange in a different locale.")
    }
    if (!locale %in% stringi::stri_locale_list()) {
        rlang::abort("`.locale` must be one of the locales within `stringi::stri_locale_list()`.")
    }
    function(x) stringi::stri_sort_key(x, locale = locale)
}

.dibble_order_locations <- function(keys, size, directions, locale) {
    legacy <- if (is.null(locale)) getOption("dplyr.legacy_locale") else NULL
    if (!is.null(legacy)) {
        lifecycle::deprecate_warn("1.2.0", I("`options(dplyr.legacy_locale =)`"),
            user_env = globalenv(), id = "dplyr-legacy-locale-option")
        if (!rlang::is_bool(legacy)) {
            rlang::abort("Global option `dplyr.legacy_locale` must be a single `TRUE` or `FALSE`.")
        }
    }
    frame <- vctrs::new_data_frame(keys, n = size)
    if (isTRUE(legacy)) return(.group_order_legacy(frame, directions))
    collate <- .dibble_locale_proxy(locale)
    if (!length(keys)) return(seq_len(size))
    ranks <- vctrs::vec_rank(frame, ties = "sequential", direction = directions,
        na_value = ifelse(directions == "desc", "smallest", "largest"),
        chr_proxy_collate = collate)
    locations <- integer(size)
    locations[ranks] <- seq_len(size)
    locations
}

.dibble_arrange <- function(data, dots, by_group, locale) {
    context <- .begin_dibble_result(data, "arrange()", "rows")
    .validate_group_metadata(data)
    if (by_group) dots <- c(lapply(.group_vars(data), function(name)
        rlang::new_quosure(rlang::sym(name))), dots)
    directions <- rep("asc", length(dots))
    for (index in seq_along(dots)) {
        quo <- dots[[index]]
        if (rlang::quo_is_call(quo, "desc", ns = c("", "dplyr"))) {
            expr <- rlang::quo_get_expr(quo)
            if (length(expr) != 2L) rlang::abort("`desc()` must be called with exactly one argument.")
            dots[[index]] <- rlang::new_quosure(expr[[2L]], rlang::quo_get_env(quo))
            directions[[index]] <- "desc"
        }
    }
    size <- nrow(data)
    keys <- .dibble_with_row_mask(context, .dibble_ungrouped_expressions(size), size,
        "arrange()", function(mask, adapter, track, warn_eval) lapply(seq_along(dots), function(index) {
            quo <- dots[[index]]
            track(quo)
            mask$set_group(0L)
            # Named expansion keeps each key independent: pick expands before
            # evaluation, while across retains its runtime helper behavior.
            value <- warn_eval(function() {
                expanded <- adapter$expand(quo, mask$helpers, paste0("..", index), index)
                mask$evaluate(expanded[[1L]]$quo, 1L)
            })
            if (is.null(value)) return(NULL)
            vctrs::vec_recycle(.metadata_copy(value), size)
        }), warning_policy = "expression", error_class = "dplyr:::mutate_error")
    present <- !vapply(keys, is.null, logical(1))
    keys <- stats::setNames(keys[present], as.character(which(present)))
    locations <- .dibble_order_locations(keys, size, directions[present], locale)
    .dibble_take_rows(context, locations, data, "slice")
}

.dibble_distinct <- function(data, dots, keep_all) {
    context <- .begin_dibble_result(data, "distinct()", "computed")
    .validate_group_metadata(data)
    columns <- context$columns
    modified <- character()
    if (!length(dots)) {
        keys <- names(columns)
    } else {
        # Caller-backed symbols are computed inputs too; only actual columns
        # can bypass evaluation and its sequential Stata typing boundary.
        pure <- !any(nzchar(rlang::names2(dots))) && all(vapply(dots,
            function(quo) rlang::quo_is_symbol(quo) &&
                rlang::as_name(quo) %in% names(columns), logical(1)))
        if (pure) keys <- vapply(dots, .mask_expression_label, character(1)) else {
            evaluated <- .dibble_evaluate_columns(columns,
                .dibble_ungrouped_expressions(nrow(data)), nrow(data), dots, "distinct()")
            columns <- evaluated$columns
            keys <- evaluated$modified
            modified <- evaluated$modified
        }
        missing <- setdiff(keys, names(columns))
        if (length(missing)) rlang::abort(paste0("`", missing[[1L]], "` not found in `.data`."))
        keys <- unique(keys)
        keys <- c(setdiff(.group_vars(data), keys), keys)
    }
    locations <- vctrs::vec_unique_loc(vctrs::new_data_frame(columns[keys], n = nrow(data)))
    context$columns <- if (keep_all || !length(dots)) columns else columns[keys]
    policy <- if (any(.group_vars(data) %in% modified)) "rebuild" else "slice"
    .dibble_take_rows(context, locations, data, policy)
}
