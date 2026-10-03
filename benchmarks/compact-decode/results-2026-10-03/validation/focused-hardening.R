args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(testthat))
stopifnot(identical(normalizePath(find.package("dtatools")), file.path(library_path, "dtatools")))
results <- testthat::test_dir("<decode-checkout>/r-package/dtatools/tests/testthat",
    package = "dtatools", load_package = "installed",
    filter = "native-decode-kernels|numeric-materialization|owned-numeric-buffers|arithmetic-payload-lifetime",
    reporter = "summary", stop_on_failure = FALSE)
frame <- as.data.frame(results)
write.csv(frame[c("file", "test", "passed", "failed", "error", "skipped", "warning")], args[[2L]], row.names = FALSE)
stopifnot(!any(frame$failed), !any(frame$error), !any(frame$skipped))
