args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
root <- normalizePath(args[[2L]], mustWork = TRUE)
for (mib in c(63L, 65L)) {
    rows <- mib * 1024^2 / 4
    data <- dibble(x = dta_long(rep.int(7L, rows)))
    save_arrow(data, file.path(root, paste0('retained-', mib, '.arrow')),
               compression = 'uncompressed', threads = 1L, checksums = TRUE)
    rm(data)
    gc()
}
values <- c(1, -2, 0, 3, NA_real_, tagged_missing('a'), tagged_missing('z'), 1.5)
for (storage in c('double', 'float')) {
    value <- if (storage == 'double') dta_double(values) else dta_float(values)
    save_arrow(dibble(x = value), file.path(root, paste0('tiny-', storage, '.arrow')),
               compression = 'uncompressed', threads = 1L, checksums = TRUE)
}
saveRDS(values, file.path(root, 'tiny-reference.rds'), compress = FALSE)
cat('Prepared checksummed, uncompressed fixtures.\n')
