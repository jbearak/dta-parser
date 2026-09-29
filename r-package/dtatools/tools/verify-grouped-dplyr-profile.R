# Verify the audited grouped public-root and dependency profiles.
# This script writes only to the supplied output directory and fails closed
# if an installed dependency differs from the reviewed package manifest.
# Run from the dtatools package source directory in a fresh R process:
# Rscript tools/verify-grouped-dplyr-profile.R /path/to/audited/lib /path/to/output
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
pkg <- normalizePath(getwd())
stopifnot(file.exists(file.path(pkg, 'DESCRIPTION')))
audit <- normalizePath(args[[2L]], mustWork = FALSE)
dir.create(audit, recursive = TRUE, showWarnings = FALSE)
graph <- file.path(pkg, 'tools', 'grouped-dplyr-profile')
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
suppressPackageStartupMessages(library(dplyr))
stopifnot(identical(as.character(getRversion()), '4.6.1'),
          identical(as.character(R.version[['svn rev']]), '90187'))

expected_artifacts <- read.csv(file.path(pkg, 'inst/extdata',
                                          'grouped-dependency-artifacts.csv'),
                               stringsAsFactors = FALSE)
stopifnot(nrow(expected_artifacts) == 47L)
observed_artifacts <- expected_artifacts
for (i in seq_len(nrow(observed_artifacts))) {
  owner <- observed_artifacts$package[[i]]
  stopifnot(identical(as.character(getNamespaceVersion(owner)),
                      expected_artifacts$version[[i]]))
  owner_path <- getNamespaceInfo(asNamespace(owner), 'path')
  file <- file.path(owner_path, observed_artifacts$relative_path[[i]])
  stopifnot(file.exists(file))
  observed_artifacts$md5[[i]] <- unname(tools::md5sum(file))
}
stopifnot(identical(observed_artifacts, expected_artifacts))
write.csv(observed_artifacts, file.path(audit, 'reproduced-47-artifacts.csv'),
          row.names = FALSE)

traces <- read.csv(file.path(graph, 'grouped-postcapture-closure-census.csv'))
targets <- unique(traces[traces$ordinary > traces$candidate, c('pkg', 'name')])
entries <- data.frame(kind = 'namespace', binding_pkg = targets$pkg,
                      name = targets$name, owner = '', alias = '',
                      stringsAsFactors = FALSE)
entries <- rbind(entries,
  data.frame(kind = 'namespace', binding_pkg = 'dtatools',
             name = 'mutate.dibble', owner = '', alias = ''),
  data.frame(kind = 'method', binding_pkg = 'dplyr',
             name = 'mutate.dibble', owner = '', alias = ''),
  data.frame(kind = 'baseenv', binding_pkg = 'base',
             name = '.Internal', owner = '', alias = ''))
owner_of <- function(fn) {
  e <- environment(fn)
  if (identical(e, baseenv())) 'base' else
    if (isNamespace(e)) as.character(getNamespaceName(e)) else
      stop('unexpected owner: ', environmentName(e))
}
for (i in seq_len(nrow(entries))) {
  kind <- entries$kind[[i]]
  package <- entries$binding_pkg[[i]]
  env <- switch(kind, namespace = asNamespace(package),
                baseenv = baseenv(),
                method = get('.__S3MethodsTable__.', asNamespace(package),
                             inherits = FALSE))
  fn <- get(entries$name[[i]], env, inherits = FALSE)
  if (typeof(fn) == 'closure') entries$owner[[i]] <- owner_of(fn)
}
stopifnot(nrow(entries) == 162L)

primitive_names <- sort(unique(subset(read.csv(file.path(graph,
  'transitive-postcapture-primitive-targets.csv')), pkg == 'base')$name))
aliases <- c('is.name' = 'is.symbol', 'as.numeric' = 'as.double')
primitives <- data.frame(kind = 'primitive', binding_pkg = 'base',
                         name = primitive_names, owner = 'base', alias = '',
                         stringsAsFactors = FALSE)
for (i in seq_len(nrow(primitives)))
  if (primitives$name[[i]] %in% names(aliases))
    primitives$alias[[i]] <- aliases[[primitives$name[[i]]]]
stopifnot(nrow(primitives) == 142L)

methods <- read.csv(file.path(graph, 'grouped-method-targets16.csv'))
method_entries <- data.frame(kind = 'method', binding_pkg = methods$package,
                             name = methods$name, owner = '', alias = '',
                             stringsAsFactors = FALSE)
for (i in seq_len(nrow(method_entries))) {
  table <- get('.__S3MethodsTable__.',
               asNamespace(method_entries$binding_pkg[[i]]), inherits = FALSE)
  method_entries$owner[[i]] <- owner_of(get(method_entries$name[[i]],
                                             table, inherits = FALSE))
}
stopifnot(nrow(method_entries) == 16L)

extra_methods <- data.frame(
  kind = 'method',
  binding_pkg = c('base', 'base', 'base', 'tidyselect', 'tidyselect', 'vctrs'),
  name = c('as.data.frame.integer', 'as.data.frame.numeric',
           'as.list.default', 'tidyselect_data_proxy.default',
           'tidyselect_data_has_predicates.default',
           'vec_ptype_finalise.default'),
  owner = c('base', 'base', 'base', 'tidyselect', 'tidyselect', 'vctrs'),
  alias = '', stringsAsFactors = FALSE)
for (i in seq_len(nrow(extra_methods))) {
  table <- get('.__S3MethodsTable__.',
               asNamespace(extra_methods$binding_pkg[[i]]), inherits = FALSE)
  actual_owner <- owner_of(get(extra_methods$name[[i]], table,
                               inherits = FALSE))
  if (!identical(actual_owner, extra_methods$owner[[i]]))
    stop(extra_methods$name[[i]], ': owner ', actual_owner,
         ' vs ', extra_methods$owner[[i]])
}
adjacent_roots <- data.frame(
  kind = 'namespace', binding_pkg = c('stats', 'withr'),
  name = c('setNames', 'defer'), owner = c('stats', 'withr'), alias = '',
  stringsAsFactors = FALSE)
observed_roots <- rbind(entries, primitives, extra_methods, method_entries,
                        adjacent_roots)
expected_roots <- read.csv(file.path(pkg, 'inst/extdata',
                                      'grouped-public-roots.csv'),
                           stringsAsFactors = FALSE)
stopifnot(nrow(observed_roots) == 328L,
          identical(observed_roots, expected_roots))
write.csv(observed_roots, file.path(audit, 'reproduced-328-roots.csv'),
          row.names = FALSE)

# Base is not among the 47 package artifacts; record its code/native pieces
# separately so an equal version and svn revision cannot silently imply an
# equal build. This candidate list requires review before production pinning.
base_relative <- c('library/base/DESCRIPTION', 'library/base/R/Rprofile',
                   'library/base/R/base', 'library/base/R/base.rdb',
                   'library/base/R/base.rdx', 'lib/libR.dylib',
                   'bin/exec/R')
base_files <- file.path(R.home(), base_relative)
stopifnot(all(file.exists(base_files)))
base_profile <- data.frame(relative_path = base_relative,
                           md5 = unname(tools::md5sum(base_files)))
expected_base <- read.csv(file.path(pkg, 'inst/extdata',
                                    'grouped-r-base-artifacts.csv'),
                          stringsAsFactors = FALSE)
stopifnot(identical(base_profile, expected_base))
write.csv(base_profile, file.path(audit, 'reproduced-base-artifacts.csv'),
          row.names = FALSE)
cat('PROFILE_OK 328 roots 47 dependencies 7 base files\n')
