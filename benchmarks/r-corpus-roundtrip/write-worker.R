args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: write-worker.R INPUT_DTA OUTPUT_DTA")
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, winslash = "/", mustWork = TRUE), .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE)) stop("dtaparser is required")

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output <- args[[2L]]
data <- dtaparser::read_dta(input)
gc()
started <- proc.time()[["elapsed"]]
status <- tryCatch({
    suppressWarnings(dtaparser::write_dta(data, output, version = 19L))
    "ok"
}, error = function(condition) {
    message("dtaparser write worker: ", conditionMessage(condition))
    "error"
})
elapsed <- proc.time()[["elapsed"]] - started
bytes <- if (file.exists(output)) file.info(output, extra_cols = FALSE)$size[[1L]] else NA_real_
cat(sprintf("DTAPARSER_WRITE\t%s\t%.9f\t%s\n", status, elapsed, bytes))
if (!identical(status, "ok")) quit(status = 1L)
