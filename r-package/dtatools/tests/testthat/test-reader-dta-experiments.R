.read_dta_default <- function(path, ...) read_dta(path, output = "tibble", ...)

test_that("DTA default fills retain every storage width and missing code", {
    paths <- character()
    withr::defer(unlink(paths))
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        expected <- dtatools:::.read_dta_rust_vectors(path, n_max = 27)
        numeric_names <- names(expected)[vapply(expected, is.numeric, logical(1))]
        widths <- vapply(expected[numeric_names], dta_storage_type, character(1))
        for (compact in c(TRUE, FALSE)) {
            for (threads in c(0L, 1L, 4L)) {
                actual <- .read_dta_default(
                    path, threads = threads, use_numeric_altrep = compact, n_max = 27
                )
                info <- paste(name, compact, threads)
                expect_identical(vapply(actual[numeric_names],
                                        dtatools:::.is_numeric_altrep, logical(1)),
                                 compact & widths != "double", info = info)
                expect_identical(actual, expected, info = info)
                for (column in numeric_names) {
                    expect_identical(missing_tag(actual[[column]]),
                                     c(NA_character_, letters), info = info)
                    expect_true(anyNA(actual[[column]]), info = info)
                }
            }
        }
    }
})

test_that("DTA defaults preserve projected legacy and strL reads", {
    for (name in c("synthetic_v105.dta", "synthetic_v108.dta",
                   "synthetic_v110.dta", "synthetic_v111.dta",
                   "all_types_v115.dta", "all_types_v118.dta",
                   "strl_test_v118.dta")) {
        path <- fixture(name)
        all <- dtatools:::.read_dta_rust_vectors(path)
        selected <- rev(names(all))
        expected <- dtatools:::.read_dta_rust_vectors(
            path, col_select = tidyselect::all_of(selected), skip = 1, n_max = 3
        )
        expected_empty_rows <- dtatools:::.read_dta_rust_vectors(path, n_max = 0)
        expected_empty_columns <- dtatools:::.read_dta_rust_vectors(
            path, col_select = tidyselect::any_of("absent_column")
        )
        for (threads in c(0L, 1L, 4L)) {
            actual <- .read_dta_default(
                path, col_select = tidyselect::all_of(selected), skip = 1, n_max = 3,
                threads = threads
            )
            expect_identical(actual, expected, info = paste(name, threads))
            expect_identical(.read_dta_default(path, n_max = 0, threads = threads),
                             expected_empty_rows)
            expect_identical(.read_dta_default(
                path, col_select = tidyselect::any_of("absent_column"), threads = threads
            ), expected_empty_columns)
        }
    }
})

test_that("DTA default ring completes multiple blocks with ordered strings", {
    count <- 34000L
    tags <- c(NA_real_, tagged_missing("a"), tagged_missing("z"))
    data <- tibble::tibble(
        b = dta_byte(rep(c(-10, 0, 100, tags), length.out = count)),
        i = dta_int(rep(c(-30000, 0, 30000, tags), length.out = count)),
        l = dta_long(rep(c(-2000000000, 0, 2000000000, tags), length.out = count)),
        f = dta_float(rep(c(-1.5, 0, 2.5, tags), length.out = count)),
        d = dta_double(rep(c(-1.5, 0, 2.5, tags), length.out = count)),
        s = rep(c("é", "", "repeated"), length.out = count)
    )
    attr(data$s, "stata.string.storage") <- "str1024"
    path <- withr::local_tempfile(fileext = ".dta")
    save_dta(data, path)
    expect_gt(file.info(path)$size, 32 * 1024^2)
    expected <- dtatools:::.read_dta_rust_vectors(path)
    window <- dtatools:::.read_dta_rust_vectors(
        path, col_select = c(f, s, l, i), skip = 8000, n_max = 10000
    )
    for (threads in c(1L, 4L)) {
        expect_identical(.read_dta_default(path, threads = threads), expected)
        expect_identical(.read_dta_default(
            path, col_select = c(f, s, l, i),
            skip = 8000, n_max = 10000, threads = threads
        ), window)
    }
})
