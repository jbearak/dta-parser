.arithmetic_lifetime_native <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
    invisible(dta_double(c(1, 2)) + 1)
}

.arithmetic_lifetime_result <- function(source) {
    before <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    result <- source * 2
    after <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    expect_identical(after - before,
                     if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
    result
}

test_that("arithmetic payloads survive collection and compact serialization", {
    .arithmetic_lifetime_native()
    expected <- c(-6, 0, 6, NA_real_, NA_real_)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        result <- local({
            source <- constructor(c(-3, 0, 3, NA_real_, tagged_missing("z")))
            .arithmetic_lifetime_result(source)
        })
        storage <- dta_storage_type(result)
        gc()
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result))
        expect_identical(as.double(result), expected)
        restored <- unserialize(serialize(result, NULL))
        gc()
        expect_identical(dta_storage_type(restored), storage)
        expect_identical(as.double(restored), expected)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(restored))

        # Materialization explicitly releases the compact descriptor. A second
        # request and a later GC must neither free it twice nor lose the values.
        .force_altrep_materialization(result)
        .force_altrep_materialization(result)
        gc()
        expect_identical(as.double(result), expected)
        expect_identical(as.double(restored), expected)
    }
})

test_that("arithmetic payload aliases detach before writable access and patches", {
    .arithmetic_lifetime_native()
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- constructor(c(1, NA_real_, 3, 4))
        result <- .arithmetic_lifetime_result(source)
        captured <- .Call(C_dtatools_metadata_copy, result)
        .Call(C_dtatools_mutate_first_numeric_altrep, result, 9)
        gc()
        expect_identical(as.double(result), c(9, NA_real_, 6, 8))
        expect_identical(as.double(captured), c(2, NA_real_, 6, 8))
        .force_altrep_materialization(captured)
        gc()
        expect_identical(as.double(captured), c(2, NA_real_, 6, 8))

        data <- dibble(x = .arithmetic_lifetime_result(source))
        saved <- copy_data(data)
        captured <- data$x
        replace_values(data, x = 7, where = c(1L, 3L))
        gc()
        expect_identical(as.double(data$x), c(7, NA_real_, 7, 8))
        expect_identical(as.double(saved$x), c(2, NA_real_, 6, 8))
        expect_identical(as.double(captured), c(2, NA_real_, 6, 8))
    }
})

test_that("arithmetic payload adoption roots descriptor and bytes across allocations", {
    .arithmetic_lifetime_native()
    source <- dta_int(c(3, NA_real_, 32740))
    before <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    previous <- gctorture2(1L)
    result <- tryCatch(source * 2, finally = gctorture2(previous))
    after <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    expect_identical(after - before,
                     if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
    gc()
    expect_identical(dta_storage_type(result), "long")
    expect_identical(as.double(result), c(6, NA_real_, 65480))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result))
    .force_altrep_materialization(result)
    gc()
    expect_identical(as.double(result), c(6, NA_real_, 65480))
})

.arithmetic_lifetime_arm <- function(finalizer) {
    token <- new.env(parent = emptyenv())
    reg.finalizer(token, finalizer, onexit = FALSE)
    # Keep the key live until the one-use checkpoint releases it. An ordinary
    # interpreter GC before native entry therefore cannot satisfy this test.
    invisible(.Call(C_dtatools_test_arithmetic_checkpoint, 1L, token))
}

.arithmetic_lifetime_checkpoint_ready <- function(env = parent.frame()) {
    if (!.dtatools_numeric_entry_expected("scalar"))
        skip("arithmetic checkpoint requires an admitted native execution profile")
    withr::defer(.Call(C_dtatools_test_arithmetic_checkpoint, 0L, NULL), envir = env)
}

test_that("arithmetic promotion proof survives a reentrant source patch", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    for (replacement in list(100, NA_real_)) {
        for (aliased in c(FALSE, TRUE)) {
            x <- dta_byte(rep(1, 128L))
            fired <- 0L
            .arithmetic_lifetime_arm(function(key) {
                fired <<- fired + 1L
                .Call(C_dtatools_patch_vector, x, 1L, replacement)
            })
            before <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
            result <- if (aliased) x * x else x * 2
            after <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
            expect_identical(after - before, 1)
            expect_identical(fired, 1L)
            expect_identical(as.double(x)[[1L]], replacement)
            expect_identical(dta_storage_type(result), "byte")
            expect_identical(as.double(result), rep(if (aliased) 1 else 2, 128L))
            expect_false(anyNA(result))
        }
    }
})

test_that("temporary arithmetic claims restore ordinary and owned write access", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    for (owned_proxy in c(FALSE, TRUE)) {
        for (fail in c(FALSE, TRUE)) {
            x <- dta_byte(rep(1, 128L))
            if (owned_proxy) {
                x <- .Call(C_dtatools_mutation_views, list(x = x))[[1L]]
                .Call(C_dtatools_patch_vector, x, 1L, 2)
            }
            if (fail) {
                .Call(C_dtatools_test_arithmetic_checkpoint, 2L, NULL)
                expect_error(x * 2, "injected arithmetic checkpoint failure")
            } else {
                result <- .arithmetic_lifetime_result(x)
                expect_identical(as.double(result)[[1L]], if (owned_proxy) 4 else 2)
            }
            before <- .Call(C_dtatools_native_copy_stats, FALSE)[["compact_copy"]]
            .Call(C_dtatools_patch_vector, x, 1L, 9)
            after <- .Call(C_dtatools_native_copy_stats, FALSE)[["compact_copy"]]
            expect_identical(after - before, 0)
            expect_identical(as.double(x)[[1L]], 9)
        }
    }
})

test_that("arithmetic cleanup preserves aliases created while the source is claimed", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    for (during in c(FALSE, TRUE)) {
        x <- dta_byte(rep(1, 128L))
        captured <- NULL
        fired <- 0L
        if (during) {
            .arithmetic_lifetime_arm(function(key) {
                fired <<- fired + 1L
                captured <<- .Call(C_dtatools_metadata_copy, x)
            })
        } else captured <- .Call(C_dtatools_metadata_copy, x)
        result <- .arithmetic_lifetime_result(x)
        expect_identical(fired, if (during) 1L else 0L)
        expect_identical(as.double(result), rep(2, 128L))
        .Call(C_dtatools_patch_vector, x, 1L, 100)
        gc()
        expect_identical(as.double(x)[[1L]], 100)
        expect_identical(as.double(captured), rep(1, 128L))
    }
})

test_that("disarming an abandoned arithmetic checkpoint releases its token", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    x <- dta_byte(c(1, 2))
    fired <- 0L
    .arithmetic_lifetime_arm(function(key) fired <<- fired + 1L)

    # Size validation fails before the backing-allocation checkpoint. The
    # preserved finalizer token must stay live until the caller disarms it.
    expect_error(x * c(1, 2, 3), class = "vctrs_error_incompatible_size")
    gc()
    expect_identical(fired, 0L)
    expect_identical(.Call(C_dtatools_test_arithmetic_checkpoint, 0L, NULL), 1L)
    gc()
    expect_identical(fired, 1L)
    expect_identical(.Call(C_dtatools_test_arithmetic_checkpoint, 0L, NULL), 0L)
    expect_identical(as.double(.arithmetic_lifetime_result(x)), c(2, 4))
})

test_that("general arithmetic preflight retains owned sources across reentrant writes", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    for (typed in c(FALSE, TRUE)) {
        for (scalar in c(FALSE, TRUE)) {
            for (replacement in list(1000, NA_real_)) {
                x <- dta_byte(rep(1, if (scalar) 1L else 128L))
                y <- if (typed) dta_double(rep(1, 128L)) else
                    .Call(C_dtatools_capture_column, rep(1, 128L))
                fired <- 0L
                .arithmetic_lifetime_arm(function(key) {
                    fired <<- fired + 1L
                    .Call(C_dtatools_patch_vector, y, 1L, replacement)
                })
                result <- x * y
                expect_identical(fired, 1L)
                expect_identical(as.double(result), rep(1, 128L))
                expect_identical(dta_storage_type(result), if (typed) "double" else "byte")
                expect_false(anyNA(result))
                before <- .Call(C_dtatools_native_copy_stats, FALSE)[["mutation_target_copy"]]
                .Call(C_dtatools_patch_vector, y, 1L, 9)
                after <- .Call(C_dtatools_native_copy_stats, FALSE)[["mutation_target_copy"]]
                expect_identical(after - before, 0)
                expect_identical(as.double(y)[[1L]], 9)
            }
        }
    }
})

test_that("owned arithmetic read claims survive nesting and release on unwind", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    for (fail in c(FALSE, TRUE)) {
        x <- dta_byte(rep(1, 128L))
        y <- .Call(C_dtatools_capture_column, rep(1, 128L))
        if (fail) {
            .Call(C_dtatools_test_arithmetic_checkpoint, 2L, NULL)
            expect_error(x * y, "injected arithmetic checkpoint failure")
        } else {
            nested <- NULL
            .arithmetic_lifetime_arm(function(key) {
                nested <<- x * y
                .Call(C_dtatools_patch_vector, y, 1L, 1000)
            })
            result <- x * y
            expect_identical(as.double(nested), rep(1, 128L))
            expect_identical(as.double(result), rep(1, 128L))
            expect_identical(as.double(y)[[1L]], 1000)
        }
        before <- .Call(C_dtatools_native_copy_stats, FALSE)[["mutation_target_copy"]]
        .Call(C_dtatools_patch_vector, y, 1L, 9)
        after <- .Call(C_dtatools_native_copy_stats, FALSE)[["mutation_target_copy"]]
        expect_identical(after - before, 0)
        expect_identical(as.double(y)[[1L]], 9)
    }
    x <- dta_byte(rep(1, 128L))
    y <- .Call(C_dtatools_capture_column, rep(1, 128L))
    alias <- NULL
    .arithmetic_lifetime_arm(function(key) {
        alias <<- .Call(C_dtatools_metadata_copy, y)
    })
    result <- x * y
    expect_identical(as.double(result), rep(1, 128L))
    .Call(C_dtatools_patch_vector, y, 1L, 1000)
    gc()
    expect_identical(as.double(y)[[1L]], 1000)
    expect_identical(as.double(alias), rep(1, 128L))
})

test_that("integer reciprocal inherits the captured missing count during reentrant writes", {
    .arithmetic_lifetime_native()
    .arithmetic_lifetime_checkpoint_ready()
    for (kind in c("byte", "int", "long")) {
        for (replacement in list(0, 2, NA_real_)) {
            values <- rep(c(NA_real_, 0, 1, -1, 3, tagged_missing("z")), length.out = 128L)
            x <- get(paste0("dta_", kind))(values)
            quotients <- 1.01 / values
            quotients[is.na(values)] <- NA_real_
            expected <- dtatools:::.dta_computed(quotients, kind)
            fired <- 0L
            .arithmetic_lifetime_arm(function(key) {
                fired <<- fired + 1L
                .Call(C_dtatools_patch_vector, x, 1L, replacement)
            })
            actual <- 1.01 / x
            expect_identical(fired, 1L)
            expect_identical(as.double(x)[[1L]], replacement)
            expect_identical(dta_storage_type(actual), dta_storage_type(expected))
            expect_identical(writeBin(as.double(actual), raw(), size = 8L),
                             writeBin(as.double(expected), raw(), size = 8L))
            missing <- is.na(as.double(expected))
            expect_identical(is.na(actual), missing)
            result <- dibble(x = actual)
            replace_values(result, x = 0, where = which(missing))
            expect_false(anyNA(result$x))
        }
    }
})
