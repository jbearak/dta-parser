.numeric_size_call <- function(name, ...) {
    .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
}

.numeric_size_observe <- function(operation) {
    invisible(.numeric_size_call("C_dtatools_numeric_size_stats", TRUE))
    invisible(.numeric_size_call("C_dtatools_numeric_proof_stats", TRUE))
    observed <- .dtatools_numeric_entry_observe(operation)
    observed$size <- .numeric_size_call("C_dtatools_numeric_size_stats", FALSE)
    observed$proof <- .numeric_size_call("C_dtatools_numeric_proof_stats", FALSE)
    observed
}

.numeric_size_gates <- function() {
    call <- .Primitive(".Call")
    gate <- get("C_dtatools_test_numeric_size_gate", asNamespace("dtatools"))
    list(scalar = function(x, y = 1) call(gate, 1L),
         computed = function(result) call(gate, 2L),
         construct = function(x) call(gate, 4L),
         holds = function(doubles) call(gate, 8L))
}

test_that("numeric size boundaries retain small fallback and large native publication", {
    expect_identical(.numeric_size_call("C_dtatools_test_numeric_size_minimum", NULL), 2048L)
    for (size in c(1L, 2047L, 2048L, 2049L)) {
        values <- rep(c(1, 2), length.out = size)
        source <- dta_double(values)
        owned <- dtatools:::.dta_data(source)
        operations <- list(
            construct = function() dta_double(values),
            owned_construct = function() dta_double(owned),
            computed = function() dtatools:::.dta_computed(values, "double"),
            scalar = function() source + 1,
            reverse = function() 1 + source,
            holds = function() dtatools:::.dta_storage_holds(values, "double"))
        routes <- c(construct = "construct", owned_construct = "construct",
                    computed = "computed", scalar = "scalar", reverse = "scalar", holds = "holds")
        for (operation in operations) for (i in 1:3) invisible(operation())
        for (name in names(operations)) {
            info <- paste(size, name)
            route <- routes[[name]]
            observed <- .numeric_size_observe(operations[[name]])
            expected <- c(construct = 0, computed = 0, scalar = 0, holds = 0)
            if (size >= 2048L && .dtatools_numeric_entry_expected(route)) expected[[route]] <- 1
            expect_identical(observed$counts, expected, info = info)
            expect_identical(if (route == "holds") observed$result else as.double(observed$result),
                             if (route == "holds") TRUE else if (route == "scalar") values + 1 else values,
                             info = info)
            expect_identical(dta_storage_type(observed$result),
                             if (route == "holds") NULL else "double", info = info)
            if (size < 2048L) {
                expect_identical(observed$proof, c(functions = 0, closures = 0), info = info)
                expect_identical(observed$size[[paste0(route, ".small")]], 1, info = info)
            } else {
                expect_true(observed$size[[paste0(route, ".continue")]] >= 1, info = info)
                # Scalar repeats use live binding and closure-component checks
                # after the first full profile proof, so their successful
                # checks do not increment the full-proof closure counter.
                if (.dtatools_numeric_entry_expected(route) && route != "scalar")
                    expect_true(observed$proof[["closures"]] > 0, info = info)
            }
        }
    }
})

test_that("numeric size preflight leaves unknown operands and foreign readers untouched", {
    gates <- .numeric_size_gates()
    values <- rep(1, 2048L)
    for (name in names(gates)) {
        gate <- gates[[name]]
        reads <- 0L
        foreign <- .numeric_size_call("C_dtatools_callback_length", values,
                                      function() reads <<- reads + 1L)
        expect_false(gate(foreign), info = name)
        expect_identical(reads, 0L, info = name)
        foreign <- .numeric_size_call("C_dtatools_callback_double", values,
                                      function() reads <<- reads + 1L, TRUE)
        expect_false(gate(foreign), info = name)
        expect_identical(reads, 0L, info = name)
        effects <- 0L
        expect_false(gate({ effects <- effects + 1L; values }), info = name)
        expect_identical(effects, 0L, info = name)
        env <- new.env(parent = environment())
        makeActiveBinding("arg", function() { effects <<- effects + 1L; values }, env)
        expect_false(eval(quote(gate(arg)), env), info = name)
        expect_identical(effects, 0L, info = name)
        rm("arg", envir = env)
        delayedAssign("arg", { effects <<- effects + 1L; values }, assign.env = env)
        expect_false(eval(quote(gate(arg)), env), info = name)
        expect_identical(effects, 0L, info = name)
        rm("arg", envir = env)
        delayedAssign("arg", values, assign.env = env)
        expect_true(eval(quote(gate(arg)), env), info = name)
        prior <- values
        values <- rep(9, 2049L)
        expect_identical(env$arg, values, info = name)
        values <- prior
        forced <- function(input) { force(input); gate(input) }
        expect_true(forced(values), info = name)
        expect_false(gate(), info = name)
        cycle <- new.env(parent = environment())
        delayedAssign("first", second, eval.env = cycle, assign.env = cycle)
        delayedAssign("second", first, eval.env = cycle, assign.env = cycle)
        expect_false(eval(quote(gate(first)), cycle), info = name)
    }
})

test_that("numeric size preflight does not treat dots references as ordinary bindings", {
    values <- rep(1, 4096L)
    for (gate in .numeric_size_gates()) {
        forward <- function(...) {
            assign("..1", values, envir = environment())
            gate(..1)
        }
        expect_false(forward(values))
    }
})

test_that("numeric size preflight rejects custom forwarded environments before lookup", {
    values <- rep(1, 2048L)
    for (gate in .numeric_size_gates()) {
        for (class in c("numeric_size_custom_environment", "UserDefinedDatabase")) {
            custom <- new.env(parent = baseenv())
            custom$payload <- values
            class(custom) <- class
            bridge <- new.env(parent = environment())
            delayedAssign("arg", payload, eval.env = custom, assign.env = bridge)
            # R must never perform a database lookup on this classed ordinary
            # environment. The next test supplies a genuine object table.
            expect_false(eval(quote(gate(arg)), bridge), info = class)
        }
    }
})

test_that("numeric size preflight leaves genuine database operands to the original read", {
    skip_if_not_installed("callr")
    fixture <- normalizePath(test_path("fixtures", "numeric-size-userdb.c"))
    records <- .dtatools_child_r("numeric-size-userdb", function(libraries, fixture) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        scratch <- tempfile("numeric-size-userdb-")
        dir.create(scratch)
        on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
        prior <- setwd(scratch)
        on.exit(setwd(prior), add = TRUE)
        stopifnot(file.copy(fixture, "numeric-size-userdb.c"))
        output <- system2(file.path(R.home("bin"), "R"),
                          c("CMD", "SHLIB", "numeric-size-userdb.c"),
                          stdout = TRUE, stderr = TRUE)
        if (!is.null(attr(output, "status"))) stop(paste(output, collapse = "\n"))
        dyn.load(file.path(scratch, paste0("numeric-size-userdb", .Platform$dynlib.ext)))
        # Keep the DLL loaded until this child exits: attached table finalizers
        # contain pointers into it, including after each table is detached.
        ns <- asNamespace("dtatools")
        call <- function(name, ...) .Primitive(".Call")(get(name, ns), ...)
        replace <- function(name, value) {
            unlockBinding(name, ns); assign(name, value, ns); lockBinding(name, ns)
        }
        run <- function(size, route, traced) {
            values <- rep(c(1, 2), length.out = size)
            value <- if (route %in% c("scalar", "reverse")) dta_double(values) else values
            pointer <- .Call("numeric_size_userdb_create", value)
            table_name <- paste("numeric-size-userdb", size, route, traced, sep = "-")
            database <- attach(pointer, name = table_name, warn.conflicts = FALSE)
            on.exit(detach(table_name, character.only = TRUE), add = TRUE)
            name <- switch(route, scalar = ".dta_arith_base", reverse = ".dta_arith_base",
                           computed = ".dta_computed", construct = ".construct_dta_numeric",
                           holds = ".dta_storage_holds")
            original <- get(name, ns)
            events <- character()
            if (traced) {
                entry <- function() { events <<- c(events, "entry"); untrace(name, where = ns) }
                trace(name, tracer = as.call(list(entry)), where = ns, print = FALSE)
                on.exit(replace(name, original), add = TRUE)
            }
            scope <- new.env(parent = database)
            scope$operation <- get(name, ns)
            expression <- switch(route,
                scalar = quote(operation("+", operand, 1, "double")),
                reverse = quote(operation("+", 1, operand, "double")),
                computed = quote(operation(operand, "double")),
                construct = quote(operation(operand, NULL, "double")),
                holds = quote(operation(operand, "double")))
            invisible(.Call("numeric_size_userdb_gets", pointer, TRUE))
            invisible(call("C_dtatools_numeric_size_stats", TRUE))
            invisible(call("C_dtatools_numeric_entry_stats", TRUE))
            observed <- eval(expression, scope)
            key <- if (route == "reverse") "scalar" else route
            list(size = size, route = route, traced = traced,
                 gets = .Call("numeric_size_userdb_gets", pointer, FALSE), events = events,
                 unknown = call("C_dtatools_numeric_size_stats", FALSE)[[paste0(key, ".unknown")]],
                 entries = call("C_dtatools_numeric_entry_stats", FALSE)[[key]],
                 value = if (route == "holds") observed else as.double(observed),
                 storage = dta_storage_type(observed))
        }
        records <- list()
        for (size in c(2047L, 2048L))
            for (route in c("scalar", "reverse", "computed", "construct", "holds"))
                for (traced in c(FALSE, TRUE))
                    records[[paste(size, route, traced)]] <- run(size, route, traced)
        records
    }, args = list(libraries = .libPaths(), fixture = fixture))
    expect_length(records, 20L)
    for (name in names(records)) {
        record <- records[[name]]
        values <- rep(c(1, 2), length.out = record$size)
        expected <- if (record$route == "holds") TRUE else
            if (record$route %in% c("scalar", "reverse")) values + 1 else values
        expect_identical(record$gets, 1L, info = name)
        expect_identical(record$unknown, 1, info = name)
        expect_identical(record$entries, 0, info = name)
        expect_identical(record$events, if (record$traced) "entry" else character(), info = name)
        expect_identical(record$value, expected, info = name)
        expect_identical(record$storage, if (record$route == "holds") NULL else "double", info = name)
    }
})

test_that("small numeric fallback settles forwarded operand promises", {
    values <- c(1, 2)
    source <- dta_double(values)
    retained <- NULL
    operations <- list(
        construct = function(input) { retained <<- environment(); dta_double(input) },
        computed = function(input) {
            retained <<- environment(); dtatools:::.dta_computed(input, "double")
        },
        scalar = function(input) { retained <<- environment(); input + 1 },
        holds = function(input) {
            retained <<- environment(); dtatools:::.dta_storage_holds(input, "double")
        })
    for (route in names(operations)) {
        external <- if (route == "scalar") source else values
        original <- external
        observed <- .numeric_size_observe(function() operations[[route]](external))
        external <- NULL
        expect_identical(retained$input, original, info = route)
        expect_identical(substitute(input, retained), quote(external), info = route)
        expect_identical(observed$counts, c(construct = 0, computed = 0, scalar = 0, holds = 0),
                         info = route)
        expect_identical(if (route == "holds") observed$result else as.double(observed$result),
                         if (route == "holds") TRUE else if (route == "scalar") values + 1 else values,
                         info = route)
    }
})

test_that("large numeric routes retain executable helper callbacks after size admission", {
    values <- rep(c(1, 2), length.out = 2048L)
    source <- dta_double(values)
    operations <- list(scalar = function() source + 1,
                       computed = function() dtatools:::.dta_computed(values, "double"),
                       construct = function() dta_double(values),
                       holds = function() dtatools:::.dta_storage_holds(values, "double"))
    for (operation in operations) for (i in 1:3) invisible(operation())
    for (route in names(operations)) {
        control <- .numeric_size_observe(operations[[route]])
        expect_identical(control$counts[[route]],
                         as.double(.dtatools_numeric_entry_expected(route)), info = route)
    }
    ns <- asNamespace("dtatools")
    hits <- 0L
    trace(".tab_missing_codes", tracer = function() hits <<- hits + 1L,
          where = ns, print = FALSE)
    withr::defer(untrace(".tab_missing_codes", where = ns))
    for (route in names(operations)) {
        hits <- 0L
        observed <- .numeric_size_observe(operations[[route]])
        expect_identical(observed$counts[[route]], 0, info = route)
        expect_true(observed$size[[paste0(route, ".continue")]] >= 1, info = route)
        expect_true(hits > 0L, info = route)
        expect_identical(if (route == "holds") observed$result else as.double(observed$result),
                         if (route == "holds") TRUE else if (route == "scalar") values + 1 else values,
                         info = route)
    }
})

test_that("size admission does not replace changed or self-untracing executing closures", {
    ns <- asNamespace("dtatools")
    targets <- c(scalar = ".dta_arith_base", computed = ".dta_computed",
                 construct = ".construct_dta_numeric", holds = ".dta_storage_holds")
    replace <- function(name, value) {
        unlockBinding(name, ns); assign(name, value, ns); lockBinding(name, ns)
    }
    for (size in c(2047L, 2048L)) {
        values <- rep(1, size)
        source <- dta_double(values)
        operations <- list(scalar = function() source + 1,
                           computed = function() dtatools:::.dta_computed(values, "double"),
                           construct = function() dta_double(values),
                           holds = function() dtatools:::.dta_storage_holds(values, "double"))
        for (route in names(targets)) {
            name <- targets[[route]]
            original <- get(name, ns)
            reference <- operations[[route]]()
            for (mode in c("body", "recompile")) {
                replacement <- original
                body(replacement) <- body(replacement)
                if (mode == "recompile") replacement <- compiler::cmpfun(
                    replacement, options = list(optimize = 0L))
                replace(name, replacement)
                observed <- tryCatch(.numeric_size_observe(operations[[route]]),
                                     finally = replace(name, original))
                expect_identical(observed$result, reference, info = paste(size, route, mode))
                expect_identical(observed$counts[[route]], 0, info = paste(size, route, mode))
            }
            events <- new.env(parent = emptyenv())
            events$frame <- NULL
            tracer <- substitute({
                assign("frame", environment(), envir = EVENTS)
                untrace(TARGET, where = NS)
            }, list(EVENTS = events, TARGET = name, NS = ns))
            trace(name, tracer = tracer, where = ns, print = FALSE)
            observed <- tryCatch(.numeric_size_observe(operations[[route]]),
                                 finally = replace(name, original))
            local <- switch(route, scalar = "args", computed = "values",
                            construct = "values", holds = "codes")
            expect_identical(observed$result, reference, info = paste(size, route))
            expect_identical(observed$counts[[route]], 0, info = paste(size, route))
            expect_true(exists(local, events$frame, inherits = FALSE), info = paste(size, route))
        }
    }
})

test_that("numeric size peeks retain their roots under GC and reentrant finalizers", {
    gates <- .numeric_size_gates()
    values <- rep(1, 2048L)
    finalized <- logical()
    for (i in 1:4) {
        token <- new.env(parent = emptyenv())
        reg.finalizer(token, function(key) {
            finalized <<- c(finalized, gates$construct(values))
        }, onexit = FALSE)
        rm(token)
        invisible(gc())
    }
    expect_identical(finalized, rep(TRUE, 4L))
    previous <- gctorture2(10L)
    withr::defer(gctorture2(previous))
    for (i in 1:6) {
        forced <- function(input) { force(input); gates$construct(input) }
        expect_true(forced(values))
    }
})
