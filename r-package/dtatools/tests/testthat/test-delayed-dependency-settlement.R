# These observations restore every base/import binding before testthat sees it.
.dtatools_delayed_dependency_probe <- function(operation, symbol, where,
                                                native = TRUE, repeat_call = FALSE) {
    ns <- asNamespace('dtatools')
    state <- if (exists('.numeric_helper_state', ns, inherits = FALSE))
        get('.numeric_helper_state', ns) else NULL
    saved <- if (!is.null(state)) state$dependencies else NULL
    get_original <- base::get
    identical_original <- base::identical
    original <- get_original(symbol, where, inherits = FALSE)
    holder <- new.env(parent = baseenv())
    holder$fn <- original
    replacement <- function(...) stop('delayed dependency changed', call. = FALSE)
    if (symbol == '.Machine') {
        replacement <- original
        replacement$double.xmax <- 2
    }
    restore <- function() {
        unlockBinding(symbol, where)
        assign(symbol, original, where)
        lockBinding(symbol, where)
        if (!is.null(state)) state$dependencies <- saved
    }
    on.exit(restore(), add = TRUE)
    if (!is.null(state) && !native) state$dependencies <- NULL
    unlockBinding(symbol, where)
    delayedAssign(symbol, fn, eval.env = holder, assign.env = where)
    lockBinding(symbol, where)
    first <- operation()
    holder$fn <- replacement
    if (repeat_call) {
        second <- tryCatch(operation(), error = conditionMessage)
        settled <- NULL
    } else {
        settled <- identical_original(get_original(symbol, where, inherits = FALSE), original)
        second <- NULL
    }
    restore()
    normalize <- function(x) if (is.double(x)) as.double(x) else x
    list(first = normalize(first), settled = settled, second = normalize(second))
}

.dtatools_delayed_dependency_operations <- function() {
    values <- c(1, 2)
    source <- dta_double(values)
    operations <- list(
        scalar = function() source + 1,
        construct = function() dta_double(values),
        computed = function() dtatools:::.dta_computed(values, 'double'),
        holds = function() dtatools:::.dta_storage_holds(values, 'double'))
    for (operation in operations) for (i in 1:3) invisible(operation())
    operations
}

test_that('numeric shortcuts preserve delayed dependency binding settlement', {
    operations <- .dtatools_delayed_dependency_operations()
    symbols <- c(
        'suppressWarnings', 'getExportedValue', 'withCallingHandlers',
        'parent.frame', 'list', 'is.na', 'is.infinite', 'is.finite', 'any',
        'abs', 'floor', '!', '|', '&', '==', '>', '<', '>=', '<=', '[', '[<-',
        'attr', 'names', 'names<-', '[[', 'length', 'rep', 'utf8ToInt',
        'identical', '/', '$', 'is.numeric', 'as.double', '.Machine',
        'is.primitive', 'isTRUE', 'inherits', 'is.null', 'typeof', 'is.factor',
        '%in%', 'dim', 'match', 'switch')
    for (route in names(operations)) for (symbol in symbols) {
        expected <- .dtatools_delayed_dependency_probe(
            operations[[route]], symbol, baseenv(), native = FALSE)
        actual <- .dtatools_delayed_dependency_probe(
            operations[[route]], symbol, baseenv())
        expect_identical(actual, expected, info = paste(route, symbol))
    }
    imports <- parent.env(asNamespace('vctrs'))
    expected <- .dtatools_delayed_dependency_probe(
        operations$scalar, 'list2', imports, native = FALSE)
    actual <- .dtatools_delayed_dependency_probe(operations$scalar, 'list2', imports)
    expect_identical(actual, expected, info = 'scalar imported list2')
})

test_that('delayed function dependencies retain later numeric results and errors', {
    operations <- .dtatools_delayed_dependency_operations()
    symbols <- list(
        scalar = c('suppressWarnings', 'getExportedValue', 'withCallingHandlers',
                   'is.na', 'is.infinite', 'is.finite', 'any', 'as.double'),
        construct = c('is.na', 'is.finite', 'any', 'dim', 'as.double'),
        computed = c('is.na', 'is.infinite', 'is.finite', 'any', 'as.double'),
        holds = c('is.na', 'is.finite', 'any'))
    for (route in names(symbols)) for (symbol in symbols[[route]]) {
        expected <- .dtatools_delayed_dependency_probe(
            operations[[route]], symbol, baseenv(), native = FALSE, repeat_call = TRUE)
        actual <- .dtatools_delayed_dependency_probe(
            operations[[route]], symbol, baseenv(), repeat_call = TRUE)
        expect_identical(actual, expected, info = paste(route, symbol))
        expect_identical(expected$second, expected$first, info = paste(route, symbol))
    }
    imports <- parent.env(asNamespace('vctrs'))
    expected <- .dtatools_delayed_dependency_probe(
        operations$scalar, 'list2', imports, native = FALSE, repeat_call = TRUE)
    actual <- .dtatools_delayed_dependency_probe(
        operations$scalar, 'list2', imports, repeat_call = TRUE)
    expect_identical(actual, expected)
    expect_identical(expected$second, c(2, 3))
})

test_that('delayed public machine limits settle before later numeric calls', {
    operations <- .dtatools_delayed_dependency_operations()
    for (route in names(operations)) {
        expected <- .dtatools_delayed_dependency_probe(
            operations[[route]], '.Machine', baseenv(), native = FALSE, repeat_call = TRUE)
        actual <- .dtatools_delayed_dependency_probe(
            operations[[route]], '.Machine', baseenv(), repeat_call = TRUE)
        expect_identical(actual, expected, info = route)
        expect_identical(expected$second, expected$first, info = route)
    }
})

test_that('delayed minimum getters settle through the original minimum promise', {
    ns <- asNamespace('dtatools')
    original <- get('.declared_dta_storage', ns)
    holder <- new.env(parent = baseenv())
    holder$fn <- original
    caller <- new.env(parent = environment())
    caller$values <- c(1, 2)
    caller$source <- dta_double(caller$values)
    delayedAssign('.declared_dta_storage', fn, eval.env = holder, assign.env = caller)
    expression <- quote(dtatools:::.dta_computed(values, .declared_dta_storage(source)))
    first <- eval(expression, caller)
    holder$fn <- function(...) stop('delayed minimum getter changed')
    second <- eval(expression, caller)
    expect_identical(as.double(first), c(1, 2))
    expect_identical(as.double(second), c(1, 2))
    expect_identical(get('.declared_dta_storage', caller, inherits = FALSE), original)
})
