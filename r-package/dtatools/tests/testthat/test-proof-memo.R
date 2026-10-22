.proof_memo_call <- function(name, ...) {
    .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
}

test_that("a kept proof never covers a closure that R code has changed", {
    template <- eval(quote(function(x, y = 2) x + y * 3), baseenv())
    template <- compiler::cmpfun(utils::removeSource(template))
    expected <- unserialize(serialize(template, NULL))
    same <- function(actual) {
        .proof_memo_call("C_dtatools_test_numeric_old_proof", actual, expected)
    }
    # The kept proof is the only other reference to `proven`, so the
    # replacement functions below must copy it rather than edit it in place.
    proven <- unserialize(serialize(template, NULL))
    expect_true(same(proven))
    expect_true(same(proven))
    original <- proven
    environment(proven) <- new.env(parent = baseenv())
    expect_false(same(proven))
    proven <- original
    body(proven) <- quote(x - y * 3)
    expect_false(same(compiler::cmpfun(proven)))
    proven <- original
    formals(proven)$y <- 3
    expect_false(same(compiler::cmpfun(proven)))
    expect_true(same(original))
})

test_that("a kept proof admits the original helper again but never a traced one", {
    values <- rep(1, 4096L)
    source <- dta_double(values)
    operation <- function() source + 1
    ns <- asNamespace("dtatools")
    for (i in 1:3) invisible(operation())
    expected <- as.double(.dtatools_numeric_entry_expected("scalar"))
    expect_identical(.dtatools_numeric_entry_observe(operation)$counts[["scalar"]], expected)
    hits <- 0L
    suppressMessages(trace(".tab_missing_codes", tracer = function() hits <<- hits + 1L,
                           where = ns, print = FALSE))
    traced <- tryCatch(
        .dtatools_numeric_entry_observe(operation),
        finally = suppressMessages(untrace(".tab_missing_codes", where = ns))
    )
    expect_identical(traced$counts[["scalar"]], 0)
    expect_true(hits > 0L)
    expect_identical(as.double(traced$result), values + 1)
    expect_identical(.dtatools_numeric_entry_observe(operation)$counts[["scalar"]], expected)
})
