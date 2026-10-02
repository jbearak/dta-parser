args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(args[[1L]], .libPaths()))
library(dtatools)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    normalizePath(file.path(args[[1L]], "dtatools"))))
env <- new.env(parent = asNamespace("dtatools"))
sys.source("r-package/dtatools/tests/testthat/helper-native-execution-profile.R", envir = env)
sys.source("r-package/dtatools/tests/testthat/helper-fixtures.R", envir = env)
results <- testthat::test_file(
    "r-package/dtatools/tests/testthat/test-native-arithmetic-kernels.R",
    env = env, reporter = "summary", stop_on_failure = FALSE)
saveRDS(results, paste0(args[[2L]], ".rds"))
summary <- as.data.frame(results)
summary$result <- NULL
write.csv(summary, paste0(args[[2L]], ".csv"), row.names = FALSE)
counts <- colSums(summary[c("passed", "failed", "error", "warning", "skipped")])
print(counts)
stopifnot(counts[["failed"]] == 0, counts[["error"]] == 0)
