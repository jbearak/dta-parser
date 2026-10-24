# ADR 0061: a grouped summary of one column's mean(), min(), max() or sum()
# takes one native call for every group after the first when each later
# group would reach the package's method and its native result.

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
    planned <- assembled <- 0L
    warnings <- character()
    original <- dtatools:::.summary_planned
    replacement <- if (plan) function(...) {
        result <- original(...)
        planned <<- planned + !is.null(result)
        assembled <<- assembled + !is.null(result$result)
        result
    } else function(...) NULL
    testthat::local_mocked_bindings(.summary_planned = replacement, .package = "dtatools")
    outcome <- tryCatch(withCallingHandlers(list(value = .plan_strip(run())),
        warning = function(condition) {
            warnings <<- c(warnings, conditionMessage(condition))
            invokeRestart("muffleWarning")
        }), error = function(condition) list(error = conditionMessage(condition)))
    list(outcome = serialize(outcome, NULL), warnings = warnings, planned = planned,
         error = !is.null(outcome$error), assembled = assembled)
}

# Whether the summary gives the same value, warnings and errors with the
# plan as with the loop, and how many expressions the plan took.
.plan_compare <- function(run) {
    planned <- .plan_run(run)
    looped <- .plan_run(run, plan = FALSE)
    list(same = identical(planned[1:2], looped[1:2]), planned = planned$planned,
         error = planned$error, assembled = planned$assembled)
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
            expect_false(result$error, info = info)
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
    check <- function(run, planned = 0L, error = FALSE) {
        result <- .plan_compare(run)
        expect_true(result$same)
        expect_identical(result$planned, planned)
        expect_identical(result$error, error)
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
    # An active binding on the way would run R code. A promise would too,
    # but the first group forces it.
    lazy <- in_env()
    delayedAssign("mean", base::mean, assign.env = environment(lazy)$env)
    check(lazy, planned = 2L)
    lazy <- in_env()
    delayedAssign("mean", function(x, ...) 99, assign.env = environment(lazy)$env)
    check(lazy, planned = 1L)
    active <- in_env()
    makeActiveBinding("mean.dta_numeric", function() NULL, environment(active)$env)
    check(active, planned = 1L)
    # A missing argument where the call looks for its function is an error.
    missing_generic <- function(mean) dplyr::summarise(data, m = mean(int), .by = g)
    check(function() missing_generic(), error = TRUE)
    # A column named for the generic or a method is read while R looks for it.
    named <- data
    named$mean <- data$int
    check(.plan_global(dplyr::summarise(named, m = mean(int), h = max(byte), .by = g),
                       named = named), planned = 1L)
    named <- data
    named$Summary.dta_numeric <- data$int
    check(.plan_global(dplyr::summarise(named, m = mean(int), h = max(byte), .by = g),
                       named = named), planned = 1L)
    # The mask's pronouns and R's dots shadow columns that take their names.
    dotted <- data
    dotted$.env <- data$int
    check(.plan_global(dplyr::summarise(dotted, m = mean(.env), .by = g), dotted = dotted))
    dotted <- data
    dotted$..1 <- data$int
    wrapper <- function(...) dplyr::summarise(dotted, m = mean(..1), .by = g)
    check(function() wrapper(dta_int(5)))
    # A primitive rebound in base is what the groups call. The expectations
    # wait until it is restored, since they call max() too.
    restore <- function() {
        assign("max", .Primitive("max"), envir = baseenv())
        lockBinding("max", baseenv())
    }
    unlockBinding("max", baseenv())
    withr::defer(if (bindingIsLocked("max", baseenv())) NULL else restore())
    assign("max", .Primitive("min"), envir = baseenv())
    rebound <- .plan_compare(in_env())
    restore()
    expect_true(rebound$same)
    expect_identical(rebound$planned, 1L)
    expect_false(rebound$error)
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

test_that("other columns split in the first group's evaluation", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(g = rep(1:2, each = 2),
                   x = vctrs::new_vctr(as.double(1:4), class = "plan_custom"))
    table <- asNamespace("vctrs")[[".__S3MethodsTable__."]]
    registerS3method("vec_restore", "plan_custom", function(x, to, ...)
        vctrs::new_vctr(vctrs::vec_data(x) + 10 * dplyr::cur_group_id(),
                        class = "plan_custom"), envir = asNamespace("vctrs"))
    withr::defer(rm("vec_restore.plan_custom", envir = table))
    result <- .plan_compare(.plan_global(dplyr::summarise(data, m = mean(x), .by = g),
                                         data = data))
    expect_true(result$same)
    expect_false(result$error)
    expect_identical(result$planned, 0L)
})

test_that("a one-shot debugger stops in the first group", {
    skip_if_not_installed("callr")
    skip_if_not_installed("dplyr", "1.2.1")
    records <- .dtatools_child_r("summary-plan-debugonce", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        data <- dibble(g = rep(1:3, each = 2), x = dta_int(1:6))
        invisible(dplyr::summarise(data, m = mean(x), h = max(x), .by = g))
        targets <- list(base::mean, utils::getS3method("mean", "dta_numeric"),
                        utils::getS3method("Summary", "dta_numeric"))
        calls <- list(quote(mean(x)), quote(mean(x)), quote(max(x)))
        lapply(seq_along(targets), function(i) {
            lines <- utils::capture.output({
                debugonce(targets[[i]])
                cat("BEFORE_SUMMARY\n")
                value <- tryCatch(eval(rlang::expr(dplyr::summarise(data, m = !!calls[[i]],
                                                                   .by = g))),
                                  error = identity)
                cat("AFTER_SUMMARY\n")
                invisible(tryCatch(max(dta_int(1:2)) + mean(dta_int(1:2)), error = identity))
                cat("AFTER_EXPLICIT_CALL\n")
            })
            list(lines = lines)
        })
    }, args = list(.libPaths()), timeout = 20)
    for (record in records) {
        entry <- grep("^debugging in:", record$lines)
        expect_length(entry, 1L)
        expect_true(all(entry > match("BEFORE_SUMMARY", record$lines) &
                        entry < match("AFTER_SUMMARY", record$lines)))
    }
})

test_that("mutate() plans a summary of one column across groups", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_data()
    columns <- setdiff(names(data), "g")
    planned <- 0L
    for (column in columns) for (generic in c("mean", "min", "max", "sum"))
        for (na.rm in list(NULL, TRUE)) {
            call <- if (is.null(na.rm)) rlang::call2(generic, rlang::sym(column)) else
                rlang::call2(generic, rlang::sym(column), na.rm = na.rm)
            result <- .plan_compare(.plan_global(
                dplyr::mutate(data, m = !!call, .by = g), data = data, call = call))
            expect_true(result$same, info = paste(column, generic, deparse(na.rm)))
            expect_false(result$error, info = paste(column, generic, deparse(na.rm)))
            planned <- planned + result$planned
        }
    expect_gt(planned, 40L)
    taken <- function(code) .plan_compare(.plan_global_call(substitute(code), data = data))
    # A result may replace its column, and later expressions read it.
    result <- taken(dplyr::mutate(data, int = mean(int), d = int * 2, k = max(int), .by = g))
    expect_true(result$same)
    expect_identical(result$planned, 2L)
    result <- taken(dplyr::mutate(dplyr::group_by(data, g), m = mean(byte), .keep = "used"))
    expect_true(result$same)
    expect_identical(result$planned, 1L)
    # One group, and an empty group, recycle each result in the loop.
    result <- taken(dplyr::mutate(data, m = mean(int)))
    expect_true(result$same)
    expect_identical(result$planned, 0L)
    empty <- dplyr::group_by(dplyr::mutate(data, f = factor(g, levels = 1:7)), f, .drop = FALSE)
    result <- .plan_compare(.plan_global(dplyr::mutate(empty, m = mean(int)), empty = empty))
    expect_true(result$same)
    expect_identical(result$planned, 0L)
})

test_that("later expressions see planned results as the loop builds them", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_data()
    result <- .plan_compare(.plan_global(dplyr::summarise(data, m = max(int),
        d = m * 2, k = mean(m), n = dplyr::n(), s = sum(byte, na.rm = TRUE), .by = g),
        data = data))
    expect_true(result$same)
    expect_gte(result$planned, 2L)
    result <- .plan_compare(.plan_global(dplyr::reframe(data, m = mean(int),
        h = max(byte), .by = g), data = data))
    expect_true(result$same)
    expect_identical(result$planned, 2L)
})

# ADR 0062: with eight groups or more, the plan builds the combined vector
# of compact results without the results themselves.
.plan_wide <- function() dibble(
    g = rep(1:12, c(1, 2, 3, 2, 1, 4, 2, 3, 1, 2, 3, 2)),
    byte = dta_byte(c(4, -1, 7, NA, 3, 2, 100, -100, tagged_missing("a"), 5, 1, 0,
                      2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 9)),
    int = dta_int(c(30000, -2, 7, 8, NA, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                    13, 14, 15, 16, 17, 18, 19, 20, 21)),
    long = dta_long(c(2e9, -1, 2e9, 0, 5, NA, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
                      12, 13, 14, 15, 16, 17, 18, 19, 20)),
    float = dta_float(c(0.5, 1.25, -3, NA, tagged_missing("b"), 2.5, 1e30, 1e30,
                        0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2,
                        1.3, 1.4, 1.5, 1.6, 1.7, 1.8)),
    labelled = set_val_labels(dta_byte(rep(c(1, 2, NA), length.out = 26)),
                              c(low = 1, high = 2)),
    described = set_var_labels(dta_int(seq(-12, 13)), "a label"),
    whole = dta_int(rep(c(4, 8, 12, 16), length.out = 26)),
    huge = dta_float(rep(1.5e38, 26)),
    double = dta_double(seq(0.25, 6.5, by = 0.25))
)

test_that("summaries of eight groups or more build the combined vector", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_wide()
    columns <- setdiff(names(data), "g")
    forms <- list(missing = NULL, true = TRUE, false = FALSE)
    assembled <- 0L
    for (column in columns) for (generic in c("mean", "min", "max", "sum"))
        for (form in names(forms)) for (by in c("by", "group_by")) {
            call <- if (is.null(forms[[form]])) rlang::call2(generic, rlang::sym(column)) else
                rlang::call2(generic, rlang::sym(column), na.rm = forms[[form]])
            run <- switch(by,
                by = .plan_global(dplyr::summarise(data, m = !!call, .by = g),
                                  data = data, call = call),
                group_by = .plan_global(dplyr::summarise(dplyr::group_by(data, g), m = !!call),
                                        data = data, call = call))
            result <- .plan_compare(run)
            info <- paste(column, generic, form, by)
            expect_true(result$same, info = info)
            expect_false(result$error, info = info)
            assembled <- assembled + result$assembled
        }
    expect_gt(assembled, 80L)
    # Later expressions read the combined vector one group at a time.
    result <- .plan_compare(.plan_global(dplyr::summarise(data, m = mean(int),
        d = m * 2, k = max(m), j = mean(m), n = dplyr::n(), s = sum(m) + dplyr::cur_group_id(),
        .by = g), data = data))
    expect_true(result$same)
    expect_false(result$error)
    expect_gte(result$assembled, 3L)
})

test_that("results the combine would leave to vctrs keep their group results", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- .plan_wide()
    check <- function(run, planned, assembled = 0L) {
        result <- .plan_compare(run)
        expect_true(result$same)
        expect_false(result$error)
        expect_identical(result$planned, planned)
        expect_identical(result$assembled, assembled)
    }
    # Fewer than eight groups.
    check(.plan_global(dplyr::summarise(data, m = mean(int), .by = whole),
                       data = data), planned = 1L)
    # A long mean that is not whole is a double, which is not compact.
    check(.plan_global(dplyr::summarise(data, m = mean(long), .by = g), data = data),
          planned = 1L)
    # A float sum past float's range is a double too.
    check(.plan_global(dplyr::summarise(data, s = sum(huge), .by = g), data = data),
          planned = 1L)
    # reframe() reads each result.
    check(.plan_global(dplyr::reframe(data, m = mean(int), .by = g), data = data),
          planned = 1L)
    # A common type method in the global environment.
    assign("vec_ptype2.dta_numeric.dta_numeric",
           dtatools:::vec_ptype2.dta_numeric.dta_numeric, envir = globalenv())
    withr::defer(rm("vec_ptype2.dta_numeric.dta_numeric", envir = globalenv()))
    check(.plan_global(dplyr::summarise(data, m = mean(int), .by = g), data = data),
          planned = 1L)
})
