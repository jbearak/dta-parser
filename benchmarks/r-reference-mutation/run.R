#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dtatools))

rows <- 5000000L
small_rows <- 50000L
repetitions <- 100L
warmup <- data.frame(compact = stata_byte(1:2))
for (iteration in seq_len(5L)) {
    replace_values(warmup, compact, 2, where = 1)
}
small <- data.frame(compact = stata_byte(rep(1, small_rows)))
small_replacement_time <- system.time(
    for (iteration in seq_len(repetitions)) {
        replace_values(small, compact, 2, where = small_rows)
    }
)[["elapsed"]] / repetitions
data <- data.frame(
    compact = stata_byte(rep(1, rows)),
    untouched = runif(rows)
)
untouched_trace <- tracemem(data$untouched)

profile <- tempfile("dtatools-reference-replacement-", fileext = ".out")
Rprofmem(profile, threshold = 1000)
replacement_time <- system.time(
    for (iteration in seq_len(repetitions)) {
        replace_values(data, compact, 2, where = rows)
    }
)[["elapsed"]] / repetitions
Rprofmem(NULL)

records <- readLines(profile, warn = FALSE)
unlink(profile)
allocation <- suppressWarnings(as.numeric(sub(" .*", "", records)))
recorded_allocation <- allocation[is.finite(allocation)]
largest_allocation <- if (length(recorded_allocation) == 0L) {
    0
} else {
    max(recorded_allocation)
}
full_double_bytes <- as.double(rows) * 8
compact_byte_bytes <- as.double(rows)

stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    largest_allocation < compact_byte_bytes,
    replacement_time < 0.002,
    replacement_time < max(0.0005, small_replacement_time * 10),
    identical(tracemem(data$untouched), untouched_trace)
)

late_missing <- data.frame(
    compact = stata_byte(c(rep(1, rows - 1L), NA_real_))
)
late_missing_time <- system.time(
    for (iteration in seq_len(repetitions)) {
        replace_values(late_missing, compact, 2, where = 1L)
    }
)[["elapsed"]] / repetitions
stopifnot(
    anyNA(late_missing$compact),
    dtatools:::.is_unmaterialized_numeric_altrep(late_missing$compact),
    late_missing_time < max(0.002, replacement_time * 10)
)

cleared_missing <- data.frame(
    compact = stata_byte(c(rep(1, rows - 1L), NA_real_))
)
missing_cycle_time <- system.time(
    for (iteration in seq_len(repetitions)) {
        replace_values(cleared_missing, compact, 1, where = rows)
        replace_values(cleared_missing, compact, NA_real_, where = rows)
    }
)[["elapsed"]] / (2 * repetitions)
replace_values(cleared_missing, compact, 1, where = rows)
stopifnot(
    !anyNA(cleared_missing$compact),
    dtatools:::.is_unmaterialized_numeric_altrep(cleared_missing$compact),
    missing_cycle_time < max(0.002, replacement_time * 10)
)

proxy_source <- stata_byte(rep(1, rows))
proxy <- data.frame(compact = dtatools:::.metadata_copy(proxy_source))
proxy_profile <- tempfile("dtatools-reference-proxy-", fileext = ".out")
Rprofmem(proxy_profile, threshold = 1000)
replace_values(proxy, compact, 2, where = rows)
Rprofmem(NULL)
proxy_records <- readLines(proxy_profile, warn = FALSE)
unlink(proxy_profile)
proxy_allocation <- suppressWarnings(as.numeric(sub(" .*", "", proxy_records)))
largest_proxy_allocation <- max(proxy_allocation, na.rm = TRUE)
second_proxy_profile <- tempfile(
    "dtatools-reference-proxy-second-", fileext = ".out"
)
Rprofmem(second_proxy_profile, threshold = 1000)
replace_values(proxy, compact, 3, where = rows - 1L)
Rprofmem(NULL)
second_proxy_records <- readLines(second_proxy_profile, warn = FALSE)
unlink(second_proxy_profile)
second_proxy_allocation <- suppressWarnings(as.numeric(sub(
    " .*", "", second_proxy_records
)))
recorded_second_proxy <- second_proxy_allocation[
    is.finite(second_proxy_allocation)
]
largest_second_proxy_allocation <- if (length(recorded_second_proxy) == 0L) {
    0
} else {
    max(recorded_second_proxy)
}
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(proxy$compact),
    identical(as.double(proxy_source[[rows]]), 1),
    identical(as.double(proxy_source[[rows - 1L]]), 1),
    largest_proxy_allocation >= compact_byte_bytes,
    largest_proxy_allocation < full_double_bytes,
    largest_second_proxy_allocation < compact_byte_bytes
)

compact_trace <- tracemem(data$compact)
generation_profile <- tempfile(
    "dtatools-reference-generation-", fileext = ".out"
)
Rprofmem(generation_profile, threshold = 1000)
generation_time <- system.time(
    gen(data, generated, stata_byte(3))
)[["elapsed"]]
Rprofmem(NULL)
generation_records <- readLines(generation_profile, warn = FALSE)
unlink(generation_profile)
generation_allocation <- suppressWarnings(as.numeric(sub(
    " .*", "", generation_records
)))
largest_generation_allocation <- max(generation_allocation, na.rm = TRUE)
stopifnot(
    identical(tracemem(data$compact), compact_trace),
    identical(tracemem(data$untouched), untouched_trace),
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    dtatools:::.is_unmaterialized_numeric_altrep(data$generated),
    identical(stata_storage_type(data$generated), "byte"),
    largest_generation_allocation < full_double_bytes
)
untracemem(data$compact)
untracemem(data$untouched)

cat(sprintf("rows\t%d\n", rows))
cat(sprintf("repetitions\t%d\n", repetitions))
cat(sprintf("small_sparse_replacement_seconds\t%.6f\n", small_replacement_time))
cat(sprintf("sparse_replacement_seconds\t%.6f\n", replacement_time))
cat(sprintf("late_missing_sparse_seconds\t%.6f\n", late_missing_time))
cat(sprintf("missing_cycle_seconds\t%.6f\n", missing_cycle_time))
cat(sprintf("largest_profiled_allocation_bytes\t%.0f\n", largest_allocation))
cat(sprintf(
    "largest_proxy_allocation_bytes\t%.0f\n",
    largest_proxy_allocation
))
cat(sprintf(
    "largest_second_proxy_allocation_bytes\t%.0f\n",
    largest_second_proxy_allocation
))
cat(sprintf(
    "largest_generation_allocation_bytes\t%.0f\n",
    largest_generation_allocation
))
cat(sprintf("compact_byte_bytes\t%.0f\n", compact_byte_bytes))
cat(sprintf("full_double_bytes\t%.0f\n", full_double_bytes))
cat(sprintf("generation_seconds\t%.3f\n", generation_time))
cat("existing_payload_copy_detected\tfalse\n")
