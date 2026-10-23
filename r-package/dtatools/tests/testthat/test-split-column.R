# The chunks a grouped read gathered one group at a time before the split.
.split_reference <- function(value, rows) {
    lapply(rows, function(index) .gather_dta_columns(list(value = value), index)[[1L]])
}
.split_facts <- function(chunks) lapply(chunks, function(x) list(
    value = x, attributes = attributes(x), altrep = .is_altrep(x),
    compact = .is_unmaterialized_numeric_altrep(x),
    owned = !is.null(.Call(C_dtatools_owned_info, x))
))
.split_same <- function(x, y) {
    identical(x, y, num.eq = FALSE, single.NA = FALSE, attrib.as.set = FALSE)
}
.split_owned <- function(value) .Call(C_dtatools_capture_column, value)

test_that("a column splits into the chunks the per-group gathers give", {
    files <- c("all_types_v118.dta", "missing_values_v118.dta", "auto_v118.dta")
    columns <- list()
    for (file in files) {
        data <- read_dta(system.file("extdata", file, package = "dtatools"))
        data <- data[rep_len(seq_len(nrow(data)), 6L), ]
        for (name in names(data)) columns[[paste(file, name)]] <- .subset2(data, name)
    }
    columns$owned_logical <- .split_owned(c(TRUE, FALSE, NA, TRUE, NA, FALSE))
    columns$owned_factor <- .split_owned(factor(c("b", "a", NA, "a", "b", "b")))
    columns$owned_ordered <- .split_owned(ordered(c("b", "a", NA, "a", "b", "b")))
    columns$dta_double <- dta_double(c(1.5, NA, tagged_missing("a"), 4, 5, 6))
    columns$named <- dta_double(c(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6))
    columns$plain <- c(1.5, 2, NA, 4, 5, 6)
    columns$plain_integer <- 1:6
    columns$strings <- c("a", "b", NA, "d", "e", "f")
    rows <- list(c(1L, 3L), integer(), 2L, c(6L, 4L, 5L, 1L))
    split <- character()
    for (name in names(columns)) {
        value <- columns[[name]]
        actual <- .split_dta_column(value, rows)
        if (!is.null(actual)) split <- c(split, name)
        expected <- .split_reference(value, rows)
        if (is.null(actual)) actual <- expected
        expect_true(.split_same(.split_facts(actual), .split_facts(expected)), info = name)
    }
    # Every Stata numeric but the named one, and the owned discrete columns.
    numeric <- vapply(columns, function(value) .gather_dta_native(list(value))[[1L]], NA)
    expect_gt(sum(numeric), 10L)
    expect_identical(split, names(columns)[(numeric & names(columns) != "named") |
                                               startsWith(names(columns), "owned_")])

    # Names on the rows carry over, as `lapply()` keeps them.
    named_rows <- list(a = 2L, b = c(1L, 3L))
    expect_identical(names(.split_dta_column(columns$dta_double, named_rows)), c("a", "b"))
    expect_true(.split_same(.split_dta_column(columns$dta_double, named_rows),
                            .split_reference(columns$dta_double, named_rows)))
})

test_that("the split declines what the per-group gathers leave to the R code", {
    calls <- 0L
    foreign <- .Call(C_dtatools_callback_double, c(1, 2, 3), function() calls <<- calls + 1L,
                     FALSE)
    attr(foreign, "stata.storage") <- "double"
    expect_null(.split_dta_column(foreign, list(1L, 2:3)))
    expect_identical(calls, 0L)

    # Rows whose reads can run R code decline before any gather reads them,
    # even for a named column the numeric gather would read and then decline.
    calls <- 0L
    named <- dta_double(c(a = 1, b = 2, c = 3))
    rows <- list(.Call(C_dtatools_callback_integer, c(1L, 2L), function() calls <<- calls + 1L),
                 3L)
    expect_null(.split_dta_column(named, rows))
    expect_null(.split_dta_column(dta_int(c(1, 2, 3)), rows))
    expect_identical(calls, 0L)
    rows <- list(1:2, 3:4)
    expect_true(.is_altrep(rows[[1L]]))
    expect_null(.split_dta_column(dta_int(c(1, 2, 3, 4)), rows))
    # Attributed rows partway through stop the owned discrete gather.
    expect_null(.split_dta_column(.split_owned(c(TRUE, FALSE, NA, TRUE)),
                                  list(1L, structure(2L, note = TRUE))))

    # A missing storage makes the R code's verdict NA and its gather fail.
    broken <- structure(c(1, 2, 3), stata.storage = NA_character_)
    expect_null(.split_dta_column(broken, list(1L, 2:3)))
    expect_error(.gather_dta_columns(list(value = broken), 1L))
})

test_that("grouped verbs read each column with one split", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(g = c(1L, 2L, 1L, 3L, 2L), x = dta_int(c(1, 2, 3, 4, 5)),
                   y = dta_float(c(0.5, NA, 1.5, 2, 2.5)), s = c("a", "b", "c", "d", "e"))
    rows <- list(c(1L, 3L), c(2L, 5L), 4L)
    ns <- asNamespace("dtatools")
    counts <- c(gather = 0L, split = 0L)
    for (name in c(".gather_dta_columns", ".split_dta_column")) {
        key <- if (name == ".split_dta_column") "split" else "gather"
        tracer <- substitute(function() counts[[KEY]] <<- counts[[KEY]] + 1L, list(KEY = key))
        suppressMessages(trace(name, tracer = eval(tracer), where = ns, print = FALSE))
    }
    withr::defer(for (name in c(".gather_dta_columns", ".split_dta_column"))
        suppressMessages(untrace(name, where = ns)))
    result <- dplyr::summarise(data, x = list(x), y = list(y), s = list(s), .by = g)
    expect_identical(counts[["split"]], 3L)
    # The strings fall back to the R code, one gather per group.
    expect_identical(counts[["gather"]], 3L)
    for (name in c("x", "y", "s")) {
        expect_true(.split_same(.split_facts(result[[name]]),
                                .split_facts(.split_reference(data[[name]], rows))), info = name)
    }
})
