tab_summary_fixture <- function() {
    d <- data.frame(g = c(1, 1, 1, 2, 2, 3, NA), h = c(1, 1, 2, 1, 2, 2, 1),
        y = c(10, 20, 40, 50, NA, NA, 60), w = c(1, 2, 3, 4, 2, 1, 1))
    attr(d$y, "label") <- "Outcome measure"
    d
}

tab_summary_log <- function() {
    lines <- readLines(test_path("fixtures", "tabulate-summary.log"), warn = FALSE)
    commands <- grep("^\\. ", lines)
    starts <- grep("^\\. tabulate ", lines)
    lapply(starts, function(start) {
        following <- commands[commands > start]
        end <- if (length(following)) following[1L] - 1L else length(lines)
        output <- lines[seq.int(start + 1L, end)]
        output <- output[!grepl("^end of do-file", output)]
        while (length(output) && !nzchar(output[1L])) output <- output[-1L]
        while (length(output) && !nzchar(tail(output, 1L))) output <- head(output, -1L)
        list(command = sub("^\\. ", "", lines[start]), output = output)
    })
}

test_that("summary tables reproduce native Stata's printed statistics and layouts", {
    blocks <- tab_summary_log()
    position <- 0L
    stata <- function(command, result) {
        position <<- position + 1L
        expect_identical(blocks[[position]]$command, command)
        expect_identical(format(result, width = 80L), blocks[[position]]$output,
            info = command)
    }
    d <- tab_summary_fixture()
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    stata("tabulate g h, summarize(y)", tab(d, g, h, summarize = y))
    stata("tabulate g [fw=w], summarize(y)", tab(d, g, summarize = y, weights = w, weight = "fweight"))
    stata("tabulate g [aw=w], summarize(y)", tab(d, g, summarize = y, weights = w))
    stata("tabulate g h [fw=w], summarize(y)", tab(d, g, h, summarize = y, weights = w, weight = "fweight"))
    stata("tabulate g h [aw=w], summarize(y)", tab(d, g, h, summarize = y, weights = w))
    stata("tabulate g, summarize(y) means", tab(d, g, summarize = y, means = TRUE))
    stata("tabulate g, summarize(y) standard", tab(d, g, summarize = y, standard = TRUE))
    stata("tabulate g, summarize(y) freq obs", tab(d, g, summarize = y, freq = TRUE, obs = TRUE))
    stata("tabulate g, summarize(y) nofreq", tab(d, g, summarize = y, freq = FALSE))
    stata("tabulate g h, summarize(y) obs", tab(d, g, h, summarize = y, obs = TRUE))
    stata("tabulate g h, summarize(y) missing", tab(d, g, h, summarize = y, missing = TRUE))
    stata("tabulate g [fw=w], summarize(y) means", tab(d, g, summarize = y, weights = w, weight = "fweight", means = TRUE))
    stata("tabulate g [aw=w], summarize(y) freq", tab(d, g, summarize = y, weights = w, freq = TRUE))
    stata("tabulate g h, summarize(y) means standard", tab(d, g, h, summarize = y, means = TRUE, standard = TRUE))
    stata("tabulate g h, summarize(y) nomeans nostandard nofreq",
        tab(d, g, h, summarize = y, means = FALSE, standard = FALSE, freq = FALSE))
    stata("tabulate g h if g == 3, summarize(y)", tab(d, g, h, summarize = y, where = g == 3))
    attr(d$g, "label") <- "A very long label for this factor"
    attr(d$g, "labels") <- c(ABCDEFGHIJKLMNOQRSTUVWXYZABCDEFGHIJKLMNOPQRST = 1, B = 2)
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    stata("tabulate g h, summarize(y)", tab(d, g, h, summarize = y))
    d <- data.frame(g = c("ABCDEFGHIJKLMNOQRSTUVWXYZABCDEFGHIJKLMNOPQRST", "B"), h = 1:2, y = c(10, 20))
    attr(d$g, "label") <- "A long grouping label"
    attr(d$y, "label") <- "A very long outcome label with a trailing word"
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    stata("tabulate g, summarize(y) means", tab(d, g, summarize = y, means = TRUE))
    stata("tabulate g h, summarize(y)", tab(d, g, h, summarize = y))
    stata("tabulate g h, summarize(y) means", tab(d, g, h, summarize = y, means = TRUE))
    d <- data.frame(g = rep(1, 12), h = 1:12, y = 1:12)
    stata("tabulate g h, summarize(y) means", tab(d, g, h, summarize = y, means = TRUE))
    stata("tabulate g h, summarize(y) means", tab(d, g, h, summarize = y, means = TRUE))
    stata("tabulate g h, summarize(y) means wrap", tab(d, g, h, summarize = y, means = TRUE, wrap = TRUE))
    d <- data.frame(g = c(1, 1, 2), h = c("ABCDEFGHIJKLMNO", "Short", "B"), y = c(10, 20, 30))
    attr(d$h, "label") <- "A very long column heading this is"
    stata("tabulate g h, summarize(y)", tab(d, g, h, summarize = y))
    d <- data.frame(g = c(1, 1), y = c(1e100, 1e100))
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    d$y <- c(1e-100, 1e-100)
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    d <- data.frame(g = c(1, 2), h = c(1, 1), y = c(10, 20))
    attr(d$g, "labels") <- c(Same = 1, Same = 2)
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    stata("tabulate g h, summarize(y)", tab(d, g, h, summarize = y))
    d$g <- c(.1, .2)
    attr(d$g, "format.stata") <- "%9.2f"
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    d$g <- as.Date(c("2020-01-01", "2020-01-02"))
    attr(d$g, "format.stata") <- "%td"
    stata("tabulate g, summarize(y)", tab(d, g, summarize = y))
    expect_identical(position, length(blocks))
})

test_that("summary cells and margins retain native weighted moments", {
    d <- tab_summary_fixture()
    a <- tab(d, g, h, summarize = y, weights = w)
    f <- tab(d, g, h, summarize = y, weights = w, weight = "fweight")
    expect_s3_class(a, "dta_tab_summary")
    expect_equal(as.data.frame(a)$mean, c(50 / 3, 50, 40, NA))
    expect_equal(as.data.frame(a)$sd, c(20 / 3, 0, 0, NA))
    expect_equal(as.data.frame(a)$freq, c(3, 4, 3, 0))
    expect_equal(as.data.frame(a)$obs, c(2, 1, 1, 0))
    expect_equal(as.data.frame(f)$obs, as.data.frame(f)$freq)
    expect_equal(as.data.frame(f)$sd, c(sqrt(100 / 3), 0, 0, NA))
    m <- attr(a, "dta_tab_summary")$margins
    expect_equal(unname(m$mean[3, ]), c(250 / 7, 40, 37))
    expect_equal(unname(m$sd[3, ]), c(sqrt(422.448979591837), 0, sqrt(268)))
    expect_equal(unname(m$freq[3, ]), c(7, 3, 10))
    expect_equal(unname(m$obs[3, ]), c(3, 1, 4))
    expect_identical(attr(a, "r"), list())
    expect_false(any(as.data.frame(a)$g == "3"))
    expect_s3_class(a[1, ], "data.frame")
    expect_false(inherits(a[1, ], "dta_tab_summary"))
})

test_that("summary options and sample validation follow the summary command", {
    d <- tab_summary_fixture()
    expect_error(tab(d, g, summarize = y, weights = w, weight = "iweight"), "iweight")
    expect_error(tab(d, g, summarize = h, weights = w / 2, weight = "fweight"), "integers")
    expect_error(tab(d, g, summarize = "x"), "numeric")
    expect_error(tab(d, g, h, w, summarize = y), "one or two")
    expect_error(tab(d, g, summarize = y, means = NA), "means")
    expect_equal(as.data.frame(tab(d, g, summarize = y, where = w >= 2))$mean, c(30, 50))
    expect_equal(as.data.frame(tab(d, g, summarize = y, rows = 1:2))$mean, 15)
    expect_identical(format(tab(d, g, summarize = y, where = FALSE)), "no observations")
    expect_identical(format(tab(d, g, summarize = y, means = FALSE, standard = FALSE, freq = FALSE)), character())
    d$mean <- d$g
    out <- as.data.frame(tab(d, mean, summarize = y))
    expect_named(out, c("mean", "mean.1", "sd", "freq", "obs"))
    expect_equal(out$mean.1, c(70 / 3, 50))
})

test_that("grouped summary tables evaluate samples and weights inside each group", {
    d <- data.frame(group = c(2, 1, 2, 1, 2, 1), category = c(1, 1, 1, 1, 2, 2),
        outcome = c(10, 20, 30, 40, 50, NA), w = c(1, 2, 3, 4, 5, 6))
    attr(d$outcome, "label") <- "Response label"
    out <- tab(d, category, summarize = outcome, by = group,
        where = .n <= 2, weights = w)
    expect_s3_class(out, "dta_tab_grouped")
    expect_equal(attr(out, "groups")$group, c(2, 1))
    expect_equal(as.data.frame(out[[1L]])$mean, 25)
    expect_equal(as.data.frame(out[[2L]])$mean, 100 / 3)
    expect_equal(as.data.frame(out[[1L]])$freq, 4)
    expect_equal(as.data.frame(out[[2L]])$freq, 6)
    expect_true(any(grepl("Response label", format(out), fixed = TRUE)))
    selected <- tab(d, category, summarize = outcome, by = group, rows = 1)
    expect_equal(as.data.frame(selected[[1L]])$mean, 10)
    expect_equal(as.data.frame(selected[[2L]])$mean, 20)
    collected <- tab(d, category, summarize = outcome, collect = "Summary")
    expect_identical(attr(collected, "collection")$name, "Summary")
    expect_equal(attr(collected, "collection")$table, as.data.frame(collected))
})

test_that("editing summary cells drops the saved display and marginal moments", {
    d <- tab_summary_fixture()
    result <- tab(d, g, summarize = y, collect = TRUE)
    dollar <- bracket <- double_bracket <- result
    dollar$mean <- c(100, 200)
    bracket[1, "mean"] <- 300
    double_bracket[["mean"]] <- c(400, 500)
    for (edited in list(dollar, bracket, double_bracket)) {
        expect_identical(class(edited), "data.frame")
        expect_null(attr(edited, "dta_tab_summary"))
        expect_null(attr(edited, "collection"))
        expect_null(attr(edited, "r", exact = TRUE))
    }
    expect_equal(dollar$mean, c(100, 200))
    expect_equal(bracket$mean, c(300, 50))
    expect_equal(double_bracket$mean, c(400, 500))
    expect_equal(result$mean, c(70 / 3, 50))
})

test_that("binding and transforming summaries cannot retain the original moments", {
    result <- tab(tab_summary_fixture(), g, summarize = y, collect = TRUE)
    plain <- as.data.frame(result)
    combined <- list(rbind(result, result), rbind(result, plain), rbind(plain, result))
    for (value in combined) {
        expect_identical(value, rbind(plain, plain))
        expect_false(any(grepl("Summary of", capture.output(print(value)), fixed = TRUE)))
    }
    expect_identical(rbind(first = result, second = plain), rbind(first = plain, second = plain))
    expect_identical(rbind(result, plain, make.row.names = FALSE),
        rbind(plain, plain, make.row.names = FALSE))
    expect_identical(cbind(result, added = 1), cbind(plain, added = 1))
    expect_identical(cbind(added = 1, result), cbind(added = 1, plain))
    expect_identical(within(result, mean <- mean * 2), within(plain, mean <- mean * 2))
    expect_identical(transform(result, mean = mean * 2), transform(plain, mean = mean * 2))
})

test_that("dplyr operations on summaries drop the original moments", {
    skip_if_not_installed("dplyr", "1.2.1")
    result <- tab(tab_summary_fixture(), g, summarize = y, collect = TRUE)
    plain <- as.data.frame(result)
    expect_identical(dplyr::mutate(result, mean = mean * 2),
        dplyr::mutate(plain, mean = mean * 2))
    expect_identical(dplyr::filter(result, g == 1), dplyr::filter(plain, g == 1))
    expect_identical(dplyr::slice(result, 1), dplyr::slice(plain, 1))
    expect_identical(dplyr::bind_rows(result, result), dplyr::bind_rows(plain, plain))
    expect_identical(dplyr::bind_rows(result, plain), dplyr::bind_rows(plain, plain))
    expect_identical(dplyr::bind_rows(plain, result), dplyr::bind_rows(plain, plain))
})
