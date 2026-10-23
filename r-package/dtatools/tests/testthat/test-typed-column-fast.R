.typed_fast <- function(value, row_count = length(value)) {
    typed <- .Call(C_dtatools_typed_column_fast, value)
    if (is.raw(typed)) typed <- .Call(C_dtatools_typed_scalar_fast, value, row_count)
    typed
}
.typed_facts <- function(x) list(
    value = x, attributes = attributes(x), altrep = .is_altrep(x),
    compact = .is_unmaterialized_numeric_altrep(x)
)
.typed_same <- function(x, y) {
    identical(x, y, num.eq = FALSE, single.NA = FALSE, attrib.as.set = FALSE)
}

test_that("typed values and bare scalars match the R code", {
    data <- read_dta(system.file("extdata", "all_types_v118.dta", package = "dtatools"))
    values <- list(
        byte = dta_byte(c(1, tagged_missing("a"))), int = dta_int(c(1, 2)), long = dta_long(5),
        float = dta_float(0.5), double = dta_double(c(a = 1.5, b = NA)),
        computed = mean(dta_int(c(1, 2, 3))),
        labelled = structure(dta_int(1), label = "x", format.stata = "%8.0g"),
        factor = factor(c("a", "b")), ordered = ordered("a"), logical = c(TRUE, NA),
        logical_scalar = NA, named_logical = c(a = TRUE), logical_matrix = matrix(TRUE),
        integer = 1L, integer_na = NA_integer_, integer_limit = 2147483620L,
        integer_minimum = -2147483647L, zero = 0L, double_scalar = 1.5, negative_zero = -0,
        large = 1e300, tiny = 1e-300
    )
    for (name in names(data)) values[[paste("file", name)]] <- .subset2(data, name)
    covered <- character()
    for (name in names(values)) {
        value <- values[[name]]
        fast <- .typed_fast(value)
        if (is.null(fast)) next
        covered <- c(covered, name)
        expected <- .typed_column(value, length(value), "summarise()")
        expect_true(.typed_same(.typed_facts(fast), .typed_facts(expected)), info = name)
        # A typed value comes back as the same vector.
        if (!is.integer(value) && !is.double(value) || is.object(value))
            expect_identical(rlang::obj_address(fast), rlang::obj_address(value), info = name)
    }
    expect_true(all(names(values)[!startsWith(names(values), "file ")] %in% covered))
    # The row count reaches the generated column as the R code passes it.
    expect_true(.typed_same(.typed_fast(1L, 1), .typed_column(1L, 1L, "summarise()")))
})

test_that("the shortcut leaves other values to the R code", {
    calls <- 0L
    foreign <- .Call(C_dtatools_callback_double, 1, function() calls <<- calls + 1L, FALSE)
    values <- list(
        integer_beyond = 2147483621L, nan = NaN, infinite = Inf, double_na = NA_real_,
        double_beyond = 8.1e307, double_below = -9e307, integers = 1:2, doubles = c(1.5, 2), named = c(a = 1),
        character = "a", string = dta_string("a"), s4 = asS4(1), foreign = foreign,
        date = Sys.Date(), datetime = Sys.time(), list = list(1), complex = 1i, raw = raw(0),
        haven = structure(1, labels = c(a = 1), class = c("haven_labelled",
                                                                          "vctrs_vctr", "double"))
    )
    # The shortcut does not read a foreign ALTREP value.
    expect_null(.typed_fast(foreign))
    expect_identical(calls, 0L)
    for (name in names(values)) {
        value <- values[[name]]
        expect_null(.typed_fast(value), info = name)
        expect_true(.typed_same(
            tryCatch(.retyped_column(value, NULL, length(value), "summarise()"), error = conditionMessage),
            tryCatch(.typed_column(value, length(value), "summarise()"), error = conditionMessage)
        ), info = name)
    }
    # The scalar call takes only a count the R code would accept unchanged.
    # The R code rejects `NULL` and the missing, negative, fractional and
    # infinite counts with its own error, and reads the others through
    # `as.double()`.
    counts <- list(character = "1", vector = c(1, 2), null = NULL, missing = NA_integer_,
                   negative = -1, fraction = 2.5, infinite = Inf, classed = dta_int(1))
    for (name in names(counts)) {
        count <- counts[[name]]
        expect_null(.typed_fast(1L, count), info = name)
        expect_null(.typed_fast(1.5, count), info = name)
        expect_identical(
            tryCatch(.retyped_column(1L, NULL, count, "summarise()"), error = function(e)
                list(conditionMessage(e), conditionCall(e))),
            tryCatch(.typed_column(1L, count, "summarise()"), error = function(e)
                list(conditionMessage(e), conditionCall(e))), info = name)
    }
    # R and C can parse 8e307 a unit apart, so either path may type the
    # limit. Both give the same column.
    for (value in c(8e307, -8e307)) expect_true(.typed_same(
        .retyped_column(value, NULL, 1L, "summarise()"), .typed_column(value, 1L, "summarise()")))
})

test_that("the shortcut reads no foreign class vector", {
    reads <- 0L
    value <- list(1)
    attr(value, "class") <- .Call(C_dtatools_callback_character, c("probe", "list"),
                                  function() reads <<- reads + 1L)
    expect_true(.is_altrep(attr(value, "class")))
    reads <- 0L
    expect_null(.typed_fast(value))
    expect_identical(reads, 0L)
})

test_that("a typed value leaves its row count unread", {
    reads <- 0L
    value <- mean(dta_int(c(1, 2, 3)))
    typed <- .retyped_column(value, NULL, {reads <- reads + 1L; 1L}, "summarise()")
    expect_identical(rlang::obj_address(typed), rlang::obj_address(value))
    expect_identical(reads, 0L)
    # A bare scalar reads it once.
    expect_identical(dta_storage_type(.retyped_column(2L, NULL, {reads <- reads + 1L; 1L},
                                                      "summarise()")), "long")
    expect_identical(reads, 1L)
    # A declined value leaves it to the R code, which reads it after its own
    # checks, so a foreign vector's length callback does not run first.
    lengths <- 0L
    foreign <- .Call(C_dtatools_callback_length, 1, function() lengths <<- lengths + 1L)
    for (value in list(foreign, c(1, 2), "a")) {
        reads <- 0L
        lengths <- 0L
        expect_null(.typed_fast(value, {reads <- reads + 1L; length(value)}))
        expect_identical(c(reads, lengths), c(0L, 0L))
    }
})

test_that("grouped summaries type bare and Stata numeric results without the R helpers", {
    skip_if_not_installed("dplyr", "1.2.1")
    ns <- asNamespace("dtatools")
    counts <- c(typed = 0L, generated = 0L)
    helpers <- c(typed = ".typed_column", generated = ".generated_column")
    for (key in names(helpers)) {
        tracer <- substitute(function() counts[[KEY]] <<- counts[[KEY]] + 1L, list(KEY = key))
        suppressMessages(trace(helpers[[key]], tracer = eval(tracer), where = ns, print = FALSE))
    }
    withr::defer(for (name in helpers) suppressMessages(untrace(name, where = ns)))
    calls <- function(groups, verb) {
        data <- dibble(g = rep(seq_len(groups), length.out = 5L * groups),
                       x = dta_int(seq_len(5L * groups)),
                       s = rep(c("a", "b", "c", "d", "e"), groups))
        counts[] <<- 0L
        result <- verb(data)
        list(counts = counts, result = result)
    }
    covered <- function(data) dplyr::summarise(data, n = dplyr::n(), m = mean(x), k = 2.5,
                                               .by = g)
    # The helpers' calls do not grow with the groups.
    expect_identical(calls(12L, covered)$counts, calls(3L, covered)$counts)
    result <- calls(3L, covered)$result
    expect_identical(as.double(result$n), c(5, 5, 5))
    expect_identical(dta_storage_type(result$n), "long")
    expect_identical(dta_storage_type(result$k), "double")
    # A string result is left to the R code, once per group.
    strings <- function(data) dplyr::summarise(data, t = dplyr::first(s), .by = g)
    expect_identical(calls(12L, strings)$counts[["typed"]] - calls(3L, strings)$counts[["typed"]],
                     9L)
})
