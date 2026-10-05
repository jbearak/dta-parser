args <- commandArgs(TRUE)
stopifnot(length(args) == 7L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    file.path(normalizePath(args[[1L]]), "dtatools")))
round <- as.integer(args[[2L]])
variant <- args[[4L]]
qualify_only <- identical(args[[5L]], "qualify")
fixtures_dir <- normalizePath(args[[6L]])
target_cpu <- as.double(args[[7L]])
stopifnot(round %in% 1:6, variant %in% c("baseline", "candidate"),
          args[[5L]] %in% c("qualify", "measure"), target_cpu %in% c(0.15, 0.3))
options(dtatools.threads = 1L)
stopifnot(identical(.Call(dtatools:::C_dtatools_test_numeric_size_minimum, NULL), 2048L))
hash_raw <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
value_hash <- function(x) hash_raw(writeBin(as.double(x), raw(), 8L, endian = "little"))
rank_hash <- function(x) hash_raw(writeBin(as.integer(x), raw(), 4L, endian = "little"))
metadata_hash <- function(x) digest::digest(attributes(x), algo = "sha256")
entry <- function() .Call(dtatools:::C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
facts <- function(x) .Call(dtatools:::C_dtatools_numeric_facts_info, x)
state <- function(x) {
    info <- .Call(dtatools:::C_dtatools_owned_numeric_info, x)
    c(compact = dtatools:::.is_unmaterialized_numeric_altrep(x),
      materialized = .Call(dtatools:::C_dtatools_is_materialized_numeric_altrep, x),
      retained = info[["owned"]],
      chunks = info[["chunks"]])
}
expected_facts <- function(plain, width, format) {
    if (variant == "baseline" || format != "arrow" || width != "float") return(c(flags = 0, max_magnitude_bound = 0,
        min_nonzero_magnitude_bound = 0, zero_count = 0))
    observed <- plain[!is.na(plain)]
    zeros <- as.double(sum(observed == 0))
    bits <- readBin(writeBin(abs(observed), raw(), 4L, endian = "little"),
                    "integer", length(observed), 4L, endian = "little")
    c(flags = 7, max_magnitude_bound = as.double(max(bits)),
      min_nonzero_magnitude_bound = as.double(min(bits[bits != 0L])), zero_count = zeros)
}
workflow <- function(path, format, operations) {
    table <- if (format == "dta") read_dta(path, threads = 1L, use_numeric_altrep = TRUE)
             else read_arrow(path, threads = 1L, use_numeric_altrep = TRUE)
    source <- table$x
    result <- source
    if (operations > 0L) for (j in seq_len(operations)) result <- 1.01 / source
    list(source = source, result = result)
}
n <- 1000000L
integer_plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L)
integer_positions <- seq.int(13L, n, by = 997L)
integer_ranks <- integer(n)
integer_ranks[integer_positions] <- 1L
integer_plain[integer_positions] <- NA_real_
float_plain <- as.double((seq_len(n) * 13) %% 10001L - 5000L) / 8
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
set.seed(29071L)
float_positions <- sample.int(n, n %/% 2L)
float_ranks <- integer(n)
float_ranks[float_positions] <- rep(1:27, length.out = length(float_positions))
for (code in 1:27) float_plain[float_ranks == code] <-
    if (code == 1L) NA_real_ else tagged_missing(letters[code - 1L])
fixtures <- list(dense_float = list(plain = float_plain, ranks = float_ranks, width = "float"),
                 sparse_int = list(plain = integer_plain, ranks = integer_ranks, width = "int"))
stopifnot(value_hash(float_plain) == "b6b60ef8bb430be90e7239dd64b807cda383733b1048ca6748094e19e1003f06",
          rank_hash(float_ranks) == "6d001f63d9ce5612a17ed6ff62e0d269d6d862dde318265b90a63af3b92b0706",
          length(integer_positions) == 1003L)
manifest <- read.csv(file.path(fixtures_dir, "fixtures.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(manifest) == 4L, !anyDuplicated(manifest[c("fixture", "format")]))
phases <- expand.grid(operations = c(0L, 1L, 5L), fixture = names(fixtures),
                      format = c("dta", "arrow"), KEEP.OUT.ATTRS = FALSE,
                      stringsAsFactors = FALSE)
# Rotate by four within each two-round pair and reverse the even round.
# Each phase occupies six distinct positions with mean 6.5, three in each
# half. Baseline and candidate use exactly the same phase order.
offset <- 4L * ((round - 1L) %/% 2L)
phase_order <- (seq_len(nrow(phases)) + offset - 1L) %% nrow(phases) + 1L
if (round %% 2L == 0L) phase_order <- rev(phase_order)
rows <- list()
for (position in seq_along(phase_order)) {
    phase <- phases[phase_order[[position]], ]
    fixture <- fixtures[[phase$fixture]]
    plain <- fixture$plain
    operations <- phase$operations
    record_manifest <- manifest[manifest$fixture == phase$fixture & manifest$format == phase$format, ]
    stopifnot(nrow(record_manifest) == 1L, record_manifest$rows == n,
              record_manifest$width == fixture$width,
              record_manifest$input_hash == value_hash(plain),
              record_manifest$rank_hash == rank_hash(fixture$ranks))
    path <- file.path(fixtures_dir, paste0(phase$fixture, ".", phase$format))
    stopifnot(identical(normalizePath(record_manifest$path), normalizePath(path)))
    input_hash <- value_hash(plain)
    ranks_hash <- rank_hash(fixture$ranks)
    input_missing <- sum(fixture$ranks > 0L)
    zero_observed <- sum(!is.na(plain) & plain == 0)
    proof <- expected_facts(plain, fixture$width, phase$format)
    expected <- plain
    expected_storage <- fixture$width
    if (operations > 0L) {
        expected <- 1.01 / plain
        expected[fixture$ranks > 0L | !is.finite(expected) |
                 abs(expected) > (2^53 - 1) * 2^970] <- NA_real_
        observed <- !is.na(expected)
        stopifnot(all(abs(expected[observed]) <= (2^24 - 1) * 2^103))
        expected[observed] <- readBin(writeBin(expected[observed], raw(), 4L, endian = "little"),
                                     "numeric", sum(observed), 4L, endian = "little")
        expected_storage <- "float"
    }
    expected_hash <- value_hash(expected)
    mask <- is.na(expected)
    missing_hash <- rank_hash(mask)
    reference <- workflow(path, phase$format, 0L)
    before <- state(reference$source)
    source_meta <- metadata_hash(reference$source)
    stopifnot(as.logical(before[["compact"]]), !before[["materialized"]],
              as.logical(before[["retained"]]) == (phase$format == "arrow"),
              identical(facts(reference$source), proof))
    check <- function(record) {
        source <- record$source
        result <- record$result
        stopifnot(length(source) == n, length(result) == n,
                  identical(dta_storage_type(source), fixture$width),
                  identical(dta_storage_type(result), expected_storage),
                  identical(facts(source), proof), identical(state(source), before),
                  identical(metadata_hash(source), source_meta),
                  identical(value_hash(source), input_hash),
                  identical(value_hash(result), expected_hash),
                  identical(is.na(result), mask), identical(anyNA(result), any(mask)),
                  dtatools:::.is_unmaterialized_numeric_altrep(result),
                  identical(facts(source), proof), identical(state(source), before))
    }
    check(workflow(path, phase$format, operations))
    started <- entry()
    record <- workflow(path, phase$format, operations)
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
            for (i in seq_len(repetitions)) record <- workflow(path, phase$format, operations)
            delta <- proc.time() - start
            duration <- unname(delta[["user.self"]] + delta[["sys.self"]])
            if (duration >= 0.03 || repetitions >= 100000L) break
            repetitions <- repetitions * 2L
        }
        repetitions <- min(1000000L, max(repetitions,
            as.integer(ceiling(repetitions * target_cpu / max(duration, 0.001)))))
        gc()
        started <- entry()
        start <- proc.time()
        for (i in seq_len(repetitions)) record <- workflow(path, phase$format, operations)
        delta <- proc.time() - start
        native_calls <- entry() - started
        cpu <- unname(delta[["user.self"]] + delta[["sys.self"]])
        wall <- unname(delta[["elapsed"]])
        stopifnot(native_calls == repetitions * operations)
        check(record)
        stopifnot(identical(metadata_hash(record$result), result_meta))
    }
    original <- record$result
    result_state <- state(original)
    cleared <- expected
    cleared[mask] <- 0
    cleared_hash <- value_hash(cleared)
    mutable <- dibble(x = original)
    replace_values(mutable, x = 0, where = which(mask))
    expected_result_state <- result_state
    if (operations == 0L && phase$format == "arrow") expected_result_state[c("retained", "chunks")] <- 0
    stopifnot(identical(value_hash(mutable$x), cleared_hash),
              !anyNA(mutable$x), !any(is.na(mutable$x)),
              identical(state(original), expected_result_state),
              identical(value_hash(original), expected_hash),
              identical(metadata_hash(original), result_meta))
    if (operations == 0L) {
        # Writable alias preparation invalidates facts and may detach retained
        # backing outside clocks. Original values, masks and metadata stay intact.
        stopifnot(facts(original)[["flags"]] == 0,
                  identical(is.na(original), mask), identical(anyNA(original), any(mask)))
    } else check(record)
    mutation_source_state <- state(record$source)
    rows[[length(rows) + 1L]] <- data.frame(round, variant,
        mode = if (qualify_only) "qualify" else "measure", position,
        fixture = phase$fixture, format = phase$format, width = fixture$width,
        rows = n, operations, repetitions, cpu, wall, native_calls, qualification_calls,
        input_hash, rank_hash = ranks_hash, input_missing, zero_observed,
        source_flags = proof[["flags"]], source_maximum = proof[["max_magnitude_bound"]],
        source_minimum = proof[["min_nonzero_magnitude_bound"]], source_zeros = proof[["zero_count"]],
        result_hash = expected_hash, missing_hash, result_missing = sum(mask),
        result_storage = expected_storage, source_metadata_hash = source_meta,
        result_metadata_hash = result_meta, cleared_hash, mutation_checked = TRUE,
        compact_before = as.logical(before[["compact"]]), compact_after = as.logical(state(record$source)[["compact"]]),
        materialized_before = as.logical(before[["materialized"]]), materialized_after = as.logical(state(record$source)[["materialized"]]),
        retained = as.logical(before[["retained"]]), chunks = before[["chunks"]],
        mutation_source_compact = as.logical(mutation_source_state[["compact"]]),
        mutation_source_materialized = as.logical(mutation_source_state[["materialized"]]),
        mutation_source_retained = as.logical(mutation_source_state[["retained"]]),
        mutation_source_chunks = mutation_source_state[["chunks"]],
        mutation_source_flags = facts(record$source)[["flags"]],
        automatic_gc_included = TRUE)
}
write.csv(do.call(rbind, rows), args[[3L]], row.names = FALSE)
cat(length(rows), if (qualify_only) "qualified reader/workflow cases\n" else "qualified reader/workflow observations\n")
