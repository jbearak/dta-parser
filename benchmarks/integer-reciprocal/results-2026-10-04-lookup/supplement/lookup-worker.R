args <- commandArgs(TRUE)
stopifnot(length(args) == 5L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    file.path(normalizePath(args[[1L]]), "dtatools")))
round <- as.integer(args[[2L]])
variant <- args[[4L]]
qualify <- identical(args[[5L]], "qualify")
stopifnot(round %in% 1:2, variant %in% c("baseline", "candidate"))
hash <- function(x) digest::digest(writeBin(as.double(x), raw(), 8L, endian = "little"),
                                  algo = "sha256", serialize = FALSE)
state <- function(x) c(compact = dtatools:::.is_unmaterialized_numeric_altrep(x),
                       materialized = .Call(dtatools:::C_dtatools_is_materialized_numeric_altrep, x))
divide <- function(numerator, source) numerator / source
normalize <- function(values, storage) {
    if (identical(storage, "")) return(values)
    values[!is.finite(values) | abs(values) > (2^53 - 1) * 2^970] <- NA_real_
    if (storage == "float") {
        observed <- !is.na(values)
        values[observed] <- readBin(writeBin(values[observed], raw(), 4L, endian = "little"),
                                    double(), sum(observed), 4L, endian = "little")
    }
    values
}
cases <- data.frame(
    width = c("byte", "byte", "byte", "byte", "int", "int", "int", "int", "int", "int"),
    destination = c("float", "float", "float", "double", "float", "float", "float", "float", "double", "double"),
    cardinality = c("low", "low", "full_observed", "full_observed", "low", "low", "low", "full_observed", "full_observed", "full_observed"),
    n = c(262143L, 262144L, 1000000L, 1000000L, 262143L, 262144L,
          1000000L, 1000000L, 262144L, 1000000L), stringsAsFactors = FALSE)
rows <- list()
for (case in seq_len(nrow(cases))) {
    spec <- cases[case, ]
    grid <- if (spec$cardinality == "low") c(-3, -1, 0, 1, 3) else
        if (spec$width == "byte") seq.int(-127L, 100L) else seq.int(-32767L, 32740L)
    plain <- as.double(rep(grid, length.out = spec$n))
    missing_rows <- seq.int(13L, spec$n, by = 997L)
    plain[missing_rows] <- rep(c(NA_real_, tagged_missing(c("a", "z"))), length.out = length(missing_rows))
    input_sha256 <- hash(plain)
    input_missing <- sum(is.na(plain))
    input_zeros <- sum(plain == 0, na.rm = TRUE)
    observed_codes <- length(unique(plain[!is.na(plain)]))
    sources <- list(compact = if (spec$width == "byte") dta_byte(plain) else dta_int(plain),
                    typed_double = dta_double(plain), ordinary = plain)
    numerators <- list(compact = if (spec$destination == "double") dta_double(1.01) else 1.01,
                       typed_double = if (spec$destination == "double") dta_double(1.01) else 1.01,
                       ordinary = 1.01)
    # Fixture preparation, hashes, constructor costs and checks are outside clocks.
    stopifnot(!.Call(dtatools:::C_dtatools_is_altrep, plain),
              .Call(dtatools:::C_dtatools_numeric_facts_info, sources$compact)[["flags"]] == 4,
              .Call(dtatools:::C_dtatools_numeric_facts_info, sources$compact)[["zero_count"]] == input_zeros)
    reference <- divide(1.01, plain)
    order <- names(sources)[(seq_len(3L) + round + case - 1L) %% 3L + 1L]
    if (round %% 2L == 0L) order <- rev(order)
    for (representation in order) {
        x <- sources[[representation]]
        numerator <- numerators[[representation]]
        before <- state(x)
        numerator_before <- state(numerator)
        attributes_before <- attributes(x)
        facts_before <- .Call(dtatools:::C_dtatools_numeric_facts_info, x)
        storage <- if (representation == "ordinary") "" else
            if (representation == "typed_double") "double" else spec$destination
        expected <- normalize(reference, storage)
        expected_sha256 <- hash(expected)
        expected_missing <- is.na(expected)
        expected_missing_sha256 <- hash(as.double(expected_missing))
        stopifnot(identical(hash(x), input_sha256), identical(state(x), before),
                  identical(hash(numerator), hash(1.01)), identical(state(numerator), numerator_before),
                  identical(before[["compact"]], representation == "compact"), !before[["materialized"]])
        check <- function(result) {
            actual_storage <- if (inherits(result, "dta_numeric")) dta_storage_type(result) else ""
            stopifnot(identical(actual_storage, storage), identical(hash(result), expected_sha256),
                      identical(is.na(result), expected_missing), identical(anyNA(result), any(expected_missing)),
                      identical(hash(x), input_sha256), identical(state(x), before),
                      identical(attributes(x), attributes_before),
                      identical(.Call(dtatools:::C_dtatools_numeric_facts_info, x), facts_before),
                      identical(hash(numerator), hash(1.01)), identical(state(numerator), numerator_before))
            if (storage == "float") stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(result))
        }
        # Settle dependencies, then require the admitted public route explicitly.
        check(divide(numerator, x))
        entries <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
        result <- divide(numerator, x)
        native_calls <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries
        stopifnot(native_calls == if (representation == "ordinary") 0 else 1)
        check(result)
        reps <- 1L
        timing <- c(user.self = NA_real_, sys.self = NA_real_, elapsed = NA_real_)
        if (!qualify) {
            repeat {
                gc()
                start <- proc.time()
                for (i in seq_len(reps)) result <- divide(numerator, x)
                calibration <- proc.time() - start
                duration <- unname(calibration[["user.self"]] + calibration[["sys.self"]])
                if (duration >= .02 || reps >= 100000L) break
                reps <- reps * 5L
            }
            reps <- min(1000000L, max(reps, as.integer(ceiling(reps * .1 / max(duration, .001)))))
            gc()
            entries <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
            start <- proc.time()
            # The public call allocates/builds its LUT anew every iteration.
            for (i in seq_len(reps)) result <- divide(numerator, x)
            timing <- proc.time() - start
            native_calls <- .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries
            stopifnot(native_calls == if (representation == "ordinary") 0 else reps)
            check(result)
        }
        mutation_checked <- representation != "ordinary"
        cleared_sha256 <- ""
        if (mutation_checked) {
            alias <- .Call(dtatools:::C_dtatools_metadata_copy, result)
            mutable <- dibble(x = result)
            cleared <- expected
            cleared[expected_missing] <- 0
            if (any(expected_missing)) replace_values(mutable, x = 0, where = which(expected_missing))
            cleared_sha256 <- hash(mutable$x)
            stopifnot(identical(cleared_sha256, hash(cleared)), !anyNA(mutable$x),
                      identical(hash(alias), expected_sha256))
            check(result)
        }
        rows[[length(rows) + 1L]] <- data.frame(round, case, width = spec$width,
            destination = spec$destination, cardinality = spec$cardinality, n = spec$n,
            representation, order = match(representation, order), iterations = reps,
            cpu = unname(timing[["user.self"]] + timing[["sys.self"]]), wall = unname(timing[["elapsed"]]),
            input_sha256, input_missing, input_zeros, observed_codes,
            result_sha256 = expected_sha256, missing_sha256 = expected_missing_sha256,
            result_missing = sum(expected_missing), result_storage = storage,
            mutation_checked, cleared_sha256, native_calls,
            compact_before = before[["compact"]], compact_after = state(x)[["compact"]],
            materialized_before = before[["materialized"]], materialized_after = state(x)[["materialized"]],
            numerator_compact_before = numerator_before[["compact"]],
            numerator_compact_after = state(numerator)[["compact"]],
            numerator_materialized_before = numerator_before[["materialized"]],
            numerator_materialized_after = state(numerator)[["materialized"]])
    }
}
write.csv(do.call(rbind, rows), args[[3L]], row.names = FALSE)
cat(length(rows), if (qualify) "qualified cases\n" else "qualified observations\n")
