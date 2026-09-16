test_that("Arrow reads preserve numeric values across representations and projected windows", {
    data <- tibble::tibble(
        b = dta_byte(rep(c(-10, 0, 100, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        i = dta_int(rep(c(-30000, 0, 30000, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        l = dta_long(rep(c(-2000000000, 0, 2000000000, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        f = dta_float(rep(c(-1.5, 0, 2.5, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        d = dta_double(rep(c(-1.5, 0, 2.5, NA, tagged_missing("a"), tagged_missing("z")), 1000))
    )
    expected_values <- lapply(data, as.double)
    expected_tags <- lapply(data, missing_tag)
    expected_signature <- datasig(data)
    for (compression in c("uncompressed", "lz4", "zstd")) {
        path <- tempfile(fileext = ".arrow")
        on.exit(unlink(path), add = TRUE)
        save_arrow(data, path, compression = compression)
        for (compact in c(TRUE, FALSE)) {
            for (threads in c(1L, 4L)) {
                actual <- read_arrow(path, threads = threads, use_numeric_altrep = compact)
                expect_identical(lapply(actual, as.double), expected_values)
                expect_identical(lapply(actual, missing_tag), expected_tags)
                expect_identical(datasig(actual), expected_signature)
                expect_identical(vapply(actual, dta_storage_type, ""),
                                 vapply(data, dta_storage_type, ""))
                expect_equal(vapply(actual[1:4], function(x) {
                    .Call(C_dtatools_owned_numeric_info, x)[["owned"]]
                }, 0), setNames(rep(as.numeric(compact), 4), names(data)[1:4]))
                selected <- read_arrow(path, col_select = c(f, b, l), skip = 7, n_max = 23,
                                       threads = threads, use_numeric_altrep = compact)
                expect_identical(lapply(selected, as.double),
                                 lapply(data[8:30, c("f", "b", "l")], as.double))
                expect_equal(dim(read_arrow(path, n_max = 0, threads = threads,
                                            use_numeric_altrep = compact)), c(0, 5))
                expect_equal(dim(read_arrow(path, col_select = tidyselect::any_of("absent"),
                                            threads = threads, use_numeric_altrep = compact)), c(6000, 0))
            }
        }
    }
})

test_that("Arrow reads preserve ordinary columns alongside owned numeric storage", {
    data <- tibble::tibble(
        compact = dta_int(c(1, NA_real_, tagged_missing("z"))),
        n = c(1L, NA_integer_, -2L),
        s = c("", NA_character_, "é"),
        text = c("", "shared", "shared"),
        flag = c(TRUE, NA, FALSE),
        bytes = as.raw(c(0, 127, 255)),
        f = factor(c("a", NA, "b"), levels = c("b", "a", "unused"))
    )
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path)
    for (compact in c(TRUE, FALSE)) for (threads in c(1L, 4L)) {
        actual <- read_arrow(path, threads = threads, use_numeric_altrep = compact)
        expect_identical(as.double(actual$compact), as.double(data$compact))
        expect_identical(actual[-1], data[-1])
        expect_equal(.Call(C_dtatools_owned_numeric_info, actual$compact)[["owned"]],
                     as.numeric(compact))
        expect_identical(read_arrow(path, col_select = c(f, s), threads = threads),
                         data[c("f", "s")])
    }
})
