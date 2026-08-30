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
        started <- proc.time()[["elapsed"]]
        result <- read_call()
        elapsed <- proc.time()[["elapsed"]] - started
        emit("iteration", iteration, sprintf("%.6f", elapsed),
             nrow(result), ncol(result))
        rm(result)
        gc(full = TRUE)
    }
}

if (task == "prepare-arrow") {
    input <- arguments[[2L]]
    output <- arguments[[3L]]
    checksums <- length(arguments) < 4L ||
        !identical(arguments[[4L]], "nochecksums")
    data <- read_dta(input)
    gc(full = TRUE)
    started <- proc.time()[["elapsed"]]
    save_arrow(data, output, checksums = checksums)
    elapsed <- proc.time()[["elapsed"]] - started
    emit("save_arrow", sprintf("%.6f", elapsed),
         file.size(input), file.size(output), nrow(data), ncol(data))
} else if (task == "read-dta") {
    path <- arguments[[2L]]
    iterations <- as.integer(arguments[[3L]])
    read_iterations(function() read_dta(path), iterations)
} else if (task == "read-arrow") {
    path <- arguments[[2L]]
    iterations <- as.integer(arguments[[3L]])
    verify <- identical(arguments[[4L]], "verify")
    read_iterations(function() read_arrow(path, verify = verify), iterations)
} else if (task == "write-primary") {
    writer <- arguments[[2L]]
    input <- arguments[[3L]]
    output <- arguments[[4L]]
    data <- read_dta(input)
    gc(full = TRUE)
    started <- proc.time()[["elapsed"]]
    switch(writer,
        save_dta = save_dta(data, output, version = 19L),
        save_arrow = save_arrow(data, output),
        save_arrow_nochecksums = save_arrow(data, output, checksums = FALSE),
        haven = haven::write_dta(data, output, version = 15L),
        stop("unknown writer")
    )
    elapsed <- proc.time()[["elapsed"]] - started
    emit(writer, sprintf("%.6f", elapsed), file.size(output))
} else if (task == "write-secondary") {
    writer <- arguments[[2L]]
    fixture_script <- arguments[[3L]]
    rows <- as.integer(arguments[[4L]])
    output <- arguments[[5L]]
    source(fixture_script)
    data <- make_standard_r_write_fixture(rows)
    gc(full = TRUE)
    started <- proc.time()[["elapsed"]]
    switch(writer,
        save_dta = save_dta(data, output, version = 19L),
        save_arrow = save_arrow(data, output),
        save_arrow_nochecksums = save_arrow(data, output, checksums = FALSE),
        haven = haven::write_dta(data, output, version = 15L),
        stop("unknown writer")
    )
    elapsed <- proc.time()[["elapsed"]] - started
    emit(writer, sprintf("%.6f", elapsed), file.size(output))
} else {
    stop("unknown task")
}
