test_that("native entry conditions do not add executable if callbacks", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-entry-if-callbacks", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        ns <- asNamespace("dtatools")
        prototype <- dta_double(c(1, 2))
        pieces <- list(prototype, dta_double(c(3, 4)))
        data <- dibble(x = dta_double(c(1, 2, 3, 4)), g = c(1, 1, 2, 2))
        plan <- get(".dta_attribute_plan", ns)
        gather <- get(".mutation_gather_values", ns)
        # This is the real expression evaluator behind mutate.dibble(). Its
        # built-in adapter also runs when the optional dplyr namespace is absent.
        mutate <- get(".dibble_mutate", ns)
        dots <- rlang::quos(y = x + 1)
        by <- rlang::quo(g)
        original_if <- .Primitive("if")
        inspect <- function(case) {
            calls <- list()
            expected_entry <- switch(case,
                attribute = quote(C_dtatools_canonical_attribute_plan),
                gather = quote(C_dtatools_combine_double_into_current),
                mask = quote(C_dtatools_try_mask_bindings), indexed = NULL)
            replacement <- function(condition, yes, no) {
                expression <- substitute(condition)
                original_if(is.call(expression), {
                    head <- expression[[1L]]
                    original_if((identical(head, quote(.native_admission_call)) &&
                                 identical(expression[[2L]], expected_entry)) ||
                                (identical(case, "indexed") &&
                                 identical(head, quote(.try_combine_dta_double_indexed))), {
                        calls[[length(calls) + 1L]] <<- expression
                    })
                })
                original_if(missing(no), original_if(condition, yes),
                            original_if(condition, yes, no))
            }
            run <- function() {
                unlockBinding("if", baseenv())
                assign("if", replacement, baseenv())
                lockBinding("if", baseenv())
                on.exit({
                    unlockBinding("if", baseenv())
                    assign("if", original_if, baseenv())
                    lockBinding("if", baseenv())
                }, add = TRUE)
                switch(case,
                    attribute = plan(prototype, "double", temporal = FALSE),
                    gather = gather(pieces),
                    mask = mutate(data, dots),
                    indexed = mutate(data, dots, by = by))
            }
            value <- run()
            list(calls = calls, value = switch(case,
                attribute = value, gather = as.double(value),
                mask = as.double(value$y), indexed = as.double(value$y)),
                restored = identical(get("if", baseenv()), original_if))
        }
        cases <- lapply(c("attribute", "gather", "mask", "indexed"), inspect)
        names(cases) <- c("attribute", "gather", "mask", "indexed")
        list(cases = cases, classes = class(prototype),
             source = as.double(data$x), source_names = names(data),
             dplyr_loaded = "dplyr" %in% loadedNamespaces())
    }, args = list(.libPaths()), timeout = 30)
    for (name in names(observed$cases)) {
        case <- observed$cases[[name]]
        expect_identical(case$calls, list(), info = name)
        expect_true(case$restored, info = name)
    }
    expect_identical(observed$cases$attribute$value,
                     list(stata.storage = "double", class = observed$classes))
    expect_identical(observed$cases$gather$value, c(1, 2, 3, 4))
    expect_identical(observed$cases$mask$value, c(2, 3, 4, 5))
    expect_identical(observed$cases$indexed$value, c(2, 3, 4, 5))
    expect_identical(observed$source, c(1, 2, 3, 4))
    expect_identical(observed$source_names, c("x", "g"))
    expect_false(observed$dplyr_loaded)
})

test_that("original helper if callbacks still retain their errors", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-original-if-errors", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        ns <- asNamespace("dtatools")
        prototype <- dta_double(c(1, 2))
        pieces <- list(prototype, dta_double(c(3, 4)))
        original_if <- .Primitive("if")
        inspect <- function(name, target) {
            original_helper <- get(name, ns)
            helper <- original_helper
            # Ordinary body replacement keeps original conditions interpreted
            # in both child modes and must preserve their executable callbacks.
            body(helper) <- body(helper)
            calls <- list()
            replacement <- function(condition, yes, no) {
                expression <- substitute(condition)
                original_if(identical(expression, target), {
                    calls[[length(calls) + 1L]] <<- expression
                    stop("original if callback", call. = FALSE)
                })
                original_if(missing(no), original_if(condition, yes),
                            original_if(condition, yes, no))
            }
            run <- function() {
                unlockBinding(name, ns)
                assign(name, helper, ns)
                lockBinding(name, ns)
                unlockBinding("if", baseenv())
                assign("if", replacement, baseenv())
                lockBinding("if", baseenv())
                on.exit({
                    unlockBinding("if", baseenv())
                    assign("if", original_if, baseenv())
                    lockBinding("if", baseenv())
                    unlockBinding(name, ns)
                    assign(name, original_helper, ns)
                    lockBinding(name, ns)
                }, add = TRUE)
                tryCatch(switch(name,
                    .dta_attribute_plan = helper(prototype, "double", temporal = FALSE),
                    .mutation_gather_values = helper(pieces)), error = conditionMessage)
            }
            value <- run()
            list(value = value, calls = calls,
                 restored = identical(get("if", baseenv()), original_if) &&
                            identical(get(name, ns), original_helper))
        }
        list(attribute = inspect(".dta_attribute_plan", quote(length(unknown))),
             gather = inspect(".mutation_gather_values", quote(length(first) == 0L)))
    }, args = list(.libPaths()), timeout = 30)
    expect_identical(observed$attribute$value, "original if callback")
    expect_identical(observed$attribute$calls, list(quote(length(unknown))))
    expect_true(observed$attribute$restored)
    expect_identical(observed$gather$value, "original if callback")
    expect_identical(observed$gather$calls, list(quote(length(first) == 0L)))
    expect_true(observed$gather$restored)
})

test_that("labelled generation keeps the original fallback evaluator callbacks", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-labelled-fallback-evaluation", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        ns <- asNamespace("dtatools")
        original <- get(".dta_attribute_plan", ns)
        original_length <- get("length", baseenv())
        inspect <- function(mode) {
            column <- dta_double(c(1, 2, 3, 4))
            attr(column, "label") <- "score"
            data <- dibble(g = c(2, 1, 2, 1), x = column)
            helper <- original
            if (mode != "canonical") body(helper) <- body(helper)
            if (mode == "optimize0") {
                helper <- compiler::cmpfun(helper, options = list(optimize = 0L))
            }
            if (mode == "optimize2") {
                helper <- compiler::cmpfun(helper, options = list(optimize = 2L))
            }
            unlockBinding(".dta_attribute_plan", ns)
            assign(".dta_attribute_plan", helper, ns)
            lockBinding(".dta_attribute_plan", ns)
            on.exit({
                unlockBinding(".dta_attribute_plan", ns)
                assign(".dta_attribute_plan", original, ns)
                lockBinding(".dta_attribute_plan", ns)
            }, add = TRUE)
            callbacks <- list()
            trace("length", tracer = function() {
                if (any(vapply(sys.calls(), identical, logical(1),
                               quote(length(unknown))))) {
                    callbacks[[length(callbacks) + 1L]] <<- quote(length(unknown))
                    stop("metadata fallback length callback", call. = FALSE)
                }
            }, where = baseenv(), print = FALSE)
            on.exit(untrace("length", where = baseenv()), add = TRUE)
            outcome <- tryCatch({
                gen(data, y = x + 1.0, by = g)
                list(error = NULL, values = as.double(data$y),
                     attributes = attributes(data$y))
            }, error = function(error) {
                list(error = conditionMessage(error), call = conditionCall(error))
            })
            list(outcome = outcome, callbacks = callbacks, names = names(data),
                 source_values = as.double(data$x), source_attributes = attributes(data$x))
        }
        modes <- c("canonical", "interpreted", "optimize0", "optimize2")
        records <- lapply(modes, function(mode) {
            record <- inspect(mode)
            record$restored <- identical(get(".dta_attribute_plan", ns), original) &&
                               identical(get("length", baseenv()), original_length)
            record
        })
        names(records) <- modes
        records
    }, args = list(.libPaths()), timeout = 30)
    classes <- c("dta_numeric", "dta_double", "vctrs_vctr", "double")
    for (mode in names(observed)) {
        record <- observed[[mode]]
        # Main's compiled length opcode bypasses this executable tracer only
        # for canonical/optimize-2 helpers while bytecode is enabled.
        succeeds <- .dtatools_bytecode_execution_expected() &&
                    mode %in% c("canonical", "optimize2")
        expected <- if (succeeds) {
            list(error = NULL, values = c(2, 3, 4, 5),
                 attributes = list(stata.storage = "double", class = classes))
        } else list(error = "metadata fallback length callback", call = NULL)
        expect_identical(record$outcome, expected, info = mode)
        expect_identical(record$callbacks,
                         if (succeeds) list() else list(quote(length(unknown))), info = mode)
        expect_identical(record$names, if (succeeds) c("g", "x", "y") else c("g", "x"),
                         info = mode)
        expect_identical(record$source_values, c(1, 2, 3, 4), info = mode)
        expect_identical(record$source_attributes,
                         list(stata.storage = "double", class = classes, label = "score"),
                         info = mode)
        expect_true(record$restored, info = mode)
    }
})
