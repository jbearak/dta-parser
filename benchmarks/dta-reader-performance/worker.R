# An independent read process for controlled kernel experiments.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
library_path <- normalizePath(Sys.getenv("DTATOOLS_BENCH_LIB"), mustWork=TRUE)
.libPaths(c(library_path, .libPaths()))
stopifnot(requireNamespace("dtatools", quietly=TRUE))
stopifnot(identical(normalizePath(find.package("dtatools")),
                    normalizePath(file.path(library_path, "dtatools"), mustWork=TRUE)))
path <- normalizePath(args[[1]])
mode <- args[[2]]
threads <- as.integer(args[[3]])
iterations <- as.integer(args[[4]])
stopifnot(mode %in% c("dta", "arrow", "metadata"), threads >= 0L, iterations >= 1L)
read_one <- switch(mode,
    dta = function() dtatools::read_dta(path, threads=threads),
    arrow = function() dtatools::read_arrow(path, threads=threads),
    metadata = function() dtatools::read_dta(path, n_max=0, threads=threads))
for (i in seq_len(iterations)) {
    gc(full=TRUE)
    start <- proc.time()[["elapsed"]]
    result <- read_one()
    elapsed <- proc.time()[["elapsed"]] - start
    cat(sprintf("READ\t%d\t%.9f\t%d\t%d\n", i, elapsed, nrow(result), ncol(result)))
    if (i < iterations) rm(result)
}
# A full signature is an untimed, optional correctness check in a separate run.
if (identical(Sys.getenv("DTA_READ_PERF_SIGNATURE"), "1")) {
    cat("SIGNATURE", dtatools::datasig(result), "\n")
}
