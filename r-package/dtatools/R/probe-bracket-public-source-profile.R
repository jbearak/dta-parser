# Conservative public closure roots for the isolated bracket admission probe.
# The external database digests bind this list to the exact audited
# R/rlang/vctrs builds.
# A different build declines native admission until it is audited separately.
.probe_bracket_source_manifest <- list(
    base = c(
        'is.data.frame', 'anyDuplicated', 'isTRUE', 'identical', 'eval',
        'getOption', 'unique', 'exists', 'vapply', 'lapply', 'new.env',
        'as.list', 'parent.frame', 'suppressWarnings', 'getExportedValue',
        'unique.default', 'anyDuplicated.default', 'as.list.default',
        '.row_names_info', '%in%', 'all.names', 'character', 'environment',
        'is.factor', 'is.primitive', 'isNamespace', 'logical', 'numeric',
        'parent.env', 'paste', 'paste0', 'setdiff', 'withCallingHandlers',
        'inherits', 'typeof', 'is.vector', 'match', 'startsWith',
        'intersect', 'sprintf', 'structure', 'suspendInterrupts',
        'sys.call'
    ),
    rlang = c('is_bool', 'is_formula', 'is_quosure', 'quo_get_env',
              'quo_get_expr', 'quo_is_missing', 'list2', 'enquo',
              'enquos', 'new_quosure', 'obj_address', 'arg_match0',
              'as_function', 'caller_env', 'enexpr', 'inject', 'is_false',
              'is_function', 'is_missing', 'is_symbol', 'is_true',
              'maybe_missing', 'names2', 'node_cdr'),
    vctrs = c('vec_recycle_common', 'vec_size', '+.vctrs_vctr', 'vec_arith',
              'vec_data', 'obj_check_vector', 'vec_proxy'),
    dtatools = c('Ops.dta_numeric', 'vec_arith.dta_numeric',
                 'vec_arith.dta_numeric.numeric', 'vec_proxy.dta_numeric',
                 'length.dibble'),
    rlang_tail = c('is_logical', 'check_dots_empty0'),
    vctrs_tail = 'names<-.vctrs_vctr',
    base_tail = c('%||%', '.set_ops_need_as_vector', 'isa', 'match.fun',
                  'NextMethod', 'sys.frame', 'tryCatch')
)

.probe_bracket_installed_public_profile <- function() {
    if (!identical(as.character(getRversion()), '4.6.1') ||
        !identical(as.character(R.version[['svn rev']]), '90187') ||
        !identical(as.character(getNamespaceVersion('rlang')), '1.3.0') ||
        !identical(as.character(getNamespaceVersion('vctrs')), '0.7.3'))
        stop('public profile build differs')
    db_paths <- vapply(c('base', 'rlang', 'vctrs'), function(pkg)
        system.file('R', paste0(pkg, '.rdb'), package = pkg), '')
    db_fingerprints <- c(base = '5d4f9e724b77f1e2',
                         rlang = 'f80bf320561fb90c',
                         vctrs = '11ff33033790bd5c')
    if (!all(nzchar(db_paths)) ||
        !identical(unname(.native_admission_call(
            C_dtatools_profile_file_fingerprints, db_paths)),
                   unname(db_fingerprints)))
        stop('public profile database differs')
    native_paths <- c(R = file.path(R.home('lib'), 'libR.dylib'),
                      vctrs = system.file('libs', paste0('vctrs',
                        .Platform$dynlib.ext), package = 'vctrs'),
                      rlang = system.file('libs', paste0('rlang',
                        .Platform$dynlib.ext), package = 'rlang'))
    native_fingerprints <- c(R = '080247de6d9aa85c',
                             vctrs = '34f806ecac577e40',
                             rlang = 'b14c1d7b1912aff1')
    if (!all(nzchar(native_paths)) ||
        !identical(unname(.native_admission_call(
            C_dtatools_profile_file_fingerprints, native_paths)),
                   unname(native_fingerprints)))
        stop('public profile native dependencies differ')
    owners <- sub('_tail$', '', names(.probe_bracket_source_manifest))
    dbs <- list()
    for (pkg in unique(owners)) {
        path <- system.file('R', pkg, package = pkg)
        if (!nzchar(path)) stop('missing public profile database: ', pkg)
        db <- new.env(parent = emptyenv())
        base::lazyLoad(path, envir = db)
        dbs[[pkg]] <- db
    }
    roots <- list()
    for (index in seq_along(owners)) {
        pkg <- owners[[index]]
        ns <- if (pkg == 'base') baseenv() else asNamespace(pkg)
        for (name in .probe_bracket_source_manifest[[index]]) {
            code <- get0(name, envir = dbs[[pkg]], inherits = FALSE)
            if (!identical(typeof(code), 'closure'))
                stop('missing public profile closure: ', pkg, '::', name)
            roots[[length(roots) + 1L]] <- list(
                name = name, env = ns, canonical = code)
        }
    }
    if (length(roots) != 89L) stop('public profile manifest count')
    roots
}

.probe_bracket_public_state <- new.env(parent = emptyenv())
.probe_bracket_public_state$snapshots <- NULL
.probe_bracket_public_state$error <- NULL
.probe_bracket_public_state$tables <- NULL
.probe_bracket_public_state$live <- NULL
.probe_bracket_public_state$namespaces <- NULL
.probe_bracket_public_state$primitives <- NULL
.probe_bracket_public_state$length_method <- NULL

.probe_bracket_public_init <- function() {
    tryCatch({
        profile <- .probe_bracket_installed_public_profile()
        groups <- list()
        for (root in profile) {
            binding <- get(root$name, envir = root$env, inherits = FALSE)
            comparison <- .native_admission_call(
                C_probe_public48_source_qualification,
                binding, root$canonical)
            if (!is.logical(comparison) || length(comparison) != 4L ||
                !all(comparison))
                stop('bracket public source differs: ', root$name)
            key <- if (identical(root$env, baseenv())) 'base' else
                environmentName(root$env)
            groups[[key]][[root$name]] <- binding
        }
        snapshots <- list()
        for (key in names(groups)) {
            env <- if (identical(key, 'base')) baseenv() else
                asNamespace(key)
            snapshots[[key]] <- .native_admission_call(
                C_snap_new_shallow_all, groups[[key]], env)
            if (is.null(snapshots[[key]]))
                stop('bracket public snapshot declined: ', key)
        }
        dtans <- asNamespace('dtatools')
        vns <- asNamespace('vctrs')
        tbl <- function(env) get('.__S3MethodsTable__.', envir = env,
                                 inherits = FALSE)
        tables <- list(tbl(baseenv()), tbl(vns), tbl(dtans))
        length_method <- get('length.dibble', dtans, inherits = FALSE)
        if (!identical(get0('length.dibble', tables[[1L]],
                            inherits = FALSE), length_method))
            stop('bracket length method differs')
        live <- list(
            get0('Ops.dta_numeric', tables[[1L]], inherits = FALSE),
            get0('+.vctrs_vctr', tables[[1L]], inherits = FALSE),
            get('vec_arith', vns, inherits = FALSE),
            get0('vec_arith.dta_numeric', tables[[2L]], inherits = FALSE),
            get0('vec_arith.dta_numeric.numeric', tables[[3L]],
                 inherits = FALSE),
            get('vec_arith.dta_numeric', dtans, inherits = FALSE),
            .Primitive('+'),
            get0('vec_proxy.dta_numeric', tables[[2L]], inherits = FALSE),
            get0('anyDuplicated.default', tables[[1L]], inherits = FALSE),
            get0('as.list.default', tables[[1L]], inherits = FALSE),
            get0('unique.default', tables[[1L]], inherits = FALSE),
            get0('names<-.vctrs_vctr', tables[[1L]], inherits = FALSE)
        )
        method_sources <- list(
            get('vec_proxy.dta_numeric', dtans, inherits = FALSE),
            get('anyDuplicated.default', baseenv(), inherits = FALSE),
            get('as.list.default', baseenv(), inherits = FALSE),
            get('unique.default', baseenv(), inherits = FALSE),
            get('names<-.vctrs_vctr', vns, inherits = FALSE))
        if (any(vapply(seq_along(method_sources), function(i)
            is.null(live[[i + 7L]]) ||
                !identical(live[[i + 7L]], method_sources[[i]]),
            logical(1))))
            stop('bracket public method differs')
        primitive_names <- c('names', 'length', 'list', 'is.null',
                             'as.double', 'is.logical',
                             'is.na', 'nzchar', 'missing', '...length',
                             '::', '.Call',
                             'class', 'class<-', '[[', '$', 'seq.int',
                             'on.exit', 'if', 'for', 'return', '&&', '||',
                             '!', '{', '(', '+', '-', 'abs', '*', '/', '==',
                             '!=', '<', '<=', '>', '>=', ':', '[', '@',
                             'c', 'attr', 'attr<-', 'attributes',
                             'attributes<-', 'names<-', '.Internal',
                             'quote', '<-', 'lazyLoadDBfetch',
                             'is.object', 'isS4', 'is.atomic',
                             'is.character', 'is.numeric', 'is.integer',
                             'is.double', 'is.function', 'is.environment',
                             'is.symbol', 'is.call', 'is.list',
                             'unclass', 'any',
                             'all', 'rep')
        primitives <- lapply(primitive_names, .Primitive)
        names(primitives) <- primitive_names
        for (name in primitive_names)
            if (bindingIsActive(name, baseenv()) ||
                !identical(get(name, baseenv(), inherits = FALSE),
                           primitives[[name]]))
                stop('bracket public primitive differs: ', name)
        .native_admission_call(C_bracket_s3_init, NULL)
        .probe_bracket_public_state$tables <- tables
        .probe_bracket_public_state$live <- live
        .probe_bracket_public_state$namespaces <- list(vns, dtans)
        .probe_bracket_public_state$primitives <- primitives
        .probe_bracket_public_state$length_method <- length_method
        .probe_bracket_public_state$snapshots <- unname(snapshots)
    }, error = function(e) {
        .probe_bracket_public_state$error <- conditionMessage(e)
        .probe_bracket_public_state$snapshots <- NULL
    })
    invisible(NULL)
}
