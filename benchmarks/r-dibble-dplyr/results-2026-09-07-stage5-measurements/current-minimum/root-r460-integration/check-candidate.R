# Exact installed-package checks under the clean minimum R runtime.
source(Sys.getenv("DTA_MINIMUM_GUARD"))
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
minimum_runtime_guard(output, "before")
tryCatch({
    mode <- Sys.getenv("DTA_MINIMUM_CHECK")
    if (mode %in% c("behavior", "observe")) {
        source(Sys.getenv("DTA_MINIMUM_CASES"), local = globalenv())
    } else if (mode == "tests") {
        library <- Sys.getenv("DTA_ORACLE_LIBRARY")
        revision <- Sys.getenv("DTA_ORACLE_SOURCE")
        root <- Sys.getenv("DTA_MINIMUM_SOURCE_ROOT")
        source(Sys.getenv("DTA_ORACLE_HELPER"))
        validate_benchmark_install(library, revision)
        suppressPackageStartupMessages(library(dtatools, lib.loc = library))
        if (!identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                       normalizePath(file.path(library, "dtatools")))) stop("Wrong installed namespace")
        filter <- Sys.getenv("DTA_MINIMUM_TEST_FILTER", "dibble|group|mutat")
        result <- testthat::test_local(file.path(root, "r-package/dtatools"),
            filter = if (filter == "all") NULL else filter, load_package = "installed",
            reporter = "summary", stop_on_failure = FALSE)
        results <- as.data.frame(result)
        details <- lapply(results$result, function(expectations) {
            lapply(expectations, function(item) list(classes = class(item), message = item$message))
        })
        saveRDS(details, file.path(output, "expectation-details.rds"))
        dput(details, file = file.path(output, "expectation-details.R"))
        results$result <- NULL
        write.csv(results, file.path(output, "tests.csv"), row.names = FALSE)
        counts <- colSums(results[c("failed", "skipped", "error", "warning", "passed")])
        dput(counts, file.path(output, "counts.R"))
        print(counts)
        validate_benchmark_install(library, revision)
        if (counts[["failed"]] || counts[["error"]]) stop("Minimum-runtime test failure")
        # Capability skips are retained explicitly for classification. This
        # runtime has no profmem and cannot replace current-R allocation gates.
    } else stop("Unknown minimum check mode")
}, finally = minimum_runtime_guard(output, "after"))
