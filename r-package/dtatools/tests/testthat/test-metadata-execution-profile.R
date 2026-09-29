test_that("metadata execution probe detects the active evaluator", {
    expected <- .dtatools_execution_profile_expected()
    actual <- .Call(C_dtatools_metadata_execution_profile, .metadata_execution_probe)
    expect_identical(actual, expected)
    expect_identical(!is.null(.metadata_state$dependencies), expected)
    expect_false(.Call(C_dtatools_metadata_execution_profile, NULL))
    expect_false(.Call(C_dtatools_metadata_execution_profile, function() FALSE))
    # Startup mode is process state: editing this variable later cannot change it.
    old <- Sys.getenv("R_DISABLE_BYTECODE", unset = NA_character_)
    on.exit(if (is.na(old)) Sys.unsetenv("R_DISABLE_BYTECODE") else
        Sys.setenv(R_DISABLE_BYTECODE = old))
    if (identical(old, "1")) Sys.unsetenv("R_DISABLE_BYTECODE") else
        Sys.setenv(R_DISABLE_BYTECODE = "1")
    expect_identical(.Call(C_dtatools_metadata_execution_profile, .metadata_execution_probe),
                     actual)
})

test_that("metadata shape admission adds no executable names callbacks", {
    old_jit <- compiler::enableJIT(0)
    on.exit(compiler::enableJIT(old_jit), add = TRUE)
    prototype <- dta_double(c(1, 2))
    calls <- 0L
    trace(".dta_attribute_plan", tracer = function() invisible(NULL),
          where = asNamespace("dtatools"), print = FALSE)
    on.exit(untrace(".dta_attribute_plan", where = asNamespace("dtatools")), add = TRUE)
    trace("names", tracer = function() {
        if (any(vapply(sys.calls(), identical, logical(1), quote(names(source))))) {
            calls <<- calls + 1L
        }
    }, where = baseenv(), print = FALSE)
    on.exit(untrace("names", where = baseenv()), add = TRUE)
    plan <- get(".dta_attribute_plan", asNamespace("dtatools"))
    result <- plan(prototype, "double", temporal = FALSE)
    observed <- calls
    expect_identical(observed, 2L)
    expect_identical(result, attributes(prototype))
})

test_that("metadata shape admission retains positive and nonforcing cases", {
    attempt <- function(source, state = .metadata_state) {
        .Call(C_dtatools_canonical_attribute_plan, source, state)
    }
    prototype <- dta_double(c(1, 2))
    invisible(.dta_attribute_plan(prototype, "double", temporal = FALSE))
    source <- attributes(prototype)
    expect_identical(attempt(source), .dtatools_execution_profile_expected())
    for (bad in list(NULL, list(), unname(source), source[2:1],
                     structure(source, class = "custom"),
                     structure(source, extra = TRUE))) {
        expect_false(attempt(bad))
    }
    calls <- 0L
    state <- new.env(parent = emptyenv())
    makeActiveBinding("dependencies", function() {
        calls <<- calls + 1L
        stop("must not run")
    }, state)
    expect_false(attempt(source, state))
    expect_identical(calls, 0L)
})

test_that("metadata admission preserves environment callbacks", {
    prototype <- dta_double(c(1, 2))
    source <- attributes(prototype)
    plan <- get(".dta_attribute_plan", asNamespace("dtatools"))
    generate <- get(".generate_attributes", asNamespace("dtatools"))
    invisible(plan(prototype, "double", temporal = FALSE))
    invisible(generate(source))
    calls <- 0L
    trace("environment", tracer = function() calls <<- calls + 1L,
          where = baseenv(), print = FALSE)
    on.exit(untrace("environment", where = baseenv()), add = TRUE)
    calls <- 0L
    planned <- plan(prototype, "double", temporal = FALSE)
    plan_calls <- calls
    calls <- 0L
    generated <- generate(source)
    generate_calls <- calls
    expect_identical(plan_calls, 4L)
    expect_identical(generate_calls, 4L)
    expect_identical(planned, source)
    expect_identical(generated, source)
})

test_that("metadata shortcuts retain callbacks after supported closure transformations", {
    saved <- .metadata_state$dependencies
    old_jit <- compiler::enableJIT(0)
    on.exit(compiler::enableJIT(old_jit), add = TRUE)
    on.exit(.metadata_state$dependencies <- saved, add = TRUE)
    fixture <- function() dibble(g = c(2, 1, 2, 1), x = dta_double(c(1, 2, 3, 4)))
    run <- function(data) gen(data, y = x + 1.0, by = g)
    compare <- function(helper, wrapper, transform = NULL) {
        lhs <- fixture()
        rhs <- fixture()
        calls <- 0L
        helper_calls <- 0L
        if (is.null(transform)) {
            trace(helper, tracer = function() helper_calls <<- helper_calls + 1L,
                  where = asNamespace("dtatools"), print = FALSE)
            on.exit(untrace(helper, where = asNamespace("dtatools")), add = TRUE)
        } else {
            original <- get(helper, baseenv(), inherits = FALSE)
            replacement <- transform(original)
            unlockBinding(helper, baseenv())
            assign(helper, replacement, baseenv())
            lockBinding(helper, baseenv())
            on.exit({
                unlockBinding(helper, baseenv())
                assign(helper, original, baseenv())
                lockBinding(helper, baseenv())
            }, add = TRUE)
        }
        trace(wrapper, tracer = function() calls <<- calls + 1L,
              where = baseenv(), print = FALSE)
        on.exit(untrace(wrapper, where = baseenv()), add = TRUE)
        .metadata_state$dependencies <- NULL
        calls <- 0L
        helper_calls <- 0L
        run(lhs)
        expected <- c(calls, helper_calls)
        .metadata_state$dependencies <- saved
        calls <- 0L
        helper_calls <- 0L
        run(rhs)
        observed <- c(calls, helper_calls)
        expect_identical(observed, expected, info = paste(helper, wrapper))
        expect_gt(expected[[1L]], 0L)
        expect_identical(as.double(rhs$y), as.double(lhs$y))
        expect_identical(attributes(rhs$y), attributes(lhs$y))
    }
    for (helper in c("isa", ".set_ops_need_as_vector")) {
        compare(helper, "class", function(f) { body(f) <- body(f); f })
        compare(helper, "class", function(f) {
            body(f) <- body(f)
            compiler::cmpfun(f, options = list(optimize = 0L))
        })
    }
    for (helper in c(".generate_attributes", ".dta_attribute_plan")) {
        for (wrapper in c("is.null", "length", "names")) compare(helper, wrapper)
    }
})
