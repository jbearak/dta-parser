path <- '<work>/allocation-probe'
dyn.load(file.path(path, paste0('allocation', .Platform$dynlib.ext)))
gc.time(TRUE)
cases <- expand.grid(raw = c(TRUE, FALSE), bytes = c(4000000,8000000),
                     finalizer = c(FALSE, TRUE), fill = c(TRUE, FALSE))
iterations <- 384L
out <- list()
for(round in 1:3) {
  order <- if(round %% 2L) seq_len(nrow(cases)) else rev(seq_len(nrow(cases)))
  for(i in order) {
    case <- cases[i,]
    gc(); gc()
    .Call('probe_stats', TRUE)
    gc_before <- gc.time()
    before <- proc.time()
    for(j in seq_len(iterations)) value <- .Call('probe_alloc', case$raw, case$bytes, case$fill, case$finalizer)
    duration <- proc.time() - before
    gc_duration <- gc.time() - gc_before
    stats <- .Call('probe_stats', FALSE)
    rm(value)
    out[[length(out) + 1L]] <- cbind(round=round, case,
      allocation_us=stats[1]*1e6/iterations, overwrite_us=stats[2]*1e6/iterations,
      total_us=sum(duration[1:2])*1e6/iterations,
      gc_us=sum(gc_duration[1:2])*1e6/iterations, finalizers=stats[3])
  }
}
observations <- do.call(rbind,out)
write.csv(observations,file.path(path,'observations.csv'),row.names=FALSE)
print(aggregate(cbind(allocation_us,overwrite_us,total_us,gc_us,finalizers) ~ raw+bytes+finalizer+fill, observations,median),digits=4,row.names=FALSE)
