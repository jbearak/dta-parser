args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
sha <- args[[2L]]
source('benchmarks/r-dibble-dplyr/helpers.R')
validate_benchmark_install(lib, sha)
audit <- '/private/tmp/dta-direct-stage4-validation/root-acceptance-c8ca0a4'
names <- c('generation-names', 'delayed-mask', 'delayed-private-mask', 'symbol-private-callback')
total <- 0L
for (name in names) {
    script <- file.path(audit, paste0(name, '-matrix.R'))
    result <- file.path(audit, paste0(name, '-candidate.rds'))
    log <- file.path(audit, paste0(name, '-candidate.log'))
    stopifnot(!file.exists(result), !file.exists(log))
    status <- system2(file.path(R.home('bin'), 'Rscript'),
        c('--vanilla', shQuote(script), shQuote(lib), shQuote(result)), stdout = log, stderr = log)
    stopifnot(status == 0L)
    actual <- readRDS(result)
    baseline <- readRDS(file.path(audit, paste0(name, '-baseline.rds')))
    stopifnot(identical(actual, baseline))
    cat(name, length(actual), 'exact historical behavior comparisons passed\n')
    total <- total + length(actual)
}
validate_benchmark_install(lib, sha)
cat('Exact package source', sha, '\nAll', total, 'R-only root regression cases passed\n')
