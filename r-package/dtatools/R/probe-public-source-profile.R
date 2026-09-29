# Audited public closure roots for the opt-in repl probe. The external database
# digests bind this list to the exact R/rlang/vctrs builds used for the audit.
# A different build declines native admission until it is audited separately.
.probe_public_source_manifest <- list(
    base = c(
        'is.data.frame', 'anyDuplicated', 'isTRUE', 'identical', 'eval',
        'getOption', 'unique', 'exists', 'vapply', 'lapply', 'new.env',
        'as.list', 'parent.frame', 'suppressWarnings', 'getExportedValue',
        'unique.default', 'anyDuplicated.default', 'as.list.default',
        '.row_names_info', '%in%', 'all.names', 'character', 'environment',
        'is.factor', 'is.primitive', 'isNamespace', 'logical', 'numeric',
        'parent.env', 'paste', 'paste0', 'setdiff', 'withCallingHandlers'
    ),
    rlang = c('is_bool', 'is_formula', 'is_quosure', 'quo_get_env',
              'quo_get_expr', 'quo_is_missing', 'list2'),
    vctrs = c('vec_recycle_common', 'vec_size', '+.vctrs_vctr', 'vec_arith'),
    dtatools = c('Ops.dta_numeric', 'vec_arith.dta_numeric',
                 'vec_arith.dta_numeric.numeric', 'vec_proxy.dta_numeric'),
    rlang_tail = c('is_logical', 'check_dots_empty0'),
    vctrs_tail = 'names<-.vctrs_vctr',
    base_tail = c('%||%', '.set_ops_need_as_vector', 'isa', 'match.fun',
                  'NextMethod', 'sys.frame', 'tryCatch')
)

.probe_installed_public_profile <- function() {
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
    owners <- sub('_tail$', '', names(.probe_public_source_manifest))
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
        for (name in .probe_public_source_manifest[[index]]) {
            code <- get0(name, envir = dbs[[pkg]], inherits = FALSE)
            if (!identical(typeof(code), 'closure'))
                stop('missing public profile closure: ', pkg, '::', name)
            roots[[length(roots) + 1L]] <- list(
                name = name, env = ns, canonical = code)
        }
    }
    if (length(roots) != 58L) stop('public profile manifest count')
    roots
}
