test_that("tabulate is an exact alias and Stata selections and weights agree", {
    expect_identical(tabulate, tab)
    d <- data.frame(x = c(1, 1, 2, 2, 3, NA), y = c(1, 2, 1, 2, NA, 1),
                    w = c(.5, 2, 3, 0, 4, 1), s = c(1, 0, NA, 0, 1, 1))
    lines <- readLines(test_path("fixtures", "tabulate-features.log"), warn = FALSE)
    commands <- grep("^\\. ", lines)
    starts <- grep("^\\. tabulate ", lines)
    blocks <- lapply(starts, function(start) {
        end <- commands[commands > start][1L] - 1L
        if (is.na(end)) end <- length(lines)
        result <- lines[seq.int(start + 1L, end)]
        result <- result[!grepl("^end of do-file", result)]
        while (length(result) && !nzchar(result[1L])) result <- result[-1L]
        while (length(result) && !nzchar(tail(result, 1L))) result <- head(result, -1L)
        result
    })
    i <- 0L
    check <- function(result) {
        i <<- i + 1L
        expect_identical(format(result, width = 80), blocks[[i]], info = lines[starts[i]])
        invisible(result)
    }
    aw <- check(tab(d, x, weights = w))
    expect_equal(as.vector(aw), c(2.5, 3, 4) * 4 / 9.5)
    expect_equal(attr(aw, "r")$N, 4)
    check(tab(d, x, y, weights = w))
    check(tab(d, x, weights = w, weight = "iweight"))
    check(tab(d, x, y, weights = w, weight = "iweight"))
    check(tab(d, x, subpop = s))
    check(tab(d, x, weights = w, subpop = s))
    check(tab(d, x, where = .n <= 4, rows = 2:5))
    d$w <- round(d$w * 2)
    fw <- check(tab(d, x, weights = w, weight = "fweight", sort = TRUE,
                    matrow = TRUE, matcell = TRUE, generate = "z"))
    expect_equal(attr(fw, "r")$matrow, matrix(c(3, 2, 1), ncol = 1))
    expect_equal(attr(fw, "r")$matcell, matrix(c(8, 6, 5), ncol = 1))
    expect_equal(lapply(attr(fw, "generated"), as.double),
        list(z1 = c(0, 0, 0, NA, 1, NA), z2 = c(0, 0, 1, NA, 0, NA),
             z3 = c(1, 1, 0, NA, 0, NA)))
    check(tab(d, x, y, rowsort = TRUE, colsort = TRUE, row = TRUE))
    attr(d$x, "labels") <- c(Same = 1, Same = 2, Other = 3)
    dup <- check(tab(d, x))
    expect_identical(dimnames(dup)[[1]], c("Same [1]", "Same [2]", "Other"))
    check(tab(d, x, y))
    attr(d$x, "labels") <- NULL
    d$x[1:2] <- 1.23456789
    d$x[3:5] <- 2.34567891
    check(tab(d, x))
    attr(d$x, "format.stata") <- "%9.2f"
    check(tab(d, x))
    attr(d$x, "format.stata") <- "%td"
    check(tab(d, x))
    expect_equal(i, length(blocks))
})

test_that("joint samples, subpop categories and indicators follow native rules", {
    d <- data.frame(x = c(1, 1, 2, 3, NA), y = c(1, NA, NA, 2, 3),
                    w = c(1, 2, 3, 4, -1), s = c(1, 0, 0, 1, 1))
    expect_identical(dimnames(tab(d, x, y)), list(x = c("1", "3"), y = c("1", "2")))
    expect_equal(sum(tab(d, x, weights = w, weight = "iweight")), 10)
    result <- tab(d, x, subpop = s, generate = "z")
    expect_identical(as.vector(result), c(1L, 0L, 1L))
    expect_equal(as.double(attr(result, "generated")$z1), c(1, 1, 0, 0, NA))
    expect_equal(attr(tab(d, x, rows = 1:3, generate = "z"), "generated")$z1,
                 dta_byte(c(1, 1, 0, NA, NA)), ignore_attr = TRUE)
    expect_equal(ncol(attr(tab(numeric(), generate = "z"), "generated")), 0)
    expect_equal(nrow(attr(tab(c(NA, NA), generate = "z"), "generated")), 2)
    expect_equal(attr(tab(d, x, y, matcol = TRUE), "r")$matcol, matrix(c(1, 2), nrow = 1))
    collected <- tab(d, x, collect = "Answers")
    expect_identical(attr(collected, "collection")$name, "Answers")
    expect_identical(attr(collected, "collection")$table, as.data.frame(collected))
    expect_null(attr(as.table(collected), "collection"))
    expect_null(attr(as.table(result), "generated"))
    expect_null(attr(as.table(result), "r"))
})

test_that("by groups evaluate sample and weights within each group", {
    d <- data.frame(x = c(1, 2, 1, 3, 4, 4), g = c(2, 2, 1, 1, NA, NA))
    result <- tab(d, x, by = g, where = .n == .N, weights = .n)
    expect_s3_class(result, "dta_tab_grouped")
    expect_identical(lapply(result, as.vector), list(1, 1, 1))
    expect_equal(attr(result, "groups")$g, c(2, 1, NA))
    expect_equal(attr(result, "r")$N, 1)
    expect_match(format(result)[2], "g = 2", fixed = TRUE)
    if (requireNamespace("dplyr", quietly = TRUE)) {
        grouped <- tab(dplyr::group_by(d, g), x, rows = 1)
        expect_identical(lapply(grouped, as.vector), list(1L, 1L, 1L))
    }
    d$g <- c(NA, tagged_missing("a"), NA, tagged_missing("a"), 1, 1)
    expect_length(tab(d, x, by = g), 3)
})

test_that("new tabulate options reject invalid requests before returning results", {
    d <- data.frame(x = c(1, 2, 1), y = c(2, 1, 1), w = c(1, -1, 2))
    expect_error(tab(d, x, weights = w), "nonnegative")
    expect_error(tab(d, x, weights = c(1, 1.5, 2), weight = "fweight"), "integers")
    expect_error(tab(d, x, weights = c(1, Inf, 2)), "finite")
    expect_error(tab(d, x, weights = 1:2), "group row count")
    expect_error(tab(d, x, y, weights = 1, all = TRUE), "aweights")
    expect_error(tab(d, x, exact = TRUE), "two-way")
    expect_error(tab(d, x, y, exact = NA), "exact")
    expect_error(tab(d, x, y, generate = "z"), "one-way")
    expect_error(tab(d, x, by = y, generate = "z"), "by")
    expect_equal(sum(tab(d, x, y, subpop = w)), 3)
    expect_error(tab(letters, matrow = TRUE), "string")
    expect_error(tab(d, x, means = TRUE), "summarize")
    expect_error(tab(d, x, summarize = y, chi2 = TRUE), "two-way|summarize")
    expect_error(tab(d, x, summarize = y, weights = 1, weight = "iweight"), "iweights")
    expect_error(tab(d, x, collect = NA), "collect")
    expect_error(tab(d, x, rows = 4), "row count")
    expect_error(tab(d, x, generate = "not a name"), "prefix")
})
