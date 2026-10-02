args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], Sys.getenv("DTATOOLS_COMPARATOR_LIBRARY"), .libPaths()))
library(dtatools)
stopifnot(normalizePath(find.package('dtatools')) == normalizePath(file.path(args[[1L]],'dtatools')))
r <- testthat::test_dir(system.file('tests/testthat', package='dtatools'), package='dtatools', reporter='summary', stop_on_failure=FALSE)
s <- as.data.frame(r); s$result <- NULL
write.csv(s,args[[2L]],row.names=FALSE)
counts <- colSums(s[c('passed','failed','error','warning','skipped')]); print(counts)
stopifnot(counts[['failed']]==0,counts[['error']]==0)
