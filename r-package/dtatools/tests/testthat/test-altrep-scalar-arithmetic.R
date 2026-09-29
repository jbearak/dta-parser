test_that("compact Stata numerics use the typed scalar producer", {
    skip_if_not(exists("C_dtatools_numeric_entry_stats", asNamespace("dtatools")))
    # Settle the one-time helper profile before observing the compact route.
    invisible(dta_double(c(1, 2)) + 1)
    ns <- asNamespace("dtatools")
    counter <- function(reset = FALSE) .Primitive(".Call")(
        get("C_dtatools_numeric_entry_stats", ns, inherits = FALSE), reset
    )
    compact <- dtatools:::.is_unmaterialized_numeric_altrep
    constructors <- list(
        byte = dta_byte, int = dta_int, long = dta_long, float = dta_float
    )
    native_expected <- .dtatools_numeric_entry_expected("scalar")
    for (kind in names(constructors)) {
        source <- constructors[[kind]](rep(1, 4096L))
        invisible(counter(TRUE))
        result <- source + 1
        expect_identical(as.double(result), rep(2, 4096L), info = kind)
        expect_identical(dta_storage_type(result), kind, info = kind)
        expect_true(compact(source), info = kind)
        expect_true(compact(result), info = kind)
        if (native_expected)
            expect_identical(counter(FALSE)[["scalar"]], 1, info = kind)
    }
})

test_that("compact scalar promotion and missing values match the R route", {
    invisible(dta_double(c(1, 2)) + 1)
    source <- dta_byte(c(100, 1, NA_real_, tagged_missing("a")))
    promoted <- source + 1
    expect_identical(dta_storage_type(promoted), "int")
    expect_identical(as.double(promoted), c(101, 2, NA_real_, NA_real_))

    fractional <- dta_byte(c(1, 2)) + 0.5
    expect_identical(dta_storage_type(fractional), "float")
    expect_identical(as.double(fractional), c(1.5, 2.5))

    reverse <- 1 - dta_byte(c(1, 2, NA_real_))
    expect_identical(dta_storage_type(reverse), "byte")
    expect_identical(as.double(reverse), c(0, -1, NA_real_))
})

test_that("bounded integer scalar arithmetic preserves compact storage and promotes at limits", {
    invisible(dta_double(c(1, 2)) + 1)
    values <- list(byte = c(-127, 1, 100),
                   int = c(-32767, 1, 32740),
                   long = c(-2147483647, 1, 2147483620))
    constructors <- list(byte = dta_byte, int = dta_int, long = dta_long)
    for (kind in names(values)) {
        source <- constructors[[kind]](values[[kind]])
        unchanged <- source + 0
        widened <- source + 1
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(unchanged), info = kind)
        expect_identical(dta_storage_type(unchanged), kind, info = kind)
        expect_identical(as.double(unchanged), values[[kind]], info = kind)
        expect_identical(as.double(widened), values[[kind]] + 1, info = kind)
        expect_identical(dta_storage_type(widened),
                         switch(kind, byte = "int", int = "long", long = "double"),
                         info = kind)
    }
    reverse <- 1 - dta_int(c(-32767, 0, 32740))
    expect_identical(as.double(reverse), c(32768, 1, -32739))
    expect_identical(dta_storage_type(reverse), "long")
    large <- dta_byte(c(1, 2)) + 2147483648
    expect_identical(dta_storage_type(large), "float")
    expect_identical(as.double(large), rep(2147483648, 2))
})

test_that("compact float arithmetic promotes past the Stata observed limit", {
    invisible(dta_double(rep(1, 16L)) + 1)
    invisible(dta_float(rep(1, 4096L)) + 1)
    ordinary <- dta_float(c(-3.5, 0, 3.5))
    expect_identical(as.double(ordinary + 0.25), c(-3.25, 0.25, 3.75))
    expect_identical(dta_storage_type(ordinary + 0.25), "float")
    expect_identical(as.double(1 - ordinary), c(4.5, 1, -2.5))
    expect_identical(as.double(dta_float(c(1, NA_real_)) + 1), c(2, NA_real_))
    source <- dta_float(rep(1e38, 4096L))
    result <- source + 1e38
    expect_identical(dta_storage_type(result), "double")
    expect_equal(as.double(result), as.double(source) + 1e38)
})

test_that("compact helper admission checks live executable traces after warming", {
    ns <- asNamespace("dtatools")
    counter <- function(reset = FALSE) .Primitive(".Call")(
        get("C_dtatools_numeric_entry_stats", ns, inherits = FALSE), reset
    )
    source <- dta_byte(rep(1, 4096L))
    invisible(dta_double(rep(1, 16L)) + 1)
    invisible(source + 1)
    invisible(counter(TRUE))
    invisible(source + 1)
    native_expected <- .dtatools_numeric_entry_expected("scalar")
    if (native_expected) expect_identical(counter(FALSE)[["scalar"]], 1)

    hits <- 0L
    trace(".dta_read_is_na", tracer = function() hits <<- hits + 1L,
          where = ns, print = FALSE)
    on.exit(untrace(".dta_read_is_na", where = ns), add = TRUE)
    invisible(counter(TRUE))
    result <- source + 1
    expect_identical(hits, 2L)
    expect_identical(as.double(result), rep(2, 4096L))
    if (native_expected) expect_identical(counter(FALSE)[["scalar"]], 0)
})
