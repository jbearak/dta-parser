#!/usr/bin/env Rscript

# Diagnostic experiment: retain the baseline's complete column isolation,
# but skip redundant validation only after proving that a column-only verb
# returned the exact source vectors. No namespace or production-code edits.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(normalizePath(args[[1L]], mustWork = TRUE), .libPaths()))
output <- args[[2L]]
dir.create(output, recursive = TRUE, showWarnings = FALSE)
suppressPackageStartupMessages({ library(dtatools); library(dplyr); library(bench) })

source("benchmarks/r-dibble-dplyr/helpers.R")

trusted_environment <- new.env(parent = asNamespace("dtatools"))
trusted_environment$.type_dibble_columns <- function(data, caller) data
trusted_constructor <- dtatools:::.as_dibble
environment(trusted_constructor) <- trusted_environment

rename_prototype <- function(data) {
    source <- dtatools:::.reference_snapshot(data)
    result <- dplyr::rename(source, renamed = c01)
    addresses <- vapply(source, rlang::obj_address, character(1))
    stopifnot(all(vapply(result, rlang::obj_address, character(1)) %in% addresses))
    trusted_constructor(dtatools:::.isolate_shared_columns(result, NULL), "rename()")
}

records <- list()
for (kind in c("double", "string", "declared_character", "compact_int", "dict_string")) {
    rows <- if (kind == "dict_string") 100000L else 1000000L
    columns <- 16L
    cat("Prototype", kind, rows, columns, "\n")
    pair <- make_pair(kind, rows, columns)
    expected <- rename(pair$dibble, renamed = c01)
    actual <- rename_prototype(pair$dibble)
    stopifnot(identical(names(actual), names(expected)),
              identical(column_values(actual), column_values(expected)),
              identical(lapply(actual, attributes), lapply(expected, attributes)))
    # Both mutation directions and same-table aliases retain baseline behavior.
    before <- column_values(pair$dibble)
    alias <- actual
    replacement <- if (kind %in% c("string", "declared_character", "dict_string")) "z" else 9
    repl(actual, renamed = replacement, where = 1L)
    stopifnot(identical(column_values(pair$dibble), before),
              identical(column_values(alias), column_values(actual)))
    actual_before <- column_values(actual)
    repl(pair$dibble, c01 = replacement, where = 2L)
    stopifnot(identical(column_values(actual), actual_before))
    rm(expected, actual, alias, before, actual_before, pair)
    pair <- make_pair(kind, rows, columns)
    invisible(gc())
    mark <- bench::mark(
        baseline = rename(pair$dibble, renamed = c01),
        validation_once = rename_prototype(pair$dibble),
        iterations = 7L, check = FALSE, filter_gc = FALSE, memory = TRUE
    )
    record <- data.frame(kind, rows, columns, variant = as.character(mark$expression),
        median_ms = as.numeric(mark$median) * 1000,
        allocated_bytes = as.numeric(mark$mem_alloc),
        iterations = mark$n_itr, gc_count = mark$n_gc)
    print(record, row.names = FALSE)
    records[[length(records) + 1L]] <- record
    write.csv(do.call(rbind, records), file.path(output, "prototype.csv"), row.names = FALSE)
    if (kind == "string") {
        Rprof(file.path(output, "string-rename.Rprof"), interval = 0.001)
        for (index in seq_len(10L)) invisible(rename(pair$dibble, renamed = c01))
        Rprof(NULL)
        profile <- summaryRprof(file.path(output, "string-rename.Rprof"))
        write.csv(profile$by.total, file.path(output, "string-profile-total.csv"))
        write.csv(profile$by.self, file.path(output, "string-profile-self.csv"))
    }
    rm(mark, pair)
    invisible(gc())
}
cat("Prototype output, metadata, aliases, and two-way mutation isolation checks passed.\n")
