args<-commandArgs(TRUE); stopifnot(length(args)==2L)
.libPaths(c(args[[1L]],.libPaths()));library(dtatools)
source('benchmarks/r-dibble-dplyr/helpers.R');source('benchmarks/r-dibble-dplyr/owned-atomic-helpers.R')
cat('DEVELOPMENT ONLY',args[[2L]],normalizePath(find.package('dtatools')),'\n');print(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]))
for(kind in c('logical','ordered')) {
 x<-atomic_fixture(kind,1000000L,8L);frozen<-atomic_frozen(x,kind);before<-owned_state(x)
 raw<-atomic_raw(kind,1000000L,8L)[[1L]]
 op<-if(kind=='logical')function(x)mean(x,na.rm=TRUE) else function(x)range(x,na.rm=TRUE)
 expected<-op(raw); actual<-op(x$c01);stopifnot(identical(expected,actual))
 m<-bench::mark(op(x$c01),iterations=15L,check=FALSE,filter_gc=FALSE)
 cat(kind,as.numeric(m$median)*1000,'ms',as.numeric(m$mem_alloc),'Rbytes\n')
 owned_native('C_dtatools_native_copy_stats',TRUE);invisible(op(x$c01));print(owned_native('C_dtatools_native_copy_stats',FALSE))
 atomic_preserved(x,frozen);stopifnot(identical(atomic_backings(before),atomic_backings(owned_state(x))))
}
