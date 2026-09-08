# Summary chunk collection, deferred sizing, grouping transitions, and callback
# assembly adapt dplyr 1.2.1 summarise.R, reframe.R, group-map.R, group-nest.R,
# nest-by.R and src/summarise.cpp at 95740975. See installed NOTICE.
# Unlike mutate, chunks keep their computed sizes until all dots have run.
.dibble_summary_columns <- function(context, groups, size, dots, reframe) {
    caller <- if (reframe) "reframe()" else "summarise()"
    mask <- .new_dibble_expression_mask(context$columns, groups, size, caller)
    on.exit(mask$forget(), add = TRUE)
    adapter <- .dibble_dplyr_context()
    records <- list()
    warnings <- list()
    original <- NULL
    original_name <- ""
    run <- function() {
        result <- withCallingHandlers(tryCatch({
            for (index in seq_along(dots)) {
                original <- dots[[index]]
                original_name <- rlang::names2(dots)[[index]]
                name <- if (nzchar(original_name)) original_name else
                    .mask_expression_label(original)
                mask$set_group(0L)
                adapter$reset_column()
                # The established typed wrapper keeps across() inside each
                # group, so its sibling callbacks run before any installation.
                quo <- adapter$expand_summary(original, mask$helpers, original_name, index)
                typable <- .mask_expression_typable(original, context$columns)
                chunks <- vector("list", length(mask$rows))
                for (id in seq_along(mask$rows)) {
                    value <- mask$with_group(id, function(evaluate) {
                        value <- evaluate(quo)
                        if (is.null(value) || !typable) return(value)
                        prior <- function(target) {
                            if (target %in% names(mask$values()))
                                mask$helpers$current_cols(target)[[target]] else NULL
                        }
                        if (is.data.frame(value)) {
                            if (!nzchar(original_name)) {
                                value <- .metadata_copy(value)
                                for (target in names(value)) value[[target]] <-
                                    .typed_mask_value(value[[target]], prior(target), caller)
                            }
                            value
                        } else .typed_mask_value(value, prior(name), caller)
                    })
                    if (!is.null(value) && !vctrs::obj_is_vector(value)) {
                        rlang::abort(paste0("`", name, "` must be a vector."))
                    }
                    chunks[id] <- list(if (is.null(value)) NULL else .capture_dibble_nested(value))
                }
                nulls <- vapply(chunks, is.null, logical(1))
                if (all(nulls)) next
                if (any(nulls)) {
                    mask$set_group(which(nulls)[[1L]])
                    rlang::abort(c("Must return compatible vectors across groups.",
                        x = "Can't combine NULL and non NULL results."))
                }
                mask$set_group(0L)
                ptype <- vctrs::vec_ptype_common(!!!chunks)
                chunks <- vctrs::vec_cast_common(!!!chunks, .to = ptype)
                result <- vctrs::vec_c(!!!chunks, .ptype = ptype)
                install <- function(target, pieces, value) {
                    binding_chunks <- pieces
                    if (identical(groups$type, "rowwise") &&
                        all(vapply(pieces, function(x) vctrs::obj_is_list(x) &&
                            length(x) == 1L, logical(1)))) {
                        binding_chunks <- lapply(pieces, .subset2, 1L)
                    }
                    mask$add(target, value, binding_chunks)
                    records[[length(records) + 1L]] <<- list(name = target,
                        chunks = pieces, result = value, quo = original,
                        original_name = original_name)
                }
                if (!nzchar(original_name) && is.data.frame(result)) {
                    for (target in names(result)) install(target,
                        lapply(chunks, .subset2, target), result[[target]])
                } else install(name, chunks, result)
            }
            count <- nrow(groups$keys)
            sizes <- rep.int(1L, count)
            for (record in records) {
                original <- record$quo
                original_name <- record$original_name
                for (id in seq_len(count)) {
                    actual <- vctrs::vec_size(record$chunks[[id]])
                    mask$set_group(id)
                    if (!reframe && actual != 1L) {
                        rlang::abort(c(paste0("`", record$name,
                            "` must be size 1, not ", actual, "."),
                            i = "To return more or less than 1 row per group, use `reframe()`."))
                    }
                    if (reframe) {
                        if (sizes[[id]] == 1L) sizes[[id]] <- actual else
                        if (actual != 1L && actual != sizes[[id]]) rlang::abort(
                            paste0("`", record$name, "` must be size ", sizes[[id]],
                                " or 1, not ", actual, "."))
                    }
                }
            }
            columns <- list()
            for (record in records) {
                value <- record$result
                if (reframe && count) {
                    chunks <- Map(vctrs::vec_recycle, record$chunks, sizes)
                    value <- vctrs::vec_c(!!!chunks, .ptype = vctrs::vec_ptype(value))
                }
                columns[record$name] <- list(value)
            }
            list(columns = columns, sizes = sizes)
        }, error = function(condition) {
            .dibble_expression_condition(condition, original, original_name,
                mask, caller, error_class = "dplyr:::summarise_error")
        }), warning = function(condition) {
            id <- mask$current_id()
            type <- if (size) groups$type else "ungrouped"
            warnings[[length(warnings) + 1L]] <<- list(cnd = condition,
                name = original_name, expr = rlang::quo_get_expr(original), type = type,
                has_group_data = id != 0L, group_data = if (!id) NULL else switch(type,
                    grouped = list(id = id, group = mask$helpers$current_key()),
                    rowwise = list(id = id), list()), call = str2lang(caller))
            invokeRestart("muffleWarning")
        })
        if (length(warnings)) adapter$warnings(warnings, str2lang(caller))
        result
    }
    adapter$run(mask$helpers, run)
}

.dibble_summary <- function(data, dots, by = rlang::quo(NULL), groups_arg = NULL,
                            reframe = FALSE, caller_env = parent.frame()) {
    caller <- if (reframe) "reframe()" else "summarise()"
    context <- .begin_dibble_result(data, caller, "computed")
    groups <- .dibble_expression_groups(data, by)
    evaluated <- .dibble_summary_columns(context, groups, nrow(data), dots, reframe)
    keys <- groups$keys
    if (reframe) keys <- vctrs::vec_rep_each(keys, evaluated$sizes)
    columns <- .data_columns(keys)
    for (name in names(evaluated$columns)) columns[name] <-
        list(vctrs::vec_recycle(evaluated$columns[[name]], nrow(keys)))
    result <- tibble::new_tibble(columns, nrow = nrow(keys))
    # Bare references bypass mask-time typing in the established contract.
    # Final replacement promotion still applies, after all dependent dots ran.
    result <- .retype_changed_columns(result, context$columns,
        if (reframe) "`reframe()`" else "`summarise()`")
    grouping <- function(result) result
    if (!reframe) {
        grouped <- inherits(data, "grouped_df")
        rowwise <- inherits(data, "rowwise_df")
        policy <- groups_arg
        if (is.null(policy)) policy <- if (rowwise) "keep" else "drop_last"
        if (grouped || rowwise) {
            allowed <- c("drop", "keep", "rowwise", if (grouped) "drop_last")
            if (!is.character(policy) || length(policy) != 1L ||
                is.na(policy) || !policy %in% allowed) rlang::abort(
                paste0("`.groups` can't be ", rlang::as_label(policy), "."))
        }
        vars <- if (identical(policy, "rowwise") && (grouped || rowwise)) groups$names else
            if ((grouped || rowwise) && identical(policy, "keep")) groups$names else
            if (grouped && identical(policy, "drop_last")) head(groups$names, -1L) else character()
        is_rowwise <- identical(policy, "rowwise")
        grouping <- function(result) {
            if (length(vars) || is_rowwise) {
                class(result) <- c(if (is_rowwise) "rowwise_df" else "grouped_df", class(result))
                attr(result, "groups") <- .build_group_metadata(.data_columns(result), vars,
                    nrow(result), drop = if (rowwise) TRUE else .group_drop_default(data),
                    rowwise = is_rowwise)
            }
            result
        }
        inform <- getOption("dplyr.summarise.inform")
        verbose <- is.null(groups_arg) && (isTRUE(inform) ||
            (is.null(inform) && identical(topenv(caller_env), globalenv())))
        if (verbose && length(vars) && !is_rowwise &&
            (rowwise || identical(policy, "drop_last"))) {
            rlang::inform(c(if (rowwise)
                "`summarise()` has converted the output from a rowwise data frame to a grouped data frame." else
                "`summarise()` has regrouped the output.",
                i = paste0("Output is grouped by ", paste(vars, collapse = ", "), "."),
                i = paste0("Use `summarise(.groups = \"", policy, "\")` to silence this message.")))
        }
    }
    .finish_dibble_result(context, result, grouping = grouping)
}
