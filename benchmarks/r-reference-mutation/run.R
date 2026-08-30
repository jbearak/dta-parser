#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dtatools))

rows <- 5000000L
repetitions <- 25L
warmup <- data.frame(compact = stata_byte(1:2))
for (iteration in seq_len(5L)) {
    replace_values(warmup, compact, 2, where = 1)
}
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
largest_allocation <- max(allocation, na.rm = TRUE)
full_double_bytes <- as.double(rows) * 8
compact_byte_bytes <- as.double(rows)

stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    largest_allocation < compact_byte_bytes,
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
    dtatools:::.is_unmaterialized_numeric_altrep(late_missing$compact)
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
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(proxy$compact),
    identical(as.double(proxy_source[[rows]]), 1),
    largest_proxy_allocation >= compact_byte_bytes,
    largest_proxy_allocation < full_double_bytes
)

compact_trace <- tracemem(data$compact)
generation_time <- system.time(gen(data, generated, 3))[["elapsed"]]
stopifnot(
    identical(tracemem(data$compact), compact_trace),
    identical(tracemem(data$untouched), untouched_trace),
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    dtatools:::.is_unmaterialized_numeric_altrep(data$generated)
)
untracemem(data$compact)
untracemem(data$untouched)

cat(sprintf("rows\t%d\n", rows))
cat(sprintf("repetitions\t%d\n", repetitions))
cat(sprintf("sparse_replacement_seconds\t%.6f\n", replacement_time))
cat(sprintf("late_missing_sparse_seconds\t%.6f\n", late_missing_time))
cat(sprintf("largest_profiled_allocation_bytes\t%.0f\n", largest_allocation))
cat(sprintf(
    "largest_proxy_allocation_bytes\t%.0f\n",
    largest_proxy_allocation
))
cat(sprintf("compact_byte_bytes\t%.0f\n", compact_byte_bytes))
cat(sprintf("full_double_bytes\t%.0f\n", full_double_bytes))
cat(sprintf("generation_seconds\t%.3f\n", generation_time))
cat("existing_payload_copy_detected\tfalse\n")
