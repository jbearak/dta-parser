args <- commandArgs(TRUE)
stopifnot(length(args) %in% c(7L, 8L))
qualification_only <- length(args) == 8L && args[[8L]] == 'qualify'
stopifnot(length(args) == 7L || qualification_only)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    file.path(normalizePath(args[[1L]]), 'dtatools')))
root <- normalizePath(args[[2L]])
condition <- args[[3L]]
storage <- args[[4L]]
repetitions <- as.integer(args[[5L]])
output <- args[[6L]]
variant <- args[[7L]]
stopifnot(condition %in% c('none', '63', '65'), storage %in% c('double', 'float'),
          repetitions > 0L, variant %in% c('baseline', 'candidate'))
info <- function(x = NULL) .Call(dtatools:::C_dtatools_owned_numeric_info, x)
attempts <- function() {
    value <- info()
    if ('gc_attempts' %in% names(value)) value[['gc_attempts']] else NA_real_
}
values <- readRDS(file.path(root, 'tiny-reference.rds'))
bytes <- function(x) writeBin(as.double(x), raw(), 8L, endian = 'little')
expected_bytes <- bytes(values)
tiny_path <- file.path(root, paste0('tiny-', storage, '.arrow'))
qualify <- function(x) {
    stopifnot(identical(names(x), 'x'), inherits(x, 'dibble'),
              nrow(x) == length(values), identical(dta_storage_type(x$x), storage),
              identical(bytes(x$x), expected_bytes))
    if (storage == 'float') stopifnot(info(x$x)[['owned']] == 1)
}
held <- if (condition == 'none') NULL else read_arrow(
    file.path(root, paste0('retained-', condition, '.arrow')), threads = 1L)
gc(); gc()
native_before <- info()[['native_bytes']]
expected_native <- if (condition == 'none') 0 else as.double(condition) * 1024^2
stopifnot(native_before == expected_native)
qualify_held <- function() {
    if (!is.null(held)) {
        stopifnot(info(held$x)[['owned']] == 1, all(held$x == 7), !anyNA(held$x),
                  as.double(sum(held$x)) == nrow(held) * 7)
    }
}
qualify_held()
held_signature <- if (is.null(held)) '' else datasig(held, threads = 1L)
warm <- read_arrow(tiny_path, threads = 1L)
qualify(warm)
signature <- datasig(warm, threads = 1L)
rm(warm)
gc(); gc()
stopifnot(info()[['native_bytes']] == native_before)
if (qualification_only) {
    actual <- read_arrow(tiny_path, threads = 1L)
    qualify(actual)
    qualify_held()
    stopifnot(identical(datasig(actual, threads = 1L), signature))
    cat('PASS:', condition, storage, 'values, storage and retained ownership\n')
    quit(status = 0L)
}
gc.time(TRUE)
before_attempts <- attempts()
before_gc <- gc.time()
start <- proc.time()
for (i in seq_len(repetitions)) actual <- read_arrow(tiny_path, threads = 1L)
timing <- proc.time() - start
gc_timing <- gc.time() - before_gc
attempt_delta <- attempts() - before_attempts
native_after <- info()[['native_bytes']]
qualify(actual)
qualify_held()
stopifnot(identical(datasig(actual, threads = 1L), signature),
          identical(if (is.null(held)) '' else datasig(held, threads = 1L), held_signature))
if (storage == 'double') {
    stopifnot(native_after == native_before)
} else {
    stopifnot(native_after >= native_before,
              native_after <= native_before + repetitions * length(values) * 4)
}
if (variant == 'candidate') stopifnot(identical(attempt_delta, 0))
write.csv(data.frame(condition, storage, repetitions, cpu = sum(timing[1:2]),
                     wall = timing[['elapsed']], gc_cpu = sum(gc_timing[1:2]),
                     gc_attempts = attempt_delta, native_before, native_after,
                     signature, held_signature, R_version = R.version.string),
          output, row.names = FALSE)
