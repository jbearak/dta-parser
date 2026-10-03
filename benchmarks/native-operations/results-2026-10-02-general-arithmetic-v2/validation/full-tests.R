args <- commandArgs(trailingOnly = TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(dtatools))
suppressPackageStartupMessages(library(testthat))
stopifnot(identical(normalizePath(find.package("dtatools")), normalizePath(file.path(args[[1L]], "dtatools"))))
results <- testthat::test_dir("r-package/dtatools/tests/testthat", package = "dtatools", load_package = "installed", reporter = "silent", stop_on_failure = FALSE)
frame <- as.data.frame(results)
utils::write.csv(frame[c("file", "test", "passed", "failed", "error", "skipped", "warning")], args[[2L]], row.names = FALSE)
print(colSums(frame[c("passed", "failed", "error", "skipped", "warning")]))
for (i in which(frame$failed > 0 | frame$error)) {
    cat(frame$file[[i]], frame$test[[i]], "\n")
    for (result in frame$result[[i]]) if (inherits(result, "expectation_failure") || inherits(result, "expectation_error")) cat(substr(conditionMessage(result), 1L, 1000L), "\n")
}
quit(status = as.integer(any(frame$failed > 0 | frame$error)))
