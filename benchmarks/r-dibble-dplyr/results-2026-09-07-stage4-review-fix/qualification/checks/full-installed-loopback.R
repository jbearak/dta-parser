source('benchmarks/r-dibble-dplyr/helpers.R')
lib <- '/private/tmp/dta-direct-stage4-validation/candidate-c8ca0a4-library'
sha <- 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
out <- '/private/tmp/dta-direct-stage4-validation/checks-c8ca0a4/full-installed-loopback.csv'
stopifnot(!file.exists(out))
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
library(dtatools, lib.loc = lib)
package <- normalizePath(file.path(lib, 'dtatools'))
dll <- normalizePath(file.path(package, 'libs', paste0('dtatools', .Platform$dynlib.ext)))
stopifnot(identical(normalizePath(find.package('dtatools')), package),
          identical(normalizePath(getLoadedDLLs()[['dtatools']][['path']]), dll))
cat('source', sha, '\npackage', package, '\ndll', dll, '\nDLL MD5', tools::md5sum(dll), '\n')
result <- testthat::test_dir('r-package/dtatools/tests/testthat', reporter = 'summary',
    package = 'dtatools', load_package = 'installed', stop_on_failure = TRUE)
summary <- as.data.frame(result)
stopifnot(all(c('failed', 'skipped', 'error', 'warning', 'passed') %in% names(summary)))
write.csv(summary[setdiff(names(summary), 'result')], out, row.names = FALSE)
cat('TOTALS failed', sum(summary$failed), 'skipped', sum(summary$skipped),
    'error', sum(summary$error), 'warning', sum(summary$warning), 'passed', sum(summary$passed), '\n')
stopifnot(!any(summary$failed), !any(summary$skipped), !any(summary$error))
validate_benchmark_install(lib, sha)
