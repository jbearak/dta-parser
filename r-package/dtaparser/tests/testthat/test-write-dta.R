test_that("write_dta writes a typed release-118 dataset and returns its input invisibly", {
    data <- data.frame(
        answer = stata_byte(c(-5, tagged_missing("a"))),
        stringsAsFactors = FALSE
    )
    attr(data, "label") <- "writer tracer bullet"
    var_label(data$answer) <- "the answer"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_invisible(expect_identical(write_dta(data, path), data))
    expect_true(file.exists(path))

    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(attr(actual, "label", exact = TRUE), "writer tracer bullet")
    expect_identical(var_label(actual$answer), "the answer")
    expect_identical(stata_storage_type(actual$answer), "byte")
    expect_identical(missing_tag(actual$answer), c(NA_character_, "a"))
    expect_identical(as.double(actual$answer[[1L]]), -5)
})

test_that("character missing values become empty strings and long values use strL", {
    data <- data.frame(
        short = c("é", NA_character_, ""),
        long = c(strrep("x", 20L), strrep("x", 20L), "different"),
        stringsAsFactors = FALSE
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_warning(
        write_dta(data, path, strl_threshold = 4L),
        class = "dtaparser_write_character_missing_warning"
    )
    actual <- read_dta(path)
    expect_identical(unname(vapply(actual$short, identity, character(1))), c("é", "", ""))
    expect_identical(unname(vapply(actual$long, identity, character(1))), data$long)
})

test_that("ordered and unordered factors become labelled long integers", {
    data <- data.frame(
        group = factor(c("b", "a", NA), levels = c("a", "b", "unused")),
        rank = ordered(c("low", "high", "low"), levels = c("low", "high"))
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_warning(
        write_dta(data, path),
        class = "dtaparser_write_factor_warning"
    )
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(stata_storage_type(actual$group), "long")
    expect_identical(as.double(actual$group), c(2, 1, NA_real_))
    expect_identical(val_labels(actual$group), c(a = 1, b = 2, unused = 3))
    expect_identical(as.double(actual$rank), c(1, 2, 1))
    expect_identical(val_labels(actual$rank), c(low = 1, high = 2))
    expect_false(is.factor(actual$group))
    expect_false(is.ordered(actual$rank))
})

test_that("unrepresentable numerics become system missing in one aggregated warning", {
    narrow <- c(1, 1.5, 101, tagged_missing("b"), Inf, NaN)
    data <- data.frame(
        narrow = narrow,
        wide = c(1, .Machine$double.xmax, -Inf, NA_real_, tagged_missing("z"), 2)
    )
    attr(data$narrow, "stata.storage") <- "byte"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    warning <- expect_warning(
        write_dta(data, path),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    expect_match(conditionMessage(warning), "`narrow` (4)", fixed = TRUE)
    expect_match(conditionMessage(warning), "`wide` (2)", fixed = TRUE)
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(as.double(actual$narrow), c(1, NA, NA, tagged_missing("b"), NA, NA))
    expect_identical(as.double(actual$wide), c(1, NA, NA, NA, tagged_missing("z"), 2))
    expect_identical(missing_tag(actual$narrow), c(NA, NA, NA, "b", NA, NA))
    expect_identical(missing_tag(actual$wide), c(NA, NA, NA, NA, "z", NA))
})

test_that("Date and POSIXct columns use Stata epochs and both timezone modes", {
    dates <- as.Date(c("1960-01-01", "1970-01-01", NA))
    times <- as.POSIXct(
        c("2020-01-01 12:00:00", "2020-07-01 12:00:00", NA),
        tz = "America/New_York"
    )
    attr(dates, "format.stata") <- "%td"
    attr(times, "format.stata") <- "%tc"
    data <- data.frame(dates = dates, times = times)
    wall_path <- tempfile(fileext = ".dta")
    instant_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(wall_path, instant_path)), add = TRUE)

    expect_silent(write_dta(data, wall_path, adjust_tz = TRUE))
    expect_silent(write_dta(data, instant_path, adjust_tz = FALSE))
    wall <- read_dta(wall_path, use_numeric_altrep = FALSE)
    instant <- read_dta(instant_path, use_numeric_altrep = FALSE)

    expect_identical(as.double(wall$dates), as.double(dates))
    expect_identical(attr(wall$dates, "format.stata"), "%td")
    expect_equal(
        as.double(wall$times),
        as.double(as.POSIXct(
            c("2020-01-01 12:00:00", "2020-07-01 12:00:00", NA),
            tz = "UTC"
        )),
        tolerance = 1e-9
    )
    expect_equal(as.double(instant$times), as.double(times), tolerance = 1e-9)
    expect_identical(attr(wall$times, "tzone"), "UTC")
})

test_that("value labels and ordered dataset notes round-trip", {
    x <- stata_long(c(-1, 1, tagged_missing("c"), NA_real_))
    val_labels(x) <- c(
        missing_c = tagged_missing("c"), positive = 1, negative = -1
    )
    data <- data.frame(x = x)
    attr(data, "notes") <- c("first", "", "third")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(attr(actual, "notes", exact = TRUE), c("first", "", "third"))
    expect_identical(
        val_labels(actual$x),
        c(negative = -1, positive = 1, missing_c = tagged_missing("c"))
    )
})

test_that("empty value-label text from source metadata round-trips", {
    x <- stata_int(c(1201, 1213))
    attr(x, "labels") <- stats::setNames(c(1201, 1213), c("", ""))
    attr(x, "class") <- c(
        "stata_numeric", "stata_int", "haven_labelled", "vctrs_vctr", "double"
    )
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(attr(actual, "labels", exact = TRUE),
                     stats::setNames(c(1201, 1213), c("", "")))
    expect_s3_class(actual, "haven_labelled")
})

test_that("an attached empty value-label table round-trips", {
    x <- stata_double(c(1, 2))
    attr(x, "labels") <- stats::setNames(double(), character())
    attr(x, "class") <- c(
        "stata_numeric", "stata_double", "haven_labelled", "vctrs_vctr",
        "double"
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data.frame(x = x), path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(
        attr(actual, "labels", exact = TRUE),
        stats::setNames(double(), character())
    )
    expect_s3_class(actual, "haven_labelled")
})

test_that("duplicate value-label keys from source metadata round-trip stably", {
    x <- stata_byte(c(tagged_missing("a"), tagged_missing("b")))
    attr(x, "labels") <- c(
        `Don't know` = tagged_missing("b"),
        Refused = tagged_missing("a"),
        `Not ascertained` = tagged_missing("a")
    )
    attr(x, "class") <- c(
        "stata_numeric", "stata_byte", "haven_labelled", "vctrs_vctr", "double"
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data.frame(x = x), path))
    actual <- attr(read_dta(path)$x, "labels", exact = TRUE)
    expect_identical(names(actual), c("Refused", "Not ascertained", "Don't know"))
    expect_identical(unname(missing_tag(actual)), c("a", "a", "b"))
})

test_that("value-label text limits count UTF-8 bytes before touching the destination", {
    x <- stata_long(1)
    attr(x, "labels") <- stats::setNames(1, strrep("é", 16001L))
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    sentinel <- charToRaw("existing destination")
    writeBin(sentinel, path)
    on.exit(unlink(path), add = TRUE)

    expect_error(
        write_dta(data, path),
        class = "dtaparser_write_validation_error"
    )
    expect_identical(readBin(path, "raw", n = file.info(path)$size), sentinel)
})

test_that("warnings promoted to errors leave an existing destination unchanged", {
    data <- data.frame(x = factor("a"))
    path <- tempfile(fileext = ".dta")
    sentinel <- charToRaw("existing destination")
    writeBin(sentinel, path)
    on.exit(unlink(path), add = TRUE)
    previous <- options(warn = 2)
    on.exit(options(previous), add = TRUE)

    expect_error(write_dta(data, path), "factor columns", ignore.case = TRUE)
    expect_identical(readBin(path, "raw", n = file.info(path)$size), sentinel)
})

test_that("extensionless output appends .dta with one classed warning", {
    data <- data.frame(x = 1L)
    base <- tempfile(pattern = "dtaparser-extensionless-write-")
    path <- paste0(base, ".dta")
    on.exit(unlink(c(base, path)), add = TRUE)

    expect_warning(
        write_dta(data, base),
        class = "dtaparser_write_extension_warning"
    )
    expect_false(file.exists(base))
    expect_true(file.exists(path))
    expect_identical(nrow(read_dta(base)), 1L)
})

test_that("unsupported columns are reported together with their classes", {
    data <- data.frame(ok = 1:2)
    data$list_col <- I(list(1, 2))
    data$duration <- as.difftime(c(1, 2), units = "hours")
    data$custom <- structure(c(1, 2), class = "mystery_measure")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    error <- expect_error(
        write_dta(data, path),
        class = "dtaparser_write_validation_error"
    )
    message <- conditionMessage(error)
    expect_true(all(vapply(
        c("list_col", "AsIs", "duration", "difftime", "custom", "mystery_measure"),
        grepl, logical(1), x = message, fixed = TRUE
    )))
    expect_false(file.exists(path))
})

test_that("dependency-free haven_labelled-compatible vectors are supported", {
    x <- structure(
        c(1, 2, tagged_missing("a")),
        labels = c(One = 1, Two = 2),
        class = c("haven_labelled", "vctrs_vctr", "double")
    )
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(as.double(actual), c(1, 2, tagged_missing("a")))
    expect_identical(val_labels(actual), c(One = 1, Two = 2))
})

test_that("haven opens dtaparser output with matching values and metadata", {
    skip_if_not_installed("haven")
    x <- c(1, 2, tagged_missing("a"), NA_real_)
    attr(x, "labels") <- c(One = 1, Two = 2)
    data <- data.frame(x = x, text = c("é", "", "long text", "long text"))
    attr(data, "label") <- "haven compatibility"
    attr(data, "notes") <- c("first note", "second note")
    var_label(data$x) <- "coded value"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path, strl_threshold = 4L))
    actual <- haven::read_dta(path)
    expect_identical(attr(actual, "label", exact = TRUE), "haven compatibility")
    # haven exposes Stata's internal note0 count characteristic; Stata and
    # dtaparser treat it as metadata rather than a user note.
    expect_identical(tail(attr(actual, "notes", exact = TRUE), 2L), c("first note", "second note"))
    expect_identical(attr(actual$x, "label", exact = TRUE), "coded value")
    expect_identical(haven::na_tag(actual$x), c(NA, NA, "a", NA))
    expect_identical(unname(attr(actual$x, "labels")), c(1, 2))
    expect_identical(as.character(actual$text), data$text)
})

test_that("zero-row data frames with columns are supported", {
    data <- data.frame(x = integer(), text = character())
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path)
    expect_identical(dim(actual), c(0L, 2L))
    expect_identical(names(actual), names(data))
})

test_that("malformed and storage-incompatible explicit display formats fail", {
    cases <- list(
        numeric_string = structure(1, format.stata = "%9s"),
        string_numeric = structure("x", format.stata = "%8.0g"),
        malformed = structure(1, format.stata = "not-a-format"),
        date_numeric = structure(as.Date("2020-01-01"), format.stata = "%9.0g")
    )
    for (name in names(cases)) {
        path <- tempfile(fileext = ".dta")
        expect_error(
            write_dta(data.frame(x = cases[[name]]), path),
            "format",
            info = name
        )
        expect_false(file.exists(path), info = name)
    }
})

test_that("numeric Stata calendar formats that remain numeric are preserved", {
    x <- stata_int(c(0, 1, NA_real_))
    attr(x, "format.stata") <- "%tmcY_m"
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(as.double(actual), c(0, 1, NA_real_))
    expect_identical(attr(actual, "format.stata", exact = TRUE), "%tmcY_m")
    expect_false(inherits(actual, c("Date", "POSIXct")))
})
