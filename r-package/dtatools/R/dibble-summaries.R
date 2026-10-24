# Summary chunk collection, deferred sizing, grouping transitions, and callback
# assembly adapt dplyr 1.2.1 summarise.R, reframe.R, group-map.R, group-nest.R,
# nest-by.R and src/summarise.cpp at 95740975. See installed NOTICE.
# Unlike mutate, chunks keep their computed sizes until all dots have run.
.dibble_summary_ptype <- function(chunks, name, groups, size) {
    # Adapt common_handler/cnd_bullet_combine_details using the owned key plan.
    # Formatting runs only after common typing fails, outside an active group.
    detail <- function(value, argument) {
        id <- suppressWarnings(as.integer(sub("^\\.\\.", "", argument)))
        if (length(id) != 1L || is.na(id) || id < 1L || id > nrow(groups$keys))
            return(NULL)
        where <- if (!size || identical(groups$type, "ungrouped")) "" else
            if (identical(groups$type, "rowwise")) paste0("row ", id) else {
                key <- vctrs::vec_slice(groups$keys, id)
                labels <- vapply(key, pillar::format_glimpse, character(1))
                paste0("group ", id, ": `",
                    paste0(names(labels), " = ", labels, collapse = ", "), "`")
            }
        paste0("Result of type <", vctrs::vec_ptype_full(value), "> for ", where, ".")
    }
    # The selector keeps each branch's compiled promise and uses the captured
    # if, so a declined check runs the original call and adds no R calls.
    withCallingHandlers(.native_admission_call(C_dtatools_select_branch,
        .native_admission_branches(.summary_ptype_settles(chunks),
            vctrs::vec_ptype_common(!!!chunks[.summary_ptype_kept(chunks)]),
            vctrs::vec_ptype_common(!!!chunks)),
        .native_admission_if), error = function(condition) {
        details <- c(detail(condition$x, condition$x_arg),
                     detail(condition$y, condition$y_arg))
        if (!length(details)) details <- conditionMessage(condition)
        rlang::abort(c(paste0("`", name, "` must return compatible vectors across groups."),
            stats::setNames(details, rep.int("i", length(details)))),
            class = "dplyr:::error_incompatible_combine", parent = NULL)
    })
}

# Build copies of the reducer that receives only the first chunks when the
# others are skipped, of the helper it calls, of the caller_env() default
# that a fold forces, and of the primitives that promote mixed storage.
.summary_ptype_dependencies <- if (
    identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
    identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
) list(
    utils::removeSource(vctrs::vec_ptype_common), utils::removeSource(rlang::list2),
    asNamespace("vctrs"), .Primitive("::"), .Primitive("{"), .Primitive(".External2"),
    utils::removeSource(rlang::caller_env), .Primitive("+"),
    .Primitive("is.character"), .Primitive("switch")
) else NULL

# The routine objects that the reducers pass to .External2, as vctrs and
# rlang bound them when dtatools loaded. Build copies cannot hold them.
.summary_routine_state <- new.env(parent = emptyenv())
.summary_routine_state$routines <- NULL

# vctrs folds the per-group results into a common type one chunk at a time.
# When every chunk is a canonical Stata numeric, the native check confirms
# that each fold would reach the canonical method with its whole graph
# unchanged, so a fold is a pure function of the running type and the next
# chunk's attributes. The check also confirms that vctrs::vec_ptype_common()
# is unchanged, so handing it fewer chunks cannot be observed. The kept
# chunks are the first three and the first chunk with each distinct set of
# attributes. Folding them in order, each type from the third fold on must
# come back unchanged when folded with every distinct set seen so far. Then
# no skipped chunk can change the type, and vctrs folds only the kept chunks.
# The native check costs about as much as six folds, so fewer than eight
# chunks are always folded in full. chunks stays an unforced promise, so the
# check reads the caller's frame, where vctrs is called. The captured
# predicates add no R calls when the check declines.
.summary_ptype_settles <- function(chunks) {
    fold <- .native_admission_call(C_dtatools_summary_ptype_method,
                                   .double_combine_state, .metadata_state,
                                   .summary_ptype_dependencies, .summary_routine_state)
    .native_admission_and(.native_admission_not(.native_admission_is_null(fold)),
        !is.null(kept <- .summary_ptype_kept(chunks)) && tryCatch({
            firsts <- attr(kept, "firsts", exact = TRUE)
            ptype <- fold(chunks[[1L]], chunks[[2L]])
            settled <- TRUE
            for (index in kept[-(1:2)]) {
                ptype <- fold(ptype, chunks[[index]])
                for (first in firsts[firsts <= index]) {
                    settled <- settled &&
                        identical(fold(ptype, chunks[[first]]), ptype, attrib.as.set = FALSE)
                }
            }
            settled
        }, error = function(condition) FALSE, warning = function(condition) FALSE,
        message = function(condition) FALSE))
}

# The chunks vctrs must fold, with the first chunk of each distinct set of
# attributes as their "firsts". NULL past four distinct sets, or when the
# check would fold more often than the chunks it skips.
.summary_ptype_kept <- function(chunks) {
    # One native call scans the chunks when `attributes()` would return
    # each one's attributes as stored (ADR 0056).
    kept <- .Call(C_dtatools_summary_ptype_kept, chunks)
    if (!is.logical(kept)) return(kept)
    .summary_ptype_kept_r(chunks)
}

.summary_ptype_kept_r <- function(chunks) {
    seen <- list()
    firsts <- integer()
    for (index in seq_along(chunks)) {
        current <- attributes(chunks[[index]])
        known <- FALSE
        for (attributes in seen) known <- known || identical(attributes, current)
        if (!known) {
            if (length(seen) == 4L) return(NULL)
            seen[[length(seen) + 1L]] <- current
            firsts <- c(firsts, index)
        }
    }
    kept <- c(1:3, firsts[firsts > 3L])
    if (length(firsts) > 1L) {
        # The check folds the kept chunks and every first seen after each
        # kept fold from the third, and vctrs folds the kept chunks again.
        checks <- sum(vapply(kept[-(1:2)], function(index) sum(firsts <= index), integer(1)))
        if (2L * (length(kept) - 1L) + checks + 6L >= length(chunks) - 1L) return(NULL)
    }
    structure(kept, firsts = firsts)
}

# Build copies of the calls that cast the chunks to the common type and
# combine them, of the helper they call, and of the caller_env() default
# that the cast forces.
.summary_combine_dependencies <- if (
    identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
    identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
) list(
    utils::removeSource(vctrs::vec_cast_common), utils::removeSource(vctrs::vec_c),
    utils::removeSource(rlang::list2), asNamespace("vctrs"), .Primitive("::"),
    .Primitive("{"), .Primitive(".External2"), utils::removeSource(rlang::caller_env),
    .Primitive("+")
) else NULL

# After the common type, vctrs casts every chunk to it and then combines the
# casts, at two method calls per chunk. When every chunk is a canonical Stata
# double with its attributes in the order the cast writes them, and the
# common type is one too, each cast returns a copy of its chunk. The native
# check confirms that, and that both vctrs calls and every method they reach
# are unchanged. It then copies the chunks as the casts would, assembles the
# result as double assembly does, and assigns both in the caller's frame, or
# returns FALSE. When every chunk is a compact Stata numeric, or the metadata
# proxy over one that a summary usually returns, with only its storage and
# class, and its storage widens to a compact common type, the check instead
# constructs each cast and the result in that storage, as the cast and
# restore methods do.
# The arguments stay unforced promises, so the check can read the caller's
# frame, where the vctrs calls otherwise run.
.summary_combine <- function(chunks, ptype) {
    .native_admission_call(C_dtatools_summary_combine,
                           .double_combine_state, .metadata_state,
                           .summary_combine_dependencies, .summary_routine_state)
}

# The functions that the common type and combine checks read, besides the
# numeric helper profile: the vctrs reducers and assembly, the package
# helpers and methods of the combine graph, the vctrs and rlang functions
# it reaches, and the delayed entries that registration put in the vctrs
# and base method tables for those methods. A first grouped summary reaches
# many of them only through the vctrs calls the checks replace, so each
# check found a lazy binding and declined, and vctrs folded and cast every
# group's result through R methods. `dependencies` is the combine profile,
# which holds the vctrs namespace and the two method tables the checks read.
.settle_summary_bindings <- function(dependencies) {
    package <- topenv()
    for (name in c(".dta_promote", ".dta_common_ptype", ".dta_ptype",
                   ".reconcile_dta_metadata", ".restore_dta_metadata",
                   ".dta_classes_from", ".dta_combine_value_labels",
                   ".reconcile_dta_metadata_attributes", ".apply_haven_labelled_class",
                   ".dta_snapshot", ".cast_to_dta", ".compact_dta_storage_matches",
                   "vec_ptype2.dta_numeric.dta_numeric", "vec_cast.dta_numeric.dta_numeric",
                   "vec_proxy.dta_numeric", "vec_restore.dta_numeric",
                   "as.double.dta_numeric")) {
        get(name, envir = package, inherits = FALSE)
    }
    for (name in c("vec_ptype_common", "vec_cast_common", "vec_c", "list_unchop",
                   "vec_ptype_finalise.default", "names<-.vctrs_vctr",
                   "names_repair_missing")) {
        get(name, envir = dependencies[[1L]], inherits = FALSE)
    }
    rlang::check_dots_empty0
    rlang::current_env
    for (name in c("vec_ptype2.dta_numeric.dta_numeric", "vec_cast.dta_numeric.dta_numeric",
                   "vec_proxy.dta_numeric", "vec_restore.dta_numeric")) {
        get0(name, envir = dependencies[[8L]], inherits = FALSE)
    }
    get0("names<-.vctrs_vctr", envir = dependencies[[9L]], inherits = FALSE)
    invisible(NULL)
}

# `mean()`, `min()`, `max()` or `sum()` of one column, with `na.rm` left
# out or given as a logical, takes one native call over the column's group
# chunks after the first group when each later group's evaluation would
# reach the package's method and its native result (ADR 0061). The first
# group runs through the loop, which reads the column and stops in a
# debugger a one-shot `debugonce()` set. It returns the captured results and
# their sizes for the later groups as the loop builds them, or NULL, and the
# loop goes on. Given the first group's result, `first`, and the frame that
# combines the results, `caller`, it can instead return the combined vector
# as `result` (ADR 0062). With `combined`, for mutate(), it also declines
# when a group is empty, since only when none is do the loop's results wait
# for the combiners to recycle them, and when a group's rows have a class or
# are ALTREP, whose length could run R code before the loop would.
.summary_planned <- function(quo, mask, groups, combined = FALSE, first = NULL,
                             caller = NULL) {
    if (identical(groups$type, "rowwise") || !rlang::is_quosure(quo)) return(NULL)
    sized <- .size_planned(quo, mask, groups, combined)
    if (!is.null(sized)) return(sized)
    expression <- rlang::quo_get_expr(quo)
    # A classed expression's `[[` and length() methods would run R code the
    # loop does not.
    if (!is.call(expression) || is.object(expression) ||
        !is.symbol(expression[[1L]])) return(NULL)
    generic <- as.character(expression[[1L]])
    if (!generic %in% c("mean", "sum", "min", "max")) return(NULL)
    arguments <- as.list(expression)[-1L]
    labels <- rlang::names2(arguments)
    na.rm <- FALSE
    if (length(arguments) == 2L && identical(labels, c("", "na.rm")) &&
        is.logical(arguments[[2L]])) {
        na.rm <- arguments[[2L]]
    } else if (length(arguments) != 1L || nzchar(labels[[1L]])) return(NULL)
    column <- arguments[[1L]]
    if (!is.symbol(column)) return(NULL)
    column <- as.character(column)
    # The mask's pronouns and R's `..1` take names that begin with a dot,
    # which no Stata variable does.
    if (startsWith(column, ".")) return(NULL)
    if (combined && !.Call(C_dtatools_plan_rows, mask$rows, TRUE)) return(NULL)
    # A column named for the generic or a method would be read while R
    # looks for them in the mask.
    current <- mask$helpers$current_vars()
    looked_up <- c(generic, paste0(generic, ".dta_numeric"),
                   if (generic != "mean") "Summary.dta_numeric")
    if (!column %in% current || any(looked_up %in% current)) return(NULL)
    chunks <- mask$cached(column)
    if (is.null(chunks)) return(NULL)
    env <- rlang::quo_get_env(quo)
    top <- topenv(env)
    found <- .Call(C_dtatools_summary_plan_admitted, generic, env, top, environment())
    if (is.null(found) || isdebugged(found[[1L]]) || isdebugged(found[[2L]])) return(NULL)
    .Call(C_dtatools_summary_plan, chunks, generic, env, top, environment(), first, caller,
          list(.double_combine_state, .metadata_state, .summary_ptype_dependencies,
               .summary_combine_dependencies, .summary_routine_state))
}

# n(), row_number() in a mutate(), and a literal number in a summarise(),
# whose results depend only on the groups' sizes, for every group after the
# first in one native call (ADR 0063). A mutate() recycles a literal before
# it reaches here, and row_number() in a summary returns more than one value.
.size_planned <- function(quo, mask, groups, combined) {
    expression <- rlang::quo_get_expr(quo)
    # A classed expression's `[[` and length() methods would run R code the
    # loop does not.
    if (is.object(expression)) return(NULL)
    namespace <- NULL
    if (is.call(expression)) {
        if (length(expression) != 1L || is.null(.size_plan_dependencies) ||
            !isNamespaceLoaded("dplyr")) return(NULL)
        head <- expression[[1L]]
        # count() and tally() summarise `dplyr::n()`.
        qualified <- is.call(head) && length(head) == 3L &&
            identical(head[[1L]], quote(`::`)) && identical(head[[2L]], quote(dplyr))
        if (qualified) head <- head[[3L]]
        if (!is.symbol(head)) return(NULL)
        generic <- as.character(head)
        if (!generic %in% c("n", if (combined) "row_number")) return(NULL)
        # A column named for the function would be read while R looks for it.
        if ((if (qualified) "::" else generic) %in% mask$helpers$current_vars()) return(NULL)
        namespace <- asNamespace("dplyr")
        found <- .Call(C_dtatools_size_plan_admitted, expression, rlang::quo_get_env(quo),
                       mask$helpers, namespace, .size_plan_dependencies)
        if (is.null(found) || any(vapply(found, isdebugged, logical(1)))) return(NULL)
    } else if (combined || !(is.double(expression) || is.integer(expression)) ||
               !is.null(attributes(expression)) || length(expression) != 1L) {
        return(NULL)
    }
    # The mutate() loop recycles an empty group's result itself, which the
    # native call checks.
    .Call(C_dtatools_size_plan, mask$rows, expression, combined, rlang::quo_get_env(quo),
          mask$helpers, namespace, .size_plan_dependencies)
}

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
                known <- rep.int(NA_integer_, length(mask$rows))
                # The mask's columns change only after the groups run, so
                # whether the result replaces one is known before (ADR 0055).
                replaces <- name %in% mask$helpers$current_vars()
                install <- function(target, pieces, value, sizes = NULL) {
                    binding_chunks <- pieces
                    if (identical(groups$type, "rowwise") &&
                        all(vapply(pieces, function(x) vctrs::obj_is_list(x) &&
                            length(x) == 1L, logical(1)))) {
                        binding_chunks <- lapply(pieces, .subset2, 1L)
                    }
                    mask$add(target, value, binding_chunks, positions = is.null(pieces))
                    records[[length(records) + 1L]] <<- list(name = target,
                        chunks = pieces, result = value, quo = original,
                        original_name = original_name, sizes = sizes)
                }
                assembled <- NULL
                for (id in seq_along(mask$rows)) {
                    # After the first group, a summary of one column can take
                    # one native call for the rest, which gives what the loop
                    # would (ADR 0061), or the vector the steps below combine
                    # from it (ADR 0062).
                    if (id == 2L && !replaces &&
                        !is.null(planned <- .summary_planned(quo, mask, groups,
                            first = if (!reframe) chunks[[1L]], caller = environment()))) {
                        if (!is.null(planned$result)) assembled <- planned$result else {
                            chunks[-1L] <- planned$chunks
                            known[-1L] <- planned$known
                        }
                        # The loop leaves the mask at its last group.
                        mask$set_group(length(mask$rows))
                        break
                    }
                    value <- mask$with_group(id, function(evaluate) {
                        value <- evaluate(quo)
                        if (is.null(value) || !typable) return(value)
                        if (is.data.frame(value)) {
                            prior <- function(target) {
                                if (target %in% mask$helpers$current_vars())
                                    mask$helpers$current_cols(target)[[target]] else NULL
                            }
                            if (!nzchar(original_name)) {
                                value <- .metadata_copy(value)
                                for (target in names(value)) value[[target]] <-
                                    .retyped_column(value[[target]], prior(target),
                                        length(value[[target]]), caller)
                            }
                            value
                        } else .retyped_column(value,
                            if (replaces) mask$helpers$current_cols(name)[[name]],
                            length(value), caller)
                    })
                    # A bare vector or a package Stata numeric is a vector
                    # of its length, which the native call returns without
                    # its vec_proxy() method (ADR 0052).
                    measured <- .Call(C_dtatools_chunk_size, value)
                    if (!is.null(measured)) known[[id]] <- measured else
                    if (!is.null(value) && !vctrs::obj_is_vector(value)) {
                        rlang::abort(paste0("`", name, "` must be a vector."))
                    }
                    chunks[id] <- list(if (is.null(value)) NULL else .capture_dibble_nested(value))
                }
                if (!is.null(assembled)) {
                    # Each result has size one, and the mask splits the
                    # combined vector into them when a later expression reads it.
                    mask$set_group(0L)
                    install(name, NULL, assembled, rep.int(1L, length(mask$rows)))
                    next
                }
                nulls <- vapply(chunks, is.null, logical(1))
                if (all(nulls)) next
                if (any(nulls)) {
                    mask$set_group(which(nulls)[[1L]])
                    rlang::abort(c("Must return compatible vectors across groups.",
                        x = "Can't combine NULL and non NULL results."))
                }
                mask$set_group(0L)
                # Chunks that share their attributes are their own casts.
                shared <- .shared_dta_ptype(chunks)
                ptype <- if (is.null(shared)) .dibble_summary_ptype(chunks, name, groups, size) else shared
                # A settled native combine assigns the casts to chunks and
                # the combined vector to result. A decline runs the vctrs calls.
                result <- if (!is.null(shared)) .combine_shared_dta(chunks, shared) else
                    .native_admission_call(C_dtatools_select_branch,
                        .native_admission_branches(.summary_combine(chunks, ptype), result, {
                            chunks <- vctrs::vec_cast_common(!!!chunks, .to = ptype)
                            vctrs::vec_c(!!!chunks, .ptype = ptype)
                        }), .native_admission_if)
                if (!nzchar(original_name) && is.data.frame(result)) {
                    for (target in names(result)) install(target,
                        lapply(chunks, .subset2, target), result[[target]])
                } else install(name, chunks, result, known)
            }
            count <- nrow(groups$keys)
            sizes <- rep.int(1L, count)
            chunk_sizes <- vector("list", length(records))
            for (record_index in seq_along(records)) {
                record <- records[[record_index]]
                chunk_sizes[[record_index]] <- numeric(count)
                original <- record$quo
                original_name <- record$original_name
                known <- record$sizes
                # When every group's size is known to be one, no check can
                # fail, and the mask ends at the last group as the loop
                # leaves it.
                if (!reframe && length(known) == count && !anyNA(known) &&
                    all(known == 1L)) {
                    chunk_sizes[[record_index]] <- as.double(known)
                    if (count) mask$set_group(count)
                    next
                }
                for (id in seq_len(count)) {
                    actual <- if (!is.null(known) && !is.na(known[[id]])) known[[id]] else
                        vctrs::vec_size(record$chunks[[id]])
                    chunk_sizes[[record_index]][[id]] <- actual
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
            for (record_index in seq_along(records)) {
                record <- records[[record_index]]
                value <- record$result
                if (reframe && count && any(chunk_sizes[[record_index]] != sizes)) {
                    chunks <- Map(vctrs::vec_recycle, record$chunks, sizes)
                    value <- vctrs::vec_c(!!!chunks, .ptype = vctrs::vec_ptype(value))
                }
                columns[record$name] <- list(value)
            }
            list(columns = columns, sizes = sizes)
        }, error = function(condition) {
            .dibble_expression_condition(condition, original, original_name,
                mask, caller, error_class = NULL)
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
            if (grouped && identical(policy, "drop_last")) utils::head(groups$names, -1L) else character()
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
