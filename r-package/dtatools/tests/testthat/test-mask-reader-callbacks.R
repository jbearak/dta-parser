test_that("mask readers retain argument expressions for executable tracers", {
    groups <- list(rows = list(1L), keys = tibble::new_tibble(list(), nrow = 1L),
                   names = character(), type = "ungrouped")
    mask <- dtatools:::.new_dibble_expression_mask(
        list(x = dta_double(1)), groups, 1L, "mutate()")
    withr::defer(mask$forget())
    reader <- environment(mask$evaluate)
    trace("read", tracer = quote(stop(paste(
        deparse(substitute(generation)), deparse(substitute(name)),
        deparse(substitute(id)), sep = "/"))), where = reader, print = FALSE)
    withr::defer(untrace("read", where = reader))
    expect_error(mask$evaluate(rlang::quo(x), 1L), "generation/name/id", fixed = TRUE)
})

test_that("public masks retain reader replacement after binding construction", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(x = c(1, 2))
    result <- dplyr::mutate(data, y = {
        bindings <- parent.env(environment())
        getter <- activeBindingFunction("x", bindings)
        capture <- environment(getter)
        reader <- if (exists("state", capture, inherits = FALSE)) capture else
            parent.env(capture)
        captured_expressions <- list(substitute(generation, capture),
                                     substitute(name, capture), substitute(id, capture))
        replacement <- function(generation, name, id) {
            expressions <- list(substitute(generation), substitute(name), substitute(id))
            if (identical(expressions, alist(generation, name, id)) &&
                identical(captured_expressions, alist(state$current[[name]], name, id))) {
                c(10, 20)
            } else c(30, 40)
        }
        assign("read", replacement, reader)
        x
    })
    expect_identical(as.double(result$y), c(10, 20))
    expect_identical(as.double(data$x), c(1, 2))
})
