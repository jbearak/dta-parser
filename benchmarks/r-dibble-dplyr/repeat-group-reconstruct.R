#!/usr/bin/env Rscript
# Controlled repeats for the small grouped-reconstruction investigation.
args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Usage: repeat-group-reconstruct.R LIBRARY OUTPUT SOURCE_SHA")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
source("benchmarks/r-dibble-dplyr/helpers.R")
validate_benchmark_install(library_path, args[[3L]])
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages({ library(dtatools); library(dplyr); library(bench) })
stopifnot(identical(normalizePath(dirname(find.package("dtatools"))), library_path))
public_attributes <- function(data) {
    attr(data, ".dtatools_ref_state") <- NULL
    class(data) <- dtatools:::.reference_base_classes(class(data))
    data
}
results <- list()
for (repeat_id in seq_len(3L)) {
    data <- make_pair("double", 10000L, 16L)$dibble
    gen(data, group = dta_double(rep(seq_len(1000L), length.out = nrow(data))))
    data <- group_by(data, group)
    stopifnot(is_dibble(data), !any(compact_state(data)))
    source_bytes <- serialize(public_attributes(data), NULL)
    candidate <- unserialize(source_bytes)[seq.int(1L, nrow(data), by = 2L), ]
    expected <- dtatools:::.close_dibble(data, dplyr_reconstruct(candidate, unserialize(source_bytes)))
    actual <- dplyr_reconstruct(candidate, data)
    stopifnot(identical(public_attributes(actual), public_attributes(expected)),
              identical(serialize(public_attributes(data), NULL), source_bytes),
              !any(compact_state(data)))
    rm(actual, expected)
    invisible(gc())
    mark <- bench::mark(value = dplyr_reconstruct(candidate, data), iterations = 15L,
                        check = FALSE, filter_gc = FALSE, memory = TRUE)
    stopifnot(identical(serialize(public_attributes(data), NULL), source_bytes),
              !any(compact_state(data)))
    results[[repeat_id]] <- data.frame(source_sha = args[[3L]], repeat_id,
        runner_md5 = unname(tools::md5sum("benchmarks/r-dibble-dplyr/repeat-group-reconstruct.R")),
        median_ms = as.numeric(mark$median) * 1000, allocated_bytes = as.numeric(mark$mem_alloc),
        iterations = mark$n_itr, gc_count = mark$n_gc)
    rm(data, candidate, mark, source_bytes)
    invisible(gc())
}
write.csv(do.call(rbind, results), args[[2L]], row.names = FALSE)
print(do.call(rbind, results))
