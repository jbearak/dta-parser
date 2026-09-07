#!/usr/bin/env Rscript
# Each invocation runs all Stage 4 operation cases for one exact installation.
args <- commandArgs(TRUE)
if (length(args) != 5L) stop(
    "Usage: owned-atomic.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA baseline|candidate ITERATIONS")
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], args[[4L]])
output <- args[[2L]]
mode <- args[[4L]]
iterations <- as.integer(args[[5L]])
stopifnot(!is.na(iterations), iterations >= 3L, capabilities("profmem"), dir.exists(output))
stopifnot(!any(file.exists(file.path(output, c("owned-atomic-session.txt",
    "owned-atomic.csv", "owned-atomic-after-read.csv", "owned-atomic-writes.csv")))))
writeLines(atomic_identity(args[[3L]], library_path, mode),
           file.path(output, "owned-atomic-session.txt"))
suppressPackageStartupMessages(library(bench))
records <- after_read_records <- write_records <- list()
record <- function(kind, family, operation, rows, columns, mark, metrics) {
    result <- cbind(data.frame(kind, family, operation, rows, columns,
        median_ms = as.numeric(mark$median) * 1000,
        bench_allocated_bytes = as.numeric(mark$mem_alloc),
        iterations = mark$n_itr, gc_count = mark$n_gc), as.data.frame(as.list(metrics)))
    records[[length(records) + 1L]] <<- result
    write.csv(do.call(rbind, records), file.path(output, "owned-atomic.csv"), row.names = FALSE)
    print(result[c("kind", "family", "operation", "rows", "median_ms", "r_allocated_bytes",
                   "validation_scanned_values")])
    invisible(result)
}

selectors <- list(
    rename = function(data) dplyr::rename(data, changed = c01),
    select = function(data) dplyr::select(data, dplyr::everything()),
    relocate = function(data) dplyr::relocate(data, c01, .after = c16),
    pipeline_five = owned_pipeline)

for (kind in atomic_kinds) for (rows in c(100000L, 1000000L)) {
    data <- atomic_fixture(kind, rows)
    frozen <- atomic_frozen(data, kind)
    before <- atomic_state(data, mode)
    for (name in names(selectors)) {
        operation <- selectors[[name]]
        expected <- atomic_pipeline_expected(frozen, name)
        invisible(operation(atomic_fixture(kind, 4L)))
        profile <- atomic_profile(function() operation(data))
        atomic_check(profile$value, frozen, expected)
        result_state <- atomic_state(profile$value, mode)
        atomic_unchanged_backings(before, data, mode)
        if (mode == "candidate") {
            indices <- switch(name, relocate = c(2:16, 1L), pipeline_five = c(2:16, 2L), seq_len(16L))
            stopifnot(identical(atomic_backings(result_state), atomic_backings(before[indices])))
        }
        metrics <- profile$metrics
        rm(profile, result_state)
        invisible(gc())
        scans_before <- atomic_scans()
        mark <- bench::mark(operation(data), iterations = iterations, check = TRUE, filter_gc = FALSE)
        atomic_check(mark$result[[1L]], frozen, expected)
        scans_after <- atomic_scans()
        result <- record(kind, "direct", name, rows, 16L, mark, metrics)
        if (name != "pipeline_five") {
            atomic_selector_gate(metrics, kind, mode)
            if (mode == "candidate") stopifnot(result$bench_allocated_bytes < 1000000,
                identical(scans_before, scans_after))
        }
        rm(mark, result)
        atomic_preserved(data, frozen)
        atomic_unchanged_backings(before, data, mode)
        delegated <- function() dtatools:::.close_dibble(
            data, operation(dtatools:::.reference_snapshot(data)))
        invisible(delegated())
        profile <- atomic_profile(delegated)
        atomic_check(profile$value, frozen, expected)
        atomic_state(profile$value, mode)
        metrics <- profile$metrics
        rm(profile)
        invisible(gc())
        mark <- bench::mark(delegated(), iterations = iterations, check = TRUE, filter_gc = FALSE)
        atomic_check(mark$result[[1L]], frozen, expected)
        record(kind, "safe_delegation", name, rows, 16L, mark, metrics)
        rm(mark)
        atomic_preserved(data, frozen)
        atomic_unchanged_backings(before, data, mode)
    }
    rm(data, frozen, before, expected, delegated)
    invisible(gc())
}

# Each first write gets a fresh table. Repeating it on an already changed table
# would measure subsequent private writes instead of detaching a shared column.
for (kind in c("string", "declared_character", "logical")) {
    for (rows in c(100000L, 1000000L)) for (case in c("shared_sparse", "private_sparse", "full_replacement")) {
        data <- atomic_fixture(kind, rows)
        frozen <- atomic_frozen(data, kind)
        result <- dplyr::rename(data, changed = c01)
        replacement <- if (kind == "logical") FALSE else "changed"
        if (case == "private_sparse") {
            dtatools::replace_values(result, changed, .env$replacement, where = 1L)
            if (mode == "candidate") {
                info <- owned_native("C_dtatools_mutation_info", result, 1L)
                stopifnot(!info$handle_shared, info$backing_private, !info$exposed)
            }
        }
        before <- owned_state(result)
        write_row <- if (case == "private_sparse") 3L else 1L
        profile <- atomic_profile(function() {
            if (case == "full_replacement") dtatools::replace_values(result, changed, .env$replacement)
            else dtatools::replace_values(result, changed, .env$replacement, where = .env$write_row)
        })
        after <- owned_state(result)
        expected <- atomic_pipeline_expected(frozen, "rename")
        if (case == "full_replacement") expected$values[[1L]][] <- replacement
        else expected$values[[1L]][write_row] <- replacement
        if (case == "private_sparse") expected$values[[1L]][1L] <- replacement
        atomic_check(result, frozen, expected)
        atomic_preserved(data, frozen)
        if (mode == "candidate") {
            stopifnot(identical(atomic_backings(before[-1L]), atomic_backings(after[-1L])))
            copied <- if (case == "shared_sparse") rows * if (kind == "logical") 4 else .Machine$sizeof.pointer else 0
            stopifnot(profile$metrics[["native_mutation_target_copy_bytes"]] == copied)
            if (case == "full_replacement") stopifnot(profile$metrics[["native_old_journal_bytes"]] == 0)
        }
        write_records[[length(write_records) + 1L]] <- cbind(
            data.frame(kind, rows, operation = case), as.data.frame(as.list(profile$metrics)))
        write.csv(do.call(rbind, write_records), file.path(output, "owned-atomic-writes.csv"), row.names = FALSE)
        # Now write the source while the changed result survives. This is outside
        # measurement, and guards the reverse direction of result isolation.
        dtatools::replace_values(data, c01, .env$replacement, where = 4L)
        atomic_check(result, frozen, expected)
        source_expected <- atomic_expected(frozen)
        source_expected$values[[1L]][4L] <- replacement
        atomic_check(data, frozen, source_expected)
        rm(data, frozen, result, before, after, profile, expected, source_expected)
        invisible(gc())
    }
}

for (kind in atomic_kinds) for (rows in c(100000L, 1000000L)) {
    data <- atomic_fixture(kind, rows, 8L)
    frozen <- atomic_frozen(data, kind)
    reference <- tibble::new_tibble(atomic_raw(kind, rows, 8L), nrow = rows)
    input_path <- tempfile(fileext = ".dta")
    output_path <- tempfile(fileext = ".dta")
    input_arrow <- tempfile(fileext = ".arrow")
    output_arrow <- tempfile(fileext = ".arrow")
    setup_before <- atomic_state(data, mode)
    atomic_write_dta(data, input_path, kind)
    save_arrow(data, input_arrow, compression = "uncompressed", threads = 1L)
    atomic_unchanged_backings(setup_before, data, mode)
    reads <- list(
        any_na = function(x) anyNA(x$c01),
        nonmissing_count = function(x) sum(!is.na(x$c01)),
        coercion_character = function(x) as.character(x$c01),
        export_data_frame = function(x) as.data.frame(x),
        export_tibble = function(x) tibble::as_tibble(x),
        filter_half = function(x) dplyr::filter(x, seq_len(n()) %% 2L == 0L),
        row_subset = function(x) x[seq.int(1L, nrow(x), by = 2L), ],
        read_dta = function(x) read_dta(input_path),
        write_dta = function(x) atomic_write_dta(x, output_path, kind),
        read_arrow = function(x) read_arrow(input_arrow, threads = 1L),
        write_arrow = function(x) {
            save_arrow(x, output_arrow, compression = "uncompressed", threads = 1L)
            invisible(NULL)
        })
    if (kind %in% c("string", "declared_character")) reads$byte_width <- function(x) nchar(as.character(x$c01), type = "bytes")
    if (kind %in% c("logical", "factor", "ordered")) reads$coercion_integer <- function(x) as.integer(x$c01)
    if (kind == "logical") {
        reads$sum <- function(x) sum(x$c01, na.rm = TRUE)
        reads$mean <- function(x) mean(x$c01, na.rm = TRUE)
    }
    if (kind == "ordered") reads$range <- function(x) range(x$c01, na.rm = TRUE)
    for (name in names(reads)) {
        operation <- reads[[name]]
        check_read <- function(value) {
            if (name %in% c("read_dta", "read_arrow")) {
                expected <- atomic_io_expected(kind, rows, 8L, sub("read_", "", name))
                atomic_check(value, frozen, expected)
            } else if (name %in% c("write_dta", "write_arrow")) {
                stopifnot(is.null(value))
                format <- sub("write_", "", name)
                roundtrip <- if (format == "dta") read_dta(output_path) else read_arrow(output_arrow, threads = 1L)
                atomic_check(roundtrip, frozen, atomic_io_expected(kind, rows, 8L, format))
            } else if (name %in% c("export_data_frame", "export_tibble", "filter_half", "row_subset")) {
                indices <- if (name == "filter_half") seq.int(2L, rows, by = 2L) else
                    if (name == "row_subset") seq.int(1L, rows, by = 2L) else NULL
                expected <- atomic_expected(frozen, rows = indices)
                classes <- switch(name, export_data_frame = "data.frame",
                                  export_tibble = c("tbl_df", "tbl", "data.frame"), NULL)
                atomic_check(value, frozen, expected, classes = classes)
            } else {
                expected <- operation(reference)
                stopifnot(identical(value, expected))
            }
            invisible(NULL)
        }
        before <- atomic_state(data, mode)
        actual <- operation(data)
        atomic_unchanged_backings(before, data, mode)
        check_read(actual)
        # Keep the first returned result alive across profiling, timing and the
        # post-read selector. Inspect source backing before and after each phase.
        before_profile <- atomic_state(data, mode)
        profile <- atomic_profile(function() operation(data))
        atomic_unchanged_backings(before_profile, data, mode)
        check_read(profile$value)
        metrics <- profile$metrics
        invisible(gc())
        before_timing <- atomic_state(data, mode)
        mark <- bench::mark(operation(data), iterations = iterations, check = TRUE, filter_gc = FALSE)
        atomic_unchanged_backings(before_timing, data, mode)
        check_read(mark$result[[1L]])
        # For writes this reopens the final timed output, independently of the
        # earlier warm-up and profiled files. All checks are outside timing.
        record(kind, "read", name, rows, 8L, mark, metrics)
        atomic_preserved(data, frozen)
        fork_before <- atomic_state(data, mode)
        fork <- atomic_profile(function() dplyr::rename(data, changed = c01))
        expected_fork <- atomic_expected(frozen, names = c("changed", names(data)[-1L]))
        atomic_check(fork$value, frozen, expected_fork)
        output_info <- atomic_state(fork$value, mode)
        atomic_unchanged_backings(fork_before, data, mode)
        if (mode == "candidate") stopifnot(identical(atomic_backings(fork_before), atomic_backings(output_info)))
        atomic_selector_gate(fork$metrics, kind, mode)
        after_read_records[[length(after_read_records) + 1L]] <- cbind(
            data.frame(kind, rows, after_operation = name), as.data.frame(as.list(fork$metrics)))
        write.csv(do.call(rbind, after_read_records), file.path(output, "owned-atomic-after-read.csv"), row.names = FALSE)
        rm(actual, profile, mark, fork, expected_fork, output_info)
    }
    unlink(c(input_path, output_path, input_arrow, output_arrow))
    rm(data, frozen, reference)
    invisible(gc())
}
validate_benchmark_install(library_path, args[[3L]])
cat("All", mode, "atomic operation, value, metadata, alias, backing and scan checks passed.\n")
