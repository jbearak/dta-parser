test_that("imported temporal columns retain storage through supported mutation", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    haven::write_dta(
        data.frame(date = as.Date(c("1960-01-01", "2020-01-01"))),
        path,
        version = 15
    )
    values <- read_dta(path)$date
    shifted <- values + 1
    selected <- dplyr::if_else(c(TRUE, FALSE), values, shifted)

    expect_s3_class(values, "Date")
    expect_s3_class(values, "stata_temporal")
    expect_s3_class(shifted, "Date")
    expect_s3_class(selected, "Date")
    expect_identical(stata_storage_type(shifted), "double")
    expect_identical(stata_storage_type(selected), "double")
    expect_identical(
        as.character(selected), c("1960-01-01", "2020-01-02")
    )
})

test_that("datetime arithmetic promotes using Stata millisecond values", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    input <- structure(
        c(-315619200L, -315619199L),
        class = c("POSIXct", "POSIXt"),
        tzone = "UTC"
    )
    haven::write_dta(data.frame(value = input), path, version = 15)
    values <- read_dta(path)$value

    expect_identical(stata_storage_type(values), "long")
    shifted <- values + 315619200
    expect_identical(stata_storage_type(shifted), "double")
    expect_identical(as.double(shifted), c(0, 1))
})

test_that("integer datetime backing round-trips fractional R seconds", {
    skip_if_not_installed("haven")
    byte_path <- fixture_with_temporal_storage("foreign", "%tc")
    int_path <- fixture_with_temporal_storage("price", "%tc")
    on.exit(unlink(c(byte_path, int_path)), add = TRUE)

    byte_value <- read_dta(byte_path)$foreign[53]
    int_value <- read_dta(int_path)$price[1]
    expect_identical(stata_storage_type(byte_value), "byte")
    expect_identical(stata_storage_type(int_value), "int")

    long_input <- structure(
        c(-315619200L, -315619199L),
        class = c("POSIXct", "POSIXt"),
        tzone = "UTC"
    )
    long_path <- tempfile(fileext = ".dta")
    haven::write_dta(data.frame(value = long_input), long_path, version = 15)
    bytes <- readBin(long_path, "raw", n = file.info(long_path)[["size"]])
    data_start <- grepRaw(charToRaw("<data>"), bytes, fixed = TRUE)[[1L]] +
        nchar("<data>")
    bytes[data_start + 0:3] <- writeBin(
        1L, raw(), size = 4L, endian = "little"
    )
    writeBin(bytes, long_path)
    on.exit(unlink(long_path), add = TRUE)

    long_values <- read_dta(long_path)$value
    expect_identical(stata_storage_type(long_values), "long")
    expect_identical(stata_storage_type(long_values[1]), "long")
    expected_first <- -315619200 + 0.001
    expect_identical(as.double(long_values[1]), expected_first)
})
