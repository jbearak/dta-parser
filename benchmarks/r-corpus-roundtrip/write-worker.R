args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: write-worker.R INPUT_DTA OUTPUT_DTA")
script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
sys.source(
    file.path(script_dir, "..", "benchmark-common.R"),
    envir = environment()
)
benchmark_activate_library("dtatools")

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output <- dtatools:::.resolve_dta_write_path(args[[2L]])$path
data <- dtatools::read_dta(input)
gc()
started <- proc.time()[["elapsed"]]
status <- tryCatch({
    suppressWarnings(dtatools::save_dta(data, output, version = 19L))
    "ok"
}, error = function(condition) {
    message("dtatools write worker: ", conditionMessage(condition))
    "error"
})
elapsed <- proc.time()[["elapsed"]] - started
bytes <- if (file.exists(output)) file.info(output, extra_cols = FALSE)$size[[1L]] else NA_real_
cat(sprintf("DTATOOLS_WRITE\t%s\t%.9f\t%s\n", status, elapsed, bytes))
if (!identical(status, "ok")) quit(status = 1L)
