test_that("bare S4 numeric policies retain constructor and temporal errors", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    ordinary <- list(
        construct = function() dta_double(values),
        computed = function() dtatools:::.dta_computed(values, "double"),
        scalar = function() source + 1,
        holds = function() dtatools:::.dta_storage_holds(values, "double"))
    for (i in 1:5) for (operation in ordinary) invisible(operation())
    for (route in names(ordinary)) {
        observed <- .dtatools_numeric_entry_observe(ordinary[[route]])
        expect_identical(observed$counts[[route]],
                         as.double(.dtatools_numeric_entry_expected(route)), info = route)
        expect_identical(if (route == "holds") observed$result else as.double(observed$result),
                         if (route == "holds") TRUE else if (route == "scalar") values + 1 else values,
                         info = route)
    }

    storage <- asS4("double")
    temporal <- asS4(0L)
    prototype <- dta_double(double())
    attr(prototype, "stata.storage") <- storage
    expect_null(attributes(storage))
    expect_null(attributes(temporal))
    expect_true(isS4(storage))
    expect_true(isS4(temporal))
    operations <- list(
        construct_storage = function() dtatools:::.construct_dta_numeric(values, NULL, storage),
        restore_storage = function() vctrs::vec_restore(values, prototype),
        computed_temporal = function() dtatools:::.dta_computed(values, "double", temporal),
        construct_temporal = function() dtatools:::.construct_dta_numeric(values, NULL, "double", temporal))
    for (name in names(operations)) {
        invisible(.dtatools_numeric_entry_counts(TRUE))
        expect_error(operations[[name]](),
                     if (grepl("storage$", name)) "invalid compact Stata numeric storage type" else
                         "invalid Stata temporal storage type", fixed = TRUE, info = name)
        expect_identical(.dtatools_numeric_entry_counts(FALSE),
                         c(construct = 0, computed = 0, scalar = 0, holds = 0), info = name)
    }
    expect_identical(attr(prototype, "stata.storage"), storage)
    expect_identical(as.double(source), values)
})

test_that("bare S4 storage policies retain computed scalar and holds fallback results", {
    values <- rep(c(1, 2), length.out = 2048L)
    storage <- asS4("double")
    typed <- dta_double(values)
    source <- typed
    attr(source, "stata.storage") <- storage
    operations <- list(
        computed = function() dtatools:::.dta_computed(values, storage),
        scalar = function() dtatools:::.dta_arith_base("+", typed, 1, storage),
        scalar_attribute = function() source + 1,
        holds = function() dtatools:::.dta_storage_holds(values, storage))
    routes <- c(computed = "computed", scalar = "scalar", scalar_attribute = "scalar", holds = "holds")
    expected_attributes <- attributes(dta_double(double()))
    for (name in names(operations)) {
        observed <- .dtatools_numeric_entry_observe(operations[[name]])
        expect_identical(observed$counts[[routes[[name]]]], 0, info = name)
        expect_identical(if (name == "holds") observed$result else as.double(observed$result),
                         if (name == "holds") TRUE else if (name == "computed") values else values + 1,
                         info = name)
        expect_identical(attributes(observed$result),
                         if (name == "holds") NULL else expected_attributes, info = name)
    }
    expect_identical(attr(source, "stata.storage"), storage)
    expect_identical(as.double(source), values)
})
