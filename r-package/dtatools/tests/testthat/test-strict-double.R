test_that("strict double construction preserves bits names and rejection policy", {
    bits <- function(x) writeBin(as.double(x), raw(), size = 8L)
    input <- c(-0, .Machine$double.xmin / 2, -.Machine$double.xmax / 2,
               .Machine$double.xmax / 2, NA_real_, tagged_missing(letters),
               -tagged_missing("a"))
    names(input) <- paste0("v", seq_along(input))
    result <- dta_double(input)
    expect_identical(bits(result), bits(input))
    expect_identical(names(result), names(input))
    expect_identical(names(attributes(result)), c("stata.storage", "class", "names"))
    expect_identical(as.double(dta_double(double())), double())
    expect_identical(as.double(dta_double(c(TRUE, NA))), c(1, NA_real_))
    for (invalid in list(NaN, Inf, -Inf, .Machine$double.xmax)) {
        expect_error(dta_double(invalid), "No Stata numeric storage")
    }
})

test_that("strict double native admission never reads foreign or attributed inputs", {
    invisible(dta_double(c(1, 2)))
    # Resolve the actual public fit route before asking its native entry point.
    expect_true(dtatools:::.dta_storage_holds(c(1, 2), "double"))
    construct <- function(value) {
        .Call(C_dtatools_construct_double, value, environment(), .strict_double_dependencies)
    }
    fits <- function(value, storage = "double") {
        .Call(C_dtatools_double_fits, value, environment(), .strict_double_dependencies)
    }
    environment(construct) <- asNamespace("dtatools")
    environment(fits) <- asNamespace("dtatools")
    reads <- 0L
    foreign <- .Call(C_dtatools_callback_double, c(1, 2), function() {
        reads <<- reads + 1L
    }, TRUE)
    expect_null(construct(foreign))
    expect_null(fits(foreign))
    expect_identical(reads, 0L)
    for (value in list(c(a = 1), structure(c(1, 2), class = "Date"))) {
        expect_null(construct(value))
        expect_null(fits(value))
    }
    if (.dtatools_execution_profile_expected()) {
        expect_identical(fits(c(1, 2)), TRUE)
    } else {
        expect_null(fits(c(1, 2)))
    }
    expect_null(fits(c(1, 2), "float"))
    expect_null(construct(NaN))
})

test_that("strict double output retains independent handles and backing rules", {
    invisible(dta_double(c(1, 2)))
    native_expected <- .dtatools_execution_profile_expected()
    attempt <- function(value) {
        .Call(C_dtatools_construct_double, value, environment(),
              .strict_double_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    construct <- function(value) {
        # Exercise the same representation through the real route first.
        public <- dta_double(value)
        native <- attempt(value)
        expect_identical(as.double(public), as.double(value))
        if (native_expected) {
            expect_type(native, "double")
            native
        } else {
            expect_null(native)
            public
        }
    }
    plain <- c(1, 2)
    result <- construct(plain)
    pointer <- .Call(C_dtatools_owned_pointer, result, TRUE)
    .Call(C_dtatools_owned_pointer_write, pointer, 1L, 9)
    expect_identical(plain, c(1, 2))
    expect_identical(as.double(result), c(9, 2))

    source <- .Call(C_dtatools_capture_column, c(1, 2))
    shared <- construct(source)
    expect_identical(.Call(C_dtatools_owned_info, source)$backing,
                     .Call(C_dtatools_owned_info, shared)$backing)
    pointer <- .Call(C_dtatools_owned_pointer, source, TRUE)
    .Call(C_dtatools_owned_pointer_write, pointer, 1L, 7)
    expect_identical(as.double(shared), c(1, 2))
    captured <- construct(source)
    .Call(C_dtatools_owned_pointer_write, pointer, 2L, 8)
    expect_identical(as.double(captured), c(7, 2))
})

test_that("double fit keeps delayed policy and unsupported-tag fallback", {
    events <- character()
    foreign <- .Call(C_dtatools_callback_double, c(1, 2), function() {
        events <<- c(events, "read")
        stop("foreign read failure")
    }, TRUE)
    expect_error(.dta_storage_holds(foreign, {
        events <<- c(events, "storage")
        "double"
    }), "foreign read failure")
    expect_identical(events, "read")
    expect_false(.dta_storage_holds(NaN, stop("unused storage")))
    invalid_tag <- readBin(as.raw(c(0xa2, 0x07, 0, 0, 0x41, 0, 0xf0, 0x7f)),
                           "double", n = 1L, size = 8L, endian = "little")
    # The legacy fit helper accepts unknown missing tags; construction rejects them.
    expect_true(.dta_storage_holds(invalid_tag, "double"))
    expect_error(dta_double(invalid_tag), "No Stata numeric storage")
})

test_that("strict double admission respects replaced and traced predicates", {
    attempt <- function(value = c(1, 2), storage = "double") {
        is.finite <- base::is.na
        .Call(C_dtatools_double_fits, value, environment(), .strict_double_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    expect_null(attempt())
    calls <- 0L
    trace("utf8ToInt", tracer = function() { calls <<- calls + 1L },
          where = baseenv(), print = FALSE)
    result <- tryCatch(dta_double(c(1, 2)),
                       finally = untrace("utf8ToInt", where = baseenv()))
    expect_identical(as.double(result), c(1, 2))
    expect_identical(calls, 2L)
})

test_that("strict double checks retain machine limit values and methods", {
    with_machine <- function(machine, expression) {
        local_mocked_bindings(.Machine = machine, .package = "base")
        force(expression)
    }
    calls <- 0L
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("$", "dtatools_strict_machine_limit", function(x, name) {
        calls <<- calls + 1L
        .subset2(x, name)
    }, envir = baseenv())
    withr::defer(rm(list = "$.dtatools_strict_machine_limit", envir = table))
    result <- with_machine(structure(.Machine, class = "dtatools_strict_machine_limit"), {
        value <- dta_double(c(1, 2))
        fits <- .dta_storage_holds(c(1, 2), "double")
        list(value = value, fits = fits, calls = calls)
    })
    expect_identical(result$calls, 2L)
    expect_identical(as.double(result$value), c(1, 2))
    expect_true(result$fits)

    machine <- .Machine
    machine$double.xmax <- 2
    result <- with_machine(machine, list(
        error = tryCatch(dta_double(c(1, 2)), error = conditionMessage),
        fits = .dta_storage_holds(c(1, 2), "double")
    ))
    expect_identical(result$error, "No Stata numeric storage can represent `x`")
    expect_false(result$fits)
})

test_that("storage fit preserves lazy replacement callback and error order", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("storage-fit-callback-order", function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        invisible(compiler::enableJIT(0L))
        ns <- asNamespace("dtatools")
        run <- function(fail) {
            data <- dibble(x = dta_double(c(1, 2)))
            values <- dta_double(c(3, 4))
            class(values) <- c("dtatools_holds_callback", class(values))
            events <- character()
            in_holds <- function() any(vapply(sys.calls(), function(call) {
                is.call(call) && identical(call[[1L]], as.name(".dta_storage_holds"))
            }, logical(1)))
            assign("vec_proxy.dtatools_holds_callback", function(x, ...) {
                if (in_holds()) {
                    events <<- c(events, "proxy")
                    if (fail) stop("proxy forced first")
                }
                unclass(x)
            }, .GlobalEnv)
            on.exit(rm("vec_proxy.dtatools_holds_callback", envir = .GlobalEnv), add = TRUE)
            trace(".tab_missing_codes", tracer = function() {
                if (in_holds()) {
                    events <<- c(events, "missing")
                    if (fail) stop("missing callback first")
                }
            }, where = ns, print = FALSE)
            on.exit(untrace(".tab_missing_codes", where = ns), add = TRUE)
            error <- tryCatch({ repl(data, x = values); NULL }, error = conditionMessage)
            list(events = events, error = error, values = as.double(data$x))
        }
        list(order = run(FALSE), error = run(TRUE))
    }, args = list(.libPaths()))
    expect_identical(observed$order$events, c("missing", "proxy", "proxy"))
    expect_null(observed$order$error)
    expect_identical(observed$order$values, c(3, 4))
    expect_identical(observed$error$events, "missing")
    expect_identical(observed$error$error, "missing callback first")
    expect_identical(observed$error$values, c(1, 2))
})

test_that("synthetic double fit entries decline without forcing arguments", {
    invisible(dta_double(c(1, 2)))
    invisible(.dta_storage_holds(c(1, 2), "double"))
    attempt <- function(doubles, storage = "double") {
        .Call(C_dtatools_double_fits, NULL, NULL, .strict_double_dependencies)
    }
    environment(attempt) <- asNamespace("dtatools")
    ordinary <- c(1, 2)
    expect_false(attempt(ordinary))
    expect_false(attempt(1))
    expect_identical(attempt(NULL), FALSE)
    expect_identical(attempt(), FALSE)
    owned <- as.double(dta_double(ordinary))
    expect_false(attempt(owned))
    expect_identical(attempt({ stop("doubles promise forced") }), FALSE)
    expect_identical(attempt(ordinary, { stop("storage promise forced") }), FALSE)
    events <- 0L
    reader <- new.env(parent = environment())
    makeActiveBinding("doubles", function() {
        events <<- events + 1L
        stop("active doubles binding invoked")
    }, reader)
    expect_identical(eval(quote(attempt(doubles)), reader), FALSE)
    expect_identical(events, 0L)
    expect_identical(attempt(c(1, 2)), FALSE)
    expect_identical(as.double(owned), ordinary)
})

test_that("successful double fit settles forwarded value and storage promises", {
    invisible(dta_double(c(1, 2)) + 1)
    invisible(dta_byte(c(1, 2)) + 1)
    bridge <- function(values, kind) {
        fits <- .dta_storage_holds(values, kind)
        list(fits = fits, read = function() list(values = values, storage = kind),
             expressions = list(substitute(values), substitute(kind)))
    }
    for (input in list(c(1, 2), double(), c(NA_real_, tagged_missing("a")),
                       as.double(dta_double(c(3, 4))))) {
        policy <- list2env(list(input = input, storage = "double"),
                          parent = environment())
        retained <- evalq(bridge(input, storage), policy)
        policy$input <- c(20, 30)
        policy$storage <- "byte"
        expect_true(retained$fits)
        expect_identical(retained$read(), list(values = input, storage = "double"))
        expect_identical(retained$expressions, alist(input, storage))
    }
})
