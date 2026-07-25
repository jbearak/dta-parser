fixture <- function(name) {
    system.file("extdata", name, package = "dtaparser", mustWork = TRUE)
}

test_that("read_dta has the haven-compatible public signature", {
    expected <- c("file", "encoding", "col_select", "skip", "n_max", ".name_repair")
    expect_identical(names(formals(read_dta)), expected)
    expect_null(formals(read_dta)$encoding)
    expect_null(formals(read_dta)$col_select)
    expect_identical(formals(read_dta)$skip, 0)
    expect_identical(formals(read_dta)$n_max, Inf)
    expect_identical(formals(read_dta)$.name_repair, "unique")
})

test_that("all bundled fixtures agree with haven", {
    skip_if_not_installed("haven")
    paths <- list.files(
        system.file("extdata", package = "dtaparser"),
        pattern = "[.]dta$",
        full.names = TRUE
    )
    expect_gt(length(paths), 20L)

    for (path in paths) {
        actual <- read_dta(path)
        expected <- haven::read_dta(path)
        info <- basename(path)
        metadata <- dtaparser:::.dta_metadata(normalizePath(path))
        storage <- stats::setNames(
            attr(metadata, "dta_storage", exact = TRUE),
            as.character(metadata)
        )

        expect_identical(dim(actual), dim(expected), info = info)
        expect_identical(names(actual), names(expected), info = info)
        expect_identical(attr(actual, "label", exact = TRUE),
                         attr(expected, "label", exact = TRUE), info = info)
        expect_true(attr(actual, "dta_format_version", exact = TRUE) %in%
                    c(113L, 114L, 115L, 117L, 118L, 119L), info = info)

        for (name in names(actual)) {
            if (storage[[name]] %in% c("float", "double")) {
                expect_equal(actual[[name]], expected[[name]], tolerance = 1e-7,
                             info = paste(info, name))
            } else {
                expect_equal(actual[[name]], expected[[name]], tolerance = 0,
                             info = paste(info, name, "exact"))
            }
            expect_identical(is.na(actual[[name]]), is.na(expected[[name]]),
                             info = paste(info, name, "missing positions"))
            if (is.numeric(actual[[name]])) {
                expect_identical(
                    haven::na_tag(actual[[name]]),
                    haven::na_tag(expected[[name]]),
                    info = paste(info, name, "missing tags")
                )
            }
        }
    }
})

test_that("projection, renaming, and row bounds match haven", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4
    )
    expected <- haven::read_dta(path, skip = 5, n_max = 4)

    expect_identical(names(actual), c("origin", "make", "price"))
    expect_equal(actual$origin, expected$foreign)
    expect_equal(actual$make, expected$make)
    expect_equal(actual$price, expected$price)
    expect_identical(attr(actual, "label"), attr(expected, "label"))
})

test_that("an empty projection retains the selected row count", {
    path <- fixture("auto_v118.dta")
    result <- read_dta(path, col_select = character(), skip = 2, n_max = 3)
    expect_identical(dim(result), c(3L, 0L))
})

test_that("typed predicates and duplicate selections are deterministic", {
    path <- fixture("auto_v118.dta")

    strings <- read_dta(path, col_select = where(is.character), n_max = 2)
    expect_identical(names(strings), "make")
    expect_type(strings$make, "character")

    numerics <- read_dta(path, col_select = where(is.numeric), n_max = 2)
    expect_identical(names(numerics), setdiff(
        names(read_dta(path, n_max = 0)), "make"
    ))
    expect_true(all(vapply(numerics, is.numeric, logical(1))))

    duplicated <- read_dta(
        path,
        col_select = c(first_price = price, price, make),
        n_max = 2
    )
    expect_identical(names(duplicated), c("first_price", "make"))
    expect_equal(duplicated$first_price, read_dta(path, n_max = 2)$price)
})

test_that("wide materialization uses bounded native protection", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    column_count <- 5500L
    input <- as.data.frame(
        stats::setNames(rep.int(list(1), column_count),
                        sprintf("v%05d", seq_len(column_count))),
        check.names = FALSE
    )
    haven::write_dta(input, path, version = 15)

    result <- read_dta(path)
    expect_identical(dim(result), c(1L, column_count))
    expect_identical(as.double(result[[column_count]]), 1)
})

test_that("date and datetime storage become native R temporal vectors", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    input <- data.frame(
        date = as.Date(c("1960-01-01", "2024-02-29")),
        instant = as.POSIXct(c("1960-01-01 00:00:00", "2024-02-29 12:34:56"),
                            tz = "UTC")
    )
    haven::write_dta(input, path, version = 15)

    actual <- read_dta(path)
    expected <- haven::read_dta(path)
    expect_equal(actual$date, expected$date)
    expect_s3_class(actual$date, "Date")
    expect_equal(actual$instant, expected$instant)
    expect_s3_class(actual$instant, "POSIXct")
    expect_identical(attr(actual$instant, "tzone"), "UTC")
})

test_that("argument and native parse failures are ordinary R errors", {
    path <- fixture("auto_v118.dta")
    expect_error(read_dta(path, encoding = "latin1"), "not supported")
    expect_error(read_dta(path, skip = -1), "non-negative")
    expect_error(read_dta(path, skip = 1.5), "whole number")
    expect_error(read_dta(path, n_max = NA_real_), "non-negative")
    expect_error(read_dta(path, n_max = 2^53 + 2), "non-negative")
    expect_error(read_dta(path, col_select = absent), "absent")

    corrupt <- tempfile(fileext = ".dta")
    on.exit(unlink(corrupt), add = TRUE)
    writeBin(as.raw(1:8), corrupt)
    expect_error(read_dta(corrupt), "header|format|small|read|I/O", ignore.case = TRUE)
})
