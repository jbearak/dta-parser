# Expression sequencing and group context adapt dplyr 1.2.1's data-mask.R,
# mutate.R, by.R and src/chop.cpp at 95740975. See installed NOTICE.
# Only dibble-dplyr-context.R accesses optional private dplyr interfaces.
.dibble_expression_groups <- function(data, by = rlang::quo(NULL)) {
    grouped <- inherits(data, "grouped_df")
    rowwise <- inherits(data, "rowwise_df")
    if (!rlang::quo_is_null(by) && (grouped || rowwise)) {
        rlang::abort(paste0("Can't supply `.by` when `.data` is a ",
                            if (grouped) "grouped" else "rowwise", " data frame."))
    }
    if (grouped || rowwise) {
        .validate_group_metadata(data)
        groups <- attr(data, "groups", exact = TRUE)
        keys <- groups[setdiff(names(groups), ".rows")]
        return(list(rows = groups$.rows, keys = keys, names = names(keys),
                    type = if (rowwise) "rowwise" else "grouped"))
    }
    vars <- if (rlang::quo_is_null(by)) character() else names(
        tidyselect::eval_select(by, data, allow_rename = FALSE))
    if (!length(vars)) {
        return(list(rows = list(seq_len(nrow(data))),
                    keys = tibble::new_tibble(list(), nrow = 1L),
                    names = character(), type = "ungrouped"))
    }
    info <- vctrs::vec_group_loc(.group_key_frame(.data_columns(data), vars, nrow(data)))
    list(rows = info$loc, keys = info$key, names = vars, type = "grouped")
}

# The mask owns isolated public column handles. Bindings capture a column
# generation and a fixed group, never the mutable current-group scalar. A
# call-local lifetime invalidates deferred reads and releases all retained
# generation payloads on normal return, errors and interrupts.
.new_dibble_expression_mask <- function(columns, groups, size, caller) {
    force(columns); force(groups); force(size); force(caller)
    if (is.null(names(columns)) || anyNA(names(columns)) ||
        any(!nzchar(names(columns))) || anyDuplicated(names(columns))) {
        rlang::abort("Can't transform a data frame with missing or duplicate names.")
    }
    state <- new.env(parent = emptyenv())
    state$alive <- TRUE
    state$id <- 0L
    state$generations <- list()
    state$expired <- new.env(parent = emptyenv())
    state$names <- character()
    state$current <- list()
    state$mask <- NULL
    rows <- groups$rows
    if (!length(rows)) rows <- list(integer())
    rowwise <- identical(groups$type, "rowwise")
    add <- function(name, value, chunks = NULL) {
        generation <- new.env(parent = emptyenv())
        generation$value <- .metadata_copy(value)
        generation$chunks <- chunks
        generation$used <- FALSE
        state$current[[name]] <- generation
        if (!name %in% state$names) state$names <- c(state$names, name)
        state$generations[[length(state$generations) + 1L]] <- rlang::new_weakref(generation)
    }
    for (name in names(columns)) add(name, columns[[name]])
    columns <- NULL
    obsolete <- function(name) {
        rlang::abort(c("Obsolete data mask.",
            x = paste0("Too late to resolve `", name, "` after the end of `dplyr::", caller, "`."),
            i = paste0("Did you save an object that uses `", name, "` lazily in a column in the `dplyr::", caller, "` expression ?")),
            call = NULL)
    }
    read <- function(generation, name, id) {
        if (!state$alive) return(get(name, state$expired, inherits = FALSE))
        generation$used <- TRUE
        if (is.null(generation$chunks)) {
            value <- generation$value
            generation$chunks <- if (identical(groups$type, "ungrouped")) list(value) else
                lapply(rows, function(index) {
                    if (rowwise && vctrs::obj_is_list(value)) {
                        if (!length(value)) {
                            ptype <- attr(value, "ptype", exact = TRUE)
                            if (is.null(ptype)) logical() else ptype
                        } else .metadata_copy(value[[index]])
                    } else .gather_dta_columns(list(value = value), index)[[1L]]
                })
        }
        if (id == -1L) return(generation$chunks)
        # Expansion before the first group sees empty column slices.
        if (id == 0L) return(vctrs::vec_slice(generation$value, integer()))
        generation$chunks[[id]]
    }
    binding <- function(generation, name, id) {
        force(generation); force(name); force(id)
        function() read(generation, name, id)
    }
    make_mask <- function(id = state$id) {
        bindings <- new.env(parent = emptyenv())
        for (name in names(state$current)) {
            makeActiveBinding(name, binding(state$current[[name]], name, id), bindings)
        }
        mask <- rlang::new_data_mask(bindings)
        mask$.data <- rlang::as_data_pronoun(bindings)
        mask
    }
    values <- function(vars = names(state$current)) {
        stats::setNames(lapply(vars, function(name) state$current[[name]]$value), vars)
    }
    current_cols <- function(vars) {
        stats::setNames(lapply(vars, function(name) read(state$current[[name]], name, state$id)), vars)
    }
    helpers <- list(
        get_current_group_size = function() if (state$id) length(rows[[state$id]]) else 0L,
        get_current_group_size_mutable = function() if (state$id) length(rows[[state$id]]) else 0L,
        get_current_group_id = function() state$id + 0L,
        get_current_group_id_mutable = function() state$id + 0L,
        current_key = function() if (!nrow(groups$keys)) groups$keys else
            vctrs::vec_slice(groups$keys, state$id),
        current_rows = function() if (state$id) rows[[state$id]] else integer(),
        current_vars = function() names(state$current),
        current_non_group_vars = function() setdiff(names(state$current), groups$names),
        get_current_data = function(groups = TRUE) {
            if (groups) values() else values(helpers$current_non_group_vars())
        },
        current_cols = current_cols,
        pick_current = function(vars) {
            out <- current_cols(vars)
            if (rowwise) for (name in vars) {
                if (vctrs::obj_is_list(state$current[[name]]$value)) out[name] <- list(list(out[[name]]))
            }
            tibble::new_tibble(out, nrow = helpers$get_current_group_size())
        },
        get_rlang_mask = function() make_mask(),
        is_grouped = function() identical(groups$type, "grouped"),
        is_rowwise = function() rowwise,
        get_keys = function() groups$keys,
        get_rows = function() rows,
        get_size = function() size,
        get_n_groups = function() nrow(groups$keys)
    )
    # One group frame can evaluate several expressions with shared temporary
    # bindings. Mutate still requests a fresh frame for each expression.
    with_group <- function(id, action) {
        state$id <- as.integer(id)
        state$mask <- make_mask()
        mask <- state$mask
        action(function(quo) rlang::eval_tidy(quo, mask))
    }
    evaluate <- function(quo, id) {
        with_group(id, function(evaluate) evaluate(quo))
    }
    expire <- function(name) {
        force(name)
        delayedAssign(name, obsolete(name), eval.env = environment(), assign.env = state$expired)
    }
    forget <- function() {
        for (name in state$names) expire(name)
        state$alive <- FALSE
        for (reference in state$generations) {
            generation <- rlang::wref_key(reference)
            if (!is.null(generation)) {
                generation$value <- NULL
                generation$chunks <- NULL
            }
        }
        state$generations <- state$current <- list()
        state$mask <- NULL
        groups <<- rows <<- NULL
    }
    list(helpers = helpers, evaluate = evaluate, with_group = with_group, add = add,
         remove = function(name) { state$current[[name]] <- NULL },
         values = values, rows = rows, groups = groups,
         resolve = function(name) {
             generation <- state$current[[name]]
             read(generation, name, -1L)
         },
         used = function() vapply(state$current, function(x) x$used, logical(1)),
         current_id = function() state$id,
         set_group = function(id) { state$id <- as.integer(id) }, forget = forget)
}

.dibble_expression_label <- function(quo, name) {
    label <- .mask_expression_label(quo)
    if (nzchar(name)) paste0(name, " = ", label) else label
}

.dibble_expression_condition <- function(condition, quo, name, mask, caller, warning = FALSE,
                                         error_class = "dplyr:::mutate_error") {
    message <- c(i = paste0("In argument: `", .dibble_expression_label(quo, name), "`."))
    id <- mask$current_id()
    if (id && !identical(mask$groups$type, "ungrouped")) {
        group <- if (identical(mask$groups$type, "rowwise")) paste0("row ", id) else {
            key <- mask$helpers$current_key()
            labels <- vapply(key, function(x) paste(format(x), collapse = ", "), character(1))
            paste0("group ", id, ": `", paste0(names(labels), " = ", labels, collapse = ", "), "`")
        }
        message <- c(message, i = paste0("In ", group, "."))
    }
    if (warning) {
        rlang::warn(c(paste0("There was a warning in `", caller, "`."), message),
                    parent = condition, call = str2lang(caller))
    } else {
        rlang::abort(message, parent = condition, call = str2lang(caller),
                     class = error_class)
    }
}

# Values are typed and captured before another expression can observe them.
# Expanded across expressions all finish their first pass before installation.
.dibble_evaluate_columns <- function(columns, groups, size, dots, caller = "mutate()",
                                      adapter = .dibble_dplyr_context()) {
    mask <- .new_dibble_expression_mask(columns, groups, size, caller)
    on.exit(mask$forget(), add = TRUE)
    modified <- character()
    warnings <- list()
    run <- function() {
        for (index in seq_along(dots)) {
            original <- dots[[index]]
            original_name <- rlang::names2(dots)[[index]]
            adapter$reset_column()
            withCallingHandlers(tryCatch({
                expanded <- adapter$expand(original, mask$helpers, original_name, index)
                pending <- list()
                for (item in expanded) {
                    quo <- item$quo
                    name <- item$name
                    adapter$column(item$column)
                    chunks <- vector("list", length(mask$rows))
                    # Inlined constants recycle to the whole table before chopping,
                    # unlike caller symbols and other expressions evaluated per group.
                    constant <- !rlang::quo_is_symbolic(quo) && !rlang::quo_is_null(quo)
                    current <- mask$values()
                    symbol <- rlang::quo_is_symbol(quo) && rlang::as_name(quo) %in% names(current)
                    preserved <- NULL
                    if (symbol) {
                        target <- rlang::as_name(quo)
                        chunks <- mask$resolve(target)
                        if (!(identical(groups$type, "rowwise") && vctrs::obj_is_list(current[[target]]))) {
                            preserved <- current[[target]]
                        } else {
                            sizes <- vapply(chunks, vctrs::vec_size, integer(1))
                            bad <- which(sizes != lengths(mask$rows) & sizes != 1L)
                            if (length(bad)) {
                                mask$set_group(bad[[1L]])
                                rlang::abort(paste0("`", name, "` must be size 1, not ", sizes[[bad[[1L]]]],
                                    ". Did you mean to wrap the result in `list()`?"))
                            }
                        }
                    } else if (constant) {
                        value <- vctrs::vec_recycle(rlang::quo_get_expr(quo), size)
                        chunks <- vctrs::vec_chop(value, mask$rows)
                    } else {
                        for (id in seq_along(mask$rows)) {
                            value <- mask$evaluate(quo, id)
                            if (!is.null(value)) {
                                if (!vctrs::obj_is_vector(value)) {
                                    rlang::abort(paste0("`", name, "` must be a vector."))
                                }
                                expected <- length(mask$rows[[id]])
                                actual <- vctrs::vec_size(value)
                                if (actual != expected && actual != 1L) {
                                    rlang::abort(paste0("`", name, "` must be size ", expected,
                                        " or 1, not ", actual, ".",
                                        if (identical(groups$type, "rowwise"))
                                            " Did you mean to wrap the result in `list()`?"))
                                }
                                value <- vctrs::vec_recycle(value, expected)
                            }
                            chunks[id] <- list(if (is.null(value)) NULL else .metadata_copy(value))
                        }
                    }
                    nulls <- vapply(chunks, is.null, logical(1))
                    if (any(nulls) && !all(nulls)) {
                        mask$set_group(which(nulls)[[1L]])
                        rlang::abort(c("Must return compatible vectors across groups.",
                                      x = "Can't combine NULL and non NULL results."))
                    }
                    if (all(nulls)) {
                        if (item$named) pending[name] <- list(NULL)
                        next
                    }
                    value <- if (!is.null(preserved)) preserved else if (length(chunks) == 1L) chunks[[1L]] else
                        vctrs::list_unchop(chunks, indices = mask$rows)
                    prior <- mask$values()
                    if (!item$named && is.data.frame(value)) {
                        for (position in seq_along(value)) {
                            target <- names(value)[[position]]
                            pending[target] <- list(.metadata_copy(.typed_mask_value(
                                value[[position]], prior[[target]], caller)))
                        }
                    } else {
                        pending[name] <- list(.metadata_copy(if (is.data.frame(value)) value else
                            .typed_mask_value(value, prior[[name]], caller)))
                    }
                }
                for (name in names(pending)) {
                    value <- pending[[name]]
                    if (is.null(value)) mask$remove(name) else mask$add(name, value)
                    modified <- union(modified, name)
                }
            }, error = function(condition) {
                .dibble_expression_condition(condition, original, original_name, mask, caller)
            }), warning = function(condition) {
                type <- if (size) groups$type else "ungrouped"
                id <- mask$current_id()
                group_data <- if (!id) NULL else switch(type,
                    grouped = list(id = id, group = mask$helpers$current_key()),
                    rowwise = list(id = id), list())
                warnings[[length(warnings) + 1L]] <<- list(cnd = condition,
                    name = original_name, expr = rlang::quo_get_expr(original),
                    type = type, has_group_data = id != 0L, group_data = group_data,
                    call = str2lang(caller))
                invokeRestart("muffleWarning")
            })
        }
        if (length(warnings)) adapter$warnings(warnings, str2lang(caller))
        list(columns = mask$values(), modified = modified, used = mask$used())
    }
    adapter$run(mask$helpers, run)
}

.dibble_modify_columns <- function(context, evaluated, data, groups, keep,
                                    before, after, transmute = FALSE) {
    columns <- evaluated$columns
    missing_keys <- setdiff(.group_vars(data), names(columns))
    if (length(missing_keys)) rlang::abort(paste0(
        "Grouping variables must remain in the data. Missing column `", missing_keys[[1L]], "`."))
    original <- names(context$columns)
    modified <- intersect(evaluated$modified, names(columns))
    if (transmute) {
        retain <- c(setdiff(groups$names, modified), modified)
    } else {
        retain <- if (keep == "all") names(columns) else {
            used <- evaluated$used
            selected <- switch(keep, used = names(used)[used],
                unused = names(used)[!used], none = character())
            intersect(names(columns), c(modified, groups$names, selected))
        }
    }
    result <- tibble::new_tibble(columns, nrow = nrow(data))
    if (!rlang::quo_is_null(before) || !rlang::quo_is_null(after)) {
        new <- setdiff(names(columns), original)
        locations <- .dibble_relocate_locations(result,
            rlang::expr(tidyselect::all_of(!!new)), before, after, parent.frame())
        columns <- columns[unname(locations)]
        names(columns) <- names(locations)
    }
    columns <- columns[names(columns) %in% retain]
    if (transmute) columns <- columns[retain]
    metadata <- context$metadata
    metadata$names <- names(columns)
    metadata$row.names <- .set_row_names(nrow(data))
    metadata$class <- setdiff(metadata$class, c("grouped_df", "rowwise_df"))
    metadata$groups <- NULL
    attributes(columns) <- metadata
    .finish_dibble_result(context, columns, grouping = function(result) {
        policy <- if (inherits(data, "grouped_df") &&
            any(.group_vars(data) %in% evaluated$modified)) "rebuild" else "columns"
        .restore_group_metadata(result, data, policy = policy)
    })
}

.dibble_mutate <- function(data, dots, by = rlang::quo(NULL), keep = "all",
                           before = rlang::quo(NULL), after = rlang::quo(NULL),
                           transmute = FALSE) {
    keep <- rlang::arg_match0(keep, c("all", "used", "unused", "none"))
    caller <- if (transmute) "transmute()" else "mutate()"
    context <- .begin_dibble_result(data, caller, "computed")
    groups <- .dibble_expression_groups(data, by)
    evaluated <- .dibble_evaluate_columns(context$columns, groups, nrow(data), dots, caller)
    .dibble_modify_columns(context, evaluated, data, groups, keep, before, after, transmute)
}

# Grouping verbs share metadata assembly with row/result operations. Computed
# keys evaluate on the whole ungrouped data, including when `.add` keeps keys.
.dibble_group_result <- function(data, context, columns, keys, drop = TRUE,
                                 rowwise = FALSE) {
    missing <- setdiff(keys, names(columns))
    if (length(missing)) rlang::abort(c("Must group by variables found in `.data`.",
        x = paste0("Column `", missing[[1L]], "` is not found.")))
    metadata <- context$metadata
    metadata$class <- c(if (rowwise) "rowwise_df" else if (length(keys)) "grouped_df",
        setdiff(metadata$class, c("grouped_df", "rowwise_df")))
    final_classes <- metadata$class
    metadata$class <- setdiff(metadata$class, c("grouped_df", "rowwise_df"))
    metadata$groups <- NULL
    metadata$names <- names(columns)
    metadata$row.names <- if (identical(context$caller, "ungroup()") &&
        !inherits(data, c("grouped_df", "rowwise_df"))) context$metadata$row.names else
        .set_row_names(nrow(data))
    attributes(columns) <- metadata
    .finish_dibble_result(context, columns, grouping = function(result) {
        class(result) <- final_classes
        attr(result, "groups") <- .build_group_metadata(
            .data_columns(result), keys, nrow(result), drop = drop, rowwise = rowwise)
        result
    })
}

.dibble_group_by <- function(data, dots, add, drop) {
    context <- .begin_dibble_result(data, "group_by()", "computed")
    .validate_group_metadata(data)
    # Pure references use their expression names without evaluating caller
    # bindings. Once one computed expression occurs, all dots share the mask.
    reference <- function(quo) {
        if (rlang::quo_is_symbol(quo)) return(rlang::as_name(quo) %in% names(context$columns))
        expr <- rlang::quo_get_expr(quo)
        rlang::is_call(expr, c("$", "[["), n = 2L) &&
            identical(expr[[2L]], quote(.data)) &&
            (rlang::is_symbol(expr[[3L]]) || rlang::is_string(expr[[3L]]))
    }
    computed <- any(nzchar(rlang::names2(dots))) || !all(vapply(dots, reference, logical(1)))
    if (computed) {
        groups <- list(rows = list(seq_len(nrow(data))), names = character(),
            keys = tibble::new_tibble(list(), nrow = 1L), type = "ungrouped")
        evaluated <- .dibble_evaluate_columns(context$columns, groups, nrow(data), dots, "group_by()")
        columns <- evaluated$columns
        keys <- evaluated$modified
    } else {
        columns <- context$columns
        keys <- vapply(dots, .mask_expression_label, character(1))
    }
    keys <- unique(keys)
    if (add) keys <- union(.group_vars(data), keys)
    .dibble_group_result(data, context, columns, keys, drop)
}
