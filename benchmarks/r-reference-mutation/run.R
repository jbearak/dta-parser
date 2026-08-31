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

all_rows_repetitions <- 5L
all_rows_replacement_time <- system.time(
    for (iteration in seq_len(all_rows_repetitions)) {
        replace_values(data, compact, 2)
    }
)[["elapsed"]] / all_rows_repetitions
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    all_rows_replacement_time < 0.2
)

raw_fill_repetitions <- 5L
raw_target <- raw(rows)
raw_fill_time <- system.time(
    for (iteration in seq_len(raw_fill_repetitions)) {
        raw_target[] <- as.raw(2)
    }
)[["elapsed"]] / raw_fill_repetitions
stopifnot(
    all_rows_replacement_time < max(0.02, raw_fill_time * 5)
)

logical_rows <- rep(FALSE, rows)
logical_rows[[rows]] <- TRUE
logical_profile <- tempfile(
    "dtatools-reference-logical-plan-", fileext = ".out"
)
Rprofmem(logical_profile, threshold = 1000)
logical_plan_time <- system.time(
    for (iteration in seq_len(5L)) {
        replace_values(data, compact, 3, where = logical_rows)
    }
)[["elapsed"]] / 5
Rprofmem(NULL)
logical_records <- readLines(logical_profile, warn = FALSE)
unlink(logical_profile)
logical_allocations <- suppressWarnings(as.numeric(sub(
    " .*", "", logical_records
)))
logical_plan_allocation <- sum(
    logical_allocations[is.finite(logical_allocations)]
)
stopifnot(
    logical_plan_time < 0.02,
    logical_plan_allocation < compact_byte_bytes
)

explicit_rows <- stata_long(seq_len(rows))
explicit_profile <- tempfile(
    "dtatools-reference-explicit-plan-", fileext = ".out"
)
Rprofmem(explicit_profile, threshold = 1000)
explicit_plan_time <- system.time(
    for (iteration in seq_len(3L)) {
        replace_values(data, compact, 2, where = explicit_rows)
    }
)[["elapsed"]] / 3
Rprofmem(NULL)
explicit_records <- readLines(explicit_profile, warn = FALSE)
unlink(explicit_profile)
explicit_allocations <- suppressWarnings(as.numeric(sub(
    " .*", "", explicit_records
)))
explicit_plan_allocation <- sum(
    explicit_allocations[is.finite(explicit_allocations)]
)
stopifnot(
    explicit_plan_time < 0.15,
    explicit_plan_allocation < compact_byte_bytes
)

integer_replacement <- rep.int(2L, rows)
vector_profile <- tempfile(
    "dtatools-reference-vector-replacement-", fileext = ".out"
)
Rprofmem(vector_profile, threshold = 1000)
vector_replacement_time <- system.time(
    replace_values(data, compact, integer_replacement)
)[["elapsed"]]
Rprofmem(NULL)
vector_records <- readLines(vector_profile, warn = FALSE)
unlink(vector_profile)
vector_allocations <- suppressWarnings(as.numeric(sub(
    " .*", "", vector_records
)))
recorded_vector <- vector_allocations[is.finite(vector_allocations)]
largest_vector_allocation <- if (length(recorded_vector) == 0L) {
    0
} else {
    max(recorded_vector)
}

compact_replacement <- stata_byte(rep(3, rows))
compact_vector_profile <- tempfile(
    "dtatools-reference-compact-vector-replacement-", fileext = ".out"
)
Rprofmem(compact_vector_profile, threshold = 1000)
compact_vector_replacement_time <- system.time(
    replace_values(data, compact, .env$compact_replacement)
)[["elapsed"]]
Rprofmem(NULL)
compact_vector_records <- readLines(compact_vector_profile, warn = FALSE)
unlink(compact_vector_profile)
compact_vector_allocations <- suppressWarnings(as.numeric(sub(
    " .*", "", compact_vector_records
)))
recorded_compact_vector <- compact_vector_allocations[
    is.finite(compact_vector_allocations)
]
largest_compact_vector_allocation <- if (
    length(recorded_compact_vector) == 0L
) {
    0
} else {
    max(recorded_compact_vector)
}
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    identical(as.double(data$compact[[rows]]), 3),
    largest_vector_allocation < compact_byte_bytes,
    largest_compact_vector_allocation < compact_byte_bytes,
    vector_replacement_time < 0.2,
    compact_vector_replacement_time < 0.3
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

integer_generation_values <- seq_len(rows)
integer_generation_data <- data.frame(anchor = stata_byte(rep(1, rows)))
integer_generation_trace <- tracemem(integer_generation_data$anchor)
integer_generation_profile <- tempfile(
    "dtatools-reference-integer-generation-", fileext = ".out"
)
Rprofmem(integer_generation_profile, threshold = 1000)
integer_generation_time <- system.time(
    gen(integer_generation_data, generated, integer_generation_values)
)[["elapsed"]]
Rprofmem(NULL)
integer_generation_records <- readLines(
    integer_generation_profile, warn = FALSE
)
unlink(integer_generation_profile)
integer_generation_allocations <- suppressWarnings(as.numeric(sub(
    " .*", "", integer_generation_records
)))
recorded_integer_generation <- integer_generation_allocations[
    is.finite(integer_generation_allocations)
]
largest_integer_generation_allocation <- if (
    length(recorded_integer_generation) == 0L
) {
    0
} else {
    max(recorded_integer_generation)
}

compact_generation_values <- stata_byte(rep(2, rows))
compact_generation_data <- data.frame(anchor = stata_byte(rep(1, rows)))
compact_generation_profile <- tempfile(
    "dtatools-reference-compact-vector-generation-", fileext = ".out"
)
Rprofmem(compact_generation_profile, threshold = 1000)
compact_vector_generation_time <- system.time(
    gen(compact_generation_data, generated, compact_generation_values)
)[["elapsed"]]
Rprofmem(NULL)
compact_generation_records <- readLines(
    compact_generation_profile, warn = FALSE
)
unlink(compact_generation_profile)
compact_generation_allocations <- suppressWarnings(as.numeric(sub(
    " .*", "", compact_generation_records
)))
recorded_compact_generation <- compact_generation_allocations[
    is.finite(compact_generation_allocations)
]
largest_compact_generation_allocation <- if (
    length(recorded_compact_generation) == 0L
) {
    0
} else {
    max(recorded_compact_generation)
}
stopifnot(
    identical(tracemem(integer_generation_data$anchor),
              integer_generation_trace),
    largest_integer_generation_allocation < full_double_bytes,
    largest_compact_generation_allocation < full_double_bytes,
    integer_generation_time < 0.2,
    compact_vector_generation_time < 0.3,
    dtatools:::.is_unmaterialized_numeric_altrep(
        compact_generation_data$generated
    )
)
untracemem(integer_generation_data$anchor)
untracemem(data$compact)
untracemem(data$untouched)

cat(sprintf("rows\t%d\n", rows))
cat(sprintf("repetitions\t%d\n", repetitions))
cat(sprintf("small_sparse_replacement_seconds\t%.6f\n", small_replacement_time))
cat(sprintf("sparse_replacement_seconds\t%.6f\n", replacement_time))
cat(sprintf(
    "all_rows_scalar_replacement_seconds\t%.6f\n",
    all_rows_replacement_time
))
cat(sprintf("raw_fill_seconds\t%.6f\n", raw_fill_time))
cat(sprintf("logical_plan_seconds\t%.6f\n", logical_plan_time))
cat(sprintf(
    "logical_plan_profiled_allocation_bytes\t%.0f\n",
    logical_plan_allocation
))
cat(sprintf("explicit_plan_seconds\t%.6f\n", explicit_plan_time))
cat(sprintf(
    "explicit_plan_profiled_allocation_bytes\t%.0f\n",
    explicit_plan_allocation
))
cat(sprintf(
    "integer_vector_replacement_seconds\t%.6f\n",
    vector_replacement_time
))
cat(sprintf(
    "integer_vector_replacement_largest_allocation_bytes\t%.0f\n",
    largest_vector_allocation
))
cat(sprintf(
    "compact_vector_replacement_seconds\t%.6f\n",
    compact_vector_replacement_time
))
cat(sprintf(
    "compact_vector_replacement_largest_allocation_bytes\t%.0f\n",
    largest_compact_vector_allocation
))
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
cat(sprintf(
    "integer_vector_generation_seconds\t%.6f\n",
    integer_generation_time
))
cat(sprintf(
    "integer_vector_generation_largest_allocation_bytes\t%.0f\n",
    largest_integer_generation_allocation
))
cat(sprintf(
    "compact_vector_generation_seconds\t%.6f\n",
    compact_vector_generation_time
))
cat(sprintf(
    "compact_vector_generation_largest_allocation_bytes\t%.0f\n",
    largest_compact_generation_allocation
))
cat(sprintf("compact_byte_bytes\t%.0f\n", compact_byte_bytes))
cat(sprintf("full_double_bytes\t%.0f\n", full_double_bytes))
cat(sprintf("generation_seconds\t%.3f\n", generation_time))
cat("existing_payload_copy_detected\tfalse\n")
