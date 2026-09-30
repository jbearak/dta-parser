test_that("native replacement admits an unfamiliar column and preserves public fallback", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    native_expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("repl-native-clean-session", function(native_expected) {
        library(dtatools)
        probe <- function(name, ...) {
            .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
        }
        make <- function() {
            values <- setNames(lapply(seq_len(9L), function(i)
                rep(as.double(i), 41L)), paste0("field_", seq_len(9L)))
            values[[6L]] <- rep(c(-3, 1, 7), length.out = 41L)
            data <- as_dibble(tibble::as_tibble(values))
            probe("C_dtatools_patch_slot", data, 6L, NULL,
                  values[[6L]], TRUE)
            data
        }
        run <- function(enabled, events = NULL) {
            probe("C_dtatools_probe_unique_repl_mode", as.integer(enabled))
            probe("C_dtatools_probe_unique_repl_stats", TRUE)
            data <- make()
            if (!is.null(events)) events$hits <- 0L
            repl(data, field_6 = field_6 + 1.75)
            list(data = data,
                 counts = as.integer(probe("C_dtatools_probe_unique_repl_stats", FALSE)),
                 hits = if (is.null(events)) NULL else events$hits)
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
        }

        ordinary <- run(FALSE)
        native <- run(TRUE)
        same(native$data, ordinary$data)
        stopifnot(identical(native$counts[[1L]], as.integer(native_expected)),
                  identical(native$counts[[6L]], as.integer(native_expected)),
                  identical(as.double(native$data$field_6[1:3]),
                            c(-1.25, 2.75, 8.75)),
                  identical(as.double(native$data$field_5[[1L]]), 5))
        if (!native_expected)
            stopifnot(identical(native$counts, integer(6L)))

        events <- new.env(parent = emptyenv())
        events$hits <- 0L
        trace("vec_arith", where = asNamespace("vctrs"),
              tracer = function() events$hits <- events$hits + 1L,
              print = FALSE)
        traced_ordinary <- run(FALSE, events)
        traced_native <- run(TRUE, events)
        untrace("vec_arith", where = asNamespace("vctrs"))
        same(traced_native$data, traced_ordinary$data)
        stopifnot(traced_native$hits > 0L,
                  identical(traced_native$hits, traced_ordinary$hits),
                  identical(traced_native$counts[[6L]], 0L))
        probe("C_dtatools_probe_unique_repl_mode", 1L)
        list(native = native$counts, traced = traced_native$counts,
             callbacks = traced_native$hits)
    }, args = list(native_expected = native_expected), libpath = .libPaths())
    expect_identical(observed$native[[1L]], as.integer(native_expected))
    expect_identical(observed$native[[6L]], as.integer(native_expected))
    expect_identical(observed$traced[[6L]], 0L)
    expect_gt(observed$callbacks, 0L)
})

test_that("native constant replacement stages a buffer for shared owned targets", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    native_expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("repl-native-shared-constant", function(native_expected) {
        library(dtatools)
        cc <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        d <- as_dibble(tibble::tibble(x = rep(2, 41L), spare = rep(7, 41L)))
        table_alias <- d
        column_alias <- d$x
        attrs <- attributes(column_alias)
        before <- cc("C_dtatools_probe_unique_repl_stats", FALSE)
        replace_values(d, x = abs(-3))
        counts <- cc("C_dtatools_probe_unique_repl_stats", FALSE) - before
        stopifnot(counts[[6L]] == as.integer(native_expected),
            identical(as.double(d$x), rep(3, 41L)),
            identical(as.double(table_alias$x), rep(3, 41L)),
            identical(as.double(column_alias), rep(2, 41L)),
            identical(attributes(d$x), attrs),
            identical(attributes(column_alias), attrs),
            identical(as.double(d$spare), rep(7, 41L)))
        TRUE
    }, args = list(native_expected = native_expected), libpath = .libPaths())
    expect_true(observed)
})
