args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], '<reader-work>/comparator-lib', .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(normalizePath(find.package('dtatools')) == normalizePath(file.path(args[[1L]], 'dtatools')))
r <- testthat::test_dir(args[[2L]], package='dtatools', reporter='summary', stop_on_failure=FALSE)
s <- as.data.frame(r); s$result <- NULL
write.csv(s, paste0(args[[3L]], '.csv'), row.names=FALSE)
counts <- colSums(s[c('passed','failed','error','warning','skipped')]); print(counts)
stopifnot(counts[['failed']]==0, counts[['error']]==0)
