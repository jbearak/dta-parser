.shared_labelled <- function(values) {
    set_val_labels(set_var_label(dta_byte(values), "sex of child"),
                   .labels = c(male = 1, female = 2))
}
.shared_count <- function(code) {
    ns <- asNamespace("dtatools")
    hits <- 0L
    suppressMessages(trace(".combine_shared_dta", tracer = function() hits <<- hits + 1L,
                           where = ns, print = FALSE))
    on.exit(suppressMessages(untrace(".combine_shared_dta", where = ns)))
    value <- code()
    list(value = value, hits = hits)
}

test_that("group results that share their attributes combine as vctrs does", {
    x <- .shared_labelled(c(1L, 2L, 2L, 1L, 2L, 1L))
    attr(x, "notes") <- "a note"
    pieces <- list(x[1], x[3:4], x[5])
    rows <- list(1L, 2:3, 4:6)
    ptype <- .shared_dta_ptype(pieces)
    expect_identical(ptype, vctrs::vec_ptype_common(!!!pieces))
    expect_identical(.combine_shared_dta(pieces, ptype), vctrs::list_unchop(pieces))
    expect_identical(.combine_shared_dta(pieces, ptype, rows),
                     vctrs::list_unchop(pieces, indices = rows))

    data <- dibble(g = c(1, 2, 2, 3, 3, 3), x = x)
    mutated <- .shared_count(function()
        dplyr::mutate(data, f = dplyr::first(x), l = dplyr::lag(x), .by = g))
    expect_identical(mutated$hits, 2L)
    firsts <- lapply(rows, function(r) vctrs::vec_recycle(dplyr::first(x[r]), length(r)))
    expect_identical(mutated$value$f, vctrs::list_unchop(firsts, indices = rows))
    lags <- lapply(rows, function(r) dplyr::lag(x[r]))
    expect_identical(mutated$value$l, vctrs::list_unchop(lags, indices = rows))

    # A later expression reads each group's chunk as vctrs would cast it.
    summarised <- .shared_count(function()
        dplyr::summarise(data, f = dplyr::last(x),
                         order = paste(names(attributes(f)), collapse = ","), .by = g))
    expect_identical(summarised$hits, 1L)
    expect_identical(summarised$value$f, vctrs::vec_c(x[1], x[3], x[6]))
    expect_identical(as.character(summarised$value$order),
                     rep(paste(names(attributes(vctrs::vec_cast(x[1], ptype))), collapse = ","), 3))
})

test_that("group results that differ or signal while folding take the vctrs path", {
    x <- .shared_labelled(c(1L, 2L, 2L))
    relabelled <- set_var_label(x, "another label")
    expect_null(.shared_dta_ptype(list(x[1])))
    expect_null(.shared_dta_ptype(list(x[1], relabelled[2], x[3])))
    expect_null(.shared_dta_ptype(list(x[1], x[2], relabelled[3])))
    expect_null(.shared_dta_ptype(list(dta_double(1), dta_double(2))))
    named <- x
    names(named) <- c("a", "b", "c")
    expect_null(.shared_dta_ptype(list(named[1], named[2])))
    extra <- lapply(1:2, function(i) structure(x[i], extra = TRUE))
    expect_null(.shared_dta_ptype(extra))
    subclass <- x
    class(subclass) <- c("shared_subclass", class(x))
    expect_null(.shared_dta_ptype(list(subclass[1], subclass[2])))

    # Two names for one code warn in every fold, so the warnings stay vctrs's.
    duplicated <- dta_double(c(1, 2, 1, 2))
    attr(duplicated, "label") <- "duplicated codes"
    attr(duplicated, "labels") <- c(a = 1, b = 1, c = 2)
    pieces <- list(duplicated[1], duplicated[2], duplicated[3], duplicated[4])
    expect_null(.shared_dta_ptype(pieces))
    data <- dibble(g = c(1, 2, 3, 4), x = duplicated)
    summarised <- .shared_count(function()
        suppressWarnings(dplyr::summarise(data, f = dplyr::first(x), .by = g)))
    expect_identical(summarised$hits, 0L)
    expect_identical(summarised$value$f, suppressWarnings(vctrs::vec_c(!!!pieces)))
})
