test_that("experimental Arrow fills preserve compact values and projected windows", {
    data <- tibble::tibble(
        b = dta_byte(rep(c(-10, 0, 100, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        i = dta_int(rep(c(-30000, 0, 30000, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        l = dta_long(rep(c(-2000000000, 0, 2000000000, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        f = dta_float(rep(c(-1.5, 0, 2.5, NA, tagged_missing("a"), tagged_missing("z")), 1000)),
        d = dta_double(rep(c(-1.5, 0, 2.5, NA, tagged_missing("a"), tagged_missing("z")), 1000))
    )
    for (compression in c("uncompressed", "lz4", "zstd")) {
        path <- tempfile(fileext = ".arrow")
        save_arrow(data, path, compression = compression)
        expected <- withr::with_envvar(c(DTATOOLS_EXPERIMENT_ARROW_BOUNDED = "0",
            DTATOOLS_EXPERIMENT_ARROW_BULK_COPY = "0", DTATOOLS_EXPERIMENT_ARROW_OWNED = "0"),
            read_arrow(path))
        for (bulk in c("0", "1")) {
            withr::local_envvar(c(DTATOOLS_EXPERIMENT_ARROW_BOUNDED = "1",
                                 DTATOOLS_EXPERIMENT_ARROW_BULK_COPY = bulk,
                                 DTATOOLS_EXPERIMENT_ARROW_OWNED = "0"))
            for (threads in c(1L, 4L)) {
                actual <- read_arrow(path, threads = threads)
                expect_identical(actual, expected)
                expect_identical(datasig(actual), datasig(expected))
                selected <- read_arrow(path, col_select = c(f, b, l), skip = 7, n_max = 23,
                                       threads = threads)
                expect_identical(selected, expected[8:30, c("f", "b", "l")])
                expect_equal(nrow(read_arrow(path, n_max = 0, threads = threads)), 0)
                expect_equal(dim(read_arrow(path, col_select = tidyselect::any_of("absent"),
                                            threads = threads)), c(6000, 0))
            }
        }
    }
})

test_that("bounded Arrow falls back for value-dependent ordinary storage", {
    data <- tibble::tibble(n = c(1L, NA_integer_, -2L),
                           s = c("", NA_character_, "é"),
                           f = factor(c("a", NA, "b"), levels = c("b", "a", "unused")))
    path <- tempfile(fileext = ".arrow")
    save_arrow(data, path)
    withr::local_envvar(c(DTATOOLS_EXPERIMENT_ARROW_BOUNDED = "1",
                         DTATOOLS_EXPERIMENT_ARROW_OWNED = "0"))
    expect_identical(read_arrow(path), data)
    expect_identical(read_arrow(path, col_select = c(f, s)), data[c("f", "s")])
})
