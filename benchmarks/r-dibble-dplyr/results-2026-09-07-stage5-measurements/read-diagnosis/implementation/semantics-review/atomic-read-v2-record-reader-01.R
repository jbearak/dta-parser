# Read completed RDS/CSV only; no fixture, benchmark or native helper is executed.
options(warn=2)
root <- '/private/tmp/dta-direct-stage5-validation/root-expression-performance'
names <- c(unlist(lapply(1:3,function(i)c(sprintf('baseline-ec10-read-repeat-v2-%02d',i),sprintf('candidate-a2d8b6a-read-repeat-v2-%02d',i)))),unlist(lapply(1:3,function(i)c(sprintf('baseline-f622-arrow-repeat-v2-%02d',i),sprintf('candidate-a2d8b6a-arrow-repeat-v2-%02d',i)))),'baseline-ec10-read-minimum-v2-01','candidate-a2d8b6a-read-minimum-v2-01')
samples <- states <- list()
for (run in names) {
 path <- file.path(root,run);measurements <- read.csv(file.path(path,'owned-atomic.csv'))
 for (i in seq_len(nrow(measurements))) {
  row <- measurements[i,,drop=FALSE];raw <- readRDS(file.path(path,paste0('raw-timing-',i,'.rds')))
  stopifnot(length(raw$samples)==1L,inherits(raw$samples[[1L]],'bench_time'))
  seconds <- unclass(raw$samples[[1L]])
  stopifnot(is.double(seconds),length(seconds)==7L,all(is.finite(seconds)&seconds>0),identical(raw$iterations,7L),row$iterations==7L,raw$gc_count==row$gc_count,is.double(raw$median_ms),!inherits(raw$median_ms,'bench_time'))
  ms <- sort(seconds)[[4L]]*1000
  stopifnot(identical(unname(raw$median_ms),ms),abs(row$median_ms-ms)<=max(1,ms)*1e-12,as.numeric(raw$allocation)==row$bench_allocated_bytes)
  samples[[length(samples)+1L]] <- cbind(data.frame(run,index=i),row[rep(1,7),c('kind','operation','rows','columns')],data.frame(sample=1:7,seconds,derived_median_ms=ms,allocation=as.numeric(raw$allocation),gc_count=raw$gc_count))
  facts <- readRDS(file.path(path,paste0('source-states-',i,'.rds')))
  stopifnot(identical(names(facts),c('before','before_profile','before_timing')))
  baseline <- vapply(facts[[1L]],function(x)x$backing,'')
  for (phase in names(facts)) {
   values <- facts[[phase]];stopifnot(length(values)==row$columns,identical(vapply(values,function(x)x$backing,''),baseline))
   for (column in seq_along(values)) {
    x <- values[[column]]
    stopifnot(x$bytes==row$rows*if(row$kind=='declared_character')8 else 4,!x$exposed,x$handle_shared,!x$backing_private,x$depth==if(startsWith(run,'baseline-ec10'))0L else 1L)
    states[[length(states)+1L]] <- data.frame(run,index=i,kind=row$kind,operation=row$operation,rows=row$rows,columns=row$columns,phase,column,backing=x$backing,bytes=x$bytes,depth=x$depth,exposed=x$exposed,handle_shared=x$handle_shared,backing_private=x$backing_private)
   }
  }
 }
}
write.csv(do.call(rbind,samples),'/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/atomic-read-v2-raw-records-01.csv',row.names=FALSE)
write.csv(do.call(rbind,states),'/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/atomic-read-v2-states-01.csv',row.names=FALSE)
cat('PASS 14 runs,174 series,1218 saved seconds samples,3672 stable saved state facts; ms/allocation/GC match\n')
