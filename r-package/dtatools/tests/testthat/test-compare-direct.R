# ADR 0060: `Ops.dta_numeric()` makes a comparison's kernel calls in one
# native call. These tests call it from a frame like the method's and
# compare the operators with `.dta_compare()`, the R code it replaces.
.compare_direct_native <- function(op, e1, e2) {
    .Generic <- op
    if (.Call(C_dtatools_compare_direct)) native else NULL
}
environment(.compare_direct_native) <- asNamespace("dtatools")

.compare_direct_ops <- c("==", "!=", "<", "<=", ">", ">=")

.compare_direct_outcome <- function(operation) {
    tryCatch(operation(), error = function(error) conditionMessage(error))
}

.compare_direct_vectors <- function() list(
    byte = dta_byte(c(1, -3, NA, tagged_missing("a"), 100)),
    int = dta_int(c(30000, 3, 7, NA, tagged_missing("z"))),
    long = dta_long(c(2e9, -1, 0, NA, 3)),
    float = dta_float(c(0.5, 3, -3, tagged_missing("a"), tagged_missing("b"))),
    double = dta_double(c(0.1, 3, -0, NA, tagged_missing("c"))),
    labelled = set_val_labels(dta_byte(c(1, 2, NA, tagged_missing("d"), 3)),
                              c(male = 1, female = 2)),
    bare = c(3, -0, Inf, NA, NaN),
    tagged = c(tagged_missing("a"), 3, NA, tagged_missing("z"), 0),
    integer = c(3L, NA, -2L, 0L, 1L),
    logical = c(TRUE, NA, FALSE, TRUE, FALSE)
)

.compare_direct_scalars <- function() list(
    three = 3, zero = -0, infinite = -Inf, missing = NA_real_, nan = NaN,
    tag_a = tagged_missing("a"), tag_z = tagged_missing("z"), integer_one = 3L,
    integer_na = NA_integer_, true = TRUE, logical_na = NA,
    stata = dta_int(3), stata_missing = dta_byte(NA),
    stata_tag = dta_float(tagged_missing("b")), stata_double = dta_double(0.1),
    computed = max(dta_int(c(1, 3))), labelled = set_val_labels(dta_byte(1), c(one = 1))
)

.compare_direct_pairs <- function() {
    vectors <- .compare_direct_vectors()
    scalars <- .compare_direct_scalars()
    stata <- names(vectors)[1:6]
    pairs <- list()
    for (left in stata) {
        for (right in names(vectors)) {
            pairs[[paste(left, right)]] <- list(vectors[[left]], vectors[[right]])
            pairs[[paste(right, left)]] <- list(vectors[[right]], vectors[[left]])
        }
        for (right in names(scalars)) {
            pairs[[paste(left, right)]] <- list(vectors[[left]], scalars[[right]])
            pairs[[paste(right, left)]] <- list(scalars[[right]], vectors[[left]])
        }
    }
    for (left in names(scalars)[12:17]) for (right in names(scalars)) {
        pairs[[paste(left, right)]] <- list(scalars[[left]], scalars[[right]])
        pairs[[paste(right, left)]] <- list(scalars[[right]], scalars[[left]])
    }
    pairs
}

test_that("comparisons give what the R code gives", {
    pairs <- .compare_direct_pairs()
    # The kernel takes neither integer nor logical vectors, nor NaN.
    declining <- c("bare", "integer", "logical", "nan")
    failures <- character()
    for (name in names(pairs)) for (op in .compare_direct_ops) {
        x <- pairs[[name]][[1L]]
        y <- pairs[[name]][[2L]]
        expected <- .compare_direct_outcome(function() .dta_compare(op, x, y))
        actual <- .compare_direct_outcome(
            function() getExportedValue("base", op)(x, y))
        if (!identical(actual, expected)) failures <- c(failures, paste(name, op))
        native <- .compare_direct_native(op, x, y)
        if (is.null(native) != any(strsplit(name, " ")[[1L]] %in% declining))
            failures <- c(failures, paste(name, op, "admission"))
        if (!is.null(native) && !identical(native, expected))
            failures <- c(failures, paste(name, op, "native"))
    }
    expect_identical(failures, character())
})

test_that("compact comparisons take one call", {
    x <- dta_int(c(1, 3, NA))
    m <- max(x, na.rm = TRUE)
    expect_identical(.compare_direct_native("==", x, m), c(FALSE, TRUE, FALSE))
    # Missing values sort above every number.
    expect_identical(.compare_direct_native("<", 2, x), c(FALSE, TRUE, TRUE))
    expect_identical(.compare_direct_native(">=", x, x), c(TRUE, TRUE, TRUE))
    hits <- 0L
    suppressMessages(trace(".dta_compare", tracer = function() hits <<- hits + 1L,
                           where = asNamespace("dtatools"), print = FALSE))
    withr::defer(suppressMessages(untrace(".dta_compare",
                                          where = asNamespace("dtatools"))))
    direct <- x == 3
    direct_hits <- hits
    hits <- 0L
    named <- x
    names(named) <- c("a", "b", "c")
    fallback <- named == 3
    fallback_hits <- hits
    expect_identical(direct, c(FALSE, TRUE, FALSE))
    expect_identical(fallback, c(FALSE, TRUE, FALSE))
    expect_identical(direct_hits, 0L)
    expect_identical(fallback_hits, 1L)
})

test_that("other operands leave comparisons to the R code", {
    native <- .compare_direct_native
    x <- dta_int(c(1, 2, 3))
    for (op in list("+", "%%", "!", "===", NA_character_, c("==", "!="), as.name("==")))
        expect_null(native(op, x, 2), info = deparse(op))
    bare <- c(1, 2, 3)
    expect_false(is.null(native("==", bare, 2)))
    shorter <- dta_int(c(1, 2))
    expect_null(native("==", x, shorter))
    expect_error(x == shorter)
    empty <- dta_int(numeric())
    expect_null(native("==", empty, 2))
    expect_identical(empty == 2, logical())
    named <- x
    names(named) <- c("a", "b", "c")
    subclass <- x
    class(subclass) <- c("probe_subclass", class(subclass))
    others <- list(named = named, subclass = subclass, character = "2",
                   factor = factor("2"), complex = 2i, list = list(2),
                   date = as.Date("2020-01-01"), matrix = matrix(1:3),
                   sequence = 1:3, named_bare = c(a = 2))
    for (name in names(others)) {
        other <- others[[name]]
        expect_null(native("==", x, other), info = name)
        expect_null(native("==", other, x), info = name)
    }
    # Operands still to be computed stay unevaluated.
    expect_null(native("==", x, stop("forced")))
    expect_null(native("==", stop("forced"), x))
    # The call never replaces a binding of `native` in its frame.
    bound <- function(op, e1, e2) {
        .Generic <- op
        native <- "kept"
        list(.Call(C_dtatools_compare_direct), native)
    }
    environment(bound) <- asNamespace("dtatools")
    expect_identical(bound("==", x, 2), list(FALSE, "kept"))
})

test_that("the thread option settles as the R code settles it", {
    x <- dta_int(seq_len(100L))
    expected <- .dta_compare("<", x, 50)
    for (threads in list(NULL, 0L, 2L, 2.5, -1, NA, "2", TRUE, c(1L, 2L))) {
        withr::local_options(dtatools.threads = threads)
        info <- deparse(threads)
        expect_identical(.compare_direct_native("<", x, 50), expected, info = info)
        expect_identical(x < 50, expected, info = info)
    }
    for (threads in list(Inf, 1e10, structure(2L, class = "probe"))) {
        withr::local_options(dtatools.threads = threads)
        info <- deparse(threads)
        expect_null(.compare_direct_native("<", x, 50), info = info)
        expect_identical(suppressWarnings(x < 50), expected, info = info)
    }
})
