# ADR 0061: a grouped summary of one column's mean(), min(), max() or sum()
# takes one native call for every group when each group would reach the
# package's method and its native result.

# The plan declines while base's lazy bindings of mean() and mean.default(),
# or the S3 registrations of the package's methods, are unforced. A mean and
# a max of a Stata numeric force them.
invisible(mean(c(1, 2)))
invisible(mean(dta_int(c(1, 2))))
invisible(max(dta_int(c(1, 2))))

.plan_data <- function() dibble(
    g = rep(1:6, c(1, 2, 3, 4, 5, 9)),
    byte = dta_byte(c(4, -1, 7, NA, 3, 2, 100, -100, tagged_missing("a"), 5, 1, 0,
                      2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7)),
    int = dta_int(c(30000, -2, 7, 8, NA, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                    13, 14, 15, 16, 17, 18, 19)),
    long = dta_long(c(2e9, -1, 2e9, 0, 5, NA, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
                      12, 13, 14, 15, 16, 17, 18)),
    float = dta_float(c(0.5, 1.25, -3, NA, tagged_missing("b"), 2.5, 1e30, 1e30,
                        0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2,
                        1.3, 1.4, 1.5, 1.6)),
    labelled = set_val_labels(dta_byte(rep(c(1, 2, NA), 8)), c(low = 1, high = 2)),
    described = set_var_labels(dta_int(seq(-11, 12)), "a label"),
    missing = dta_int(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                        rep(NA, 9))),
    double = dta_double(seq(0.25, 6, by = 0.25))
)

.plan_strip <- function(x) {
    attr(x, ".dtatools_ref_state") <- NULL
    x
}

# Runs a summary with the plan, counting the expressions it takes, or with
# the plan replaced by one that always declines.
.plan_run <- function(run, plan = TRUE) {
    planned <- 0L
    warnings <- character()
    original <- dtatools:::.summary_planned
    replacement <- if (plan) function(quo, mask, groups) {
        result <- original(quo, mask, groups)
        planned <<- planned + !is.null(result)
        result
    } else function(quo, mask, groups) NULL
    testthat::local_mocked_bindings(.summary_planned = replacement, .package = "dtatools")
    outcome <- tryCatch(withCallingHandlers(list(value = .plan_strip(run())),
        warning = function(condition) {
            warnings <<- c(warnings, conditionMessage(condition))
            invokeRestart("muffleWarning")
        }), error = function(condition) list(error = conditionMessage(condition)))
    list(outcome = serialize(outcome, NULL), warnings = warnings, planned = planned)
}

# Whether the summary gives the same value, warnings and errors with the
# plan as with the loop, and how many expressions the plan took.
.plan_compare <- function(run) {
    planned <- .plan_run(run)
    looped <- .plan_run(run, plan = FALSE)
    list(same = identical(planned[1:2], looped[1:2]), planned = planned$planned)
}

# A function whose quosures are made in a child of the global environment,
# as a user's calls are, so that S3 lookup ends at the global environment.
.plan_global <- function(code, ...) .plan_global_call(substitute(code), ...)
.plan_global_call <- function(code, ...) {
    env <- list2env(list(...), parent = globalenv())
    eval(call("function", NULL, code), env)
}

test_that("planned summaries give what the group loop gives", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_data()
    columns <- setdiff(names(data), "g")
    forms <- list(missing = NULL, true = TRUE, false = FALSE)
    planned <- 0L
    for (column in columns) for (generic in c("mean", "min", "max", "sum"))
        for (form in names(forms)) for (by in c("by", "group_by", "none")) {
            call <- if (is.null(forms[[form]])) rlang::call2(generic, rlang::sym(column)) else
                rlang::call2(generic, rlang::sym(column), na.rm = forms[[form]])
            run <- switch(by,
                by = .plan_global(dplyr::summarise(data, m = !!call, .by = g),
                                  data = data, call = call),
                group_by = .plan_global(dplyr::summarise(dplyr::group_by(data, g), m = !!call),
                                        data = data, call = call),
                none = .plan_global(dplyr::summarise(data, m = !!call), data = data, call = call))
            result <- .plan_compare(run)
            info <- paste(column, generic, form, by)
            expect_true(result$same, info = info)
            planned <- planned + result$planned
        }
    expect_gt(planned, 100L)
    # Quosures made in a package frame end S3 lookup at its namespace.
    run <- function() dplyr::summarise(data, m = mean(int), h = max(byte, na.rm = TRUE),
                                       .by = g)
    result <- .plan_compare(run)
    expect_true(result$same)
    expect_identical(result$planned, 2L)
})

test_that("compact columns take the plan and others keep the loop", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_data()
    taken <- function(code) .plan_run(.plan_global_call(substitute(code), data = data))$planned
    expect_identical(taken(dplyr::summarise(data, m = mean(byte), s = sum(int),
                                            l = min(long, na.rm = TRUE), h = max(float),
                                            .by = g)), 4L)
    expect_identical(taken(dplyr::summarise(data, m = mean(labelled), h = max(described),
                                            .by = g)), 2L)
    # A double column is not compact.
    expect_identical(taken(dplyr::summarise(data, m = mean(double), h = max(double),
                                            .by = g)), 0L)
    # The kernel leaves an empty max and a group with no observed value under
    # na.rm to the R code, which warns.
    expect_identical(taken(dplyr::summarise(data, h = max(missing, na.rm = TRUE),
                                            .by = g)), 0L)
    expect_identical(taken(dplyr::summarise(data, h = max(missing), .by = g)), 1L)
})

test_that("summaries whose groups could evaluate differently keep the loop", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_data()
    check <- function(run, planned = 0L) {
        result <- .plan_compare(run)
        expect_true(result$same)
        expect_identical(result$planned, planned)
    }
    summary <- quote(dplyr::summarise(data, m = mean(int), h = max(byte), .by = g))
    in_env <- function(...) {
        env <- list2env(list(data = data, ...), parent = globalenv())
        function() eval(summary, env)
    }
    # Functions and methods the groups would find instead of the package's.
    check(in_env(mean = function(x, ...) 99), planned = 1L)
    check(in_env(max = function(..., na.rm = FALSE) 99), planned = 1L)
    check(in_env(mean.dta_numeric = function(x, ...) 98), planned = 1L)
    check(in_env(max.dta_numeric = function(..., na.rm = FALSE) 97), planned = 1L)
    check(in_env(Summary.dta_numeric = function(..., na.rm = FALSE) 96), planned = 1L)
    # A binding that is not a function is passed over, as R passes it.
    check(in_env(mean = 5, max = "max"), planned = 2L)
    # A promise or active binding on the way would run R code.
    lazy <- in_env()
    delayedAssign("mean", base::mean, assign.env = environment(lazy)$env)
    check(lazy, planned = 1L)
    active <- in_env()
    makeActiveBinding("mean.dta_numeric", function() NULL, environment(active)$env)
    check(active, planned = 1L)
    # A missing argument where the call looks for its function is an error.
    missing_generic <- function(mean) dplyr::summarise(data, m = mean(int), .by = g)
    check(function() missing_generic())
    # A column named for the generic or a method is read while R looks for it.
    named <- data
    named$mean <- data$int
    check(.plan_global(dplyr::summarise(named, m = mean(int), h = max(byte), .by = g),
                       named = named), planned = 1L)
    named <- data
    named$Summary.dta_numeric <- data$int
    check(.plan_global(dplyr::summarise(named, m = mean(int), h = max(byte), .by = g),
                       named = named), planned = 1L)
    # Other forms of the call.
    flag <- TRUE
    for (code in list(
        quote(dplyr::summarise(data, int = mean(int), .by = g)),
        quote(dplyr::summarise(data, m = mean(int, na.rm = NA), .by = g)),
        quote(dplyr::summarise(data, m = mean(int, na.rm = flag), .by = g)),
        quote(dplyr::summarise(data, m = mean(int, trim = 0.1), .by = g)),
        quote(dplyr::summarise(data, m = mean(x = int), .by = g)),
        quote(dplyr::summarise(data, m = mean(.data$int), .by = g)),
        quote(dplyr::summarise(data, m = max(int, byte), .by = g)),
        quote(dplyr::summarise(dplyr::rowwise(data), m = mean(int))))) {
        check(eval(call("function", NULL, code)))
    }
    # A method registered for the generic itself comes before the group's.
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    assign("max.dta_numeric", function(..., na.rm = FALSE) 95, envir = table)
    withr::defer(rm("max.dta_numeric", envir = table))
    check(in_env(), planned = 1L)
})

test_that("later expressions see planned results as the loop builds them", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_data()
    result <- .plan_compare(.plan_global(dplyr::summarise(data, m = max(int),
        d = m * 2, k = mean(m), n = dplyr::n(), s = sum(byte, na.rm = TRUE), .by = g),
        data = data))
    expect_true(result$same)
    expect_gte(result$planned, 2L)
})
