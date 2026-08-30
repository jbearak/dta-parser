#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dtatools))

rows <- 5000000L
data <- data.frame(
    compact = stata_byte(rep(1, rows)),
    untouched = runif(rows)
)
untouched_trace <- tracemem(data$untouched)

profile <- tempfile("dtatools-reference-replacement-", fileext = ".out")
Rprofmem(profile, threshold = 1000)
replacement_time <- system.time(
    replace_values(data, compact, 2, where = rows)
)[["elapsed"]]
Rprofmem(NULL)

records <- readLines(profile, warn = FALSE)
unlink(profile)
allocation <- suppressWarnings(as.numeric(sub(" .*", "", records)))
largest_allocation <- max(allocation, na.rm = TRUE)
full_double_bytes <- as.double(rows) * 8

stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    largest_allocation < full_double_bytes,
    identical(tracemem(data$untouched), untouched_trace)
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
cat(sprintf("sparse_replacement_seconds\t%.3f\n", replacement_time))
cat(sprintf("largest_profiled_allocation_bytes\t%.0f\n", largest_allocation))
cat(sprintf("full_double_bytes\t%.0f\n", full_double_bytes))
cat(sprintf("generation_seconds\t%.3f\n", generation_time))
cat("existing_payload_copy_detected\tfalse\n")
