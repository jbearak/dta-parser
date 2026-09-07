#!/usr/bin/env Rscript

# This intentionally fails on the recorded Stage 2 baseline. Stage 3 requires
# it to pass for owned doubles. Both limits below cover recorded allocations
# above 10,000 bytes; owned-double.R adds unthresholded selector/scaling gates.
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
    records <- records[is.finite(records)]
    c(largest = max(c(0, records)), total = sum(records))
}
typed <- allocation(dtatools:::.reference_snapshot(data))
cat("Typed tibble largest allocation:", typed[["largest"]], "bytes\n")
cat("Typed tibble total recorded allocation:", typed[["total"]], "bytes\n")
owned <- allocation(data)
largest <- owned[["largest"]]
cat("Dibble largest allocation:", largest, "bytes\n")
cat("Dibble total recorded allocation:", owned[["total"]], "bytes\n")
stopifnot(largest < 8 * rows)
stopifnot(owned[["total"]] < 8 * rows)
