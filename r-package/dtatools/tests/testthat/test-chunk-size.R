.chunk_size <- function(value) .Call(C_dtatools_chunk_size, value)

test_that("the native size matches vctrs for the results it covers", {
    owned <- function(value) .Call(C_dtatools_capture_column, value)
    compact <- mean(dta_int(c(1, 2, 3)))
    values <- list(
        logical = c(TRUE, NA), integer = c(1L, NA, 3L), double = c(a = 1.5, b = NA),
        complex = 1i, character = c("a", NA), raw = as.raw(1:3), list = list(1, "a"),
        empty = double(), empty_list = list(), attributed = structure(1:2, note = "x"),
        byte = dta_byte(c(1, NA)), int = dta_int(c(1, 2, 3)), long = dta_long(c(5, 6)),
        float = dta_float(0.5), stata_double = dta_double(c(1.5, tagged_missing("a"))),
        named = dta_double(c(a = 1, b = 2)), empty_stata = dta_int(integer()),
        labelled = structure(dta_int(c(1, 2)), label = "x", format.stata = "%8.0g"),
        compact = compact, owned_real = owned(c(1, 2)), owned_integer = owned(c(1L, 2L, 3L)),
        owned_logical = owned(c(TRUE, FALSE)), owned_string = owned(c("a", "b"))
    )
    expect_true(.is_unmaterialized_numeric_altrep(compact))
    data <- read_dta(system.file("extdata", "all_types_v118.dta", package = "dtatools"))
    for (name in names(data)) values[[paste("file", name)]] <- .subset2(data, name)
    covered <- character()
    for (name in names(values)) {
        value <- values[[name]]
        size <- .chunk_size(value)
        if (is.null(size)) next
        covered <- c(covered, name)
        expect_identical(size, vctrs::vec_size(value), info = name)
        expect_true(vctrs::obj_is_vector(value), info = name)
    }
    expect_true(all(names(values)[!startsWith(names(values), "file ")] %in% covered))
    expect_gt(sum(startsWith(covered, "file ")), 0L)
    # Measuring a compact result leaves it compact.
    expect_true(.is_unmaterialized_numeric_altrep(compact))
})

test_that("the native size leaves other values to vctrs", {
    calls <- 0L
    foreign <- .Call(C_dtatools_callback_double, c(1, 2, 3), function() calls <<- calls + 1L,
                     FALSE)
    temporal <- .attach_dta_temporal(
        .construct_dta_numeric(c(1, 2) - 315619200, NULL, "long", temporal = 2L),
        structure(double(), format.stata = "%tc", tzone = "UTC",
                  class = c("dta_temporal", "dta_datetime", "POSIXct", "POSIXt")),
        "long"
    )
    expect_true(inherits(temporal, "dta_temporal"))
    subclassed <- dta_int(c(1, 2))
    class(subclassed) <- c("dta_special", class(subclassed))
    array <- dta_int(c(1, 2, 3, 4))
    attr(array, "dim") <- c(2L, 2L)
    values <- c(list(
        null = NULL, frame = data.frame(x = 1:2), factor = factor("a"), date = Sys.Date(),
        matrix = matrix(1:4, 2L), string = dta_string("a"), subclassed = subclassed,
        array = array, s4 = asS4(c(1, 2)), closure = function() NULL, environment = globalenv(),
        symbol = quote(x), sequence = 1:3, foreign = foreign, temporal = temporal
    ))
    for (name in names(values)) expect_null(.chunk_size(values[[name]]), info = name)
    expect_identical(calls, 0L)
})

test_that("grouped verbs size bare and Stata numeric results without vctrs", {
    skip_if_not_installed("dplyr", "1.2.1")
    counts <- c(obj_is_vector = 0L, vec_size = 0L)
    vctrs_namespace <- asNamespace("vctrs")
    for (name in names(counts)) {
        tracer <- substitute(function() counts[[KEY]] <<- counts[[KEY]] + 1L, list(KEY = name))
        suppressMessages(trace(name, tracer = eval(tracer), where = vctrs_namespace,
                               print = FALSE))
    }
    withr::defer(for (name in names(counts))
        suppressMessages(untrace(name, where = vctrs_namespace)))
    checks <- function(groups, verb) {
        data <- dibble(g = rep(seq_len(groups), length.out = 5L * groups),
                       x = dta_int(seq_len(5L * groups)),
                       s = rep(c("a", "b", "c", "d", "e"), groups))
        counts[] <<- 0L
        verb(data)
        counts
    }
    covered <- list(
        function(data) dplyr::summarise(data, m = mean(x), .by = g),
        function(data) dplyr::summarise(data, n = dplyr::n(), .by = g),
        function(data) dplyr::mutate(data, m = mean(x), .by = g),
        function(data) dplyr::mutate(data, m = x + 1, .by = g)
    )
    # The checks of covered results do not grow with the groups.
    for (verb in covered) expect_identical(checks(12L, verb), checks(3L, verb))
    # A factor is left to vctrs, which checks each group's result.
    factors <- list(
        function(data) dplyr::summarise(data, m = factor(s[[1L]]), .by = g),
        function(data) dplyr::mutate(data, m = factor(s), .by = g)
    )
    for (verb in factors) {
        expect_identical(checks(12L, verb) - checks(3L, verb),
                         c(obj_is_vector = 9L, vec_size = 9L))
    }
})

test_that("grouped verbs report sizes and non-vectors as before", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(g = c(1L, 2L, 1L, 3L, 2L), x = dta_int(c(1, 2, 3, 4, 5)))
    expect_error(dplyr::summarise(data, m = x[c(1L, 1L)], .by = g),
                 "`m` must be size 1, not 2")
    expect_error(dplyr::summarise(data, m = mean(x), y = x, .by = g),
                 "`y` must be size 1, not 2")
    expect_error(dplyr::mutate(data, m = x[c(1L, 1L, 1L)], .by = g),
                 "`m` must be size 2 or 1, not 3")
    expect_error(dplyr::summarise(data, m = function() x, .by = g), "`m` must be a vector")
    expect_error(dplyr::mutate(data, m = function() x, .by = g), "`m` must be a vector")
    expect_identical(as.double(dplyr::summarise(data, m = mean(x), .by = g)$m), c(2, 3.5, 4))
    expect_identical(as.double(dplyr::reframe(data, m = x[c(1L, 1L)], .by = g)$m),
                     c(1, 1, 2, 2, 4, 4))
})
