args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
test_root <- normalizePath(args[[2L]], mustWork = TRUE)
output <- normalizePath(args[[3L]], mustWork = TRUE)
expected_dll <- normalizePath(args[[4L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
library(dtatools)
namespace <- asNamespace("dtatools")
stopifnot(identical(normalizePath(getNamespaceInfo(namespace, "path")),
                    file.path(library_path, "dtatools")))
loaded_dll <- normalizePath(getLoadedDLLs()[["dtatools"]][["path"]], mustWork = TRUE)
stopifnot(identical(loaded_dll, expected_dll))
stats <- get("C_dtatools_numeric_entry_stats", envir = namespace)
calls_before <- .Call(stats, FALSE)
filter <- paste0("^(native-arithmetic-kernels|native-arithmetic-parity|compact-float-domain|",
    "arithmetic-payload-lifetime|compact-pair-domain|dense-float-reciprocal-kernel|",
    "compact-reciprocal-facts|integer-reciprocal-lookup|constructor-region-inputs|",
    "dta-numeric|reader-numeric-facts)$")
testthat::set_max_fails(Inf)
result <- testthat::test_dir(test_root, filter = filter, package = "dtatools",
    reporter = "summary", stop_on_failure = FALSE)
saveRDS(result, file.path(output, "test-results.rds"))
table <- as.data.frame(result)
table <- table[, !vapply(table, is.list, logical(1)), drop = FALSE]
write.csv(table, file.path(output, "test-results.csv"), row.names = FALSE)
calls_after <- .Call(stats, FALSE)
write.csv(data.frame(entry = names(calls_before), before = as.double(calls_before),
    after = as.double(calls_after)), file.path(output, "native-entry-observations.csv"),
    row.names = FALSE)
dput(list(namespace_path = getNamespaceInfo(namespace, "path"), loaded_dll = loaded_dll,
    test_root = test_root, filter = filter, session = sessionInfo(),
    native_counts_are_observations = "Tests reset counters and assert per-operation entry counts"),
    file = file.path(output, "loaded-inputs.R"))
for (block in result) for (value in block$results)
    if (inherits(value, "expectation_failure") || inherits(value, "expectation_error")) print(value)
cat(sum(table$nb), "assertions in", nrow(table), "blocks; failures", sum(table$failed),
    "errors", sum(table$error), "warnings", sum(table$warning), "skips", sum(table$skipped), "\n")
stopifnot(all(table$failed == 0), all(!table$error), all(table$warning == 0), all(!table$skipped))
