# These expectations come from main, including R_DISABLE_BYTECODE=1. They do
# not use a disabled candidate shortcut as the reference implementation.
.numeric_entry_method <- function(class, method, defer_env = parent.frame()) {
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- paste0("as.double.", class)
    existed <- exists(key, table, inherits = FALSE)
    original <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, original, table) else rm(list = key, envir = table)
    }, envir = defer_env)
    registerS3method("as.double", class, method, baseenv())
}

.numeric_entry_replace <- function(name, value, where) {
    unlockBinding(name, where)
    assign(name, value, where)
    lockBinding(name, where)
}

test_that("constructor input forcing retains callbacks on later local assignments", {
    invisible(dta_double(c(1, 2)))
    supplied <- 0L
    supply <- function() {
        supplied <<- supplied + 1L
        calls <- sys.calls()
        index <- which(vapply(calls, function(call) {
            identical(call[[1L]], quote(.construct_dta_numeric))
        }, logical(1)))
        stopifnot(length(index) == 1L)
        makeActiveBinding("result", function(value) {
            stop("constructor result callback")
        }, sys.frame(index))
        c(1, 2)
    }
    observed <- tryCatch({ dta_double(supply()); "success" }, error = conditionMessage)
    expect_identical(observed, "constructor result callback")
    expect_identical(supplied, 1L)
})

test_that("constructor conversion preserves all original local assignment callbacks", {
    invisible(dta_double(c(1, 2)))
    slots <- c("valid_owned", "missing_codes", "dta_missing", "invalid_missing",
               "observed", "encoded", "invalid_observed", "result")
    current_slot <- NULL
    method <- function(x, ...) {
        slot <- current_slot
        makeActiveBinding(slot, function(value) {
            stop(paste("constructor callback", slot))
        }, parent.frame())
        unclass(x)
    }
    .numeric_entry_method("dtatools_entry_constructor", method)
    input <- structure(c(1, 2), class = "dtatools_entry_constructor")
    for (slot in slots) {
        current_slot <- slot
        observed <- tryCatch({ dta_double(input); "success" }, error = conditionMessage)
        expect_identical(observed, paste("constructor callback", slot), info = slot)
    }
    expect_identical(unclass(input), c(1, 2))
})

test_that("constructor conversion retains the original completed caller frame", {
    invisible(dta_double(c(1, 2)))
    retained <- NULL
    method <- function(x, ...) {
        retained <<- parent.frame()
        unclass(x)
    }
    .numeric_entry_method("dtatools_entry_frame", method)
    input <- structure(c(1, 2), class = "dtatools_entry_frame")
    result <- dta_double(input)
    expected <- list(result = result, encoded = c(1, 2),
                     missing_codes = c(NA_integer_, NA_integer_),
                     observed = c(TRUE, TRUE), valid_owned = FALSE)
    observed <- lapply(names(expected), function(name) {
        get0(name, retained, inherits = FALSE, ifnotfound = "absent local")
    })
    names(observed) <- names(expected)
    expect_identical(observed, expected)
    expect_identical(as.double(result), c(1, 2))
    expect_identical(unclass(input), c(1, 2))
})

test_that("scalar data callbacks retain all original local assignment callbacks", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    ns <- asNamespace("dtatools")
    original <- get(".dta_data", ns)
    withr::defer(.numeric_entry_replace(".dta_data", original, ns))
    current_slot <- NULL
    replacement <- function(x, ordinary = FALSE) {
        slot <- current_slot
        makeActiveBinding(slot, function(value) {
            stop(paste("scalar callback", slot))
        }, parent.frame())
        original(x, ordinary)
    }
    .numeric_entry_replace(".dta_data", replacement, ns)
    for (slot in c("args", "operation", "result", "missing_operand")) {
        current_slot <- slot
        observed <- tryCatch({ source + 1; "success" }, error = conditionMessage)
        expect_identical(observed, paste("scalar callback", slot), info = slot)
    }
    expect_identical(as.double(source), c(1, 2))
})

test_that("self restoring scalar callbacks retain their later local assignments", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    ns <- asNamespace("dtatools")
    original <- get(".dta_data", ns)
    withr::defer(.numeric_entry_replace(".dta_data", original, ns))
    replacement <- function(x, ordinary = FALSE) {
        frame <- parent.frame()
        .numeric_entry_replace(".dta_data", original, ns)
        makeActiveBinding("args", function(value) {
            stop("self restoring args callback")
        }, frame)
        original(x, ordinary)
    }
    .numeric_entry_replace(".dta_data", replacement, ns)
    observed <- tryCatch({ source + 1; "success" }, error = conditionMessage)
    expect_identical(observed, "self restoring args callback")
    expect_identical(get(".dta_data", ns), original)
    expect_identical(as.double(source), c(1, 2))
})

test_that("self restoring scalar callbacks retain the original completed caller frame", {
    source <- dta_double(c(1, 2))
    invisible(source + 1)
    ns <- asNamespace("dtatools")
    original <- get(".dta_data", ns)
    withr::defer(.numeric_entry_replace(".dta_data", original, ns))
    retained <- NULL
    replacement <- function(x, ordinary = FALSE) {
        retained <<- parent.frame()
        .numeric_entry_replace(".dta_data", original, ns)
        original(x, ordinary)
    }
    .numeric_entry_replace(".dta_data", replacement, ns)
    result <- source + 1
    expected <- list(args = list(c(1, 2), c(1, 1)), operation = .Primitive("+"),
                     result = c(2, 3), missing_operand = c(FALSE, FALSE))
    observed <- lapply(names(expected), function(name) {
        get0(name, retained, inherits = FALSE, ifnotfound = "absent local")
    })
    names(observed) <- names(expected)
    expect_identical(observed, expected)
    expect_identical(as.double(result), c(2, 3))
    expect_identical(get(".dta_data", ns), original)
    expect_identical(as.double(source), c(1, 2))
})

test_that("computed conversion preserves all original local assignment callbacks", {
    source <- dta_double(c(1, 4))
    invisible(sqrt(source))
    ns <- asNamespace("dtatools")
    original <- get(".collapse_missing", ns)
    withr::defer(.numeric_entry_replace(".collapse_missing", original, ns))
    replacement <- function(result, where = is.na(result)) {
        structure(original(result, where), class = "dtatools_entry_computed")
    }
    current_slot <- NULL
    method <- function(x, ...) {
        slot <- current_slot
        makeActiveBinding(slot, function(value) {
            stop(paste("computed callback", slot))
        }, parent.frame())
        unclass(x)
    }
    .numeric_entry_method("dtatools_entry_computed", method)
    .numeric_entry_replace(".collapse_missing", replacement, ns)
    for (slot in c("missing_codes", "computational_nan", "invalid_result",
                   "observed", "encoded", "outside_double")) {
        current_slot <- slot
        observed <- tryCatch({ sqrt(source); "success" }, error = conditionMessage)
        expect_identical(observed, paste("computed callback", slot), info = slot)
    }
    expect_identical(as.double(source), c(1, 4))
})

test_that("constructor conversion does not introduce a plain double local assignment", {
    invisible(dta_double(c(1, 2)))
    calls <- 0L
    method <- function(x, ...) {
        makeActiveBinding("plain_double", function(value) {
            calls <<- calls + 1L
            stop("unexpected plain_double callback")
        }, parent.frame())
        unclass(x)
    }
    .numeric_entry_method("dtatools_entry_plain_double", method)
    input <- structure(c(1, 2), class = "dtatools_entry_plain_double")
    result <- tryCatch(dta_double(input), error = conditionMessage)
    expect_identical(calls, 0L)
    expect_identical(if (is.character(result)) result else as.double(result), c(1, 2))
    expect_identical(if (is.character(result)) NULL else dta_storage_type(result), "double")
    expect_identical(unclass(input), c(1, 2))
})

test_that("self untracing storage checks retain locals for later public mutations", {
    skip_if_not_installed("dplyr", "1.2.1")
    ns <- asNamespace("dtatools")
    data <- dibble(x = dta_double(c(1, 2)))
    values <- c(3, 4)
    invisible(get(".dta_storage_holds", ns)(values, "double"))
    observed <- new.env(parent = emptyenv())
    observed$frame <- NULL
    original <- get(".dta_storage_holds", ns)
    withr::defer({
        unlockBinding(".dta_storage_holds", ns)
        assign(".dta_storage_holds", original, ns)
        lockBinding(".dta_storage_holds", ns)
    })
    tracer <- substitute({
        assign("frame", environment(), envir = EVENTS)
        untrace(".dta_storage_holds", where = NS)
    }, list(EVENTS = observed, NS = ns))
    trace(".dta_storage_holds", tracer = tracer, where = ns, print = FALSE)
    result <- dplyr::mutate(data, x = values, z = {
        if (exists("codes", observed$frame, inherits = FALSE)) 1 else 2
    })
    expect_identical(as.double(result$x), values)
    expect_identical(as.double(result$z), c(1, 1))
    expect_identical(get0("codes", observed$frame, inherits = FALSE),
                     c(NA_integer_, NA_integer_))
    expect_identical(get(".dta_storage_holds", ns), original)
    expect_identical(as.double(data$x), c(1, 2))
})

test_that("self untracing metadata generation retains locals for later public generation", {
    ns <- asNamespace("dtatools")
    data <- dibble(x = dta_double(c(1, 2)))
    invisible(gen(data, warm = x + 1))
    observed <- new.env(parent = emptyenv())
    observed$frame <- NULL
    original <- get(".generate_attributes", ns)
    withr::defer({
        unlockBinding(".generate_attributes", ns)
        assign(".generate_attributes", original, ns)
        lockBinding(".generate_attributes", ns)
    })
    tracer <- substitute({
        assign("frame", environment(), envir = EVENTS)
        untrace(".generate_attributes", where = NS)
    }, list(EVENTS = observed, NS = ns))
    trace(".generate_attributes", tracer = tracer, where = ns, print = FALSE)
    gen(data, y = x + 1)
    gen(data, z = if (exists("kept", observed$frame, inherits = FALSE)) 1 else 2)
    expect_identical(as.double(data$y), c(2, 3))
    expect_identical(as.double(data$z), c(1, 1))
    expect_identical(get0("kept", observed$frame, inherits = FALSE), attributes(data$y))
    expect_identical(get(".generate_attributes", ns), original)
    expect_identical(as.double(data$x), c(1, 2))
})
