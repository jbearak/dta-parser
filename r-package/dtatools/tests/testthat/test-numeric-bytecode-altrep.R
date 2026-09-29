test_that("compiled helper identity does not execute ALTREP bytecode constants", {
    skip_if_not_installed("callr")
    skip_if_not(.dtatools_numeric_entry_expected("scalar"))

    fixture <- normalizePath(test_path("fixtures", "numeric-bytecode-probe.c"))
    observed <- .dtatools_child_r("numeric-bytecode-altrep", function(libraries, fixture) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        scratch <- tempfile("numeric-bytecode-altrep-")
        dir.create(scratch)
        on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
        prior <- setwd(scratch)
        on.exit(setwd(prior), add = TRUE)
        stopifnot(file.copy(fixture, "numeric_bytecode_probe.c"))
        output <- system2(file.path(R.home("bin"), "R"),
                          c("CMD", "SHLIB", "numeric_bytecode_probe.c"),
                          stdout = TRUE, stderr = TRUE)
        if (!is.null(attr(output, "status"))) stop(paste(output, collapse = "\n"))
        dyn.load(file.path(scratch, paste0("numeric_bytecode_probe", .Platform$dynlib.ext)))

        ns <- asNamespace("dtatools")
        state <- get(".numeric_helper_state", ns)
        helper <- get(".dta_storage_candidates", ns)
        source <- dta_long(rep(c(1, 2), length.out = 2048L))
        seed <- dta_double(rep(c(1, 2), length.out = 2048L))
        operation <- function() source + 1
        for (i in seq_len(5L)) invisible(seed + 1)
        for (i in seq_len(5L)) invisible(operation())
        observe <- function(fallback = FALSE) {
            saved <- state$dependencies
            if (fallback) state$dependencies <- NULL
            on.exit(state$dependencies <- saved)
            invisible(.Call(dtatools:::C_dtatools_numeric_entry_stats, TRUE))
            result <- operation()
            list(storage = dta_storage_type(result), values = as.double(result),
                 attributes = attributes(result),
                 scalar = unname(.Call(dtatools:::C_dtatools_numeric_entry_stats,
                                       FALSE)[["scalar"]]))
        }
        baseline <- observe()

        invisible(capture.output(constants <- compiler::disassemble(helper)[[3L]]))
        indices <- which(vapply(constants, function(value)
            is.integer(value) && identical(class(value), "expressionsIndex"), logical(1)))
        stopifnot(length(indices) == 1L)
        index <- as.integer(indices[[1L]] - 1L)
        original <- constants[[indices[[1L]]]]

        wrapped <- .Call("C_probe_altrep_integer", original)
        old <- .Call("C_probe_replace_constant", helper, index, wrapped)
        stopifnot(identical(old, original))
        invisible(.Call("C_probe_altrep_hits", TRUE))
        direct <- observe()
        direct_hits <- .Call("C_probe_altrep_hits", FALSE)
        invisible(.Call("C_probe_altrep_hits", TRUE))
        direct_fallback <- observe(TRUE)
        direct_fallback_hits <- .Call("C_probe_altrep_hits", FALSE)
        invisible(.Call("C_probe_replace_constant", helper, index, old))
        direct_restored <- observe()

        old_class <- attr(original, "class", exact = TRUE)
        hits <- 0L
        callback <- function() hits <<- hits + 1L
        class_altrep <- .Call(dtatools:::C_dtatools_callback_length,
                              old_class, callback)
        previous_class <- .Call("C_probe_set_constant_attribute", helper,
                                index, "class", class_altrep)
        stopifnot(identical(previous_class, old_class))
        .Call(dtatools:::C_dtatools_arm_callback_character, class_altrep, callback)
        hits <- 0L
        nested <- observe()
        nested_hits <- hits
        hits <- 0L
        nested_fallback <- observe(TRUE)
        nested_fallback_hits <- hits
        invisible(.Call("C_probe_set_constant_attribute", helper, index,
                        "class", previous_class))
        nested_restored <- observe()

        list(baseline = baseline, direct = direct, direct_hits = direct_hits,
             direct_fallback = direct_fallback,
             direct_fallback_hits = direct_fallback_hits,
             direct_restored = direct_restored,
             nested = nested, nested_hits = nested_hits,
             nested_fallback = nested_fallback,
             nested_fallback_hits = nested_fallback_hits,
             nested_restored = nested_restored)
    }, args = list(libraries = .libPaths(), fixture = fixture))

    expect_identical(observed$baseline$scalar, 1)
    for (case in c("direct", "nested")) {
        actual <- observed[[case]]
        fallback <- observed[[paste0(case, "_fallback")]]
        expect_identical(actual$scalar, 0, info = case)
        expect_identical(fallback$scalar, 0, info = case)
        expect_identical(observed[[paste0(case, "_hits")]], 0L, info = case)
        expect_identical(observed[[paste0(case, "_fallback_hits")]], 0L, info = case)
        expect_identical(actual$storage, fallback$storage, info = case)
        expect_identical(actual$values, fallback$values, info = case)
        expect_identical(actual$attributes, fallback$attributes, info = case)
        expect_identical(observed[[paste0(case, "_restored")]]$scalar, 1, info = case)
    }
})
