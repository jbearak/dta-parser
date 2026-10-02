# Focused private regressions for direct metadata_real_value -> numeric_value.
# Source with testthat and a candidate dtatools namespace available. Not run yet.
# C_dtatools_summarize_sum iterates REAL_ELT on the original handle; public
# as.double()/unclass() can create a different handle and miss this exact path.
scalar_call <- function(name, ...) {
    .Call(get(name, envir = asNamespace("dtatools"), inherits = FALSE), ...)
}
scalar_sum <- function(x) scalar_call("C_dtatools_summarize_sum", x)
scalar_compact <- function(x) {
    get(".is_unmaterialized_numeric_altrep", asNamespace("dtatools"))(x)
}
scalar_constructors <- list(dtatools::dta_byte, dtatools::dta_int,
                            dtatools::dta_long, dtatools::dta_float)

testthat::test_that("metadata scalar forwarding preserves isolated compact captures", {
    for (constructor in scalar_constructors) {
        for (retained in c(FALSE, TRUE)) {
            source <- constructor(c(1, 3, 5))
            if (retained) {
                source <- scalar_call("C_dtatools_owned_numeric_freeze", source, 2)
            }
            proxy <- scalar_call("C_dtatools_metadata_copy", source)
            attributes_before <- attributes(proxy)
            testthat::expect_identical(
                scalar_call("C_dtatools_metadata_proxy_depth", proxy), 1L)
            testthat::expect_identical(scalar_sum(proxy), 9)
            testthat::expect_true(scalar_compact(proxy))
            scalar_call("C_dtatools_mutate_first_numeric_altrep", source, 7)
            gc()
            testthat::expect_identical(scalar_sum(source), 15)
            testthat::expect_identical(scalar_sum(proxy), 9)
            testthat::expect_identical(attributes(proxy), attributes_before)
            testthat::expect_true(scalar_compact(proxy))

            tagged <- constructor(c(1, dtatools::tagged_missing("z"), 5))
            if (retained) {
                tagged <- scalar_call("C_dtatools_owned_numeric_freeze", tagged, 1)
            }
            tagged_proxy <- scalar_call("C_dtatools_metadata_copy", tagged)
            testthat::expect_true(
                scalar_call("C_dtatools_has_tagged_na", tagged_proxy))
            testthat::expect_true(scalar_compact(tagged_proxy))
        }
    }
})

testthat::test_that("metadata scalar forwarding respects both materialized states", {
    for (constructor in scalar_constructors) {
        source <- constructor(c(1, 3, 5))
        # The two-slot view intentionally follows this physical source handle.
        proxy <- scalar_call("C_dtatools_metadata_view", source)
        testthat::expect_identical(scalar_sum(proxy), 9)
        scalar_call("C_dtatools_mutate_first_numeric_altrep", source, 7)
        testthat::expect_identical(scalar_sum(proxy), 15)

        # Once the proxy has its own data2, it must take priority over source.
        scalar_call("C_dtatools_force_altrep_materialization", proxy)
        scalar_call("C_dtatools_mutate_first_numeric_altrep", proxy, 11)
        testthat::expect_identical(scalar_sum(proxy), 19)
        testthat::expect_identical(scalar_sum(source), 15)
        testthat::expect_false(scalar_compact(proxy))
    }
})

testthat::test_that("three-slot scalar views track live compact values and missing counts", {
    for (constructor in scalar_constructors) {
        source <- constructor(c(1, 2, 3))
        views <- scalar_call("C_dtatools_mutation_views", list(x = source))
        proxy <- views[[1L]]
        testthat::expect_identical(scalar_sum(proxy), 6)
        testthat::expect_false(anyNA(proxy))

        # No public capture occurs before these writes: the private descriptor
        # shares the original compact bytes and synchronizes missing_count.
        scalar_call("C_dtatools_patch_vector", source, 2L, NA_real_)
        testthat::expect_true(is.na(scalar_sum(proxy)))
        testthat::expect_true(anyNA(proxy))
        scalar_call("C_dtatools_patch_vector", source, 2L, 4)
        testthat::expect_identical(scalar_sum(proxy), 8)
        testthat::expect_false(anyNA(proxy))

        # Physical source materialization must not invalidate the descriptor's
        # retained raw allocation or redirect it to the new writable doubles.
        scalar_call("C_dtatools_mutate_first_numeric_altrep", source, 9)
        gc()
        testthat::expect_identical(scalar_sum(source), 16)
        testthat::expect_identical(scalar_sum(proxy), 8)
        testthat::expect_true(scalar_compact(proxy))
    }
})

testthat::test_that("native scalar forwarding does not inspect foreign class metadata", {
    calls <- 0L
    source <- dtatools::dta_int(c(1, 3, 5))
    classes <- scalar_call("C_dtatools_callback_character", class(source),
                           function() NULL)
    attr(source, "class") <- classes
    proxy <- scalar_call("C_dtatools_metadata_view", source)
    scalar_call("C_dtatools_arm_callback_character", classes, function() {
        calls <<- calls + 1L
        stop("foreign scalar class metadata callback")
    })
    testthat::expect_identical(scalar_sum(proxy), 9)
    testthat::expect_identical(calls, 0L)
    testthat::expect_error(classes[[1L]], "foreign scalar class metadata callback")
    testthat::expect_identical(calls, 1L)
})

# This file cannot exercise a metadata-real proxy whose source is an arbitrary
# foreign ALTREAL: metadata_copy/view deliberately shallow-duplicate that input
# rather than wrap it. The production REAL_ELT fallback must remain in place;
# constructing that exact state needs a private C probe, not a public R test.
