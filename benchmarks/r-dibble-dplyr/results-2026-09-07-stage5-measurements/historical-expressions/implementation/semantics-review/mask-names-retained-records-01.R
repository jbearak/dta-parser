# Recalculate retained records only. No timed or profiled operation executes.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
root <- args[[1L]]
out <- args[[2L]]
keys <- c('rows','columns','groups','kind','operation')
runs <- c('candidate-ad976-wide-minimum-01','candidate-ad976-width-repeat-01')
records <- list()
for (run in runs) {
    folder <- file.path(root,run)
    grid <- read.csv(file.path(folder,'grid.csv'),stringsAsFactors=FALSE)
    rows <- read.csv(file.path(folder,'measurements.csv'),stringsAsFactors=FALSE)
    expected <- if(grepl('minimum',run,fixed=TRUE)) 1L else 6L
    stopifnot(nrow(grid)==expected,nrow(rows)==expected*2L,
              !anyDuplicated(grid[keys]),!anyDuplicated(rows[c(keys,'mode')]))
    for(i in seq_len(nrow(grid))) for(mode in c('safe_reference','direct')) {
        selected <- rows$mode==mode
        for(key in keys) selected <- selected & rows[[key]]==grid[[key]][[i]]
        stopifnot(sum(selected)==1L)
        row <- rows[selected,,drop=FALSE]
        raw <- readRDS(file.path(folder,paste0('raw-timing-',i,'-',mode,'.rds')))
        stopifnot(length(raw$samples)==1L,inherits(raw$samples[[1L]],'bench_time'))
        sample <- unclass(raw$samples[[1L]])
        stopifnot(length(sample)==7L,all(is.finite(sample) & sample>0),
                  identical(raw$iterations,7L),row$iterations==7L,
                  raw$gc_count==row$gc_count,raw$gc_count>=0)
        median_ms <- sort(sample)[[4L]]*1000
        stopifnot(!inherits(raw$median,'bench_time'),identical(unname(raw$median),median_ms),
                  abs(median_ms-row$median_ms)<=max(1,abs(median_ms))*1e-12,
                  as.numeric(raw$allocation)==row$bench_allocated_bytes)
        records[[length(records)+1L]] <- data.frame(run,case=i,mode,sample=seq_along(sample),
             seconds=sample,derived_median_ms=median_ms,allocation=as.numeric(raw$allocation),gc_count=raw$gc_count)
    }
}
write.csv(do.call(rbind,records),file.path(out,'mask-names-raw-recalculation-01.csv'),row.names=FALSE)
cat('PASS 14 raw timing series /98 samples, exact seconds-to-ms medians and allocation/GC records\n')
