args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(lib, .libPaths()))
library(dtatools, lib.loc = lib)
stopifnot(identical(normalizePath(find.package('dtatools')), file.path(lib, 'dtatools')))
cat('library', lib, '\nDLL_md5', unname(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']])), '\n')
make <- function(kind, empty = FALSE) {
    x <- if (empty) data.frame(row.names = 1:3) else data.frame(x = 1:3)
    if (kind == 'tibble') x <- tibble::as_tibble(x)
    if (kind == 'dibble') x <- as_dibble(x)
    reserve_columns(x, n = 8L)
}
public <- function(x) list(names = names(x), rows = .row_names_info(x, 0L),
    values = lapply(x, function(v) if (is.numeric(v)) as.double(v) else as.vector(v)))
results <- list()
for (kind in c('frame', 'tibble', 'dibble')) {
    for (empty in c(FALSE, TRUE)) {
        for (capture in c('names', 'attributes', 'copy', 'active_value', 'runtime_name', 'arbitrary_value')) {
            data <- make(kind, empty)
            before <- names(data)
            box <- new.env(parent = emptyenv())
            if (capture == 'names') box$saved <- names(data)
            if (capture == 'attributes') box$saved <- attributes(data)
            if (capture == 'copy') { box$copy <- data; attr(box$copy, 'copy') <- TRUE }
            if (capture == 'active_value') {
                env <- new.env(parent = environment())
                makeActiveBinding('rhs', function() { box$saved <- names(data); 7L }, env)
                evalq(dtatools::gen(data, added = rhs), env)
            } else if (capture == 'runtime_name') {
                dtatools::gen(data, !!{ box$saved <- names(data); 'added' }, 7L)
            } else if (capture == 'arbitrary_value') {
                dtatools::gen(data, added = { box$saved <- names(data); 7L })
            } else dtatools::gen(data, added = 7L)
            saved <- if (capture == 'attributes') box$saved$names else if (capture == 'copy') names(box$copy) else box$saved
            stopifnot(identical(saved, before), identical(names(data), c(before, 'added')),
                      identical(as.double(data$added), rep(7, 3)))
            results[[paste(kind, empty, capture, sep = '/')]] <- list(saved = saved, result = public(data),
                copy = if (capture == 'copy') public(box$copy) else NULL)
        }
    }
    for (operation in c('rename', 'drop', 'roundtrip')) {
        data <- make(kind)
        dtatools::gen(data, first = 2L)
        first_names <- names(data)
        if (operation == 'rename') dtatools::rename_vars(data, renamed = x)
        if (operation == 'drop') dtatools::drop_vars(data, x)
        if (operation == 'roundtrip') data <- reserve_columns(unserialize(serialize(data, NULL)), n = 3L)
        second_names <- names(data)
        dtatools::gen(data, second = 3L)
        stopifnot(identical(first_names, c('x', 'first')),
                  identical(names(data), c(second_names, 'second')))
        results[[paste(kind, operation, sep = '/')]] <- list(first = first_names, second = second_names,
                                                           result = public(data))
    }
}
saveRDS(results, args[[2L]])
cat(length(results), 'public names/capacity/callback cases passed\n')
