#!/usr/bin/env Rscript
# Exact-source paired operation and read measurements for Stage 3.
args <- commandArgs(TRUE)
if (length(args) != 5L) {
    stop("Usage: owned-double.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA baseline|candidate ITERATIONS")
}
source("benchmarks/r-dibble-dplyr/owned-double-helpers.R")
library_path <- owned_benchmark_start(args[[1L]], args[[3L]], args[[4L]])
output <- args[[2L]]
mode <- args[[4L]]
iterations <- as.integer(args[[5L]])
stopifnot(!is.na(iterations), iterations >= 3L, capabilities("profmem"))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
writeLines(owned_runner_identity(args[[3L]], library_path, mode),
           file.path(output, "owned-double-session.txt"))
suppressPackageStartupMessages(library(bench))
records <- list()
after_read_records <- list()
record <- function(family, operation, rows, columns, mark, metrics) {
    result <- cbind(data.frame(family, operation, rows, columns,
                              median_ms = as.numeric(mark$median) * 1000,
                              bench_allocated_bytes = as.numeric(mark$mem_alloc),
                              iterations = mark$n_itr, gc_count = mark$n_gc),
                    as.data.frame(as.list(metrics)))
    records[[length(records) + 1L]] <<- result
    write.csv(do.call(rbind, records), file.path(output, "owned-double.csv"), row.names = FALSE)
    print(result[c("family", "operation", "rows", "median_ms", "r_allocated_bytes")])
    invisible(result)
}

selectors <- list(
    rename = function(data) dplyr::rename(data, changed = c01),
    select = function(data) dplyr::select(data, dplyr::everything()),
    relocate = function(data) dplyr::relocate(data, c01, .after = c16),
    pipeline_five = owned_pipeline
)
for (rows in c(100000L, 1000000L)) {
    data <- owned_fixture(rows)
    frozen <- owned_frozen(data)
    owned_assert_state(data, mode)
    reference <- dtatools:::.reference_snapshot(data)
    for (name in names(selectors)) {
        operation <- selectors[[name]]
        expected <- owned_columns(operation(reference))
        invisible(operation(owned_fixture(4L)))
        profile <- owned_profile(function() operation(data))
        stopifnot(is_dibble(profile$value), identical(owned_columns(profile$value), expected))
        owned_assert_table(profile$value, frozen, expected$names, rows)
        owned_assert_state(profile$value, mode)
        owned_preserved(data, frozen)
        metrics <- profile$metrics
        rm(profile, expected)
        invisible(gc())
        mark <- bench::mark(operation(data), iterations = iterations,
                            check = FALSE, filter_gc = FALSE)
        result <- record("direct", name, rows, 16L, mark, metrics)
        if (mode == "candidate" && name != "pipeline_five") {
            stopifnot(result$r_allocated_bytes < 1000000,
                      result$bench_allocated_bytes < 1000000,
                      result$r_largest_allocation_bytes < rows * 8,
                      result$native_owned_capture_bytes == 0,
                      result$native_mutation_target_copy_bytes == 0)
        }
        rm(mark, result)
        owned_preserved(data, frozen)
        # The comparison uses this exact installation's safe finalizer.
        delegated <- function() dtatools:::.close_dibble(
            data, operation(dtatools:::.reference_snapshot(data)))
        invisible(delegated())
        profile <- owned_profile(delegated)
        stopifnot(is_dibble(profile$value),
                  identical(owned_columns(profile$value), owned_columns(operation(reference))))
        owned_assert_table(profile$value, frozen, names(operation(reference)), rows)
        metrics <- profile$metrics
        rm(profile)
        invisible(gc())
        mark <- bench::mark(delegated(), iterations = iterations,
                            check = FALSE, filter_gc = FALSE)
        record("safe_delegation", name, rows, 16L, mark, metrics)
        rm(mark)
        owned_preserved(data, frozen)
    }
    rm(data, frozen, reference)
    invisible(gc())
}

# These profiles measure one write per prepared fixture. Repeating a first-write
# expression on the same table would silently turn it into a private-write test.
write_records <- list()
for (rows in c(100000L, 1000000L)) {
    for (case in c("shared_sparse", "private_sparse", "full_replacement")) {
        data <- owned_fixture(rows)
        frozen <- owned_frozen(data)
        result <- dplyr::rename(data, changed = c01)
        if (case == "private_sparse") {
            dtatools::replace_values(result, changed, 1.0, where = 1L)
            if (mode == "candidate") {
                state <- owned_native("C_dtatools_mutation_info", result, 1L)
                stopifnot(!state$handle_shared, state$backing_private, !state$exposed)
            }
        }
        before <- owned_state(result)
        result_names <- names(result)
        profile <- owned_profile(function() {
            if (case == "full_replacement") dtatools::replace_values(result, changed, 9.5)
            else dtatools::replace_values(result, changed, 9.5, where = 1L)
        })
        after <- owned_state(result)
        owned_preserved(data, frozen)
        owned_assert_table(result, frozen, result_names, rows)
        expected <- rep(1 + c(0, 0.5, 0.25, 1), length.out = rows)
        if (case == "full_replacement") expected[] <- 9.5 else expected[1L] <- 9.5
        stopifnot(identical(as.double(result$changed), expected),
                  identical(column_values(result)[-1L], unserialize(frozen)$columns$values[-1L]))
        if (mode == "candidate") {
            stopifnot(identical(vapply(before[-1L], `[[`, "", "backing"),
                                vapply(after[-1L], `[[`, "", "backing")))
            if (case == "shared_sparse") {
                stopifnot(profile$metrics[["native_mutation_target_copy_bytes"]] == rows * 8)
            } else {
                stopifnot(profile$metrics[["native_mutation_target_copy_bytes"]] == 0)
            }
            if (case == "full_replacement") {
                stopifnot(profile$metrics[["native_old_journal_bytes"]] == 0)
            }
        }
        write_records[[length(write_records) + 1L]] <- cbind(
            data.frame(rows, operation = case), as.data.frame(as.list(profile$metrics)))
        write.csv(do.call(rbind, write_records), file.path(output, "owned-double-writes.csv"),
                  row.names = FALSE)
        rm(data, frozen, result, before, after, profile, expected)
        invisible(gc())
    }
}

# Read workloads use the same finite typed values in both installed revisions.
# Fixtures, file creation, method warming, and checks are outside timed calls.
for (rows in c(100000L, 1000000L)) {
    data <- owned_fixture(rows, 8L)
    frozen <- owned_frozen(data)
    owned_assert_state(data, mode)
    reference <- dtatools:::.reference_snapshot(data)
    input_path <- tempfile(fileext = ".dta")
    output_path <- tempfile(fileext = ".dta")
    input_arrow <- tempfile(fileext = ".arrow")
    output_arrow <- tempfile(fileext = ".arrow")
    save_dta(data, input_path)
    save_arrow(data, input_arrow, compression = "uncompressed", threads = 1L)
    reads <- list(
        sum = function(x) sum(x$c01),
        mean = function(x) mean(x$c01),
        range = function(x) range(x$c01),
        coercion_double = function(x) as.double(x$c01),
        coercion_integer = function(x) as.integer(x$c01),
        export_data_frame = function(x) as.data.frame(x),
        export_tibble = function(x) tibble::as_tibble(x),
        arithmetic = function(x) x$c01 + 0.5,
        mutate_arithmetic = function(x) dplyr::mutate(x, c01 = c01 + 0.5),
        filter_half = function(x) dplyr::filter(x, c01 > 1.3),
        row_subset = function(x) x[seq.int(1L, nrow(x), by = 2L), ],
        read_dta = function(x) read_dta(input_path),
        write_dta = function(x) { save_dta(x, output_path); invisible(NULL) },
        read_arrow = function(x) read_arrow(input_arrow, threads = 1L),
        write_arrow = function(x) {
            save_arrow(x, output_arrow, compression = "uncompressed", threads = 1L)
            invisible(NULL)
        }
    )
    for (name in names(reads)) {
        operation <- reads[[name]]
        actual <- operation(data)
        if (name %in% c("read_dta", "read_arrow")) {
            # The frozen deterministic fixture is independent of reader output.
            # It declares the default display format that file readers restore.
            owned_assert_roundtrip(actual, frozen)
        } else if (name %in% c("write_dta", "write_arrow")) {
            stopifnot(is.null(actual))
        } else {
            expected <- operation(reference)
            if (is.data.frame(actual)) {
                stopifnot(identical(owned_columns(actual), owned_columns(expected)))
                export <- name %in% c("export_data_frame", "export_tibble")
                if (!export) stopifnot(is_dibble(actual))
                owned_assert_table(actual, frozen, names(expected), nrow(expected),
                                   classes = if (export) class(expected) else NULL)
            } else stopifnot(identical(actual, expected))
            rm(expected)
        }
        rm(actual)
        if (name == "write_dta") {
            owned_assert_roundtrip(read_dta(output_path), frozen)
        }
        if (name == "write_arrow") {
            owned_assert_roundtrip(read_arrow(output_arrow, threads = 1L), frozen)
        }
        profile <- owned_profile(function() operation(data))
        metrics <- profile$metrics
        rm(profile)
        invisible(gc())
        mark <- bench::mark(operation(data), iterations = iterations,
                            check = FALSE, filter_gc = FALSE)
        record("read", name, rows, 8L, mark, metrics)
        rm(mark)
        owned_preserved(data, frozen)
        owned_assert_state(data, mode)
        # A read or public export must not make a later selector copy values.
        input_info <- owned_state(data)
        fork <- owned_profile(function() dplyr::rename(data, changed = c01))
        owned_assert_table(fork$value, frozen, c("changed", names(data)[-1L]), rows)
        expected_fork <- owned_expected_columns(frozen)
        expected_fork$names[1L] <- "changed"
        stopifnot(identical(owned_columns(fork$value), expected_fork))
        rm(expected_fork)
        owned_assert_state(fork$value, mode)
        if (mode == "candidate") {
            output_info <- owned_state(fork$value)
            stopifnot(identical(vapply(input_info, `[[`, "", "backing"),
                                vapply(output_info, `[[`, "", "backing")),
                      fork$metrics[["native_owned_capture_bytes"]] == 0,
                      fork$metrics[["native_mutation_target_copy_bytes"]] == 0,
                      fork$metrics[["r_allocated_bytes"]] < 1000000)
            rm(output_info)
        }
        after_read_records[[length(after_read_records) + 1L]] <- cbind(
            data.frame(rows, after_operation = name), as.data.frame(as.list(fork$metrics)))
        write.csv(do.call(rbind, after_read_records), file.path(output, "owned-after-read.csv"),
                  row.names = FALSE)
        rm(fork, input_info)
        owned_preserved(data, frozen)
    }
    unlink(c(input_path, output_path, input_arrow, output_arrow))
    rm(data, frozen, reference)
    invisible(gc())
}

# Deliberately retain an unread mutation environment. A nested arbitrary RHS
# must freeze its input before later explicit writes, even at a full-column cost.
# The native runner measures a separately acquired literal .env member instead.
for (rows in c(100000L, 1000000L)) {
    data <- dibble(text = dta_string(rep("aa", rows), "str2"))
    dtatools::replace_values(data, text, "aa", where = 1L)
    source_values <- dta_string(rep("bb", rows), "str2")
    holder <- list(values = source_values)
    captured <- new.env(parent = emptyenv())
    profile <- owned_profile(function() {
        dtatools::replace_values(data, text, {
            assign("mask", environment(), envir = .env$captured)
            .env$holder$values
        }, where = 1L)
    })
    stopifnot(identical(eval(quote(text[1L]), captured$mask), dta_string("aa", "str2")),
              identical(as.character(data$text[1L]), "bb"))
    dtatools::replace_values(data, text, "cc", where = 2L)
    stopifnot(identical(as.character(eval(quote(text[1:2]), captured$mask)), c("aa", "aa")),
              identical(as.character(data$text[1:2]), c("bb", "cc")))
    write.csv(cbind(data.frame(rows, operation = "captured_nested_string_rhs"),
                    as.data.frame(as.list(profile$metrics))),
              file.path(output, paste0("snapshot-cost-", rows, ".csv")), row.names = FALSE)
    rm(data, source_values, holder, captured, profile)
    invisible(gc())

    data <- dibble(x = dta_byte(rep(0L, rows)))
    dtatools::replace_values(data, x, 0L, where = 1L)
    if (mode == "candidate") {
        state <- owned_native("C_dtatools_mutation_info", data, 1L)
        stopifnot(!state$handle_shared, state$backing_private, !state$exposed)
    }
    profile <- owned_profile(function() dtatools::replace_values(data, x, 1L, where = rows - 1L))
    stopifnot(identical(as.double(data$x[c(rows - 1L, rows)]), c(1, 0)))
    write.csv(cbind(data.frame(rows, operation = "arithmetic_where"),
                    as.data.frame(as.list(profile$metrics))),
              file.path(output, paste0("arithmetic-where-cost-", rows, ".csv")), row.names = FALSE)
    rm(data, profile)
    invisible(gc())
}
cat("All", mode, "operation, source preservation and captured-mask checks passed.\n")
if (mode == "candidate") cat("Candidate owned allocation and backing checks passed.\n")
