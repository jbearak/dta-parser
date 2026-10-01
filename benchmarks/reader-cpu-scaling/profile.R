# Separate diagnostic workload, never part of the clean timing observations.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
library_path <- normalizePath(Sys.getenv("DTATOOLS_BENCH_LIB"), mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
stopifnot(requireNamespace("dtatools", quietly = TRUE),
    identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
              normalizePath(file.path(library_path, "dtatools"))))
path <- normalizePath(args[[1L]], mustWork = TRUE)
threads <- as.integer(args[[2L]])
stopifnot(threads %in% c(0L, 1L))
reader <- dtatools::read_dta
cat("READY\n")
flush(stdout())
started <- proc.time()[["elapsed"]]
iterations <- 0L
repeat {
    value <- reader(path, threads = threads)
    stopifnot(nrow(value) == as.integer(args[[3L]]), ncol(value) == as.integer(args[[4L]]))
    iterations <- iterations + 1L
    if (proc.time()[["elapsed"]] - started >= 12) break
}
cat(sprintf("COMPLETE\t%d\n", iterations))
