# Read retained serialized samples only. No fixture or operation is evaluated.
options(warn = 2)
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
run <- args[[1L]]
out <- args[[2L]]
grid <- read.csv(file.path(run, 'grid.csv'), stringsAsFactors = FALSE)
rows <- read.csv(file.path(run, 'measurements.csv'), stringsAsFactors = FALSE)
stopifnot(nrow(grid) == 25L, nrow(rows) == 50L)
records <- vector('list', 50L)
k <- 0L
for (i in seq_len(nrow(grid))) for (mode in c('safe_reference', 'direct')) {
    k <- k + 1L
    raw <- readRDS(file.path(run, paste0('raw-timing-', i, '-', mode, '.rds')))
    selected <- rows$mode == mode
    for (name in names(grid)) selected <- selected & rows[[name]] == grid[[name]][[i]]
    stopifnot(sum(selected) == 1L, length(raw$samples) == 1L)
    row <- rows[selected, , drop = FALSE]
    sample <- unclass(raw$samples[[1L]])
    stopifnot(inherits(raw$samples[[1L]], 'bench_time'), is.double(sample),
              length(sample) == 7L, all(is.finite(sample) & sample > 0),
              identical(raw$iterations, 7L), row$iterations == 7L,
              raw$gc_count == row$gc_count, raw$gc_count >= 0,
              is.double(raw$median), !inherits(raw$median, 'bench_time'))
    med <- sort(sample)[[4L]] * 1000
    stopifnot(abs(med - row$median_ms) <= max(1, abs(med)) * 1e-12,
              identical(unname(raw$median), med),
              as.numeric(raw$allocation) == row$bench_allocated_bytes)
    records[[k]] <- data.frame(case = i, mode, sample = seq_along(sample), seconds = sample,
         derived_median_ms = med, bench_allocated_bytes = as.numeric(raw$allocation),
         iterations = raw$iterations, gc_count = raw$gc_count)
}
write.csv(do.call(rbind, records), out, row.names = FALSE)
cat('PASS 50 series, 350 positive raw second samples, plain numeric millisecond medians, allocation and GC CSV equality\n')
