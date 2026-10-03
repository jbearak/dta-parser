args <- commandArgs(TRUE)
if (!length(args) %in% c(3L, 4L) || (length(args) == 4L && args[[4L]] != 'qualify'))
    stop('usage: worker.R LIBRARY ROUND OUTPUT.csv [qualify]')
qualify_only <- length(args) == 4L
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
round <- as.integer(args[[2L]])
stopifnot(!is.na(round), round > 0L)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    file.path(library_path, 'dtatools')))
if (!requireNamespace('digest', quietly = TRUE)) stop('digest is required')

hash <- function(x) digest::digest(x, algo = 'sha256', serialize = TRUE)
bytes <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = 'little')
value_hash <- function(x) hash(bytes(x))
source_hash <- function(x) {
    # Normalize system-NA payloads only; preserve all extended missing tags.
    value <- readBin(bytes(x), double(), length(x), size = 8L, endian = 'little')
    value[is.na(value) & !is_tagged_missing(value)] <- NA_real_
    value_hash(value)
}
state <- function(x) c(compact = dtatools:::.is_unmaterialized_numeric_altrep(x),
    materialized = .Call(dtatools:::C_dtatools_is_materialized_numeric_altrep, x))
states <- function(x) lapply(x, state)
hashes <- function(x) vapply(x, source_hash, character(1))
storage <- function(x) if (inherits(x, 'dta_numeric')) dta_storage_type(x) else ''
group <- function(columns) dta_group_id(columns, missing = TRUE)
stats_symbol <- get0('C_dtatools_egen_group_stats', asNamespace('dtatools'))
rows <- list()
case <- 0L

for (n in c(100000L, 1000000L)) {
    widths <- if (n == 100000L) c('byte', 'int', 'long', 'float') else c('int', 'float')
    key_counts <- if (n == 100000L) c(1L, 4L) else 1L
    for (width in widths) for (key_count in key_counts) {
        # The same sample serves random and sorted layouts and every build.
        set.seed(67931L + n + key_count)
        cardinality <- if (width == 'byte') 74L else 10001L
        rank_columns <- replicate(key_count, sample.int(cardinality, n, replace = TRUE) - 1L,
                                  simplify = FALSE)
        for (k in seq_len(key_count)) {
            positions <- seq.int(13L + k, n, by = 997L)
            rank_columns[[k]][positions] <- cardinality + (seq_along(positions) - 1L) %% 3L
        }
        names(rank_columns) <- paste0('key', seq_len(key_count))
        sorted_rows <- do.call(order, c(rank_columns, list(method = 'radix')))
        for (layout in c('random', 'sorted')) {
            ranks <- lapply(rank_columns, function(x) if (layout == 'sorted') x[sorted_rows] else x)
            ordinary <- lapply(ranks, function(rank) {
                value <- as.double(rank - cardinality %/% 2L)
                if (width == 'long') value <- value * 100000
                if (width == 'float') value <- value / 8
                value[rank == cardinality] <- NA_real_
                value[rank == cardinality + 1L] <- tagged_missing('a')
                value[rank == cardinality + 2L] <- tagged_missing('z')
                value
            })
            constructor <- get(paste0('dta_', width), asNamespace('dtatools'))
            inputs <- list(compact = lapply(ordinary, constructor),
                           typed_double = lapply(ordinary, dta_double), ordinary = ordinary)
            # Independent integer-rank oracle: radix order and adjacent tuple
            # equality, with no dtatools grouping or numeric decoding involved.
            ordered <- do.call(order, c(ranks, list(method = 'radix')))
            changed <- c(TRUE, rep(FALSE, n - 1L))
            for (rank in ranks) changed[-1L] <- changed[-1L] | diff(rank[ordered]) != 0L
            expected <- numeric(n)
            expected[ordered] <- cumsum(changed)
            expected_first <- ordered[changed]
            expected_hash <- value_hash(expected)
            expected_sources <- hashes(ordinary)
            expected_ranks <- hash(ranks)
            case <- case + 1L
            representation_order <- names(inputs)[(seq_len(3L) + round + case - 2L) %% 3L + 1L]
            if (round %% 2L == 0L) representation_order <- rev(representation_order)
            for (representation in representation_order) {
                columns <- inputs[[representation]]
                before <- states(columns)
                stopifnot(identical(hashes(columns), expected_sources))
                if (representation == 'compact') {
                    stopifnot(all(vapply(before, function(x) isTRUE(x[['compact']]) &&
                        !x[['materialized']], logical(1))))
                    stopifnot(all(vapply(columns, storage, character(1)) == width))
                }
                if (representation == 'typed_double')
                    stopifnot(all(vapply(columns, storage, character(1)) == 'double'))
                # Qualify codes, stable first rows, metadata and the exact
                # prepared-value bound before timing with counters disabled.
                if (!is.null(stats_symbol)) .Call(stats_symbol, TRUE)
                result <- group(columns)
                counts <- if (!is.null(stats_symbol)) .Call(stats_symbol, FALSE) else
                    c(scalar_values = NA_real_, prepared_values = NA_real_, prepared_bytes = NA_real_)
                if (!is.null(stats_symbol)) stopifnot(counts[['scalar_values']] == 0,
                    counts[['prepared_values']] == n * key_count,
                    counts[['prepared_bytes']] == 8 * n * key_count)
                plan <- .Call(dtatools:::C_dtatools_egen_group, columns, TRUE, FALSE)
                stopifnot(identical(value_hash(result), expected_hash),
                    identical(as.double(plan$codes), expected), identical(plan$first, expected_first))
                metadata_hash <- hash(attributes(result))
                result_storage <- storage(result)
                result <- plan <- NULL
                # Separate, untimed R vector-heap high-water diagnostic. This
                # includes result/sort allocations; it is not process RSS.
                gc()
                live <- gc(reset = TRUE)
                memory_result <- group(columns)
                high <- gc()
                peak_vcell_bytes <- max(0, high['Vcells', 'max used'] - live['Vcells', 'used']) * 8
                stopifnot(identical(value_hash(memory_result), expected_hash))
                memory_result <- NULL
                repetitions <- 0L
                timing <- c(user.self = NA_real_, sys.self = NA_real_, elapsed = NA_real_)
                if (qualify_only) result <- group(columns) else {
                    repetitions <- 1L
                    repeat {
                        gc()
                        started <- proc.time()[['elapsed']]
                        for (i in seq_len(repetitions)) result <- group(columns)
                        duration <- proc.time()[['elapsed']] - started
                        if (duration >= .025 || repetitions >= 100000L) break
                        repetitions <- repetitions * 5L
                    }
                    repetitions <- min(1000000L,
                        max(repetitions, as.integer(ceiling(repetitions * .15 / max(duration, .001)))))
                    gc()
                    started <- proc.time()
                    for (i in seq_len(repetitions)) result <- group(columns)
                    timing <- proc.time() - started
                }
                stopifnot(identical(value_hash(result), expected_hash),
                    identical(hash(attributes(result)), metadata_hash),
                    identical(storage(result), result_storage),
                    identical(states(columns), before), identical(hashes(columns), expected_sources),
                    identical(states(columns), before))
                rows[[length(rows) + 1L]] <- data.frame(round, case, n, width, key_count, layout,
                    phase = if (qualify_only) 'qualification' else 'timing',
                    representation, order = match(representation, representation_order),
                    iterations = repetitions,
                    cpu_seconds = unname(timing[['user.self']] + timing[['sys.self']]),
                    elapsed_seconds = unname(timing[['elapsed']]),
                    result_sha256 = expected_hash, metadata_sha256 = metadata_hash, result_storage,
                    source_sha256 = hash(expected_sources), ranks_sha256 = expected_ranks,
                    scalar_values = counts[['scalar_values']], prepared_values = counts[['prepared_values']],
                    prepared_bytes = counts[['prepared_bytes']], key_cache_bytes = 8 * n * key_count,
                    peak_vcell_bytes, source_state_sha256 = hash(before))
            }
        }
    }
}
write.csv(do.call(rbind, rows), args[[3L]], row.names = FALSE)
cat(length(rows), 'qualified grouping observations\n')
