# Load-time source and artifact qualification of the grouped producer.
.grouped_probe_state <- new.env(parent = emptyenv())
.grouped_probe_state$pinned <- FALSE
.grouped_probe_state$error <- NULL
.grouped_probe_state$libname <- NULL
.grouped_probe_state$pkgname <- NULL

.grouped_probe_pin_if_ready <- function() {
    # dplyr is optional. Namespace load and non-dplyr operations must not
    # resolve its database, or load tools and the rest of this profile.
    if (!isNamespaceLoaded('dplyr')) return(invisible(FALSE))
    state <- .grouped_probe_state
    if (isTRUE(state$pinned)) return(invisible(TRUE))
    state$pinned <- tryCatch(
        .grouped_probe_init(state$libname, state$pkgname),
        error = function(e) {
            state$error <- conditionMessage(e)
            FALSE
        })
    if (isTRUE(state$pinned)) .probe_grouped_bracket_init()
    invisible(state$pinned)
}

.grouped_probe_artifact_profile <- function(libname, pkgname) {
    stopifnot(identical(as.character(getRversion()), '4.6.1'),
              identical(as.character(R.version[['svn rev']]), '90187'))
    r_profile <- utils::read.csv(file.path(libname, pkgname, 'extdata',
                              'grouped-r-base-artifacts.csv'),
                                 stringsAsFactors = FALSE)
    stopifnot(identical(names(r_profile), c('relative_path', 'md5')),
              nrow(r_profile) == 7L)
    r_files <- file.path(R.home(), r_profile$relative_path)
    stopifnot(all(file.exists(r_files)),
              identical(unname(tools::md5sum(r_files)), r_profile$md5))
    path <- file.path(libname, pkgname, 'extdata',
                      'grouped-dependency-artifacts.csv')
    profile <- utils::read.csv(path, stringsAsFactors = FALSE)
    stopifnot(identical(names(profile),
                        c('package', 'version', 'relative_path', 'md5')),
              nrow(profile) == 47L,
              identical(sort(unique(profile$package)),
                        c('dplyr', 'rlang', 'stats', 'tibble', 'tidyselect', 'vctrs', 'withr')))
    for (pkg in unique(profile$package)) {
        entries <- profile[profile$package == pkg, ]
        stopifnot(length(unique(entries$version)) == 1L,
                  identical(as.character(getNamespaceVersion(pkg)),
                            entries$version[[1L]]))
        root <- getNamespaceInfo(asNamespace(pkg), 'path')
        files <- file.path(root, entries$relative_path)
        stopifnot(all(file.exists(files)),
                  identical(unname(tools::md5sum(files)), entries$md5))
    }
    TRUE
}

.grouped_probe_init <- function(libname, pkgname) {
    stopifnot(isTRUE(.grouped_probe_artifact_profile(libname, pkgname)))
    manifest_path <- file.path(libname, pkgname, 'extdata',
                               'grouped-public-roots.csv')
    manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
    stopifnot(identical(names(manifest),
                        c('kind', 'binding_pkg', 'name', 'owner', 'alias')),
              nrow(manifest) == 328L)
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
            baseenv = baseenv(),
            primitive = baseenv(),
            method = get('.__S3MethodsTable__.', asNamespace(pkg),
                         inherits = FALSE),
            stop('unknown grouped root kind'))
        stopifnot(exists(name, where, inherits = FALSE),
                  !bindingIsActive(name, where))
        actual <- get(name, where, inherits = FALSE)
        if (kind %in% c('primitive', 'baseenv')) {
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
    stopifnot(isTRUE(.Call(C_dtatools_grouped_pin_operators, operators)),
              isTRUE(.Call(C_dtatools_grouped_pin_public, roots)),
              isTRUE(.Call(C_dtatools_grouped_pin_absent, absent_roots)),
              isTRUE(.Call(C_dtatools_grouped_guard_public, NULL)))
    TRUE
}
