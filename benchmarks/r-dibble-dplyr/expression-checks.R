# Exact-installed expression/full-suite gate; the Python launcher binds every
# source and visible installed dependency before this process starts.
args <- commandArgs(TRUE)
if (length(args) != 5L) stop("Expected library, source revision, source root, output and filter")
library <- normalizePath(args[[1L]], mustWork = TRUE)
revision <- args[[2L]]
root <- normalizePath(args[[3L]], mustWork = TRUE)
output <- normalizePath(args[[4L]], mustWork = TRUE)
source(file.path(root, "benchmarks/r-dibble-dplyr/helpers.R"))
.libPaths(c(library, .libPaths()))
main <- function() {
    validate_benchmark_install(library, revision)
    on.exit({
        namespaces <- sort(loadedNamespaces())
        paths <- vapply(namespaces, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
        write.table(data.frame(name = namespaces, path = paths),
            file.path(output, "namespaces.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
        dput(lapply(getLoadedDLLs(), function(dll) dll[["path"]]),
            file.path(output, "loaded-dlls.R"))
        validate_benchmark_install(library, revision)
    }, add = TRUE)
    library(dtatools, lib.loc = library)
    stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                        normalizePath(file.path(library, "dtatools"))))
    result <- testthat::test_local(file.path(root, "r-package/dtatools"),
        filter = if (args[[5L]] == "all") NULL else args[[5L]],
        load_package = "installed", reporter = "summary", stop_on_failure = FALSE)
    results <- as.data.frame(result)
    results$result <- NULL
    utils::write.csv(results, file.path(output, "tests.csv"), row.names = FALSE)
    counts <- colSums(results[c("failed", "skipped", "error", "warning", "passed")])
    dput(counts, file.path(output, "counts.R"))
    print(counts)
    if (counts[["failed"]] || counts[["error"]] || counts[["skipped"]]) stop("Required test gate failed or skipped")
}
main()
