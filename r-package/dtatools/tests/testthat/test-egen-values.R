test_that("numeric summaries apply Stata missing rules without rounding", {
    values <- c(3, NA_real_, tagged_missing("a"), 1)
    expect_identical(dta_mean(values), 2)
    expect_identical(dta_min(values), 1)
    expect_identical(dta_max(values), 3)
    expect_identical(dta_total(values), 4)
    expect_identical(dta_max(values, missing = TRUE), tagged_missing("a"))
    expect_identical(dta_min(values, missing = TRUE), 1)
    missings <- c(tagged_missing("z"), NA_real_, tagged_missing("a"))
    expect_identical(dta_min(missings, missing = TRUE), NA_real_)
    expect_identical(dta_max(missings, missing = TRUE), tagged_missing("z"))
    for (fun in list(dta_mean, dta_min, dta_max)) {
        expect_identical(fun(missings), NA_real_)
        expect_identical(fun(numeric()), NA_real_)
    }
    expect_identical(dta_total(missings), 0)
    expect_identical(dta_total(numeric()), 0)
    expect_identical(dta_total(missings, missing = TRUE), NA_real_)
    expect_identical(dta_total(numeric(), missing = TRUE), NA_real_)
    expect_identical(dta_mean(c(TRUE, FALSE, NA)), 0.5)
    expect_identical(dta_total(c(TRUE, FALSE, NA)), 1)
    expect_identical(dta_mean(c(1, 1 + 2^-24)), 1 + 2^-25)
})

test_that("row calculations accept columns and preserve all-missing rules", {
    x <- c(1, NA, tagged_missing("a"), 2)
    y <- c(3, tagged_missing("z"), NA, NA)
    expect_identical(dta_row_max(x, y), c(3, NA_real_, NA_real_, 2))
    expect_identical(dta_row_total(x, y), c(4, 0, 0, 2))
    expect_identical(dta_row_total(x, y, missing = TRUE), c(4, NA, NA, 2))
    expect_identical(dta_row_max(list(x, y)), dta_row_max(x, y))
    expect_identical(dta_row_total(data.frame(x, y)), dta_row_total(x, y))
    expect_identical(dta_row_max(numeric(), numeric()), numeric())
    expect_identical(dta_row_total(numeric()), numeric())
    expect_identical(dta_row_total(c(TRUE, FALSE), c(1L, 2L)), c(2, 2))
})

test_that("numeric calculations validate input classes, shapes, and options", {
    for (value in list(NaN, Inf, -Inf, c(1, NaN))) {
        expect_error(dta_max(value), "NaN|infinities")
        expect_error(dta_row_total(c(1, 2), rep(value, length.out = 2)),
                     "NaN|infinities")
    }
    for (value in list("1", factor("1"), matrix(1),
                      structure(1, class = "integer64"),
                      structure(NaN, class = c("custom", "Date")),
                      as.difftime(1, units = "days"))) {
        expect_error(dta_mean(value), "numeric or logical")
        expect_error(dta_row_max(value), "numeric or logical")
    }
    expect_error(dta_row_max(), "At least one")
    expect_error(dta_row_total(list()), "At least one")
    expect_error(dta_row_max(1, c(1, 2)), "equal lengths")
    for (flag in list(NA, 1, logical(), c(TRUE, FALSE))) {
        expect_error(dta_total(1, missing = flag), "TRUE or FALSE")
    }
    for (value in c(1e308, -1e308)) {
        expect_error(dta_mean(c(value, 0)), "Stata double storage")
        expect_error(dta_row_max(value), "Stata double storage")
    }
    expect_identical(dta_max(.Machine$double.xmax / 2), .Machine$double.xmax / 2)
    expect_error(dta_max(structure(1e305, class = c("POSIXct", "POSIXt"))),
                 "Stata double storage")
})

test_that("calculations discard metadata and use encoded temporal numbers", {
    values <- dta_double(c(1, 2))
    attr(values, "label") <- "Source variable"
    attr(values, "labels") <- c(one = 1)
    expect_identical(dta_max(values), 2)
    expect_null(attributes(dta_row_max(values)))
    dates <- as.Date(c("1960-01-01", "1960-01-03"))
    times <- as.POSIXct(c("1960-01-01", "1960-01-02"), tz = "UTC")
    expect_identical(dta_mean(dates), 1)
    expect_identical(dta_max(times), 86400000)
    expect_identical(dta_row_total(dates), c(0, 2))
    typed <- dibble(dates = dates, times = times)
    expect_identical(dta_mean(typed$dates), 1)
    expect_identical(dta_max(typed$times), 86400000)
    expect_identical(dta_row_total(typed$dates, typed$dates), c(0, 4))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(typed$dates))
    attr(typed$dates, "class") <- c("custom", class(typed$dates))
    expect_error(dta_mean(typed$dates), "numeric or logical")
})

test_that("datetime calculations use the package epoch conversion order", {
    seconds <- -315619200 + c(0.0001, 0.0003, 0.0011)
    times <- structure(seconds, class = c("POSIXct", "POSIXt"), tzone = "UTC")
    expected <- (seconds + 315619200) * 1000
    typed <- dibble(times = times)
    expect_identical(dta_row_total(times), expected)
    expect_identical(dta_row_total(typed$times), expected)
    expect_identical(dta_max(times), max(expected))
    expect_identical(dta_max(typed$times), max(expected))
})

test_that("numeric calculations leave compact inputs unmaterialized", {
    data <- read_dta(fixture("auto_v118.dta"))
    value <- data$price
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    actual <- list(dta_mean(value), dta_min(value), dta_max(value),
                   dta_total(value), dta_row_max(value, value),
                   dta_row_total(value, value))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(value))
    decoded <- as.double(value)
    expect_equal(actual[[1L]], mean(decoded))
    expect_identical(actual[[2L]], min(decoded))
    expect_identical(actual[[3L]], max(decoded))
    expect_identical(actual[[4L]], sum(decoded))
    expect_identical(actual[[5L]], decoded)
    expect_identical(actual[[6L]], 2 * decoded)
})

test_that("Arrow numeric calculations preserve compact input storage", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    source <- data.frame(x = dta_int(c(2, NA, 4)),
                         y = dta_float(c(1, 3, NA)))
    save_arrow(source, path)
    data <- read_arrow(path)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$y))
    expect_identical(dta_mean(data$x), 3)
    expect_identical(dta_row_total(data), c(3, 3, 4))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$y))
})

test_that("egen calculation scope normalizes only ordinary NaN payloads", {
    evaluation <- dtatools:::.dta_egen_evaluation
    previous <- evaluation$allow_nan
    on.exit(evaluation$allow_nan <- previous, add = TRUE)
    evaluation$allow_nan <- TRUE
    expect_identical(dta_max(c(1, NaN)), 1)
    expect_identical(dta_row_total(c(NaN, 1)), c(0, 1))
    evaluation$allow_nan <- FALSE
    expect_error(dta_max(c(1, NaN)), "NaN")
})

test_that("numeric value functions compose with grouped dibble assignment", {
    withr::local_options(dtatools.generate_type = "float")
    data <- as_dibble(data.frame(group = c(1, 1, 2), value = c(1, 2, 3)))
    data[, average := dta_mean(value), by = group]
    expect_identical(as.double(data$average), c(1.5, 1.5, 3))
    expect_identical(dta_storage_type(data$average), "float")
    data[, precise := dta_double(dta_total(value)), by = group]
    expect_identical(as.double(data$precise), c(3, 3, 3))
    expect_identical(dta_storage_type(data$precise), "double")
    data[, combined := dta_row_total(value, average)]
    expect_identical(as.double(data$combined), c(2.5, 3.5, 6))
})
