#!/usr/bin/env Rscript
args <- commandArgs(TRUE)
stopifnot(length(args) == 6L)
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], args[[4L]])
output <- args[[2L]]
mode <- args[[4L]]
stopifnot(as.integer(args[[5L]]) == 7L, capabilities("profmem"), dir.exists(output))
options(warn = 2)
writeLines(atomic_identity(args[[3L]], library_path, mode),
           file.path(output, "owned-atomic-session.txt"))
suppressPackageStartupMessages(library(bench))
dll <- dyn.load(args[[6L]])
elt_symbol <- getNativeSymbolInfo("nonmissing_elt", dll)$address
pointer_symbol <- getNativeSymbolInfo("nonmissing_pointer", dll)$address
visits_symbol <- getNativeSymbolInfo("count_visits", dll)$address

# Untimed ordinary and table-column checks include empty, all-NA and mixed
# values. Counts and types are independent of the native implementations.
patterns <- list(empty = logical(), nonmissing = c(TRUE, FALSE),
                 all_missing = c(NA, NA), mixed = c(TRUE, FALSE, NA, TRUE))
tiny_checks <- list()
for (kind in c("logical", "factor", "ordered")) for (case_name in names(patterns)) {
    pattern <- patterns[[case_name]]
    raw <- if (kind == "logical") pattern else {
        strings <- ifelse(is.na(pattern), NA_character_, ifelse(pattern, "b", "a"))
        factor(strings, levels = c("a", "b", "unused"), ordered = kind == "ordered")
    }
    attr(raw, "label") <- "Tiny count control"
    table <- as_dibble(tibble::new_tibble(list(c01 = raw), nrow = length(raw)))
    expected <- sum(!is.na(pattern))
    stopifnot(typeof(expected) == "integer")
    for (container in c("ordinary", "table_column")) {
        x <- if (container == "ordinary") raw else table$c01
        cat("Checking tiny nonmissing control", kind, case_name, container, "\n")
        stopifnot(identical(typeof(x), typeof(raw)), identical(attributes(x), attributes(raw)),
                  identical(as.integer(x), as.integer(raw)),
                  identical(sum(!is.na(x)), expected),
                  identical(.Call(elt_symbol, x), expected),
                  identical(.Call(pointer_symbol, x), expected),
                  identical(.Call(visits_symbol, x), c(as.double(expected), as.double(length(raw)))))
        tiny_checks[[length(tiny_checks) + 1L]] <- list(kind = kind, case = case_name,
            container = container, expected = expected, type = typeof(x), attributes = attributes(x))
    }
}
stopifnot(length(tiny_checks) == 24L)
saveRDS(tiny_checks, file.path(output, "tiny-checks.rds"))
rm(patterns, tiny_checks, kind, case_name, pattern, raw, table, expected, container, x)

validate_benchmark_install(library_path, args[[3L]])
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dll_paths <- vapply(getLoadedDLLs(), function(info) info[["path"]], character(1))
write.table(data.frame(name = names(dll_paths), path = unname(dll_paths)),
    file.path(output, "dlls.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("PASS 24 untimed logical/factor/ordered correctness cases; no profiling or timing\n")
