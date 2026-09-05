compact_constructors <- list(
    byte = dta_byte,
    int = dta_int,
    long = dta_long,
    float = dta_float
)

mixed_values <- function(constructor) {
    constructor(c(
        -5, 0, 5, NA_real_, tagged_missing("a"), tagged_missing("z")
    ))
}

test_that("native scalar comparisons match Stata total order", {
    for (storage in names(compact_constructors)) {
        value <- mixed_values(compact_constructors[[storage]])

        expect_identical(
            value == 5, c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value != 5, c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE),
            info = storage
        )
        expect_identical(
            value < 5, c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value <= 5, c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value > 5, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE),
            info = storage
        )
        expect_identical(
            value >= 5, c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE),
            info = storage
        )
    }
})

test_that("native comparisons keep every missing code distinct and ordered", {
    for (storage in names(compact_constructors)) {
        value <- mixed_values(compact_constructors[[storage]])

        expect_identical(
            value == NA_real_,
            c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value < NA_real_,
            c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
        expect_identical(
            value == tagged_missing("a"),
            c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE),
            info = storage
        )
        expect_identical(
            value >= tagged_missing("a"),
            c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE),
            info = storage
        )
        expect_identical(
            value <= tagged_missing("z"),
            rep(TRUE, 6),
            info = storage
        )
        expect_identical(
            value > tagged_missing("z"),
            rep(FALSE, 6),
            info = storage
        )
    }
})

test_that("narrow storage understands constants it cannot represent", {
    value <- dta_byte(c(-5, 0, 5, NA_real_, tagged_missing("a")))

    # 5.5 and 200 are not representable as Stata bytes, yet comparisons
    # must still work on the byte's decoded value.
    expect_identical(value == 5.5, rep(FALSE, 5))
    expect_identical(value < 5.5, c(TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(value < 200, c(TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(value > -200, c(TRUE, TRUE, TRUE, TRUE, TRUE))
    expect_identical(value < Inf, c(TRUE, TRUE, TRUE, FALSE, FALSE))
    expect_identical(value > -Inf, rep(TRUE, 5))
})

test_that("scalar-on-the-left comparisons flip correctly", {
    value <- mixed_values(dta_int)

    expect_identical(5 == value, value == 5)
    expect_identical(5 != value, value != 5)
    expect_identical(5 < value, value > 5)
    expect_identical(5 <= value, value >= 5)
    expect_identical(5 > value, value < 5)
    expect_identical(5 >= value, value <= 5)
})

test_that("compact-versus-compact comparisons agree elementwise", {
    x <- dta_byte(c(1, 2, NA_real_, tagged_missing("a"), 5))
    y <- dta_long(c(1, 3, NA_real_, tagged_missing("b"), 4))

    expect_identical(x == y, c(TRUE, FALSE, TRUE, FALSE, FALSE))
    expect_identical(x < y, c(FALSE, TRUE, FALSE, TRUE, FALSE))
    expect_identical(x >= y, c(TRUE, FALSE, TRUE, FALSE, TRUE))
})

test_that("comparisons never materialize compact operands", {
    value <- mixed_values(dta_byte)
    other <- mixed_values(dta_long)

    invisible(value == 5)
    invisible(5 < value)
    invisible(value >= tagged_missing("a"))
    invisible(value == other)

    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(other))
})

test_that("the native kernel is engaged for compact storage", {
    for (storage in names(compact_constructors)) {
        value <- mixed_values(compact_constructors[[storage]])
        native <- dtatools:::.dta_compare_native("==", value, 5)

        expect_identical(
            native, c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
            info = storage
        )
    }

    # Eager doubles compare natively too, classifying NA_real_ and
    # tagged NaNs from the decoded payload bits.
    expect_identical(
        dtatools:::.dta_compare_native("==", dta_double(c(1, 2)), 1),
        c(TRUE, FALSE)
    )
})

test_that("decoded double vectors compare natively with full semantics", {
    value <- dta_double(c(
        -5, 0, 5, NA_real_, tagged_missing("a"), tagged_missing("z")
    ))

    expect_identical(value == 5, c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE))
    expect_identical(value < 5, c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE))
    expect_identical(value > 5, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
    expect_identical(
        value == NA_real_, c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE)
    )
    expect_identical(
        value == tagged_missing("a"),
        c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE)
    )
    expect_identical(
        value >= tagged_missing("a"),
        c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE)
    )

    # Mixed compact-vs-double pairs of equal length also stay native.
    compact <- dta_byte(c(
        -5, NA_real_, 5, 3, tagged_missing("a"), tagged_missing("z")
    ))
    expect_identical(
        dtatools:::.dta_compare_native("==", compact, value),
        c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
    )
    expect_identical(
        compact == value, c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
    )
    # Element 2 is `.` versus 0: missing sorts above every finite value.
    expect_identical(
        compact < value, c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE)
    )

    # Noncanonical NaN payloads still surface the fallback's error.
    expect_error(value == NaN, "noncanonical NaN")
})

test_that("multi-threaded comparisons match single-threaded results", {
    length_over_threshold <- 600000L
    value <- dta_long(seq_len(length_over_threshold))
    expected <- seq_len(length_over_threshold) <= 300000L

    previous <- options(dtatools.threads = 2L)
    on.exit(options(previous), add = TRUE)
    threaded <- value <= 300000

    options(dtatools.threads = 1L)
    serial <- value <= 300000

    expect_identical(threaded, expected)
    expect_identical(serial, expected)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
})

test_that("fallback-owned errors survive the native fast path", {
    value <- mixed_values(dta_byte)

    expect_error(value == NaN, "noncanonical NaN")
    expect_error(value == dta_byte(c(1, 2)), class = "vctrs_error")
})
