.reciprocal_facts_bytes <- function(x) {
    writeBin(as.double(x), raw(), size = 8L, endian = "little")
}

.reciprocal_facts_native <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
    invisible(dta_double(c(1, 2)) + 1)
}

.reciprocal_facts_expected <- function(values, scalar, storage) {
    result <- scalar / values
    result[!is.finite(result) | abs(result) > (2^53 - 1) * 2^970] <- NA_real_
    if (storage == "float") {
        observed <- !is.na(result)
        result[observed] <- readBin(writeBin(result[observed], raw(), size = 4L,
                                           endian = "little"), double(),
                                    sum(observed), size = 4L, endian = "little")
    }
    result
}

.reciprocal_facts_check <- function(source, scalar, storage, double_scalar = FALSE) {
    values <- as.double(source)
    source_bytes <- .reciprocal_facts_bytes(source)
    facts <- .Call(C_dtatools_numeric_facts_info, source)
    expected <- .reciprocal_facts_expected(values, scalar, storage)
    numerator <- if (double_scalar) dta_double(scalar) else scalar
    entries <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    result <- numerator / source
    expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries,
                     if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
    expect_identical(dta_storage_type(result), storage)
    expect_identical(.reciprocal_facts_bytes(result), .reciprocal_facts_bytes(expected))
    expect_identical(is.na(result), is.na(expected))
    expect_identical(anyNA(result), anyNA(expected))
    expect_identical(.reciprocal_facts_bytes(source), source_bytes)
    expect_identical(.Call(C_dtatools_numeric_facts_info, source), facts)
    result_bytes <- .reciprocal_facts_bytes(result)
    mutable <- dibble(x = result)
    replace_values(mutable, x = 0, where = which(is.na(expected)))
    expected[is.na(expected)] <- 0
    expect_identical(.reciprocal_facts_bytes(mutable$x), .reciprocal_facts_bytes(expected))
    expect_false(anyNA(mutable$x))
    expect_identical(.reciprocal_facts_bytes(result), result_bytes)
    invisible(result)
}

test_that("cached FLOAT reciprocal facts cover ordinary zero and missing shapes", {
    .reciprocal_facts_native()
    shapes <- list(c(0.125, -3, 3), c(0.125, -3, 0, -0),
                   c(0.125, -3, NA_real_, tagged_missing("z")),
                   c(0.125, -3, 0, -0, NA_real_, tagged_missing("a")),
                   c(0, -0, NA_real_, tagged_missing("z")))
    for (values in shapes) for (retained in c(FALSE, TRUE)) {
        source <- dta_float(rep(values, length.out = 257L))
        if (retained) source <- .Call(C_dtatools_owned_numeric_freeze, source, 7L)
        expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 7)
        for (scalar in c(1.01, -0, 2^-1074)) {
            .reciprocal_facts_check(source, scalar, "float")
            .reciprocal_facts_check(source, scalar, "double", double_scalar = TRUE)
        }
    }
})

test_that("reciprocal fact invalidation preserves fallback and exact result caches", {
    .reciprocal_facts_native()
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        storage <- if (identical(constructor, dta_long)) "double" else "float"
        for (values in list(c(3, -3), c(3, -3, 0),
                            c(3, -3, NA_real_, tagged_missing("z")))) {
            source <- constructor(rep(values, length.out = 257L))
            .reciprocal_facts_check(source, 1.01, storage)
        }
        source <- constructor(rep(c(3, -3, 0, NA_real_, tagged_missing("z")),
                                  length.out = 257L))
        expected_flags <- if (identical(constructor, dta_float)) 7 else 4
        expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], expected_flags)
        .reciprocal_facts_check(source, 1.01, storage)
        .Call(C_dtatools_patch_vector, source, 3L, 3)
        expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 0)
        .reciprocal_facts_check(source, 1.01, storage)
        restored <- unserialize(serialize(source, NULL))
        expect_identical(.Call(C_dtatools_numeric_facts_info, restored)[["flags"]], 0)
        .reciprocal_facts_check(restored, 1.01, storage)
    }
    source <- dta_float(rep(c(0.125, -3, NA_real_, tagged_missing("z")),
                           length.out = 257L))
    .Call(C_dtatools_patch_vector, source, 257L, 2^-149)
    expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 0)
    .reciprocal_facts_check(source, 1.01, "double")
    source <- dta_float(rep(c(0.125, -3, NA_real_, tagged_missing("z")),
                           length.out = 257L))
    source <- .Call(C_dtatools_owned_numeric_freeze, source, 7L)
    alias <- .Call(C_dtatools_metadata_copy, source)
    .Call(C_dtatools_patch_vector, source, 1L, 2^-149)
    expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 0)
    expect_identical(.Call(C_dtatools_numeric_facts_info, alias)[["flags"]], 7)
    .reciprocal_facts_check(source, 1.01, "double")
    .reciprocal_facts_check(alias, 1.01, "float")
})

test_that("captured reciprocal facts survive source changes during allocation", {
    .reciprocal_facts_native()
    if (!.dtatools_numeric_entry_expected("scalar"))
        skip("arithmetic checkpoint requires an admitted native execution profile")
    withr::defer(.Call(C_dtatools_test_arithmetic_checkpoint, 0L, NULL))
    values <- rep(c(1, 0, -3, NA_real_, tagged_missing("z")), length.out = 257L)
    for (constructor in list(dta_int, dta_float)) {
        for (retained in c(FALSE, TRUE)) for (action in c("patch", "materialize")) {
            source <- constructor(values)
            if (retained) source <- .Call(C_dtatools_owned_numeric_freeze, source, 7L)
            expected <- .reciprocal_facts_expected(as.double(source), 1.01, "float")
            fired <- 0L
            local({
                token <- new.env(parent = emptyenv())
                reg.finalizer(token, function(key) {
                    fired <<- fired + 1L
                    if (action == "patch") .Call(C_dtatools_patch_vector, source, 1L, 0)
                    else .force_altrep_materialization(source)
                }, onexit = FALSE)
                .Call(C_dtatools_test_arithmetic_checkpoint, 1L, token)
            })
            result <- 1.01 / source
            expect_identical(fired, 1L)
            expect_identical(dta_storage_type(result), "float")
            expect_identical(.reciprocal_facts_bytes(result), .reciprocal_facts_bytes(expected))
            expect_identical(anyNA(result), anyNA(expected))
            expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 0)
            if (action == "patch") expect_identical(as.double(source)[[1L]], 0)
            mutable <- dibble(x = result)
            replace_values(mutable, x = 0, where = which(is.na(expected)))
            expected[is.na(expected)] <- 0
            expect_identical(.reciprocal_facts_bytes(mutable$x), .reciprocal_facts_bytes(expected))
            expect_false(anyNA(mutable$x))
        }
    }
})
