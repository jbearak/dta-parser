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

records <- states <- visits <- list()
for (kind in c("logical", "factor", "ordered")) for (rows in c(100000L, 1000000L)) {
    invisible(dplyr::rename(atomic_fixture(kind, 4L), changed = c01))
    data <- atomic_fixture(kind, rows, 1L)
    frozen <- atomic_frozen(data, kind)
    reference <- atomic_raw(kind, rows, 1L)[[1L]]
    expected <- sum(!is.na(reference))
    stopifnot(identical(expected, as.integer(rows * 0.75)))
    column <- data$c01
    operations <- list(
        public_table = function() sum(!is.na(data$c01)),
        public_column = function() sum(!is.na(column)),
        native_elt = function() .Call(elt_symbol, column),
        native_pointer = function() .Call(pointer_symbol, column))
    initial <- atomic_state(data, mode)
    visit_result <- .Call(visits_symbol, column)
    stopifnot(identical(visit_result, c(as.double(expected), as.double(rows))))
    atomic_unchanged_backings(initial, data, mode)
    visits[[length(visits) + 1L]] <- list(kind = kind, rows = rows, expected = expected,
                                        native_count_and_visits = visit_result)
    saveRDS(visits, file.path(output, "untimed-native-visits.rds"))
    for (name in names(operations)) {
        operation <- operations[[name]]
        before <- atomic_state(data, mode)
        stopifnot(identical(operation(), expected))
        atomic_unchanged_backings(before, data, mode)
        before_profile <- atomic_state(data, mode)
        profile <- atomic_profile(operation)
        stopifnot(identical(profile$value, expected),
                  all(profile$metrics[startsWith(names(profile$metrics), "native_")] == 0))
        atomic_unchanged_backings(before_profile, data, mode)
        invisible(gc())
        before_timing <- atomic_state(data, mode)
        mark <- bench::mark(operation(), iterations = 7L, check = TRUE, filter_gc = FALSE)
        stopifnot(identical(mark$result[[1L]], expected), mark$n_itr == 7L)
        after <- atomic_state(data, mode)
        atomic_unchanged_backings(before_timing, data, mode)
        atomic_preserved(data, frozen)
        id <- length(records) + 1L
        saveRDS(list(median_ms = as.numeric(mark$median) * 1000, samples = mark$time,
                    allocation = mark$mem_alloc, iterations = mark$n_itr, gc_count = mark$n_gc),
                file.path(output, paste0("raw-timing-", id, ".rds")))
        states[[id]] <- list(kind = kind, operation = name, rows = rows, before = before,
                            before_profile = before_profile, before_timing = before_timing, after = after)
        records[[id]] <- cbind(data.frame(kind = kind, operation = name, rows = rows, columns = 1L,
            expected_count = expected, median_ms = as.numeric(mark$median) * 1000,
            bench_allocated_bytes = as.numeric(mark$mem_alloc), iterations = mark$n_itr,
            gc_count = mark$n_gc), as.data.frame(as.list(profile$metrics)))
        write.csv(do.call(rbind, records), file.path(output, "read-count-control.csv"), row.names = FALSE)
        saveRDS(states, file.path(output, "source-states.rds"))
        print(records[[id]])
    }
    rm(data, frozen, reference, expected, column, operations, operation, before, before_profile,
       profile, before_timing, after, mark, initial, visit_result)
    invisible(gc())
}
stopifnot(length(records) == 24L, length(visits) == 6L)
validate_benchmark_install(library_path, args[[3L]])
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dll_paths <- vapply(getLoadedDLLs(), function(info) info[["path"]], character(1))
write.table(data.frame(name = names(dll_paths), path = unname(dll_paths)),
    file.path(output, "dlls.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("PASS 24 logical/factor/ordered nonmissing-count controls; native visit counts were untimed\n")
