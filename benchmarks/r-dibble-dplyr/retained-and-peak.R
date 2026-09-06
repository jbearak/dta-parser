args <- commandArgs(TRUE)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages({library(dtatools); library(dplyr)})
source("benchmarks/r-dibble-dplyr/helpers.R")
pair <- make_pair(args[[2L]], 1000000L, 16L)
# Warm method planning on a small independent fixture; do not retain its output.
invisible(rename(make_pair(args[[2L]], 3L, 2L)$dibble, renamed = c01))
prior <- gc()
out <- rename(pair$dibble, renamed = c01)
retained <- gc()
stopifnot(is_dibble(out), identical(as.vector(out$renamed), as.vector(pair$dibble$c01)))
cat("library", args[[1L]], "\nkind", args[[2L]], "\n")
cat("retained_vector_heap_bytes", (retained["Vcells", "used"] - prior["Vcells", "used"]) * 8, "\n")
cat("nominal_result_bytes", as.numeric(utils::object.size(out)), "\n")
# /usr/bin/time's maximum RSS covers this complete process, including package
# startup and fixture construction, not an isolated operation-only peak.
