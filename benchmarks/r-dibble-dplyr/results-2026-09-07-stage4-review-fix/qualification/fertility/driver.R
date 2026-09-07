lib <- Sys.getenv('DTA_QUALIFICATION_LIBRARY')
sha <- Sys.getenv('DTA_QUALIFICATION_SOURCE')
source(Sys.getenv('DTA_QUALIFICATION_HELPER'))
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
library(dtatools, lib.loc = lib)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    normalizePath(file.path(lib, 'dtatools'))),
          identical(normalizePath(getLoadedDLLs()[['dtatools']][['path']]),
                    normalizePath(file.path(lib, 'dtatools', 'libs', paste0('dtatools', .Platform$dynlib.ext)))))
cat(sprintf('Exact source %s\nDLL_md5 %s\n', sha,
            unname(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]))))
testthat::set_max_fails(Inf)
source('checks/run_testthat.R')
