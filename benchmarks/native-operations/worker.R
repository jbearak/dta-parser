args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L)
    stop('usage: worker.R LIBRARY FIXTURES ROUND OUTPUT.csv')
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
fixtures <- normalizePath(args[[2L]], mustWork = TRUE)
round <- as.integer(args[[3L]])
if (is.na(round) || round < 1L) stop('ROUND must be a positive integer')
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    file.path(library_path, 'dtatools')))
if (!requireNamespace('digest', quietly = TRUE)) stop('digest is required')

# Setup, fixture qualification, reference calculations and explicit GC are
# excluded. Each timed loop includes public dispatch, result allocation and
# automatic GC. No result is retained across loop iterations except the last.
full_reference <- readRDS(file.path(fixtures, 'compact.rds'))
positions <- c(byte = 1L, int = 9L, long = 17L, float = 25L)
columns <- names(full_reference)[positions]
ordinary <- lapply(full_reference[columns], function(x) {
    result <- numeric(length(x))
    result[] <- as.double(x)
    result
})
rm(full_reference)
dta <- read_dta(file.path(fixtures, 'compact.dta'),
                col_select = tidyselect::all_of(columns), threads = 1L,
                output = 'tibble')
arrow <- read_arrow(file.path(fixtures, 'compact.arrow'),
                    col_select = tidyselect::all_of(columns), threads = 1L,
                    output = 'tibble')

storage <- function(x) {
    if (inherits(x, 'dta_numeric')) dta_storage_type(x) else NA_character_
}
source_state <- function(x) {
    c(compact = dtatools:::.is_unmaterialized_numeric_altrep(x),
      materialized = .Call(dtatools:::C_dtatools_is_materialized_numeric_altrep, x))
}
canonical <- function(x) {
    if (inherits(x, 'dta_summarize')) {
        return(list(statistics = x$statistics, r = x$r,
                    smallest = x$smallest, largest = x$largest))
    }
    if (typeof(x) == 'double') {
        return(list(type = 'double', storage = storage(x), names = names(x),
                    bytes = writeBin(as.double(x), raw(), size = 8L, endian = 'little')))
    }
    list(type = typeof(x), storage = storage(x), names = names(x), values = x)
}
fingerprint <- function(x) digest::digest(canonical(x), algo = 'sha256', serialize = TRUE)
values_hash <- function(x) digest::digest(
    writeBin(as.double(x), raw(), size = 8L, endian = 'little'),
    algo = 'sha256', serialize = FALSE)
restore <- function(value, source) {
    if (!inherits(source, 'dta_numeric')) return(value)
    dtatools:::.dta_computed(dtatools:::.collapse_missing(value), storage(source))
}
operations <- list(
    is_tagged_missing = function(x) is_tagged_missing(x),
    missing_tag = function(x) missing_tag(x),
    anyNA = function(x) anyNA(x),
    dta_total = function(x) dta_total(x),
    dta_row_total = function(x) dta_row_total(x, x, x),
    mean = function(x) mean(x, na.rm = TRUE),
    range = function(x) range(x, na.rm = TRUE),
    summ = function(x) summ(x),
    dta_match = function(x) dta_match(x, x),
    dta_in = function(x) dta_in(x, x),
    multiply = function(x) x * 2,
    divide = function(x) x / 2,
    add = function(x) x + x
)
iterations <- c(is_tagged_missing = 10L, missing_tag = 10L, anyNA = 10000L,
                dta_total = 10L, dta_row_total = 5L, mean = 10L, range = 10L,
                summ = 3L, dta_match = 2L, dta_in = 2L,
                multiply = 5L, divide = 5L, add = 5L)
base_reference <- function(operation, x, source) {
    switch(operation,
        # These fixed fixtures contain periodic system NA only. Validate that
        # condition below before relying on these independent tag oracles.
        is_tagged_missing = rep(FALSE, length(x)),
        missing_tag = rep(NA_character_, length(x)),
        anyNA = anyNA(x),
        dta_total = sum(x, na.rm = TRUE),
        dta_row_total = {
            observed <- x
            observed[is.na(observed)] <- 0
            observed + observed + observed
        },
        mean = restore(mean(x, na.rm = TRUE), source),
        range = restore(range(x, na.rm = TRUE), source),
        summ = summ(x),
        dta_match = match(x, x),
        dta_in = rep(TRUE, length(x)),
        multiply = restore(x * 2, source),
        divide = restore(x / 2, source),
        add = restore(x + x, source))
}

# Calibrate outside the retained interval, then use fixed repetitions for
# that observation. At least 20 ms of calibration supports a 150 ms target
# without trying to estimate a sub-tick operation from a rounded zero.
calibrate <- function(call, x, initial) {
    repeat {
        gc()
        start <- proc.time()[['elapsed']]
        for (i in seq_len(initial)) result <- call(x)
        duration <- proc.time()[['elapsed']] - start
        if (duration >= .02 || initial >= 1000000L) break
        initial <- min(1000000L, initial * 10L)
    }
    if (duration >= .15) return(initial)
    min(1000000L, max(initial, as.integer(ceiling(initial * .15 / max(duration, .001)))))
}
rows <- list()
case <- 0L
for (index in seq_along(columns)) {
    name <- columns[[index]]
    width <- names(positions)[[index]]
    plain <- ordinary[[name]]
    stopifnot(length(plain) == 1000000L, !any(is.nan(plain)),
              !any(is.infinite(plain)), !any(is_tagged_missing(plain)))
    expected_input <- values_hash(plain)
    first_missing <- match(TRUE, is.na(plain), nomatch = NA_integer_)
    for (format in c('dta', 'arrow')) {
        compact <- if (format == 'dta') dta[[name]] else arrow[[name]]
        stopifnot(identical(storage(compact), width),
                  identical(values_hash(compact), expected_input),
                  isTRUE(source_state(compact)[['compact']]))
        for (operation in names(operations)) {
            case <- case + 1L
            order <- if ((round + case) %% 2L) c('compact', 'ordinary')
                     else c('ordinary', 'compact')
            call <- operations[[operation]]
            for (representation in order) {
                x <- if (representation == 'compact') compact else plain
                expected <- base_reference(operation, plain, x)
                expected_hash <- fingerprint(expected)
                # Qualification warms method dispatch before the measurement.
                actual <- call(x)
                actual_hash <- fingerprint(actual)
                if (!identical(actual_hash, expected_hash))
                    stop('reference mismatch: ', format, '/', width, '/', operation,
                         '/', representation)
                rm(expected, actual)
                before <- source_state(x)
                if (representation == 'compact') stopifnot(isTRUE(before[['compact']]), !before[['materialized']])
                reps <- calibrate(call, x, iterations[[operation]])
                gc()
                entries <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)
                start <- proc.time()
                for (iteration in seq_len(reps)) result <- call(x)
                elapsed <- proc.time() - start
                native_calls <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[['scalar']] - entries[['scalar']]
                after <- source_state(x)
                result_hash <- fingerprint(result)
                stopifnot(identical(result_hash, expected_hash), identical(before, after))
                rows[[length(rows) + 1L]] <- data.frame(
                    round = round, case = case, format = format, width = width,
                    column = name, operation = operation, representation = representation,
                    order_in_pair = match(representation, order), rows = length(x),
                    iterations = reps,
                    elapsed_seconds = unname(elapsed[['elapsed']]),
                    cpu_seconds = unname(elapsed[['user.self']] + elapsed[['sys.self']]),
                    seconds_per_call = unname(elapsed[['elapsed']]) / reps,
                    result_sha256 = result_hash,
                    full_result_sha256 = if (inherits(result, 'dta_summarize')) digest::digest(result, algo='sha256') else result_hash,
                    result_storage = storage(result),
                    input_sha256 = expected_input, first_missing = first_missing,
                    native_scalar_calls = native_calls,
                    compact_before = before[['compact']], compact_after = after[['compact']],
                    materialized_before = before[['materialized']],
                    materialized_after = after[['materialized']],
                    package_version = as.character(packageVersion('dtatools')),
                    stringsAsFactors = FALSE)
                rm(result)
            }
        }
        stopifnot(identical(values_hash(compact), expected_input),
                  identical(values_hash(plain), expected_input))
    }
}
# A separate deterministic late-missing control exposes the cached-count
# benefit; the file fixture above has an early missing value. These sources
# are constructed here, and the retained variant uses the package chunk owner.
late <- rep(1, 1000000L)
late[length(late)] <- NA_real_
constructors <- list(byte=dta_byte, int=dta_int, long=dta_long, float=dta_float)
for (width in names(constructors)) for (format in c('constructed', 'retained')) {
    compact <- constructors[[width]](late)
    if (format == 'retained') compact <- .Call(dtatools:::C_dtatools_owned_numeric_freeze, compact, 8192L)
    expected_input <- values_hash(late)
    stopifnot(identical(values_hash(compact), expected_input))
    case <- case + 1L
    order <- if ((round + case) %% 2L) c('compact','ordinary') else c('ordinary','compact')
    for (representation in order) {
        x <- if (representation == 'compact') compact else late
        stopifnot(identical(anyNA(x), TRUE))
        before <- source_state(x)
        if (representation == 'compact') stopifnot(isTRUE(before[['compact']]), !before[['materialized']])
        reps <- calibrate(anyNA, x, 100L)
        gc()
        start <- proc.time()
        for (iteration in seq_len(reps)) result <- anyNA(x)
        elapsed <- proc.time()-start
        after <- source_state(x)
        stopifnot(identical(result,TRUE), identical(before,after))
        rows[[length(rows)+1L]] <- data.frame(
            round=round, case=case, format=format, width=width, column='synthetic_late_na',
            operation='anyNA_late', representation=representation,
            order_in_pair=match(representation,order), rows=length(x), iterations=reps,
            elapsed_seconds=unname(elapsed[['elapsed']]),
            cpu_seconds=unname(elapsed[['user.self']]+elapsed[['sys.self']]),
            seconds_per_call=unname(elapsed[['elapsed']])/reps,
            result_sha256=fingerprint(result), full_result_sha256=fingerprint(result), result_storage=storage(result),
            input_sha256=expected_input, first_missing=length(late), native_scalar_calls=0,
            compact_before=before[['compact']], compact_after=after[['compact']],
            materialized_before=before[['materialized']], materialized_after=after[['materialized']],
            package_version=as.character(packageVersion('dtatools')), stringsAsFactors=FALSE)
    }
    stopifnot(identical(values_hash(compact), expected_input),
              identical(values_hash(late), expected_input))
}
result <- do.call(rbind, rows)
dir.create(dirname(args[[4L]]), recursive = TRUE, showWarnings = FALSE)
write.csv(result, args[[4L]], row.names = FALSE, na = '')
cat(nrow(result), 'qualified timing rows written to', args[[4L]], '\n')
