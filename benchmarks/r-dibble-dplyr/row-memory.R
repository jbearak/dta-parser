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
stopifnot(is_dibble(pair$dibble))
compact_before <- compact_state(pair$dibble)
if (args[[2L]] %in% c("compact_int", "dict_string")) stopifnot(all(compact_before))
public_attributes <- function(data) {
    attr(data, ".dtatools_ref_state") <- NULL
    class(data) <- dtatools:::.reference_base_classes(class(data))
    data
}
source_bytes <- serialize(public_attributes(pair$dibble), NULL)
stopifnot(identical(compact_state(pair$dibble), compact_before))
locations <- seq.int(1L, 1000000L, by = 2L)
invisible(make_pair(args[[2L]], 4L, 2L)$dibble[1:2, ])
prior <- gc()
result <- pair$dibble[locations, ]
after <- gc()
stopifnot(is_dibble(result), nrow(result) == length(locations),
          identical(column_values(result), column_values(unserialize(source_bytes)[locations, ])),
          identical(serialize(public_attributes(pair$dibble), NULL), source_bytes),
          identical(compact_state(pair$dibble), compact_before))
cat("source_sha", args[[3L]], "\nkind", args[[2L]], "\n")
cat("runner_md5", unname(tools::md5sum("benchmarks/r-dibble-dplyr/row-memory.R")), "\n")
cat("retained_vector_heap_bytes", (after["Vcells", "used"] - prior["Vcells", "used"]) * 8, "\n")
cat("nominal_result_bytes", as.numeric(utils::object.size(result)), "\n")
