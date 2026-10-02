args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], Sys.getenv("DTATOOLS_COMPARATOR_LIBRARY"), .libPaths()))
library(dtatools)
stopifnot(normalizePath(find.package("dtatools")) ==
          normalizePath(file.path(args[[1L]], "dtatools")))
result <- testthat::test_file(
    file.path(Sys.getenv("DTATOOLS_SCALAR_WORK"), "scalar-regression-tests.R"),
    reporter = "summary", stop_on_failure = FALSE
)
summary <- as.data.frame(result)
summary$result <- NULL
write.csv(summary, args[[2L]], row.names = FALSE)
counts <- colSums(summary[c("passed", "failed", "error", "warning", "skipped")])
print(counts)
stopifnot(counts[["failed"]] == 0, counts[["error"]] == 0)
