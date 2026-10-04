args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
suppressPackageStartupMessages(library(testthat))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    file.path(library_path, "dtatools")))
results <- testthat::test_dir(args[[2L]], package = "dtatools", load_package = "installed",
    filter = "^native-arithmetic-parity$|^arithmetic-payload-lifetime$|^compact-float-domain$",
    reporter = "silent", stop_on_failure = FALSE)
frame <- as.data.frame(results)
write.csv(frame[c("file", "test", "passed", "failed", "error", "skipped", "warning")],
          args[[3L]], row.names = FALSE)
print(colSums(frame[c("passed", "failed", "error", "skipped", "warning")]))
cat("Test blocks:", nrow(frame), "\n")
stopifnot(!any(frame$failed), !any(frame$error), !any(frame$skipped), !any(frame$warning))
