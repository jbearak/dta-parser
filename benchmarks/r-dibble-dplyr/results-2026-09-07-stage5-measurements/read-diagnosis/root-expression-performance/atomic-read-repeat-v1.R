#!/usr/bin/env Rscript
# Bounded diagnosis derived from the unchanged atomic read loop. No production source changes.
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
    saveRDS(list(median_ms = as.numeric(mark$median) * 1000, samples = mark$time,
        allocation = mark$mem_alloc, iterations = mark$n_itr, gc_count = mark$n_gc),
        file.path(output, paste0("raw-timing-", length(records) + 1L, ".rds")))
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

case_set <- Sys.getenv("DTA_ATOMIC_REPEAT_CASES")
stopifnot(case_set %in% c("reads_repeat", "reads_minimum", "arrow_repeat"), iterations == 7L)
selected <- list(declared_character = c("any_na", "nonmissing_count"),
    logical = c("nonmissing_count", "coercion_character", "coercion_integer", "mean"),
    factor = c("any_na", "nonmissing_count", "coercion_character"),
    ordered = c("any_na", "nonmissing_count", "coercion_character"))
if (case_set == "arrow_repeat") selected <- list(logical = "write_arrow")
row_counts <- switch(case_set, reads_repeat = c(100000L, 1000000L),
    reads_minimum = 1000000L, arrow_repeat = 100000L)
columns <- if (case_set == "reads_minimum") 1L else 8L
expected_count <- switch(case_set, reads_repeat = 24L, reads_minimum = 12L, arrow_repeat = 1L)
options(warn = 2)
for (kind in names(selected)) for (rows in row_counts) {
    data <- atomic_fixture(kind, rows, columns)
    frozen <- atomic_frozen(data, kind)
    reference <- tibble::new_tibble(atomic_raw(kind, rows, columns), nrow = rows)
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
    stopifnot(all(selected[[kind]] %in% names(reads)))
    for (name in selected[[kind]]) {
        operation <- reads[[name]]
        check_read <- function(value) {
            if (name %in% c("read_dta", "read_arrow")) {
                expected <- atomic_io_expected(kind, rows, columns, sub("read_", "", name))
                atomic_check(value, frozen, expected)
            } else if (name %in% c("write_dta", "write_arrow")) {
                stopifnot(is.null(value))
                format <- sub("write_", "", name)
                roundtrip <- if (format == "dta") read_dta(output_path) else read_arrow(output_arrow, threads = 1L)
                atomic_check(roundtrip, frozen, atomic_io_expected(kind, rows, columns, format))
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
        saveRDS(list(before = before, before_profile = before_profile, before_timing = before_timing),
            file.path(output, paste0("source-states-", length(records) + 1L, ".rds")))
        mark <- bench::mark(operation(data), iterations = iterations, check = TRUE, filter_gc = FALSE)
        atomic_unchanged_backings(before_timing, data, mode)
        check_read(mark$result[[1L]])
        # For writes this reopens the final timed output, independently of the
        # earlier warm-up and profiled files. All checks are outside timing.
        record(kind, "read", name, rows, columns, mark, metrics)
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
stopifnot(length(records) == expected_count)
validate_benchmark_install(library_path, args[[3L]])
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("PASS", expected_count, mode, case_set, "bounded read cases\n")
