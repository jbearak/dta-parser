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
elt_symbol <- getNativeSymbolInfo("any_na_elt", dll)$address
pointer_symbol <- getNativeSymbolInfo("any_na_pointer", dll)$address
visits_symbol <- getNativeSymbolInfo("elt_visits", dll)$address

# Untimed checks use independent raw and Stata-normalized constructor oracles.
# Existing as_dibble policy replaces declared-string NA with empty string and
# recomputes stale storage; valid declarations on no-NA values remain unchanged.
cases <- list(
    empty = list(raw = character(), stored = character(), storage = "str12"),
    nonmissing = list(raw = c("a", ""), stored = c("a", ""), storage = "str12"),
    missing_first = list(raw = NA_character_, stored = "", storage = "str1"),
    missing_last = list(raw = c("a", NA_character_), stored = c("a", ""), storage = "str1"))
for (case_name in names(cases)) {
    case <- cases[[case_name]]
    declared <- structure(case$raw, stata.string.storage = "str12")
    table <- as_dibble(tibble::tibble(c01 = declared))
    stopifnot(identical(attr(table$c01, "stata.string.storage", exact = TRUE), case$storage))
    inputs <- list(ordinary = case$raw, table_column = table$c01)
    for (container in names(inputs)) {
        x <- inputs[[container]]
        expected_values <- if (container == "ordinary") case$raw else case$stored
        expected <- anyNA(expected_values)
        visits <- if (expected) match(NA_character_, expected_values) else length(expected_values)
        cat("Checking tiny native control", case_name, container, "\n")
        stopifnot(!is.object(x), identical(as.character(x), expected_values),
                  identical(.Call(elt_symbol, x), expected),
                  identical(.Call(pointer_symbol, x), expected),
                  identical(.Call(visits_symbol, x), as.double(visits)))
    }
}
rm(cases, case_name, case, declared, table, inputs, container, x, expected_values, expected, visits)

records <- states <- list()
for (rows in c(100000L, 1000000L)) {
    invisible(dplyr::rename(atomic_fixture("declared_character", 4L), changed = c01))
    data <- atomic_fixture("declared_character", rows, 1L)
    frozen <- atomic_frozen(data, "declared_character")
    column <- data$c01
    operations <- list(
        public_table = function() anyNA(data$c01),
        public_column = function() anyNA(column),
        native_elt = function() .Call(elt_symbol, column),
        native_pointer = function() .Call(pointer_symbol, column))
    initial <- atomic_state(data, mode)
    stopifnot(identical(.Call(visits_symbol, column), as.double(rows)))
    atomic_unchanged_backings(initial, data, mode)
    for (name in names(operations)) {
        operation <- operations[[name]]
        before <- atomic_state(data, mode)
        stopifnot(identical(operation(), FALSE))
        atomic_unchanged_backings(before, data, mode)
        before_profile <- atomic_state(data, mode)
        profile <- atomic_profile(operation)
        stopifnot(identical(profile$value, FALSE),
                  all(profile$metrics[startsWith(names(profile$metrics), "native_")] == 0))
        atomic_unchanged_backings(before_profile, data, mode)
        invisible(gc())
        before_timing <- atomic_state(data, mode)
        mark <- bench::mark(operation(), iterations = 7L, check = TRUE, filter_gc = FALSE)
        stopifnot(identical(mark$result[[1L]], FALSE), mark$n_itr == 7L)
        after <- atomic_state(data, mode)
        atomic_unchanged_backings(before_timing, data, mode)
        atomic_preserved(data, frozen)
        id <- length(records) + 1L
        saveRDS(list(median_ms = as.numeric(mark$median) * 1000, samples = mark$time,
                    allocation = mark$mem_alloc, iterations = mark$n_itr, gc_count = mark$n_gc),
                file.path(output, paste0("raw-timing-", id, ".rds")))
        states[[id]] <- list(operation = name, rows = rows, before = before,
                            before_profile = before_profile, before_timing = before_timing, after = after)
        records[[id]] <- cbind(data.frame(operation = name, rows = rows, columns = 1L,
            median_ms = as.numeric(mark$median) * 1000,
            bench_allocated_bytes = as.numeric(mark$mem_alloc), iterations = mark$n_itr,
            gc_count = mark$n_gc), as.data.frame(as.list(profile$metrics)))
        write.csv(do.call(rbind, records), file.path(output, "read-control.csv"), row.names = FALSE)
        saveRDS(states, file.path(output, "source-states.rds"))
        print(records[[id]])
    }
    rm(data, frozen, column, operations, operation, before, before_profile,
       profile, before_timing, after, mark, initial)
    invisible(gc())
}
stopifnot(length(records) == 8L)
validate_benchmark_install(library_path, args[[3L]])
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dll_paths <- vapply(getLoadedDLLs(), function(info) info[["path"]], character(1))
write.table(data.frame(name = names(dll_paths), path = unname(dll_paths)),
    file.path(output, "dlls.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("PASS eight declared-character read controls; visit counts were untimed\n")
