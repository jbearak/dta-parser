test_that("dta_identical compares numeric values across storage and bare vectors", {
    values <- c(1, 2, -0)
    constructors <- list(
        stata_byte, stata_int, stata_long, stata_float, stata_double
    )

    for (left in constructors) {
        expect_true(dta_identical(left(values), values))
        for (right in constructors) {
            expect_true(dta_identical(left(values), right(values)))
        }
    }
    expect_false(dta_identical(stata_byte(c(1, 2)), stata_byte(c(2, 1))))
    expect_false(dta_identical(stata_byte(1), c(1, 2)))
})

test_that("dta_identical distinguishes every Stata missing code", {
    values <- c(NA_real_, tagged_missing(letters))

    expect_true(dta_identical(stata_double(values), values))
    for (index in seq_along(values)) {
        expect_true(dta_identical(values[[index]], values[[index]]))
        expect_false(dta_identical(
            values[[index]], values[[index %% length(values) + 1L]]
        ))
    }
})

test_that("dta_identical compares strings exactly", {
    expect_true(dta_identical(stata_string(c("a", "")), c("a", "")))
    expect_false(dta_identical(stata_string(""), " "))
    expect_false(dta_identical(c("a", "b"), c("A", "b")))
})

test_that("dta_identical keeps date and datetime identity domains separate", {
    dates <- as.Date(c("2020-01-01", "2020-01-02"))
    datetimes <- as.POSIXct(dates, tz = "UTC")
    date_prototype <- structure(
        as.Date(numeric(), origin = "1970-01-01"),
        class = c("stata_temporal", "stata_date", "Date"),
        stata.storage = "int",
        format.stata = "%td"
    )
    datetime_prototype <- structure(
        as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"),
        class = c("stata_temporal", "stata_datetime", "POSIXct", "POSIXt"),
        stata.storage = "double",
        format.stata = "%tc"
    )
    stata_dates <- dtatools:::.restore_stata_temporal(
        dates, date_prototype, "int"
    )
    stata_datetimes <- dtatools:::.restore_stata_temporal(
        datetimes, datetime_prototype, "double"
    )

    expect_true(dta_identical(stata_dates, dates))
    expect_true(dta_identical(stata_datetimes, datetimes))
    expect_false(dta_identical(dates, datetimes))
    expect_false(dta_identical(dates, as.double(dates)))
    expect_false(dta_identical(datetimes, as.double(datetimes)))
})

test_that("dta_identical returns false for incompatible kinds", {
    expect_false(dta_identical(1, "1"))
    expect_false(dta_identical(stata_string("1"), stata_byte(1)))
})

test_that("dta_identical handles empty vectors and NULL without recycling", {
    expect_true(dta_identical(numeric(), stata_double()))
    expect_true(dta_identical(character(), stata_string()))
    expect_false(dta_identical(numeric(), character()))
    expect_true(dta_identical(NULL, NULL))
    expect_false(dta_identical(NULL, numeric()))
    expect_false(dta_identical(numeric(), NULL))
})

test_that("dta_identical ignores names, classes, and variable metadata", {
    x <- stata_byte(c(left = 1, right = tagged_missing("a")))
    attr(x, "label") <- "first label"
    attr(x, "format.stata") <- "%8.0g"
    attr(x, "labels") <- c(one = 1)

    y <- stata_double(c(other = 1, missing = tagged_missing("a")))
    attr(y, "label") <- "second label"
    attr(y, "format.stata") <- "%12.0g"
    attr(y, "labels") <- c(uno = 1)

    expect_true(dta_identical(x, y))
    expect_false(identical(x, y))
})

test_that("dta_identical rejects noncanonical NaN payloads", {
    expect_error(dta_identical(NaN, NaN), "noncanonical NaN")
    expect_error(dta_identical(NaN, "not numeric"), "noncanonical NaN")
    expect_error(
        dta_identical(tagged_nan_for_test("!"), tagged_nan_for_test("!")),
        "noncanonical NaN"
    )
})
