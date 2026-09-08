args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
root <- args[[1L]]
output <- args[[2L]]
series <- samples <- facts <- visit_records <- tiny_records <- list()
for (repeat_id in 1:3) for (label in c('baseline-ec10','candidate-a2d8b6a')) {
    name <- sprintf('%s-read-count-control-v1-%02d', label, repeat_id)
    directory <- file.path(root, name)
    csv <- read.csv(file.path(directory, 'read-count-control.csv'), check.names=FALSE)
    states <- readRDS(file.path(directory, 'source-states.rds'))
    stopifnot(nrow(csv) == 24L, length(states) == 24L)
    visits <- readRDS(file.path(directory,'untimed-native-visits.rds'))
    stopifnot(length(visits)==6L)
    for (v in visits) {
        stopifnot(v$kind %in% c('logical','factor','ordered'), v$rows %in% c(100000L,1000000L),
            identical(v$expected,as.integer(v$rows*0.75)), identical(v$native_count_and_visits,c(as.double(v$expected),as.double(v$rows))))
        visit_records[[length(visit_records)+1L]] <- data.frame(run=name,kind=v$kind,rows=v$rows,count=v$expected,visits=v$native_count_and_visits[[2L]])
    }
    tiny <- readRDS(file.path(directory,'tiny-checks.rds'))
    stopifnot(length(tiny)==24L)
    for (x in tiny) {
        expected_counts <- c(empty=0L,nonmissing=2L,all_missing=0L,mixed=3L)
        stopifnot(x$kind %in% c('logical','factor','ordered'),x$case %in% names(expected_counts),x$container %in% c('ordinary','table_column'),
            identical(x$expected,unname(expected_counts[[x$case]])),identical(x$type,if(x$kind=='logical') 'logical' else 'integer'))
        attrs <- if(x$kind=='logical') list(label='Tiny count control') else list(levels=c('a','b','unused'),class=if(x$kind=='factor') 'factor' else c('ordered','factor'),label='Tiny count control')
        stopifnot(identical(x$attributes,attrs))
        tiny_records[[length(tiny_records)+1L]] <- data.frame(run=name,kind=x$kind,case=x$case,container=x$container,count=x$expected,type=x$type)
    }
    for (i in 1:24) {
        raw <- readRDS(file.path(directory, paste0('raw-timing-',i,'.rds')))
        stopifnot(length(raw$samples)==1L)
        times <- as.numeric(raw$samples[[1L]])
        ms <- median(times) * 1000
        stopifnot(length(times)==7L, all(is.finite(times)), all(times>0),
                  identical(raw$iterations, 7L), raw$gc_count == csv$gc_count[[i]],
                  as.numeric(raw$allocation) == csv$bench_allocated_bytes[[i]],
                  abs(ms-raw$median_ms)<1e-10, abs(ms-csv$median_ms[[i]])<1e-10)
        series[[length(series)+1L]] <- data.frame(run=name, index=i, kind=csv$kind[[i]], operation=csv$operation[[i]], rows=csv$rows[[i]],
             median_ms=ms, allocation=as.numeric(raw$allocation), gc_count=raw$gc_count, samples=length(times))
        samples[[length(samples)+1L]] <- data.frame(run=name,index=i,sample=1:7,seconds=times)
        s <- states[[i]]
        stopifnot(identical(s$operation, csv$operation[[i]]), s$rows==csv$rows[[i]])
        backing <- NULL
        for (phase in c('before','before_profile','before_timing','after')) {
            stopifnot(length(s[[phase]])==1L)
            x <- s[[phase]][[1L]]
            stopifnot(x$depth==as.integer(label=='candidate-a2d8b6a'), x$bytes==s$rows*4,
                      !x$exposed, !is.null(x$backing), !is.null(x$handle))
            if(is.null(backing)) backing <- x$backing else stopifnot(identical(backing,x$backing))
            facts[[length(facts)+1L]] <- data.frame(run=name,index=i,kind=s$kind,rows=s$rows,operation=s$operation,phase=phase,
                depth=x$depth,bytes=x$bytes,exposed=x$exposed,handle_shared=x$handle_shared,backing_private=x$backing_private,
                backing=x$backing,handle=x$handle)
        }
    }
}
write.csv(do.call(rbind,visit_records),file.path(output,'read-count-untimed-visits-01.csv'),row.names=FALSE)
write.csv(do.call(rbind,tiny_records),file.path(output,'read-count-tiny-records-measured-01.csv'),row.names=FALSE)
write.csv(do.call(rbind,series),file.path(output,'read-count-raw-series-01.csv'),row.names=FALSE)
write.csv(do.call(rbind,samples),file.path(output,'read-count-raw-samples-01.csv'),row.names=FALSE)
write.csv(do.call(rbind,facts),file.path(output,'read-count-state-facts-01.csv'),row.names=FALSE)
cat('PASS 144 medians, 1008 samples, 576 states, 36 untimed count/visit records and 144 tiny records; no control operations executed\n')
