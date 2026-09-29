# These 24 gen-only closures extend the installed 58-root public profile.
# The shared external RDB/native fingerprint check qualifies both sets.
.probe_gen_extra_manifest <- list(
    base = c('unlist', 'sprintf', 'intersect', 'startsWith',
             'suspendInterrupts'),
    rlang = c('enquo', 'enquos0', 'as_quosure', 'is_bare_formula',
              'is_symbolic', 'new_quosure', 'quos', 'quo_is_null',
              'is_missing', 'maybe_missing'),
    vctrs = c('new_data_frame', 'vec_group_loc', 'vec_slice',
              'list_unchop', 'vec_recycle', 'vec_proxy_equal',
              'vec_proxy'),
    dtatools = c('vec_proxy_equal.dta_numeric', 'gen')
)

.probe_gen_extra_state <- new.env(parent = emptyenv())
.probe_gen_wrapper_state <- new.env(parent = emptyenv())
.probe_grouped_gen_state <- new.env(parent = emptyenv())

# Grouped evaluation reaches these public base closures in addition to the
# ungrouped graph. The group-key data.frame method must remain absent.
.probe_grouped_gen_manifest <- list(
    base = c('order', 'makeActiveBinding', 'local', 'vector')
)

.probe_grouped_gen_init <- function() {
    tryCatch({
        if (is.null(.probe_gen_extra_state$bodies))
            stop('gen profile unavailable')
        .probe_installed_public_profile()
        records <- list()
        for (pkg in names(.probe_grouped_gen_manifest)) {
            path <- system.file('R', pkg, package = pkg)
            if (!nzchar(path)) stop('missing grouped source database')
            db <- new.env(parent = emptyenv())
            base::lazyLoad(path, envir = db)
            env <- if (pkg == 'base') baseenv() else asNamespace(pkg)
            for (name in .probe_grouped_gen_manifest[[pkg]]) {
                current <- get0(name, envir = env, inherits = FALSE)
                frozen <- get0(name, envir = db, inherits = FALSE)
                if (!identical(typeof(current), 'closure') ||
                    !identical(typeof(frozen), 'closure'))
                    stop('grouped source closure unavailable')
                check <- .native_admission_call(
                    C_probe_public48_source_qualification,
                    current, frozen)
                if (!is.logical(check) || length(check) != 4L ||
                    !all(check))
                    stop('grouped source qualification failed')
                records[[length(records) + 1L]] <- list(
                    name = name, env = env, live = current,
                    frozen = frozen)
            }
        }
        if (length(records) != 4L) stop('grouped source manifest count')
        state <- .probe_grouped_gen_state
        state$labels <- vapply(records, `[[`, '', 'name')
        state$envs <- lapply(records, `[[`, 'env')
        state$frozen <- lapply(records, `[[`, 'frozen')
        state$live <- lapply(records, `[[`, 'live')
        state$bodies <- NULL
        state$environments <- NULL
        state$attributes <- NULL
        primitives <- c(as_integer = 'as.integer', as_character = 'as.character',
                        is_symbol = 'is.symbol', is_atomic = 'is.atomic',
                        names = 'names', seq_len = 'seq_len')
        for (index in seq_along(primitives)) {
            field <- paste0('primitive_', names(primitives)[[index]])
            state[[field]] <- get(primitives[[index]], baseenv(),
                                  inherits = FALSE)
        }
        if (!isTRUE(.native_admission_call(
                C_dtatools_probe_gen_extra_capture, state)))
            stop('grouped source capture failed')
    }, error = function(e) NULL)
    invisible(NULL)
}

.probe_gen_extra_init <- function() {
    tryCatch({
        if (is.null(.probe_public48_state$live) ||
            is.null(.probe_wrapper_state$helper))
            stop('shared public profile unavailable')
        # This checks the exact external RDB and native artifacts before
        # fetching any additional installed source.
        .probe_installed_public_profile()
        records <- list()
        for (pkg in names(.probe_gen_extra_manifest)) {
            path <- system.file('R', pkg, package = pkg)
            if (!nzchar(path)) stop('missing gen source database')
            db <- new.env(parent = emptyenv())
            base::lazyLoad(path, envir = db)
            env <- if (pkg == 'base') baseenv() else asNamespace(pkg)
            for (name in .probe_gen_extra_manifest[[pkg]]) {
                current <- get0(name, envir = env, inherits = FALSE)
                frozen <- get0(name, envir = db, inherits = FALSE)
                if (!identical(typeof(current), 'closure') ||
                    !identical(typeof(frozen), 'closure'))
                    stop('gen source closure unavailable')
                check <- .native_admission_call(
                    C_probe_public48_source_qualification,
                    current, frozen)
                if (!is.logical(check) || length(check) != 4L ||
                    !all(check))
                    stop('gen source qualification failed')
                records[[length(records) + 1L]] <- list(
                    name = name, env = env, live = current,
                    frozen = frozen)
            }
        }
        if (length(records) != 24L) stop('gen source manifest count')
        # These registered S3-table bindings can still be delayed on this
        # pinned build. Resolve and qualify them once at load so the per-call
        # guard compares value bindings without invoking their promises.
        method_roots <- list(
            list('vec_proxy_equal.dta_numeric', 2L, 'dtatools'),
            list('vec_proxy.dta_numeric', 2L, 'dtatools'),
            list('names<-.vctrs_vctr', 1L, 'vctrs')
        )
        for (root in method_roots) {
            method <- get0(root[[1L]],
                           envir = .probe_s3_state$tables[[root[[2L]]]],
                           inherits = FALSE)
            if (!identical(method,
                           get0(root[[1L]],
                                envir = asNamespace(root[[3L]]),
                                inherits = FALSE)))
                stop('gen S3 method qualification failed')
        }
        state <- .probe_gen_extra_state
        state$labels <- vapply(records, `[[`, '', 'name')
        state$envs <- lapply(records, `[[`, 'env')
        state$frozen <- lapply(records, `[[`, 'frozen')
        state$live <- lapply(records, `[[`, 'live')
        state$bodies <- NULL
        state$environments <- NULL
        state$attributes <- NULL
        primitives <- c(length = 'length', bracket2 = '[[',
                        minus = '-', names_set = 'names<-', list = 'list')
        for (index in seq_along(primitives)) {
            field <- paste0('primitive_', names(primitives)[[index]])
            state[[field]] <- get(primitives[[index]], envir = baseenv(),
                                  inherits = FALSE)
        }
        if (!isTRUE(.native_admission_call(
                C_dtatools_probe_gen_extra_capture, state)))
            stop('gen source capture failed')
        wrapper <- .probe_gen_wrapper_state
        wrapper$frozen <- state$frozen[[match('gen', state$labels)]]
        wrapper$internal <- .probe_wrapper_state$internal
        wrapper$live <- state$live[[match('gen', state$labels)]]
        wrapper$repl <- wrapper$live
        if (!isTRUE(.native_admission_call(
                C_dtatools_probe_wrapper_capture, wrapper)))
            stop('gen wrapper capture failed')
    }, error = function(e) NULL)
    invisible(NULL)
}
