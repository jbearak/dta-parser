# The R calculation predates the fused scan and is kept as a differential
# oracle for compensated summation, weighting and rounded-mean moments.
.native_summary_reference <- function(value, weights, weight, detail, meanonly) {
    names <- c("N", "sum_w", "mean", if (!meanonly) c("Var", "sd"),
               "min", "max", "sum", if (detail)
                   c("skewness", "kurtosis", paste0("p", c(1, 5, 10, 25, 50, 75, 90, 95, 99))))
    out <- stats::setNames(rep(NA_real_, length(names)), names)
    out[c("N", "sum_w", "sum")] <- 0
    smallest <- largest <- rep(NA_real_, 4L)
    if (is.character(value)) value <- rep(NA_real_, length(value))
    else value <- dtatools:::.summarize_numeric(value)
    if (any(is.infinite(value)))
        stop("summary inputs must be finite or missing", call. = FALSE)
    keep <- !is.na(value) & !is.na(weights) & weights != 0
    x <- value[keep]
    w <- weights[keep]
    n <- length(x)
    r <- as.list(out[c("N", "sum_w", "sum")])
    if (n) {
        total <- dtatools:::.summarize_sum(w)
        out["N"] <- if (identical(weight, "fweight")) total else n
        out["sum_w"] <- total
        out["sum"] <- dtatools:::.summarize_sum(w * x)
        out["min"] <- min(x)
        out["max"] <- max(x)
        if (total != 0 && is.finite(out[["sum"]] / total)) {
            # Center the moments on the rounded mean, as Stata does.
            mu <- out[["sum"]] / total
            out["mean"] <- mu
            if (!meanonly) {
                centered <- x - mu
                m2 <- dtatools:::.summarize_sum(w * centered^2) / total
                variance <- if (identical(weight, "aweight")) {
                    if (n > 1L) m2 * n / (n - 1) else NA_real_
                } else if (total != 1 && (n > 1L || identical(weight, "fweight"))) {
                    m2 * total / (total - 1)
                } else NA_real_
                out["Var"] <- variance
                out["sd"] <- if (!is.na(variance) && variance >= 0)
                    sqrt(variance) else NA_real_
            }
            if (detail && is.finite(m2) && m2 > 0) {
                out["skewness"] <- (dtatools:::.summarize_sum(w * centered^3) / total) / sqrt(m2^3)
                out["kurtosis"] <- (dtatools:::.summarize_sum(w * centered^4) / total) / m2^2
            }
        }
        if (detail) {
            order <- order(x)
            ordered <- x[order]
            smallest[seq_len(min(n, 4L))] <- utils::head(ordered, 4L)
            largest[5L - rev(seq_len(min(n, 4L)))] <- utils::tail(ordered, 4L)
            ps <- c(1, 5, 10, 25, 50, 75, 90, 95, 99)
            out[paste0("p", ps)] <- dtatools:::.summarize_percentiles(ordered,
                w[order], total, ps)
        }
        out[!is.finite(out)] <- NA_real_
        r <- as.list(out)
    }
    list(statistics = out, r = r, smallest = smallest, largest = largest)
}

.native_summary_freeze <- function(value, chunk_rows = 7) {
    .Call(dtatools:::C_dtatools_owned_numeric_freeze, value, chunk_rows)
}

test_that("mean and range preserve compact storage and base precision", {
    values <- c(rep(0, 4095), 64, 1, -64, NA_real_, tagged_missing(letters))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        for (retained in c(FALSE, TRUE)) {
            x <- constructor(values)
            if (retained && dta_storage_type(x) != "double")
                x <- .native_summary_freeze(x)
            for (remove in c(FALSE, TRUE)) {
                expected <- dtatools:::.dta_computed(
                    dtatools:::.collapse_missing(mean(values, na.rm = remove)),
                    dta_storage_type(x))
                expect_identical(mean(x, na.rm = remove), expected)
                expected <- dtatools:::.dta_computed(
                    dtatools:::.collapse_missing(range(values, na.rm = remove)),
                    dta_storage_type(x))
                expect_identical(range(x, na.rm = remove), expected)
            }
            if (dta_storage_type(x) != "double")
                expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        }
    }
    for (values in list(c(1e16, 1, -1e16), c(8e307, 8e307, 8e307),
                        c(rep(0, 65535), 2^120, 1, -2^120, 1),
                        c(1, 1 + .Machine$double.eps, 1))) {
        x <- dta_double(values)
        expect_identical(as.double(mean(x)), mean(values))
    }
})

test_that("mean and range keep fallback arguments and empty policies", {
    x <- dta_int(c(8, 2, 3, NA_real_))
    for (trim in c(0, .1, .5))
        expect_identical(mean(x, trim = trim, na.rm = TRUE),
            dtatools:::.dta_computed(
                mean(c(8, 2, 3, NA_real_), trim = trim, na.rm = TRUE), "int"))
    expect_error(mean(x, trim = "bad"), "trim")
    expect_error(mean(x, trim = c(0, 1)), "trim")
    expect_identical(as.double(range(x, c(-5L, 12L), na.rm = TRUE)), c(-5, 12))
    expect_identical(as.double(range(x, finite = TRUE)), c(2, 8))
    warnings <- character()
    empty <- withCallingHandlers(range(dta_int(numeric())), warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    })
    expect_length(warnings, 2L)
    expect_true(all(grepl("no non-missing", warnings)))
    expect_identical(empty, c(Inf, -Inf))
    expect_identical(as.double(range(dta_byte(c(NA, NA)), na.rm = TRUE)),
                     c(NA_real_, NA_real_))
    expect_identical(dta_storage_type(range(dta_byte(1), dta_long(2))), "long")
    expect_identical(as.double(mean(dta_int(numeric()))), NA_real_)
})

test_that("range preserves NULL operands and nonempty all-missing silence", {
    cases <- list(
        list(function() range(dta_int(c(NA, NA)), na.rm = TRUE),
             c(NA_real_, NA_real_), "int"),
        list(function() range(dta_byte(NA), c(NA_real_, NaN), NULL, na.rm = TRUE),
             c(NA_real_, NA_real_), "byte"),
        list(function() range(dta_float(c(2.5, 3.5)), NULL, NULL, na.rm = TRUE),
             c(2.5, 3.5), "float"),
        list(function() range(dta_long(tagged_missing(c("a", "z"))), NULL,
                              na.rm = TRUE),
             c(NA_real_, NA_real_), "long")
    )
    for (case in cases) {
        warnings <- character()
        actual <- withCallingHandlers(case[[1]](), warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
        })
        expect_identical(warnings, character())
        expect_identical(as.double(actual), case[[2]])
        expect_identical(dta_storage_type(actual), case[[3]])
    }
    warnings <- character()
    empty <- withCallingHandlers(range(dta_int(numeric()), NULL, na.rm = TRUE),
        warning = function(w) {
            warnings <<- c(warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
        })
    expect_length(warnings, 2L)
    expect_true(all(grepl("no non-missing", warnings)))
    expect_identical(empty, c(Inf, -Inf))
})

test_that("fused summary moments match the previous weighted calculation", {
    samples <- list(
        list(x = c(1e16, 1, -1e16), w = c(1, 1, 1)),
        list(x = c(1, 2, 4, 8, NA, tagged_missing("z")), w = c(1, 0, 2, 3, 4, 5)),
        list(x = c(1, 2, 3, 4), w = c(1e307, 1e307, 1e307, 1e307)),
        list(x = c(1e-100, 2e-100, 3e-100), w = c(.2, .1, .1)),
        list(x = c(1, 1e150, -1e150), w = c(1, 2, 3)),
        list(x = c(1, 2, 3), w = c(-2, 1, 1)),
        list(x = numeric(), w = numeric()),
        list(x = c(NA_real_, tagged_missing("a")), w = c(1, 1)))
    for (sample in samples) for (kind in list(NULL, "aweight", "fweight", "iweight")) {
        for (mode in c("default", "detail", "meanonly")) {
            detail <- mode == "detail"
            meanonly <- mode == "meanonly"
            expected <- .native_summary_reference(sample$x, sample$w, kind,
                                                  detail, meanonly)
            actual <- dtatools:::.summarize_statistics(dta_double(sample$x),
                sample$w, kind, detail, meanonly)
            expect_equal(actual, expected, tolerance = 0,
                         info = paste(kind, mode, deparse(sample$x)))
        }
    }
})

test_that("fused scans cross retained chunks and retain the input backing", {
    values <- rep_len(c(-7, 2, 8, NA, tagged_missing("b")), 65539)
    weights <- rep_len(c(1, 0, 2, 3, 4, NA), length(values))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        x <- .native_summary_freeze(constructor(values), 4093)
        proxy <- .Call(dtatools:::C_dtatools_metadata_copy, x)
        gc()
        expect_equal(dtatools:::.summarize_statistics(proxy, weights, "aweight", FALSE, FALSE),
                     .native_summary_reference(values, weights, "aweight", FALSE, FALSE),
                     tolerance = 0)
        expect_identical(as.double(range(proxy, na.rm = TRUE)), c(-7, 8))
        expect_identical(as.double(mean(proxy, na.rm = TRUE)),
                         mean(values, na.rm = TRUE))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(proxy))
    }
    legacy <- read_dta(fixture("synthetic_v111.dta"))
    for (name in c("b", "i", "l", "f")) {
        x <- legacy[[name]]
        ordinary <- as.double(x)
        expect_identical(mean(x, na.rm = TRUE),
                         dtatools:::.dta_computed(mean(ordinary, na.rm = TRUE),
                                                 dta_storage_type(x)))
        expect_identical(as.double(range(x, na.rm = TRUE)),
                         range(ordinary, na.rm = TRUE))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(x))
    }
})

test_that("foreign summary providers retain the previous read path", {
    run <- function(operation, reference = FALSE, detail = FALSE) {
        calls <- 0L
        value <- .Call(dtatools:::C_dtatools_callback_double,
            c(1, NA_real_, 3), function() { calls <<- calls + 1L; gc() }, TRUE)
        if (operation != "summ") attributes(value) <- attributes(dta_double(1:3))
        answer <- if (operation == "summ") {
            if (reference) .native_summary_reference(value, c(1, 2, 3),
                "aweight", detail, FALSE)
            else dtatools:::.summarize_statistics(value, c(1, 2, 3),
                "aweight", detail, FALSE)
        } else if (operation == "mean") {
            if (reference) dtatools:::.dta_computed(dtatools:::.collapse_missing(
                mean(dtatools:::.dta_data(value), na.rm = TRUE)), "double")
            else mean(value, na.rm = TRUE)
        } else {
            if (reference) dtatools:::.dta_computed(dtatools:::.collapse_missing(
                range(dtatools:::.dta_data(value, ordinary = TRUE), na.rm = TRUE)),
                "double")
            else range(value, na.rm = TRUE)
        }
        list(answer = answer, calls = calls)
    }
    for (operation in c("mean", "range", "summ"))
        expect_identical(run(operation), run(operation, reference = TRUE))
    expect_identical(run("summ", detail = TRUE),
                     run("summ", reference = TRUE, detail = TRUE))
})

test_that("full-sample summaries copy foreign ALTREP inputs for the fused scan", {
    d <- data.frame(x = as.double(seq_len(10)), y = seq_len(10))
    expect_true(dtatools:::.is_altrep(d$x))
    expect_true(dtatools:::.is_altrep(d$y))
    local_mocked_bindings(.summarize_moments_fallback = function(...)
        stop("unexpected R fallback"), .package = "dtatools")
    result <- summ(d, x, y, detail = TRUE)
    expect_identical(result$statistics$sum, c(55, 55))
    expect_identical(result$statistics$p50, c(5.5, 5.5))
})

test_that("summary na.rm promises retain input capture order", {
    run <- function(constructor, operation, reference) {
        x <- constructor(c(1, 2, 3))
        remove <- function() {
            .Call(dtatools:::C_dtatools_mutate_first_numeric_altrep, x, 77)
            gc()
            TRUE
        }
        actual <- if (reference && operation == "range") {
            # The public group generic may force arguments before dispatch.
            # Invoke it with the old method instead of calling its body as an
            # ordinary function, which would change the oracle's promise order.
            current <- getS3method("Summary", "dta_numeric")
            legacy <- function(..., na.rm = FALSE) {
                inputs <- list(...)
                declared <- Filter(function(x) inherits(x, "dta_numeric"), inputs)
                minimum <- Reduce(dtatools:::.dta_promote,
                    vapply(declared, dtatools:::.declared_dta_storage, character(1)))
                arguments <- c(lapply(inputs, function(value) {
                    if (inherits(value, "dta_numeric"))
                        dtatools:::.dta_data(value, ordinary = TRUE) else value
                }), list(na.rm = na.rm))
                dtatools:::.dta_computed(dtatools:::.collapse_missing(
                    do.call(base::range, arguments)), minimum)
            }
            registerS3method("Summary", "dta_numeric", legacy, envir = asNamespace("base"))
            on.exit(registerS3method("Summary", "dta_numeric", current,
                                     envir = asNamespace("base")), add = TRUE)
            range(x, na.rm = remove())
        } else if (reference) {
            result <- mean(dtatools:::.dta_data(x), na.rm = remove())
            dtatools:::.dta_computed(dtatools:::.collapse_missing(result),
                                    dta_storage_type(x))
        } else if (operation == "mean") mean(x, na.rm = remove())
        else range(x, na.rm = remove())
        list(result = actual, source = as.double(x))
    }
    for (constructor in list(dta_byte, dta_float, dta_double))
        for (operation in c("mean", "range"))
            expect_identical(run(constructor, operation, FALSE),
                             run(constructor, operation, TRUE))
})

.native_summary_binding <- function(env, name, replacement, code) {
    present <- exists(name, envir = env, inherits = FALSE)
    original <- if (present) get(name, envir = env, inherits = FALSE) else NULL
    locked <- present && bindingIsLocked(name, env)
    if (locked) unlockBinding(name, env)
    assign(name, replacement, envir = env)
    on.exit({
        if (bindingIsActive(name, env)) rm(list = name, envir = env)
        if (present) assign(name, original, envir = env)
        else rm(list = name, envir = env)
        if (locked) lockBinding(name, env)
    }, add = TRUE)
    force(code)
}

.native_legacy_mean <- function(x, ..., na.rm = FALSE) {
    result <- suppressWarnings(mean(dtatools:::.dta_data(x), ..., na.rm = na.rm))
    dtatools:::.dta_computed(dtatools:::.collapse_missing(result),
                            dtatools:::.declared_dta_storage(x))
}

test_that("unchanged base summary dispatch admits native scans", {
    # Settle the ordinary base helpers before testing the callback-free gate.
    mean(c(1, 2, NA_real_), na.rm = TRUE)
    range(c(1, 2, NA_real_), na.rm = TRUE)
    frame <- new.env(parent = asNamespace("dtatools"))
    frame$value <- dtatools:::.dta_data(dta_int(1:3))
    frame$na.rm <- TRUE
    frame$operation <- base::range
    frame$arguments <- list(frame$value)
    expect_true(.Call(dtatools:::C_dtatools_mean_admitted, frame))
    expect_true(.Call(dtatools:::C_dtatools_range_admitted, frame))
})

test_that("summary admission leaves executable na.rm promises untouched", {
    for (gate in list(dtatools:::C_dtatools_mean_admitted,
                      dtatools:::C_dtatools_range_admitted)) {
        frame <- new.env(parent = asNamespace("dtatools"))
        frame$value <- dtatools:::.dta_data(dta_int(1:3))
        frame$operation <- base::range
        frame$arguments <- list(frame$value)
        events <- 0L
        delayedAssign("na.rm", { events <<- events + 1L; TRUE },
                      assign.env = frame, eval.env = environment())
        expect_false(.Call(gate, frame))
        expect_identical(events, 0L)
        rm("na.rm", envir = frame)
        makeActiveBinding("na.rm", function() { events <<- events + 1L; TRUE }, frame)
        expect_false(.Call(gate, frame))
        expect_identical(events, 0L)
        rm("na.rm", envir = frame)
        settled <- TRUE
        delayedAssign("na.rm", settled, assign.env = frame, eval.env = environment())
        expect_true(.Call(gate, frame))
    }
})

test_that("classed na.rm cannot change the already selected mean method", {
    table <- get(".__S3MethodsTable__.", asNamespace("base"), inherits = FALSE)
    run <- function(reference) {
        x <- dta_int(c(1, NA_real_, 3))
        flag <- structure(TRUE, class = "native_mean_flag")
        is_missing <- function(x) {
            registerS3method("mean", "default", function(x, ...) 17,
                             envir = asNamespace("base"))
            TRUE
        }
        .native_summary_binding(table, "is.na.native_mean_flag", is_missing, {
            .native_summary_binding(table, "mean.default", base::mean.default, {
                if (reference) {
                    .native_summary_binding(table, "mean.dta_numeric", .native_legacy_mean,
                                            mean(x, na.rm = flag))
                } else mean(x, na.rm = flag)
            })
        })
    }
    expect_identical(run(FALSE), run(TRUE))
    expect_identical(as.double(run(FALSE)), NA_real_)
})

test_that("registered bare mean methods precede na.rm evaluation", {
    table <- get(".__S3MethodsTable__.", asNamespace("base"), inherits = FALSE)
    x <- dta_int(1:3)
    for (method in c("mean.default", "mean.numeric", "mean.double")) {
        .native_summary_binding(table, method, function(x, ...) 17, {
            expect_identical(as.double(mean(x, na.rm = TRUE)), 17)
            expect_identical(as.double(mean(x, na.rm = stop("na.rm forced"))), 17)
        })
        .native_summary_binding(table, method, function(x, ...) stop("selected mean method"), {
            expect_error(mean(x, na.rm = TRUE), "selected mean method")
            expect_error(mean(x, na.rm = stop("na.rm forced")), "selected mean method")
        })
    }
})

test_that("mean declines active and delayed S3 bindings without reading them", {
    table <- get(".__S3MethodsTable__.", asNamespace("base"), inherits = FALSE)
    run <- function(mode, reference) {
        events <- character()
        .native_summary_binding(table, "mean.default", function(x, ...) 17, {
            rm("mean.default", envir = table)
            method <- function() {
                events <<- c(events, "lookup")
                function(x, ...) { events <<- c(events, "method"); 17 }
            }
            if (mode == "active") makeActiveBinding("mean.default", method, table)
            else delayedAssign("mean.default", method(), assign.env = table,
                               eval.env = environment())
            x <- dta_int(1:3)
            call <- function() mean(x, na.rm = stop("na.rm forced"))
            result <- if (reference) {
                .native_summary_binding(table, "mean.dta_numeric", .native_legacy_mean, call())
            } else call()
            list(result = result, events = events)
        })
    }
    for (mode in c("active", "delayed"))
        expect_identical(run(mode, FALSE), run(mode, TRUE))
})

test_that("mean honors replaced and traced generic and default bindings", {
    base <- asNamespace("base")
    table <- get(".__S3MethodsTable__.", base, inherits = FALSE)
    x <- dta_int(1:3)
    generic <- function(x, ...) {
        if (inherits(x, "dta_numeric")) UseMethod("mean") else 17
    }
    .native_summary_binding(base, "mean", generic, {
        expect_identical(as.double(mean(x, na.rm = stop("na.rm forced"))), 17)
    })
    .native_summary_binding(base, "mean.default", function(x, ...) 17, {
        actual <- mean(x, na.rm = TRUE)
        expected <- .native_summary_binding(table, "mean.dta_numeric", .native_legacy_mean,
                                            mean(x, na.rm = TRUE))
        expect_identical(actual, expected)
    })
    for (name in c("mean", "mean.default")) {
        run <- function(reference) {
            events <- new.env(parent = emptyenv())
            events$count <- 0L
            tracer <- substitute(assign("count", get("count", envir = EVENTS) + 1L,
                                        envir = EVENTS), list(EVENTS = events))
            suppressMessages(trace(name, tracer = tracer, print = FALSE, where = base))
            on.exit(suppressMessages(untrace(name, where = base)), add = TRUE)
            result <- if (reference) {
                .native_summary_binding(table, "mean.dta_numeric", .native_legacy_mean,
                                        mean(x, na.rm = TRUE))
            } else mean(x, na.rm = TRUE)
            list(result = result, events = events$count)
        }
        expect_identical(run(FALSE), run(TRUE))
    }
})

test_that("range honors replaced and traced default implementations", {
    base <- asNamespace("base")
    x <- dta_int(1:3)
    for (name in c("range.default", ".rangeNum")) {
        .native_summary_binding(base, name,
            function(..., na.rm = FALSE, finite = FALSE, isNumeric = is.numeric) c(-7, 17), {
                expect_identical(as.double(range(x)), c(-7, 17))
            })
    }
    suppressMessages(trace("range.default", tracer = quote(stop("traced range")),
                           print = FALSE, where = base))
    on.exit(suppressMessages(untrace("range.default", where = base)), add = TRUE)
    expect_error(range(x), "traced range")
})
