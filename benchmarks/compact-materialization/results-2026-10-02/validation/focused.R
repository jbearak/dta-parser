args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(testthat))
results <- testthat::test_dir(
    '<candidate-checkout>/r-package/dtatools/tests/testthat',
    package = 'dtatools', load_package = 'installed', filter = args[[2L]],
    reporter = 'summary', stop_on_failure = FALSE)
frame <- as.data.frame(results)
write.csv(frame[c('file', 'test', 'passed', 'failed', 'error', 'skipped', 'warning')],
          args[[3L]], row.names = FALSE)
stopifnot(!any(frame$failed), !any(frame$error), !any(frame$skipped))
