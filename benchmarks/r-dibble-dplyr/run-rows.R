#!/usr/bin/env Rscript
# Run from the repository root against a fresh exact-source installation.
args <- commandArgs(TRUE)
if (length(args) < 3L) stop("Usage: run-rows.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA [ITERATIONS]")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
source_sha <- args[[3L]]
iterations <- if (length(args) > 3L) as.integer(args[[4L]]) else 9L
stopifnot(iterations > 0L, capabilities("profmem"))
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages({ library(dtatools); library(dplyr); library(bench) })
stopifnot(identical(normalizePath(dirname(find.package("dtatools"))), library_path))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
writeLines(c(paste("source_sha", source_sha),
             paste("runner_md5", unname(tools::md5sum("benchmarks/r-dibble-dplyr/run-rows.R"))),
             paste("library", library_path),
             paste("iterations", iterations), paste("utc", format(Sys.time(), tz = "UTC", usetz = TRUE)),
             capture.output(sessionInfo())), file.path(output, "session.txt"))
source("benchmarks/r-dibble-dplyr/helpers.R")

cases <- data.frame(kind = c(rep(c("double", "compact_int", "string", "mixed"), each = 2L),
                             "dict_string", "logical", "factor", "double", "compact_int"),
                    rows = c(rep(c(100000L, 1000000L), 4L), rep(100000L, 3L), 100L, 100L),
                    columns = c(rep(16L, 8L), rep(32L, 3L), 1000L, 1000L))
results <- list()
record <- function(operation, data, case, name) {
    invisible(gc())
    mark <- bench::mark(value = operation(data), iterations = iterations,
                        check = FALSE, filter_gc = FALSE, memory = TRUE)
    row <- data.frame(kind = case$kind, rows = case$rows, columns = case$columns,
                      operation = name, median_ms = as.numeric(mark$median) * 1000,
                      allocated_bytes = as.numeric(mark$mem_alloc), iterations = mark$n_itr,
                      gc_count = mark$n_gc)
    results[[length(results) + 1L]] <<- row
    write.csv(do.call(rbind, results), file.path(output, "rows.csv"), row.names = FALSE)
    cat(case$kind, case$rows, case$columns, name, row$median_ms, row$allocated_bytes, "\n")
}
public_attributes <- function(data) {
    attr(data, ".dtatools_ref_state") <- NULL
    class(data) <- dtatools:::.reference_base_classes(class(data))
    data
}
for (index in seq_len(nrow(cases))) {
    case <- cases[index, ]
    pair <- make_pair(case$kind, case$rows, case$columns)
    data <- pair$dibble
    stopifnot(is_dibble(data))
    compact_before <- compact_state(data)
    if (case$kind %in% c("compact_int", "dict_string")) stopifnot(all(compact_before))
    source_bytes <- serialize(public_attributes(data), NULL)
    stopifnot(identical(compact_state(data), compact_before))
    locations <- seq.int(1L, nrow(data), by = 2L)
    all_rows <- seq_len(nrow(data))
    ops <- list(bracket_half = function(d) d[locations, ],
                bracket_all = function(d) d[all_rows, ],
                slice_helper = function(d) slice_dta_rows(d, locations),
                row_hook = function(d) dplyr_row_slice(d, locations),
                safe_delegation = function(d) dtatools:::.close_dibble(
                    d, dtatools:::.reference_snapshot(d)[locations, ]))
    expected <- dtatools:::.close_dibble(data, pair$typed_tibble[locations, ])
    for (name in names(ops)) {
        actual <- ops[[name]](data)
        oracle <- if (name == "bracket_all") unserialize(source_bytes) else expected
        stopifnot(identical(public_attributes(actual), public_attributes(oracle)),
                  identical(serialize(public_attributes(data), NULL), source_bytes),
                  identical(compact_state(data), compact_before))
        rm(actual)
        record(ops[[name]], data, case, name)
        stopifnot(identical(serialize(public_attributes(data), NULL), source_bytes),
                  identical(compact_state(data), compact_before))
    }
    # Isolate gather costs from grouping and finalization, without summing
    # these measurements into a claimed whole-operation decomposition.
    gather <- function(d) dtatools:::.dta_merge_slice_columns(
        dtatools:::.reference_snapshot(d), locations, fill_string_missing = FALSE)
    invisible(gather(data))
    record(gather, data, case, "gather_only")
    stopifnot(identical(serialize(public_attributes(data), NULL), source_bytes),
              identical(compact_state(data), compact_before))
    rm(pair, data, expected, ops, source_bytes, compact_before)
    invisible(gc())
}

for (rows in c(10000L, 100000L, 1000000L)) {
    pair <- make_pair("double", rows, 16L)
    data <- pair$dibble
    gen(data, group = dta_double(rep(seq_len(1000L), length.out = rows)))
    data <- group_by(data, group)
    snapshot <- dtatools:::.reference_snapshot(data)
    compact_before <- compact_state(data)
    stopifnot(!any(compact_before))
    source_bytes <- serialize(public_attributes(data), NULL)
    stopifnot(identical(compact_state(data), compact_before))
    locations <- seq.int(1L, rows, by = 2L)
    candidate <- dtatools:::.reference_snapshot(data)[locations, ]
    case <- data.frame(kind = "grouped_double", rows = rows, columns = 17L)
    ops <- list(grouped_bracket = function(d) d[locations, ],
                grouped_hook = function(d) dplyr_row_slice(d, locations),
                grouped_reconstruct = function(d) dplyr_reconstruct(candidate, d),
                group_validation = function(d) dtatools:::.as_mutation_data(d, allow_grouped = TRUE),
                grouped_filter = function(d) filter(d, c01 > 1),
                grouped_mutate = function(d) mutate(d, c01 = c02))
    for (name in names(ops)) {
        actual <- ops[[name]](data)
        if (is.data.frame(actual)) {
            expected <- switch(name,
                grouped_bracket = snapshot[locations, ],
                grouped_hook = dplyr_row_slice(snapshot, locations),
                grouped_reconstruct = dplyr_reconstruct(candidate, snapshot),
                grouped_filter = filter(snapshot, c01 > 1),
                grouped_mutate = mutate(snapshot, c01 = c02))
            expected <- dtatools:::.close_dibble(data, expected)
            stopifnot(identical(public_attributes(actual), public_attributes(expected)))
            dtatools:::.as_mutation_data(actual, allow_grouped = TRUE)
            rm(expected)
        } else {
            stopifnot(identical(actual$names, names(data)), identical(actual$nrow, nrow(data)))
        }
        stopifnot(identical(serialize(public_attributes(data), NULL), source_bytes),
                  identical(compact_state(data), compact_before))
        rm(actual)
        record(ops[[name]], data, case, name)
        stopifnot(identical(serialize(public_attributes(data), NULL), source_bytes),
                  identical(compact_state(data), compact_before))
    }
    rm(data, pair, ops, candidate, snapshot, source_bytes, compact_before)
    invisible(gc())
}
cat("Public row equivalence, source preservation and grouped validity checks passed.\n")
