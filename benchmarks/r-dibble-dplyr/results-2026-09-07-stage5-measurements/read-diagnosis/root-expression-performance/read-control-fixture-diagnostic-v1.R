#!/usr/bin/env Rscript
# Untimed observation of the exact tiny correctness fixtures from control v1.
args <- commandArgs(TRUE)
stopifnot(length(args) == 6L)
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], args[[4L]])
output <- args[[2L]]
mode <- args[[4L]]
options(warn = 2)
writeLines(atomic_identity(args[[3L]], library_path, mode),
           file.path(output, "owned-atomic-session.txt"))
suppressPackageStartupMessages(library(bench))
dll <- dyn.load(args[[6L]])
elt_symbol <- getNativeSymbolInfo("any_na_elt", dll)$address
pointer_symbol <- getNativeSymbolInfo("any_na_pointer", dll)$address
visits_symbol <- getNativeSymbolInfo("elt_visits", dll)$address
records <- list()
cases <- list(empty = character(), nonmissing = c("a", ""),
              missing_first = NA_character_, missing_last = c("a", NA_character_))
for (case in names(cases)) {
    values <- cases[[case]]
    expected <- anyNA(values)
    visits <- if (expected) match(NA_character_, values) else length(values)
    declared <- structure(values, stata.string.storage = "str12")
    table <- as_dibble(tibble::tibble(c01 = declared))
    containers <- list(ordinary = values, table_column = table$c01)
    for (container in names(containers)) {
        x <- containers[[container]]
        observed <- list(case = case, container = container, original = values,
            original_attributes = attributes(values), declaration = declared,
            declaration_attributes = attributes(declared), actual = as.character(x),
            attributes = attributes(x), is_object = is.object(x),
            original_expected_any_na = expected, original_expected_visits = visits,
            actual_any_na = anyNA(x), native_elt = .Call(elt_symbol, x),
            native_pointer = .Call(pointer_symbol, x), native_visits = .Call(visits_symbol, x),
            original_identical_predicate = identical(as.character(x), values))
        records[[length(records) + 1L]] <- observed
        dput(observed)
    }
}
saveRDS(records, file.path(output, "fixture-observations.rds"))
dput(records, file = file.path(output, "fixture-observations.R"))
stopifnot(length(records) == 8L)
validate_benchmark_install(library_path, args[[3L]])
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dll_paths <- vapply(getLoadedDLLs(), function(info) info[["path"]], character(1))
write.table(data.frame(name = names(dll_paths), path = unname(dll_paths)),
    file.path(output, "dlls.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("OBSERVED eight tiny fixture/container combinations; no benchmark or changed oracle\n")
