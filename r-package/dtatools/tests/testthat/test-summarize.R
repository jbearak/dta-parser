test_that("summary aliases and vector/data-frame calls share one interface", {
    expect_identical(summarise, summarize)
    expect_identical(summ, summarize)
    expect_true(all(c("summarize", "summarise", "summ") %in%
        getNamespaceExports("dtatools")))
    d <- data.frame(x = c(1, 2, 3, NA), y = c(4, NA, 6, 8))
    expected <- summarize(d)$statistics
    expect_equal(summarize(data = d)$statistics, expected)
    expect_equal(summarize(x, y, data = d)$statistics, expected)
    expect_equal(summarize(d, x:y)$statistics, expected)
    direct <- summarize(x = d$x, y = d$y)$statistics
    direct$variable[1L] <- "x"
    expect_equal(direct, expected)
    expect_equal(summarize(list(x = d$x, y = d$y))$statistics, expected)
    expect_equal(summarize(d$x)$r$N, 3)
    expect_equal(summarize(d, "x-y")$statistics, expected)
    expect_equal(summarize(d, tidyselect::all_of(c("x", "y")))$statistics, expected)
    expect_equal(expected$N, c(3, 3))
    expect_equal(expected$mean, c(2, 6))
    expect_error(summarize(), "nothing to summarize")
    expect_error(summarize(1:2, 1:3), "equal lengths")
    expect_error(summarize(d, absent), "[Uu]nknown|not found|does not exist")
})

test_that("where and rows select each group's calculation sample", {
    d <- data.frame(x = c(1, 2, 3, 5, 7, 9), g = c(2, 1, 2, 1, 2, 1),
        w = 1:6)
    result <- summarize(d, x, where = .n <= 2, by = g, weights = w,
        detail = TRUE)
    expect_equal(result$statistics$N, c(2, 2))
    expect_equal(as.double(result$groups$g), c(2, 1))
    expect_equal(result$statistics$mean, c(2.5, 4))
    expect_equal(summarize(d, x, rows = 2:3, by = g)$statistics$sum, c(10, 14))
    expect_equal(summarize(d, x, where = ~ x > 5, rows = 1:5)$r$sum, 7)
    expect_equal(summarize(d, x, where = c(TRUE, FALSE, NA, TRUE, FALSE, FALSE))$r$N, 2)
    expect_error(summarize(d, x, by = g, rows = 4), "beyond")
    expect_error(summarize(d, x, rows = c(1, 1)), "unique")
    expect_error(summarize(d, x, weights = c(1, 2)), "group row count")
})

test_that("summary grouping preserves Stata missing identities and dplyr groups", {
    d <- dibble(x = 1:6, g = c(NA_real_, tagged_missing("a"),
        tagged_missing("z"), NA_real_, tagged_missing("a"), tagged_missing("z")))
    original <- copy_data(d)
    result <- summarize(d, x, by = g)
    expect_equal(result$statistics$N, rep(2, 3))
    expect_equal(result$statistics$sum, c(5, 7, 9))
    expect_identical(missing_tag(result$groups$g), c(NA_character_, "a", "z"))
    expect_identical(datasig(d), datasig(original))
    ordinary <- data.frame(x = as.double(d$x), g = as.double(d$g))
    expect_equal(summarize(ordinary, x, by = g)$statistics, result$statistics)
    strings <- summarize(data.frame(x = 1:3, g = c("", NA, "a")), x, by = g)
    expect_equal(strings$statistics$N, c(2, 1))
    expect_identical(strings$groups$g, c("", "a"))
    skip_if_not_installed("dplyr", "1.2.1")
    grouped <- dplyr::group_by(d, g)
    expect_equal(summarize(grouped, x)$statistics, result$statistics)
    expect_error(summarize(grouped, x, by = g), "group")
    expect_equal(as.double(dplyr::summarise(grouped, total = sum(x))$total), c(5, 7, 9))
})

test_that("summary temporals contribute Stata codes and missing values are excluded", {
    dates <- as.Date(c("1960-01-01", "1960-01-03", NA))
    times <- as.POSIXct(c("1960-01-01 00:00:00", "1960-01-01 00:00:02", NA), tz = "UTC")
    expect_equal(summarize(dates)$r$mean, 1)
    expect_equal(summarize(times)$r$mean, 1000)
    x <- dta_double(c(1, 3, NA_real_, tagged_missing(letters)))
    expect_equal(summarize(x)$r$N, 2)
    expect_equal(summarize(x)$r$mean, 2)
    expect_error(summarize(c(1, Inf)), "finite")
    expect_error(summarize(factor(c("a", "b"))), "numeric")
    expect_error(summarize(matrix(1:4, 2)), "numeric")
})

test_that("summary flags, empty samples, and quiet results are validated", {
    expect_false(withVisible(summarize(1:3, meanonly = TRUE))$visible)
    expect_true(withVisible(summarize(1:3))$visible)
    expect_false("Var" %in% names(summarize(1:3, meanonly = TRUE)$r))
    expect_error(summarize(1:3, detail = TRUE, meanonly = TRUE), "may not")
    expect_error(summarize(1:3, detail = TRUE, nofvlabel = TRUE), "display options")
    expect_error(summarize(1:3, detail = TRUE, fvwrap = 1), "display options")
    expect_error(summarize(1:3, detail = NA), "TRUE or FALSE")
    expect_identical(format(summarize(1:3, separator = -1)),
                     format(summarize(1:3, separator = 1)))
    expect_error(summarize(1:3, fvwrap = 1.5), "integer")
    expect_error(summarize(1:3, weights = Inf), "finite")
    expect_equal(summarize(numeric())$r, list(N = 0, sum_w = 0, sum = 0))
    expect_equal(summarize(data.frame(x = numeric()))$r,
        list(N = 0, sum_w = 0, sum = 0))
    expect_equal(nrow(summarize(data.frame())$statistics), 0)
    # Native `clear; summarize` succeeds without leaving r() scalars.
    expect_identical(summarize(data.frame())$r, list())
    expect_identical(summarize(data.frame(row.names = 1:3))$r, list())
    grouped_empty <- summarize(data.frame(x = numeric(), g = numeric()), x, by = g)
    expect_equal(nrow(grouped_empty$statistics), 0)
    expect_identical(names(grouped_empty$groups), "g")
    expect_identical(grouped_empty$r, list())
})

test_that("factor summaries retain hidden results and expand levels within groups", {
    d <- data.frame(g = c(1, 1, 2, 2), category = c(1, 2, 2, 3))
    result <- summarize(d, "i.category", by = g)
    expect_identical(result$statistics$variable,
        c("1.category", "2.category", "2.category", "3.category"))
    expect_equal(result$statistics$mean, rep(.5, 4))
    base <- summarize(d, "ib3.category")
    expect_identical(base$display, c(TRUE, TRUE, FALSE))
    expect_equal(base$r$mean, 0)
    expect_true(all(summarize(d, "ib3.category", detail = TRUE)$display))
    expect_equal(nrow(summarize(d, tidyselect::all_of(character()))$statistics), 0)
    expect_identical(summarize(d, tidyselect::all_of(character()))$r, list())
    weighted <- data.frame(category = c(0, 1, 1), w = c(100, 1, 1))
    base <- summarize(weighted, "ib(freq).category", weights = w,
        allbaselevels = TRUE)
    expect_identical(base$statistics$variable, c("0b.category", "1.category"))
})

test_that("summaries accept haven-compatible columns and evaluate vectors once", {
    x <- labelled_for_test(c(1, 2, NA_real_), c(First = 1, Second = 2))
    expect_equal(summarize(x)$r$mean, 1.5)
    called <- 0L
    value <- function() {
        called <<- called + 1L
        c(1, 2, 3)
    }
    expect_equal(summarize(value())$r$mean, 2)
    expect_equal(called, 1L)
})
