test_that("dplyr reload disables all stale grouped native guards", {
    skip_if_not_installed("dplyr")
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    expected <- .dtatools_ungrouped_dplyr_build_expected()
    observed <- .dtatools_child_r("grouped-native-dplyr-reload", function(expected) {
        library(dtatools)
        loadNamespace("dplyr")
        probe <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
        guards <- function() c(
            probe("C_dtatools_grouped_guard_early", NULL),
            probe("C_dtatools_grouped_guard_public", NULL),
            probe("C_dtatools_probe_grouped_guard_live", NULL))
        before <- guards()
        if (expected) stopifnot(all(before))
        unloadNamespace("dplyr")
        stopifnot(!any(guards()), !dtatools:::.grouped_probe_state$pinned)
        loadNamespace("dplyr")
        stopifnot(!any(guards()), !dtatools:::.grouped_probe_state$pinned)
        calls <- 0L
        trace("vec_group_loc", where = asNamespace("vctrs"), print = FALSE,
            tracer = function() calls <<- calls + 1L)
        on.exit(untrace("vec_group_loc", where = asNamespace("vctrs")))
        d <- as_dibble(tibble::tibble(x = rep(c(2, 7), 20L),
            g = dta_long(rep(1:4, 10L))))
        out <- dplyr::mutate(d, y = x + 1, .by = g)
        stopifnot(calls > 0L, identical(as.double(out$y), rep(c(3, 8), 20L)),
            identical(names(d), c("x", "g")))
        TRUE
    }, args = list(expected = expected), libpath = .libPaths())
    expect_true(observed)
})
