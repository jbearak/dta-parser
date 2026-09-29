test_that("metadata and combination settle every reached delayed primitive binding", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("metadata-primitive-dependency-settlement", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        values <- c(1, 2)
        source <- dta_double(values)
        metadata <- attributes(source)
        pieces <- list(source, source)
        operations <- list(
            attribute = function() dtatools:::.dta_attribute_plan(source, "double", temporal = FALSE),
            generate = function() dtatools:::.generate_attributes(metadata),
            combine = function() dtatools:::.mutation_gather_values(pieces)
        )
        for (operation in operations) for (i in 1:3) invisible(operation())
        targets <- list(
            attribute = c("==", "all", "c", "dim", "isS4", "length", "missing", "names", "UseMethod"),
            generate = c("!", "==", ">", "all", "any", "c", "class", "dim", "isS4", "length", "missing", "names", "UseMethod"),
            combine = c(".subset", "all", "attr", "isS4", "missing")
        )
        get_original <- base::get
        identical_original <- base::identical
        inspect <- function(operation, target) {
            original <- get_original(target, baseenv(), inherits = FALSE)
            holder <- new.env(parent = baseenv())
            holder$fn <- original
            restore <- function() {
                unlockBinding(target, baseenv())
                assign(target, original, baseenv())
                lockBinding(target, baseenv())
            }
            on.exit(restore(), add = TRUE)
            unlockBinding(target, baseenv())
            delayedAssign(target, fn, eval.env = holder, assign.env = baseenv())
            lockBinding(target, baseenv())
            value <- operation()
            holder$fn <- function(...) stop("delayed metadata dependency changed", call. = FALSE)
            settled <- identical_original(get_original(target, baseenv(), inherits = FALSE), original)
            restore()
            list(settled = settled,
                 value = if (inherits(value, "dta_numeric")) as.double(value) else value,
                 restored = identical_original(get_original(target, baseenv(), inherits = FALSE), original))
        }
        records <- list()
        for (route in names(targets)) for (target in targets[[route]]) {
            records[[paste(route, target)]] <- inspect(operations[[route]], target)
        }
        list(records = records, metadata = metadata)
    }, args = list(.libPaths()), timeout = 30)
    expect_length(observed$records, 27L)
    for (name in names(observed$records)) {
        record <- observed$records[[name]]
        expect_true(record$settled, info = name)
        expect_true(record$restored, info = name)
        expect_identical(record$value, if (startsWith(name, "combine "))
            c(1, 2, 1, 2) else observed$metadata, info = name)
    }
})

test_that("settled metadata dependencies retain later public function results", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("metadata-primitive-dependency-followup", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        source <- dta_double(c(1, 2))
        metadata <- attributes(source)
        pieces <- list(source, source)
        operations <- list(
            attribute = function() dtatools:::.dta_attribute_plan(source, "double", temporal = FALSE),
            generate = function() dtatools:::.generate_attributes(metadata),
            combine = function() dtatools:::.mutation_gather_values(pieces)
        )
        for (operation in operations) for (i in 1:3) invisible(operation())
        inspect <- function(route) {
            target <- if (route == "combine") ".subset" else "all"
            original <- get(target, baseenv(), inherits = FALSE)
            holder <- new.env(parent = baseenv())
            holder$fn <- original
            restore <- function() {
                unlockBinding(target, baseenv())
                assign(target, original, baseenv())
                lockBinding(target, baseenv())
            }
            on.exit(restore(), add = TRUE)
            unlockBinding(target, baseenv())
            delayedAssign(target, fn, eval.env = holder, assign.env = baseenv())
            lockBinding(target, baseenv())
            first <- operations[[route]]()
            holder$fn <- function(...) stop("delayed metadata dependency changed", call. = FALSE)
            expression <- if (route == "combine") quote(.subset(c(1, 2), 1L)) else quote(all(TRUE))
            # Evaluate the public call as source so compiler builtin instructions
            # cannot hide the changed function value after the missed force.
            later <- tryCatch(eval(expression), error = conditionMessage)
            restore()
            list(later = later, restored = identical(get(target, baseenv()), original))
        }
        lapply(names(operations), inspect)
    }, args = list(.libPaths()), timeout = 30)
    expected <- list(TRUE, TRUE, 1)
    for (i in seq_along(observed)) {
        expect_identical(observed[[i]]$later, expected[[i]])
        expect_true(observed[[i]]$restored)
    }
})

test_that("public generation retains delayed metadata errors before publication", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("metadata-primitive-dependency-gen-errors", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0)
        ns <- asNamespace("dtatools")
        replace_binding <- function(name, value, where) {
            unlockBinding(name, where)
            assign(name, value, where)
            lockBinding(name, where)
        }
        fixture <- function() dibble(x = dta_double(c(1, 2, 3, 4)), g = c(1, 1, 2, 2))
        for (i in 1:3) gen(fixture(), y = x + 1, by = g)
        inspect <- function(route) {
            data <- fixture()
            alias <- data
            helper <- switch(route, generate = ".generate_attributes",
                             attribute = ".dta_attribute_plan", combine = ".mutation_gather_values")
            target <- if (route == "combine") ".subset" else "all"
            original <- get(helper, ns)
            original_target <- get(target, baseenv())
            callbacks <- 0L
            enter <- function() {
                replace_binding(helper, original, ns)
                unlockBinding(target, baseenv())
                delayedAssign(target, {
                    callbacks <<- callbacks + 1L
                    stop("metadata dependency callback", call. = FALSE)
                }, eval.env = environment(), assign.env = baseenv())
                lockBinding(target, baseenv())
            }
            leave <- function() replace_binding(target, original_target, baseenv())
            replacement <- switch(route,
                generate = function(source) {
                    enter(); on.exit(leave()); original(source)
                },
                attribute = function(prototype, storage, result_names = NULL,
                                     temporal = inherits(prototype, "dta_temporal"), labelled = FALSE) {
                    enter(); on.exit(leave()); original(prototype, storage, result_names, temporal, labelled)
                },
                combine = function(pieces) {
                    enter(); on.exit(leave()); original(pieces)
                }
            )
            replace_binding(helper, replacement, ns)
            on.exit({ replace_binding(helper, original, ns); leave() }, add = TRUE)
            outcome <- tryCatch({ gen(data, y = x + 1, by = g); "success" }, error = conditionMessage)
            list(outcome = outcome, callbacks = callbacks, names = names(data),
                 alias_names = names(alias), values = as.double(data$x), groups = as.double(data$g),
                 restored = identical(get(helper, ns), original) &&
                     identical(get(target, baseenv()), original_target))
        }
        lapply(c("generate", "attribute", "combine"), inspect)
    }, args = list(.libPaths()), timeout = 30)
    for (record in observed) {
        expect_identical(record$outcome, "metadata dependency callback")
        expect_identical(record$callbacks, 1L)
        expect_identical(record$names, c("x", "g"))
        expect_identical(record$alias_names, c("x", "g"))
        expect_identical(record$values, c(1, 2, 3, 4))
        expect_identical(record$groups, c(1, 1, 2, 2))
        expect_true(record$restored)
    }
})
