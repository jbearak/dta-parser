# One benchmark operation per invocation. Reads warm in-process; every write
# measurement runs in its own fresh process, mirroring the large-scale write
# methodology: the timer covers only the save call, after the input exists in
# memory.
library_path <- Sys.getenv("DTATOOLS_BENCH_LIB")
if (nzchar(library_path)) .libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))

arguments <- commandArgs(trailingOnly = TRUE)
task <- arguments[[1L]]

emit <- function(...) cat(paste(..., sep = "\t"), "\n", sep = "")

read_iterations <- function(read_call, iterations) {
    invisible(read_call())
    gc(full = TRUE)
    for (iteration in seq_len(iterations)) {
        started <- proc.time()
        result <- read_call()
        duration <- proc.time() - started
        elapsed <- duration[["elapsed"]]
        emit("iteration", iteration, sprintf("%.6f", elapsed),
             nrow(result), ncol(result))
        emit("cpu", iteration, sprintf("%.9f", duration[["user.self"]]),
             sprintf("%.9f", duration[["sys.self"]]))
        rm(result)
        gc(full = TRUE)
    }
}

if (task == "read-dta") {
    path <- arguments[[2L]]
    iterations <- as.integer(arguments[[3L]])
    read_iterations(function() read_dta(path), iterations)
} else if (task == "read-arrow") {
    path <- arguments[[2L]]
    iterations <- as.integer(arguments[[3L]])
    stopifnot(arguments[[4L]] %in% c("verify", "noverify"))
    verify <- identical(arguments[[4L]], "verify")
    read_iterations(function() read_arrow(path, verify = verify), iterations)
} else stop("reader-only worker: unknown task")
