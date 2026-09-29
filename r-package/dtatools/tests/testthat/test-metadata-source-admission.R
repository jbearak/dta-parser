test_that("generated metadata keeps lazy source forcing after subset callbacks", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("metadata-source-forcing", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        data <- dibble(x = c(1, 2))
        ns <- asNamespace("dtatools")
        compiler::enableJIT(0)
        helper <- get(".generate_attributes", ns)
        body(helper) <- body(helper)
        unlockBinding(".generate_attributes", ns)
        assign(".generate_attributes", helper, ns)
        lockBinding(".generate_attributes", ns)
        original <- .Primitive("[")
        replacement <- function(x, ...) {
            frame <- parent.frame()
            if (identical(substitute(x), quote(source)) &&
                exists("source", frame, inherits = FALSE) &&
                identical(sys.call(-1L), quote(.generate_attributes(source)))) {
                assign("source", list(late = TRUE), parent.frame(2L))
                stop(if (identical(x, list(late = TRUE))) "late source" else "early source")
            }
            original(x, ...)
        }
        unlockBinding("[", baseenv())
        assign("[", replacement, baseenv())
        lockBinding("[", baseenv())
        result <- tryCatch(gen(data, y = x + 1), error = conditionMessage)
        unlockBinding("[", baseenv())
        assign("[", original, baseenv())
        lockBinding("[", baseenv())
        list(result = result, source = as.double(data$x), names = names(data))
    }, args = list(.libPaths()), timeout = 20)
    expect_identical(observed$result, "late source")
    expect_identical(observed$source, c(1, 2))
    expect_identical(observed$names, "x")
})

test_that("attribute planning keeps active source reads after original callbacks", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("metadata-active-source", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        data <- dibble(x = c(1, 2))
        ns <- asNamespace("dtatools")
        helper <- get(".dta_attribute_plan", ns)
        body(helper) <- body(helper)
        unlockBinding(".dta_attribute_plan", ns)
        assign(".dta_attribute_plan", helper, ns)
        lockBinding(".dta_attribute_plan", ns)
        old_attributes <- base::attributes
        old_setdiff <- base::setdiff
        events <- character()
        replacement_attributes <- function(obj) {
            frame <- parent.frame()
            value <- old_attributes(obj)
            if (identical(sys.call(-1L)[[1L]], quote(.dta_attribute_plan))) {
                assign("metadata_active_source", TRUE, frame)
                makeActiveBinding("source", local({
                    held <- value
                    function(x) {
                        if (missing(x)) {
                            events <<- c(events, "source")
                            held
                        } else held <<- x
                    }
                }), frame)
            }
            value
        }
        replacement_setdiff <- function(x, y) {
            if (exists("metadata_active_source", parent.frame(), inherits = FALSE)) {
                events <<- c(events, "setdiff")
            }
            old_setdiff(x, y)
        }
        unlockBinding("attributes", baseenv())
        assign("attributes", replacement_attributes, baseenv())
        lockBinding("attributes", baseenv())
        unlockBinding("setdiff", baseenv())
        assign("setdiff", replacement_setdiff, baseenv())
        lockBinding("setdiff", baseenv())
        result <- tryCatch(gen(data, y = x + 1), error = identity)
        unlockBinding("attributes", baseenv())
        assign("attributes", old_attributes, baseenv())
        lockBinding("attributes", baseenv())
        unlockBinding("setdiff", baseenv())
        assign("setdiff", old_setdiff, baseenv())
        lockBinding("setdiff", baseenv())
        list(events = events,
             error = if (inherits(result, "error")) conditionMessage(result) else NULL,
             values = if (inherits(result, "error")) NULL else as.double(result$y),
             source = as.double(data$x))
    }, args = list(.libPaths()), timeout = 20)
    expect_identical(observed$events, c("setdiff", "source", "source", "source"))
    expect_null(observed$error)
    expect_identical(observed$values, c(2, 3))
    expect_identical(observed$source, c(1, 2))
})

test_that("metadata class callbacks retain the original unknown attribute local", {
    data <- dibble(x = c(1, 2))
    invisible(gen(data, z = x + 1))
    ns <- asNamespace("dtatools")
    original <- get(".dta_classes_from", ns)
    seen <- list()
    replacement <- function(prototype, storage) {
        frame <- parent.frame()
        if (exists("desired", frame, inherits = FALSE) &&
            exists("source", frame, inherits = FALSE)) {
            if (!exists("unknown", frame, inherits = FALSE)) stop("missing unknown local")
            seen[[length(seen) + 1L]] <<- get("unknown", frame, inherits = FALSE)
        }
        original(prototype, storage)
    }
    unlockBinding(".dta_classes_from", ns)
    assign(".dta_classes_from", replacement, ns)
    lockBinding(".dta_classes_from", ns)
    withr::defer({
        unlockBinding(".dta_classes_from", ns)
        assign(".dta_classes_from", original, ns)
        lockBinding(".dta_classes_from", ns)
    })
    result <- tryCatch(gen(data, y = x + 1), error = identity)
    expect_identical(if (inherits(result, "error")) conditionMessage(result) else NULL, NULL)
    expect_identical(seen, list(character()))
    expect_identical(if (inherits(result, "error")) NULL else as.double(result$y), c(2, 3))
    expect_identical(as.double(data$x), c(1, 2))
})

test_that("ordinary metadata filtering preserves values and diagnostic caller bindings", {
    source <- attributes(dta_double(c(1, 2)))
    invisible(.generate_attributes(source))
    invisible(.dta_attribute_plan(dta_double(c(1, 2)), "double", temporal = FALSE))
    generation <- function(source) {
        .native_admission_call(C_dtatools_canonical_generate_attributes,
                               NULL, NULL, .metadata_state)
    }
    environment(generation) <- asNamespace("dtatools")
    # Ordinary filtering creates a distinct list with equal metadata.
    actual <- .generate_attributes(source)
    expect_false(rlang::is_reference(actual, source))
    expect_identical(actual, source)
    prototype <- dta_double(c(1, 2))
    invisible(.dta_attribute_plan(prototype, "double", temporal = FALSE))
    invisible(.Call(C_dtatools_attribute_plan_stats, TRUE))
    plan <- .dta_attribute_plan(prototype, "double", temporal = FALSE)
    expect_identical(.Call(C_dtatools_attribute_plan_stats, FALSE), 0)
    expect_identical(plan, source)
    # A synthetic wrapper cannot stand in for the actual executing helper.
    expect_false(generation(source))
    attempt <- function(source, slot, events) {
        status <- NULL
        if (slot == "value") unknown <- "existing"
        if (slot == "active") makeActiveBinding("unknown", function(...) {
            events$calls <- events$calls + 1L
            stop("unexpected metadata local access")
        }, environment())
        if (slot == "delayed") delayedAssign("unknown", {
            events$calls <- events$calls + 1L
            stop("unexpected metadata local forcing")
        }, assign.env = environment())
        if (slot == "locked") lockEnvironment(environment())
        status <- .native_admission_call(C_dtatools_canonical_attribute_plan,
                                          NULL, .metadata_state)
        list(status = status, frame = environment())
    }
    environment(attempt) <- asNamespace("dtatools")
    for (slot in c("absent", "value", "active", "delayed", "locked")) {
        events <- new.env(parent = emptyenv())
        events$calls <- 0L
        observed <- attempt(source, slot, events)
        expect_false(observed$status, info = slot)
        expect_identical(events$calls, 0L, info = slot)
        if (slot == "absent") {
            expect_false(exists("unknown", observed$frame, inherits = FALSE))
        } else if (slot == "value") {
            expect_identical(observed$frame$unknown, "existing")
        }
    }
})

test_that("self untracing attribute plans retain executable callbacks and generation errors", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("attribute-plan-self-untrace", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        ns <- asNamespace("dtatools")
        data <- dibble(x = dta_double(c(1, 2)))
        warm <- copy_data(data)
        invisible(gen(warm, y = x + 1))
        original_plan <- get(".dta_attribute_plan", ns)
        original_length <- get("length", baseenv())
        before <- attributes(data$x)
        callbacks <- list()
        trace(".dta_attribute_plan", tracer = quote(
            untrace(".dta_attribute_plan", where = asNamespace("dtatools"))
        ), where = ns, print = FALSE)
        trace("length", tracer = function() {
            if (any(vapply(sys.calls(), identical, logical(1), quote(length(unknown))))) {
                callbacks[[length(callbacks) + 1L]] <<- quote(length(unknown))
                stop("attribute plan length callback", call. = FALSE)
            }
        }, where = baseenv(), print = FALSE)
        outcome <- tryCatch({
            gen(data, y = x + 1)
            list(error = NULL, call = NULL)
        }, error = function(error) {
            list(error = conditionMessage(error), call = conditionCall(error))
        })
        untrace("length", where = baseenv())
        list(outcome = outcome, callbacks = callbacks,
             names = names(data), values = as.double(data$x),
             attributes = attributes(data$x), before = before,
             restored = identical(get(".dta_attribute_plan", ns), original_plan) &&
                        identical(get("length", baseenv()), original_length))
    }, args = list(.libPaths()), timeout = 30)
    expect_identical(observed$outcome,
                     list(error = "attribute plan length callback", call = NULL))
    expect_identical(observed$callbacks, list(quote(length(unknown))))
    expect_identical(observed$names, "x")
    expect_identical(observed$values, c(1, 2))
    expect_identical(observed$attributes, observed$before)
    expect_true(observed$restored)
})

test_that("prototype forcing retains active unknown assignments and completed plan locals", {
    ns <- asNamespace("dtatools")
    plan <- get(".dta_attribute_plan", ns)
    prototype <- dta_double(c(1, 2))
    invisible(plan(prototype, "double", temporal = FALSE))
    retained <- NULL
    callbacks <- 0L
    supply <- function(active) {
        calls <- sys.calls()
        index <- which(vapply(calls, function(call) identical(call[[1L]], quote(plan)),
                              logical(1)))
        stopifnot(length(index) == 1L)
        retained <<- sys.frame(index)
        if (active) makeActiveBinding("unknown", function(value) {
            callbacks <<- callbacks + 1L
            stop("prototype unknown assignment", call. = FALSE)
        }, retained)
        prototype
    }
    outcome <- tryCatch(plan(supply(TRUE), "double", temporal = FALSE),
                        error = conditionMessage)
    expect_identical(outcome, "prototype unknown assignment")
    expect_identical(callbacks, 1L)
    result <- plan(supply(FALSE), "double", temporal = FALSE)
    expect_identical(result, attributes(prototype))
    expect_identical(retained$source, attributes(prototype))
    expect_identical(retained$unknown, character())
    expect_identical(retained$desired, attributes(prototype))
    expect_identical(retained$classes, class(prototype))
    expect_identical(as.double(prototype), c(1, 2))
})
