test_that("summarize resolves Stata variable lists in dataset order", {
    data <- data.frame(alpha = 1:3, beta = 4:6, betamax = 7:9,
                       gamma = letters[1:3], check.names = FALSE)
    data[["c(1, 2, 3)"]] <- 1:3
    expand <- function(spec) .summarize_varlist(data, spec, rep(TRUE, 3))
    expect_identical(expand("alpha-gamma")$names,
                     c("alpha", "beta", "betamax", "gamma"))
    expect_identical(expand("bet*")$names, c("beta", "betamax"))
    expect_identical(expand("_all")$names, names(data))
    expect_identical(expand("alph")$values, list(data$alpha))
    expect_identical(expand("alpha alpha")$names, c("alpha", "alpha"))
    expect_identical(expand("c(1, 2, 3)")$values, list(1:3))
    expect_error(expand("bet"), "Ambiguous variable")
    expect_error(expand("gamma-alpha"), "reverse dataset order")
    expect_error(expand("absent*"), "Variable not found")
})

test_that("summarize preserves literal names containing Stata punctuation", {
    data <- setNames(data.frame(1:3, 4:6, 7:9, 10:12),
                     c("a#b", "(a b)", "i.(a b)", "(unbalanced"))
    result <- .summarize_varlist(data, names(data), rep(TRUE, 3))
    expect_identical(result$names, names(data))
    expect_identical(result$values, unname(as.list(data)))
    result <- summarize(data)
    expect_identical(result$statistics$variable, names(data))
    expect_identical(result$statistics$mean, c(2, 5, 8, 11))
})

test_that("summarize includes every default factor level and retains labels", {
    data <- data.frame(a = c(0, 1, 2, 0, 1, 2, NA), x = 1:7)
    attr(data$a, "labels") <- c(zero = 0, one = 1, two = 2)
    attr(data$a, "label") <- "Category a"
    expand <- function(spec, ...) {
        result <- .summarize_varlist(data, spec, rep(TRUE, 7), ...)
        lapply(result, function(x) x[result$display])
    }
    result <- expand("i.a")
    expect_identical(result$names, c("0.a", "1.a", "2.a"))
    expect_identical(result$values[[1]], c(1, 0, 0, 1, 0, 0, NA))
    expect_identical(result$factor_labels, c("zero", "one", "two"))
    expect_identical(result$factor_headers, rep("a", 3))
    expect_identical(result$headers, rep("Category a", 3))
    expect_identical(expand("i.a", nofvlabel = TRUE)$factor_labels, c("0", "1", "2"))
    expect_identical(expand("ibn.a")$names, c("0bn.a", "1.a", "2.a"))
    expect_identical(expand("i.a i.a")$names, result$names)
    expect_identical(expand("i.a i(1 2).a")$names, c("1.a", "2.a"))
    expect_error(expand("ib1.a ib2.a"), "base category conflict")
    expect_identical(expand("ib2.a")$names, c("0.a", "1.a"))
    expect_identical(expand("ib(last).a")$names, c("0.a", "1.a"))
    expect_identical(expand("ib(first).a")$names, c("1.a", "2.a"))
    expect_identical(expand("ib(freq).a")$names, c("1.a", "2.a"))
    expect_identical(expand("ib(freq).a", weights = c(1, 1, 100, 1, 1, 1, 1))$names,
                     c("0.a", "1.a"))
    expect_identical(expand("ib(#2).a")$names, c("0.a", "2.a"))
    expect_identical(expand("i(0 2).a")$names, c("0.a", "2.a"))
    expect_identical(expand("i(0/2).a")$names, result$names)
    expect_identical(expand("i(0(2)2).a")$names, c("0.a", "2.a"))
    expect_identical(expand("2.a")$values[[1]], c(0, 0, 1, 0, 0, 1, NA))
    selected <- .summarize_varlist(data, "i.a", data$x <= 2)
    expect_identical(selected$names, c("0.a", "1.a"))
    expect_identical(selected$values[[1]], result$values[[1]])
    empty <- .summarize_varlist(data, "ib(freq).a", rep(FALSE, 7))
    expect_identical(empty$names, "0.a")
    expect_true(empty$display)
    empty_base <- .summarize_varlist(data, "ib1.a", rep(FALSE, 7))
    expect_identical(empty_base$names, c("0o.a", "1b.a"))
    expect_true(all(empty_base$display))
})

test_that("summarize interactions use per-variable missingness and full factorial order", {
    data <- data.frame(a = c(0, 1, 2, 0, 1, 2, NA),
                       b = c(0, 0, 0, 1, 1, NA, 1), x = 1:7)
    expand <- function(spec, ...) {
        result <- .summarize_varlist(data, spec, rep(TRUE, 7), ...)
        lapply(result, function(x) x[result$display])
    }
    result <- expand("i.a##c.x")
    expect_identical(result$names,
                     c("0.a", "1.a", "2.a", "x", "0.a#c.x", "1.a#c.x", "2.a#c.x"))
    expect_identical(result$values[[4]], 1:7)
    expect_identical(result$values[[7]], c(0, 0, 3, 0, 0, 6, NA))
    result <- expand("a#b")
    expect_identical(result$names,
                     c("0.a#0.b", "0.a#1.b", "1.a#0.b", "1.a#1.b", "2.a#0.b", "2o.a#1o.b"))
    expect_identical(result$values[[3]], c(0, 1, 0, 0, 0, NA, NA))
    expect_true(attr(result$values[[6]], "summarize.empty"))
    expect_length(expand("a#b", noemptycells = TRUE)$values, 5)
    expect_identical(expand("i.a#i.a")$names, c("0.a", "1.a", "2.a"))
    expect_identical(expand("c.a#i.a"), expand("i.a#c.a"))
    expect_identical(expand("c.a#c.a#i.a"), expand("i.a#c.a#c.a"))
    expect_identical(expand("c.x#c.x")$values[[1]], as.double((1:7)^2))
    expect_identical(expand("i.(a b)")$names, c("0.a", "1.a", "2.a", "0.b", "1.b"))
    expect_identical(expand("a##(b c.x)")$names,
                     c("0.a", "1.a", "2.a", "0.b", "1.b", "x", result$names,
                       "0.a#c.x", "1.a#c.x", "2.a#c.x"))
})

test_that("summarize marks explicit bases and omissions as native Stata does", {
    data <- data.frame(a = rep(0:2, each = 2), b = rep(0:1, 3), x = 1:6)
    expand <- function(spec, ...) {
        result <- .summarize_varlist(data, spec, rep(TRUE, 6), ...)
        lapply(result, function(x) x[result$display])
    }
    result <- expand("ib2.a", baselevels = TRUE)
    expect_identical(result$names, c("0.a", "1.a", "2b.a"))
    expect_true(attr(result$values[[3]], "summarize.base"))
    expect_identical(as.double(result$values[[3]]), rep(0, 6))
    hidden <- .summarize_varlist(data, "ib2.a", rep(TRUE, 6))
    expect_identical(hidden$display, c(TRUE, TRUE, FALSE))
    expect_identical(as.double(hidden$values[[3]]), rep(0, 6))
    detailed <- .summarize_varlist(data, "ib2.a##c.x", rep(TRUE, 6), detail = TRUE)
    expect_true(all(detailed$display))
    expect_identical(tail(detailed$names, 1), "2b.a#co.x")
    expect_length(expand("ib2.a#i.b")$values, 6)
    expect_length(expand("ib2.a#ib1.b")$values, 5)
    expect_length(expand("ib2.a#ib1.b", baselevels = TRUE)$values, 6)
    expect_length(expand("ib2.a##ib1.b")$values, 5)
    expect_length(expand("ib2.a##ib1.b", baselevels = TRUE)$values, 7)
    expect_length(expand("ib2.a##ib1.b", allbaselevels = TRUE)$values, 11)
    expect_length(expand("ib2.a#c.x")$values, 3)
    expect_length(expand("ib2.a##c.x")$values, 5)
    factor_main <- expand("i.a ib2.a#c.a", allbaselevels = TRUE)
    expect_equal(utils::tail(factor_main$values, 1)[[1]], c(0, 0, 0, 0, 2, 2))
    squared <- expand("c.x ib2.a#c.x#c.x", allbaselevels = TRUE)
    expect_equal(utils::tail(squared$values, 1)[[1]], c(0, 0, 0, 0, 25, 36))
    omitted <- expand("io2.a")
    expect_true(attr(omitted$values[[3]], "summarize.omitted"))
    expect_identical(as.double(omitted$values[[3]]), rep(0, 6))
    expect_identical(expand("io2.a#i.b"), expand("i.a#i.b"))
    omitted_joint <- expand("io2.a#io1.b")
    expect_equal(vapply(omitted_joint$values, function(x) sum(x), numeric(1)),
                 c(1, 1, 1, 1, 1, 0))
    expect_true(attr(omitted_joint$values[[6]], "summarize.omitted"))
    expect_identical(expand("io2.a##i.b"), expand("i.a##i.b"))
    expect_error(expand("i.x"), NA)
    data$a[[1]] <- -1
    expect_error(expand("i.a"), "integers from 0 to 32740")
})

test_that("summarize time operators respect panels, time gaps, and the full source", {
    data <- data.frame(id = c(2, 1, 1, 2, 1, 2),
                       time = c(3, 1, 3, 1, 2, 2),
                       x = c(30, 1, 9, 10, 4, 20))
    expand <- function(spec, ...) .summarize_varlist(data, spec, rep(TRUE, 6),
                                                    time = "time", panel = "id", ...)
    expect_identical(expand("L.x")$values[[1]], c(20, NA, 4, NA, 1, 10))
    expect_identical(expand("F.x")$values[[1]], c(NA, 4, NA, 20, 9, 30))
    expect_identical(expand("D.x")$values[[1]], c(10, NA, 5, NA, 3, 10))
    expect_identical(expand("D2.x")$values[[1]], c(0, NA, 2, NA, NA, NA))
    expect_identical(expand("S2.x")$values[[1]], c(20, NA, 8, NA, NA, NA))
    expect_identical(expand("LD.x")$values[[1]], c(10, NA, 3, NA, NA, NA))
    expect_identical(expand("FL.x")$values[[1]], data$x)
    expect_identical(expand("L(0/2).x")$names, c("x", "L.x", "L2.x"))
    expect_identical(expand("x L.x")$factor_headers, c("x", "x"))
    expect_identical(expand("x L.x")$factor_labels, c("--.", "L1."))
    expect_identical(expand("L0.x")$factor_headers, "")
    expect_identical(expand("L(1/2).(x time)")$names,
                     c("L.x", "L2.x", "L.time", "L2.time"))
    selected <- .summarize_varlist(data, "L.x", data$time == 3,
                                   time = "time", panel = "id")
    expect_identical(selected$values[[1]], c(20, NA, 4, NA, 1, 10))
    data$time[[5]] <- 4
    expect_identical(expand("L2.x")$values[[1]], c(10, NA, 1, NA, NA, NA))
    expect_error(.summarize_varlist(data, "L.x", rep(TRUE, 6)), "require a `time` column")
    data$time[[5]] <- 3
    expect_error(expand("L.x"), "Repeated time values")
})

test_that("summarize normalizes omitted continuous interactions and repeated terms", {
    data <- data.frame(a = rep(0:2, each = 2), b = rep(0:1, 3),
                       x = 1:6, y = c(3, 2, 1, 6, 5, 4))
    expand <- function(spec) .summarize_varlist(data, spec, rep(TRUE, 6), detail = TRUE)
    omitted <- expand("o.x#c.x")
    expect_identical(omitted$names, "co.x#co.x")
    expect_true(attr(omitted$values[[1]], "summarize.omitted"))
    expect_identical(as.double(omitted$values[[1]]), rep(0, 6))
    expect_identical(expand("o.x#c.y")$values[[1]], as.double(data$x * data$y))
    expect_identical(expand("o.x#c.x#c.y")$values[[1]], as.double(data$x^2 * data$y))
    expect_identical(as.double(expand("o.x#c.x#o.y")$values[[1]]), rep(0, 6))
    expect_identical(expand("o.x")$names, "o.x")
    expect_identical(expand("co.x"), expand("o.x"))
    expect_identical(expand("o.x##c.x")$names, c("x", "co.x#co.x"))
    expect_identical(expand("o.x##c.x")$values, c(list(data$x), omitted$values))
    expect_identical(expand("c.x##o.x"), expand("o.x##c.x"))
    expect_identical(expand("i.a#i.b i.b#i.a"), expand("i.a#i.b"))
    expect_identical(expand("i.b#i.a i.a#i.b"), expand("i.b#i.a"))
    expect_identical(expand("c.x#c.y c.y#c.x"), expand("c.x#c.y"))
    expect_identical(expand("c.x#c.y o.x#o.y"), expand("c.x#c.y"))
    expect_identical(expand("o.x#o.y c.y#c.x"), expand("o.x#o.y"))
    expect_identical(expand("c.x c.x")$names, c("x", "x"))
    expect_identical(expand("c.x##c.y c.y##c.x")$names,
                     c("x", "y", "c.x#c.y", "y", "x"))
    chained <- expand("io1.a##o.x##o.y")
    expect_identical(chained$names,
                     c("0.a", "1.a", "2.a", "x", "0.a#c.x", "1o.a#co.x",
                       "2.a#c.x", "y", "0.a#c.y", "1o.a#co.y", "2.a#c.y",
                       "co.x#co.y", "0.a#c.x#c.y", "1o.a#co.x#co.y", "2.a#c.x#c.y"))
    expect_equal(vapply(chained$values, mean, numeric(1)),
                 c(1/3, 1/3, 1/3, 3.5, .5, 0, 11/6, 3.5, 5/6, 0, 1.5,
                   0, 7/6, 0, 49/6))
    chained <- expand("o.y##o.x#c.x")
    expect_identical(chained$names,
                     c("co.y#co.x", "co.x#co.x", "co.y#co.x#co.x"))
    expect_identical(vapply(chained$values, sum, numeric(1)), c(0, 0, 0))
})

test_that("summarize resolves repeated factor omission declarations", {
    data <- data.frame(a = rep(0:2, each = 2))
    expand <- function(spec) .summarize_varlist(data, spec, rep(TRUE, 6), detail = TRUE)
    expect_identical(expand("i.a#io1.a"), expand("i.a"))
    expect_identical(expand("io1.a#i.a"), expand("i.a"))
    expect_identical(expand("io1.a#ib2.a"), expand("ib2.a"))
    expect_identical(expand("ibn.a#io1.a"), expand("ibn.a"))
    expect_identical(expand("1o.a#i.a"), expand("1.a"))
    for (spec in c("io1.a#io1.a", "io1.a#io2.a", "ib1.a#io2.a",
                   "io1.a##io1.a", "io1.a#i.a#io1.a", "1o.a#1b.a")) {
        expect_error(expand(spec), "Multiple omitted operators")
    }
})

test_that("summarize carries sequential interaction omissions into equivalent terms", {
    data <- data.frame(a = rep(0:2, each = 2), b = rep(0:1, 3),
                       x = 1:6, y = c(3, 2, 1, 6, 5, 4))
    expand <- function(spec) .summarize_varlist(data, spec, rep(TRUE, 6), detail = TRUE)
    means <- function(result) vapply(result$values, mean, numeric(1))
    result <- expand("i.a#io1.b#o.y")
    expect_identical(result$names,
                     c("0.a#0.b#c.y", "0o.a#1o.b#co.y", "1.a#0.b#c.y",
                       "1.a#1.b#c.y", "2.a#0.b#c.y", "2.a#1.b#c.y"))
    expect_equal(means(result), c(.5, 0, 1/6, 1, 5/6, 2/3))
    expect_equal(means(expand("i.a#(io1.b#o.y)")), c(.5, 1/3, 1/6, 1, 5/6, 2/3))
    expect_equal(means(expand("i.a#io1.b#o.y#o.x")), c(.5, 2/3, .5, 4, 25/6, 4))
    for (spec in c("io1.a##io1.b##i.a", "io1.b##io1.a##i.b")) {
        result <- expand(spec)
        interactions <- grepl("#", result$names, fixed = TRUE)
        expect_equal(means(result)[interactions], c(0, 1/6, 1/6, 0, 1/6, 1/6)[
            if (startsWith(spec, "io1.a")) 1:6 else c(1, 3, 5, 2, 4, 6)])
        expect_identical(sum(vapply(result$values[interactions], function(x)
            isTRUE(attr(x, "summarize.omitted")), logical(1))), 2L)
    }
    result <- expand("io1.a#io1.b#ib1.b")
    expect_identical(result$names,
                     c("0o.a#0o.b", "0.a#1b.b", "1.a#0.b",
                       "1o.a#1b.b", "2.a#0.b", "2.a#1b.b"))
    expect_equal(means(result), c(0, 1/6, 1/6, 0, 1/6, 1/6))
    expect_equal(means(expand("i.a#io1.b#io1.a")), c(0, 0, 1/6, 1/6, 1/6, 1/6))
    expect_equal(means(expand("io1.a#io1.b#ib0.a")), c(0, 1/6, 1/6, 0, 1/6, 1/6))
    expect_equal(means(expand("io1.b#ib1.b#ib1.a")), c(1/6, 1/6, 1/6, 1/6, 0, 1/6))
    expect_identical(expand("io1.a#(io1.b#i.a)")$names,
                     c("0o.b#0o.a", "0.b#1.a", "0.b#2.a", "1.b#0.a",
                       "1o.b#1o.a", "1.b#2.a"))
})

test_that("summarize merges omitted cells within equivalent factor terms", {
    data <- data.frame(a = rep(0:2, each = 2), b = rep(0:1, 3), x = 1:6)
    expand <- function(spec) .summarize_varlist(data, spec, rep(TRUE, 6), detail = TRUE)
    means <- function(spec) vapply(expand(spec)$values, mean, numeric(1))
    expect_equal(tail(means("io1.a#io1.b i.a"), 3), rep(1/3, 3))
    expect_equal(head(means("i.a io1.a#io1.b"), 3), rep(1/3, 3))
    expect_equal(tail(means("io1.a io1.b i.a#i.b"), 6), rep(1/6, 6))
    expect_identical(expand("i.a#i.b io1.a#io1.b"), expand("io1.a#io1.b"))
    expect_identical(expand("io1.a#i.b i.a#io1.b"), expand("i.a#i.b"))
    expect_identical(expand("i.a io1.a"), expand("io1.a"))
})

test_that("summarize supports temporal scales, fractional deltas and lagged factors", {
    data <- data.frame(t = 0:4 / 10, x = c(2, 4, 8, 16, 32), a = c(0, 1, 0, 2, NA))
    result <- .summarize_varlist(data, "L.x", rep(TRUE, 5), time = "t", delta = 0.1)
    expect_identical(result$values[[1]], c(NA, 2, 4, 8, 16))
    data$t <- as.Date("1960-01-01") + 0:4
    data$x <- as.Date("1960-01-01") + 0:4
    attr(data$x, "format.stata") <- "%td"
    result <- .summarize_varlist(data, "L.x", rep(TRUE, 5), time = "t")
    expect_identical(as.double(result$values[[1]]), c(NA, 0, 1, 2, 3))
    expect_identical(attr(result$values[[1]], "format.stata"), "%td")
    first <- .summarize_varlist(data, "L.i.a", rep(TRUE, 5), time = "t")
    second <- .summarize_varlist(data, "iL.a", rep(TRUE, 5), time = "t")
    expect_identical(first, second)
    expect_identical(first$names, c("0.L.a", "1.L.a", "2.L.a"))
    expect_identical(first$values[[1]], c(NA, 1, 0, 1, 0))
    expect_error(.summarize_varlist(data, "D.i.a", rep(TRUE, 5), time = "t"),
                 "only lag and lead")
})
