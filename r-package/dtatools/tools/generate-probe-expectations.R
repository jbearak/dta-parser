# Run after R CMD INSTALL into an isolated library:
# Rscript tools/generate-probe-expectations.R LIBRARY OUTPUT_DIRECTORY
# This script snapshots installed canonical package code, never live bindings.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
output_path <- normalizePath(args[[2L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))

packages <- c('base', 'rlang', 'vctrs', 'dtatools')
db_paths <- vapply(packages, function(pkg)
  system.file('R', paste0(pkg, '.rdb'), package = pkg), '')
stopifnot(all(nzchar(db_paths)),
          identical(as.character(getRversion()), '4.6.1'),
          identical(as.character(R.version[['svn rev']]), '90187'),
          identical(as.character(getNamespaceVersion('rlang')), '1.3.0'),
          identical(as.character(getNamespaceVersion('vctrs')), '0.7.3'))
expected_external <- c(base = '021f0beae727b3a819484ec49390f3e5',
                       rlang = '76538dba869773487446c5f4b12ddc51',
                       vctrs = 'edb81a62bca8cbd01de4a978fc733456')
# External dependencies are fixed admission inputs. The dtatools database and
# library are outputs of this source build, so record their digests below
# rather than pinning digests from a previous installation of the package.
db_md5 <- unname(tools::md5sum(db_paths))
names(db_md5) <- packages
stopifnot(identical(db_md5[names(expected_external)], expected_external),
          nzchar(db_md5[['dtatools']]))
native_paths <- c(R = file.path(R.home('lib'), 'libR.dylib'),
                  vctrs = system.file('libs', paste0('vctrs',
                    .Platform$dynlib.ext), package = 'vctrs'),
                  rlang = system.file('libs', paste0('rlang',
                    .Platform$dynlib.ext), package = 'rlang'),
                  dtatools = system.file('libs', paste0('dtatools',
                    .Platform$dynlib.ext), package = 'dtatools'))
expected_native <- c(R = 'bfbd266353f98efd4ac8bc487fd7d45c',
                     vctrs = 'bc58bbeb3ec490b263b937e23c3971a5',
                     rlang = 'd44ef6f686048db191bb0a7b1d6a7eb1')
native_md5 <- unname(tools::md5sum(native_paths))
names(native_md5) <- names(native_paths)
stopifnot(all(nzchar(native_paths)),
          identical(native_md5[names(expected_native)], expected_native),
          nzchar(native_md5[['dtatools']]))
fingerprint_paths <- c(db_paths[c('base', 'rlang', 'vctrs')],
                       native_paths[c('R', 'vctrs', 'rlang')])
expected_fingerprints <- c(base_db = '5d4f9e724b77f1e2',
                           rlang_db = 'f80bf320561fb90c',
                           vctrs_db = '11ff33033790bd5c',
                           R_native = '080247de6d9aa85c',
                           vctrs_native = '34f806ecac577e40',
                           rlang_native = 'b14c1d7b1912aff1')
actual_fingerprints <- .Call(
    dtatools:::C_dtatools_profile_file_fingerprints,
    unname(fingerprint_paths))
stopifnot(identical(unname(actual_fingerprints),
                    unname(expected_fingerprints)))

databases <- lapply(packages, function(pkg) {
  env <- new.env(parent = emptyenv())
  base::lazyLoad(system.file('R', pkg, package = pkg), envir = env)
  env
})
names(databases) <- packages
fetch <- function(pkg, name) {
  env <- databases[[pkg]]
  if (exists(name, envir = env, inherits = FALSE))
    return(get(name, envir = env, inherits = FALSE))
  if (pkg == 'base' && exists(name, envir = baseenv(), inherits = FALSE) &&
      is.primitive(get(name, envir = baseenv(), inherits = FALSE)))
    return(get(name, envir = baseenv(), inherits = FALSE))
  stop('missing installed canonical binding: ', pkg, '::', name)
}
snapshot <- function(filename, object) {
  saveRDS(object, file.path(output_path, filename), version = 3L,
          compress = 'gzip')
}
base29 <- c('is.data.frame', 'anyDuplicated', 'isTRUE', 'identical', 'eval',
            'getOption', 'unique', 'exists', 'vapply', 'lapply', 'new.env',
            'as.list', 'parent.frame', 'suppressWarnings',
            'getExportedValue', 'unique.default', 'anyDuplicated.default',
            'as.list.default', 'c', '$', 'missing', '&&', 'if', 'return', '!',
            'is.null', '.Call', 'attr<-', 'attributes<-')
base16 <- c('.row_names_info', '%in%', 'all.names', 'character',
            'environment', 'is.factor', 'is.primitive', 'isNamespace',
            'logical', 'numeric', 'parent.env', 'paste', 'paste0', 'setdiff',
            'unique.default', 'anyDuplicated.default')
rlang6 <- c('is_bool', 'is_formula', 'is_quosure', 'quo_get_env',
            'quo_get_expr', 'quo_is_missing')
by_name <- function(pkg, labels) {
  out <- lapply(labels, function(name) fetch(pkg, name))
  names(out) <- labels
  out
}
snapshot('probe-frozen-base.rds', by_name('base', base29))
snapshot('probe-base16-source.rds', by_name('base', base16))
snapshot('probe-base16-compiled.rds', by_name('base', base16))
snapshot('probe-frozen-rlang-public.rds', by_name('rlang', rlang6))
snapshot('frozen-vec-size-source.rds', fetch('vctrs', 'vec_size'))
snapshot('frozen-vec-size-compiled.rds', fetch('vctrs', 'vec_size'))
snapshot('frozen-proxy-source.rds',
         fetch('dtatools', 'vec_proxy.dta_numeric'))
snapshot('frozen-proxy-compiled.rds',
         fetch('dtatools', 'vec_proxy.dta_numeric'))
snapshot('probe-wrapper-clean.rds', fetch('dtatools', 'replace_values'))
snapshot('probe-base-internal-clean.rds', fetch('base', '.Internal'))

output_files <- sort(list.files(output_path, pattern = '[.]rds$',
                                full.names = TRUE))
stopifnot(length(output_files) == 10L)
hashes <- tools::md5sum(output_files)
names(hashes) <- basename(output_files)
cat('installed_databases\n')
for (pkg in packages) cat(pkg, db_md5[[pkg]], '\n')
cat('installed_native\n')
for (pkg in names(native_paths))
  cat(pkg, native_md5[[pkg]], '\n')
cat('installed_fingerprints\n')
for (name in names(expected_fingerprints))
  cat(name, unname(expected_fingerprints[[name]]), '\n')
cat('snapshots\n')
for (name in names(hashes)) cat(name, unname(hashes[[name]]), '\n')
