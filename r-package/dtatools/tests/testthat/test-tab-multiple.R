read_tab_multiple_oracle <- function() {
    lines <- readLines(test_path("fixtures", "tabulate-multiple.log"),
                       warn = FALSE, encoding = "UTF-8")
    starts <- grep("^\\. (bysort g: )?tab[12i] ", lines)
    commands <- grep("^\\. ", lines)
    lapply(starts, function(start) {
        later <- commands[commands > start]
        end <- if (length(later)) later[[1L]] - 1L else length(lines)
        output <- lines[seq.int(start + 1L, end)]
        output <- output[!grepl("^end of do-file", output)]
        while (length(output) && !nzchar(output[[1L]])) output <- output[-1L]
        while (length(output) && !nzchar(output[[length(output)]]))
            output <- output[-length(output)]
        list(command = sub("^\\. ", "", lines[[start]]), output = output)
    })
}

test_that("tab1 tab2 and tabi print identically to native Stata", {
    d <- data.frame(x = c(1, 1, 2, 2, 3, NA), y = c(1, 2, 1, 2, NA, 3),
                    z = c(1, 2, 3, 1, 2, 2))
    counts <- matrix(c(30, 18, 38, 14), 2L, byrow = TRUE)
    actual <- list(
        tab1(d, missing = TRUE),
        tab1(d, x, y, where = z > 1, missing = TRUE, sort = TRUE),
        tab2(d, firstonly = TRUE, chi2 = TRUE),
        tab2(d, missing = TRUE, row = TRUE),
        tabi(counts), tabi(counts, row = TRUE),
        tabi(matrix(1:6, 2L, byrow = TRUE)),
        tabi(matrix(c(2, 2, 0, 0), 2L, byrow = TRUE)),
        tabi(matrix(c(2, 1, 0, 0, 3, 2, 0, 0, 5), 3L, byrow = TRUE),
             all = TRUE, exact = TRUE, nolog = TRUE, rowsort = TRUE, colsort = TRUE),
        tab1(transform(d, g = c(1, 1, 1, 2, 2, 2)), x, y, by = g, missing = TRUE)
    )
    oracle <- read_tab_multiple_oracle()
    commands <- grep("^(bysort g: )?tab[12i] ", readLines(test_path("fixtures", "tabulate-multiple.do")),
                     value = TRUE)
    expect_identical(vapply(oracle, `[[`, character(1), "command"), commands)
    expect_length(actual, length(oracle))
    for (index in seq_along(actual)) {
        expect_identical(format(actual[[index]], width = 80L), oracle[[index]]$output,
                         info = oracle[[index]]$command)
    }
})

test_that("multiple table forwarding preserves selection and option environments", {
    d <- data.frame(x = c(1, 1, 2, 2), y = c(2, 3, 2, 3), z = c(1, 2, 3, 4))
    cutoff <- 1
    one <- tab1(x, y, data = d, where = z > cutoff, weights = z, weight = "fweight")
    expect_identical(one[[1L]], tab(d, x, where = z > cutoff, weights = z, weight = "fweight"))
    expect_identical(one[[2L]], tab(d, y, where = z > cutoff, weights = z, weight = "fweight"))
    expect_identical(tab1(d), tab1(data = d))
    expect_identical(tab1(list(x = d$x, y = d$y))[[1L]], tab(x = d$x))
    two <- tab2(d, x, y, z, all = TRUE, chi2 = FALSE, weights = z, weight = "fweight")
    expect_null(attr(two[[1L]], "r")[["chi2"]])
    expect_identical(attr(two, "r"), attr(two[[3L]], "r"))
    expect_length(tab2(d, firstonly = TRUE), 2L)
    expect_length(tab2(d), 3L)
    expect_error(tab2(d, weights = z), "fweights only")
    expect_error(tab2(d, x), "at least two")
    expect_error(tab2(d, firstonly = NA), "firstonly")
    expect_error(tab1(d, freq = NULL), "freq")
    expect_error(tab2(d, all = NULL), "all")
})

test_that("immediate frequencies retain compact data even for large totals", {
    counts <- matrix(c(1e8, 2e8, 0, 3e8), 2L)
    result <- tabi(counts, chi2 = TRUE, replace = TRUE, matcell = TRUE)
    expect_equal(as.vector(result), as.vector(counts))
    expect_equal(attr(result, "r")$N, sum(counts))
    expect_equal(nrow(attr(result, "data")), 4L)
    expect_identical(attr(result, "data")$row, c(1L, 1L, 2L, 2L))
    expect_identical(attr(result, "data")$col, c(1L, 2L, 1L, 2L))
    expect_equal(attr(result, "data")$pop, as.vector(t(counts)))
    expect_equal(sum(attr(result, "data")$pop), sum(counts))
    expect_lt(as.numeric(object.size(result)), 50000)
    expect_equal(unname(attr(result, "r")$matcell), counts)
    expect_null(attr(tabi(counts, chi2 = TRUE), "data"))
    for (bad in list(c(1, 2), matrix(1, 1L, 2L), matrix(-1, 2L, 2L),
                     matrix(NA_real_, 2L, 2L), matrix(Inf, 2L, 2L), matrix(0.5, 2L, 2L))) {
        expect_error(tabi(bad), "numeric matrix")
    }
    expect_error(tabi(counts, weights = 1), "named frequency-table options")
    expect_error(tabi(counts, TRUE), "named frequency-table options")
})

test_that("multiple tabulation evaluates its data source only once", {
    calls <- 0L
    fetch <- function() {
        calls <<- calls + 1L
        data.frame(x = c(1, 1, 2), y = c(1, 2, 1))
    }
    one <- tab1(fetch(), x, y)
    expect_identical(calls, 1L)
    expect_length(one, 2L)
    calls <- 0L
    two <- tab2(fetch(), x, y)
    expect_identical(calls, 1L)
    expect_length(two, 1L)
})

test_that("immediate matrix labels are presentation labels with numeric stored rows", {
    counts <- matrix(c(5, 2, 1, 4), 2L,
        dimnames = list(Response = c("No", "Yes"), Group = c("A", "B")))
    result <- tabi(counts, all = TRUE, matrow = TRUE, matcol = TRUE)
    expect_identical(unname(dimnames(result)), unname(dimnames(counts)))
    expect_identical(attr(result, "dta_tab")$headers, c("Response", "Group"))
    expect_equal(attr(result, "r")$matrow, matrix(1:2, ncol = 1L))
    expect_equal(attr(result, "r")$matcol, matrix(1:2, nrow = 1L))
})
