args <- commandArgs(TRUE)
.libPaths(c(args[[1]], .libPaths()))
suppressPackageStartupMessages({library(dtatools);library(dplyr);library(bench)})
source('benchmarks/r-dibble-dplyr/helpers.R')
for (kind in c('double','logical')) {
 pair <- if(kind=='double') make_pair(kind,1000000L,16L) else make_pair(kind,100000L,32L)
 operation <- operations$pipeline_five
 invisible(operation(pair$dibble))
 for(repeat_index in 1:3) {
  invisible(gc())
  b <- bench::mark(operation(pair$dibble),iterations=7,check=FALSE,filter_gc=FALSE)
  print(data.frame(kind,repeat_index,median_ms=as.numeric(b$median)*1000,allocated_bytes=as.numeric(b$mem_alloc),gc_count=b$n_gc))
 }
}
