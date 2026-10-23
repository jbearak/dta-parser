# The mean admission declines while base's lazy bindings of mean() and
# mean.default() are unforced. One bare mean forces them.
invisible(mean(c(1, 2)))
.summary_fast <- function(x, generic, na.rm = FALSE) {
    force(x)
    if (generic == "mean") .Call(C_dtatools_mean_computed, environment())
    else .Call(C_dtatools_summary_computed, x, generic, environment())
}
# The code the native calls replace.
.summary_r <- function(x, generic, na.rm = FALSE) {
    value <- .dta_data(x)
    result <- if (generic == "mean") .Call(C_dtatools_numeric_mean, value, na.rm) else
        suppressWarnings(getExportedValue("base", generic)(value, na.rm = na.rm))
    .dta_computed(.collapse_missing(result), .declared_dta_storage(x))
}
.summary_facts <- function(x) list(
    value = x, attributes = attributes(x), serialized = serialize(x, NULL),
    compact = .is_unmaterialized_numeric_altrep(x)
)
# Comparing values materializes them, so each value's facts are taken once,
# before any comparison.
.summary_same <- function(...) {
    facts <- lapply(list(...), .summary_facts)
    all(vapply(facts[-1L], identical, NA, facts[[1L]], num.eq = FALSE,
               single.NA = FALSE, attrib.as.set = FALSE))
}

test_that("one compact numeric's mean, min, max and sum match the R code", {
    sets <- list(
        int = c(3, 5), missing = c(1, 2, NA), tagged = c(4, tagged_missing("z"), -2),
        zero = c(0, -0), negative_zero = c(-0, -0), wide = c(1e38, 1e38, -3),
        long = c(2^31 - 30, 2^31 - 40), fraction = c(0.5, 1.25, 3.25e10),
        all_missing = c(NA, tagged_missing("a")), one = 7
    )
    constructors <- list(byte = dta_byte, int = dta_int, long = dta_long, float = dta_float)
    covered <- 0L
    for (set in names(sets)) for (storage in names(constructors)) {
        base <- tryCatch(constructors[[storage]](sets[[set]]), error = function(e) NULL)
        if (is.null(base)) next
        proxy <- set_var_labels(base, "label")
        for (x in list(base, proxy)) for (generic in c("mean", "min", "max", "sum"))
            for (na.rm in c(FALSE, TRUE)) {
                fast <- .summary_fast(x, generic, na.rm)
                info <- paste(set, storage, generic, na.rm)
                if (is.null(fast)) next
                covered <- covered + 1L
                method <- getExportedValue("base", generic)(x, na.rm = na.rm)
                expect_true(.summary_same(fast, .summary_r(x, generic, na.rm), method),
                            info = info)
            }
    }
    expect_gt(covered, 200L)
    # A large sum keeps the kernel's order of addition.
    x <- dta_float(seq(0.1, 3000, by = 0.7))
    expect_true(.summary_same(.summary_fast(x, "sum"), .summary_r(x, "sum")))
    expect_true(.summary_same(.summary_fast(x, "mean"), .summary_r(x, "mean")))
})

test_that("the shortcuts leave other summaries to the R code", {
    x <- dta_int(c(1, 2, NA))
    for (generic in c("mean", "min", "max", "sum")) {
        expect_null(.summary_fast(dta_double(c(1.5, 2)), generic), info = generic)
        expect_null(.summary_fast(.force_altrep_materialization(dta_int(c(1, 2))), generic),
                    info = generic)
        expect_null(.summary_fast(x, generic, NA), info = generic)
    }
    # A metadata proxy's view reads the source by region, not through the
    # method the summary call uses.
    proxy <- set_var_labels(x, "label")
    for (generic in c("min", "max", "sum")) expect_null(.summary_fast(proxy, generic))
    for (generic in c("prod", "range", "any", "all")) expect_null(.summary_fast(x, generic))
    # min() and max() of nothing warn, and the R code returns a bare infinity.
    empty <- dta_int(numeric())
    missing <- dta_int(c(NA, NA))
    for (generic in c("min", "max")) {
        expect_null(.summary_fast(empty, generic))
        expect_null(.summary_fast(missing, generic, TRUE))
        expect_warning(result <- getExportedValue("base", generic)(empty), "no non-missing")
        expect_false(inherits(result, "dta_numeric"))
    }
    # An na.rm that settles through a call is left to the R code.
    for (generic in c("mean", "max")) expect_null(local({
        x <- x
        delayedAssign("na.rm", isTRUE(TRUE))
        if (generic == "mean") .Call(C_dtatools_mean_computed, environment())
        else .Call(C_dtatools_summary_computed, x, generic, environment())
    }), info = generic)
    # The size gate's test hook turns both calls off.
    prior <- .Call(C_dtatools_test_numeric_size_minimum, 0L)
    withr::defer(.Call(C_dtatools_test_numeric_size_minimum, prior))
    expect_null(.summary_fast(x, "mean"))
    expect_null(.summary_fast(x, "max"))
})

test_that("mean() of an operand forced after its admission keeps the R code", {
    skip_if(exists("mean.numeric", envir = globalenv(), inherits = FALSE),
            "the global environment defines mean.numeric()")
    withr::defer(if (exists("mean.numeric", envir = globalenv(), inherits = FALSE))
        rm("mean.numeric", envir = globalenv()))
    # A promise is not read, so a lazy operand leaves the call to the R code.
    expect_null(local({
        delayedAssign("x", dta_int(c(1, 3)))
        .Call(C_dtatools_mean_computed, environment())
    }))
    # The operand installs a method that the R code's second admission sees.
    method <- getS3method("mean", "dta_numeric")
    result <- method({
        assign("mean.numeric", function(x, ...) 17, envir = globalenv())
        dta_int(c(1, 3))
    })
    expect_identical(as.double(result), 17)
})

test_that("the compact mean checks the mean methods but not their base helpers", {
    compact <- dta_int(c(1, 2, NA))
    double <- dta_double(c(1, 2, NA))
    # mean.default() calls isTRUE(na.rm). The full admission declines while
    # it is traced, so the R code calls mean() on a double's values, but the
    # compact mean no longer checks it (ADR 0057).
    hits <- 0L
    suppressMessages(trace("isTRUE", tracer = function() hits <<- hits + 1L,
                           where = baseenv(), print = FALSE))
    withr::defer(suppressMessages(untrace("isTRUE", where = baseenv())))
    # Expectations can call isTRUE() themselves, so the hits are read first.
    fast <- .summary_fast(compact, "mean", na.rm = TRUE)
    hits <- 0L
    result <- mean(compact, na.rm = TRUE)
    compact_hits <- hits
    hits <- 0L
    double_result <- mean(double, na.rm = TRUE)
    double_hits <- hits
    expect_false(is.null(fast))
    expect_identical(compact_hits, 0L)
    expect_true(.summary_same(result, fast, .summary_r(compact, "mean", TRUE)))
    expect_identical(as.double(double_result), 1.5)
    expect_gt(double_hits, 0L)
    # A mean method in the global environment still takes the call.
    skip_if(exists("mean.numeric", envir = globalenv(), inherits = FALSE),
            "the global environment defines mean.numeric()")
    assign("mean.numeric", function(x, ...) 17, envir = globalenv())
    withr::defer(rm("mean.numeric", envir = globalenv()))
    expect_null(.summary_fast(compact, "mean", na.rm = TRUE))
    expect_identical(as.double(mean(compact, na.rm = TRUE)), 17)
})

test_that("the shortcuts read no foreign class or names vector", {
    reads <- 0L
    count <- function() reads <<- reads + 1L
    classed <- dta_int(c(1, 2))
    attr(classed, "class") <- .Call(C_dtatools_callback_character, class(classed), count)
    named <- dta_int(c(1, 2))
    attr(named, "names") <- .Call(C_dtatools_callback_length, c("a", "b"), count)
    expect_true(.is_unmaterialized_numeric_altrep(named))
    # Setting each attribute read it, which spent the probe's one callback.
    .Call(C_dtatools_arm_callback_character, attr(classed, "class", exact = TRUE), count)
    .Call(C_dtatools_arm_callback_character, attr(named, "names", exact = TRUE), count)
    for (x in list(classed, named)) for (generic in c("mean", "max", "sum")) {
        reads <- 0L
        expect_null(.summary_fast(x, generic), info = generic)
        expect_identical(reads, 0L, info = generic)
    }
})

test_that("the shortcuts take only the package's classes", {
    labelled <- dta_int(c(1, 2))
    class(labelled) <- c("dta_numeric", "dta_int", "haven_labelled", "vctrs_vctr", "double")
    subclass <- dta_int(c(1, 2))
    class(subclass) <- c("probe_subclass", class(subclass))
    expect_true(.is_unmaterialized_numeric_altrep(labelled))
    expect_true(.is_unmaterialized_numeric_altrep(subclass))
    for (generic in c("mean", "max", "sum")) {
        expect_false(is.null(.summary_fast(labelled, generic)), info = generic)
        expect_null(.summary_fast(subclass, generic), info = generic)
    }
    # A subclass's names() method runs in the R code's capture, so a mean
    # method it defines there reaches the R code's second admission.
    skip_if(exists("mean.numeric", envir = globalenv(), inherits = FALSE),
            "the global environment defines mean.numeric()")
    skip_if(exists("names.probe_subclass", envir = globalenv(), inherits = FALSE),
            "the global environment defines names.probe_subclass()")
    withr::defer(for (name in c("mean.numeric", "names.probe_subclass"))
        if (exists(name, envir = globalenv(), inherits = FALSE)) rm(list = name, envir = globalenv()))
    assign("names.probe_subclass", function(x) {
        assign("mean.numeric", function(x, ...) 17, envir = globalenv())
        NULL
    }, envir = globalenv())
    expect_identical(as.double(mean(subclass)), 17)
})

test_that("grouped summaries of compact numerics skip the R helpers", {
    skip_if_not_installed("dplyr", "1.2.1")
    ns <- asNamespace("dtatools")
    helpers <- c(".dta_data", ".dta_computed", ".collapse_missing")
    counts <- setNames(integer(length(helpers)), helpers)
    for (helper in helpers) {
        tracer <- substitute(function() counts[[KEY]] <<- counts[[KEY]] + 1L, list(KEY = helper))
        suppressMessages(trace(helper, tracer = eval(tracer), where = ns, print = FALSE))
    }
    withr::defer(for (helper in helpers) suppressMessages(untrace(helper, where = ns)))
    calls <- function(groups, column) {
        data <- dibble(g = rep(seq_len(groups), length.out = 4L * groups),
                       x = column(seq_len(4L * groups)))
        counts[] <<- 0L
        result <- dplyr::summarise(data, m = mean(x), h = max(x), l = min(x, na.rm = TRUE),
                                   s = sum(x), .by = g)
        list(counts = counts, result = result)
    }
    expect_identical(calls(12L, dta_int)$counts, calls(3L, dta_int)$counts)
    result <- calls(3L, dta_int)$result
    expect_identical(as.double(result$m), c(5.5, 6.5, 7.5))
    expect_identical(as.double(result$s), c(22, 26, 30))
    # A double column is not compact and keeps the R code, once per group.
    grown <- calls(12L, dta_double)$counts - calls(3L, dta_double)$counts
    expect_true(all(grown[c(".dta_data", ".dta_computed")] >= 4L * 9L))
})
