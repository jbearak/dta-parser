#!/usr/bin/env Rscript
# Supplement the unchanged memory runners with their recorded header-cell counts.
args <- commandArgs(TRUE)
if (length(args) != 6L) stop(
    "Usage: owned-heap.R LIBRARY SOURCE_SHA baseline|candidate KIND OPERATION ROWS")
stopifnot(args[[4L]] %in% c("double", "string", "declared_character", "logical", "factor", "ordered"))
paths <- file.path("benchmarks/r-dibble-dplyr", c(
    "helpers.R", "owned-double-helpers.R", "owned-atomic-helpers.R",
    "owned-double.R", "owned-double-memory.R", "owned-atomic.R",
    "owned-atomic-memory.R", "owned-heap.R"))
before_md5 <- unname(tools::md5sum(paths))
stopifnot(!anyNA(before_md5))
inner_args <- if (args[[4L]] == "double") args[-4L] else args
child <- new.env(parent = globalenv())
# Only the sourced script sees this argument adapter. No namespace is modified.
child$commandArgs <- function(trailingOnly = FALSE) {
    stopifnot(isTRUE(trailingOnly))
    inner_args
}
runner <- if (args[[4L]] == "double") "owned-double-memory.R" else "owned-atomic-memory.R"
sys.source(file.path("benchmarks/r-dibble-dplyr", runner), envir = child)
validate_benchmark_install(child$library_path, args[[2L]])
stopifnot(identical(unname(tools::md5sum(paths)), before_md5))

checkpoint_names <- c("prefixture", "prior", "after_result", "after_drop_source", "after_drop_result")
checkpoints <- lapply(checkpoint_names, get, envir = child, inherits = FALSE)
names(checkpoints) <- checkpoint_names
header_cells <- vapply(checkpoints, function(x) x["Ncells", "used"], 0)
vector_bytes <- vapply(checkpoints, function(x) x["Vcells", "used"] * 8, 0)
header_mb <- vapply(checkpoints, function(x) x["Ncells", 2L], 0)
stopifnot(all(is.finite(c(header_cells, vector_bytes, header_mb))),
          all(header_cells > 0), all(header_cells == trunc(header_cells)))
# R reports gc() MB totals rounded upward to 0.1 MiB. Infer the unique integer
# header size consistent with every checkpoint instead of assuming a platform.
possible_sizes <- seq_len(1024L)
matches <- vapply(possible_sizes, function(bytes) {
    all(abs(ceiling(10 * header_cells / 1024^2 * bytes) / 10 - header_mb) < 1e-9)
}, TRUE)
stopifnot(sum(matches) == 1L)
header_bytes_per_cell <- possible_sizes[matches]
tracked_heap <- header_cells * header_bytes_per_cell + vector_bytes
metrics <- c(
    retained_header_cells = header_cells[["after_result"]] - header_cells[["prior"]],
    excess_header_cells_after_drop_result = header_cells[["after_drop_result"]] - header_cells[["prefixture"]],
    retained_tracked_heap_bytes = tracked_heap[["after_result"]] - tracked_heap[["prior"]],
    excess_tracked_heap_bytes_after_drop_result = tracked_heap[["after_drop_result"]] - tracked_heap[["prefixture"]],
    released_tracked_heap_bytes_with_last_result = tracked_heap[["after_drop_source"]] - tracked_heap[["after_drop_result"]])
if (args[[3L]] == "candidate") stopifnot(
    metrics[["retained_tracked_heap_bytes"]] < 1000000,
    metrics[["excess_tracked_heap_bytes_after_drop_result"]] < 1000000)
cat("heap_source_sha", args[[2L]], "\nheap_library", child$library_path,
    "\nheap_mode", args[[3L]], "\nheap_kind", args[[4L]],
    "\nheap_operation", args[[5L]], "\nheap_rows", args[[6L]],
    "\nheap_header_bytes_per_cell", header_bytes_per_cell, "\n")
cat(paste("heap_runner_md5", paths, before_md5), sep = "\n")
cat("\n")
for (name in names(metrics)) cat("heap_", name, " ", format(metrics[[name]], scientific = FALSE, trim = TRUE, digits = 22), "\n", sep = "")
for (name in names(checkpoints)) {
    cat("heap_checkpoint", name, "header_cells", format(header_cells[[name]], scientific = FALSE, trim = TRUE, digits = 22),
        "vector_bytes", format(vector_bytes[[name]], scientific = FALSE, trim = TRUE, digits = 22),
        "header_reported_mb", header_mb[[name]], "\n")
}
cat("heap_scope R header cells plus vector heap; excludes external native allocations and unused heap capacity\n")
