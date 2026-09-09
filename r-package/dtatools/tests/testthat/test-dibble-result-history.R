# Retained-history regression for the four Stage8 memo seams. Exact installed
# 500-call evidence is separate; this shorter test has no elapsed/RSS claim.
expect_bounded_result_history <- function(kinds) {
    skip_if_not_installed("callr")
    for (kind in kinds) {
        observed <- .dtatools_child_r("history", function(libraries, kind) {
            .libPaths(libraries)
            library(dtatools)
            rows <- 64L
            column_names <- paste0("v", seq_len(8L))
            fresh <- function() {
                columns <- lapply(seq_len(8L), function(i) as.double(seq_len(rows)) + i)
                names(columns) <- column_names
                tibble::new_tibble(columns, nrow = rows)
            }
            pipeline <- function(x) {
                x <- dplyr::rename(x, renamed = v1)
                selected <- c("renamed", column_names[-1L])
                if (kind == "duplicate") {
                    x <- dplyr::select(x, tidyselect::all_of(c(stats::setNames(selected, selected), copy = "renamed")))
                    x <- dplyr::relocate(x, copy, .before = renamed)
                } else {
                    x <- dplyr::select(x, tidyselect::all_of(selected))
                    x <- dplyr::relocate(x, v8, .before = renamed)
                }
                x <- dplyr::rename(x, v1 = renamed)
                if (kind == "duplicate") dplyr::relocate(x, copy, .after = v8)
                else dplyr::relocate(x, v8, .after = v7)
            }
            operation <- switch(kind, selector = pipeline, duplicate = pipeline,
                constructor = function(x) as_dibble(fresh()),
                reserve = function(x) reserve_columns(x, n = 32L))
            heap <- function() { invisible(gc(full = TRUE)); gc(full = TRUE)[, "used"] }
            source <- as_dibble(fresh())
            latest <- source
            for (i in seq_len(24L)) latest <- operation(latest)
            first <- latest
            # Retain distinct earlier and latest outputs at both checkpoints.
            latest <- operation(latest)
            before <- heap()
            for (i in seq_len(100L)) latest <- operation(latest)
            after <- heap()
            # Check values after the measured heap checkpoints, with both
            # source and earlier output still live throughout the sequence.
            expected_names <- c(column_names, if (kind == "duplicate") "copy")
            stopifnot(identical(names(latest), expected_names))
            for (value in list(source, first, latest)) {
                for (j in seq_len(8L)) stopifnot(identical(as.double(value[[column_names[[j]]]]),
                    as.double(seq_len(rows)) + j))
            }
            if (kind == "duplicate") stopifnot(identical(as.double(latest$copy), as.double(latest$v1)))
            list(ncells = unname(after[["Ncells"]] - before[["Ncells"]]),
                vector_bytes = unname((after[["Vcells"]] - before[["Vcells"]]) * 8),
                rows = nrow(latest), columns = names(latest),
                namespace_path = getNamespaceInfo(asNamespace("dtatools"), "path"))
        }, args = list(.libPaths(), kind), libpath = .libPaths(), timeout = 120)
        expect_identical(normalizePath(observed$namespace_path),
            normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")))
        expect_identical(observed$rows, 64L)
        # The old per-address binding names grow by thousands of Ncells in
        # this interval. These budgets allow ordinary recorder/cache residue.
        expect_lt(observed$ncells, 1000)
        expect_lt(observed$vector_bytes, 40000)
    }
}

test_that("H01 construction and reserve do not retain address history", {
    expect_bounded_result_history(c("constructor", "reserve"))
})

test_that("H03 selectors do not retain address history", {
    skip_if_not_installed("dplyr", "1.2.1")
    expect_bounded_result_history(c("selector", "duplicate"))
})

test_that("H02 atomic nested capture preserves copies and opaque identities", {
    capture <- dtatools:::.capture_dibble_nested
    for (value in list(structure(c(1, 2), label = "number"),
                       structure(c("a", "b"), label = "text"), pairlist(a = 1L, b = 2L))) {
        out <- capture(value)
        expect_identical(out, value)
        expect_identical(typeof(out), typeof(value))
        expect_false(identical(rlang::obj_address(out), rlang::obj_address(value)))
    }
    environment <- new.env(parent = emptyenv())
    fn <- function() environment
    expect_identical(capture(environment), environment)
    expect_identical(capture(fn), fn)
})
