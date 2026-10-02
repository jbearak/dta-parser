args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
library(dtatools)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    file.path(normalizePath(args[[1L]]), 'dtatools')))
dir.create(args[[3L]], recursive = TRUE, showWarnings = FALSE)
results <- list()
native <- dtatools:::C_dtatools_egen_group
stats <- dtatools:::C_dtatools_egen_group_stats
for (n in c(0L, 1L, 3L)) for (keys in c(1L, 8193L)) {
    source <- c(2, 1, 2)[seq_len(n)]
    original <- writeBin(source, raw())
    columns <- rep(list(source), keys)
    expected <- switch(as.character(n), '0' = numeric(), '1' = 1, '3' = c(2, 1, 2))
    first <- switch(as.character(n), '0' = integer(), '1' = 1L, '3' = c(2L, 1L))
    .Call(stats, TRUE)
    value <- .Call(native, columns, TRUE, FALSE)
    counts <- .Call(stats, FALSE)
    stopifnot(identical(as.double(value$codes), expected), identical(value$first, first),
              identical(writeBin(source, raw()), original),
              counts[['prepared_values']] == n * keys,
              counts[['prepared_bytes']] == 8 * n * keys,
              counts[['scalar_values']] == 0)
    value <- .Call(native, columns, TRUE, FALSE)
    value <- NULL
    gc()
    path <- file.path(args[[3L]], paste0(n, '-', keys, '.txt'))
    Rprofmem(path)
    value <- tryCatch(.Call(native, columns, TRUE, FALSE), finally = Rprofmem(NULL))
    stopifnot(identical(as.double(value$codes), expected), identical(value$first, first))
    lines <- readLines(path)
    sizes <- as.double(sub(' .*', '', lines[grepl('^[0-9]+ ', lines)]))
    results[[length(results) + 1L]] <- data.frame(n, keys, sized_allocation_events = length(sizes),
        page_events = sum(grepl('^new page:', lines)),
        recorded_bytes = sum(sizes), largest_recorded_allocation = if (length(sizes)) max(sizes) else 0,
        prepared_values = counts[['prepared_values']], prepared_bytes = counts[['prepared_bytes']])
}
write.csv(do.call(rbind, results), args[[2L]], row.names = FALSE)
cat('Six empty/short/wide grouping cases passed; allocations are untimed diagnostics.\n')
