test_that("canonical numeric production calls publish through the entry counters", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    operations <- list(
        construct = function() dta_double(values),
        scalar = function() source + 1,
        sqrt = function() sqrt(source),
        negate = function() -source,
        computed = function() dtatools:::.dta_computed(values, "double"),
        holds = function() dtatools:::.dta_storage_holds(values, "double"))
    routes <- c(construct = "construct", scalar = "scalar",
                sqrt = "computed", negate = "computed",
                computed = "computed", holds = "holds")
    expected_values <- list(construct = values, scalar = values + 1,
                            sqrt = sqrt(values), negate = -values,
                            computed = values, holds = TRUE)
    for (operation in operations) invisible(operation())
    for (name in names(operations)) {
        observed <- .dtatools_numeric_entry_observe(operations[[name]])
        expected <- c(construct = 0, computed = 0, scalar = 0, holds = 0)
        if (.dtatools_numeric_entry_expected(routes[[name]])) expected[[routes[[name]]]] <- 1
        expect_identical(observed$counts, expected, info = name)
        expect_identical(if (name == "holds") observed$result else as.double(observed$result),
                         expected_values[[name]], info = name)
        expect_identical(dta_storage_type(observed$result),
                         if (name == "holds") NULL else "double", info = name)
    }
    invisible(.dtatools_numeric_entry_counts(TRUE))
    expect_identical(.dtatools_numeric_entry_counts(FALSE),
                     c(construct = 0, computed = 0, scalar = 0, holds = 0))
    expect_identical(as.double(source), values)
})

test_that("scalar literals and reductions retain the small numeric fallback", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    operations <- list(literal = function() dta_double(1),
                       median = function() stats::median(source))
    expected_values <- c(literal = 1, median = 1.5)
    for (operation in operations) invisible(operation())
    for (name in names(operations)) {
        observed <- .dtatools_numeric_entry_observe(operations[[name]])
        expect_identical(observed$counts,
                         c(construct = 0, computed = 0, scalar = 0, holds = 0), info = name)
        expect_identical(as.double(observed$result), expected_values[[name]], info = name)
        expect_identical(dta_storage_type(observed$result), "double", info = name)
    }
})

test_that("numeric entry results retain visible public and helper returns", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    operations <- list(
        construct = function() withVisible(dta_double(values)),
        computed = function() withVisible(dtatools:::.dta_computed(values, "double")),
        scalar = function() withVisible(dtatools:::.dta_arith_base("+", source, 1, "double")),
        vec_arith = function() withVisible(vctrs::vec_arith("+", source, 1)),
        vec_math = function() withVisible(vctrs::vec_math("abs", source)))
    routes <- c(construct = "construct", computed = "computed", scalar = "scalar",
                vec_arith = "scalar", vec_math = "computed")
    for (operation in operations) for (i in 1:3) invisible(operation())
    for (name in names(operations)) {
        observed <- .dtatools_numeric_entry_observe(operations[[name]])
        expected <- c(construct = 0, computed = 0, scalar = 0, holds = 0)
        if (.dtatools_numeric_entry_expected(routes[[name]])) expected[[routes[[name]]]] <- 1
        expect_identical(observed$counts, expected, info = name)
        expect_true(observed$result$visible, info = name)
        expect_identical(as.double(observed$result$value),
                         if (routes[[name]] == "scalar") values + 1 else values, info = name)
    }
})

test_that("named numeric production results retain fallback names and values", {
    values <- stats::setNames(rep(c(1, 2), length.out = 2048L),
                             rep(c("a", "b"), length.out = 2048L))
    source <- dta_double(values)
    operations <- list(construct = function() dta_double(values),
                       scalar = function() source + 1,
                       computed = function() sqrt(source),
                       holds = function() dtatools:::.dta_storage_holds(values, "double"))
    expected <- list(construct = unname(values), scalar = unname(values) + 1,
                     computed = sqrt(unname(values)),
                     holds = TRUE)
    for (name in names(operations)) {
        observed <- .dtatools_numeric_entry_observe(operations[[name]])
        expect_identical(observed$counts, c(construct = 0, computed = 0, scalar = 0, holds = 0), info = name)
        expect_identical(if (name == "holds") observed$result else unname(as.double(observed$result)),
                         expected[[name]], info = name)
        expect_identical(names(observed$result), if (name == "holds") NULL else names(values),
                         info = name)
    }
})

test_that("unknown numeric entry promises stay on the original forcing path", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    events <- character()
    operations <- list(
        construct = function() dta_double({ events <<- c(events, "input"); values }),
        computed_input = function() dtatools:::.dta_computed(
            { events <<- c(events, "input"); values }, "double"),
        computed_minimum = function() dtatools:::.dta_computed(
            values, { events <<- c(events, "minimum"); "double" }),
        scalar = function() dtatools:::.dta_arith_base(
            { events <<- c(events, "op"); "+" }, source, 1, "double"),
        holds = function() dtatools:::.dta_storage_holds(
            values, { events <<- c(events, "storage"); "double" }))
    expected_events <- c(construct = "input", computed_input = "input",
                         computed_minimum = "minimum", scalar = "op", holds = "storage")
    for (name in names(operations)) {
        events <- character()
        observed <- .dtatools_numeric_entry_observe(operations[[name]])
        expect_identical(observed$counts, c(construct = 0, computed = 0, scalar = 0, holds = 0), info = name)
        expect_identical(events, unname(expected_events[[name]]), info = name)
        expect_identical(if (name == "holds") observed$result else as.double(observed$result),
                         if (name == "scalar") values + 1 else if (name == "holds") TRUE else values,
                         info = name)
    }
})

test_that("custom numeric conversions retain their callbacks without entry publication", {
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "as.double.dtatools_entry_counter"
    existed <- exists(key, table, inherits = FALSE)
    original <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, original, table) else rm(list = key, envir = table)
    })
    calls <- 0L
    registerS3method("as.double", "dtatools_entry_counter", function(x, ...) {
        calls <<- calls + 1L
        unclass(x)
    }, baseenv())
    values <- structure(rep(c(1, 2), length.out = 2048L), class = "dtatools_entry_counter")
    for (operation in list(function() dta_double(values),
                           function() dtatools:::.dta_computed(values, "double"))) {
        calls <- 0L
        observed <- .dtatools_numeric_entry_observe(operation)
        expect_identical(observed$counts, c(construct = 0, computed = 0, scalar = 0, holds = 0))
        expect_identical(calls, 1L)
        expect_identical(as.double(observed$result), unclass(values))
    }
    expect_identical(unclass(values), rep(c(1, 2), length.out = 2048L))
})

test_that("custom scalar readers retain their callbacks without entry publication", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    ns <- asNamespace("dtatools")
    original <- get(".dta_data", ns)
    calls <- 0L
    local_mocked_bindings(.dta_data = function(x, ordinary = FALSE) {
        calls <<- calls + 1L
        original(x, ordinary)
    }, .package = "dtatools")
    observed <- .dtatools_numeric_entry_observe(function() source + 1)
    expect_identical(observed$counts, c(construct = 0, computed = 0, scalar = 0, holds = 0))
    expect_identical(calls, 1L)
    expect_identical(as.double(observed$result), values + 1)
    expect_identical(as.double(source), values)
})

test_that("actual constructor callback frames retain unsafe native result bindings", {
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "as.double.dtatools_entry_result_slot"
    existed <- exists(key, table, inherits = FALSE)
    original <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, original, table) else rm(list = key, envir = table)
    })
    retained <- NULL
    current_slot <- NULL
    calls <- 0L
    registerS3method("as.double", "dtatools_entry_result_slot", function(x, ...) {
        retained <<- parent.frame()
        if (current_slot %in% c("value", "locked")) assign("native", "existing", retained)
        if (current_slot == "locked") lockBinding("native", retained)
        if (current_slot == "active") makeActiveBinding("native", function(...) {
            calls <<- calls + 1L
            stop("native active binding invoked")
        }, retained)
        if (current_slot == "delayed") delayedAssign("native", {
            calls <<- calls + 1L
            stop("native delayed binding forced")
        }, assign.env = retained)
        unclass(x)
    }, baseenv())
    values <- structure(rep(c(1, 2), length.out = 2048L), class = "dtatools_entry_result_slot")
    for (slot in c("absent", "value", "active", "delayed", "locked")) {
        current_slot <- slot
        calls <- 0L
        observed <- .dtatools_numeric_entry_observe(function() dta_double(values))
        expect_identical(observed$counts, c(construct = 0, computed = 0, scalar = 0, holds = 0), info = slot)
        expect_identical(calls, 0L, info = slot)
        expect_identical(as.double(observed$result), unclass(values), info = slot)
        if (slot == "absent") expect_false(exists("native", retained, inherits = FALSE))
        if (slot %in% c("value", "locked")) expect_identical(retained$native, "existing")
    }
})

test_that("scalar input names getters retain their original calls before arithmetic", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    invisible(source + 1)
    ns <- asNamespace("dtatools")
    has_counters <- exists("C_dtatools_numeric_entry_stats", ns, inherits = FALSE)
    if (has_counters) {
        positive <- .dtatools_numeric_entry_observe(function() source + 1)
        expect_identical(positive$counts[["scalar"]],
                         as.double(.dtatools_numeric_entry_expected()))
    }
    observe <- function(class) {
        table <- get(".__S3MethodsTable__.", baseenv())
        key <- paste0("names.", class)
        existed <- exists(key, table, inherits = FALSE)
        original <- if (existed) get(key, table, inherits = FALSE)
        on.exit({
            if (existed) assign(key, original, table) else rm(list = key, envir = table)
        })
        calls <- list()
        registerS3method("names", class, function(x) {
            calls[[length(calls) + 1L]] <<- list(
                call = sys.call(-1L), argument = substitute(x))
            NULL
        }, baseenv())
        if (has_counters) invisible(.dtatools_numeric_entry_counts(TRUE))
        result <- source + 1
        counts <- if (has_counters) .dtatools_numeric_entry_counts(FALSE) else NULL
        list(result = result, calls = calls, counts = counts)
    }
    for (class in c("dta_numeric", "vctrs_vctr")) {
        observed <- observe(class)
        expect_identical(observed$calls,
                         list(list(call = quote(names(x)), argument = source)), info = class)
        expect_identical(as.double(observed$result), values + 1, info = class)
        expect_null(names(observed$result), info = class)
        if (has_counters) expect_identical(observed$counts[["scalar"]], 0, info = class)
    }
    expect_identical(as.double(source), values)
})

test_that("numeric entry success settles original ancestor promises and expressions", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    invisible(source + 1)
    invisible(sqrt(source))
    ns <- asNamespace("dtatools")
    has_counters <- exists("C_dtatools_numeric_entry_stats", ns, inherits = FALSE)
    observe <- function(operation) {
        if (has_counters) .dtatools_numeric_entry_observe(operation) else
            list(result = operation(), counts = NULL)
    }
    expect_publication <- function(observed, route) {
        if (has_counters) {
            expected <- c(construct = 0, computed = 0, scalar = 0, holds = 0)
            if (.dtatools_numeric_entry_expected(route)) expected[[route]] <- 1
            expect_identical(observed$counts, expected, info = route)
        }
    }
    retained <- NULL

    external_values <- values
    construct <- function(input) {
        retained <<- environment()
        dta_double(input)
    }
    observed <- observe(function() construct(external_values))
    external_values <- rep(c(9, 10), length.out = 2048L)
    expect_identical(retained$input, values)
    expect_identical(substitute(input, retained), quote(external_values))
    expect_identical(as.double(observed$result), values)
    expect_publication(observed, "construct")

    external_values <- values
    external_minimum <- "double"
    external_temporal <- 0L
    computed <- function(input, minimum, temporal) {
        retained <<- environment()
        dtatools:::.dta_computed(input, minimum, temporal)
    }
    observed <- observe(function() computed(external_values, external_minimum, external_temporal))
    external_values <- rep(c(9, 10), length.out = 2048L)
    external_minimum <- "byte"
    external_temporal <- 1L
    expect_identical(retained$input, values)
    expect_identical(retained$minimum, "double")
    expect_identical(retained$temporal, 0L)
    expect_identical(substitute(input, retained), quote(external_values))
    expect_identical(substitute(minimum, retained), quote(external_minimum))
    expect_identical(substitute(temporal, retained), quote(external_temporal))
    expect_identical(as.double(observed$result), values)
    expect_publication(observed, "computed")

    external_op <- "+"
    external_source <- source
    external_scalar <- 1
    external_minimum <- "double"
    scalar <- function(op, x, y, minimum) {
        retained <<- environment()
        dtatools:::.dta_arith_base(op, x, y, minimum)
    }
    observed <- observe(function() scalar(
        external_op, external_source, external_scalar, external_minimum))
    external_op <- "-"
    external_source <- NULL
    external_scalar <- 99
    external_minimum <- "byte"
    expect_identical(retained$op, "+")
    expect_identical(retained$x, source)
    expect_identical(retained$y, 1)
    expect_identical(retained$minimum, "double")
    expect_identical(substitute(op, retained), quote(external_op))
    expect_identical(substitute(x, retained), quote(external_source))
    expect_identical(substitute(y, retained), quote(external_scalar))
    expect_identical(substitute(minimum, retained), quote(external_minimum))
    expect_identical(as.double(observed$result), values + 1)
    expect_publication(observed, "scalar")
    expect_identical(as.double(source), values)
})
