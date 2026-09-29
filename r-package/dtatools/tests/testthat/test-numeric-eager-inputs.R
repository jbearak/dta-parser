test_that("strict construction retains custom conversion local reads", {
    reads <- 0L
    method <- function(x, ...) {
        stored <- NULL
        makeActiveBinding("values", function(value) {
            if (!missing(value)) { stored <<- value; return(invisible(NULL)) }
            reads <<- reads + 1L
            stored + reads
        }, parent.frame())
        unclass(x)
    }
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "as.double.dtatools_eager_constructor"
    existed <- exists(key, table, inherits = FALSE)
    previous <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, previous, table) else rm(list = key, envir = table)
    })
    registerS3method("as.double", "dtatools_eager_constructor", method, baseenv())
    input <- structure(c(1, 2), class = "dtatools_eager_constructor")
    result <- dta_double(input)
    expected_reads <- if (.dtatools_bytecode_execution_expected()) 8L else 4L
    expect_identical(reads, expected_reads)
    expect_identical(as.double(result), c(1, 2) + expected_reads)
    expect_identical(dta_storage_type(result), "double")
    expect_identical(unclass(input), c(1, 2))
})

test_that("scalar admission leaves active operands to original recycling", {
    source <- dta_double(c(1, 2))
    invisible(source + 2)
    original <- get(".dta_data", asNamespace("dtatools"))
    observe <- function(slot, op) {
        reads <- 0L
        calls <- list()
        local_mocked_bindings(.dta_data = function(x, ordinary = FALSE) {
            frame <- parent.frame()
            stored <- NULL
            makeActiveBinding(slot, function(value) {
                if (!missing(value)) { stored <<- value; return(invisible(NULL)) }
                reads <<- reads + 1L
                calls[[length(calls) + 1L]] <<- sys.call(-1L)
                stored + reads
            }, frame)
            original(x, ordinary)
        }, .package = "dtatools")
        value <- if (op == "+") source + 2 else source * 2
        list(reads = reads, calls = calls, value = value)
    }
    for (slot in c("left", "right")) for (op in c("+", "*")) {
        record <- observe(slot, op)
        expected <- if (slot == "left") {
            if (op == "+") c(4, 5) else c(4, 6)
        } else {
            if (op == "+") c(4, 5) else c(3, 6)
        }
        expect_identical(record$reads, 1L, info = paste(slot, op))
        expect_identical(record$calls, list(quote(list2(...))), info = paste(slot, op))
        expect_identical(as.double(record$value), expected, info = paste(slot, op))
        expect_identical(dta_storage_type(record$value), "double", info = paste(slot, op))
    }
    expect_identical(as.double(source), c(1, 2))
})

test_that("recycling errors precede active numeric operand errors", {
    source <- dta_double(c(1, 2))
    original <- get(".dta_data", asNamespace("dtatools"))
    observe <- function() {
        events <- character()
        local_mocked_bindings(.dta_data = function(x, ordinary = FALSE) {
            makeActiveBinding("left", function(value) {
                if (!missing(value)) return(invisible(NULL))
                events <<- c(events, "operand")
                stop("active operand callback")
            }, parent.frame())
            original(x, ordinary)
        }, .package = "dtatools")
        local_mocked_bindings(vec_recycle_common = function(...) {
            events <<- c(events, "recycle")
            stop("recycling callback")
        }, .package = "vctrs")
        error <- tryCatch(source * 2, error = conditionMessage)
        list(error = error, events = events)
    }
    record <- observe()
    expect_identical(record$error, "recycling callback")
    expect_identical(record$events, "recycle")
    expect_identical(as.double(source), c(1, 2))
})

test_that("computed numeric admission preserves conversion local callbacks", {
    source <- dta_double(c(1, 4))
    original <- get(".collapse_missing", asNamespace("dtatools"))
    reads <- 0L
    method <- function(x, ...) {
        stored <- NULL
        makeActiveBinding("values", function(value) {
            if (!missing(value)) { stored <<- value; return(invisible(NULL)) }
            reads <<- reads + 1L
            stored
        }, parent.frame())
        unclass(x)
    }
    table <- get(".__S3MethodsTable__.", baseenv())
    key <- "as.double.dtatools_eager_computed"
    existed <- exists(key, table, inherits = FALSE)
    previous <- if (existed) get(key, table, inherits = FALSE)
    withr::defer({
        if (existed) assign(key, previous, table) else rm(list = key, envir = table)
    })
    registerS3method("as.double", "dtatools_eager_computed", method, baseenv())
    local_mocked_bindings(.collapse_missing = function(result, where = is.na(result)) {
        structure(original(result, where), class = "dtatools_eager_computed")
    }, .package = "dtatools")
    result <- sqrt(source)
    expect_identical(reads, if (.dtatools_bytecode_execution_expected()) 10L else 6L)
    expect_identical(as.double(result), c(1, 2))
    expect_identical(dta_storage_type(result), "double")
    expect_identical(as.double(source), c(1, 4))
})
