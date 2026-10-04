.int_lookup_bytes <- function(x) {
    writeBin(as.double(x), raw(), size = 8L, endian = "little")
}

.int_lookup_native <- function(env = parent.frame()) {
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior), envir = env)
    invisible(dta_double(c(1, 2)) + 1)
}

.int_lookup_expected <- function(values, numerator, storage) {
    # Start with ordinary binary64 division. Narrow each observed result once;
    # keep canonical R missing bytes out of the FLOAT round trip.
    result <- as.double(numerator) / values
    result[!is.finite(result) | abs(result) > (2^53 - 1) * 2^970] <- NA_real_
    if (storage == "float") {
        observed <- !is.na(result)
        result[observed] <- readBin(writeBin(result[observed], raw(), size = 4L,
                                           endian = "little"), double(),
                                    sum(observed), size = 4L, endian = "little")
    }
    result
}

.int_lookup_check_result <- function(result, expected, storage) {
    expected_bytes <- .int_lookup_bytes(expected)
    expect_identical(dta_storage_type(result), storage)
    expect_identical(.int_lookup_bytes(result), expected_bytes)
    expect_identical(is.na(result), is.na(expected))
    expect_identical(anyNA(result), anyNA(expected))

    # Clearing every missing lane checks the result's exact missing cache.
    # Both aliases must retain the original bytes after the mutable copy changes.
    alias <- .Call(C_dtatools_metadata_copy, result)
    mutable <- dibble(x = result)
    missing <- which(is.na(expected))
    if (length(missing)) replace_values(mutable, x = 0, where = missing)
    expected[missing] <- 0
    expect_identical(.int_lookup_bytes(mutable$x), .int_lookup_bytes(expected))
    expect_false(anyNA(mutable$x))
    expect_identical(.int_lookup_bytes(result), expected_bytes)
    expect_identical(.int_lookup_bytes(alias), expected_bytes)
    invisible(result)
}

.int_lookup_expect <- function(source, numerator, storage) {
    values <- as.double(source)
    before <- .int_lookup_bytes(source)
    attributes_before <- attributes(source)
    facts_before <- .Call(C_dtatools_numeric_facts_info, source)
    alias <- .Call(C_dtatools_metadata_copy, source)
    expected <- .int_lookup_expected(values, numerator, storage)
    entries <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
    result <- numerator / source
    expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries,
                     if (.dtatools_numeric_entry_expected("scalar")) 1 else 0)
    expect_identical(.int_lookup_bytes(source), before)
    expect_identical(.int_lookup_bytes(alias), before)
    expect_identical(attributes(source), attributes_before)
    expect_identical(.Call(C_dtatools_numeric_facts_info, source), facts_before)
    .int_lookup_check_result(result, expected, storage)
}

.int_lookup_backing <- function(source, backing) {
    switch(backing,
           plain = source,
           retained = .Call(C_dtatools_owned_numeric_freeze, source, 4093L),
           restored = unserialize(serialize(source, NULL)))
}

test_that("BYTE and INT reciprocals preserve modern observed codes and tags across lookup admission", {
    .int_lookup_native()
    cases <- list(
        list(construct = dta_byte, observed = seq.int(-127L, 100L)),
        list(construct = dta_int, observed = seq.int(-32767L, 32740L))
    )
    for (case in cases) {
        values <- c(case$observed, NA_real_, tagged_missing(letters))
        for (n in c(262143L, 262144L, 262145L)) {
            source <- case$construct(rep(values, length.out = n))
            .int_lookup_expect(source, 1.01, "float")
            .int_lookup_expect(source, dta_double(1.01), "double")
        }
    }
})

test_that("large integer reciprocals retain zero caches and unknown backing fallbacks", {
    .int_lookup_native()
    n <- 262145L
    for (constructor in list(dta_byte, dta_int)) {
        source <- constructor(rep(c(-3, -1, 1, 3), length.out = n))
        facts <- .Call(C_dtatools_numeric_facts_info, source)
        expect_identical(facts[["flags"]], 4)
        expect_identical(facts[["zero_count"]], 0)
        .int_lookup_expect(source, 1.01, "float")

        values <- rep(c(-3, -1, 0, 1, 3, NA_real_, tagged_missing(letters)),
                      length.out = n)
        source <- constructor(values)
        facts <- .Call(C_dtatools_numeric_facts_info, source)
        expect_identical(facts[["flags"]], 4)
        expect_identical(facts[["zero_count"]], as.double(sum(values == 0, na.rm = TRUE)))
        # Typed scalars retain the declared destination even when every
        # observed quotient is a signed zero.
        .int_lookup_expect(source, dta_float(-0), "float")
        .int_lookup_expect(source, dta_double(-0), "double")

        for (backing in c("retained", "restored")) {
            source <- .int_lookup_backing(constructor(values), backing)
            expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 0)
            .int_lookup_expect(source, 1.01, "float")
            .int_lookup_expect(source, dta_double(1.01), "double")
        }
    }
})

test_that("short integer and LONG reciprocals preserve ordinary fallback results", {
    .int_lookup_native()
    cases <- list(
        list(construct = dta_byte, values = c(-127, -3, 0, 3, 100), storage = "float"),
        list(construct = dta_int, values = c(-32767, -3, 0, 3, 32740), storage = "float"),
        list(construct = dta_long, values = c(-2147483647, -3, 0, 3, 2147483620),
             storage = "double")
    )
    for (case in cases) {
        values <- c(case$values, NA_real_, tagged_missing(letters))
        source <- case$construct(rep(values, length.out = 257L))
        .int_lookup_expect(source, 1.01, case$storage)
        .int_lookup_expect(source, dta_double(1.01), "double")
    }
})

test_that("large integer reciprocals keep captured bytes during allocation callbacks", {
    .int_lookup_native()
    if (!.dtatools_numeric_entry_expected("scalar"))
        skip("arithmetic checkpoint requires an admitted native execution profile")
    withr::defer(.Call(C_dtatools_test_arithmetic_checkpoint, 0L, NULL))
    cases <- list(
        list(construct = dta_byte, backing = "plain", action = "patch", storage = "float"),
        list(construct = dta_byte, backing = "retained", action = "materialize", storage = "double"),
        list(construct = dta_int, backing = "plain", action = "materialize", storage = "float"),
        list(construct = dta_int, backing = "retained", action = "patch", storage = "double")
    )
    n <- 262145L
    values <- rep(c(-3, 1, 0, NA_real_, tagged_missing(letters)), length.out = n)
    values[[n]] <- 3
    for (case in cases) {
        source <- .int_lookup_backing(case$construct(values), case$backing)
        alias <- .Call(C_dtatools_metadata_copy, source)
        before <- .int_lookup_bytes(source)
        numerator <- if (case$storage == "double") dta_double(1.01) else 1.01
        expected <- .int_lookup_expected(values, numerator, case$storage)
        fired <- 0L
        local({
            token <- new.env(parent = emptyenv())
            reg.finalizer(token, function(key) {
                fired <<- fired + 1L
                if (case$action == "patch") .Call(C_dtatools_patch_vector, source, n, 0)
                else .force_altrep_materialization(source)
            }, onexit = FALSE)
            .Call(C_dtatools_test_arithmetic_checkpoint, 1L, token)
        })
        entries <- .Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]]
        result <- numerator / source
        expect_identical(.Call(C_dtatools_numeric_entry_stats, FALSE)[["scalar"]] - entries, 1)
        expect_identical(fired, 1L)
        expect_identical(.int_lookup_bytes(alias), before)
        if (case$action == "patch") expect_identical(as.double(source)[[n]], 0)
        else expect_true(.Call(C_dtatools_is_materialized_numeric_altrep, source))
        expect_identical(.Call(C_dtatools_numeric_facts_info, source)[["flags"]], 0)
        .int_lookup_check_result(result, expected, case$storage)
    }
})
