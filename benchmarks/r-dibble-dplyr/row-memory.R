#!/usr/bin/env Rscript
# /usr/bin/time measures whole-process peak RSS, including startup/fixtures.
args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Usage: row-memory.R LIBRARY KIND SOURCE_SHA")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages({ library(dtatools); library(dplyr) })
stopifnot(identical(normalizePath(dirname(find.package("dtatools"))), library_path))
source("benchmarks/r-dibble-dplyr/helpers.R")
pair <- make_pair(args[[2L]], 1000000L, 16L)
locations <- seq.int(1L, 1000000L, by = 2L)
invisible(make_pair(args[[2L]], 4L, 2L)$dibble[1:2, ])
prior <- gc()
result <- pair$dibble[locations, ]
after <- gc()
stopifnot(is_dibble(result), nrow(result) == length(locations),
          identical(column_values(result), column_values(pair$typed_tibble[locations, ])))
cat("source_sha", args[[3L]], "\nkind", args[[2L]], "\n")
cat("retained_vector_heap_bytes", (after["Vcells", "used"] - prior["Vcells", "used"]) * 8, "\n")
cat("nominal_result_bytes", as.numeric(utils::object.size(result)), "\n")
