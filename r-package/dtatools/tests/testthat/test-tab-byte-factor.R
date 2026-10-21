test_that("byte factorization reads raw storage as the general loop decodes it", {
    factorize <- function(x, mode) {
        .Call(C_dtatools_factorize_numeric, x, NULL, mode)
    }
    values <- c(-127, 100, 0, NA, tagged_missing("a"), tagged_missing("z"),
                5, 5, -3, NA, tagged_missing("m"))
    samples <- list(values, c(NA, tagged_missing("b")), 42, numeric(),
                    rep_len(values, 65539))
    for (sample in samples) {
        compact <- dta_byte(sample)
        inputs <- list(compact)
        if (length(sample)) {
            frozen <- .Call(C_dtatools_owned_numeric_freeze, compact, 4093L)
            inputs <- c(inputs, list(frozen,
                .Call(C_dtatools_metadata_copy, frozen)))
        }
        for (x in inputs) for (mode in 0:2) {
            expect_identical(factorize(x, mode), factorize(sample, mode),
                             info = paste(mode, length(sample)))
            expect_true(.is_unmaterialized_numeric_altrep(x))
        }
    }
    legacy <- read_dta(fixture("synthetic_v111.dta"))$b
    for (mode in 0:2) {
        expect_identical(factorize(legacy, mode),
                         factorize(as.double(legacy), mode))
    }
    # Seeds and other storage keep the general loop.
    x <- dta_byte(c(1, 3, NA))
    expect_identical(.Call(C_dtatools_factorize_numeric, x, c(2, 1), 1L),
                     .Call(C_dtatools_factorize_numeric, c(1, 3, NA), c(2, 1), 1L))
    expect_identical(factorize(dta_int(values), 1L), factorize(values, 1L))
})

test_that("codebook level counts match tabulate() and is.na()", {
    previous <- function(x, count = TRUE) {
        codes <- unclass(x)
        attributes(codes) <- NULL
        names <- levels(x)
        absent <- sum(is.na(codes))
        counts <- if (count) tabulate(codes, nbins = length(names)) else
            integer(length(names))
        if (absent) {
            counts <- c(counts, absent)
            names <- c(names, NA_character_)
        }
        stats::setNames(counts, names)
    }
    plain <- c(1L, 3L, NA, 2L, 3L, 0L, 7L, -1L, NA)
    long <- rep_len(plain, 70000)
    wrapper <- structure(long, levels = c("a", "b", "c"), class = "factor")
    expect_true(.is_altrep(wrapper))
    factors <- list(
        structure(plain, levels = c("a", "b", "c"), class = "factor"),
        wrapper,
        factor(c("x", NA, "y"), exclude = NULL),
        addNA(factor(c("x", NA, "y"))),
        structure(1:5, levels = letters[1:5], class = "factor"),
        structure(integer(), levels = character(), class = "factor"),
        structure(c(NA_integer_, NA_integer_), levels = character(),
                  class = "factor"))
    for (x in factors) for (count in c(TRUE, FALSE)) {
        expect_identical(.book_level_counts(x, count), previous(x, count))
    }
    wrapped <- .Call(C_dtatools_level_counts, factors[[1L]], 3L, TRUE)
    expect_identical(wrapped, list(c(1L, 1L, 2L), 2L))
    expect_null(.Call(C_dtatools_level_counts, c(1, 2, 2), 2L, TRUE))
})
