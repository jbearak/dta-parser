test_that("numeric kernel diagnostics retain canonical compiled route contracts", {
    supported <- .dtatools_execution_profile_expected()
    scalar_dependencies_supported <-
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
    expect_identical(!is.null(.numeric_helper_state$dependencies), supported)
    expect_identical(!is.null(.scalar_arith_dependencies), scalar_dependencies_supported)
    attempt <- function(minimum = "double", temporal = 0L, storage = "double") {
        value <- c(1, 2)
        x <- dta_double(value); y <- 1; op <- "+"
        list(
            scalar = .Call(C_dtatools_scalar_arithmetic, value, y, environment(),
                           .computed_storage_getter, .scalar_arith_dependencies),
            computed = .Call(C_dtatools_computed_numeric, value, environment(),
                             .computed_storage_getter, .computed_numeric_dependencies),
            construct = .Call(C_dtatools_construct_double, value, environment(),
                              .strict_double_dependencies),
            holds = .Call(C_dtatools_double_fits, value, environment(),
                          .strict_double_dependencies)
        )
    }
    # testthat clones package bindings; synthetic inspection frames must use
    # the actual lexical namespace used by the production helper closures.
    environment(attempt) <- asNamespace("dtatools")
    invisible(dta_double(c(1, 2)) + 1)
    invisible(get(".dta_storage_holds", asNamespace("dtatools"))(c(1, 2), "double"))
    actual <- attempt()
    if (!supported) {
        expect_identical(actual, list(scalar = NULL, computed = NULL,
                                     construct = NULL, holds = NULL))
    } else {
        if (!scalar_dependencies_supported) expect_null(actual$scalar) else
            expect_type(actual$scalar, "double")
        expect_type(actual$computed, "list")
        expect_type(actual$construct, "double")
        expect_identical(actual$holds, TRUE)
    }
})

test_that("numeric routes preserve executable skipped-helper callbacks", {
    source <- dta_double(c(1, 2))
    saved <- .numeric_helper_state$dependencies
    on.exit(.numeric_helper_state$dependencies <- saved, add = TRUE)
    operations <- list(
        scalar = function() source + 1,
        computed = function() source + c(1, 1),
        construct = function() dta_double(c(1, 2)),
        holds = function() get(".dta_storage_holds", asNamespace("dtatools"))(c(1, 2), "double")
    )
    helpers <- c(".dta_read_is_na", ".collapse_missing", ".dta_computed",
                 ".tab_missing_codes", ".encode_dta_temporal",
                 ".dta_storage_candidates", ".invalid_dta_observed",
                 ".construct_dta_numeric_trusted", ".metadata_copy",
                 ".repair_data_table_container", ".construct_dta_numeric",
                 ".dta_storage_holds", "is.primitive")
    compare <- function(helper) {
        where <- if (helper == "is.primitive") baseenv() else asNamespace("dtatools")
        hits <- 0L
        trace(helper, tracer = function() hits <<- hits + 1L, where = where, print = FALSE)
        on.exit(untrace(helper, where = where), add = TRUE)
        for (name in names(operations)) {
            .numeric_helper_state$dependencies <- NULL
            hits <- 0L
            expected <- operations[[name]]()
            expected_hits <- hits
            .numeric_helper_state$dependencies <- saved
            hits <- 0L
            observed <- operations[[name]]()
            observed_hits <- hits
            expect_identical(observed_hits, expected_hits, info = paste(helper, name))
            expect_identical(observed, expected, info = paste(helper, name))
        }
    }
    for (helper in helpers) compare(helper)
})

test_that("numeric admission adds no environment callbacks", {
    source <- dta_double(c(1, 2))
    calls <- 0L
    trace("environment", tracer = function() calls <<- calls + 1L,
          where = baseenv(), print = FALSE)
    on.exit(untrace("environment", where = baseenv()), add = TRUE)
    calls <- 0L
    scalar <- source + 1
    computed <- source + c(1, 1)
    construct <- dta_double(c(1, 2))
    holds <- .dta_storage_holds(c(1, 2), "double")
    observed <- calls
    expect_identical(observed, 0L)
    expect_identical(as.double(scalar), c(2, 3))
    expect_identical(as.double(computed), c(2, 3))
    expect_identical(as.double(construct), c(1, 2))
    expect_true(holds)
})

test_that("scalar profile rejects changed standard compiled wrapper code", {
    skip_if_not_installed("callr")
    actual <- .dtatools_child_r("numeric-recompiled-wrapper", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        source <- dta_double(c(1, 2))
        invisible(source + 1)
        replacement <- compiler::cmpfun(base::withCallingHandlers,
                                        options = list(optimize = 0L))
        unlockBinding("withCallingHandlers", baseenv())
        assign("withCallingHandlers", replacement, baseenv())
        lockBinding("withCallingHandlers", baseenv())
        hits <- 0L
        trace("!=", tracer = function() hits <<- hits + 1L, where = baseenv(), print = FALSE)
        state <- get(".numeric_helper_state", asNamespace("dtatools"))
        saved <- state$dependencies
        state$dependencies <- NULL
        hits <- 0L
        expected_result <- source + 1
        expected <- hits
        state$dependencies <- saved
        hits <- 0L
        result <- source + 1
        observed <- hits
        untrace("!=", where = baseenv())
        list(calls = observed, expected = expected, result = as.double(result))
    }, args = list(.libPaths()), timeout = 20)
    expect_identical(actual$calls, actual$expected)
    expect_gt(actual$expected, 0L)
    expect_identical(actual$result, c(2, 3))
})

test_that("scalar recycling preserves functions reached by ordinary recompilation", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    vctrs_ns <- asNamespace("vctrs")
    original_recycle <- get("vec_recycle_common", vctrs_ns)
    original_external <- get(".External2", baseenv())
    saved <- .numeric_helper_state$dependencies
    replace <- function(name, value, where) {
        unlockBinding(name, where)
        assign(name, value, where)
        lockBinding(name, where)
    }
    on.exit({
        replace(".External2", original_external, baseenv())
        replace("vec_recycle_common", original_recycle, vctrs_ns)
        .numeric_helper_state$dependencies <- saved
    }, add = TRUE)
    replace("vec_recycle_common", compiler::cmpfun(original_recycle,
            options = list(optimize = 0L)), vctrs_ns)
    hits <- 0L
    replacement <- function(...) {
        hits <<- hits + 1L
        stop("replacement .External2 reached")
    }
    replace(".External2", replacement, baseenv())
    .numeric_helper_state$dependencies <- NULL
    hits <- 0L
    expected <- tryCatch(source + 1, error = conditionMessage)
    expected_hits <- hits
    .numeric_helper_state$dependencies <- saved
    hits <- 0L
    observed <- tryCatch(source + 1, error = conditionMessage)
    observed_hits <- hits
    replace(".External2", original_external, baseenv())
    replace("vec_recycle_common", original_recycle, vctrs_ns)
    expect_identical(observed, expected)
    expect_identical(observed_hits, expected_hits)
    expect_identical(expected, "replacement .External2 reached")
    expect_identical(expected_hits, 1L)
})

test_that("numeric admission adds no predicates to interpreted helpers", {
    source <- dta_double(c(1, 2))
    ns <- asNamespace("dtatools")
    helpers <- c(".dta_arith_base", ".dta_computed",
                 ".construct_dta_numeric", ".dta_storage_holds")
    saved <- mget(helpers, ns, inherits = FALSE)
    replace <- function(name, value) {
        unlockBinding(name, ns)
        assign(name, value, ns)
        lockBinding(name, ns)
    }
    old_jit <- compiler::enableJIT(0L)
    on.exit(compiler::enableJIT(old_jit), add = TRUE)
    on.exit(for (name in helpers) replace(name, saved[[name]]), add = TRUE)
    for (name in helpers) {
        value <- saved[[name]]
        body(value) <- body(value)
        replace(name, value)
    }
    observe <- function(target) {
        hits <- 0L
        trace(target, tracer = function() hits <<- hits + 1L,
              where = baseenv(), print = FALSE)
        on.exit(untrace(target, where = baseenv()), add = TRUE)
        hits <- 0L
        scalar <- source + 1
        scalar_hits <- hits
        hits <- 0L
        computed <- source + c(1, 1)
        computed_hits <- hits
        hits <- 0L
        construct <- dta_double(c(1, 2))
        construct_hits <- hits
        hits <- 0L
        holds <- get(".dta_storage_holds", ns)(c(1, 2), "double")
        holds_hits <- hits
        c(scalar_hits, computed_hits, construct_hits, holds_hits)
    }
    bytecode_enabled <- .dtatools_bytecode_execution_expected()
    expect_identical(observe("is.null"), if (bytecode_enabled)
        c(0L, 0L, 5L, 0L) else c(4L, 4L, 6L, 0L))
    expect_identical(observe("isTRUE"), c(0L, 0L, 0L, 0L))
    expect_identical(observe("identical"), if (bytecode_enabled)
        c(0L, 0L, 4L, 1L) else c(2L, 2L, 5L, 1L))
})


test_that("owned strict construction retains its reached isTRUE callback", {
    owned <- as.double(dta_double(c(1, 2)))
    invisible(dta_double(owned))
    hits <- 0L
    trace("isTRUE", tracer = function() hits <<- hits + 1L,
          where = baseenv(), print = FALSE)
    on.exit(untrace("isTRUE", where = baseenv()), add = TRUE)
    hits <- 0L
    owned_result <- dta_double(owned)
    owned_hits <- hits
    hits <- 0L
    plain_result <- dta_double(c(1, 2))
    plain_hits <- hits
    expect_identical(owned_hits, 1L)
    expect_identical(plain_hits, 0L)
    expect_identical(as.double(owned_result), c(1, 2))
    expect_identical(as.double(plain_result), c(1, 2))
})

test_that("numeric entry rejects synthetic callers without touching result slots", {
    invisible(dta_double(c(1, 2)) + 1)
    attempt <- function(slot, events) {
        values <- c(1, 2)
        minimum <- storage <- "double"
        temporal <- 0L
        status <- NULL
        if (slot == "value") native <- "existing"
        if (slot == "active") makeActiveBinding("native", function(...) {
            events$calls <- events$calls + 1L
            stop("native result setter invoked")
        }, environment())
        if (slot == "delayed") delayedAssign("native", {
            events$calls <- events$calls + 1L
            stop("native result promise forced")
        }, assign.env = environment())
        if (slot == "locked") lockEnvironment(environment())
        status <- .Call(C_dtatools_computed_numeric, NULL, NULL,
                        .computed_storage_getter, .computed_numeric_dependencies)
        list(status = status, frame = environment())
    }
    environment(attempt) <- asNamespace("dtatools")
    for (slot in c("absent", "value", "active", "delayed", "locked")) {
        events <- new.env(parent = emptyenv())
        events$calls <- 0L
        observed <- attempt(slot, events)
        expect_identical(observed$status, FALSE, info = slot)
        expect_identical(events$calls, 0L, info = slot)
        if (slot == "absent") {
            expect_false(exists("native", observed$frame, inherits = FALSE))
        } else if (slot == "value") {
            expect_identical(observed$frame$native, "existing")
        }
    }
})

test_that("native admissions add no callbacks to replaced .Call bindings", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-admission-call-callbacks", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        ns <- asNamespace("dtatools")
        invisible(compiler::enableJIT(0L))
        source <- dta_double(c(1, 2))
        plain <- c(1, 2)
        attrs <- attributes(source)
        operations <- list(
            scalar = function() source + 1,
            computed = function() source / 2,
            strict = function() dta_double(plain),
            holds = function() dtatools:::.dta_storage_holds(plain, "double"),
            metadata = function() dtatools:::.generate_attributes(attrs),
            grouped = function() gen(
                dibble(x = c(1, 2, 3, 4), g = c(1L, 1L, 2L, 2L)),
                y = x + 1, by = g
            )
        )
        for (operation in operations) invisible(operation())
        original <- .Primitive(".Call")
        introduced <- c(
            "C_dtatools_scalar_arithmetic", "C_dtatools_computed_numeric",
            "C_dtatools_construct_double", "C_dtatools_double_fits",
            "C_dtatools_canonical_attribute_plan",
            "C_dtatools_canonical_generate_attributes",
            "C_dtatools_combine_double_into_current", "C_dtatools_try_mask_bindings"
        )
        helpers <- c(".dta_arith_base", ".dta_computed", ".construct_dta_numeric",
                     ".dta_storage_holds", ".dta_attribute_plan", ".generate_attributes",
                     ".mutation_gather_values", ".new_dibble_expression_mask")
        records <- list()
        for (mode in c("installed", "decompiled")) {
            if (mode == "decompiled") for (name in helpers) {
                value <- get(name, ns)
                body(value) <- body(value)
                unlockBinding(name, ns)
                assign(name, value, ns)
                lockBinding(name, ns)
            }
            records[[mode]] <- lapply(operations, function(operation) {
                calls <- character()
                replacement <- function(...) {
                    target <- substitute(...())[[1L]]
                    if (is.symbol(target)) {
                        calls <<- c(calls, as.character(target))
                        if (as.character(target) %in% introduced)
                            stop("additional native admission .Call callback")
                    }
                    original(...)
                }
                unlockBinding(".Call", baseenv())
                assign(".Call", replacement, baseenv())
                lockBinding(".Call", baseenv())
                result <- tryCatch(operation(), error = identity)
                unlockBinding(".Call", baseenv())
                assign(".Call", original, baseenv())
                lockBinding(".Call", baseenv())
                list(calls = calls,
                     error = if (inherits(result, "error")) conditionMessage(result) else NULL,
                     value = if (inherits(result, "error")) NULL else
                         if (inherits(result, "dta_numeric")) as.double(result) else
                         if (inherits(result, "dibble")) as.double(result$y) else result)
            })
        }
        records
    }, args = list(.libPaths()))
    expected <- list(scalar = c(2, 3), computed = c(.5, 1), strict = c(1, 2),
                     holds = TRUE, metadata = attributes(dta_double(c(1, 2))),
                     grouped = c(2, 3, 4, 5))
    for (mode in names(observed)) for (name in names(expected)) {
        record <- observed[[mode]][[name]]
        expect_null(record$error, info = paste(mode, name))
        expect_identical(record$value, expected[[name]], info = paste(mode, name))
    }
})

test_that("numeric entry aliases leave synthetic production wrappers unadmitted", {
    invisible(dta_double(c(1, 2)) + 1)
    attempt <- function(route) {
        values <- doubles <- left <- c(1, 2)
        value_names <- NULL
        x <- dta_double(left)
        y <- right <- 1
        minimum <- storage <- "double"
        temporal <- 0L
        op <- "+"
        status <- switch(route,
            scalar = .native_admission_call(C_dtatools_scalar_arithmetic,
                NULL, NULL, NULL, .computed_storage_getter, .scalar_arith_dependencies),
            computed = .native_admission_call(C_dtatools_computed_numeric,
                NULL, NULL, .computed_storage_getter, .computed_numeric_dependencies),
            construct = .native_admission_call(C_dtatools_construct_double,
                NULL, NULL, .strict_double_dependencies),
            holds = .native_admission_call(C_dtatools_double_fits,
                NULL, NULL, .strict_double_dependencies)
        )
        list(status = status, frame = environment())
    }
    environment(attempt) <- asNamespace("dtatools")
    ns <- asNamespace("dtatools")
    expect_identical(get(".native_admission_call", ns), .Primitive(".Call"))
    expect_identical(get(".native_admission_if", ns), .Primitive("if"))
    expect_identical(get(".native_admission_return", ns), .Primitive("return"))
    for (route in c("scalar", "computed", "construct", "holds")) {
        record <- attempt(route)
        expect_identical(record$status, FALSE, info = route)
        expect_false(exists("native", record$frame, inherits = FALSE), info = route)
    }
})
