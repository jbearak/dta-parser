#!/usr/bin/env Rscript

required_benchmark_packages <- "callr"
missing_benchmark_packages <- required_benchmark_packages[!vapply(
    required_benchmark_packages, requireNamespace, logical(1), quietly = TRUE
)]
if (length(missing_benchmark_packages) > 0L) {
    stop(
        sprintf(
            "Install the required benchmark package: %s",
            paste(missing_benchmark_packages, collapse = ", ")
        ),
        call. = FALSE
    )
}
if (!capabilities("profmem")) {
    stop(
        "This benchmark requires an R build with memory profiling enabled",
        call. = FALSE
    )
}

arguments <- commandArgs(trailingOnly = TRUE)
markdown_argument <- grep("^--markdown=", arguments, value = TRUE)
if (length(markdown_argument) > 1L) {
    stop("Pass at most one `--markdown=PATH` argument", call. = FALSE)
}
markdown_path <- if (length(markdown_argument) == 0L) {
    ""
} else {
    sub("^--markdown=", "", markdown_argument[[1L]])
}

if (!identical(Sys.getenv("DTATOOLS_BENCHMARK_CHILD"), "1")) {
    file_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE),
                          value = TRUE)
    if (length(file_argument) != 1L) {
        stop("Run this benchmark with `Rscript`", call. = FALSE)
    }
    script_path <- normalizePath(sub("^--file=", "", file_argument))
    repository <- normalizePath(file.path(dirname(script_path), "../.."))
    package_path <- file.path(repository, "r-package", "dtatools")
    library_path <- tempfile("dtatools-reference-library-")
    install_log <- tempfile("dtatools-reference-install-", fileext = ".log")
    dir.create(library_path)
    on.exit(unlink(c(library_path, install_log), recursive = TRUE), add = TRUE)

    source_sha <- system2(
        "git", c("-C", shQuote(repository), "rev-parse", "HEAD"),
        stdout = TRUE
    )
    source_changes <- system2(
        "git",
        c("-C", shQuote(repository), "status", "--short"),
        stdout = TRUE
    )
    source_state <- if (length(source_changes) == 0L) "clean" else "modified"
    if (source_state != "clean") {
        stop(
            "Commit or remove tracked and untracked changes before benchmarking",
            call. = FALSE
        )
    }
    original_directory <- getwd()
    setwd(repository)
    install_status <- system2(
        file.path(R.home("bin"), "Rscript"),
        vapply(c("benchmarks/r-dibble-dplyr/install.R", library_path, source_sha), shQuote, character(1)),
        stdout = install_log, stderr = install_log
    )
    setwd(original_directory)
    if (!identical(install_status, 0L)) {
        writeLines(readLines(install_log, warn = FALSE), stderr())
        stop("Could not install the benchmark source package", call. = FALSE)
    }

    child_arguments <- vapply(
        c(script_path, markdown_argument), shQuote, character(1)
    )
    child_status <- system2(
        file.path(R.home("bin"), "Rscript"), child_arguments,
        env = c(
            sprintf("DTATOOLS_BENCHMARK_CHILD=%s", shQuote("1")),
            sprintf("DTATOOLS_BENCHMARK_LIBRARY=%s", shQuote(library_path)),
            sprintf("DTATOOLS_BENCHMARK_SHA=%s", shQuote(source_sha)),
            sprintf("DTATOOLS_BENCHMARK_STATE=%s", shQuote(source_state))
        )
    )
    quit(status = child_status)
}

.libPaths(c(Sys.getenv("DTATOOLS_BENCHMARK_LIBRARY"), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
expected_package <- normalizePath(file.path(Sys.getenv("DTATOOLS_BENCHMARK_LIBRARY"), "dtatools"))
stopifnot(identical(normalizePath(find.package("dtatools")), expected_package),
          identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]),
                    normalizePath(file.path(expected_package, "libs", paste0("dtatools", .Platform$dynlib.ext)))))
# The normal entry point binds this library to a git archive. Development child
# runs are diagnostic only and explicitly retain their non-clean source label.
if (identical(Sys.getenv("DTATOOLS_BENCHMARK_STATE"), "clean")) {
    file_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    script_path <- normalizePath(sub("^--file=", "", file_argument))
    source(file.path(dirname(script_path), "../r-dibble-dplyr/helpers.R"))
    validate_benchmark_install(Sys.getenv("DTATOOLS_BENCHMARK_LIBRARY"), Sys.getenv("DTATOOLS_BENCHMARK_SHA"))
}

benchmark_metrics <- list()

record_metric <- function(name, value, format = NULL) {
    formatted <- if (is.null(format)) as.character(value) else {
        sprintf(format, value)
    }
    valid_name <- length(name) == 1L && !is.na(name) && name != "" &&
        !grepl("[\t\n]", name) && !name %in% names(benchmark_metrics)
    valid_value <- length(formatted) == 1L && !is.na(formatted) &&
        !grepl("[\t\n]", formatted)
    if (!valid_name || !valid_value) {
        stop("Invalid or duplicate benchmark metric", call. = FALSE)
    }
    benchmark_metrics[[name]] <<- formatted
    invisible(NULL)
}

emit_metrics <- function(metrics, markdown_path) {
    writeLines(paste(names(metrics), unlist(metrics), sep = "\t"))
    if (markdown_path == "") return(invisible(NULL))
    markdown <- c(
        "# R reference mutation benchmark metrics",
        "",
        "| Measurement | Result |",
        "| --- | ---: |",
        sprintf("| `%s` | %s |", names(metrics), unlist(metrics))
    )
    writeLines(markdown, markdown_path)
    invisible(NULL)
}

record_metric("benchmark_source_sha", Sys.getenv("DTATOOLS_BENCHMARK_SHA"))
record_metric("benchmark_source_state", Sys.getenv("DTATOOLS_BENCHMARK_STATE"))

profile_memory <- function(code, prefix) {
    path <- tempfile(prefix, fileext = ".out")
    on.exit({
        Rprofmem(NULL)
        unlink(path)
    }, add = TRUE)
    before_native <- native("C_dtatools_native_copy_stats", FALSE)
    Rprofmem(path, threshold = 1000)
    elapsed <- system.time(force(code))[["elapsed"]]
    Rprofmem(NULL)
    native_bytes <- native("C_dtatools_native_copy_stats", FALSE) - before_native
    key <- gsub("-", "_", sub("-$", "", prefix))
    for (field in names(native_bytes)) {
        record_metric(paste0(key, "_native_", field, "_bytes"), native_bytes[[field]], "%.0f")
    }
    records <- readLines(path, warn = FALSE)
    allocations <- suppressWarnings(as.numeric(sub(" .*", "", records)))
    allocations <- allocations[is.finite(allocations)]
    list(
        elapsed = elapsed,
        total = sum(allocations),
        largest = if (length(allocations) == 0L) 0 else max(allocations)
    )
}

# Preparation is assigned before measuring the operation. These checks inspect
# the physical table without exporting a column or requesting a writable pointer.
native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
assert_frame <- function(data, extra = 0L) {
    stopifnot(is.data.frame(data), !is_dibble(data),
              !inherits(data, "tbl_df"), !inherits(data, "data.table"))
    if (extra > 0L) stopifnot(can_add_columns(data, extra))
    invisible(data)
}
assert_private <- function(data, location) {
    info <- native("C_dtatools_mutation_info", data, as.integer(location))
    stopifnot(!info$handle_shared, info$backing_private, !info$exposed,
              info$depth <= 1L)
    invisible(info)
}
capture_private <- function(data, name, value, row, metric) {
    assert_frame(data)
    profile <- profile_memory(
        replace_values(data, !!rlang::sym(name), .env$value, where = .env$row),
        paste0("dtatools-capture-", metric, "-")
    )
    record_metric(paste0(metric, "_capture_total_profiled_allocation_bytes"), profile$total, "%.0f")
    record_metric(paste0(metric, "_capture_largest_allocation_bytes"), profile$largest, "%.0f")
    record_metric(paste0(metric, "_capture_seconds"), profile$elapsed, "%.6f")
    assert_private(data, match(name, names(data)))
    invisible(data)
}

rows <- 5000000L
small_rows <- 50000L
repetitions <- 100L
warmup <- data.frame(compact = dta_byte(1:2))
capture_private(warmup, "compact", 1, 1L, "warmup")
for (iteration in seq_len(5L)) {
    replace_values(warmup, compact, 2, where = 1)
}
small <- data.frame(compact = dta_byte(rep(1, small_rows)))
capture_private(small, "compact", 1, 1L, "small")
small_replacement_time <- system.time(
    for (iteration in seq_len(repetitions)) {
        replace_values(small, compact, 2, where = small_rows)
    }
)[["elapsed"]] / repetitions
data <- data.frame(
    compact = dta_byte(rep(1, rows)),
    untouched = runif(rows)
)
data <- reserve_columns(data, n = 1L)
assert_frame(data, 1L)
capture_private(data, "compact", 1, 1L, "main")
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

label_replacement_data <- data
dataset_label_profile <- profile_memory(
    dataset_label(label_replacement_data) <- "Benchmark",
    "dtatools-dataset-label-replacement-"
)
dataset_label_replacement_time <- dataset_label_profile$elapsed
dataset_label_replacement_allocation <- dataset_label_profile$total
largest_dataset_label_replacement_allocation <- dataset_label_profile$largest
stopifnot(
    identical(dataset_label(label_replacement_data), "Benchmark"),
    dataset_label_replacement_allocation < compact_byte_bytes,
    largest_dataset_label_replacement_allocation < compact_byte_bytes
)

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

explicit_rows <- dta_long(seq_len(rows))
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
selected_rows <- dta_long(seq_len(selected_count))
integer_selected_rows <- seq_len(selected_count)
selected_replacement <- rep.int(2L, selected_count)
integer_selected_time <- system.time(
    replace_values(
        data, compact, selected_replacement, where = integer_selected_rows
    )
)[["elapsed"]]
invisible(dtatools:::.reference_row_reads(TRUE))
selected_profile <- profile_memory(
    replace_values(
        data, compact, selected_replacement, where = selected_rows
    ),
    "dtatools-reference-selected-vector-replacement-"
)
selected_position_row_reads <- dtatools:::.reference_row_reads(FALSE)
selected_vector_replacement_time <- selected_profile$elapsed
largest_selected_vector_allocation <- selected_profile$largest

compact_replacement <- dta_byte(rep(3, rows))
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
    selected_position_row_reads > 0,
    selected_position_row_reads <= as.double(selected_count) * 4,
    compact_vector_replacement_time < 0.3
)

ordinary_data <- data.frame(value = rep(1, rows))
capture_private(ordinary_data, "value", 1, 1L, "ordinary")
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
    compact = dta_byte(c(rep(1, rows - 1L), NA_real_))
)
capture_private(late_missing, "compact", 1, 1L, "late_missing")
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
    compact = dta_byte(c(rep(1, rows - 1L), NA_real_))
)
capture_private(cleared_missing, "compact", 1, 1L, "cleared_missing")
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

proxy_source <- dta_byte(rep(1, rows))
proxy <- data.frame(compact = dtatools:::.metadata_copy(proxy_source))
proxy_profile <- profile_memory(
    replace_values(proxy, compact, 2, where = rows),
    "dtatools-reference-proxy-"
)
largest_proxy_allocation <- proxy_profile$largest
# The second sparse index is a fixture too. Arbitrary expression snapshots have
# their own allocation measurement; this gate measures a proven private write.
second_proxy_row <- rows - 1L
assert_private(proxy, 1L)
second_proxy_profile <- profile_memory(
    replace_values(proxy, compact, 3, where = .env$second_proxy_row),
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
    gen(data, generated, dta_byte(3)),
    "dtatools-reference-generation-"
)
generation_time <- generation_profile$elapsed
largest_generation_allocation <- generation_profile$largest
stopifnot(
    identical(tracemem(data$compact), compact_trace),
    identical(tracemem(data$untouched), untouched_trace),
    dtatools:::.is_unmaterialized_numeric_altrep(data$compact),
    dtatools:::.is_unmaterialized_numeric_altrep(data$generated),
    identical(dta_storage_type(data$generated), "byte"),
    largest_generation_allocation < full_double_bytes
)

integer_generation_values <- seq_len(rows)
direct_float_profile <- profile_memory(
    direct_float <- dta_float(integer_generation_values),
    "dtatools-reference-direct-float-construction-"
)
direct_float_time <- direct_float_profile$elapsed
integer_generation_data <- data.frame(anchor = dta_byte(rep(1, rows)))
integer_generation_data <- reserve_columns(integer_generation_data, n = 1L)
assert_frame(integer_generation_data, 1L)
integer_generation_trace <- tracemem(integer_generation_data$anchor)
integer_generation_profile <- profile_memory(
    gen(integer_generation_data, generated, integer_generation_values),
    "dtatools-reference-integer-generation-"
)
integer_generation_time <- integer_generation_profile$elapsed
largest_integer_generation_allocation <- integer_generation_profile$largest

position_generation_data <- data.frame(anchor = dta_byte(rep(1, rows)))
position_generation_data <- reserve_columns(position_generation_data, n = 1L)
assert_frame(position_generation_data, 1L)
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

compact_generation_values <- dta_byte(rep(2, rows))
compact_generation_data <- data.frame(anchor = dta_byte(rep(1, rows)))
compact_generation_data <- reserve_columns(compact_generation_data, n = 1L)
assert_frame(compact_generation_data, 1L)
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
    integer_generation_time < direct_float_time * 1.35,
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
rm(direct_float)

# This remains the first write after native generation. No capture or warmup.
assert_private(integer_generation_data, 2L)
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
temporal_generation_data <- data.frame(anchor = dta_byte(.size = rows))
temporal_generation_data <- reserve_columns(temporal_generation_data, n = 1L)
assert_frame(temporal_generation_data, 1L)
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
    inherits(temporal_generation_data$generated, "dta_datetime"),
    identical(
        dta_storage_type(temporal_generation_data$generated), "double"
    ),
    largest_temporal_generation_allocation <= full_double_bytes * 1.01,
    total_temporal_generation_allocation < full_double_bytes * 2,
    temporal_generation_time < 0.5
)

character_generation_data <- data.frame(
    anchor = dta_byte(rep(1, rows))
)
character_generation_data <- reserve_columns(character_generation_data, n = 1L)
assert_frame(character_generation_data, 1L)
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

full_character_values <- rep(c("x", "wide"), length.out = rows)
full_character_timing_repetitions <- 5L
full_character_fill_time <- median(vapply(
    seq_len(full_character_timing_repetitions),
    function(iteration) system.time({
        full_character_fill <- full_character_values[]
    })[["elapsed"]],
    double(1)
))
full_character_data <- data.frame(
    anchor = dta_byte(rep(1, rows))
)
full_character_data <- reserve_columns(full_character_data, n = 1L)
assert_frame(full_character_data, 1L)
full_character_profile <- profile_memory(
    gen(full_character_data, generated, .env$full_character_values),
    "dtatools-reference-full-character-generation-"
)
full_character_generation_time <- median(vapply(
    seq_len(full_character_timing_repetitions),
    function(iteration) {
        timed_data <- data.frame(anchor = dta_byte(.size = rows))
        timed_data <- reserve_columns(timed_data, n = 1L)
        assert_frame(timed_data, 1L)
        system.time(
            gen(timed_data, generated, .env$full_character_values)
        )[["elapsed"]]
    },
    double(1)
))
total_full_character_generation_allocation <- full_character_profile$total
largest_full_character_generation_allocation <- full_character_profile$largest
stopifnot(
    identical(
        as.character(full_character_data$generated[c(1L, rows)]),
        full_character_values[c(1L, rows)]
    ),
    identical(
        attr(full_character_data$generated, "stata.string.storage"),
        "str4"
    ),
    largest_full_character_generation_allocation <=
        full_double_bytes * 1.01,
    total_full_character_generation_allocation <
        full_double_bytes * 1.5,
    full_character_generation_time <
        max(0.05, full_character_fill_time * 3.75)
)

sparse_character_data <- data.frame(
    anchor = dta_byte(rep(1, rows))
)
sparse_character_data <- reserve_columns(sparse_character_data, n = 1L)
assert_frame(sparse_character_data, 1L)
sparse_character_profile <- profile_memory(
    gen(sparse_character_data, generated, "wide", where = rows),
    "dtatools-reference-sparse-character-generation-"
)
sparse_character_generation_time <- sparse_character_profile$elapsed
total_sparse_character_generation_allocation <-
    sparse_character_profile$total
largest_sparse_character_generation_allocation <-
    sparse_character_profile$largest
stopifnot(
    identical(
        as.character(sparse_character_data$generated[c(1L, rows)]),
        c("", "wide")
    ),
    identical(
        attr(sparse_character_data$generated, "stata.string.storage"),
        "str4"
    ),
    largest_sparse_character_generation_allocation <=
        full_double_bytes * 1.01,
    total_sparse_character_generation_allocation <
        full_double_bytes * 1.5,
    sparse_character_generation_time <
        character_generation_time + full_character_fill_time * 0.5
)

selected_character_values <- rep(
    c("x", "wide"), length.out = selected_count
)
selected_character_data <- data.frame(
    anchor = dta_byte(rep(1, rows))
)
selected_character_data <- reserve_columns(selected_character_data, n = 1L)
assert_frame(selected_character_data, 1L)
invisible(dtatools:::.reference_row_reads(TRUE))
selected_character_profile <- profile_memory(
    gen(
        selected_character_data, generated,
        .env$selected_character_values, where = selected_rows
    ),
    "dtatools-reference-selected-character-generation-"
)
selected_character_row_reads <- dtatools:::.reference_row_reads(FALSE)
selected_character_generation_time <- selected_character_profile$elapsed
total_selected_character_generation_allocation <-
    selected_character_profile$total
largest_selected_character_generation_allocation <-
    selected_character_profile$largest
stopifnot(
    identical(
        as.character(selected_character_data$generated[c(1L, rows)]),
        c("x", "")
    ),
    identical(
        attr(selected_character_data$generated, "stata.string.storage"),
        "str4"
    ),
    selected_character_row_reads > 0,
    selected_character_row_reads <= as.double(selected_count) * 3,
    largest_selected_character_generation_allocation <=
        full_double_bytes * 1.01,
    total_selected_character_generation_allocation <
        full_double_bytes * 1.5,
    selected_character_generation_time <
        max(0.15, full_character_generation_time * 4)
)

dictionary_path <- tempfile(fileext = ".arrow")
dictionary_cardinality <- min(rows, 250000L)
dictionary_values <- sprintf(
    "value-%06d", seq_len(dictionary_cardinality)
)
save_arrow(data.frame(
    text = rep(dictionary_values, length.out = rows)
), dictionary_path)
dictionary_data <- read_arrow(dictionary_path)
scalar_dictionary_source <- read_arrow(
    dictionary_path, n_max = 1
)$text
unlink(dictionary_path)
stopifnot(dtatools:::.is_unmaterialized_dictstring(dictionary_data$text))
dictionary_alias <- dictionary_data
dictionary_alias$text <- set_var_labels(dictionary_data$text, "Alias")
dictionary_cache_before <- dtatools:::.dictstring_cached_count(
    dictionary_alias$text
)
scalar_dictionary_cache <- dtatools:::.dictstring_cached_count(
    scalar_dictionary_source
)
scalar_dictionary_generation_data <- data.frame(
    anchor = dta_byte(.size = rows)
)
scalar_dictionary_generation_data <- reserve_columns(scalar_dictionary_generation_data, n = 1L)
assert_frame(scalar_dictionary_generation_data, 1L)
scalar_dictionary_generation_profile <- profile_memory(
    gen(
        scalar_dictionary_generation_data, generated,
        .env$scalar_dictionary_source
    ),
    "dtatools-reference-scalar-dictionary-source-generation-"
)
scalar_dictionary_generation_time <-
    scalar_dictionary_generation_profile$elapsed
total_scalar_dictionary_generation_allocation <-
    scalar_dictionary_generation_profile$total
largest_scalar_dictionary_generation_allocation <-
    scalar_dictionary_generation_profile$largest
stopifnot(
    identical(
        dtatools:::.dictstring_cached_count(scalar_dictionary_source),
        scalar_dictionary_cache
    ),
    identical(
        as.character(
            scalar_dictionary_generation_data$generated[c(1L, rows)]
        ),
        rep(dictionary_values[[1L]], 2)
    ),
    largest_scalar_dictionary_generation_allocation <=
        full_double_bytes * 1.01,
    total_scalar_dictionary_generation_allocation <
        full_double_bytes * 1.01,
    scalar_dictionary_generation_time < character_generation_time * 2
)
ordinary_scalar_target <- data.frame(text = rep.int("", rows))
ordinary_scalar_profile <- profile_memory(
    replace_values(
        ordinary_scalar_target, text, dictionary_values[[1L]]
    ),
    "dtatools-reference-ordinary-scalar-character-source-"
)
ordinary_scalar_replacement_time <- ordinary_scalar_profile$elapsed
scalar_dictionary_target <- data.frame(text = rep.int("", rows))
scalar_dictionary_replacement_profile <- profile_memory(
    replace_values(
        scalar_dictionary_target, text,
        .env$scalar_dictionary_source
    ),
    "dtatools-reference-scalar-dictionary-source-replacement-"
)
scalar_dictionary_replacement_time <-
    scalar_dictionary_replacement_profile$elapsed
total_scalar_dictionary_replacement_allocation <-
    scalar_dictionary_replacement_profile$total
largest_scalar_dictionary_replacement_allocation <-
    scalar_dictionary_replacement_profile$largest
stopifnot(
    identical(
        dtatools:::.dictstring_cached_count(scalar_dictionary_source),
        scalar_dictionary_cache
    ),
    identical(
        scalar_dictionary_target$text[c(1L, rows)],
        rep(dictionary_values[[1L]], 2)
    ),
    largest_scalar_dictionary_replacement_allocation <=
        full_double_bytes * 1.01,
    total_scalar_dictionary_replacement_allocation <
        full_double_bytes * 1.01,
    scalar_dictionary_replacement_time <
        ordinary_scalar_replacement_time * 1.75
)
dictionary_generation_data <- data.frame(
    anchor = dta_byte(.size = rows)
)
dictionary_generation_data <- reserve_columns(dictionary_generation_data, n = 1L)
assert_frame(dictionary_generation_data, 1L)
dictionary_generation_profile <- profile_memory(
    gen(
        dictionary_generation_data, generated,
        .env$dictionary_alias$text
    ),
    "dtatools-reference-dictionary-source-generation-"
)
dictionary_generation_time <- dictionary_generation_profile$elapsed
total_dictionary_generation_allocation <-
    dictionary_generation_profile$total
largest_dictionary_generation_allocation <-
    dictionary_generation_profile$largest
stopifnot(
    identical(
        dtatools:::.dictstring_cached_count(dictionary_alias$text),
        dictionary_cache_before
    ),
    identical(
        as.character(dictionary_generation_data$generated[c(1L, rows)]),
        dictionary_values[c(
            1L, ((rows - 1L) %% dictionary_cardinality) + 1L
        )]
    ),
    largest_dictionary_generation_allocation <= full_double_bytes * 1.01,
    total_dictionary_generation_allocation < full_double_bytes * 1.1,
    dictionary_generation_time < full_character_generation_time * 3
)

ordinary_source_target <- data.frame(text = rep.int("", rows))
ordinary_source_profile <- profile_memory(
    replace_values(
        ordinary_source_target, text, .env$full_character_values
    ),
    "dtatools-reference-ordinary-character-source-"
)
ordinary_source_replacement_time <- ordinary_source_profile$elapsed
dictionary_source_target <- data.frame(text = rep.int("", rows))
dictionary_source_profile <- profile_memory(
    replace_values(
        dictionary_source_target, text, .env$dictionary_alias$text
    ),
    "dtatools-reference-full-dictionary-source-"
)
dictionary_source_replacement_time <- dictionary_source_profile$elapsed
total_dictionary_source_allocation <- dictionary_source_profile$total
largest_dictionary_source_allocation <- dictionary_source_profile$largest
stopifnot(
    identical(
        dtatools:::.dictstring_cached_count(dictionary_alias$text),
        dictionary_cache_before
    ),
    identical(
        as.character(dictionary_source_target$text[c(1L, rows)]),
        dictionary_values[c(
            1L, ((rows - 1L) %% dictionary_cardinality) + 1L
        )]
    ),
    largest_dictionary_source_allocation <= full_double_bytes * 1.01,
    total_dictionary_source_allocation < full_double_bytes * 1.1,
    dictionary_source_replacement_time <
        ordinary_source_replacement_time * 3
)
rm(
    scalar_dictionary_generation_data, ordinary_scalar_target,
    scalar_dictionary_target, dictionary_generation_data,
    ordinary_source_target, dictionary_source_target
)

near_unique_rows <- min(rows, 1000000L)
near_unique_values <- sprintf("unique-%07d", seq_len(near_unique_rows))
near_unique_ordinary_data <- data.frame(
    anchor = dta_byte(.size = near_unique_rows)
)
near_unique_ordinary_data <- reserve_columns(near_unique_ordinary_data, n = 1L)
assert_frame(near_unique_ordinary_data, 1L)
near_unique_ordinary_profile <- profile_memory(
    gen(
        near_unique_ordinary_data, generated,
        .env$near_unique_values
    ),
    "dtatools-reference-near-unique-ordinary-generation-"
)
near_unique_ordinary_time <- near_unique_ordinary_profile$elapsed
near_unique_path <- tempfile(fileext = ".arrow")
invisible(callr::r(
    function(path, row_count, library_paths) {
        .libPaths(library_paths)
        library(dtatools)
        values <- sprintf("cold-%07d", seq_len(row_count))
        save_arrow(data.frame(text = values), path)
    },
    args = list(near_unique_path, near_unique_rows, .libPaths()),
    stdout = NULL, stderr = NULL
))
# This target gate has always compared ordinary character values. Select that
# public reader container explicitly now that the default produces a dibble.
near_unique_source <- read_arrow(near_unique_path, output = "tibble")$text
stopifnot(typeof(near_unique_source) == "character", is.null(attributes(near_unique_source)))
unlink(near_unique_path)
stopifnot(dtatools:::.is_unmaterialized_dictstring(near_unique_source))
near_unique_cache <- dtatools:::.dictstring_cached_count(near_unique_source)
near_unique_dictionary_data <- data.frame(
    anchor = dta_byte(.size = near_unique_rows)
)
near_unique_dictionary_data <- reserve_columns(near_unique_dictionary_data, n = 1L)
assert_frame(near_unique_dictionary_data, 1L)
near_unique_dictionary_profile <- profile_memory(
    gen(
        near_unique_dictionary_data, generated,
        .env$near_unique_source
    ),
    "dtatools-reference-near-unique-dictionary-generation-"
)
near_unique_dictionary_time <- near_unique_dictionary_profile$elapsed
total_near_unique_dictionary_allocation <-
    near_unique_dictionary_profile$total
largest_near_unique_dictionary_allocation <-
    near_unique_dictionary_profile$largest
near_unique_result_bytes <- as.double(near_unique_rows) * 8
near_unique_expected <- sprintf(
    "cold-%07d", c(1L, near_unique_rows)
)
stopifnot(
    identical(
        dtatools:::.dictstring_cached_count(near_unique_source),
        near_unique_cache
    ),
    identical(
        as.character(
            near_unique_dictionary_data$generated[c(1L, near_unique_rows)]
        ),
        near_unique_expected
    ),
    largest_near_unique_dictionary_allocation <=
        near_unique_result_bytes * 1.01,
    total_near_unique_dictionary_allocation <
        near_unique_result_bytes * 1.1,
    near_unique_dictionary_time < max(0.1, near_unique_ordinary_time * 8)
)

near_unique_target_bytes <- as.double(near_unique_rows) * 8
direct_sparse_dictionary_target <- copy_data(data.frame(
    text = near_unique_source
))
direct_sparse_dictionary_cache <- dtatools:::.dictstring_cached_count(
    direct_sparse_dictionary_target$text
)
direct_sparse_dictionary_target_profile <- profile_memory(
    replace_values(
        direct_sparse_dictionary_target, text, "changed",
        where = near_unique_rows
    ),
    "dtatools-reference-direct-sparse-dictionary-target-"
)
direct_sparse_dictionary_target_time <-
    direct_sparse_dictionary_target_profile$elapsed
total_direct_sparse_dictionary_target_allocation <-
    direct_sparse_dictionary_target_profile$total
largest_direct_sparse_dictionary_target_allocation <-
    direct_sparse_dictionary_target_profile$largest

shared_sparse_dictionary_target <- copy_data(data.frame(
    text = near_unique_source
))
shared_sparse_dictionary_alias <- shared_sparse_dictionary_target
shared_sparse_dictionary_alias$text <- set_var_labels(
    shared_sparse_dictionary_target$text, "Alias"
)
shared_sparse_dictionary_cache <- dtatools:::.dictstring_cached_count(
    shared_sparse_dictionary_alias$text
)
shared_sparse_dictionary_target_profile <- profile_memory(
    replace_values(
        shared_sparse_dictionary_target, text, "changed",
        where = near_unique_rows
    ),
    "dtatools-reference-shared-sparse-dictionary-target-"
)
shared_sparse_dictionary_target_time <-
    shared_sparse_dictionary_target_profile$elapsed
total_shared_sparse_dictionary_target_allocation <-
    shared_sparse_dictionary_target_profile$total
largest_shared_sparse_dictionary_target_allocation <-
    shared_sparse_dictionary_target_profile$largest
stopifnot(
    identical(
        direct_sparse_dictionary_target$text[c(1L, near_unique_rows)],
        c(near_unique_expected[[1L]], "changed")
    ),
    identical(
        shared_sparse_dictionary_target$text[c(1L, near_unique_rows)],
        c(near_unique_expected[[1L]], "changed")
    ),
    identical(
        dtatools:::.dictstring_cached_count(
            shared_sparse_dictionary_alias$text
        ),
        shared_sparse_dictionary_cache
    ),
    identical(
        as.character(
            shared_sparse_dictionary_alias$text[c(1L, near_unique_rows)]
        ),
        near_unique_expected
    ),
    direct_sparse_dictionary_cache == 0L,
    largest_direct_sparse_dictionary_target_allocation <=
        near_unique_target_bytes * 1.01,
    total_direct_sparse_dictionary_target_allocation <
        near_unique_target_bytes * 1.1,
    largest_shared_sparse_dictionary_target_allocation <=
        near_unique_target_bytes * 1.01,
    total_shared_sparse_dictionary_target_allocation <
        near_unique_target_bytes * 1.1,
    shared_sparse_dictionary_target_time <
        max(0.1, direct_sparse_dictionary_target_time * 1.5)
)
rm(
    near_unique_values, near_unique_ordinary_data,
    near_unique_dictionary_data, direct_sparse_dictionary_target,
    shared_sparse_dictionary_target, shared_sparse_dictionary_alias
)
fill_repetitions <- 5L
character_fill_time <- system.time(
    for (iteration in seq_len(fill_repetitions)) {
        fill_result <- rep.int("changed", rows)
    }
)[["elapsed"]] / fill_repetitions
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
    identical(
        as.character(dictionary_alias$text[c(1L, rows)]),
        dictionary_values[c(
            1L, ((rows - 1L) %% dictionary_cardinality) + 1L
        )]
    ),
    largest_dictionary_replacement_allocation <= full_double_bytes * 1.01,
    total_dictionary_replacement_allocation < full_double_bytes * 1.5,
    dictionary_replacement_time < max(0.03, character_fill_time * 4)
)

sparse_dictionary_data <- data.frame(text = rep.int("", rows))
sparse_dictionary_cache <- dtatools:::.dictstring_cached_count(
    dictionary_alias$text
)
# The RHS handle is fixture setup. Timing starts with the same untouched
# dictionary source; arbitrary expression snapshots are measured separately.
sparse_dictionary_values <- dictionary_alias$text
assert_frame(sparse_dictionary_data)
# R's ordinary character constructor enters shared. Report its first isolation
# capture separately, then measure sparse decoding into that private target.
sparse_dictionary_capture <- profile_memory(
    replace_values(sparse_dictionary_data, text, "", where = 1L),
    "dtatools-capture-sparse-dictionary-target-"
)
record_metric("sparse_dictionary_target_capture_total_profiled_allocation_bytes", sparse_dictionary_capture$total, "%.0f")
record_metric("sparse_dictionary_target_capture_largest_allocation_bytes", sparse_dictionary_capture$largest, "%.0f")
record_metric("sparse_dictionary_target_capture_seconds", sparse_dictionary_capture$elapsed, "%.6f")
stopifnot(typeof(sparse_dictionary_data$text) == "character",
          !native("C_dtatools_mutation_info", sparse_dictionary_data, 1L)$handle_shared)
sparse_dictionary_profile <- profile_memory(
    replace_values(
        sparse_dictionary_data, text, .env$sparse_dictionary_values,
        where = rows
    ),
    "dtatools-reference-sparse-dictionary-source-"
)
sparse_dictionary_replacement_time <- sparse_dictionary_profile$elapsed
total_sparse_dictionary_allocation <- sparse_dictionary_profile$total
largest_sparse_dictionary_allocation <- sparse_dictionary_profile$largest
sparse_dictionary_expected <- dictionary_values[[
    ((rows - 1L) %% dictionary_cardinality) + 1L
]]
stopifnot(
    identical(sparse_dictionary_data$text[[1L]], ""),
    identical(
        sparse_dictionary_data$text[[rows]], sparse_dictionary_expected
    ),
    dtatools:::.is_unmaterialized_dictstring(dictionary_alias$text),
    identical(
        dtatools:::.dictstring_cached_count(dictionary_alias$text),
        sparse_dictionary_cache
    ),
    largest_sparse_dictionary_allocation < 1000000,
    total_sparse_dictionary_allocation < 2000000,
    sparse_dictionary_replacement_time < max(0.02, character_fill_time * 2)
)

integer_fill_time <- system.time(
    for (iteration in seq_len(fill_repetitions)) {
        fill_result <- rep.int(2L, rows)
    }
)[["elapsed"]] / fill_repetitions
generic_altrep_data <- data.frame(value = seq_len(rows))
generic_altrep_alias <- generic_altrep_data
generic_altrep_column_alias <- generic_altrep_data$value
generic_altrep_profile <- profile_memory(
    replace_values(generic_altrep_data, value, 2L),
    "dtatools-reference-generic-altrep-replacement-"
)
generic_altrep_replacement_time <- generic_altrep_profile$elapsed
total_generic_altrep_allocation <- generic_altrep_profile$total
largest_generic_altrep_allocation <- generic_altrep_profile$largest
integer_bytes <- as.double(rows) * 4
stopifnot(
    !dtatools:::.is_altrep(generic_altrep_data$value),
    identical(range(generic_altrep_data$value), c(2L, 2L)),
    identical(generic_altrep_alias$value, generic_altrep_data$value),
    identical(
        range(generic_altrep_column_alias), c(1L, rows)
    ),
    largest_generic_altrep_allocation <= integer_bytes * 1.01,
    total_generic_altrep_allocation < integer_bytes * 1.1
)

sparse_generic_altrep_data <- data.frame(value = seq_len(rows))
sparse_generic_altrep_alias <- sparse_generic_altrep_data
sparse_generic_altrep_column_alias <- sparse_generic_altrep_data$value
sparse_generic_altrep_profile <- profile_memory(
    replace_values(sparse_generic_altrep_data, value, 2L, where = rows),
    "dtatools-reference-sparse-generic-altrep-replacement-"
)
sparse_generic_altrep_replacement_time <-
    sparse_generic_altrep_profile$elapsed
total_sparse_generic_altrep_allocation <-
    sparse_generic_altrep_profile$total
largest_sparse_generic_altrep_allocation <-
    sparse_generic_altrep_profile$largest
stopifnot(
    !dtatools:::.is_altrep(sparse_generic_altrep_data$value),
    identical(
        sparse_generic_altrep_data$value[c(1L, rows)], c(1L, 2L)
    ),
    identical(
        sparse_generic_altrep_alias$value,
        sparse_generic_altrep_data$value
    ),
    identical(
        range(sparse_generic_altrep_column_alias), c(1L, rows)
    ),
    largest_sparse_generic_altrep_allocation <= integer_bytes * 1.01,
    total_sparse_generic_altrep_allocation < integer_bytes * 1.5,
    generic_altrep_replacement_time <
        sparse_generic_altrep_replacement_time * 0.8,
    sparse_generic_altrep_replacement_time <
        max(0.05, integer_fill_time * 20)
)

append_generated_columns <- function(data, count) {
    for (index in seq_len(count)) {
        name <- rlang::sym(sprintf("generated_%03d", index))
        gen(data, !!name, index)
    }
    invisible(data)
}
generation_warmup <- reserve_columns(data.frame(anchor = 1L), n = 5L)
assert_frame(generation_warmup, 5L)
invisible(append_generated_columns(generation_warmup, 5L))
small_repeated_generation_count <- 400L
large_repeated_generation_count <- 1600L
small_generated_data <- data.frame(anchor = 1L)
small_generated_data <- reserve_columns(small_generated_data, n = small_repeated_generation_count)
assert_frame(small_generated_data, small_repeated_generation_count)
small_repeated_generation_profile <- profile_memory(
    append_generated_columns(
        small_generated_data, small_repeated_generation_count
    ),
    "dtatools-reference-small-repeated-generation-"
)
large_generated_data <- data.frame(anchor = 1L)
large_generated_data <- reserve_columns(large_generated_data, n = large_repeated_generation_count)
assert_frame(large_generated_data, large_repeated_generation_count)
large_repeated_generation_profile <- profile_memory(
    append_generated_columns(
        large_generated_data, large_repeated_generation_count
    ),
    "dtatools-reference-large-repeated-generation-"
)
small_repeated_generation_time <- small_repeated_generation_profile$elapsed
large_repeated_generation_time <- large_repeated_generation_profile$elapsed
small_repeated_generation_allocation <-
    small_repeated_generation_profile$total
large_repeated_generation_allocation <-
    large_repeated_generation_profile$total
stopifnot(
    length(small_generated_data) == small_repeated_generation_count + 1L,
    length(large_generated_data) == large_repeated_generation_count + 1L,
    large_repeated_generation_allocation < max(
        500000, small_repeated_generation_allocation * 8
    ),
    large_repeated_generation_time < max(
        0.1, small_repeated_generation_time * 8
    )
)

rm(fill_result)
untracemem(integer_generation_data$anchor)
untracemem(data$compact)
untracemem(data$untouched)

record_metric("rows", rows, "%d")
record_metric("repetitions", repetitions, "%d")
record_metric("dataset_label_replacement_seconds", dataset_label_replacement_time, "%.6f")
record_metric("dataset_label_replacement_total_profiled_allocation_bytes", dataset_label_replacement_allocation, "%.0f")
record_metric("dataset_label_replacement_largest_allocation_bytes", largest_dataset_label_replacement_allocation, "%.0f")
record_metric("small_sparse_replacement_seconds", small_replacement_time, "%.6f")
record_metric("sparse_replacement_seconds", replacement_time, "%.6f")
record_metric("all_rows_scalar_replacement_seconds", all_rows_replacement_time, "%.6f")
record_metric("raw_fill_seconds", raw_fill_time, "%.6f")
record_metric("logical_plan_seconds", logical_plan_time, "%.6f")
record_metric("logical_plan_profiled_allocation_bytes", logical_plan_allocation, "%.0f")
record_metric("all_false_plan_seconds", all_false_plan_time, "%.6f")
record_metric("all_false_plan_profiled_allocation_bytes", all_false_plan_allocation, "%.0f")
record_metric("explicit_plan_seconds", explicit_plan_time, "%.6f")
record_metric("integer_explicit_plan_seconds", integer_explicit_plan_time, "%.6f")
record_metric("explicit_plan_profiled_allocation_bytes", explicit_plan_allocation, "%.0f")
record_metric("integer_vector_replacement_seconds", vector_replacement_time, "%.6f")
record_metric("integer_vector_replacement_largest_allocation_bytes", largest_vector_allocation, "%.0f")
record_metric("position_vector_replacement_seconds", position_vector_replacement_time, "%.6f")
record_metric("position_vector_replacement_largest_allocation_bytes", largest_position_vector_allocation, "%.0f")
record_metric("selected_vector_replacement_seconds", selected_vector_replacement_time, "%.6f")
record_metric("integer_selected_vector_replacement_seconds", integer_selected_time, "%.6f")
record_metric("selected_vector_replacement_largest_allocation_bytes", largest_selected_vector_allocation, "%.0f")
record_metric("selected_position_native_row_reads", selected_position_row_reads, "%.0f")
record_metric("compact_vector_replacement_seconds", compact_vector_replacement_time, "%.6f")
record_metric("compact_vector_replacement_largest_allocation_bytes", largest_compact_vector_allocation, "%.0f")
record_metric("ordinary_sparse_full_values_seconds", ordinary_sparse_time, "%.6f")
record_metric("ordinary_sparse_full_values_total_profiled_allocation_bytes", total_ordinary_sparse_allocation, "%.0f")
record_metric("ordinary_sparse_full_values_largest_allocation_bytes", largest_ordinary_sparse_allocation, "%.0f")
record_metric("late_missing_sparse_seconds", late_missing_time, "%.6f")
record_metric("missing_cycle_seconds", missing_cycle_time, "%.6f")
record_metric("largest_profiled_allocation_bytes", largest_allocation, "%.0f")
record_metric("largest_proxy_allocation_bytes", largest_proxy_allocation, "%.0f")
record_metric("largest_second_proxy_allocation_bytes", largest_second_proxy_allocation, "%.0f")
record_metric("largest_generation_allocation_bytes", largest_generation_allocation, "%.0f")
record_metric("integer_vector_generation_seconds", integer_generation_time, "%.6f")
record_metric("direct_float_construction_seconds", direct_float_time, "%.6f")
record_metric("integer_vector_generation_largest_allocation_bytes", largest_integer_generation_allocation, "%.0f")
record_metric("position_vector_generation_seconds", position_vector_generation_time, "%.6f")
record_metric("position_vector_generation_total_profiled_allocation_bytes", total_position_generation_allocation, "%.0f")
record_metric("position_vector_generation_largest_allocation_bytes", largest_position_generation_allocation, "%.0f")
record_metric("compact_vector_generation_seconds", compact_vector_generation_time, "%.6f")
record_metric("compact_vector_generation_largest_allocation_bytes", largest_compact_generation_allocation, "%.0f")
record_metric("first_generated_patch_largest_allocation_bytes", largest_first_generated_patch_allocation, "%.0f")
record_metric("temporal_generation_seconds", temporal_generation_time, "%.6f")
record_metric("temporal_generation_total_profiled_allocation_bytes", total_temporal_generation_allocation, "%.0f")
record_metric("temporal_generation_largest_allocation_bytes", largest_temporal_generation_allocation, "%.0f")
record_metric("character_generation_seconds", character_generation_time, "%.6f")
record_metric("character_generation_total_profiled_allocation_bytes", total_character_generation_allocation, "%.0f")
record_metric("character_generation_largest_allocation_bytes", largest_character_generation_allocation, "%.0f")
record_metric("full_character_generation_seconds", full_character_generation_time, "%.6f")
record_metric("full_character_fill_seconds", full_character_fill_time, "%.6f")
record_metric("full_character_generation_total_profiled_allocation_bytes", total_full_character_generation_allocation, "%.0f")
record_metric("full_character_generation_largest_allocation_bytes", largest_full_character_generation_allocation, "%.0f")
record_metric("sparse_character_generation_seconds", sparse_character_generation_time, "%.6f")
record_metric("sparse_character_generation_total_profiled_allocation_bytes", total_sparse_character_generation_allocation, "%.0f")
record_metric("sparse_character_generation_largest_allocation_bytes", largest_sparse_character_generation_allocation, "%.0f")
record_metric("selected_character_generation_seconds", selected_character_generation_time, "%.6f")
record_metric("selected_character_generation_native_row_reads", selected_character_row_reads, "%.0f")
record_metric("selected_character_generation_total_profiled_allocation_bytes", total_selected_character_generation_allocation, "%.0f")
record_metric("selected_character_generation_largest_allocation_bytes", largest_selected_character_generation_allocation, "%.0f")
record_metric("dictionary_replacement_seconds", dictionary_replacement_time, "%.6f")
record_metric("character_fill_seconds", character_fill_time, "%.6f")
record_metric("dictionary_replacement_total_profiled_allocation_bytes", total_dictionary_replacement_allocation, "%.0f")
record_metric("dictionary_replacement_largest_allocation_bytes", largest_dictionary_replacement_allocation, "%.0f")
record_metric("dictionary_cardinality", dictionary_cardinality, "%d")
record_metric("dictionary_source_generation_seconds", dictionary_generation_time, "%.6f")
record_metric("scalar_dictionary_source_generation_seconds", scalar_dictionary_generation_time, "%.6f")
record_metric("scalar_dictionary_source_generation_total_profiled_allocation_bytes", total_scalar_dictionary_generation_allocation, "%.0f")
record_metric("scalar_dictionary_source_generation_largest_allocation_bytes", largest_scalar_dictionary_generation_allocation, "%.0f")
record_metric("ordinary_scalar_character_replacement_seconds", ordinary_scalar_replacement_time, "%.6f")
record_metric("scalar_dictionary_source_replacement_seconds", scalar_dictionary_replacement_time, "%.6f")
record_metric("scalar_dictionary_source_replacement_total_profiled_allocation_bytes", total_scalar_dictionary_replacement_allocation, "%.0f")
record_metric("scalar_dictionary_source_replacement_largest_allocation_bytes", largest_scalar_dictionary_replacement_allocation, "%.0f")
record_metric("dictionary_source_generation_total_profiled_allocation_bytes", total_dictionary_generation_allocation, "%.0f")
record_metric("dictionary_source_generation_largest_allocation_bytes", largest_dictionary_generation_allocation, "%.0f")
record_metric("ordinary_character_source_replacement_seconds", ordinary_source_replacement_time, "%.6f")
record_metric("dictionary_source_full_replacement_seconds", dictionary_source_replacement_time, "%.6f")
record_metric("dictionary_source_full_replacement_total_profiled_allocation_bytes", total_dictionary_source_allocation, "%.0f")
record_metric("dictionary_source_full_replacement_largest_allocation_bytes", largest_dictionary_source_allocation, "%.0f")
record_metric("near_unique_ordinary_generation_seconds", near_unique_ordinary_time, "%.6f")
record_metric("near_unique_dictionary_generation_seconds", near_unique_dictionary_time, "%.6f")
record_metric("near_unique_dictionary_generation_total_profiled_allocation_bytes", total_near_unique_dictionary_allocation, "%.0f")
record_metric("near_unique_dictionary_generation_largest_allocation_bytes", largest_near_unique_dictionary_allocation, "%.0f")
record_metric("direct_sparse_dictionary_target_seconds", direct_sparse_dictionary_target_time, "%.6f")
record_metric("direct_sparse_dictionary_target_total_profiled_allocation_bytes", total_direct_sparse_dictionary_target_allocation, "%.0f")
record_metric("direct_sparse_dictionary_target_largest_allocation_bytes", largest_direct_sparse_dictionary_target_allocation, "%.0f")
record_metric("shared_sparse_dictionary_target_seconds", shared_sparse_dictionary_target_time, "%.6f")
record_metric("shared_sparse_dictionary_target_total_profiled_allocation_bytes", total_shared_sparse_dictionary_target_allocation, "%.0f")
record_metric("shared_sparse_dictionary_target_largest_allocation_bytes", largest_shared_sparse_dictionary_target_allocation, "%.0f")
record_metric("sparse_dictionary_source_replacement_seconds", sparse_dictionary_replacement_time, "%.6f")
record_metric("sparse_dictionary_source_total_profiled_allocation_bytes", total_sparse_dictionary_allocation, "%.0f")
record_metric("sparse_dictionary_source_largest_allocation_bytes", largest_sparse_dictionary_allocation, "%.0f")
record_metric("generic_altrep_replacement_seconds", generic_altrep_replacement_time, "%.6f")
record_metric("integer_fill_seconds", integer_fill_time, "%.6f")
record_metric("generic_altrep_replacement_total_profiled_allocation_bytes", total_generic_altrep_allocation, "%.0f")
record_metric("generic_altrep_replacement_largest_allocation_bytes", largest_generic_altrep_allocation, "%.0f")
record_metric("sparse_generic_altrep_replacement_seconds", sparse_generic_altrep_replacement_time, "%.6f")
record_metric("sparse_generic_altrep_total_profiled_allocation_bytes", total_sparse_generic_altrep_allocation, "%.0f")
record_metric("sparse_generic_altrep_largest_allocation_bytes", largest_sparse_generic_altrep_allocation, "%.0f")
record_metric("repeated_generation_small_count", small_repeated_generation_count, "%d")
record_metric("repeated_generation_large_count", large_repeated_generation_count, "%d")
record_metric("repeated_generation_small_seconds", small_repeated_generation_time, "%.6f")
record_metric("repeated_generation_large_seconds", large_repeated_generation_time, "%.6f")
record_metric("repeated_generation_small_total_profiled_allocation_bytes", small_repeated_generation_allocation, "%.0f")
record_metric("repeated_generation_large_total_profiled_allocation_bytes", large_repeated_generation_allocation, "%.0f")
record_metric("compact_byte_bytes", compact_byte_bytes, "%.0f")
record_metric("integer_bytes", integer_bytes, "%.0f")
record_metric("full_double_bytes", full_double_bytes, "%.0f")
record_metric("generation_seconds", generation_time, "%.3f")
record_metric("existing_payload_copy_detected", "false")
emit_metrics(benchmark_metrics, markdown_path)
