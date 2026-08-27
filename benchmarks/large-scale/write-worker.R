args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || !(args[[1L]] %in% c("dtaparser", "haven"))) {
    stop("usage: write-worker.R dtaparser|haven INPUT_DTA OUTPUT_DTA")
}

writer <- args[[1L]]
input <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, winslash = "/", mustWork = TRUE),
            .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE) ||
    !requireNamespace("haven", quietly = TRUE)) {
    stop("dtaparser and haven are required")
}

data <- if (writer == "dtaparser") {
    dtaparser::read_dta(input)
} else {
    haven::read_dta(input)
}
rows <- nrow(data)
columns <- ncol(data)
invisible(gc())
options(warn = 2)
started <- proc.time()[["elapsed"]]
status <- tryCatch({
    if (writer == "dtaparser") {
        dtaparser::write_dta(data, output, version = 19L)
    } else {
        haven::write_dta(data, output, version = 15L)
    }
    "ok"
}, error = function(condition) {
    message(writer, " write worker: ", conditionMessage(condition))
    "error"
})
elapsed <- proc.time()[["elapsed"]] - started
bytes <- if (file.exists(output)) {
    file.info(output, extra_cols = FALSE)$size[[1L]]
} else NA_real_
cat(sprintf(
    "SYNTHETIC_WRITE\t%s\t%s\t%.9f\t%s\t%s\t%s\n",
    writer, status, elapsed, rows, columns, bytes
))
if (status != "ok") quit(status = 1L)
