.materialization_native <- function(name, ...) {
    .Call(get(name, asNamespace("dtatools")), ...)
}

.materialization_arm <- function(finalizer, mode = 1L) {
    token <- new.env(parent = emptyenv())
    reg.finalizer(token, finalizer, onexit = FALSE)
    invisible(.materialization_native("C_dtatools_test_materialization_checkpoint", mode, token))
}

.materialization_disarm <- function() {
    invisible(.materialization_native("C_dtatools_test_materialization_checkpoint", 0L, NULL))
}

.materialization_force <- function(value) {
    invisible(.materialization_native("C_dtatools_force_altrep_materialization", value))
}

test_that("shared compact materialization decodes without copying compact bytes", {
    values <- c(-3, 0, 7, NA_real_, tagged_missing(letters))
    constructors <- list(dta_byte, dta_int, dta_long, dta_float)
    for (constructor in constructors) for (size in c(0L, 31L, 3000L)) {
        for (retained in c(FALSE, TRUE)) for (shared in c(FALSE, TRUE)) {
            expected <- rep_len(values, size)
            source <- constructor(expected)
            if (retained) source <- .materialization_native(
                "C_dtatools_owned_numeric_freeze", source, 7L)
            alias <- if (shared) .materialization_native("C_dtatools_metadata_copy", source)
            before <- .materialization_native("C_dtatools_native_copy_stats", FALSE)
            .materialization_force(source)
            added <- .materialization_native("C_dtatools_native_copy_stats", FALSE) - before
            expect_identical(added[["compact_copy"]], 0)
            expect_identical(as.double(source), expected)
            expect_false(dtatools:::.is_unmaterialized_numeric_altrep(source))
            if (shared) {
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(alias))
                expect_identical(as.double(alias), expected)
            }
            # A second pointer request reuses the doubles. Writable requests
            # remain isolated from both compact and newly materialized aliases.
            .materialization_force(source)
            second <- .materialization_native("C_dtatools_metadata_copy", source)
            if (size > 0L) {
                invisible(.materialization_native("C_dtatools_mutate_first_numeric_altrep", source, 99))
                expect_identical(as.double(source)[[1L]], 99)
                expect_identical(as.double(second), expected)
                if (shared) expect_identical(as.double(alias), expected)
            }
            if (shared) .materialization_force(alias)
            gc()
            expect_identical(as.double(second), expected)
        }
    }
})

test_that("allocation finalizers can alias materialize or patch compact inputs", {
    on.exit(.materialization_disarm(), add = TRUE)
    for (retained in c(FALSE, TRUE)) for (shared in c(FALSE, TRUE)) {
        for (action in c("alias", "materialize", "patch", "write", "alias_then_patch")) {
            expected <- c(1, NA_real_, tagged_missing("z"), 4)
            source <- dta_int(expected)
            if (retained) source <- .materialization_native(
                "C_dtatools_owned_numeric_freeze", source, 2L)
            prior <- if (shared) .materialization_native("C_dtatools_metadata_copy", source)
            captured <- NULL
            fired <- 0L
            .materialization_arm(function(key) {
                fired <<- fired + 1L
                if (action %in% c("alias", "alias_then_patch"))
                    captured <<- .materialization_native("C_dtatools_metadata_copy", source)
                if (action == "materialize") .materialization_force(source)
                if (action %in% c("patch", "alias_then_patch"))
                    invisible(.materialization_native("C_dtatools_patch_vector", source, 1L, 9))
                if (action == "write")
                    invisible(.materialization_native("C_dtatools_mutate_first_numeric_altrep", source, 9))
                gc()
            })
            .materialization_force(source)
            expect_identical(fired, 1L)
            actual <- expected
            if (action %in% c("patch", "write", "alias_then_patch")) actual[[1L]] <- 9
            expect_identical(as.double(source), actual)
            if (shared) expect_identical(as.double(prior), expected)
            if (!is.null(captured)) {
                expect_identical(as.double(captured), expected)
                .materialization_force(captured)
                expect_identical(as.double(captured), expected)
            }
            if (shared) .materialization_force(prior)
            gc()
            expect_identical(as.double(source), actual)
            if (shared) expect_identical(as.double(prior), expected)
        }
    }
})

test_that("ordinary writable pointer dispatch also avoids a compact detour", {
    expected <- rep_len(c(1, NA_real_, tagged_missing(letters), 4), 3000L)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        source <- constructor(expected)
        alias <- .materialization_native("C_dtatools_metadata_copy", source)
        before <- .materialization_native("C_dtatools_native_copy_stats", FALSE)[["compact_copy"]]
        invisible(.materialization_native("C_dtatools_mutate_first_numeric_altrep", source, 99))
        after <- .materialization_native("C_dtatools_native_copy_stats", FALSE)[["compact_copy"]]
        expect_identical(after - before, 0)
        expect_identical(as.double(source), c(99, expected[-1L]))
        expect_identical(as.double(alias), expected)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(alias))
    }
})

test_that("private materialization does not consume stale missing-count proofs", {
    on.exit(.materialization_disarm(), add = TRUE)
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (replacement in list(NA_real_, tagged_missing("a"))) {
            source <- constructor(rep(1, 3000L))
            expect_true(.materialization_native(
                "C_dtatools_mutation_info", list(source), 1L)[["backing_private"]])
            fired <- 0L
            .materialization_arm(function(key) {
                fired <<- fired + 1L
                invisible(.materialization_native("C_dtatools_patch_vector", source, 1L, replacement))
            })
            .materialization_force(source)
            expect_identical(fired, 1L)
            expect_identical(as.double(source), c(replacement, rep(1, 2999L)))
            expect_identical(missing_tag(source)[[1L]], missing_tag(replacement)[[1L]])
        }
    }
})

test_that("failed materialization preserves compact state and finalizer aliases", {
    on.exit(.materialization_disarm(), add = TRUE)
    for (retained in c(FALSE, TRUE)) {
        source <- dta_float(c(1, 2, NA_real_, tagged_missing("a")))
        if (retained) source <- .materialization_native(
            "C_dtatools_owned_numeric_freeze", source, 1L)
        captured <- NULL
        fired <- 0L
        .materialization_arm(function(key) {
            fired <<- fired + 1L
            captured <<- .materialization_native("C_dtatools_metadata_copy", source)
            gc()
        }, 2L)
        expect_error(.materialization_force(source), "injected materialization checkpoint failure")
        expect_identical(fired, 1L)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(captured))
        expected <- c(1, 2, NA_real_, tagged_missing("a"))
        expect_identical(as.double(source), expected)
        expect_identical(as.double(captured), expected)
        .materialization_force(source)
        invisible(.materialization_native("C_dtatools_mutate_first_numeric_altrep", source, 9))
        gc()
        expect_identical(as.double(captured), expected)
        expect_identical(as.double(source), c(9, expected[-1L]))
    }
})

test_that("unwinding materialization restores a private compact write claim", {
    on.exit(.materialization_disarm(), add = TRUE)
    source <- dta_int(rep(1, 3000L))
    .materialization_native("C_dtatools_test_materialization_checkpoint", 2L, NULL)
    expect_error(.materialization_force(source), "injected materialization checkpoint failure")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
    expect_true(.materialization_native(
        "C_dtatools_mutation_info", list(source), 1L)[["backing_private"]])
    before <- .materialization_native("C_dtatools_native_copy_stats", FALSE)[["compact_copy"]]
    invisible(.materialization_native("C_dtatools_patch_vector", source, 1L, 9))
    after <- .materialization_native("C_dtatools_native_copy_stats", FALSE)[["compact_copy"]]
    expect_identical(after - before, 0)
    expect_identical(as.double(source), c(9, rep(1, 2999L)))
})

test_that("materialization roots survive collection at every allocation", {
    for (retained in c(FALSE, TRUE)) {
        expected <- c(1, NA_real_, tagged_missing(letters), 4)
        source <- dta_long(expected)
        if (retained) source <- .materialization_native(
            "C_dtatools_owned_numeric_freeze", source, 3L)
        alias <- .materialization_native("C_dtatools_metadata_copy", source)
        previous <- gctorture2(1L)
        tryCatch(.materialization_force(source), finally = gctorture2(previous))
        expect_identical(as.double(source), expected)
        expect_identical(as.double(alias), expected)
        .materialization_force(alias)
        gc()
        expect_identical(as.double(alias), expected)
    }
})
