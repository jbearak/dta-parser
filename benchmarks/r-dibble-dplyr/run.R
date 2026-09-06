#!/usr/bin/env Rscript

# Run against an isolated library built from the recorded package source.
args <- commandArgs(TRUE)
if (length(args) < 3L) {
    stop("Usage: run.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA [ITERATIONS]")
}
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
source_sha <- args[[3L]]
iterations <- if (length(args) >= 4L) as.integer(args[[4L]]) else 7L
stopifnot(!is.na(iterations), iterations > 0L, capabilities("profmem"))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages({
    library(dtatools)
    library(dplyr)
    library(bench)
})
stopifnot(identical(normalizePath(dirname(find.package("dtatools"))), library_path))

writeLines(c(
    paste("source_sha", source_sha),
    paste("library", library_path),
    paste("iterations", iterations),
    paste("utc", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    capture.output(sessionInfo())
), file.path(output, "session.txt"))

source("benchmarks/r-dibble-dplyr/helpers.R")

cases <- data.frame(
    kind = c("double", "compact_int", "string", "dict_string", "mixed",
             "double", "compact_int", "string", "double", "compact_int",
             "declared_character", "logical", "factor"),
    rows = c(rep(100000L, 5L), rep(1000000L, 3L), 100L, 100L,
             1000000L, 100000L, 100000L),
    columns = c(rep(32L, 5L), rep(16L, 3L), 1000L, 1000L, 16L, 32L, 32L)
)
case_filter <- Sys.getenv("DTATOOLS_BENCH_KINDS", "")
if (nzchar(case_filter)) cases <- cases[cases$kind %in% strsplit(case_filter, ",", fixed = TRUE)[[1L]], ]
results <- list()
stages <- list()

extract <- function(mark, case, operation, field = "container") {
    labels <- as.character(mark$expression)
    records <- data.frame(
        kind = case$kind, rows = case$rows, columns = case$columns,
        operation = operation, label = labels,
        median_ms = as.numeric(mark$median) * 1000,
        min_ms = as.numeric(mark$min) * 1000,
        allocated_bytes = as.numeric(mark$mem_alloc),
        iterations = mark$n_itr, gc_count = mark$n_gc
    )
    names(records)[5L] <- field
    records
}

for (case_index in seq_len(nrow(cases))) {
    case <- cases[case_index, ]
    cat("Case", case$kind, case$rows, case$columns, "\n")
    pair <- make_pair(case$kind, case$rows, case$columns)
    original_values <- column_values(pair$typed_tibble)
    original_attributes <- lapply(pair$typed_tibble, attributes)
    compact_before <- compact_state(pair$dibble)
    local_operations <- operations
    if (case$kind %in% c("double", "compact_int")) {
        local_operations$mutate_arithmetic <- function(data) mutate(data, c01 = c01 + 1)
    }
    for (name in names(local_operations)) {
        operation <- local_operations[[name]]
        expected <- operation(pair$typed_tibble)
        actual <- operation(pair$dibble)
        stopifnot(is_dibble(actual), identical(dim(actual), dim(expected)),
                  identical(names(actual), names(expected)),
                  identical(column_values(actual), column_values(expected)),
                  identical(lapply(actual, attributes), lapply(expected, attributes)),
                  identical(column_values(pair$dibble), original_values),
                  identical(lapply(pair$dibble, attributes), original_attributes),
                  identical(compact_state(pair$dibble), compact_before))
        rm(expected, actual)
        invisible(gc())
        mark <- bench::mark(
            typed_tibble = operation(pair$typed_tibble),
            dibble = operation(pair$dibble),
            iterations = iterations, check = FALSE, filter_gc = FALSE,
            memory = TRUE
        )
        records <- extract(mark, case, name)
        results[[length(results) + 1L]] <- records
        write.csv(do.call(rbind, results), file.path(output, "operations.csv"), row.names = FALSE)
        cat(name, paste(sprintf("%s %.3f ms %.3f MB", records$container,
                               records$median_ms, records$allocated_bytes / 1e6), collapse = "; "), "\n")
        rm(mark)
    }
    renamed <- rename(pair$typed_tibble, renamed = c01)
    isolated <- dtatools:::.isolate_shared_columns(renamed, NULL)
    # Disjoint measurements of constituent stages. They are not summed to
    # claim an exact profile, because retention/GC differs from the full call.
    stage_mark <- bench::mark(
        snapshot = dtatools:::.reference_snapshot(pair$dibble),
        isolate = dtatools:::.isolate_shared_columns(renamed, NULL),
        revalidate_columns = dtatools:::.type_dibble_columns(isolated),
        reconstruct = dtatools:::.as_dibble(isolated),
        iterations = iterations, check = FALSE, filter_gc = FALSE, memory = TRUE
    )
    stages[[length(stages) + 1L]] <- extract(stage_mark, case, "rename_stages", "stage")
    write.csv(do.call(rbind, stages), file.path(output, "stages.csv"), row.names = FALSE)
    rm(pair, renamed, isolated, stage_mark, original_values, original_attributes)
    invisible(gc())
}

cat("All equivalence, input preservation, metadata, and compact-source checks passed.\n")
