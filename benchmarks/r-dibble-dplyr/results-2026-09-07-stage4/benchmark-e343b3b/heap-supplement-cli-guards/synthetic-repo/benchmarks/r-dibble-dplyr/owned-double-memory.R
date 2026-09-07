#!/usr/bin/env Rscript
# Run each case in a fresh process under /usr/bin/time -l on macOS.
# Its peak RSS includes package startup, fixtures, validation and the operation.
args <- commandArgs(TRUE)
if (length(args) != 5L) {
    stop("Usage: owned-double-memory.R LIBRARY SOURCE_SHA baseline|candidate rename|pipeline_five|pipeline_50 ROWS")
}
source("benchmarks/r-dibble-dplyr/owned-double-helpers.R")
library_path <- owned_benchmark_start(args[[1L]], args[[2L]], args[[3L]])
mode <- args[[3L]]
operation <- args[[4L]]
rows <- as.integer(args[[5L]])
stopifnot(operation %in% c("rename", "pipeline_five", "pipeline_50"),
          !is.na(rows), rows > 0L)
cat(paste(owned_runner_identity(args[[2L]], library_path, mode), collapse = "\n"), "\n")
run <- switch(operation,
    rename = function(x) dplyr::rename(x, changed = c01),
    pipeline_five = owned_pipeline,
    pipeline_50 = function(x) {
        for (i in seq_len(10L)) x <- owned_pipeline(x)
        x
    })
invisible(run(owned_fixture(4L)))
prefixture <- gc()
data <- owned_fixture(rows)
frozen <- owned_frozen(data)
owned_assert_state(data, mode)
prior <- gc()
result <- run(data)
after_result <- gc()
retained_with_source <- (after_result["Vcells", "used"] - prior["Vcells", "used"]) * 8
owned_assert_state(result, mode)
owned_preserved(data, frozen)
if (mode == "candidate") {
    input_info <- owned_state(data)
    result_info <- owned_state(result)
    expected_indices <- if (operation == "rename") seq_len(16L) else c(2:16, 2L)
    stopifnot(identical(vapply(result_info, `[[`, "", "backing"),
                        vapply(input_info[expected_indices], `[[`, "", "backing")),
              retained_with_source < 1000000)
    rm(input_info, result_info)
}
expected <- owned_expected_columns(frozen)
indices <- if (operation == "rename") seq_len(16L) else c(2:16, 2L)
expected_names <- if (operation == "rename") c("changed", expected$names[-1L]) else c(expected$names[-1L], "c01")
expected <- list(names = expected_names, values = expected$values[indices],
                 attributes = expected$attributes[indices])
stopifnot(identical(owned_columns(result), expected))
owned_assert_table(result, frozen, expected_names, rows)
rm(expected, frozen, data)
after_drop_source <- gc()
cat("operation", operation, "\nrows", rows,
    "\nretained_with_source_vector_heap_bytes", retained_with_source,
    "\nvector_heap_bytes_after_drop_source", after_drop_source["Vcells", "used"] * 8,
    "\nnominal_result_bytes", as.numeric(utils::object.size(result)), "\n")
# A reference-free baseline distinguishes retained input/result payloads from
# package startup. Dropping the final result must release all payload history.
rm(result, run)
after_drop_result <- gc()
excess <- (after_drop_result["Vcells", "used"] - prefixture["Vcells", "used"]) * 8
cat("vector_heap_bytes_after_drop_result", after_drop_result["Vcells", "used"] * 8,
    "\nprefixture_vector_heap_bytes", prefixture["Vcells", "used"] * 8,
    "\nexcess_after_drop_result_bytes", excess,
    "\nreleased_with_last_result_bytes",
    (after_drop_source["Vcells", "used"] - after_drop_result["Vcells", "used"]) * 8, "\n")
if (mode == "candidate") stopifnot(excess < 1000000)
