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
# A float whose buffer holds 0.1 itself, as `data.table::set()` can leave
# one, rather than the single-precision value the constructor stores.
.shared_unrounded <- function() {
    structure(0.1, stata.storage = "float", label = "v",
              class = .dta_storage_class("float"))
}
.shared_duplicated <- function() {
    duplicated <- dta_double(c(1, 2, 1, 2))
    attr(duplicated, "label") <- "duplicated codes"
    attr(duplicated, "labels") <- c(a = 1, b = 1, c = 2)
    duplicated
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
})

test_that("grouped dplyr verbs combine shared group results in one pass", {
    skip_if_not_installed("dplyr", "1.2.1")
    x <- .shared_labelled(c(1L, 2L, 2L, 1L, 2L, 1L))
    attr(x, "notes") <- "a note"
    rows <- list(1L, 2:3, 4:6)
    data <- dibble(g = c(1, 2, 2, 3, 3, 3), x = x)
    mutated <- .shared_count(function()
        dplyr::mutate(data, f = dplyr::first(x), l = dplyr::lag(x), .by = g))
    expect_identical(mutated$hits, 2L)
    firsts <- lapply(rows, function(r) vctrs::vec_recycle(dplyr::first(x[r]), length(r)))
    expect_identical(mutated$value$f, vctrs::list_unchop(firsts, indices = rows))
    lags <- lapply(rows, function(r) dplyr::lag(x[r]))
    expect_identical(mutated$value$l, vctrs::list_unchop(lags, indices = rows))

    # A later expression reads each group's chunk as vctrs would cast it.
    ptype <- vctrs::vec_ptype(x)
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

    # identical() alone takes .a and .b for one value, but they are two codes.
    tagged <- function(code) set_val_labels(set_var_label(dta_double(1), "v"),
        .labels = c(yes = 1, Missing = tagged_missing(code)))
    pieces <- list(tagged("a"), tagged("a"), tagged("a"), tagged("b"))
    expect_true(identical(attributes(pieces[[1L]]), attributes(pieces[[4L]])))
    expect_null(.shared_dta_ptype(pieces))
    expect_identical(missing_tag(val_labels(vctrs::vec_c(!!!pieces))),
                     c(yes = NA, Missing = "a", Missing = "b"))

    # Two names for one code warn in every fold.
    duplicated <- .shared_duplicated()
    expect_null(.shared_dta_ptype(lapply(1:4, function(i) duplicated[i])))

    # The cast rounds a float value that single precision cannot hold.
    rounded <- set_var_label(dta_float(c(0.1, 2)), "v")[1:2]
    expect_identical(attributes(rounded), attributes(.shared_unrounded()))
    expect_false(is.null(.shared_dta_ptype(list(rounded, rounded))))
    expect_null(.shared_dta_ptype(list(rounded, .shared_unrounded())))
})

test_that("a later summary expression reads a float group result as cast", {
    skip_if_not_installed("dplyr", "1.2.1")
    unrounded <- .shared_unrounded()
    data <- dibble(g = c(1, 2))
    summarised <- .shared_count(function()
        dplyr::summarise(data, f = unrounded, z = as.double(f), .by = g))
    expect_identical(summarised$hits, 0L)
    expect_identical(as.double(summarised$value$f), rep(as.double(dta_float(0.1)), 2))
    expect_identical(as.double(summarised$value$z), as.double(summarised$value$f))
})

test_that("grouped dplyr verbs keep vctrs's warnings for conflicting labels", {
    skip_if_not_installed("dplyr", "1.2.1")
    duplicated <- .shared_duplicated()
    pieces <- lapply(1:4, function(i) duplicated[i])
    data <- dibble(g = c(1, 2, 3, 4), x = duplicated)
    summarised <- .shared_count(function()
        suppressWarnings(dplyr::summarise(data, f = dplyr::first(x), .by = g)))
    expect_identical(summarised$hits, 0L)
    expect_identical(summarised$value$f, suppressWarnings(vctrs::vec_c(!!!pieces)))
})
