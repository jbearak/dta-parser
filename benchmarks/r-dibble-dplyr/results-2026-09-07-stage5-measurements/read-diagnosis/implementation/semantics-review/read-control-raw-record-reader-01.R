args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
root <- args[[1L]]
output <- args[[2L]]
series <- samples <- facts <- list()
for (repeat_id in 1:3) for (label in c('baseline-ec10','candidate-a2d8b6a')) {
    name <- sprintf('%s-read-control-v3-%02d', label, repeat_id)
    directory <- file.path(root, name)
    csv <- read.csv(file.path(directory, 'read-control.csv'), check.names=FALSE)
    states <- readRDS(file.path(directory, 'source-states.rds'))
    stopifnot(nrow(csv) == 8L, length(states) == 8L)
    for (i in 1:8) {
        raw <- readRDS(file.path(directory, paste0('raw-timing-',i,'.rds')))
        stopifnot(length(raw$samples)==1L)
        times <- as.numeric(raw$samples[[1L]])
        ms <- median(times) * 1000
        stopifnot(length(times)==7L, all(is.finite(times)), all(times>0),
                  identical(raw$iterations, 7L), raw$gc_count == csv$gc_count[[i]],
                  as.numeric(raw$allocation) == csv$bench_allocated_bytes[[i]],
                  abs(ms-raw$median_ms)<1e-10, abs(ms-csv$median_ms[[i]])<1e-10)
        series[[length(series)+1L]] <- data.frame(run=name, index=i, operation=csv$operation[[i]], rows=csv$rows[[i]],
             median_ms=ms, allocation=as.numeric(raw$allocation), gc_count=raw$gc_count, samples=length(times))
        samples[[length(samples)+1L]] <- data.frame(run=name,index=i,sample=1:7,seconds=times)
        s <- states[[i]]
        stopifnot(identical(s$operation, csv$operation[[i]]), s$rows==csv$rows[[i]])
        backing <- NULL
        for (phase in c('before','before_profile','before_timing','after')) {
            stopifnot(length(s[[phase]])==1L)
            x <- s[[phase]][[1L]]
            stopifnot(x$depth==as.integer(label=='candidate-a2d8b6a'), x$bytes==s$rows*8,
                      !x$exposed, !is.null(x$backing), !is.null(x$handle))
            if(is.null(backing)) backing <- x$backing else stopifnot(identical(backing,x$backing))
            facts[[length(facts)+1L]] <- data.frame(run=name,index=i,rows=s$rows,operation=s$operation,phase=phase,
                depth=x$depth,bytes=x$bytes,exposed=x$exposed,handle_shared=x$handle_shared,backing_private=x$backing_private,
                backing=x$backing,handle=x$handle)
        }
    }
}
write.csv(do.call(rbind,series),file.path(output,'read-control-raw-series-01.csv'),row.names=FALSE)
write.csv(do.call(rbind,samples),file.path(output,'read-control-raw-samples-01.csv'),row.names=FALSE)
write.csv(do.call(rbind,facts),file.path(output,'read-control-state-facts-01.csv'),row.names=FALSE)
cat('PASS 48 medians, 336 samples and 192 saved state facts; no control operations executed\n')
