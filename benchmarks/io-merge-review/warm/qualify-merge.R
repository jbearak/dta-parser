args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
kind <- args[[1L]]
directory <- args[[2L]]
direction <- args[[3L]]
root <- Sys.getenv("DTATOOLS_REVIEW_ROOT")
source(file.path(root, "benchmarks/reader-refresh/workers/benchmark-common.R"))
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
load <- function(side) {
    if (kind == "ordinary") readRDS(file.path(directory, paste0(side, "-standard.rds")))
    else dtatools::read_dta(file.path(directory, paste0(side, ".dta")))
}
master <- load("master")
using <- load("using")
if (kind == "one-column") {
    master <- master[c("caseid", "s1")]
    using <- using[c("caseid", "s1")]
}
before <- c(dtatools::datasig(master), dtatools::datasig(using))
call <- function() suppressWarnings(
    if (direction == "1:m") dtatools::dta_merge(master, using, by = "caseid", relationship = direction)
    else dtatools::dta_merge(using, master, by = "caseid", relationship = direction)
)
warmup <- call()
warm_signature <- dtatools::datasig(warmup)
rm(warmup)
invisible(gc(full = TRUE))
result <- call()
stopifnot(nrow(result) == 440044L, ncol(result) == if (kind == "one-column") 3L else 201L)
signature <- dtatools::datasig(result)
stopifnot(identical(warm_signature, signature),
          identical(before, c(dtatools::datasig(master), dtatools::datasig(using))))
cat("QUALIFIED", kind, direction, signature, "\n", sep = "\t")
