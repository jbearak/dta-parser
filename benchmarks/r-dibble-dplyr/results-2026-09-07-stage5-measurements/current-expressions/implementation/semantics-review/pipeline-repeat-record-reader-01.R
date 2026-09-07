# Reads retained objects only. No source or operation from the measured driver is evaluated.
options(warn=2)
root <- '/private/tmp/dta-direct-stage5-validation/root-expression-performance'
result <- list()
for (repeat_id in 1:3) for (source_name in c('baseline','candidate')) {
 run_name <- sprintf('%s-pipeline-repeat-%02d',source_name,repeat_id)
 folder <- file.path(root,run_name)
 grid <- read.csv(file.path(folder,'grid.csv'));rows <- read.csv(file.path(folder,'measurements.csv'))
 stopifnot(nrow(grid)==1L,nrow(rows)==2L,grid$rows==1000000L,grid$columns==16L,grid$groups==1L,grid$kind=='ungrouped',grid$operation=='pipeline_five')
 for (mode in c('safe_reference','direct')) {
  raw <- readRDS(file.path(folder,paste0('raw-timing-1-',mode,'.rds')))
  row <- rows[rows$mode==mode,,drop=FALSE]
  stopifnot(nrow(row)==1L,length(raw$samples)==1L,inherits(raw$samples[[1L]],'bench_time'))
  samples <- unclass(raw$samples[[1L]])
  stopifnot(is.double(samples),length(samples)==7L,all(is.finite(samples)&samples>0),identical(raw$iterations,7L),row$iterations==7L,raw$gc_count==row$gc_count,is.double(raw$median),!inherits(raw$median,'bench_time'))
  ms <- sort(samples)[[4L]]*1000
  stopifnot(identical(unname(raw$median),ms),abs(row$median_ms-ms)<=max(1,ms)*1e-12,as.numeric(raw$allocation)==row$bench_allocated_bytes)
  result[[length(result)+1L]] <- data.frame(run=run_name,mode,sample=1:7,seconds=samples,derived_median_ms=ms,allocation=as.numeric(raw$allocation),gc_count=raw$gc_count)
 }
}
write.csv(do.call(rbind,result),'/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/pipeline-repeat-raw-records-01.csv',row.names=FALSE)
cat('PASS six runs, 12 raw series, 84 samples, numeric millisecond medians and allocation/GC equality\n')
