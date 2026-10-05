read_grouped_tab_log <- function(path) {
    lines <- readLines(path, warn = FALSE)
    commands <- grep("^\\. ", lines)
    starts <- grep("^\\. bysort .*: tabulate ", lines)
    lapply(starts, function(start) {
        end <- commands[commands > start][[1L]] - 1L
        output <- lines[seq.int(start + 1L, end)]
        while (length(output) && !nzchar(output[[1L]])) output <- output[-1L]
        while (length(output) && !nzchar(output[[length(output)]])) output <- output[-length(output)]
        list(command = sub("^\\. ", "", lines[[start]]), output = output)
    })
}

test_that("grouped tabulation headers replay native by-prefix output", {
    blocks <- read_grouped_tab_log(test_path("fixtures", "tabulate-grouped.log"))
    position <- 0L
    stata <- function(command, result, width = 80L) {
        position <<- position + 1L
        expect_identical(blocks[[position]]$command, command)
        expect_identical(format(result, width = width), blocks[[position]]$output, info = command)
    }
    d <- data.frame(x = rep(1:2, 4),
        g = rep(c(0, 1, NA_real_, tagged_missing("a")), each = 2),
        s = rep(c("", "alpha beta", "quoted", "z"), each = 2))
    d$g <- set_val_labels(d$g, c(Domestic = 0, Foreign = 1, Refused = tagged_missing("a")))
    stata("bysort g: tabulate x", tab(d, x, by = g))
    stata("bysort g: tabulate x, nolabel", tab(d, x, by = g, nolabel = TRUE))
    stata("bysort s: tabulate x", tab(d, x, by = s))
    stata("bysort g s: tabulate x", tab(d, x, by = c(g, s)))
    d$day <- as.Date("2020-01-01") + rep(0:3, each = 2)
    attr(d$day, "format.stata") <- "%td"
    stata("bysort day: tabulate x", tab(d, x, by = day))
    d$stamp <- as.POSIXct("2020-01-01", tz = "UTC") + rep(0:3, each = 2)
    attr(d$stamp, "format.stata") <- "%tc"
    stata("bysort stamp: tabulate x", tab(d, x, by = stamp))
    attr(d$day, "format.stata") <- "%tdMonth_dd,_CCYY"
    stata("bysort day: tabulate x", tab(d, x, by = day))
    d$g <- set_val_labels(d$g, c(
        "This group label is much longer than the column output and would exceed a table" = 0,
        Foreign = 1, Refused = tagged_missing("a")))
    stata("bysort g: tabulate x", tab(d, x, by = g), width = 120L)
    d <- data.frame(x = rep(1:2, 2), g = rep(c(1.234567891, 12345678.9), each = 2))
    attr(d$g, "format.stata") <- "%18.10f"
    stata("bysort g: tabulate x", tab(d, x, by = g), width = 120L)
    expect_identical(position, length(blocks))
    commands <- grep("^bysort .*: tabulate ", readLines(test_path("fixtures", "tabulate-grouped.do")), value = TRUE)
    expect_identical(vapply(blocks, `[[`, character(1), "command"), commands)
})

test_that("by headers preserve group order and distinguish empty and unlabelled keys", {
    d <- data.frame(x = 1:4, g = c(2, 1, 2, 1))
    d$g <- set_val_labels(d$g, c(First = 1, Second = 2))
    result <- tab(d, x, by = g)
    expect_identical(grep("^->", format(result), value = TRUE),
                     c("-> g = Second", "-> g = First"))
    d$g <- c(NA_character_, "", "two words", "a\"b")
    expect_identical(grep("^->", format(tab(d, x, by = g)), value = TRUE),
                     c("-> g = ", "-> g = two words", "-> g = a\"b"))
    d$g <- c(1, 2, NA_real_, tagged_missing("z"))
    attr(d$g, "labels") <- stats::setNames(1, "")
    expect_identical(grep("^->", format(tab(d, x, by = g)), value = TRUE),
                     c("-> g = ", "-> g = 2", "-> g = .", "-> g = .z"))
})

test_that("grouped tabulation slices only the columns its expressions read", {
    slices <- local_slice_probe(1:4)
    d <- data.frame(x = c(1, 2, 1, 2), g = c(1, 1, 2, 2), w = c(1, 2, 3, 4))
    expected <- tab(d, x, by = g, where = x > 0, weights = w,
                    weight = "fweight", subpop = w)
    d$probe <- slices$column
    expect_identical(format(tab(d, x, by = g)),
                     format(tab(d[c("x", "g")], x, by = g)))
    expect_identical(format(tab(d, x, by = g, where = x > 0, weights = w,
                                weight = "fweight", subpop = w)),
                     format(expected))
    expect_identical(slices$count(), 0L)
    result <- tab(d, x, by = g, where = probe > 1L,
                  weights = as.integer(probe), weight = "fweight")
    expect_identical(lapply(result, function(table) as.vector(table)),
                     list(2, c(3, 4)))
    expect_identical(slices$count(), 2L)
    first <- NULL
    retained <- tab(d, x, by = g, where = {
        if (is.null(first)) first <<- .data
        x >= max(first$x)
    })
    expect_identical(as.double(first$x), c(1, 2))
    expect_identical(lapply(retained, function(table) as.vector(table)),
                     list(1L, 1L))
    duplicated_names <- data.frame(x = 1:2, w = 1:2, w = 8:9,
                                   check.names = FALSE)
    expect_identical(as.vector(tab(duplicated_names, x, weights = w,
                                   weight = "fweight")), c(8, 9))
    expect_error(tab(duplicated_names, x, weights = .data$w,
                     weight = "fweight"), "duplicate")
})
