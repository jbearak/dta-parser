# tab() prints as Stata 19 prints `tabulate`. fixtures/tabulate.do is the
# Stata side and fixtures/tabulate.log its output; the R side below
# replays the same commands in the same order, and every printed line
# must match. A new Stata case goes into the do-file, the log is
# regenerated with Stata, and its R counterpart is added here in order.

read_tabulate_log <- function(path) {
    lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
    starts <- grep("^\\. tabulate ", lines)
    commands <- grep("^\\. ", lines)
    lapply(starts, function(start) {
        following <- commands[commands > start]
        end <- if (length(following)) following[[1L]] - 1L else length(lines)
        output <- lines[seq(start + 1L, end)]
        output <- output[!grepl("^end of do-file", output)]
        while (length(output) && !nzchar(output[[1L]])) output <- output[-1L]
        while (length(output) && !nzchar(output[[length(output)]])) {
            output <- output[-length(output)]
        }
        list(command = sub("^\\. ", "", lines[[start]]), output = output)
    })
}

test_that("tab prints every tabulate case of the Stata log identically", {
    blocks <- read_tabulate_log(test_path("fixtures", "tabulate.log"))
    expect_length(blocks, 62L)
    position <- 0L
    stata <- function(command, result) {
        position <<- position + 1L
        block <- blocks[[position]]
        expect_identical(block$command, command, info = position)
        expect_identical(format(result, width = 80L), block$output, info = command)
    }

    d <- read_dta(fixture("auto_v118.dta"))
    rows <- function(condition) d[which(condition), ]

    stata("tabulate rep78", tab(d, rep78))
    stata("tabulate rep78, missing", tab(d, rep78, missing = TRUE))
    stata("tabulate foreign", tab(d, foreign))
    stata("tabulate foreign, nolabel", tab(d, foreign, display = "value"))
    stata("tabulate rep78, sort", tab(d, rep78, sort = TRUE))
    stata("tabulate make if _n <= 3", tab(d[1:3, ], make))
    stata("tabulate mpg if mpg >= 40", tab(rows(as.double(d$mpg) >= 40), mpg))

    stata("tabulate rep78 foreign", tab(d, rep78, foreign))
    stata("tabulate rep78 foreign, missing", tab(d, rep78, foreign, missing = TRUE))
    stata("tabulate rep78 foreign, nolabel", tab(d, rep78, foreign, display = "value"))
    stata("tabulate rep78 foreign, row", tab(d, rep78, foreign, percent = "row"))
    stata("tabulate rep78 foreign, column", tab(d, rep78, foreign, percent = "column"))
    stata("tabulate rep78 foreign, cell", tab(d, rep78, foreign, percent = "cell"))
    stata("tabulate rep78 foreign, row column cell",
          tab(d, rep78, foreign, percent = c("row", "column", "cell")))
    stata("tabulate rep78 foreign, expected", tab(d, rep78, foreign, expected = TRUE))
    stata("tabulate rep78 foreign, expected nofreq",
          tab(d, rep78, foreign, expected = TRUE, freq = FALSE))
    stata("tabulate rep78 foreign, nofreq row",
          tab(d, rep78, foreign, percent = "row", freq = FALSE))
    stata("tabulate rep78 foreign, cell nofreq",
          tab(d, rep78, foreign, percent = "cell", freq = FALSE))
    stata("tabulate rep78 foreign, row column nofreq",
          tab(d, rep78, foreign, percent = c("column", "row"), freq = FALSE))
    stata("tabulate rep78 foreign, missing row",
          tab(d, rep78, foreign, missing = TRUE, percent = "row"))
    stata("tabulate rep78 foreign, missing expected",
          tab(d, rep78, foreign, missing = TRUE, expected = TRUE))
    stata("tabulate rep78 foreign, nolabel missing cell",
          tab(d, rep78, foreign, display = "value", missing = TRUE, percent = "cell"))
    stata("tabulate foreign rep78", tab(d, foreign, rep78))
    stata("tabulate foreign rep78, column", tab(d, foreign, rep78, percent = "column"))
    stata("tabulate make foreign if _n <= 3", tab(d[1:3, ], make, foreign))
    stata("tabulate rep78 foreign if _n <= 3", tab(d[1:3, ], rep78, foreign))

    gen(d, r2 = rep78)
    repl(d, r2 = tagged_missing("a"), where = .n <= 2)
    repl(d, r2 = tagged_missing("b"), where = .n == 3)
    stata("tabulate r2", tab(d, r2))
    stata("tabulate r2, missing", tab(d, r2, missing = TRUE))
    stata("tabulate r2 foreign, missing", tab(d, r2, foreign, missing = TRUE))
    stata("tabulate r2 foreign, missing expected nofreq",
          tab(d, r2, foreign, missing = TRUE, expected = TRUE, freq = FALSE))

    gen(d, t = 1, where = .n <= 2)
    repl(d, t = 2, where = .n %in% 3:4)
    repl(d, t = 3, where = .n == 5)
    repl(d, t = 0, where = .n %in% 6:7)
    stata("tabulate t, sort", tab(d, t, sort = TRUE))
    stata("tabulate t, sort missing", tab(d, t, sort = TRUE, missing = TRUE))
    set_val_labels(d, t, c(Zero = 0, One = 1, Two = 2, Three = 3))
    stata("tabulate t, sort", tab(d, t, sort = TRUE))
    gen(d, e = tagged_missing("a"), where = .n <= 3)
    repl(d, e = tagged_missing("b"), where = .n == 4)
    repl(d, e = 1, where = .n %in% 5:9)
    stata("tabulate e, missing", tab(d, e, missing = TRUE))
    stata("tabulate e, missing sort", tab(d, e, missing = TRUE, sort = TRUE))

    # Stata's `gen str s = make` sizes `s` from its values, `str17`, not
    # from make's declared `str18`.
    gen(d, s = dta_string(as.character(make)))
    repl(d, s = "", where = .n <= 3)
    stata("tabulate s if _n <= 6", tab(d[1:6, ], s))
    stata("tabulate s if _n <= 6, missing", tab(d[1:6, ], s, missing = TRUE))
    gen(d, u = "b", where = .n <= 2)
    repl(d, u = "a", where = .n %in% 3:4)
    repl(d, u = "c", where = .n == 5)
    stata("tabulate u, sort", tab(d, u, sort = TRUE))
    stata("tabulate u if _n <= 6, missing", tab(d[1:6, ], u, missing = TRUE))
    stata("tabulate u foreign if _n <= 6", tab(d[1:6, ], u, foreign))
    stata("tabulate u foreign if _n <= 6, missing", tab(d[1:6, ], u, foreign, missing = TRUE))

    gen(d, q = 1, where = .n == 1)
    repl(d, q = 2, where = .n %in% 2:3)
    stata("tabulate q", tab(d, q))
    gen(d, r = .n, where = .n <= 7)
    stata("tabulate r", tab(d, r))

    stata("tabulate rep78 if mpg > 1000", tab(rows(as.double(d$mpg) > 1000), rep78))
    gen(d, z = NA_real_)
    stata("tabulate z", tab(d, z))
    stata("tabulate z, missing", tab(d, z, missing = TRUE))
    stata("tabulate z foreign", tab(d, z, foreign))

    set_val_labels(d, rep78, c("Very poor rating text long" = 1, Poor = 2,
                               Average = 3, Good = 4, Excellent = 5))
    stata("tabulate rep78", tab(d, rep78))
    stata("tabulate rep78 foreign", tab(d, rep78, foreign))
    set_val_labels(d, rep78, c(
        "This is a label that is much longer than twenty one chars" = 1, Poor = 2
    ))
    stata("tabulate rep78 if rep78 <= 2", tab(rows(as.double(d$rep78) <= 2), rep78))
    stata("tabulate rep78 foreign if rep78 <= 2",
          tab(rows(as.double(d$rep78) <= 2), rep78, foreign))
    set_val_labels(d, rep78, NULL)
    set_val_labels(d, foreign, c("Domestic car" = 0, "Foreign car built abroad" = 1))
    stata("tabulate rep78 foreign", tab(d, rep78, foreign))
    stata("tabulate foreign rep78", tab(d, foreign, rep78))
    set_val_labels(d, foreign, c(Domestic = 0, Foreign = 1))
    set_var_label(d, rep78, "Repairrecordfor1978automobiles")
    stata("tabulate rep78 if _n <= 20", tab(d[1:20, ], rep78))
    stata("tabulate rep78 foreign if _n <= 20", tab(d[1:20, ], rep78, foreign))
    set_var_label(d, foreign, "Originofthecarlongword")
    stata("tabulate rep78 foreign if _n <= 20", tab(d[1:20, ], rep78, foreign))
    set_var_label(d, rep78, "Repair record 1978")
    set_var_label(d, foreign, "Car origin")
    gen(d, c11 = foreign)
    set_var_label(d, c11, "abcdefghijk")
    stata("tabulate rep78 c11 if _n <= 3", tab(d[1:3, ], rep78, c11))
    gen(d, c10 = foreign)
    set_var_label(d, c10, "abcdefghij")
    set_val_labels(d, c10, c(Domestic10 = 0, ForeignXYZ = 1))
    stata("tabulate rep78 c10", tab(d, rep78, c10))
    gen(d, g = .n %% 3)
    gen(d, h = .n %% 2)
    stata("tabulate g h, row", tab(d, g, h, percent = "row"))
    gen(d, fo3 = substr(ifelse(as.double(foreign) == 1, "Foreign", "Domestic"), 1, 3))
    stata("tabulate rep78 fo3", tab(d, rep78, fo3))

    big <- d[rep(seq_len(nrow(d)), 2000L), ]
    stata("tabulate foreign", tab(big, foreign))
    stata("tabulate g h", tab(big, g, h))
    expect_identical(position, length(blocks))
})

test_that("the do-file and the log carry the same tabulate commands", {
    do_lines <- readLines(test_path("fixtures", "tabulate.do"), warn = FALSE)
    from_do <- grep("^tabulate ", do_lines, value = TRUE)
    from_log <- vapply(
        read_tabulate_log(test_path("fixtures", "tabulate.log")),
        function(block) block$command, character(1)
    )
    expect_identical(from_log, from_do)
})

test_that("a dta_tab is a table with a presentation record", {
    d <- read_dta(fixture("auto_v118.dta"))
    result <- tab(d, rep78, foreign, percent = "row", expected = TRUE)
    expect_s3_class(result, c("dta_tab", "table"), exact = TRUE)
    plain <- as.table(result)
    expect_s3_class(plain, "table", exact = TRUE)
    expect_null(attr(plain, "dta_tab"))
    expect_identical(unclass(plain), unclass(table(
        factor_from_labels(d$rep78, drop_unused = TRUE),
        factor_from_labels(d$foreign, drop_unused = TRUE),
        dnn = c("rep78", "foreign")
    )))
    expect_identical(names(dimnames(result)), c("rep78", "foreign"))
    expect_identical(sum(result), 69L)
    expect_identical(unname(result[, "Foreign"]), c(0L, 0L, 3L, 9L, 9L))
    expect_s3_class(result[, "Foreign", drop = FALSE], "table", exact = TRUE)
    expect_s3_class(result / sum(result), "table", exact = TRUE)
    # margin.table() is not generic and restores the class itself; the
    # margin has no layout record, so it prints as base R prints a table.
    margin <- margin.table(result, 1L)
    expect_null(attr(margin, "dta_tab"))
    expect_identical(as.table(margin), margin.table(plain, 1L))
    expect_identical(
        utils::capture.output(print(margin)),
        utils::capture.output(print(margin.table(plain, 1L)))
    )

    frame <- as.data.frame(result)
    expect_identical(names(frame), c("rep78", "foreign", "Freq", "expected",
                                     "row_percent", "column_percent", "cell_percent"))
    expect_identical(frame$Freq, as.vector(plain))
    expect_equal(frame$expected[[3L]], 30 * 48 / 69)
    expect_equal(frame$row_percent[[3L]], 100 * 27 / 30)
    expect_equal(frame$column_percent[[3L]], 100 * 27 / 48)
    expect_equal(frame$cell_percent[[3L]], 100 * 27 / 69)

    one_way <- as.data.frame(tab(d, rep78))
    expect_identical(names(one_way), c("rep78", "Freq", "percent", "cum"))
    expect_equal(one_way$cum[[5L]], 100)
    expect_equal(one_way$percent, 100 * c(2, 8, 30, 18, 11) / 69)

    # A variable named like a statistic keeps its column.
    percent <- c("a", "a", "b")
    collided <- as.data.frame(tab(percent))
    expect_identical(names(collided), c("percent", "Freq", "percent.1", "cum"))
    expect_identical(as.character(collided$percent), c("a", "b"))
    expect_equal(collided$percent.1, c(200, 100) / 3)
    renamed <- as.data.frame(tab(percent), responseName = "cum")
    expect_identical(names(renamed), c("percent", "cum", "percent.1", "cum.1"))
    expect_identical(renamed$cum, c(2L, 1L))

    # Arithmetic, transposition, and math drop the presentation: the result
    # is no longer a tabulate, and it prints and converts as a plain table.
    for (derived in list(sqrt(result), t(result), aperm(result, c(2L, 1L)),
                         result * 2, -result, round(result / 3))) {
        expect_s3_class(derived, "table", exact = TRUE)
        expect_null(attr(derived, "dta_tab"))
    }
    expect_identical(as.data.frame(sqrt(result)), as.data.frame(sqrt(plain)))
    # Without category names there is nothing to lay out, so the table
    # prints and converts as a plain one, with every count still in it.
    stripped <- unname(result)
    expect_identical(format(stripped), utils::capture.output(print(unname(plain))))
    expect_identical(as.data.frame(stripped), as.data.frame(unname(plain)))
    expect_identical(sum(stripped), 69L)
    expect_identical(
        utils::capture.output(print(t(result))),
        utils::capture.output(print(t(plain)))
    )
    expect_identical(unclass(t(result)), unclass(t(plain)))
})

test_that("tab checks its Stata options the way Stata checks them", {
    d <- read_dta(fixture("auto_v118.dta"))
    expect_error(tab(d, rep78, foreign, sort = TRUE), "one-way")
    expect_error(tab(d, rep78, percent = "row"), "two-way")
    expect_error(tab(d, rep78, expected = TRUE), "two-way")
    expect_error(tab(d, rep78, foreign, mpg, percent = "cell"), "two-way")
    expect_error(tab(d, rep78, foreign, freq = FALSE), "nothing would be shown")
    expect_error(tab(d, rep78, freq = FALSE), "nothing would be shown")
    expect_error(tab(d, rep78, foreign, percent = "rows"), "arg")
    expect_error(tab(d, rep78, foreign, percent = 1), "`percent`")
    expect_error(tab(d, rep78, sort = NA), "`sort`")
    expect_error(tab(d, rep78, foreign, expected = "yes"), "`expected`")
    expect_error(tab(d, rep78, freq = c(TRUE, FALSE)), "`freq`")
    # Stata's `nofreq` alone prints nothing; the R error names the cause.
    expect_error(tab(d, rep78, foreign, freq = FALSE), "freq = FALSE")
})

test_that("three or more variables are an R extension without a Stata layout", {
    d <- read_dta(fixture("auto_v118.dta"))
    result <- tab(d, rep78, foreign, headroom)
    expect_s3_class(result, "dta_tab")
    expect_length(dim(result), 3L)
    expect_identical(format(result), utils::capture.output(print(as.table(result))))
    expect_output(print(result), "headroom")
    expect_identical(sum(result), 69L)
})

test_that("empty strings and NA are one string missing", {
    x <- c("a", "", NA, "b", "a", "")
    excluded <- tab(x)
    expect_identical(dimnames(excluded)[[1L]], c("a", "b"))
    expect_identical(as.vector(excluded), c(2L, 1L))
    kept <- tab(x, missing = TRUE)
    expect_identical(dimnames(kept)[[1L]], c("", "a", "b"))
    expect_identical(as.vector(kept), c(3L, 2L, 1L))
    expect_identical(tab(x, missing = "combine"), kept)
    expect_identical(format(kept)[3L], "            |          3       50.00       50.00")
    strings <- dta_string(c("x", "", "y"))
    expect_identical(as.vector(tab(strings)), c(1L, 1L))
    expect_identical(dimnames(tab(strings, missing = TRUE))[[1L]], c("", "x", "y"))
    # A character crossed with a numeric drops the string-missing rows too.
    two <- tab(x, y = c(1, 1, 2, 2, 1, 1))
    expect_identical(sum(two), 3L)
    expect_identical(dim(two), c(2L, 2L))
})

test_that("printing survives categories Stata cannot produce", {
    # An unused factor level is a zero row; its row percentages are shown as
    # missing, since nothing divides by its zero total.
    f <- factor(c("a", "a", "b"), levels = c("a", "b", "unused"))
    lines <- format(tab(f, g = c(1, 1, 2), percent = "row"))
    expect_identical(lines[[17L]], "    unused |         0          0 |         0 ")
    expect_identical(lines[[18L]], "           |         .          . |         . ")
    # A wide table prints in panels sized to the console width.
    d <- read_dta(fixture("auto_v118.dta"))
    narrow <- format(tab(d, foreign, rep78), width = 60L)
    wide <- format(tab(d, foreign, rep78), width = 200L)
    expect_length(wide, 7L)
    expect_gt(length(narrow), length(wide))
    # Stata fits four columns beside an eleven-wide stub at 80 characters;
    # sixty leaves room for three, and the rest follow in a second panel.
    expect_identical(narrow[[2L]], "Car origin |         1          2          3 |     Total")
    expect_identical(narrow[8:9], c("", ""))
    expect_identical(narrow[[11L]], "Car origin |         4          5 |     Total")
    expect_true(all(nchar(narrow) <= 60L))
    # When the stub and the columns fill the width exactly, the trailing
    # space after the total still fits: no line is wider than requested.
    twelve <- rep(c("twelve chars", "b"), 5)
    exact <- format(tab(row = twelve, col = rep(1:5, 2)), width = 80L)
    expect_true(all(nchar(exact, type = "width") <= 80L))
    expect_identical(sum(grepl("^-", exact)), 4L)
    # NaN and combined missing categories print with their tab() names.
    x <- c(1, NaN, NA, 1)
    expect_match(format(tab(x, missing = TRUE))[[5L]], "^ +NaN \\|")
    combined <- format(tab(x, missing = "combine"))
    expect_match(combined[[4L]], "^ +\\. \\|")
})

test_that("the layout measures display width, not characters", {
    wide <- c("\u5317\u4eac", "\u4e0a\u6d77", "\u5317\u4eac")
    attr(wide, "label") <- "\u57ce\u5e02\u540d\u79f0\u57ce\u5e02\u540d\u79f0\u57ce\u5e02"
    y <- c(1, 1, 2)
    attr(y, "label") <- "\u7c7b\u578b\u7c7b\u578b\u7c7b\u578b\u7c7b\u578b\u7c7b\u578b"
    one <- format(tab(city = wide))
    # The ten-column label wraps into two five-character lines in the
    # eleven-wide stub; every level and rule line spans the same 48 columns.
    expect_identical(one[1:2], c(" \u57ce\u5e02\u540d\u79f0\u57ce |",
                                 " \u5e02\u540d\u79f0\u57ce\u5e02 |      Freq.     Percent        Cum."))
    expect_identical(unique(nchar(one[2:6], type = "width")), 48L)
    two <- format(tab(city = wide, kind = y, percent = "row"))
    body <- two[-(1:7)]
    expect_identical(body[[1L]], "\u57ce\u5e02\u540d\u79f0\u57ce | \u7c7b\u578b\u7c7b\u578b\u7c7b\u578b\u7c7b\u578b\u7c7b\u578b")
    expect_identical(unique(nchar(grep("^-", body, value = TRUE), type = "width")), 45L)
    expect_identical(unique(nchar(grep("\\| +[0-9.]+ $", body, value = TRUE), type = "width")), 46L)
    # A ten-character double-width label wraps into the twenty-two-wide
    # block rather than overflowing it; a column level is cut to nine
    # columns, so four double-width characters and no half character.
    long <- c("\u5317\u4eac\u5e02\u4e2d\u5fc3\u533a", "\u4e0a\u6d77")
    lines <- format(tab(k = c(1, 2), place = long))
    expect_identical(lines[[2L]], "         k |      \u4e0a\u6d77   \u5317\u4eac\u5e02\u4e2d |     Total")
    expect_identical(unique(nchar(grep("^-", lines, value = TRUE), type = "width")), 45L)
    # Cutting stops at a whole character and pads the remainder.
    expect_identical(dtatools:::.tab_cut("\u5317\u4eac\u5e02", 5L), "\u5317\u4eac")
    expect_identical(dtatools:::.tab_pad("\u5317", 4L), "  \u5317")
    expect_identical(dtatools:::.tab_wrap("\u5317\u4eac\u5e02\u4e2d\u5fc3", 4L),
                     c("\u5317\u4eac", "\u5e02\u4e2d", "\u5fc3"))
})

test_that("the console width option drives the printed panels", {
    d <- read_dta(fixture("auto_v118.dta"))
    withr::local_options(width = 60L)
    printed <- utils::capture.output(print(tab(d, foreign, rep78)))
    expect_identical(printed, format(tab(d, foreign, rep78), width = 60L))
})

test_that("sort keeps a table with one category or none", {
    one <- tab(rep(1, 5), sort = TRUE)
    expect_identical(dim(one), 1L)
    expect_identical(dimnames(one)[[1L]], "1")
    expect_identical(format(one)[[3L]], "          1 |          5      100.00      100.00")
    none <- tab(c(NA_real_, NA_real_), sort = TRUE)
    expect_identical(dim(none), 0L)
    expect_identical(format(none), "no observations")
    # The sorted table keeps its dimension name and prints as the unsorted
    # table does when frequencies are already in descending order.
    x <- c(1, 1, 2)
    expect_identical(as.table(tab(x, sort = TRUE)), as.table(tab(x)))
    expect_identical(names(dimnames(tab(x, sort = TRUE))), "x")
})

test_that("duplicate label text is qualified by code, unlike Stata", {
    # Stata prints two rows headed `Same`; tab() names every row uniquely.
    x <- set_val_labels(c(1, 2, 2, 3), Same = 1, Same = 2, Three = 3)
    lines <- format(tab(x))
    expect_identical(substr(lines[3:5], 1L, 11L),
                     c("   Same [1]", "   Same [2]", "      Three"))
    expect_identical(as.character(as.data.frame(tab(x))$x),
                     c("Same [1]", "Same [2]", "Three"))
})
