test_that("summ is exported without masking dplyr summary functions", {
    exports <- getNamespaceExports("dtatools")
    expect_true("summ" %in% exports)
    expect_false(any(c("summarize", "summarise") %in% exports))
})

test_that("summ accepts vector and data-frame calls", {
    d <- data.frame(x = c(1, 2, 3, NA), y = c(4, NA, 6, 8))
    expected <- summ(d)$statistics
    expect_equal(summ(data = d)$statistics, expected)
    expect_equal(summ(x, y, data = d)$statistics, expected)
    expect_equal(summ(d, x:y)$statistics, expected)
    direct <- summ(x = d$x, y = d$y)$statistics
    direct$variable[1L] <- "x"
    expect_equal(direct, expected)
    expect_equal(summ(list(x = d$x, y = d$y))$statistics, expected)
    expect_equal(summ(d$x)$r$N, 3)
    expect_equal(summ(d, "x-y")$statistics, expected)
    expect_equal(summ(d, tidyselect::all_of(c("x", "y")))$statistics, expected)
    expect_equal(expected$N, c(3, 3))
    expect_equal(expected$mean, c(2, 6))
    expect_error(summ(), "nothing to summarize")
    expect_error(summ(1:2, 1:3), "equal lengths")
    expect_error(summ(d, absent), "[Uu]nknown|not found|does not exist")
})

test_that("where and rows select each group's calculation sample", {
    d <- data.frame(x = c(1, 2, 3, 5, 7, 9), g = c(2, 1, 2, 1, 2, 1),
        w = 1:6)
    result <- summ(d, x, where = .n <= 2, by = g, weights = w,
        detail = TRUE)
    expect_equal(result$statistics$N, c(2, 2))
    expect_equal(as.double(result$groups$g), c(2, 1))
    expect_equal(result$statistics$mean, c(2.5, 4))
    expect_equal(summ(d, x, rows = 2:3, by = g)$statistics$sum, c(10, 14))
    expect_equal(summ(d, x, where = ~ x > 5, rows = 1:5)$r$sum, 7)
    expect_equal(summ(d, x, where = c(TRUE, FALSE, NA, TRUE, FALSE, FALSE))$r$N, 2)
    expect_error(summ(d, x, by = g, rows = 4), "beyond")
    expect_error(summ(d, x, rows = c(1, 1)), "unique")
    expect_error(summ(d, x, weights = c(1, 2)), "group row count")
})

test_that("grouped summaries slice only the columns their expressions read", {
    slices <- local_slice_probe(1:6)
    d <- data.frame(x = c(1, 2, 3, 5, 7, 9), g = c(2, 1, 2, 1, 2, 1),
        w = 1:6)
    expected <- summ(d, x, by = g, where = x > 1, weights = w)
    d$probe <- slices$column
    expect_identical(summ(d, x, by = g)$statistics,
        summ(d[c("x", "g")], x, by = g)$statistics)
    expect_identical(summ(d, x, by = g, where = x > 1, weights = w)$statistics,
        expected$statistics)
    expect_identical(slices$count(), 0L)
    expect_equal(summ(d, x, by = g, where = probe > 2L,
        weights = as.integer(probe))$statistics$N, c(2, 2))
    expect_identical(slices$count(), 2L)
})

test_that("summary grouping preserves Stata missing identities and dplyr groups", {
    d <- dibble(x = 1:6, g = c(NA_real_, tagged_missing("a"),
        tagged_missing("z"), NA_real_, tagged_missing("a"), tagged_missing("z")))
    original <- copy_data(d)
    result <- summ(d, x, by = g)
    expect_equal(result$statistics$N, rep(2, 3))
    expect_equal(result$statistics$sum, c(5, 7, 9))
    expect_identical(missing_tag(result$groups$g), c(NA_character_, "a", "z"))
    expect_identical(datasig(d), datasig(original))
    ordinary <- data.frame(x = as.double(d$x), g = as.double(d$g))
    expect_equal(summ(ordinary, x, by = g)$statistics, result$statistics)
    strings <- summ(data.frame(x = 1:3, g = c("", NA, "a")), x, by = g)
    expect_equal(strings$statistics$N, c(2, 1))
    expect_identical(strings$groups$g, c("", "a"))
    skip_if_not_installed("dplyr", "1.2.1")
    grouped <- dplyr::group_by(d, g)
    expect_equal(summ(grouped, x)$statistics, result$statistics)
    expect_error(summ(grouped, x, by = g), "group")
    expect_equal(as.double(dplyr::summarise(grouped, total = sum(x))$total), c(5, 7, 9))
})

test_that("summary temporals contribute Stata codes and missing values are excluded", {
    dates <- as.Date(c("1960-01-01", "1960-01-03", NA))
    times <- as.POSIXct(c("1960-01-01 00:00:00", "1960-01-01 00:00:02", NA), tz = "UTC")
    expect_equal(summ(dates)$r$mean, 1)
    expect_equal(summ(times)$r$mean, 1000)
    x <- dta_double(c(1, 3, NA_real_, tagged_missing(letters)))
    expect_equal(summ(x)$r$N, 2)
    expect_equal(summ(x)$r$mean, 2)
    expect_error(summ(c(1, Inf)), "finite")
    expect_error(summ(factor(c("a", "b"))), "numeric")
    expect_error(summ(matrix(1:4, 2)), "numeric")
})

test_that("summary flags, empty samples, and quiet results are validated", {
    expect_false(withVisible(summ(1:3, meanonly = TRUE))$visible)
    expect_true(withVisible(summ(1:3))$visible)
    expect_false("Var" %in% names(summ(1:3, meanonly = TRUE)$r))
    expect_error(summ(1:3, detail = TRUE, meanonly = TRUE), "may not")
    expect_error(summ(1:3, detail = TRUE, nofvlabel = TRUE), "display options")
    expect_error(summ(1:3, detail = TRUE, fvwrap = 1), "display options")
    expect_error(summ(1:3, detail = NA), "TRUE or FALSE")
    expect_identical(format(summ(1:3, separator = -1)),
                     format(summ(1:3, separator = 1)))
    expect_error(summ(1:3, fvwrap = 1.5), "integer")
    expect_error(summ(1:3, weights = Inf), "finite")
    expect_equal(summ(numeric())$r, list(N = 0, sum_w = 0, sum = 0))
    expect_equal(summ(data.frame(x = numeric()))$r,
        list(N = 0, sum_w = 0, sum = 0))
    expect_equal(nrow(summ(data.frame())$statistics), 0)
    # Native `clear; summarize` succeeds without leaving r() scalars.
    expect_identical(summ(data.frame())$r, list())
    expect_identical(summ(data.frame(row.names = 1:3))$r, list())
    grouped_empty <- summ(data.frame(x = numeric(), g = numeric()), x, by = g)
    expect_equal(nrow(grouped_empty$statistics), 0)
    expect_identical(names(grouped_empty$groups), "g")
    expect_identical(grouped_empty$r, list())
})

test_that("factor summaries retain hidden results and expand levels within groups", {
    d <- data.frame(g = c(1, 1, 2, 2), category = c(1, 2, 2, 3))
    result <- summ(d, "i.category", by = g)
    expect_identical(result$statistics$variable,
        c("1.category", "2.category", "2.category", "3.category"))
    expect_equal(result$statistics$mean, rep(.5, 4))
    base <- summ(d, "ib3.category")
    expect_identical(base$display, c(TRUE, TRUE, FALSE))
    expect_equal(base$r$mean, 0)
    expect_true(all(summ(d, "ib3.category", detail = TRUE)$display))
    expect_equal(nrow(summ(d, tidyselect::all_of(character()))$statistics), 0)
    expect_identical(summ(d, tidyselect::all_of(character()))$r, list())
    weighted <- data.frame(category = c(0, 1, 1), w = c(100, 1, 1))
    base <- summ(weighted, "ib(freq).category", weights = w,
        allbaselevels = TRUE)
    expect_identical(base$statistics$variable, c("0b.category", "1.category"))
})

test_that("summaries accept haven-compatible columns and evaluate vectors once", {
    x <- labelled_for_test(c(1, 2, NA_real_), c(First = 1, Second = 2))
    expect_equal(summ(x)$r$mean, 1.5)
    called <- 0L
    value <- function() {
        called <<- called + 1L
        c(1, 2, 3)
    }
    expect_equal(summ(value())$r$mean, 2)
    expect_equal(called, 1L)
})
