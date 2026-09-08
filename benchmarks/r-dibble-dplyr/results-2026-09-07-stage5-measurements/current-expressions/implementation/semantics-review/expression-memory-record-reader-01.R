options(warn=2)
root <- '/private/tmp/dta-direct-stage5-validation/root-expression-performance'
records <- list()
for (source in c('baseline-f622','candidate-a2d8b6a')) for (size in c('100k','1m')) for (mode in c('direct','safe')) {
 name <- paste(source,'memory',size,mode,'01',sep='-')
 path <- file.path(root,name)
 rows <- if (size=='100k') 100000L else 1000000L
 states <- readRDS(file.path(path,'source-result-states.rds'))
 expected <- c('source-0','result-0','source-5','result-5','source-50','result-50')
 stopifnot(identical(names(states),expected))
 for (phase in expected) {
  state <- states[[phase]]
  stopifnot(nrow(state)==16L,identical(state$column,c('x','s',paste0('p',3:16))),all(state$phase==phase),all(state$owned),all(state$depth==1),all(state$bytes==rows*8),!any(state$exposed),all(state$handle_shared),!any(state$backing_private))
  records[[length(records)+1L]] <- cbind(data.frame(run=rep(name,16)),state)
 }
 stopifnot(identical(states[['source-0']]$backing,states[['result-0']]$backing))
 for (calls in c(5,50)) {
  stopifnot(identical(states[['source-0']]$backing,states[[paste0('source-',calls)]]$backing),identical(states[['source-0']]$backing[-1L],states[[paste0('result-',calls)]]$backing[-1L]),states[['source-0']]$backing[[1L]]!=states[[paste0('result-',calls)]]$backing[[1L]])
 }
}
write.csv(do.call(rbind,records),'/private/tmp/dta-direct-stage5-validation/implementation/semantics-review/expression-memory-retained-states-01.csv',row.names=FALSE)
cat('PASS eight processes, 48 checkpoint objects, 768 unexposed depth-one source/result states; source and unwritten backing preserved\n')
