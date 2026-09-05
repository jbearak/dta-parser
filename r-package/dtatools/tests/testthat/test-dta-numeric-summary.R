test_that("numeric summaries match base R for every Stata storage", {
    constructors <- list(dta_byte, dta_int, dta_long, dta_float, dta_double)
    cases <- list(
        1:3, c(-10, 0, 3, 7, 20), numeric(), 4,
        c(1, 3, NA_real_, tagged_missing("a"), tagged_missing("z")),
        c(NA_real_, tagged_missing("a"), tagged_missing("z"))
    )
    for (constructor in constructors) {
        for (values in cases) {
            x <- constructor(values)
            before <- serialize(x, NULL)
            expected <- summary(as.double(x))
            expect_identical(summary(x), expected)
            expect_s3_class(summary(x), "summaryDefault")
            expect_null(dta_storage_type(summary(x)))
            expect_identical(serialize(x, NULL), before)
        }
    }
})

test_that("numeric summaries forward rounding and quantile arguments", {
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        x <- constructor(c(1, 2, 4, 8, 13, NA_real_, tagged_missing("b")))
        for (type in 1:9) {
            expect_identical(
                summary(x, digits = 2, quantile.type = type),
                summary(as.double(x), digits = 2, quantile.type = type)
            )
        }
    }
    for (constructor in list(dta_float, dta_double)) {
        x <- constructor(c(0.123456, 0.987654, 2.34567))
        expect_identical(summary(x, digits = 3), summary(as.double(x), digits = 3))
    }
})

test_that("summaries work on typed columns and whole dibbles", {
    data <- dibble(byte = dta_byte(1:3), int = dta_int(1:3),
        long = dta_long(1:3), float = dta_float(1:3), double = dta_double(1:3))
    expected <- as.data.frame(lapply(data, as.double))
    expect_identical(summary(data), summary(expected))
    expect_identical(summary(data$byte), summary(1:3))
})
