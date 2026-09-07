list(own = list(list(group = 1L, calls = pairlist(proof_eval(d, 
    list(1:2, 3L), tibble(g = c("a", "b")), "g", q, named = FALSE), proof_adapter$run(adapter_mask, 
    function() {
        quoes <- if (expand) proof_adapter$expand(quo, adapter_mask, 
            named) else list(quo)
        out <- vector("list", length(quoes))
        names(out) <- names(quoes)
        for (k in seq_along(quoes)) {
            q <- quoes[[k]]
            proof_adapter$column(q)
            chunks <- vector("list", length(rows))
            for (i in seq_along(rows)) {
                state$id <- as.integer(i)
                state$current <- lapply(data, function(value) {
                  if (rowwise && is.list(value) && length(rows[[i]]) == 
                    1L) value[[rows[[i]]]] else vctrs::vec_slice(value, 
                    rows[[i]])
                })
                state$mask <- make_mask(state$current)
                chunks[i] <- list(rlang::eval_tidy(q, data = state$mask))
            }
            out[[k]] <- chunks
        }
        attr(out, "methods") <- unique(state$calls)
        attr(out, "expanded") <- length(quoes) != 1L || !identical(rlang::quo_get_expr(quoes[[1L]]), 
            rlang::quo_get_expr(quo))
        out
    }), action(), rlang::eval_tidy(q, data = state$mask), alias(x:y, 
    make_fn()), is_missing(.fns), make_fn())), list(group = 1L, 
    calls = pairlist(proof_eval(d, list(1:2, 3L), tibble(g = c("a", 
        "b")), "g", q, named = FALSE), proof_adapter$run(adapter_mask, 
        function() {
            quoes <- if (expand) proof_adapter$expand(quo, adapter_mask, 
                named) else list(quo)
            out <- vector("list", length(quoes))
            names(out) <- names(quoes)
            for (k in seq_along(quoes)) {
                q <- quoes[[k]]
                proof_adapter$column(q)
                chunks <- vector("list", length(rows))
                for (i in seq_along(rows)) {
                  state$id <- as.integer(i)
                  state$current <- lapply(data, function(value) {
                    if (rowwise && is.list(value) && length(rows[[i]]) == 
                      1L) value[[rows[[i]]]] else vctrs::vec_slice(value, 
                      rows[[i]])
                  })
                  state$mask <- make_mask(state$current)
                  chunks[i] <- list(rlang::eval_tidy(q, data = state$mask))
                }
                out[[k]] <- chunks
            }
            attr(out, "methods") <- unique(state$calls)
            attr(out, "expanded") <- length(quoes) != 1L || !identical(rlang::quo_get_expr(quoes[[1L]]), 
                rlang::quo_get_expr(quo))
            out
        }), action(), rlang::eval_tidy(q, data = state$mask), alias(x:y, 
        make_fn()), quo_eval_fns(fns_quo, mask = fns_quo_env, 
        error_call = error_call), eval_tidy(quo({
        sentinel_env <<- current_env()
        !!quo
    })), ~make_fn(), make_fn())), list(group = 2L, calls = pairlist(proof_eval(d, 
    list(1:2, 3L), tibble(g = c("a", "b")), "g", q, named = FALSE), proof_adapter$run(adapter_mask, 
    function() {
        quoes <- if (expand) proof_adapter$expand(quo, adapter_mask, 
            named) else list(quo)
        out <- vector("list", length(quoes))
        names(out) <- names(quoes)
        for (k in seq_along(quoes)) {
            q <- quoes[[k]]
            proof_adapter$column(q)
            chunks <- vector("list", length(rows))
            for (i in seq_along(rows)) {
                state$id <- as.integer(i)
                state$current <- lapply(data, function(value) {
                  if (rowwise && is.list(value) && length(rows[[i]]) == 
                    1L) value[[rows[[i]]]] else vctrs::vec_slice(value, 
                    rows[[i]])
                })
                state$mask <- make_mask(state$current)
                chunks[i] <- list(rlang::eval_tidy(q, data = state$mask))
            }
            out[[k]] <- chunks
        }
        attr(out, "methods") <- unique(state$calls)
        attr(out, "expanded") <- length(quoes) != 1L || !identical(rlang::quo_get_expr(quoes[[1L]]), 
            rlang::quo_get_expr(quo))
        out
    }), action(), rlang::eval_tidy(q, data = state$mask), alias(x:y, 
    make_fn()), is_missing(.fns), make_fn())), list(group = 2L, 
    calls = pairlist(proof_eval(d, list(1:2, 3L), tibble(g = c("a", 
        "b")), "g", q, named = FALSE), proof_adapter$run(adapter_mask, 
        function() {
            quoes <- if (expand) proof_adapter$expand(quo, adapter_mask, 
                named) else list(quo)
            out <- vector("list", length(quoes))
            names(out) <- names(quoes)
            for (k in seq_along(quoes)) {
                q <- quoes[[k]]
                proof_adapter$column(q)
                chunks <- vector("list", length(rows))
                for (i in seq_along(rows)) {
                  state$id <- as.integer(i)
                  state$current <- lapply(data, function(value) {
                    if (rowwise && is.list(value) && length(rows[[i]]) == 
                      1L) value[[rows[[i]]]] else vctrs::vec_slice(value, 
                      rows[[i]])
                  })
                  state$mask <- make_mask(state$current)
                  chunks[i] <- list(rlang::eval_tidy(q, data = state$mask))
                }
                out[[k]] <- chunks
            }
            attr(out, "methods") <- unique(state$calls)
            attr(out, "expanded") <- length(quoes) != 1L || !identical(rlang::quo_get_expr(quoes[[1L]]), 
                rlang::quo_get_expr(quo))
            out
        }), action(), rlang::eval_tidy(q, data = state$mask), alias(x:y, 
        make_fn()), quo_eval_fns(fns_quo, mask = fns_quo_env, 
        error_call = error_call), eval_tidy(quo({
        sentinel_env <<- current_env()
        !!quo
    })), ~make_fn(), make_fn()))), reference = list(list(group = 1L, 
    calls = pairlist(dplyr::mutate(group_by(d, g), !!q), mutate.data.frame(group_by(d, 
        g), !!q), mutate_cols(.data, dplyr_quosures(...), by), withCallingHandlers(for (i in seq_along(dots)) {
        poke_error_context(dots, i, mask = mask)
        context_poke("column", old_current_column)
        new_columns <- mutate_col(dots[[i]], data, mask, new_columns)
    }, error = dplyr_error_handler(dots = dots, mask = mask, 
        bullets = mutate_bullets, error_call = error_call, error_class = "dplyr:::mutate_error"), 
        warning = dplyr_warning_handler(state = warnings_state, 
            mask = mask, error_call = error_call)), mutate_col(dots[[i]], 
        data, mask, new_columns), mask$eval_all_mutate(quo), eval(), alias(x:y, 
        make_fn()), is_missing(.fns), make_fn())), list(group = 1L, 
    calls = pairlist(dplyr::mutate(group_by(d, g), !!q), mutate.data.frame(group_by(d, 
        g), !!q), mutate_cols(.data, dplyr_quosures(...), by), withCallingHandlers(for (i in seq_along(dots)) {
        poke_error_context(dots, i, mask = mask)
        context_poke("column", old_current_column)
        new_columns <- mutate_col(dots[[i]], data, mask, new_columns)
    }, error = dplyr_error_handler(dots = dots, mask = mask, 
        bullets = mutate_bullets, error_call = error_call, error_class = "dplyr:::mutate_error"), 
        warning = dplyr_warning_handler(state = warnings_state, 
            mask = mask, error_call = error_call)), mutate_col(dots[[i]], 
        data, mask, new_columns), mask$eval_all_mutate(quo), eval(), alias(x:y, 
        make_fn()), quo_eval_fns(fns_quo, mask = fns_quo_env, 
        error_call = error_call), eval_tidy(quo({
        sentinel_env <<- current_env()
        !!quo
    })), ~make_fn(), make_fn())), list(group = 2L, calls = pairlist(dplyr::mutate(group_by(d, 
    g), !!q), mutate.data.frame(group_by(d, g), !!q), mutate_cols(.data, 
    dplyr_quosures(...), by), withCallingHandlers(for (i in seq_along(dots)) {
    poke_error_context(dots, i, mask = mask)
    context_poke("column", old_current_column)
    new_columns <- mutate_col(dots[[i]], data, mask, new_columns)
}, error = dplyr_error_handler(dots = dots, mask = mask, bullets = mutate_bullets, 
    error_call = error_call, error_class = "dplyr:::mutate_error"), 
    warning = dplyr_warning_handler(state = warnings_state, mask = mask, 
        error_call = error_call)), mutate_col(dots[[i]], data, 
    mask, new_columns), mask$eval_all_mutate(quo), eval(), alias(x:y, 
    make_fn()), is_missing(.fns), make_fn())), list(group = 2L, 
    calls = pairlist(dplyr::mutate(group_by(d, g), !!q), mutate.data.frame(group_by(d, 
        g), !!q), mutate_cols(.data, dplyr_quosures(...), by), withCallingHandlers(for (i in seq_along(dots)) {
        poke_error_context(dots, i, mask = mask)
        context_poke("column", old_current_column)
        new_columns <- mutate_col(dots[[i]], data, mask, new_columns)
    }, error = dplyr_error_handler(dots = dots, mask = mask, 
        bullets = mutate_bullets, error_call = error_call, error_class = "dplyr:::mutate_error"), 
        warning = dplyr_warning_handler(state = warnings_state, 
            mask = mask, error_call = error_call)), mutate_col(dots[[i]], 
        data, mask, new_columns), mask$eval_all_mutate(quo), eval(), alias(x:y, 
        make_fn()), quo_eval_fns(fns_quo, mask = fns_quo_env, 
        error_call = error_call), eval_tidy(quo({
        sentinel_env <<- current_env()
        !!quo
    })), ~make_fn(), make_fn()))), parsed_source_matches = list(
    `R/context.R::n` = list(formals = TRUE, body = TRUE), `R/context.R::cur_group` = list(
        formals = TRUE, body = TRUE), `R/context.R::cur_group_id` = list(
        formals = TRUE, body = TRUE), `R/context.R::cur_group_rows` = list(
        formals = TRUE, body = TRUE), `R/context.R::group_labels_details` = list(
        formals = TRUE, body = TRUE), `R/context.R::cur_group_label` = list(
        formals = TRUE, body = TRUE), `R/context.R::cur_group_data` = list(
        formals = TRUE, body = TRUE), `R/context.R::stop_mask_type` = list(
        formals = TRUE, body = TRUE), `R/context.R::cnd_data` = list(
        formals = TRUE, body = TRUE), `R/context.R::cur_column` = list(
        formals = TRUE, body = TRUE), `R/context.R::context_poke` = list(
        formals = TRUE, body = TRUE), `R/context.R::context_peek_bare` = list(
        formals = TRUE, body = TRUE), `R/context.R::context_peek` = list(
        formals = TRUE, body = TRUE), `R/context.R::context_local` = list(
        formals = TRUE, body = TRUE), `R/context.R::peek_column` = list(
        formals = TRUE, body = TRUE), `R/context.R::local_column` = list(
        formals = TRUE, body = TRUE), `R/context.R::peek_mask` = list(
        formals = TRUE, body = TRUE), `R/context.R::local_mask` = list(
        formals = TRUE, body = TRUE), `R/across.R::across` = list(
        formals = TRUE, body = TRUE), `R/across.R::if_any` = list(
        formals = TRUE, body = TRUE), `R/across.R::if_all` = list(
        formals = TRUE, body = TRUE), `R/across.R::c_across` = list(
        formals = TRUE, body = TRUE), `R/across.R::across_glue_mask` = list(
        formals = TRUE, body = TRUE), `R/across.R::across_setup` = list(
        formals = TRUE, body = TRUE), `R/across.R::uninline` = list(
        formals = TRUE, body = TRUE), `R/across.R::data_mask_top` = list(
        formals = TRUE, body = TRUE), `R/across.R::quo_set_env_to_data_mask_top` = list(
        formals = TRUE, body = TRUE), `R/across.R::c_across_setup` = list(
        formals = TRUE, body = TRUE), `R/across.R::new_dplyr_quosure` = list(
        formals = TRUE, body = TRUE), `R/across.R::dplyr_quosure_name` = list(
        formals = TRUE, body = TRUE), `R/across.R::dplyr_quosures` = list(
        formals = TRUE, body = TRUE), `R/across.R::expand_if_across` = list(
        formals = TRUE, body = TRUE), `R/across.R::expand_across` = list(
        formals = TRUE, body = TRUE), `R/across.R::as_across_fn_call` = list(
        formals = TRUE, body = TRUE), `R/across.R::is_inlinable_lambda` = list(
        formals = TRUE, body = TRUE), `R/across.R::across_missing_cols_deprecate_warn` = list(
        formals = TRUE, body = TRUE), `R/across.R::c_across_missing_cols_deprecate_warn` = list(
        formals = TRUE, body = TRUE), `R/across.R::df_unpack` = list(
        formals = TRUE, body = TRUE), `R/across.R::apply_unpack_spec` = list(
        formals = TRUE, body = TRUE), `R/across.R::quo_eval_fns` = list(
        formals = TRUE, body = TRUE), `R/across.R::is_inlinable_function` = list(
        formals = TRUE, body = TRUE), `R/across.R::is_inlinable_formula` = list(
        formals = TRUE, body = TRUE), `R/pick.R::pick` = list(
        formals = TRUE, body = TRUE), `R/pick.R::expand_pick` = list(
        formals = TRUE, body = TRUE), `R/pick.R::expand_pick_quo` = list(
        formals = TRUE, body = TRUE), `R/pick.R::expand_pick_call` = list(
        formals = TRUE, body = TRUE), `R/pick.R::eval_pick` = list(
        formals = TRUE, body = TRUE), `R/pick.R::as_pick_selection` = list(
        formals = TRUE, body = TRUE), `R/pick.R::as_pick_expansion` = list(
        formals = TRUE, body = TRUE), `R/pick.R::dplyr_pick_tibble` = list(
        formals = TRUE, body = TRUE), `R/pick.R::stop_pick_empty` = list(
        formals = TRUE, body = TRUE)))
