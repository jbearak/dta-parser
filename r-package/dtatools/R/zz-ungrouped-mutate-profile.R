# Load-time source qualification for ungrouped native mutate.
.ungrouped_mutate_state <- new.env(parent = emptyenv())
.ungrouped_mutate_state$pinned <- FALSE
.ungrouped_mutate_state$disabled_after_dplyr_unload <- FALSE
.ungrouped_mutate_state$error <- NULL
.ungrouped_mutate_state$libname <- NULL
.ungrouped_mutate_state$pkgname <- NULL

.ungrouped_mutate_pin_if_ready <- function() {
    if (isTRUE(.ungrouped_mutate_state$disabled_after_dplyr_unload))
        return(invisible(FALSE))
    if (!isNamespaceLoaded('dplyr')) return(invisible(FALSE))
    state <- .ungrouped_mutate_state
    if (isTRUE(state$pinned)) return(invisible(TRUE))
    state$pinned <- tryCatch(
        .ungrouped_mutate_init(state$libname, state$pkgname),
        error = function(e) {
            state$error <- conditionMessage(e)
            FALSE
        })
    invisible(state$pinned)
}

.ungrouped_mutate_disable_after_dplyr_unload <- function() {
    .ungrouped_mutate_state$disabled_after_dplyr_unload <- TRUE
    .ungrouped_mutate_state$pinned <- FALSE
    invisible(.native_admission_call(C_dtatools_probe_mutate_mode, FALSE))
}

.ungrouped_mutate_init <- function(libname, pkgname) {
    stopifnot(isTRUE(.grouped_probe_artifact_profile(libname, pkgname)))
    manifest_path <- file.path(libname, pkgname, 'extdata',
                               'ungrouped-create-public-roots.csv')
    manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
    stopifnot(identical(names(manifest),
                        c('kind', 'binding_pkg', 'name', 'owner', 'alias')),
              nrow(manifest) == 300L)
    source_envs <- new.env(parent = emptyenv())
    source_env <- function(owner) {
        if (!exists(owner, source_envs, inherits = FALSE)) {
            path <- system.file('R', owner, package = owner)
            stopifnot(nzchar(path))
            target <- new.env(parent = emptyenv())
            base::lazyLoad(path, envir = target)
            assign(owner, target, envir = source_envs)
        }
        get(owner, source_envs, inherits = FALSE)
    }
    roots <- vector('list', nrow(manifest))
    for (i in seq_len(nrow(manifest))) {
        kind <- manifest$kind[[i]]
        pkg <- manifest$binding_pkg[[i]]
        name <- manifest$name[[i]]
        where <- switch(kind,
            namespace = asNamespace(pkg),
            namespace_primitive = asNamespace(pkg),
            baseenv = baseenv(),
            primitive = baseenv(),
            method = get('.__S3MethodsTable__.', asNamespace(pkg),
                         inherits = FALSE),
            stop('unknown ungrouped root kind'))
        stopifnot(exists(name, where, inherits = FALSE),
                  !bindingIsActive(name, where))
        actual <- get(name, where, inherits = FALSE)
        if (kind %in% c('primitive', 'baseenv', 'namespace_primitive')) {
            canonical <- if (nzchar(manifest$alias[[i]]))
                manifest$alias[[i]] else name
            frozen <- base::.Primitive(canonical)
            stopifnot(identical(actual, frozen))
            roots[[i]] <- list(where, name, actual)
        } else {
            frozen <- get(name, source_env(manifest$owner[[i]]),
                          inherits = FALSE)
            stopifnot(typeof(actual) == 'closure',
                      typeof(frozen) == 'closure')
            if (kind == 'method')
                stopifnot(identical(get(name, environment(actual),
                                        inherits = FALSE), actual))
            roots[[i]] <- list(where, name, actual, frozen)
        }
    }
    absent_path <- file.path(libname, pkgname, 'extdata',
                             'grouped-absent-methods.csv')
    absent <- utils::read.csv(absent_path, stringsAsFactors = FALSE)
    stopifnot(identical(names(absent), c('package', 'name')),
              nrow(absent) == 213L)
    absent_roots <- lapply(seq_len(nrow(absent)), function(i) {
        table <- get('.__S3MethodsTable__.',
                     asNamespace(absent$package[[i]]), inherits = FALSE)
        list(table, absent$name[[i]])
    })
    operators <- lapply(c('+', 'abs', '-'), get, envir = baseenv(),
                        inherits = FALSE)
    stopifnot(isTRUE(.Call(C_dtatools_probe_pin_operators, operators)),
              isTRUE(.Call(C_dtatools_probe_pin_public, roots)),
              isTRUE(.Call(C_dtatools_probe_pin_absent, absent_roots)),
              isTRUE(.Call(C_dtatools_probe_guard_public, NULL)))
    invisible(.Call(C_dtatools_probe_mutate_mode, TRUE))
    TRUE
}
