#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(dtatools))

profile_memory <- function(code, prefix) {
    path <- tempfile(prefix, fileext = ".out")
    on.exit({
        Rprofmem(NULL)
        unlink(path)
    }, add = TRUE)
    Rprofmem(path, threshold = 1000)
    elapsed <- system.time(force(code))[["elapsed"]]
    Rprofmem(NULL)
    records <- readLines(path, warn = FALSE)
    allocations <- suppressWarnings(as.numeric(sub(" .*", "", records)))
    allocations <- allocations[is.finite(allocations)]
    list(
        elapsed = elapsed,
        total = sum(allocations),
        largest = if (length(allocations) == 0L) 0 else max(allocations)
    )
}

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

replacement_profile <- profile_memory(
    for (iteration in seq_len(repetitions)) {
        replace_values(data, compact, 2, where = rows)
    },
    "dtatools-reference-replacement-"
)
replacement_time <- replacement_profile$elapsed / repetitions
largest_allocation <- replacement_profile$largest
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
logical_profile <- profile_memory(
    for (iteration in seq_len(5L)) {
        replace_values(data, compact, 3, where = logical_rows)
    },
    "dtatools-reference-logical-plan-"
)
logical_plan_time <- logical_profile$elapsed / 5
logical_plan_allocation <- logical_profile$total
all_false_rows <- rep(FALSE, rows)
all_false_profile <- profile_memory(
    replace_values(data, compact, 3, where = all_false_rows),
    "dtatools-reference-all-false-plan-"
)
all_false_plan_time <- all_false_profile$elapsed
all_false_plan_allocation <- all_false_profile$total
stopifnot(
    logical_plan_time < 0.02,
    logical_plan_allocation < compact_byte_bytes,
    all_false_plan_time < max(0.01, logical_plan_time * 0.75),
    all_false_plan_allocation < compact_byte_bytes
)

explicit_rows <- stata_long(seq_len(rows))
integer_explicit_rows <- seq_len(rows)
integer_explicit_plan_time <- system.time(
    for (iteration in seq_len(3L)) {
        replace_values(data, compact, 2, where = integer_explicit_rows)
    }
)[["elapsed"]] / 3
explicit_profile <- profile_memory(
    for (iteration in seq_len(3L)) {
        replace_values(data, compact, 2, where = explicit_rows)
    },
    "dtatools-reference-explicit-plan-"
)
explicit_plan_time <- explicit_profile$elapsed / 3
explicit_plan_allocation <- explicit_profile$total
stopifnot(
    explicit_plan_time < max(0.02, integer_explicit_plan_time * 4),
    explicit_plan_allocation < compact_byte_bytes
)

integer_replacement <- rep.int(2L, rows)
vector_profile <- profile_memory(
    replace_values(data, compact, integer_replacement),
    "dtatools-reference-vector-replacement-"
)
vector_replacement_time <- vector_profile$elapsed
largest_vector_allocation <- vector_profile$largest

position_vector_profile <- profile_memory(
    replace_values(
        data, compact, integer_replacement, where = explicit_rows
    ),
    "dtatools-reference-position-vector-replacement-"
)
position_vector_replacement_time <- position_vector_profile$elapsed
largest_position_vector_allocation <- position_vector_profile$largest

selected_count <- rows - 1L
selected_rows <- stata_long(seq_len(selected_count))
integer_selected_rows <- seq_len(selected_count)
selected_replacement <- rep.int(2L, selected_count)
integer_selected_time <- system.time(
    replace_values(
        data, compact, selected_replacement, where = integer_selected_rows
    )
)[["elapsed"]]
selected_profile <- profile_memory(
    replace_values(
        data, compact, selected_replacement, where = selected_rows
    ),
    "dtatools-reference-selected-vector-replacement-"
)
selected_vector_replacement_time <- selected_profile$elapsed
largest_selected_vector_allocation <- selected_profile$largest

compact_replacement <- stata_byte(rep(3, rows))
compact_vector_profile <- profile_memory(
    replace_values(data, compact, .env$compact_replacement),
    "dtatools-reference-compact-vector-replacement-"
)
compact_vector_replacement_time <- compact_vector_profile$elapsed
largest_compact_vector_allocation <- compact_vector_profile$largest
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    identical(as.double(data$compact[[rows]]), 3),
    largest_vector_allocation < compact_byte_bytes,
    largest_position_vector_allocation < compact_byte_bytes,
    largest_selected_vector_allocation < compact_byte_bytes,
    largest_compact_vector_allocation < compact_byte_bytes,
    vector_replacement_time < 0.2,
    position_vector_replacement_time < 0.3,
    selected_vector_replacement_time < max(0.25, integer_selected_time * 2),
    compact_vector_replacement_time < 0.3
)

ordinary_data <- data.frame(value = rep(1, rows))
ordinary_values <- rep(2, rows)
ordinary_sparse_profile <- profile_memory(
    replace_values(ordinary_data, value, ordinary_values, where = rows),
    "dtatools-reference-ordinary-sparse-replacement-"
)
ordinary_sparse_time <- ordinary_sparse_profile$elapsed
total_ordinary_sparse_allocation <- ordinary_sparse_profile$total
largest_ordinary_sparse_allocation <- ordinary_sparse_profile$largest
stopifnot(
    identical(ordinary_data$value[[rows]], 2),
    largest_ordinary_sparse_allocation < compact_byte_bytes,
    total_ordinary_sparse_allocation < compact_byte_bytes,
    ordinary_sparse_time < 0.1
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
proxy_profile <- profile_memory(
    replace_values(proxy, compact, 2, where = rows),
    "dtatools-reference-proxy-"
)
largest_proxy_allocation <- proxy_profile$largest
second_proxy_profile <- profile_memory(
    replace_values(proxy, compact, 3, where = rows - 1L),
    "dtatools-reference-proxy-second-"
)
largest_second_proxy_allocation <- second_proxy_profile$largest
stopifnot(
    dtatools:::.is_unmaterialized_numeric_altrep(proxy$compact),
    identical(as.double(proxy_source[[rows]]), 1),
    identical(as.double(proxy_source[[rows - 1L]]), 1),
    largest_proxy_allocation >= compact_byte_bytes,
    largest_proxy_allocation < full_double_bytes,
    largest_second_proxy_allocation < compact_byte_bytes
)

compact_trace <- tracemem(data$compact)
generation_profile <- profile_memory(
    gen(data, generated, stata_byte(3)),
    "dtatools-reference-generation-"
)
generation_time <- generation_profile$elapsed
largest_generation_allocation <- generation_profile$largest
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
integer_generation_profile <- profile_memory(
    gen(integer_generation_data, generated, integer_generation_values),
    "dtatools-reference-integer-generation-"
)
integer_generation_time <- integer_generation_profile$elapsed
largest_integer_generation_allocation <- integer_generation_profile$largest

position_generation_data <- data.frame(anchor = stata_byte(rep(1, rows)))
position_generation_profile <- profile_memory(
    gen(
        position_generation_data, generated, integer_generation_values,
        where = explicit_rows
    ),
    "dtatools-reference-position-vector-generation-"
)
position_vector_generation_time <- position_generation_profile$elapsed
largest_position_generation_allocation <- position_generation_profile$largest
total_position_generation_allocation <- position_generation_profile$total

compact_generation_values <- stata_byte(rep(2, rows))
compact_generation_data <- data.frame(anchor = stata_byte(rep(1, rows)))
compact_generation_profile <- profile_memory(
    gen(compact_generation_data, generated, compact_generation_values),
    "dtatools-reference-compact-vector-generation-"
)
compact_vector_generation_time <- compact_generation_profile$elapsed
largest_compact_generation_allocation <- compact_generation_profile$largest
stopifnot(
    identical(tracemem(integer_generation_data$anchor),
              integer_generation_trace),
    largest_integer_generation_allocation < full_double_bytes,
    largest_position_generation_allocation <= rows * 4 * 1.01,
    total_position_generation_allocation < full_double_bytes,
    largest_compact_generation_allocation < full_double_bytes,
    integer_generation_time < 0.2,
    position_vector_generation_time < 0.3,
    compact_vector_generation_time < 0.3,
    identical(
        as.double(position_generation_data$generated[c(1L, rows)]),
        c(1, rows)
    ),
    dtatools:::.is_unmaterialized_numeric_altrep(
        compact_generation_data$generated
    )
)

first_generated_patch_profile <- profile_memory(
    replace_values(integer_generation_data, generated, 1, where = rows),
    "dtatools-reference-first-generated-patch-"
)
largest_first_generated_patch_allocation <-
    first_generated_patch_profile$largest
stopifnot(
    dtatools:::.metadata_proxy_depth(
        integer_generation_data$generated
    ) == 0L,
    dtatools:::.is_unmaterialized_numeric_altrep(
        integer_generation_data$generated
    ),
    largest_first_generated_patch_allocation < compact_byte_bytes
)

temporal_generation_values <- as.POSIXct(
    "2000-01-01", tz = "UTC"
) + seq_len(rows)
temporal_generation_data <- data.frame(anchor = stata_byte(.size = rows))
temporal_generation_profile <- profile_memory(
    gen(
        temporal_generation_data, generated,
        temporal_generation_values
    ),
    "dtatools-reference-temporal-generation-"
)
temporal_generation_time <- temporal_generation_profile$elapsed
total_temporal_generation_allocation <- temporal_generation_profile$total
largest_temporal_generation_allocation <- temporal_generation_profile$largest
stopifnot(
    identical(
        as.double(temporal_generation_data$generated),
        as.double(temporal_generation_values)
    ),
    inherits(temporal_generation_data$generated, "stata_datetime"),
    identical(
        stata_storage_type(temporal_generation_data$generated), "double"
    ),
    largest_temporal_generation_allocation <= full_double_bytes * 1.01,
    total_temporal_generation_allocation < full_double_bytes * 2,
    temporal_generation_time < 0.5
)

character_generation_data <- data.frame(
    anchor = stata_byte(rep(1, rows))
)
character_generation_profile <- profile_memory(
    gen(character_generation_data, generated, "x"),
    "dtatools-reference-character-generation-"
)
character_generation_time <- character_generation_profile$elapsed
total_character_generation_allocation <- character_generation_profile$total
largest_character_generation_allocation <- character_generation_profile$largest
stopifnot(
    identical(
        as.character(character_generation_data$generated[c(1L, rows)]),
        c("x", "x")
    ),
    identical(
        attr(character_generation_data$generated, "stata.string.storage"),
        "str1"
    ),
    largest_character_generation_allocation <= full_double_bytes * 1.01,
    total_character_generation_allocation < full_double_bytes * 1.5,
    character_generation_time < 0.5
)

dictionary_path <- tempfile(fileext = ".arrow")
save_arrow(data.frame(
    text = rep(c("a", "b"), length.out = rows)
), dictionary_path)
dictionary_data <- read_arrow(dictionary_path)
unlink(dictionary_path)
stopifnot(dtatools:::.is_unmaterialized_dictstring(dictionary_data$text))
dictionary_profile <- profile_memory(
    replace_values(dictionary_data, text, "changed"),
    "dtatools-reference-dictionary-replacement-"
)
dictionary_replacement_time <- dictionary_profile$elapsed
total_dictionary_replacement_allocation <- dictionary_profile$total
largest_dictionary_replacement_allocation <- dictionary_profile$largest
stopifnot(
    identical(
        as.character(dictionary_data$text[c(1L, rows)]),
        c("changed", "changed")
    ),
    largest_dictionary_replacement_allocation <= full_double_bytes * 1.01,
    total_dictionary_replacement_allocation < full_double_bytes * 1.5,
    dictionary_replacement_time < 1
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
cat(sprintf("all_false_plan_seconds\t%.6f\n", all_false_plan_time))
cat(sprintf(
    "all_false_plan_profiled_allocation_bytes\t%.0f\n",
    all_false_plan_allocation
))
cat(sprintf("explicit_plan_seconds\t%.6f\n", explicit_plan_time))
cat(sprintf(
    "integer_explicit_plan_seconds\t%.6f\n",
    integer_explicit_plan_time
))
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
    "position_vector_replacement_seconds\t%.6f\n",
    position_vector_replacement_time
))
cat(sprintf(
    "position_vector_replacement_largest_allocation_bytes\t%.0f\n",
    largest_position_vector_allocation
))
cat(sprintf(
    "selected_vector_replacement_seconds\t%.6f\n",
    selected_vector_replacement_time
))
cat(sprintf(
    "integer_selected_vector_replacement_seconds\t%.6f\n",
    integer_selected_time
))
cat(sprintf(
    "selected_vector_replacement_largest_allocation_bytes\t%.0f\n",
    largest_selected_vector_allocation
))
cat(sprintf(
    "compact_vector_replacement_seconds\t%.6f\n",
    compact_vector_replacement_time
))
cat(sprintf(
    "compact_vector_replacement_largest_allocation_bytes\t%.0f\n",
    largest_compact_vector_allocation
))
cat(sprintf(
    "ordinary_sparse_full_values_seconds\t%.6f\n",
    ordinary_sparse_time
))
cat(sprintf(
    "ordinary_sparse_full_values_total_profiled_allocation_bytes\t%.0f\n",
    total_ordinary_sparse_allocation
))
cat(sprintf(
    "ordinary_sparse_full_values_largest_allocation_bytes\t%.0f\n",
    largest_ordinary_sparse_allocation
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
    "position_vector_generation_seconds\t%.6f\n",
    position_vector_generation_time
))
cat(sprintf(
    "position_vector_generation_total_profiled_allocation_bytes\t%.0f\n",
    total_position_generation_allocation
))
cat(sprintf(
    "position_vector_generation_largest_allocation_bytes\t%.0f\n",
    largest_position_generation_allocation
))
cat(sprintf(
    "compact_vector_generation_seconds\t%.6f\n",
    compact_vector_generation_time
))
cat(sprintf(
    "compact_vector_generation_largest_allocation_bytes\t%.0f\n",
    largest_compact_generation_allocation
))
cat(sprintf(
    "first_generated_patch_largest_allocation_bytes\t%.0f\n",
    largest_first_generated_patch_allocation
))
cat(sprintf(
    "temporal_generation_seconds\t%.6f\n",
    temporal_generation_time
))
cat(sprintf(
    "temporal_generation_total_profiled_allocation_bytes\t%.0f\n",
    total_temporal_generation_allocation
))
cat(sprintf(
    "temporal_generation_largest_allocation_bytes\t%.0f\n",
    largest_temporal_generation_allocation
))
cat(sprintf(
    "character_generation_seconds\t%.6f\n",
    character_generation_time
))
cat(sprintf(
    "character_generation_total_profiled_allocation_bytes\t%.0f\n",
    total_character_generation_allocation
))
cat(sprintf(
    "character_generation_largest_allocation_bytes\t%.0f\n",
    largest_character_generation_allocation
))
cat(sprintf(
    "dictionary_replacement_seconds\t%.6f\n",
    dictionary_replacement_time
))
cat(sprintf(
    "dictionary_replacement_total_profiled_allocation_bytes\t%.0f\n",
    total_dictionary_replacement_allocation
))
cat(sprintf(
    "dictionary_replacement_largest_allocation_bytes\t%.0f\n",
    largest_dictionary_replacement_allocation
))
cat(sprintf("compact_byte_bytes\t%.0f\n", compact_byte_bytes))
cat(sprintf("full_double_bytes\t%.0f\n", full_double_bytes))
cat(sprintf("generation_seconds\t%.3f\n", generation_time))
cat("existing_payload_copy_detected\tfalse\n")
