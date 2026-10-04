args <- commandArgs(TRUE)
stopifnot(length(args) == 6L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    file.path(normalizePath(args[[1L]]), 'dtatools')))
round <- as.integer(args[[2L]])
variant <- args[[4L]]
qualify_only <- identical(args[[5L]], 'qualify')
target_cpu <- as.double(args[[6L]])
stopifnot(round %in% 1:6, variant %in% c('baseline', 'candidate'),
          args[[5L]] %in% c('qualify', 'measure'), target_cpu %in% c(0.15, 0.3))
options(dtatools.threads = 1L)
stopifnot(identical(.Call(dtatools:::C_dtatools_test_numeric_size_minimum, NULL), 2048L))

hash_raw <- function(x) digest::digest(x, algo='sha256', serialize=FALSE)
value_hash <- function(x) hash_raw(writeBin(as.double(x), raw(), 8L, endian='little'))
rank_hash <- function(x) hash_raw(writeBin(as.integer(x), raw(), 4L, endian='little'))
metadata_hash <- function(x) digest::digest(attributes(x), algo='sha256')
state <- function(x) c(compact=dtatools:::.is_unmaterialized_numeric_altrep(x),
                      materialized=.Call(dtatools:::C_dtatools_is_materialized_numeric_altrep, x))
entry <- function() .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[['scalar']]
construct <- function(values, width) switch(width, int=dta_int(values), float=dta_float(values))

# Same public constructors and reverse division as the published workers.
# The small returned list lets the final iteration's source and result be
# qualified outside clocks. Its identical R bookkeeping is included for both builds.
workflow <- function(plain, width, operations) {
    source <- construct(plain, width)
    result <- source
    if (operations > 0L) for (j in seq_len(operations)) result <- 1.01 / source
    list(source=source, result=result)
}

n <- 1000000L
integer_plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L)
integer_positions <- seq.int(13L, n, by=997L)
integer_ranks <- integer(n)
integer_ranks[integer_positions] <- 1L
integer_plain[integer_positions] <- NA_real_
float_plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L) / 8
RNGkind('Mersenne-Twister', 'Inversion', 'Rejection')
set.seed(29071L)
float_positions <- sample.int(n, n %/% 2L)
float_ranks <- integer(n)
float_ranks[float_positions] <- rep(1:27, length.out=length(float_positions))
for (code in 1:27) float_plain[float_ranks == code] <-
    if (code == 1L) NA_real_ else tagged_missing(letters[code - 1L])
fixtures <- list(
    dense_float=list(plain=float_plain, ranks=float_ranks, width='float', pattern='random_half'),
    sparse_int=list(plain=integer_plain, ranks=integer_ranks, width='int', pattern='sparse'))
stopifnot(identical(value_hash(float_plain), 'b6b60ef8bb430be90e7239dd64b807cda383733b1048ca6748094e19e1003f06'),
          identical(rank_hash(float_ranks), '6d001f63d9ce5612a17ed6ff62e0d269d6d862dde318265b90a63af3b92b0706'),
          length(integer_positions) == 1003L)

phases <- expand.grid(operations=c(0L, 1L, 5L), fixture=names(fixtures),
                      KEEP.OUT.ATTRS=FALSE, stringsAsFactors=FALSE)
phase_order <- (seq_len(nrow(phases)) + round - 2L) %% nrow(phases) + 1L
rows <- list()
for (position in seq_along(phase_order)) {
    phase <- phases[phase_order[[position]], ]
    fixture <- fixtures[[phase$fixture]]
    plain <- fixture$plain
    operations <- phase$operations
    input_hash <- value_hash(plain)
    ranks_hash <- rank_hash(fixture$ranks)
    input_missing <- sum(fixture$ranks > 0L)
    zero_observed <- sum(!is.na(plain) & plain == 0)
    expected <- plain
    expected_storage <- fixture$width
    if (operations > 0L) {
        # Independent binary64 division, then the established package missing
        # policy and binary32 encoding. Each operation uses the same source.
        expected <- 1.01 / plain
        expected[fixture$ranks > 0L | !is.finite(expected) |
                 abs(expected) > (2^53 - 1) * 2^970] <- NA_real_
        observed <- !is.na(expected)
        stopifnot(all(abs(expected[observed]) <= (2^24 - 1) * 2^103))
        expected[observed] <- readBin(writeBin(expected[observed], raw(), 4L, endian='little'),
                                     double(), sum(observed), 4L, endian='little')
        expected_storage <- 'float'
        stopifnot(sum(is.na(expected)) == input_missing + zero_observed)
    }
    expected_hash <- value_hash(expected)
    mask <- is.na(expected)
    expected_missing_hash <- rank_hash(mask)
    source_reference <- construct(plain, fixture$width)
    source_state <- state(source_reference)
    source_meta <- metadata_hash(source_reference)
    stopifnot(source_state[['compact']], !source_state[['materialized']],
              identical(value_hash(source_reference), input_hash))
    check <- function(record) {
        source <- record$source
        result <- record$result
        stopifnot(length(source) == n, length(result) == n,
                  identical(dta_storage_type(source), fixture$width),
                  identical(dta_storage_type(result), expected_storage),
                  identical(value_hash(source), input_hash),
                  identical(value_hash(result), expected_hash),
                  identical(is.na(result), mask), identical(anyNA(result), any(mask)),
                  identical(state(source), source_state),
                  identical(metadata_hash(source), source_meta),
                  dtatools:::.is_unmaterialized_numeric_altrep(result),
                  identical(state(source), source_state))
    }
    check(workflow(plain, fixture$width, operations))
    started <- entry()
    record <- workflow(plain, fixture$width, operations)
    qualification_calls <- entry() - started
    stopifnot(qualification_calls == operations)
    check(record)
    result_meta <- metadata_hash(record$result)

    repetitions <- 1L
    cpu <- wall <- 0
    native_calls <- qualification_calls
    if (!qualify_only) {
        repeat {
            gc()
            start <- proc.time()
            for (i in seq_len(repetitions)) record <- workflow(plain, fixture$width, operations)
            delta <- proc.time() - start
            duration <- unname(delta[['user.self']] + delta[['sys.self']])
            if (duration >= 0.03 || repetitions >= 100000L) break
            repetitions <- repetitions * 2L
        }
        repetitions <- min(1000000L, max(repetitions,
            as.integer(ceiling(repetitions * target_cpu / max(duration, 0.001)))))
        # A pre-clock collection gives comparable starts. Automatic collections
        # caused by every constructor and result allocation remain inside clocks.
        gc()
        started <- entry()
        start <- proc.time()
        for (i in seq_len(repetitions)) record <- workflow(plain, fixture$width, operations)
        delta <- proc.time() - start
        native_calls <- entry() - started
        cpu <- unname(delta[['user.self']] + delta[['sys.self']])
        wall <- unname(delta[['elapsed']])
        stopifnot(native_calls == repetitions * operations)
        check(record)
        stopifnot(identical(metadata_hash(record$result), result_meta))
    }
    # Clearing all oracle-missing rows checks both cached undercounts and
    # overcounts, and retained source/result aliases, outside every clock.
    original <- record$result
    result_state <- state(original)
    cleared <- expected
    cleared[mask] <- 0
    cleared_hash <- value_hash(cleared)
    mutable <- dibble(x=original)
    replace_values(mutable, x=0, where=which(mask))
    stopifnot(identical(value_hash(mutable$x), cleared_hash),
              !anyNA(mutable$x), !any(is.na(mutable$x)),
              identical(state(original), result_state),
              identical(value_hash(original), expected_hash),
              identical(metadata_hash(original), result_meta))
    check(record)
    rows[[length(rows) + 1L]] <- data.frame(
        round, variant, mode=if (qualify_only) 'qualify' else 'measure', position,
        fixture=phase$fixture, pattern=fixture$pattern, width=fixture$width,
        rows=n, operations, repetitions, cpu, wall, native_calls, qualification_calls,
        input_hash, rank_hash=ranks_hash, input_missing, zero_observed,
        result_hash=expected_hash, missing_hash=expected_missing_hash,
        result_missing=sum(mask), result_storage=expected_storage,
        source_metadata_hash=source_meta, result_metadata_hash=result_meta,
        cleared_hash, mutation_checked=TRUE,
        compact_before=as.logical(source_state[['compact']]),
        compact_after=as.logical(state(record$source)[['compact']]),
        materialized_before=as.logical(source_state[['materialized']]),
        materialized_after=as.logical(state(record$source)[['materialized']]),
        automatic_gc_included=TRUE)
}
write.csv(do.call(rbind, rows), args[[3L]], row.names=FALSE)
cat(length(rows), if (qualify_only) 'qualified constructor/workflow cases\n' else 'qualified constructor/workflow observations\n')
