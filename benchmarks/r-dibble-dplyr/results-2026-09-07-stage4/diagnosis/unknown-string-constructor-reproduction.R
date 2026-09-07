# Guarded replay of the retained independent foreign-constructor probe.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
source('benchmarks/r-dibble-dplyr/helpers.R')
validate_benchmark_install(args[[1L]], args[[2L]])
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = args[[1L]]))
cat('source', args[[2L]], '\nDLL_md5', tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]), '\n')
for (rows in c(64L, 1000L, 1000000L)) {
    original <- rep(c('a', 'b'), length.out = rows)
    foreign <- data.table::data.table(x = rep(c('a', 'b'), length.out = rows))
    data.table::setattr(foreign$x, 'class', 'stage4_unknown')
    key <- iconv('caf\u00e9', to = 'latin1'); Encoding(key) <- 'latin1'
    data.table::setattr(foreign$x, key, 'remove')
    result <- dta_string(foreign$x, 'str8')
    stopifnot(identical(attributes(result), list(stata.string.storage = 'str8',
        class = c('dta_string', 'vctrs_vctr', 'character'))))
    data.table::set(foreign, i = 1L, j = 'x', value = 'changed')
    cat('rows', rows, 'captured first after foreign write:', as.character(result)[[1L]], '\n')
    validate_benchmark_install(args[[1L]], args[[2L]])
    stopifnot(identical(as.character(result), original))
    result[2L] <- 'new'
    stopifnot(identical(as.character(foreign$x), c('changed', original[-1L])),
              identical(as.character(result), c('a', 'new', original[-c(1L, 2L)])))
    cat('Both mutation directions isolated.\n')
}
validate_benchmark_install(args[[1L]], args[[2L]])
