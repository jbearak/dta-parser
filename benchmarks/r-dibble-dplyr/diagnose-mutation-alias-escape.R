#!/usr/bin/env Rscript
# Known ownership prerequisite, expected to fail on starting main 5ad44406.
# This reaches the private seam whose early sharing proof must remain valid
# through expression evaluation. Ordinary public preflight currently masks it
# by adding conservative references, so simply moving that preflight is unsafe.
args <- commandArgs(TRUE)
if (length(args) != 1L) stop("Usage: diagnose-mutation-alias-escape.R LIBRARY")
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
data <- list(dtatools:::.deep_copy_value(dta_byte(1:2)))
names(data) <- "x"
class(data) <- "data.frame"
attr(data, "row.names") <- c(NA_integer_, -2L)
stopifnot(!.Call(dtatools:::C_dtatools_shared_columns, data)[[1L]])
escaped <- NULL
dtatools:::.mutate_data(data, rlang::quo(x),
    rlang::quo({ escaped <<- x; 2 }), rlang::quo(1L), generate = FALSE)
cat("Escaped values:", as.double(escaped), "\n")
cat("Supplied table:", as.double(data$x), "\n")
stopifnot(identical(as.double(data$x), c(2, 2)),
          identical(as.double(escaped), c(1, 2)))
