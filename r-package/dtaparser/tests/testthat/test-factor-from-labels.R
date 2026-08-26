test_that("factor_from_labels has an ordinary factor interface", {
    expect_true("factor_from_labels" %in% getNamespaceExports("dtaparser"))
    expect_identical(
        names(formals(factor_from_labels)),
        c("x", "missing", "display", "drop_unused", "ordered")
    )

    x <- structure(
        c(second = 2, first = 1, second_again = 2, numeric = 4),
        labels = c(Yes = 1, Yes = 2, Unused = 3, Numeric = 4),
        label = "Response",
        format.stata = "%8.0g",
        provenance = "imported",
        class = c("haven_labelled", "vctrs_vctr", "double")
    )

    expect_no_warning(actual <- factor_from_labels(x))
    expect_identical(
        list(
            values = as.character(actual),
            levels = levels(actual),
            names = names(actual),
            variable_label = attr(actual, "label", exact = TRUE),
            value_labels = attr(actual, "labels", exact = TRUE),
            stata_format = attr(actual, "format.stata", exact = TRUE),
            provenance = attr(actual, "provenance", exact = TRUE),
            classes = class(actual)
        ),
        list(
            values = c("Yes [2]", "Yes [1]", "Yes [2]", "Numeric"),
            levels = c("Yes [1]", "Yes [2]", "Unused", "Numeric"),
            names = names(x),
            variable_label = "Response",
            value_labels = NULL,
            stata_format = NULL,
            provenance = NULL,
            classes = "factor"
        )
    )
})

test_that("factor_from_labels controls unused levels, display, and ordering", {
    x <- structure(
        c(2, 1, 4),
        labels = c(Yes = 1, Yes = 2, Unused = 3, Numeric = 4)
    )

    expect_identical(
        levels(factor_from_labels(x, drop_unused = TRUE)),
        c("Yes [1]", "Yes [2]", "Numeric")
    )
    expect_identical(
        levels(factor_from_labels(x, display = "value")),
        c("1", "2", "3", "4")
    )
    expect_identical(
        levels(factor_from_labels(x, display = "both")),
        c("[1] Yes", "[2] Yes", "[3] Unused", "[4] Numeric")
    )
    expect_s3_class(factor_from_labels(x, ordered = TRUE), "ordered")
})

test_that("factor_from_labels matches installed haven on its simple seam", {
    skip_if_not_installed("haven")
    x <- haven::labelled(c(2, 1, 2), c(Yes = 1, No = 2))

    ours <- factor_from_labels(x)
    theirs <- haven::as_factor(x)

    expect_identical(as.character(ours), as.character(theirs))
    expect_identical(levels(ours), levels(theirs))
})

test_that("factor_from_labels does not invent non-Stata missing tags", {
    skip_if_not_installed("haven")
    invalid_tag <- haven::tagged_na("?")

    actual <- factor_from_labels(
        invalid_tag,
        missing = TRUE,
        display = "value"
    )

    expect_identical(levels(actual), "NaN")
    expect_identical(as.character(actual), "NaN")
})

test_that("factor_from_labels applies Stata missing-value semantics", {
    x <- structure(
        c(1, NA_real_, tagged_missing("a"), tagged_missing("b"), NaN),
        labels = c(
            One = 1,
            Refused = tagged_missing("a"),
            Unused = tagged_missing("z")
        )
    )

    excluded <- factor_from_labels(x)
    expect_identical(levels(excluded), "One")
    expect_identical(is.na(excluded), c(FALSE, rep(TRUE, 4L)))
    expect_identical(excluded, factor_from_labels(x, missing = "exclude"))

    distinguished <- factor_from_labels(x, missing = TRUE)
    expect_identical(
        levels(distinguished),
        c("One", ".", "Refused", ".b", "Unused", "NaN")
    )
    expect_identical(
        as.character(distinguished),
        c("One", ".", "Refused", ".b", "NaN")
    )
    expect_identical(
        distinguished,
        factor_from_labels(x, missing = "distinguish")
    )
    expect_identical(
        levels(factor_from_labels(x, missing = TRUE, drop_unused = TRUE)),
        c("One", ".", "Refused", ".b", "NaN")
    )
})

test_that("factor_from_labels supports unlabelled numeric vectors", {
    x <- c(third = 3L, first = 1L, missing = NA_integer_)

    actual <- factor_from_labels(x)

    expect_identical(levels(actual), c("1", "3"))
    expect_identical(as.character(actual), c("3", "1", NA_character_))
    expect_identical(names(actual), names(x))
})

test_that("factor_from_labels converts Date and POSIXct label codes", {
    dates <- as.Date(c("1960-01-01", "1960-01-02", NA))
    attr(dates, "format.stata") <- "%td"
    attr(dates, "labels") <- c(Origin = 0)
    attr(dates, "label") <- "Interview date"
    date_factor <- factor_from_labels(dates)
    expect_identical(
        list(
            values = as.character(date_factor),
            levels = levels(date_factor),
            label = attr(date_factor, "label", exact = TRUE),
            classes = class(date_factor)
        ),
        list(
            values = c("Origin", "1960-01-02", NA_character_),
            levels = c("Origin", "1960-01-02"),
            label = "Interview date",
            classes = "factor"
        )
    )

    datetimes <- as.POSIXct(
        c("1960-01-01 00:00:00", "1960-01-01 00:00:01", NA),
        tz = "UTC"
    )
    attr(datetimes, "format.stata") <- "%tc"
    attr(datetimes, "labels") <- c(Epoch = 0)
    datetime_factor <- factor_from_labels(datetimes)
    expect_identical(
        as.character(datetime_factor),
        c("Epoch", "1960-01-01 00:00:01", NA_character_)
    )
    expect_identical(
        levels(datetime_factor),
        c("Epoch", "1960-01-01 00:00:01")
    )
})

test_that("factor_from_labels matches base factor numeric ordering", {
    set.seed(20260826)
    values <- c(-Inf, -10:10 / 3, -0, 0, Inf)
    x <- sample(values, 10000L, replace = TRUE)

    expect_identical(factor_from_labels(x), factor(x))
    integers <- c(1000000L, 1L, 100000L, 200000L)
    expect_identical(factor_from_labels(integers), factor(integers))
})

test_that("factor_from_labels validates its vector and metadata boundary", {
    invalid_vectors <- list(
        logical = c(TRUE, FALSE),
        character = c("a", "b"),
        factor = factor(c("a", "b")),
        matrix = matrix(1:4, nrow = 2L),
        data_frame = data.frame(x = 1:2)
    )
    for (name in names(invalid_vectors)) {
        expect_error(
            factor_from_labels(invalid_vectors[[name]]),
            "numeric vector",
            info = name
        )
    }

    malformed <- structure(c(1, 2), labels = c(Half = 1.5))
    expect_error(factor_from_labels(malformed), "codes must")
    expect_error(factor_from_labels(1:2, missing = NA), "`missing`")
    expect_error(factor_from_labels(1:2, missing = "combine"), "arg")
    expect_error(factor_from_labels(1:2, display = "name"), "arg")
    expect_error(factor_from_labels(1:2, drop_unused = NA), "drop_unused")
    expect_error(factor_from_labels(1:2, ordered = NA), "ordered")
})

test_that("factor_from_labels warns for nonportable label metadata", {
    labels <- stats::setNames(
        as.double(seq_len(65537L)),
        rep("Label", 65537L)
    )
    names(labels)[[1L]] <- strrep("x", 32001L)
    x <- structure(1, labels = labels)

    expect_warning(
        actual <- factor_from_labels(x, drop_unused = TRUE),
        "65,537 entries.*32,001 Unicode characters"
    )
    expect_identical(as.character(actual), strrep("x", 32001L))
})

test_that("factor conversion and tabulation share compact-source semantics", {
    data <- read_dta(fixture("auto_v118.dta"))
    source <- data$foreign
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(source))

    converted <- factor_from_labels(source)
    tabled <- tab(source)

    expect_identical(levels(converted), c("Domestic", "Foreign"))
    expected <- table(factor_from_labels(source, drop_unused = TRUE))
    expect_identical(as.vector(tabled), as.vector(expected))
    expect_identical(dimnames(tabled)[[1L]], dimnames(expected)[[1L]])
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(source))
})

test_that("factor conversion handles every compact numeric missing width", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    data <- read_dta(path, n_max = 27L)
    storage <- attr(dtaparser:::.dta_metadata(path), "dta_storage")
    numeric_indices <- which(storage != "character")
    expected <- c(".", paste0(".", letters))

    for (index in numeric_indices) {
        source <- data[[index]]
        source_was_unmaterialized <-
            dtaparser:::.is_unmaterialized_numeric_altrep(source)
        actual <- factor_from_labels(
            source,
            missing = TRUE,
            display = "value"
        )
        expect_identical(levels(actual), expected, info = storage[[index]])
        expect_identical(
            as.character(actual), expected, info = storage[[index]]
        )
        expect_identical(
            dtaparser:::.is_unmaterialized_numeric_altrep(source),
            source_was_unmaterialized,
            info = storage[[index]]
        )
    }
})

test_that("compact non-Stata float NaNs follow ordinary missing semantics", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    bytes <- readBin(path, "raw", n = file.info(path)[["size"]])
    data_tag <- charToRaw("<data>")
    data_start <- grepRaw(data_tag, bytes, fixed = TRUE)[[1L]] +
        length(data_tag)
    float_start <- data_start + 15L
    bytes[float_start + 0:3] <- writeBin(
        as.integer(0x7fc00001),
        raw(),
        size = 4L,
        endian = "little"
    )
    writeBin(bytes, path)
    source <- read_dta(path, col_select = x_float, n_max = 1L)$x_float

    excluded <- factor_from_labels(source)
    distinguished <- factor_from_labels(source, missing = TRUE)

    expect_identical(levels(excluded), character())
    expect_true(is.na(excluded[[1L]]))
    expect_identical(levels(distinguished), "NaN")
    expect_identical(as.character(distinguished), "NaN")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(source))
})
