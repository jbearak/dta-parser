#!/usr/bin/env Rscript
# One case per process. Whole-process RSS includes startup, fixtures and checks.
args <- commandArgs(TRUE)
if (length(args) != 6L) stop(
    "Usage: owned-atomic-memory.R LIBRARY SOURCE_SHA baseline|candidate KIND rename|pipeline_five|pipeline_50 ROWS")
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[2L]], args[[3L]])
mode <- args[[3L]]
kind <- args[[4L]]
operation <- args[[5L]]
rows <- as.integer(args[[6L]])
stopifnot(kind %in% atomic_kinds, operation %in% c("rename", "pipeline_five", "pipeline_50"),
          !is.na(rows), rows > 0L)
cat(paste(atomic_identity(args[[2L]], library_path, mode), collapse = "\n"), "\n")
run <- switch(operation,
    rename = function(x) dplyr::rename(x, changed = c01),
    pipeline_five = owned_pipeline,
    pipeline_50 = function(x) {
        for (i in seq_len(10L)) x <- owned_pipeline(x)
        x
    })
invisible(run(atomic_fixture(kind, 4L)))
prefixture <- gc()
data <- atomic_fixture(kind, rows)
frozen <- atomic_frozen(data, kind)
before <- atomic_state(data, mode)
prior <- gc()
result <- run(data)
after_result <- gc()
retained_with_source <- (after_result["Vcells", "used"] - prior["Vcells", "used"]) * 8
result_info <- atomic_state(result, mode)
atomic_unchanged_backings(before, data, mode)
atomic_preserved(data, frozen)
if (mode == "candidate") {
    indices <- if (operation == "rename") seq_len(16L) else c(2:16, 2L)
    stopifnot(identical(atomic_backings(result_info), atomic_backings(before[indices])),
              retained_with_source < 1000000)
}
expected <- atomic_pipeline_expected(frozen, operation)
atomic_check(result, frozen, expected)
rm(expected, frozen, data, before, result_info)
after_drop_source <- gc()
cat("kind", kind, "\noperation", operation, "\nrows", rows,
    "\nretained_with_source_vector_heap_bytes", retained_with_source,
    "\nvector_heap_bytes_after_drop_source", after_drop_source["Vcells", "used"] * 8,
    "\nnominal_result_bytes", as.numeric(utils::object.size(result)), "\n")
rm(result, run)
after_drop_result <- gc()
excess <- (after_drop_result["Vcells", "used"] - prefixture["Vcells", "used"]) * 8
cat("vector_heap_bytes_after_drop_result", after_drop_result["Vcells", "used"] * 8,
    "\nprefixture_vector_heap_bytes", prefixture["Vcells", "used"] * 8,
    "\nexcess_after_drop_result_bytes", excess,
    "\nreleased_with_last_result_bytes",
    (after_drop_source["Vcells", "used"] - after_drop_result["Vcells", "used"]) * 8, "\n")
if (mode == "candidate") stopifnot(excess < 1000000)
validate_benchmark_install(library_path, args[[2L]])
