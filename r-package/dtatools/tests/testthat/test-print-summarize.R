# Expected output below was captured from Stata/MP 18.0. These checks
# include the displayed rounding, column widths, and missing-value text.
test_that("summarize prints Stata's ordinary and weighted tables", {
    d <- data.frame(x = c(1, 2, 10), w = c(.25, .25, .5))
    expect_identical(format(summ(d, x)), c(
        "    Variable |        Obs        Mean    Std. dev.       Min        Max",
        "-------------+---------------------------------------------------------",
        "           x |          3    4.333333    4.932883          1         10"
    ))
    expect_identical(format(summ(d, x, weights = w, weight = "iweight")), c(
        "    Variable |     Obs      Weight        Mean   Std. dev.       Min        Max",
        "-------------+-----------------------------------------------------------------",
        "           x |       3           1        5.75          .          1         10"
    ))
    expect_identical(format(summ(d, x, where = FALSE)), c(
        "    Variable |        Obs        Mean    Std. dev.       Min        Max",
        "-------------+---------------------------------------------------------",
        "           x |          0"
    ))
})

test_that("summarize detail matches Stata's four-extreme layout", {
    d <- data.frame(x = c(1, 2, 10), w = c(.25, .25, .5))
    expect_identical(format(summ(d, x, weights = w, detail = TRUE)), c(
        "                              x",
        "-------------------------------------------------------------",
        "      Percentiles      Smallest",
        " 1%            1              1",
        " 5%            1              2",
        "10%            1             10       Obs                   3",
        "25%          1.5              .       Sum of wgt.           1",
        "",
        "50%            6                      Mean               5.75",
        "                        Largest       Std. dev.      5.223146",
        "75%           10              .",
        "90%           10              1       Variance       27.28125",
        "95%           10              2       Skewness      -.0205476",
        "99%           10             10       Kurtosis        1.02735"
    ))
    expect_identical(format(summ(d, x, detail = TRUE, where = FALSE)), c(
        "                              x",
        "-------------------------------------------------------------",
        "no observations"
    ))
})

test_that("summary display observes labels, separators and stored formats", {
    d <- data.frame(abcdefghijklmnopqrstuvwxyz = c(1e-8, 2e-8, 3e-8, 4e-8))
    expect_identical(tail(format(summ(d)), 1L),
        "abcdefghij~z |          4    2.50e-08    1.29e-08   1.00e-08   4.00e-08")
    attr(d[[1L]], "label") <- paste(
        "A long variable label containing more than",
        "sixty-one characters which wraps"
    )
    expect_identical(head(format(summ(d, detail = TRUE)), 2L), c(
        "         A long variable label containing more than",
        "              sixty-one characters which wraps"
    ))
    d <- data.frame(x = c(1, 2, 10))
    attr(d$x, "format.stata") <- "%12.2fc"
    expect_identical(tail(format(summ(d, format = TRUE)), 1L),
        "           x |          3        4.33        4.93       1.00      10.00")
    six <- as.data.frame(setNames(rep(list(1:3), 6L), letters[1:6]))
    expect_equal(sum(grepl("^-+\\+", format(summ(six)))), 2L)
    expect_equal(sum(grepl("^-+\\+", format(summ(six, separator = 0)))), 1L)
})

test_that("factor displays retain native stubs and empty-cell flags", {
    d <- data.frame(a = c(1, 1, 2), b = c(1, 2, 1))
    expect_identical(format(summ(d, "i.a")), c(
        "    Variable |        Obs        Mean    Std. dev.       Min        Max",
        "-------------+---------------------------------------------------------",
        "           a |",
        "          1  |          3    .6666667    .5773503          0          1",
        "          2  |          3    .3333333    .5773503          0          1"
    ))
    lines <- format(summ(d, "i.a#i.b"))
    expect_true(any(grepl("(empty)", lines, fixed = TRUE)))
    expect_false(any(grepl("(empty)",
        format(summ(d, "i.a#i.b", noemptycells = TRUE)), fixed = TRUE)))
    expect_true(any(grepl("(base)",
        format(summ(d, "ib2.a", baselevels = TRUE)), fixed = TRUE)))
    expect_identical(format(summ(d, "1b.a")), c(
        "    Variable |        Obs        Mean    Std. dev.       Min        Max",
        "-------------+---------------------------------------------------------"
    ))
})

test_that("meanonly is silent and data frames retain group keys", {
    result <- summ(data.frame(x = 1:3), x, meanonly = TRUE)
    expect_identical(format(result), character())
    expect_output(print(result), NA)
    expect_invisible(print(result))
    grouped <- summ(data.frame(g = c(1, 1, 2), x = 1:3), x, by = g)
    plain <- as.data.frame(grouped)
    expect_s3_class(plain, "data.frame")
    expect_equal(plain$g, c(1, 2))
    expect_equal(plain$mean, c(1.5, 3))
    lines <- format(grouped, width = 80)
    expect_identical(lines[[1L]], strrep("-", 80L))
    expect_true(all(c("-> g = 1", "-> g = 2") %in% lines))
})

test_that("group headings distinguish extended missing keys", {
    d <- dibble(x = 1:6, g = c(NA_real_, tagged_missing("a"),
        tagged_missing("z"), NA_real_, tagged_missing("a"), tagged_missing("z")))
    lines <- format(summ(d, x, by = g))
    expect_identical(lines[startsWith(lines, "->")],
        c("-> g = .", "-> g = .a", "-> g = .z"))
    d <- set_val_labels(d, g, c(Refused = tagged_missing("a")))
    lines <- format(summ(d, x, by = g))
    expect_identical(lines[startsWith(lines, "->")],
        c("-> g = .", "-> g = Refused", "-> g = .z"))
})

test_that("summary format uses calendar dates only for location statistics", {
    d <- data.frame(x = c(0, 30, 365))
    cases <- c(
        "%td" = "           x |          3   11may1960    202.6286  01jan1960  31dec1960",
        "%tm" = "           x |          3   1970m12    202.6286   1960m1   1990m6",
        "%tq" = "           x |          3   1992q4    202.6286  1960q1  2051q2",
        "%th" = "           x |          3   2025h2    202.6286  1960h1  2142h2",
        "%tw" = "           x |          3   1962w28    202.6286   1960w1   1967w2",
        "%ty" = "           x |          3        0131    202.6286          0       0365",
        "%tdCCYY-NN-DD" = "           x |          3   1960-05-11    202.6286  1960-01-01  1960-12-31",
        "%tdD_m_Y" = "           x |          3   11 May 60    202.6286  01 Jan 60  31 Dec 60"
    )
    for (fmt in names(cases)) {
        attr(d$x, "format.stata") <- fmt
        expect_identical(tail(format(summ(d, format = TRUE)), 1L),
            unname(cases[[fmt]]), info = fmt)
    }
})

test_that("factor wrapping keeps native leading and final label lines", {
    d <- data.frame(a = c(1, 2))
    d$a <- set_val_labels(d$a,
        "Long factor level name that wraps many words" = 1,
        "This label has just three lines" = 2)
    expected <- c(
        "    Variable |        Obs        Mean    Std. dev.       Min        Max",
        "-------------+---------------------------------------------------------",
        "           a |",
        "Long factor  |",
        "level nam..  |",
        " many words  |          2          .5    .7071068          0          1",
        " This label  |",
        "   has just  |",
        "three lines  |          2          .5    .7071068          0          1"
    )
    expect_identical(format(summ(d, "i.a", fvwrap = 3)), expected)
    expect_identical(format(summ(d, "i.a", fvwrap = 0)),
        format(summ(d, "i.a", fvwrap = -1)))
})

test_that("stored numeric formats follow summarize's normalization", {
    d <- data.frame(x = c(1234.567, 2345.678, 3456.789))
    cases <- c(
        "%9.2f" = "           x |          3     2345.68     1111.11    1234.57    3456.79",
        "%9,2f" = "           x |          3     2345.68     1111.11    1234.57    3456.79",
        "%9.2fc" = "           x |          3    2,345.68    1,111.11   1,234.57   3,456.79",
        "%9,2fc" = "           x |          3    2,345.68    1,111.11   1,234.57   3,456.79",
        "%9.2e" = "           x |          3    2345.678    1111.111   1234.567   3456.789",
        "%21x" = "           x |          3    2345.678    1111.111   1234.567   3456.789",
        "%9.2gc" = "           x |          3       2,346       1,111      1,235      3,457",
        "%9,2gc" = "           x |          3       2,346       1,111      1,235      3,457",
        "%9.0gc" = "           x |          3    2,345.68    1,111.11   1,234.57   3,456.79"
    )
    for (fmt in names(cases)) {
        attr(d$x, "format.stata") <- fmt
        expect_identical(tail(format(summ(d, format = TRUE)), 1L),
            unname(cases[[fmt]]), info = fmt)
    }
})

test_that("calendar pictures match Stata's documented tokens and padding", {
    d <- data.frame(x = c(18282, 18315))
    cases <- c(
        "%tdnn/dd/YY" = "           x |          2     2/5/10    23.33452   1/20/10   2/22/10",
        "%tdDay_Mon._DD" = "           x |          2   Fri Feb. 05    23.33452  Wed Jan. 20  Mon Feb. 22",
        "%tdMonth_dd,_CCYY" = "           x |          2     February 5, 2010    23.33452    January 20, 2010   February 22, 2010",
        "%tdDAYNAME" = "           x |          2      Friday    23.33452  Wednesday     Monday",
        "%tdDayname" = "           x |          2      Friday    23.33452  Wednesday     Monday",
        "%tdCCYY-JJJ" = "           x |          2   2010-036    23.33452  2010-020  2010-053",
        "%tdDD/NN/CCYY" = "           x |          2   05/02/2010    23.33452  20/01/2010  22/02/2010"
    )
    for (fmt in names(cases)) {
        attr(d$x, "format.stata") <- fmt
        expect_identical(tail(format(summ(d, format = TRUE)), 1L),
            unname(cases[[fmt]]), info = fmt)
    }
    d$x <- c(0, 0)
    cases <- c(
        "%tmMonth_CCYY" = "           x |          2     January 1960           0    January 1960    January 1960",
        "%tqCCYY!Qq" = "           x |          2   1960Q1           0  1960Q1  1960Q1",
        "%twCCYY-NN-DD" = "           x |          2   1960-01-01           0  1960-01-01  1960-01-01",
        "%thCCYY!Hh" = "           x |          2   1960H1           0  1960H1  1960H1"
    )
    for (fmt in names(cases)) {
        attr(d$x, "format.stata") <- fmt
        expect_identical(tail(format(summ(d, format = TRUE)), 1L),
            unname(cases[[fmt]]), info = fmt)
    }
})

test_that("datetime/C prints leap seconds and truncates fractions", {
    midnight <- as.double(as.Date("2017-01-01") - as.Date("1960-01-01")) * 86400000
    d <- data.frame(x = rep(midnight + 26000 + 125, 2L))
    cases <- c(
        "%tC" = "           x |          2   31dec2016 23:59:60           0  31dec2016 23:59:60  31dec2016 23:59:60",
        "%tCDDmonCCYY_HH:MM:SS.sss" = "           x |          2   31dec2016 23:59:60.125           0  31dec2016 23:59:60.125  31dec2016 23:59:60.125",
        "%tChh:mm_AM" = "           x |          2   11:59 PM           0  11:59 PM  11:59 PM",
        "%tCHh:MM_a.m." = "           x |          2   11:59 p.m.           0  11:59 p.m.  11:59 p.m.",
        "%tCHH:MM:SS.sss" = "           x |          2   23:59:60.125           0  23:59:60.125  23:59:60.125"
    )
    for (fmt in names(cases)) {
        attr(d$x, "format.stata") <- fmt
        expect_identical(tail(format(summ(d, format = TRUE)), 1L),
            unname(cases[[fmt]]), info = fmt)
    }
    d$x <- rep(midnight + 27000 + 999, 2L)
    attr(d$x, "format.stata") <- "%tCHH:MM:SS.sss"
    expect_identical(tail(format(summ(d, format = TRUE)), 1L),
        "           x |          2   00:00:00.999           0  00:00:00.999  00:00:00.999")
    attr(d$x, "format.stata") <- "%tCHH:MM:SS.s"
    expect_match(tail(format(summ(d, format = TRUE)), 1L), "00:00:00.9", fixed = TRUE)
})

test_that("missing calendars use native numeric fallback and unknown pictures fail", {
    d <- data.frame(x = 1:3)
    attr(d$x, "format.stata") <- "%tbnyse"
    result <- summ(d, format = TRUE)
    expect_identical(format(result), format(summ(d)))
    expect_no_error(format(summ(d)))
    attr(d$x, "format.stata") <- "%tdZZZZ"
    expect_error(format(summ(d, format = TRUE)), "Unsupported token")
})

test_that("business-calendar omit rules match native Stata calendars", {
    directory <- tempfile("summarize-calendars-")
    dir.create(directory)
    on.exit(unlink(directory, recursive = TRUE), add = TRUE)
    withr::local_options(dtatools.business_calendar_path = directory)
    path <- file.path(directory, "dtasumm.stbcal")
    writeLines(c(
        "version 18", 'purpose "Summarize calendar parity"', "dateformat dmy",
        "range 01jan2020 30dec2022", "centerdate 02jan2020",
        "omit dayofweek (Sa Su)", "omit date 1jan* and +1 if dow(Fr)",
        "omit date 25dec* and (-1 +1) if dow(Tu We Th Fr)",
        "omit dowinmonth +4 Th of Nov and +1",
        "from 01jan2021 to .: omit dowinmonth -1 Mo of (May Aug) if year(2021 2022) & month(May Aug)",
        "omit date 04jul* and -1 if dow(Sa)",
        "from . to 31dec2020: omit date 15jun*"
    ), path)
    d <- data.frame(x = c(-1, 0, 1, 30, 100, 200, 300, 400, 500, 600, 700))
    attr(d$x, "format.stata") <- "%tbdtasumm"
    expect_identical(tail(format(summ(d, format = TRUE)), 1L),
        "           x |         11   06jan2021    259.3878  01jan2020  27sep2022")
    expect_identical(.summarize_number(d$x, "%tbdtasumm"), c(
        "01jan2020", "02jan2020", "03jan2020", "13feb2020", "21may2020",
        "12oct2020", "08mar2021", "27jul2021", "17dec2021", "06may2022", "27sep2022"
    ))
    attr(d$x, "format.stata") <- "%tbdtasumm:CCYY-NN-DD"
    expect_identical(tail(format(summ(d, format = TRUE)), 1L),
        "           x |         11   2021-01-06    259.3878  2020-01-01  2022-09-27")
    expect_identical(.summarize_number(c(-2, -1.5, -.5, .5, 1000), "%tbdtasumm"),
        c("-2", "01jan2020", "02jan2020", "02jan2020", "1000"))
    # A changed file is re-read, including Stata's fallback for invalid files.
    writeLines("invalid calendar content", path)
    expect_identical(format(summ(d, format = TRUE)), format(summ(d)))
})

test_that("general formats retain small values and drop commas before precision", {
    # Values and formatting were checked with native Stata 18 summarize.
    small <- c(1e-5, .00001234567, .001234567, .1234567, 1.234567)
    expect_identical(.summarize_number(small, "%9.2g"),
        c(".00001", ".000012", ".0012", ".12", "1.2"))
    expect_identical(.summarize_number(small, "%9.1gc"),
        c(".00001", ".000012", ".0012", ".12", "1.2"))
    expect_identical(.summarize_number(c(123456.78, 1234567.89, -1234567.89,
        999999.5, 9999.995), "%9.0gc"),
        c("123,457", "1234568", "-1234568", "999999.5", "10,000"))
    expect_identical(.summarize_number(c(123456.78, 999999.5), "%9.2fc"),
        c("123456.78", "999999.50"))
    expect_identical(.summarize_number(c(9999.995, 9999999.5, 1e9), "%9.2g"),
        c("1.0e+04", "1.00e+07", "1.0e+09"))
    expect_identical(.summarize_number(c(1e300, 1e-300)), c("1.0e+300", "1.0e-300"))
    d <- data.frame(x = rep(1e-5, 2L))
    attr(d$x, "format.stata") <- "%9.2g"
    expect_identical(tail(format(summ(d, format = TRUE)), 1L),
        "           x |          2      .00001           0     .00001     .00001")
})

test_that("calendar formats use numeric fallback outside years 0100 through 9999", {
    cases <- list(
        list("%td", c(-679351, -679350, 2936549, 2936550),
            c("-679351", "01jan0100", "31dec9999", "2936550")),
        list("%tm", c(-22321, -22320, 96479, 96480, 1234567.89),
            c("-22321", "0100m1", "9999m12", "96480", "1.2e+06")),
        list("%tw", c(-96721, -96720, 418079, 418080),
            c("-96721", "0100w1", "9999w52", "4.2e+05")),
        list("%tq", c(-7441, -7440, 32159, 32160),
            c("-7441", "0100q1", "9999q4", "3.2e+04")),
        list("%th", c(-3721, -3720, 16079, 16080),
            c("-3721", "0100h1", "9999h2", "1.6e+04")),
        list("%ty", c(1e-5, 99.9, 100, 9999.9, 10000),
            c("1.0e-05", "1.0e+02", "0100", "9999", "1.0e+04")),
        list("%tc", c(-58695840000001, -58695840000000,
            253717919999999, 253717920000000, 1e300),
            c("-5.86958e+13", "01jan0100 00:00:00", "31dec9999 23:59:59",
              "2.53718e+14", "1.0000e+300")),
        list("%tdCCYY", c(-679351, 2936550), c("-6.8e+05", "2.9e+06"))
    )
    for (case in cases) {
        expect_identical(trimws(.summarize_number(case[[2L]], case[[1L]])),
            case[[3L]], info = case[[1L]])
    }
    d <- data.frame(x = rep(1234567.89, 2L))
    attr(d$x, "format.stata") <- "%tm"
    expect_identical(tail(format(summ(d, format = TRUE)), 1L),
        "           x |          2   1.2e+06           0  1.2e+06  1.2e+06")
})

test_that("left-aligned calendar formats preserve date pictures and padding", {
    d <- data.frame(x = c(0, 0))
    cases <- c(
        "%-td" = "           x |          2   01jan1960           0  01jan1960  01jan1960",
        "%-tdnn/dd/YY" = "           x |          2   1/1/60             0  1/1/60    1/1/60  ",
        "%-tm" = "           x |          2   1960m1            0  1960m1   1960m1 ",
        "%-ty" = "           x |          2   0              0  0     0   "
    )
    for (fmt in names(cases)) {
        attr(d$x, "format.stata") <- fmt
        expect_identical(tail(format(summ(d, format = TRUE)), 1L),
            unname(cases[[fmt]]), info = fmt)
    }
})

test_that("numeric format families preserve Stata's halfway rounding", {
    expect_identical(.summarize_number(c(1.125, -1.125), "%9.2f"), c("1.12", "-1.12"))
    expect_identical(.summarize_number(c(2.5, -2.5), "%9.0f"), c("2", "-2"))
    expect_identical(.summarize_number(c(.125, -.125, 1.25, -1.25, 12.5, -12.5), "%9.2g"),
        c(".13", "-.13", "1.3", "-1.3", "13", "-13"))
    expect_identical(.summarize_number(c(1.125e-6, -1.125e-6, 1.225e7, -1.225e7)),
        c("1.13e-06", "-1.13e-06", "1.23e+07", "-1.23e+07"))
    expect_identical(.summarize_number(-112500, "%9.2f"), "-1.13e+05")
    expect_identical(.summarize_number(c(1.125e100, -1.125e100), "%9.2g"),
        c("1.1e+100", "-1.1e+100"))
    # Decimal values just below a halfway point must still round down.
    expect_identical(.summarize_number(.0099995, "%9.4g"), ".009999")
})

test_that("observation counts switch from commas to integers to exponentials", {
    expect_identical(.summarize_count(c(999999999, 1e9, 99999999999, 1e11, 3e16, 3e100)),
        c("999,999,999", "1000000000", "99999999999", "1.0000e+11", "3.0000e+16", "3.000e+100"))
    expect_identical(.summarize_count(1e6, width = 8L), "1000000")
    expect_identical(.summarize_count(1e6), "1,000,000")
    for (weight in c(1e16, 1e100)) {
        d <- data.frame(x = 1:3, w = weight)
        count <- if (weight == 1e16) "3.0000e+16" else "3.000e+100"
        expect_identical(tail(format(summ(d, x, weights = w, weight = "fweight")), 1L),
            paste0("           x | ", count, "           2    .8164966          1          3"))
        expect_identical(tail(format(summ(d, x, weights = w)), 1L),
            paste0("           x |       3  ", count, "           2          1          1          3"))
        lines <- format(summ(d, x, weights = w, weight = "fweight", detail = TRUE))
        expect_identical(sub("^.*Obs", "Obs", lines[grepl("Obs", lines, fixed = TRUE)]),
            paste0("Obs          ", count))
        expect_identical(sub("^.*Sum of wgt.", "Sum of wgt.", lines[grepl("Sum of wgt.", lines, fixed = TRUE)]),
            paste0("Sum of wgt.  ", count))
    }
})

test_that("weight totals use their own precision and detailed comma format", {
    expect_identical(.summarize_weight(c(.123456789, 1234.56789, 1e9)),
        c(".123456789", "1234.56789", "1.0000e+09"))
    expect_identical(.summarize_weight(c(1234.56789, 1234567.89, 1e7), comma = TRUE),
        c("1,234.5679", "1,234,568", "10000000"))
    d <- data.frame(x = 2, w = 1234.56789)
    expect_identical(tail(format(summ(d, x, weights = w)), 1L),
        "           x |       1  1234.56789           2          .          2          2")
    lines <- format(summ(d, x, weights = w, detail = TRUE))
    expect_identical(lines[grepl("Sum of wgt.", lines, fixed = TRUE)],
        "25%            2              .       Sum of wgt.  1,234.5679")
})

test_that("unavailable counts and totals remain printable after weight overflow", {
    d <- data.frame(x = 1:100, w = 1e307)
    expect_identical(.summarize_count(NA_real_), ".")
    expect_identical(.summarize_weight(NA_real_), ".")
    for (detail in c(FALSE, TRUE)) {
        result <- summ(d, x, weights = w, weight = "fweight", detail = detail)
        expect_no_error(lines <- format(result))
        expect_false("no observations" %in% lines)
        if (detail) {
            expect_true(endsWith(lines[grepl("Obs", lines, fixed = TRUE)], "."))
            expect_true(endsWith(lines[grepl("Sum of wgt.", lines, fixed = TRUE)], "."))
        } else expect_match(tail(lines, 1L), "^           x \\| +\\. +\\.")
    }
})
