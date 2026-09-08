# Recalculate retained records only. No timed or profiled operation executes.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
root <- args[[1L]]
out <- args[[2L]]
keys <- c('rows','columns','groups','kind','operation')
runs <- c('candidate-622-wide-minimum-01','candidate-622-width-repeat-01')
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
write.csv(do.call(rbind,records),file.path(out,'repair-guard-raw-recalculation-01.csv'),row.names=FALSE)
folder <- file.path(root,'candidate-622-wide-profile-01')
profiles <- list()
for(mode in c('safe_reference','direct')) {
    path <- file.path(folder,paste0(mode,'.Rprof'))
    raw <- readLines(path)
    stopifnot(identical(raw[[1L]],'GC profiling: sample.interval=1000'),length(raw)>1L)
    recomputed <- summaryRprof(path)
    saved <- readRDS(file.path(folder,paste0(mode,'-summary.rds')))
    stopifnot(identical(recomputed,saved),saved$sample.interval==0.001,
              isTRUE(all.equal(saved$sampling.time,(length(raw)-1L)*0.001)))
    for(kind in c('self','total')) {
        table <- saved[[paste0('by.',kind)]]
        wanted <- data.frame(frame=rownames(table),table,row.names=NULL)
        actual <- read.csv(file.path(folder,paste0(mode,'-by-',kind,'.csv')),stringsAsFactors=FALSE)
        stopifnot(isTRUE(all.equal(actual,wanted,tolerance=1e-12,check.attributes=FALSE)))
    }
    profiles[[mode]] <- data.frame(mode,samples=length(raw)-1L,
         interval_seconds=saved$sample.interval,sampling_time=saved$sampling.time,
         samples_with_profile_loop=sum(grepl('"profile_loop"',raw[-1L],fixed=TRUE)),
         gc_samples=sum(grepl('"<GC>"',raw[-1L],fixed=TRUE)))
}
write.csv(do.call(rbind,profiles),file.path(out,'repair-guard-profile-recalculation-01.csv'),row.names=FALSE)
snapshots <- lapply(c('safe_reference-source-before.rds','safe_reference-source-after.rds',
                     'direct-source-before.rds','direct-source-after.rds'),
                     function(name)readRDS(file.path(folder,name)))
stopifnot(all(vapply(snapshots,identical,logical(1),snapshots[[1L]])))
x <- snapshots[[1L]]
stopifnot(length(x$values)==64L,identical(x$table$names,c('x','s',paste0('p',3:64))),
          identical(x$table$row.names,c(NA_integer_,-12L)),identical(x$table$label,'Expression benchmark'),
          identical(x$values[[1L]],rep(c(1,2,3,4),3L)),identical(x$values[[2L]],rep(c('aa','b'),6L)))
for(i in 3:64)stopifnot(identical(x$values[[i]],rep(as.double(i),12L)))
checks <- dget(file.path(folder,'checks.R'))
stopifnot(identical(names(checks),c('safe_reference','direct')))
for(item in checks){
 stopifnot(identical(item$profiled,TRUE),identical(item$calls,2000L),identical(item$source_and_output_checks,'pass'))
 for(condition in item[c('cleanup_before','cleanup_after')])
  stopifnot('error'%in%condition$classes,grepl('Obsolete data mask',condition$message,fixed=TRUE))
}
cat('PASS 14 raw timing series /98 samples, exact seconds-to-ms medians and allocation/GC records; two raw profiles reproduce all retained RDS/CSV summaries; four identical source snapshots and obsolete-mask checks\n')
