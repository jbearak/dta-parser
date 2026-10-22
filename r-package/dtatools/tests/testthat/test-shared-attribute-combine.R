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
# A labelled Stata numeric whose buffer holds `value` itself, as
# `data.table::set()` can leave one, though construction would change it.
.shared_uncast <- function(value = 0.1, storage = "float") {
    structure(value, stata.storage = storage, label = "v",
              class = .dta_storage_class(storage))
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

    # The cast rounds a float value that single precision cannot hold, and
    # byte storage holds no -0.
    rounded <- set_var_label(dta_float(c(0.1, 2)), "v")[1:2]
    expect_identical(attributes(rounded), attributes(.shared_uncast()))
    expect_false(is.null(.shared_dta_ptype(list(rounded, rounded))))
    expect_null(.shared_dta_ptype(list(rounded, .shared_uncast())))
    zero <- .shared_uncast(-0, "byte")
    expect_null(.shared_dta_ptype(list(zero, zero)))
    zero <- .shared_uncast(-0, "double")
    expect_false(is.null(.shared_dta_ptype(list(zero, zero))))
})

test_that("the kept-values check matches what construction returns", {
    bits <- function(high, low) {
        readBin(writeBin(c(as.integer(low), as.integer(high)), raw(), size = 4L,
                         endian = "little"), "double", endian = "little")
    }
    raw_values <- function(x) writeBin(as.double(unclass(x)), raw())
    cases <- list(
        c(1, 2), -127, 100, -128, 101, 1.5, -32767, 32740, -32768, 32741,
        2147483620, 2147483621, -2147483647, 1.1, 3.4e38,
        2^126 * (2 - 2^-23), 2^-140, Inf, -Inf, NaN, NA_real_, -0, c(0, -0), 1e308,
        unclass(tagged_missing("a")), unclass(tagged_missing("z")),
        bits(0x7ff80000L, 1954L), bits(-0x00100000L, 1954L),
        bits(0x7ff00000L, 1955L), bits(0x7ff8007bL, 1954L), bits(0x7ff00041L, 1954L),
        c(1, NaN), c(NA, 1.5)
    )
    for (values in cases) {
        for (kind in 0:4) {
            constructed <- tryCatch(
                .construct_dta_numeric(values, NULL, .dta_storage[[kind + 1L]]),
                error = function(condition) NULL)
            kept <- !is.null(constructed) &&
                identical(raw_values(constructed), raw_values(values))
            expect_identical(.Call(C_dtatools_numeric_values_kept, values, kind), kept)
        }
    }
})

test_that("a later summary expression reads a group result as cast", {
    skip_if_not_installed("dplyr", "1.2.1")
    unrounded <- .shared_uncast()
    data <- dibble(g = c(1, 2))
    summarised <- .shared_count(function()
        dplyr::summarise(data, f = unrounded, z = as.double(f), .by = g))
    expect_identical(summarised$hits, 0L)
    expect_identical(as.double(summarised$value$f), rep(as.double(dta_float(0.1)), 2))
    expect_identical(as.double(summarised$value$z), as.double(summarised$value$f))

    zero <- .shared_uncast(-0, "byte")
    summarised <- .shared_count(function()
        dplyr::summarise(data, f = zero, negative = 1 / as.double(f) < 0, .by = g))
    expect_identical(summarised$hits, 0L)
    expect_identical(as.logical(summarised$value$negative), c(FALSE, FALSE))
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
