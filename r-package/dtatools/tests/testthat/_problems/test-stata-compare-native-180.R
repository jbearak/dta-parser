# Extracted from test-stata-compare-native.R:180

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "dtatools", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
compact_constructors <- list(
    byte = stata_byte,
    int = stata_int,
    long = stata_long,
    float = stata_float
)
mixed_values <- function(constructor) {
    constructor(c(
        -5, 0, 5, NA_real_, tagged_missing("a"), tagged_missing("z")
    ))
}

# test -------------------------------------------------------------------------
value <- stata_double(c(
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
compact <- stata_byte(c(
        -5, NA_real_, 5, 3, tagged_missing("a"), tagged_missing("z")
    ))
expect_identical(
        dtatools:::.stata_compare_native("==", compact, value),
        c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
    )
expect_identical(
        compact == value, c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE)
    )
expect_identical(
        compact < value, c(FALSE, TRUE, FALSE, TRUE, FALSE, FALSE)
    )
