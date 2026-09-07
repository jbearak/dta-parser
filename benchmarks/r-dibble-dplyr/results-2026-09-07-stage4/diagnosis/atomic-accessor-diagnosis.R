args<-commandArgs(TRUE)
stopifnot(length(args)==3L,!file.exists(args[[3L]]))
.libPaths(c(args[[1L]],.libPaths()))
library(dtatools)
source('benchmarks/r-dibble-dplyr/helpers.R')
source('benchmarks/r-dibble-dplyr/owned-atomic-helpers.R')
cat('DEVELOPMENT ONLY',args[[2L]],normalizePath(find.package('dtatools')),'\n')
print(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]))
results<-list()
for(kind in atomic_kinds) {
 x<-atomic_fixture(kind,1000000L,1L);frozen<-atomic_frozen(x,kind);before<-owned_state(x)
 raw<-atomic_raw(kind,1000000L,1L)[[1L]]
 operations<-list(any_na=function(x)anyNA(x),nonmissing=function(x)sum(!is.na(x)),character=function(x)as.character(x))
 if(kind %in% c('logical','factor','ordered'))operations$integer<-function(x)as.integer(x)
 if(kind=='logical')operations$mean<-function(x)mean(x,na.rm=TRUE)
 for(name in names(operations)) {
  operation<-operations[[name]]
  expected<-operation(raw)
  actual<-operation(x$c01)
  stopifnot(identical(actual,expected))
  m<-bench::mark(operation(x$c01),iterations=15L,check=FALSE,filter_gc=FALSE)
  results[[length(results)+1L]]<-data.frame(kind,operation=name,ms=as.numeric(m$median)*1000,bytes=as.numeric(m$mem_alloc))
 }
 atomic_preserved(x,frozen)
 stopifnot(identical(atomic_backings(before),atomic_backings(owned_state(x))))
}
result<-do.call(rbind,results);print(result);write.csv(result,args[[3L]],row.names=FALSE)
print(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]))
