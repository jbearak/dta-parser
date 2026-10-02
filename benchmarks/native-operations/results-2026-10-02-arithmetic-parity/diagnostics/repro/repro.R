# Diagnostic parity gate, deliberately not a CI test.
# Usage: Rscript --vanilla repro.R [LIBRARY [OUTPUT_DIRECTORY]]
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2L) stop('usage: repro.R [LIBRARY [OUTPUT_DIRECTORY]]')
library_path <- if (length(args)) args[[1L]] else
    '<previous-work>/final-candidate-v2/library'
library_path <- normalizePath(library_path, mustWork = TRUE)
output <- if (length(args) >= 2L) args[[2L]] else file.path(
    '<work>',
    paste0('run-', format(Sys.time(), '%Y%m%dT%H%M%S', tz = 'UTC'), '-', Sys.getpid()))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    file.path(library_path, 'dtatools')))
stopifnot(requireNamespace('digest', quietly = TRUE))

fixture <- '<reader-work>/fixtures/compact.arrow'
expected_input_sha256 <- 'abc996276c43213a415c58f29e20b709ac8ad9ca2eb3e791be59513a9173f999'
measured_dll_sha256 <- 'fa55d6edc07f8df43fb59f6c8d1460e3e553fc383584f3f165f778619b11c56d'
ns <- asNamespace('dtatools')
native <- function(symbol, ...) .Call(get(symbol, ns), ...)
bytes <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = 'little')
input_hash <- function(x) digest::digest(bytes(x), algo = 'sha256', serialize = FALSE)
state <- function(x) c(
    compact = dtatools:::.is_unmaterialized_numeric_altrep(x),
    materialized = native('C_dtatools_is_materialized_numeric_altrep', x))
counter <- function() native('C_dtatools_numeric_entry_stats', FALSE)[['scalar']]
operation <- function(x) x * 2

# The fixture and value digest come from the accepted 2,976-observation run.
# Reads, copies, qualification, hashing and explicit GC are outside timing.
x <- read_arrow(fixture, col_select = tidyselect::all_of('compact_09'),
                threads = 1L, output = 'tibble')$compact_09
stopifnot(length(x) == 1000000L, identical(dta_storage_type(x), 'int'),
          identical(input_hash(x), expected_input_sha256),
          isTRUE(state(x)[['compact']]), !state(x)[['materialized']])
plain <- numeric(length(x))
plain[] <- as.double(x)
double <- dta_double(plain)
stopifnot(identical(input_hash(double), expected_input_sha256),
          identical(dta_storage_type(double), 'double'),
          !any(is.nan(plain)), !any(is.infinite(plain)),
          !any(is_tagged_missing(plain)), match(TRUE, is.na(plain)) == 988L)
expected <- bytes(dtatools:::.collapse_missing(plain * 2))
qualify <- function(result, storage) {
    stopifnot(identical(dta_storage_type(result), storage),
              inherits(result, 'dta_numeric'), is.null(names(result)),
              identical(bytes(result), expected))
}
qualify(operation(x), 'long')
qualify(operation(double), 'double')
stopifnot(isTRUE(state(x)[['compact']]), !state(x)[['materialized']])
dll <- system.file('libs', paste0('dtatools', .Platform$dynlib.ext), package = 'dtatools')
dll_sha256 <- digest::digest(file = dll, algo = 'sha256', serialize = FALSE)
if (!length(args)) stopifnot(identical(dll_sha256, measured_dll_sha256))

repetitions <- 384L
rounds <- 3L
measure <- function(value, representation, round, order) {
    before <- state(value)
    if (representation == 'compact') {
        stopifnot(isTRUE(before[['compact']]), !before[['materialized']])
    }
    gc()
    entries <- counter()
    start <- proc.time()
    for (iteration in seq_len(repetitions)) result <- operation(value)
    elapsed <- proc.time() - start
    native_calls <- counter() - entries
    stopifnot(identical(state(value), before), native_calls == repetitions)
    storage <- if (representation == 'compact') 'long' else 'double'
    qualify(result, storage)
    cpu <- unname(elapsed[['user.self']] + elapsed[['sys.self']])
    wall <- unname(elapsed[['elapsed']])
    # The shorter control interval must span many timer ticks.
    stopifnot(cpu >= .025, wall >= .025)
    data.frame(round = round, representation = representation, order = order,
               iterations = repetitions, cpu_seconds = cpu, wall_seconds = wall,
               cpu_per_call = cpu / repetitions, wall_per_call = wall / repetitions,
               native_calls = native_calls, result_storage = storage,
               result_sha256 = digest::digest(expected, algo = 'sha256', serialize = FALSE),
               compact_before = before[['compact']], compact_after = state(value)[['compact']],
               materialized_before = before[['materialized']],
               materialized_after = state(value)[['materialized']])
}
observations <- list()
for (round in seq_len(rounds)) {
    order <- if (round %% 2L) c('compact', 'typed_double') else c('typed_double', 'compact')
    for (position in seq_along(order)) {
        representation <- order[[position]]
        value <- if (representation == 'compact') x else double
        observations[[length(observations) + 1L]] <- measure(value, representation, round, position)
    }
}
observations <- do.call(rbind, observations)
stopifnot(identical(input_hash(x), expected_input_sha256),
          identical(input_hash(double), expected_input_sha256),
          isTRUE(state(x)[['compact']]), !state(x)[['materialized']])
compact_cpu <- median(observations$cpu_per_call[observations$representation == 'compact'])
double_cpu <- median(observations$cpu_per_call[observations$representation == 'typed_double'])
ratio <- compact_cpu / double_cpu
limit <- 1.10
write.csv(observations, file.path(output, 'observations.csv'), row.names = FALSE)
result <- list(case = 'arrow-int-multiply', expression = 'x * 2', rows = length(x),
               rounds = rounds, repetitions = repetitions, library = library_path,
               dll_sha256 = dll_sha256, measured_dll_sha256 = measured_dll_sha256,
               input_sha256 = expected_input_sha256,
               result_storage = c(compact = 'long', typed_double = 'double'),
               compact_cpu_ms = compact_cpu * 1000, typed_double_cpu_ms = double_cpu * 1000,
               compact_over_typed_double = ratio, diagnostic_limit = limit,
               values_equal = TRUE, native_route_verified = TRUE,
               compact_unmaterialized = TRUE, passed = ratio <= limit)
dput(result, file = file.path(output, 'result.dput'))
cat(sprintf('arrow-int-multiply: compact %.3f ms; typed_double %.3f ms; ratio %.2fx; limit %.2fx\n',
            compact_cpu * 1000, double_cpu * 1000, ratio, limit))
cat('Exact result values/storage, native route, and unmaterialized compact input verified.\n')
cat('Observations:', normalizePath(output), '\n')
if (ratio > limit) {
    stop(sprintf('PARITY FAIL: compact/typed_double %.2f exceeds %.2f', ratio, limit), call. = FALSE)
}
cat('PARITY PASS\n')
