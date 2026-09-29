# Additional public closures reached by the grouped bracket's ordinary route.
# The grouped dplyr profile already pins the other reached roots. Both use
# the same installed-source and native artifact qualification.
.probe_grouped_bracket_state <- new.env(parent = emptyenv())
# Scratch-only ordinary stage census. The R stage assignments call no closure.
.probe_grouped_stage_state <- new.env(parent = emptyenv())
.probe_grouped_stage_state$phase <- 0L
.probe_grouped_stage_state$step <- 0L

.probe_grouped_bracket_init <- function() {
    tryCatch({
        .probe_installed_public_profile()
        manifest <- list(base = c('startsWith', 'match', 'identity',
                                  'suspendInterrupts', 'sys.call'),
                         rlang = c('is_formula', 'quo_is_missing',
                                   'enquo0', 'enquo', 'enquos',
                                   'arg_match0', 'enexpr', 'inject',
                                   'is_false', 'is_true', 'node_cdr'),
                         vctrs = c('vec_arith', 'vec_data', 'obj_check_vector'))
        records <- list()
        for (pkg in names(manifest)) {
            path <- system.file('R', pkg, package = pkg)
            stopifnot(nzchar(path))
            db <- new.env(parent = emptyenv())
            base::lazyLoad(path, envir = db)
            ns <- asNamespace(pkg)
            for (name in manifest[[pkg]]) {
                live <- get0(name, ns, inherits = FALSE)
                frozen <- get0(name, db, inherits = FALSE)
                stopifnot(typeof(live) == 'closure',
                          typeof(frozen) == 'closure',
                          all(.native_admission_call(
                              C_probe_public48_source_qualification,
                              live, frozen)))
                records[[length(records) + 1L]] <-
                    list(label = name, env = ns, frozen = frozen,
                         live = live)
            }
        }
        state <- .probe_grouped_bracket_state
        state$labels <- vapply(records, `[[`, '', 'label')
        state$envs <- lapply(records, `[[`, 'env')
        state$frozen <- lapply(records, `[[`, 'frozen')
        state$live <- lapply(records, `[[`, 'live')
        state$function_primitive <- base::.Primitive('function')
        stopifnot(identical(get('function', baseenv(), inherits = FALSE),
                            state$function_primitive))
        state$pinned <- isTRUE(.native_admission_call(
            C_dtatools_probe_grouped_bracket_pin, state))
    }, error = function(e) {
        .probe_grouped_bracket_state$pinned <- FALSE
        .probe_grouped_bracket_state$error <- conditionMessage(e)
    })
    invisible(NULL)
}
