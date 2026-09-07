# Inspect saved facts only; no fixtures or native functions are run.
options(warn=2)
root <- '/private/tmp/dta-direct-stage5-validation/root-expression-performance'
records <- list()
for (mode in c('cold','warm')) {
 path <- file.path(root,paste0('candidate-a2d8b6a-read-setup-',mode,'-01'))
 before <- readRDS(file.path(path,'source-states-1.rds'))
 fork <- readRDS(file.path(path,'fork-states.rds'))
 stopifnot(identical(names(before),c('before','before_profile','before_timing')),identical(names(fork),c('source','result')))
 states <- c(before,fork)
 expected_backing <- vapply(states[[1L]],function(x)x$backing,'')
 for (phase in names(states)) {
  state <- states[[phase]]
  stopifnot(length(state)==8L,identical(vapply(state,function(x)x$backing,''),expected_backing))
  for (i in seq_along(state)) {
   x <- state[[i]];stopifnot(x$depth==1L,x$bytes==800000,!x$exposed)
   records[[length(records)+1L]] <- data.frame(mode,phase,column=i,backing=x$backing,depth=x$depth,bytes=x$bytes,exposed=x$exposed,handle_shared=x$handle_shared,backing_private=x$backing_private)
  }
 }
}
write.csv(do.call(rbind,records),'/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/atomic-read-setup-states-01.csv',row.names=FALSE)
cat('PASS both retained modes, 80 source/result facts, unchanged depth-one unexposed backing across five saved phases\n')
