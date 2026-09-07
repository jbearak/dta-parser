.libPaths(c('/private/tmp/dta-direct-stage4-validation/working-library',.libPaths()))
library(dtatools)
ns <- asNamespace('dtatools')
probe <- dyn.load('accessor_probe.so')
make <- getNativeSymbolInfo('make_probe',probe)$address
paths <- c('accessor_probe.c','accessor_probe.so','accessor_probe.R',getLoadedDLLs()[['dtatools']][['path']])
identity <- tools::md5sum(paths)
cat('DEVELOPMENT ONLY, minimized getter experiment; no writes or subset methods\n')
print(identity)
results <- list()
for(kind in c('logical','factor','character')) {
 raw <- switch(kind,logical=rep(c(TRUE,FALSE,NA),length.out=1000000L),
               factor=factor(rep(c('a','b',NA),length.out=1000000L),levels=c('a','b','unused')),
               character=rep(c('a','b','c'),length.out=1000000L))
 stopifnot(!ns$.is_altrep(raw))
 values <- c(list(ordinary=raw,production=.Call(ns$C_dtatools_capture_column,raw)),
             setNames(lapply(0:4,function(mode).Call(make,raw,mode)),
                      c('record_elt','record_pointer','direct_elt','direct_pointer','external_pointer')))
 stopifnot(!is.null(.Call(ns$C_dtatools_owned_info,values$production)))
 operations <- list(nonmissing=function(x)sum(!is.na(x)),character=function(x)as.character(x))
 if(kind != 'logical')operations$any_na <- function(x)anyNA(x)
 if(kind == 'logical')operations$integer <- function(x)as.integer(x)
 for(name in names(operations)) {
  op <- operations[[name]];expected <- op(raw)
  for(variant in names(values)) {
   value <- values[[variant]]
   actual <- op(value);stopifnot(identical(actual,expected))
   m <- bench::mark(op(value),iterations=21L,check=FALSE,filter_gc=FALSE)
   results[[length(results)+1L]]<-data.frame(kind,operation=name,variant,ms=as.numeric(m$median)*1000,bytes=as.numeric(m$mem_alloc))
  }
 }
}
stopifnot(identical(identity,tools::md5sum(paths)))
result<-do.call(rbind,results);print(result);write.csv(result,'accessor-probe-external-results.csv',row.names=FALSE)
