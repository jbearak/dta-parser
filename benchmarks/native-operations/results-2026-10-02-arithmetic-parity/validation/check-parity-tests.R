args <- commandArgs(trailingOnly = TRUE)
library_path <- if (length(args)) args[[1L]] else
    "<previous-work>/final-candidate-v2/library"
output_prefix <- if (length(args) >= 2L) args[[2L]] else
    "<work>/baseline-parity-tests"
.libPaths(c(library_path, .libPaths()))
library(dtatools)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    normalizePath(file.path(library_path, "dtatools"))))
env <- new.env(parent = asNamespace("dtatools"))
sys.source("r-package/dtatools/tests/testthat/helper-native-execution-profile.R", envir = env)
sys.source("r-package/dtatools/tests/testthat/helper-fixtures.R", envir = env)
results <- testthat::test_file(
    "r-package/dtatools/tests/testthat/test-native-arithmetic-parity.R",
    env = env, reporter = "summary", stop_on_failure = FALSE)
saveRDS(results, paste0(output_prefix, ".rds"))
summary <- as.data.frame(results)
summary$result <- NULL
write.csv(summary, paste0(output_prefix, ".csv"), row.names = FALSE)
counts <- colSums(summary[c("passed", "failed", "error", "warning", "skipped")])
print(counts)
stopifnot(counts[["failed"]] == 0, counts[["error"]] == 0)
