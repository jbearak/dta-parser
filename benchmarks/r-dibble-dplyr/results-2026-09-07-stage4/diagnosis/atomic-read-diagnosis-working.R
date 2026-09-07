args <- commandArgs(TRUE)
stopifnot(length(args) == 4L, !file.exists(args[[4L]]))
source('benchmarks/r-dibble-dplyr/owned-atomic-helpers.R')
source('benchmarks/r-dibble-dplyr/helpers.R')
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages({library(dtatools, lib.loc=args[[1L]]);library(dplyr)})
stopifnot(normalizePath(find.package('dtatools')) == normalizePath(file.path(args[[1L]],'dtatools')))
cat('DEVELOPMENT ONLY:', args[[2L]], normalizePath(find.package('dtatools')), '\n')
print(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]))
results <- list()
for (kind in atomic_kinds) {
  x <- atomic_fixture(kind, 1000000L, 8L)
  frozen <- atomic_frozen(x, kind)
  before <- atomic_state(x, args[[3L]])
  idx <- seq.int(1L, nrow(x), by = 2L)
  output <- tempfile(fileext = '.dta')
  arrow <- tempfile(fileext = '.arrow')
  operations <- list(subset = function() x[idx, ], any_na = function() anyNA(x$c01),
    nonmissing = function() sum(!is.na(x$c01)), character = function() as.character(x$c01),
    dta = function() atomic_write_dta(x, output, kind),
    arrow = function() save_arrow(x, arrow, compression = 'uncompressed', threads = 1L))
  for (op in names(operations)) {
    m <- bench::mark(operations[[op]](), iterations = 5L, check = FALSE, filter_gc = FALSE)
    atomic_preserved(x, frozen)
    atomic_unchanged_backings(before, x, args[[3L]])
    results[[length(results) + 1L]] <- data.frame(kind, operation = op,
      median_ms = as.numeric(m$median) * 1000, bytes = as.numeric(m$mem_alloc))
  }
  unlink(c(output, arrow)); rm(x); gc()
}
write.csv(do.call(rbind, results), args[[4L]], row.names = FALSE)
