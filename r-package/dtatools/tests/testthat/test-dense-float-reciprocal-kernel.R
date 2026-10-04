.dense_reciprocal_bytes <- function(x) {
    writeBin(as.double(x), raw(), size = 8L, endian = "little")
}

.dense_reciprocal_expect <- function(source, values, scalar, storage) {
    before <- .dense_reciprocal_bytes(source)
    attributes_before <- attributes(source)
    expected <- scalar / values
    expected[!is.finite(expected) | abs(expected) > (2^53 - 1) * 2^970] <- NA_real_
    if (storage == "float") {
        observed <- !is.na(expected)
        expected[observed] <- readBin(writeBin(expected[observed], raw(), size = 4L, endian = "little"),
            double(), sum(observed), size = 4L, endian = "little")
    }
    invisible(dta_double(c(1, 2)) + 1)
    entries <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    result <- scalar / source
    expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries,
        if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
    expect_identical(dta_storage_type(result), storage)
    expect_identical(.dense_reciprocal_bytes(result), .dense_reciprocal_bytes(expected))
    expect_identical(is.na(result), is.na(expected))
    expect_identical(anyNA(result), anyNA(expected))
    expect_identical(.dense_reciprocal_bytes(source), before)
    expect_identical(attributes(source), attributes_before)
    original_result <- .dense_reciprocal_bytes(result)
    mutable <- dibble(x = result)
    replace_values(mutable, x = 0, where = which(is.na(expected)))
    expected[is.na(expected)] <- 0
    expect_identical(.dense_reciprocal_bytes(mutable$x), .dense_reciprocal_bytes(expected))
    expect_false(anyNA(mutable$x))
    expect_identical(.dense_reciprocal_bytes(result), original_result)
}

test_that("strict dense reciprocal masks retain zero signs and exact missing caches", {
    n <- 16385L
    values <- rep(c(0.125, -3, 0, -0), length.out = n)
    positions <- seq.int(2L, n, by = 2L)
    values[positions] <- rep(c(NA_real_, tagged_missing(letters)), length.out = length(positions))
    for (scalar in c(1.01, -0, 2^-1074)) {
        for (backing in c("plain", "retained", "restored")) {
            source <- dta_float(values)
            if (backing == "retained") {
                source <- .Call(C_dtatools_owned_numeric_freeze, source, 8191L)
            } else if (backing == "restored") {
                source <- unserialize(serialize(source, NULL))
            }
            expect_identical(.Call(C_dtatools_numeric_domain_info, source), backing != "restored")
            .dense_reciprocal_expect(source, values, scalar, "float")
        }
    }
})

test_that("late unsafe strict dense reciprocals discard provisional narrowed results", {
    n <- 16385L
    values <- rep(c(0.125, NA_real_, -3, tagged_missing("z")), length.out = n)
    # This observed lane appears after dense dispatch in the first captured tile.
    values[[16383L]] <- 2^-149
    for (backing in c("plain", "retained", "restored")) {
        source <- dta_float(values)
        if (backing == "retained") {
            source <- .Call(C_dtatools_owned_numeric_freeze, source, 16384L)
        } else if (backing == "restored") {
            source <- unserialize(serialize(source, NULL))
        }
        .dense_reciprocal_expect(source, values, 1.01, "double")
    }
})
