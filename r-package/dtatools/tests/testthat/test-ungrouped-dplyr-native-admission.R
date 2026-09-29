test_that("ungrouped native mutate isolates five outputs and honors public fallback", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    native_expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("ungrouped-dplyr-native-clean-session", function(native_expected) {
        library(dtatools)
        library(dplyr)
        options(dtatools.generate_type = "double")
        stopifnot(identical(isTRUE(dtatools:::.ungrouped_mutate_state$pinned),
                            native_expected))
        probe <- function(name, ...) {
            .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
        }
        make <- function() {
            values <- setNames(lapply(seq_len(8L), function(i)
                rep(as.double(i), 41L)), paste0("field_", seq_len(8L)))
            values[[6L]] <- rep(c(-3, 1, 7), length.out = 41L)
            data <- as_dibble(tibble::as_tibble(values))
            probe("C_dtatools_patch_slot", data, 6L, NULL,
                  values[[6L]], TRUE)
            data
        }
        same <- function(actual, expected) {
            stopifnot(identical(names(actual), names(expected)),
                      identical(class(actual), class(expected)),
                      identical(attr(actual, "row.names"),
                                attr(expected, "row.names")))
            for (name in names(actual))
                stopifnot(identical(as.double(actual[[name]]),
                                    as.double(expected[[name]])),
                          identical(attributes(actual[[name]]),
                                    attributes(expected[[name]])))
            invisible(TRUE)
        }
        five <- function(data) dplyr::mutate(data,
            north = field_6 + 1.75, south = field_6 + 1.75,
            east = field_6 + 1.75, west = field_6 + 1.75,
            center = field_6 + 1.75)
        run <- function(enabled, action) {
            probe("C_dtatools_probe_mutate_mode", enabled)
            probe("C_dtatools_probe_dplyr_early_stats", TRUE)
            data <- make()
            result <- action(data)
            list(data = data, result = result,
                 counts = as.integer(probe(
                     "C_dtatools_probe_dplyr_early_stats", FALSE)))
        }

        ordinary <- run(FALSE, five)
        native <- run(TRUE, five)
        same(native$result, ordinary$result)
        stopifnot(identical(native$counts, if (native_expected)
                          c(1L, 1L, 1L) else integer(3L)),
                  identical(names(native$data), paste0("field_", seq_len(8L))),
                  identical(as.double(native$data$field_6),
                            rep(c(-3, 1, 7), length.out = 41L)))
        data.table::set(native$result, i = 1L, j = "north", value = 99.0)
        stopifnot(identical(as.double(native$result$north[[1L]]), 99),
                  identical(as.double(native$result$south[[1L]]), -1.25),
                  identical(as.double(native$result$east[[1L]]), -1.25),
                  identical(as.double(native$result$west[[1L]]), -1.25),
                  identical(as.double(native$result$center[[1L]]), -1.25),
                  identical(as.double(native$data$field_6[[1L]]), -3))
        data.table::set(native$result, i = 2L, j = "field_6", value = 333.0)
        stopifnot(identical(as.double(native$result$field_6[[2L]]), 333),
                  identical(as.double(native$data$field_6[[2L]]), 1))

        old_option <- getOption("dtatools.alloccol")
        options(dtatools.alloccol = 0L)
        zero_ordinary <- run(FALSE, function(data)
            dplyr::mutate(data, extra = field_6 + 1.75))
        zero_native <- run(TRUE, function(data)
            dplyr::mutate(data, extra = field_6 + 1.75))
        same(zero_native$result, zero_ordinary$result)
        stopifnot(identical(zero_native$counts, if (native_expected)
                          c(1L, 0L, 0L) else integer(3L)))

        options(dtatools.alloccol = -1L)
        invalid <- function(enabled) {
            probe("C_dtatools_probe_mutate_mode", enabled)
            probe("C_dtatools_probe_dplyr_early_stats", TRUE)
            outcome <- tryCatch(dplyr::mutate(make(), extra = field_6 + 1.75),
                                error = conditionMessage)
            list(outcome = outcome,
                 counts = as.integer(probe(
                     "C_dtatools_probe_dplyr_early_stats", FALSE)))
        }
        invalid_ordinary <- invalid(FALSE)
        invalid_native <- invalid(TRUE)
        stopifnot(is.character(invalid_native$outcome),
                  identical(invalid_native$outcome, invalid_ordinary$outcome),
                  identical(invalid_native$counts[[3L]], 0L))
        options(dtatools.alloccol = old_option)

        callbacks <- new.env(parent = emptyenv())
        callbacks$hits <- 0L
        trace("enquos", where = asNamespace("rlang"),
              tracer = function() callbacks$hits <- callbacks$hits + 1L,
              print = FALSE)
        traced <- function(enabled) {
            probe("C_dtatools_probe_mutate_mode", enabled)
            probe("C_dtatools_probe_dplyr_early_stats", TRUE)
            data <- make()
            callbacks$hits <- 0L
            result <- dplyr::mutate(data, extra = field_6 + 1.75)
            list(result = result, hits = callbacks$hits,
                 counts = as.integer(probe(
                     "C_dtatools_probe_dplyr_early_stats", FALSE)))
        }
        traced_ordinary <- traced(FALSE)
        traced_native <- traced(TRUE)
        untrace("enquos", where = asNamespace("rlang"))
        same(traced_native$result, traced_ordinary$result)
        stopifnot(traced_native$hits > 0L,
                  identical(traced_native$hits, traced_ordinary$hits),
                  identical(traced_native$counts[[3L]], 0L))
        list(positive = native$counts, zero = zero_native$counts,
             invalid = invalid_native$counts,
             traced = traced_native$counts,
             callbacks = traced_native$hits)
    }, args = list(native_expected = native_expected), libpath = .libPaths())
    expect_identical(observed$positive, if (native_expected)
                     c(1L, 1L, 1L) else integer(3L))
    expect_identical(observed$zero, if (native_expected)
                     c(1L, 0L, 0L) else integer(3L))
    expect_identical(observed$invalid[[3L]], 0L)
    expect_identical(observed$traced[[3L]], 0L)
    expect_gt(observed$callbacks, 0L)
})
