#!/usr/bin/env Rscript

# This intentionally fails on the recorded Stage 2 baseline. Stage 3 requires
# it to pass for owned doubles; owned-double.R adds full selector/scaling gates.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(normalizePath(args[[1L]], mustWork = TRUE), .libPaths()))
suppressPackageStartupMessages({ library(dtatools); library(dplyr) })
rows <- 100000L
data <- dibble(x = dta_double(rep(1, rows)))
allocation <- function(value) {
    path <- tempfile()
    on.exit({ Rprofmem(NULL); unlink(path) })
    invisible(rename(value, renamed = x))
    Rprofmem(path, threshold = 10000)
    result <- rename(value, renamed = x)
    Rprofmem(NULL)
    stopifnot(identical(as.double(result$renamed), rep(1, rows)))
    records <- suppressWarnings(as.numeric(sub(" .*", "", readLines(path))))
    max(c(0, records[is.finite(records)]))
}
cat("Typed tibble largest allocation:", allocation(dtatools:::.reference_snapshot(data)), "bytes\n")
largest <- allocation(data)
cat("Dibble largest allocation:", largest, "bytes\n")
stopifnot(largest < 8 * rows)
