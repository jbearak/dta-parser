#!/usr/bin/env Rscript
# Stage 1 direct column operations, against an exact isolated installation.
args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Usage: columns.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
source("benchmarks/r-dibble-dplyr/helpers.R")
validate_benchmark_install(library_path, args[[3L]])
output <- args[[2L]]
dir.create(output, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages({ library(dtatools); library(dplyr); library(bench) })
stopifnot(identical(normalizePath(dirname(find.package("dtatools"))), library_path))
writeLines(c(paste("source_sha", args[[3L]]), paste("library", library_path),
             capture.output(sessionInfo())), file.path(output, "session.txt"))
results <- list()
retained <- list()
for (kind in c("double", "string", "declared_character")) {
    pair <- make_pair(kind, 1000000L, 16L)
    before <- column_values(pair$dibble)
    operations <- list(
        rename = function(x) dplyr::rename(x, renamed = c01),
        select = function(x) dplyr::select(x, dplyr::everything()),
        relocate = function(x) dplyr::relocate(x, c01, .after = c16)
    )
    for (name in names(operations)) {
        operation <- operations[[name]]
        expected <- operation(pair$typed_tibble)
        actual <- operation(pair$dibble)
        stopifnot(identical(column_values(actual), column_values(expected)),
                  identical(lapply(actual, attributes), lapply(expected, attributes)),
                  identical(names(actual), names(expected)), is_dibble(actual))
        # This is R's nominal retained object size, not native payload accounting
        # or a measurement of sharing. Stage 1 retains ordinary copied payloads.
        retained[[length(retained) + 1L]] <- data.frame(
            kind, operation = name,
            nominal_result_bytes = as.numeric(utils::object.size(actual)))
        rm(actual, expected)
        invisible(gc())
        # All fixture construction, first-use warming and assertions are outside
        # timing. The reference delegates the verb and uses this installation's
        # same safe finalizer, retaining the complete isolation contract.
        delegated <- function(x) dtatools:::.close_dibble(
            x, operation(dtatools:::.reference_snapshot(x)))
        mark <- bench::mark(
            direct = operation(pair$dibble),
            safe_delegation = delegated(pair$dibble),
            iterations = 7L, check = FALSE, filter_gc = FALSE
        )
        rows <- data.frame(kind, operation = name,
            path = as.character(mark$expression),
            median_ms = as.numeric(mark$median) * 1000,
            allocated_bytes = as.numeric(mark$mem_alloc),
            iterations = mark$n_itr, gc_count = mark$n_gc)
        print(rows)
        # This gate belongs to stage 1; the separate <1MB future ownership gate
        # remains intentionally disabled until owned backing lands.
        if (kind %in% c("string", "declared_character") && name == "rename") {
            stopifnot(rows$allocated_bytes[rows$path == "direct"] <= 130000000)
        }
        results[[length(results) + 1L]] <- rows
        write.csv(do.call(rbind, results), file.path(output, "columns.csv"), row.names = FALSE)
        write.csv(do.call(rbind, retained), file.path(output, "retained.csv"), row.names = FALSE)
        stopifnot(identical(column_values(pair$dibble), before))
    }
    rm(pair, before)
    invisible(gc())
}
