test_that("returned folded constants retain fresh numeric execution comparison", {
    skip_if_not_installed("data.table")
    namespace <- asNamespace("dtatools")
    helper <- get(".dta_storage_candidates", namespace)
    computed <- get(".dta_computed", namespace)
    values <- rep(c(1, 2, 3, 4), length.out = 4096L)
    operation <- function() dtatools:::.dta_computed(values, "long")
    native_expected <- as.double(.dtatools_numeric_entry_expected("computed"))
    bytecode_expected <- .dtatools_bytecode_execution_expected()

    # Independent ordinary R oracle: copy only the public source, then remove
    # the admission expression. Do not alter or recompile either live helper.
    source <- utils::removeSource(computed)
    syntax <- unserialize(serialize(list(formals(source), body(source)), NULL))
    expressions <- as.list(syntax[[2L]])
    stopifnot(identical(expressions[[1L]], as.name("{")),
        identical(expressions[[2L]][[1L]], as.name(".native_admission_if")))
    expressions[[2L]] <- NULL
    oracle <- function() NULL
    formals(oracle) <- syntax[[1L]]
    body(oracle) <- as.call(expressions)
    environment(oracle) <- environment(computed)

    observe <- function() {
        old_jit <- compiler::enableJIT(0L)
        on.exit(compiler::enableJIT(old_jit), add = TRUE)
        source_before <- serialize(body(helper), NULL)
        returned <- helper("long")
        old_first <- paste0(returned[[1L]])
        holder <- structure(list(value = returned), class = "data.frame",
                            row.names = .set_row_names(length(returned)))
        on.exit(data.table::set(holder, i = 1L, j = "value", value = old_first), add = TRUE)
        capture <- function(operation) {
            error <- NULL
            invisible(.dtatools_numeric_entry_counts(TRUE))
            result <- tryCatch(operation(), error = function(condition) {
                error <<- conditionMessage(condition)
                NULL
            })
            counts <- .dtatools_numeric_entry_counts(FALSE)
            list(error = error, counts = counts,
                 values = if (is.null(error)) as.double(result) else NULL,
                 storage = if (is.null(error)) dta_storage_type(result) else NULL)
        }
        # Settle the same dependencies as ordinary numeric entry tests.
        source_value <- dta_double(values)
        for (i in 1:5) {
            invisible(operation())
            invisible(source_value + 1)
            invisible(dtatools:::.dta_storage_holds(values, "double"))
        }
        positive <- capture(operation)
        mutated <- tryCatch({
            data.table::set(holder, i = 1L, j = "value", value = "double")
            # Observe the live helper before any computed operation runs.
            before_operation <- unserialize(serialize(helper("long"), NULL))
            holder_value <- unserialize(serialize(holder$value, NULL))
            source_unchanged <- identical(source_before, serialize(body(helper), NULL))
            actual <- capture(operation)
            expected <- capture(function() oracle(values, "long"))
            list(before_operation = before_operation, holder = holder_value,
                 source_unchanged = source_unchanged,
                 actual = actual, expected = expected)
        }, finally = data.table::set(holder, i = 1L, j = "value", value = old_first))
        list(positive = positive, mutated = mutated,
             restored_return = helper("long"),
             restored_source = identical(source_before, serialize(body(helper), NULL)),
             helper_unchanged = identical(helper, get(".dta_storage_candidates", namespace)),
             restored = capture(operation))
    }
    observed <- observe()
    expected_storage <- if (bytecode_expected) "double" else "long"
    expected_return <- if (bytecode_expected) c("double", "double") else c("long", "double")
    expect_identical(observed$positive$counts[["computed"]], native_expected)
    expect_identical(observed$positive$values, values)
    expect_identical(observed$positive$storage, "long")
    expect_identical(observed$mutated$holder, c("double", "double"))
    expect_identical(observed$mutated$before_operation, expected_return)
    expect_true(observed$mutated$source_unchanged)
    expect_null(observed$mutated$actual$error)
    expect_null(observed$mutated$expected$error)
    expect_identical(observed$mutated$actual$counts[["computed"]], 0)
    expect_identical(observed$mutated$expected$counts[["computed"]], 0)
    expect_identical(observed$mutated$actual$values, observed$mutated$expected$values)
    expect_identical(observed$mutated$actual$storage, observed$mutated$expected$storage)
    expect_identical(observed$mutated$expected$values, values)
    expect_identical(observed$mutated$expected$storage, expected_storage)
    expect_identical(observed$restored_return, c("long", "double"))
    expect_true(observed$restored_source)
    expect_true(observed$helper_unchanged)
    expect_identical(observed$restored$counts[["computed"]], native_expected)
    expect_identical(observed$restored$values, values)
    expect_identical(observed$restored$storage, "long")
})
