test_that("column gathers copy row runs across chunks and keep missing counts", {
    gather <- function(columns, rows, y = NULL, y_rows = NULL) {
        .Call(C_dtatools_gather_numeric_columns, columns, y, rows, y_rows)
    }
    values <- c(1, 2, NA, tagged_missing("a"), -3, 100, tagged_missing("z"), 0)
    set.seed(20261020)
    rows_of <- function(n) list(
        identity = seq_len(n),
        absent_tail = c(seq_len(n), rep(NA_integer_, 9)),
        absent_head = c(rep(NA_integer_, 5), seq_len(n)),
        shuffled = sample.int(n),
        sorted_half = sort(sample.int(n, n %/% 2)),
        reversed = rev(seq_len(n)),
        repeated = rep(seq_len(n), each = 2),
        mixed = c(seq(3, 40), seq(1, 10), NA, seq(10, 1)),
        absent = rep(NA_integer_, 4),
        empty = integer())
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        plain <- constructor(sample(values, 300, TRUE))
        inputs <- list(plain)
        if (dtatools:::.is_unmaterialized_numeric_altrep(plain)) {
            inputs <- c(inputs, list(.Call(C_dtatools_owned_numeric_freeze, plain, 7L)))
        }
        for (input in inputs) {
            reference <- as.double(input)
            for (rows in rows_of(length(input))) {
                gathered <- gather(list(input, input), rows)
                for (column in gathered) {
                    expected <- reference[rows]
                    expect_identical(as.double(column), expected)
                    expect_identical(is_tagged_missing(column), is_tagged_missing(expected))
                    expect_identical(anyNA(column), anyNA(expected))
                    # Each replaced missing value lowers the stored count by
                    # one, so an undercount would make anyNA() false early.
                    for (position in which(is.na(expected))[1:3]) {
                        if (is.na(position)) break
                        column <- replace(column, position, 1)
                        expected[[position]] <- 1
                        expect_identical(anyNA(column), anyNA(expected))
                    }
                }
            }
            absent <- c(seq_len(length(input)), rep(NA_integer_, 9))
            y_rows <- sample(c(seq_len(length(input)), NA_integer_), length(absent), TRUE)
            paired <- gather(list(input), absent, list(input), y_rows)[[1L]]
            expected <- ifelse(is.na(absent), reference[y_rows], reference[absent])
            expect_identical(as.double(paired), expected)
            expect_identical(anyNA(paired), anyNA(expected))
        }
    }
})
