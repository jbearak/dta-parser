test_that("tab is exported and returns ordinary table objects", {
    expect_true("tab" %in% getNamespaceExports("dtatools"))
    expect_identical(
        names(formals(tab)),
        c("x", "...", "data", "missing", "display")
    )

    x <- c(2, 1, 2, 3)
    y <- c("b", "a", "a", "b")
    expect_identical(tab(x), table(x))
    expect_identical(tab(x, y), table(x, y))
    expect_s3_class(tab(x), "table")

    list_x <- list(first = x, second = y)
    expect_identical(tab(list_x), table(list_x))
    expect_identical(tab(list(x, y)), table(list(x, y)))

    factor_x <- factor(c("b", "a", "b"), levels = c("b", "a", "unused"))
    expect_identical(tab(factor_x), table(factor_x))
    expect_identical(
        tab(factor_x, missing = TRUE),
        table(factor_x, useNA = "ifany")
    )
    xtab <- stats::xtabs(~ x + y)
    expect_identical(as.vector(tab(x, y)), as.vector(xtab))
    expect_identical(dimnames(tab(x, y)), dimnames(xtab))

    dates <- as.Date(c("2025-01-02", "2025-01-01", NA))
    expect_identical(
        dimnames(tab(dates, missing = TRUE))[[1L]],
        c("2025-01-01", "2025-01-02", ".")
    )
})

test_that("tab supports data frames and pipes", {
    data <- data.frame(
        status = c(1, 1, 2, 2),
        region = c("north", "south", "north", "south")
    )
    expected <- table(data)

    expect_identical(tab(data), expected)
    expect_identical(tab(data = data), expected)
    expect_identical(tab(status, region, data = data), expected)
    expect_identical(data |> tab(status, region), expected)
    expect_identical(
        data |> dplyr::select(status, region) |> tab(),
        expected
    )
    expect_identical(
        dplyr::`%>%`(data, tab(status, region)),
        expected
    )
    expect_identical(tab(first = data$status), table(first = data$status))
    expect_identical(data$status |> tab(), table(data$status))

    missing_column <- data$status
    expect_error(tab(missing_column, data = data), "unknown column")

    duplicated <- data.frame(first = 1:2, second = 3:4)
    names(duplicated) <- c("status", "status")
    expect_error(
        tab(status, data = duplicated),
        "ambiguous because its name is duplicated"
    )
})

test_that("labelled temporal vectors match Stata codes and format fallbacks", {
    dates <- as.Date(c("1960-01-01", "1960-01-02"))
    attr(dates, "format.stata") <- "%td"
    attr(dates, "labels") <- c(Origin = 0)
    expect_identical(
        dimnames(tab(dates))[[1L]],
        c("Origin", "1960-01-02")
    )

    datetimes <- as.POSIXct(
        c("1960-01-01 00:00:00", "1960-01-01 00:00:01"),
        tz = "UTC"
    )
    attr(datetimes, "format.stata") <- "%tc"
    attr(datetimes, "labels") <- c(Epoch = 0)
    expect_identical(
        dimnames(tab(datetimes))[[1L]],
        c("Epoch", "1960-01-01 00:00:01")
    )
})

test_that("missing modes distinguish every numeric payload", {
    x <- c(2, 1, NA_real_, tagged_missing(letters), NaN)
    expected_levels <- c("1", "2", ".", paste0(".", letters), "NaN")

    expect_identical(as.vector(tab(x)), c(1L, 1L))
    distinguished <- tab(x, missing = TRUE, display = "value")
    expect_identical(dimnames(distinguished)[[1L]], expected_levels)
    expect_identical(as.vector(distinguished), rep(1L, 30L))
    expect_identical(
        distinguished,
        tab(x, missing = "distinguish", display = "value")
    )
    expect_identical(tab(x, missing = FALSE), tab(x, missing = "exclude"))

    combined <- tab(x, missing = "combine", display = "value")
    expect_identical(as.vector(combined), c(1L, 1L, 28L))
    expect_true(is.na(dimnames(combined)[[1L]][[3L]]))

    transformed <- -tagged_missing(c("a", "z"))
    expect_identical(
        dimnames(tab(transformed, missing = TRUE))[[1L]],
        c(".a", ".z")
    )
})

test_that("labels apply to observed and missing values without adding levels", {
    x <- labelled_for_test(
        c(
            2, 1, 2, 4, NA_real_,
            tagged_missing(c("a", "b")), NaN
        ),
        c(
            Yes = 1,
            Yes = 2,
            Unused = 3,
            Refused = tagged_missing("a"),
            Numeric = 4
        )
    )

    labelled <- tab(x, missing = TRUE)
    expect_identical(
        dimnames(labelled)[[1L]],
        c("Yes [1]", "Yes [2]", "Numeric", ".", "Refused", ".b", "NaN")
    )
    expect_false("Unused" %in% dimnames(labelled)[[1L]])

    values <- tab(x, missing = TRUE, display = "value")
    expect_identical(
        dimnames(values)[[1L]],
        c("1", "2", "4", ".", ".a", ".b", "NaN")
    )

    both <- tab(x, missing = TRUE, display = "both")
    expect_identical(
        dimnames(both)[[1L]],
        c(
            "[1] Yes", "[2] Yes", "[4] Numeric", ".", "[.a] Refused",
            ".b", "NaN"
        )
    )
})

test_that("cross-tabs handle labelled and ordinary vectors in either order", {
    labelled <- labelled_for_test(
        c(1, 2, 1, tagged_missing("a")),
        c(Yes = 1, No = 2)
    )
    ordinary <- c("a", "a", "b", "b")

    forward <- tab(labelled, ordinary, missing = TRUE)
    reverse <- tab(ordinary, labelled, missing = TRUE)
    expect_identical(dimnames(forward)[[1L]], c("Yes", "No", ".a"))
    expect_identical(dimnames(forward)[[2L]], c("a", "b"))
    expect_identical(unname(forward), aperm(unname(reverse), c(2L, 1L)))
})

test_that("tab preserves source values and metadata", {
    x <- labelled_for_test(
        c(1, NA_real_, tagged_missing("a")),
        c(One = 1, Refused = tagged_missing("a")),
        label = "Response"
    )
    attr(x, "format.stata") <- "%8.0g"
    before <- x

    invisible(tab(x, missing = TRUE, display = "both"))
    expect_identical(x, before)
})

test_that("tab handles imported labelled ALTREP columns", {
    input <- fixture("auto_v118.dta")
    data <- read_dta(input)
    before <- data$foreign
    expect_true(dtatools:::.is_numeric_altrep(data$foreign))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$foreign))

    result <- data |> tab(foreign)
    expect_identical(dimnames(result)[[1L]], c("Domestic", "Foreign"))
    expect_identical(sum(result), nrow(data))
    expect_identical(data$foreign, before)
    expect_true(dtatools:::.is_numeric_altrep(data$foreign))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$foreign))

    subset <- data$foreign[c(1L, 2L, 1L)]
    expect_identical(sum(tab(subset)), length(subset))

    filtered <- dplyr::filter(data, mpg > stats::median(mpg))
    filtered_result <- filtered |> tab(foreign)
    expect_identical(
        dimnames(filtered_result)[[1L]],
        c("Domestic", "Foreign")
    )
    expect_identical(sum(filtered_result), nrow(filtered))
})

test_that("tab distinguishes all missing codes read by dtatools", {
    path <- fixture_with_all_numeric_missing_codes(
        "missing_values_v118.dta"
    )
    on.exit(unlink(path), add = TRUE)
    data <- read_dta(path, n_max = 27)
    storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")
    numeric_indices <- which(storage != "character")
    expected <- c(".", paste0(".", letters))

    for (index in numeric_indices) {
        info <- storage[[index]]
        result <- tab(data[[index]], missing = TRUE, display = "value")
        expect_identical(dimnames(result)[[1L]], expected, info = info)
        expect_identical(as.vector(result), rep(1L, 27L), info = info)
    }
})

test_that("tab validates its arguments", {
    expect_error(tab(), "nothing to tabulate")
    expect_error(tab(1:3, missing = NA), "`missing`")
    expect_error(tab(1:3, missing = "sometimes"), "arg")
    expect_error(tab(1:3, display = "names"), "arg")
    expect_error(tab(x, data = 1:3), "data frame")
    expect_error(tab(1:3, letters[1:2]), "same length")
})
