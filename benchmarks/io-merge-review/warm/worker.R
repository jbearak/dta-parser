# Separate warm-in-process control. One warm read, full GC, then one read.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("read_dta", "read_arrow"))
method <- args[[1L]]
path <- normalizePath(args[[2L]], mustWork = TRUE)
root <- Sys.getenv("DTATOOLS_REVIEW_ROOT")
source(file.path(root, "benchmarks/reader-refresh/workers/benchmark-common.R"))
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
stopifnot(!"jsonlite" %in% loadedNamespaces())
read <- function() {
    if (method == "read_dta") dtatools::read_dta(path)
    else dtatools::read_arrow(path, verify = TRUE)
}
warmup <- read()
rm(warmup)
invisible(gc(full = TRUE))
started <- proc.time()
value <- read()
duration <- proc.time() - started
cat(sprintf("DTATOOLS_BENCH\tok\t%.9f\t%d\t%d\n", duration[["elapsed"]], nrow(value), ncol(value)))
cat(sprintf("DTATOOLS_CPU\t%.9f\t%.9f\n", duration[["user.self"]], duration[["sys.self"]]))
stopifnot(!"jsonlite" %in% loadedNamespaces())
