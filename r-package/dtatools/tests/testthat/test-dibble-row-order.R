# Stage 6 row-operation regression coverage; adapted sources are in inst/NOTICE.
# Adapted policy cases: dplyr 95740975 test-arrange.R and test-distinct.R.

test_that("S6-O01 arrange keys are independent and see original ungrouped columns", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dplyr::group_by(dibble(id = 1:4, g = c("b", "a", "b", "a"),
        x = c(2, 1, 2, 1)), g)
    sizes <- integer()
    out <- dplyr::arrange(data, { sizes <<- c(sizes, dplyr::n()); x })
    expect_identical(sizes, 4L)
    expect_identical(.s6_ids(out), c(2L, 4L, 1L, 3L))
    expect_identical(dplyr::group_vars(out), "g")
    expect_identical(as.list(dplyr::group_rows(out)), list(1:2, 3:4))
    data <- dibble(id = 1:3, x = c(2, 1, 3))
    # Named keys are sorting expressions, not sequential column assignments.
    expect_identical(.s6_ids(dplyr::arrange(data, x = 0, x)), c(2L, 1L, 3L))
    expect_identical(.s6_ids(dplyr::arrange(data, NULL, dplyr::pick(x))), c(2L, 1L, 3L))
    expect_identical(.s6_ids(dplyr::arrange(data, TRUE, dplyr::pick(x))), c(2L, 1L, 3L))
    expect_identical(.s6_ids(dplyr::arrange(data)), 1:3)
    expect_error(dplyr::arrange(data, 1:2), "size")
    expect_error(dplyr::arrange(data, dplyr::desc(x, x)))
})

test_that("S6-O02 arrange flattens pick/across keys and applies stable directions", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:4, x = c(1, 3, 2, 1), y = c(4, 3, 2, 1))
    expect_identical(.s6_ids(dplyr::arrange(data, dplyr::pick(x, y))), c(4L, 1L, 3L, 2L))
    expect_identical(.s6_ids(dplyr::arrange(data, dplyr::across(c(x, y), dplyr::desc))),
                     c(2L, 3L, 1L, 4L))
    data <- dibble(id = 1:4, x = c(1, 1, 1, 1), y = c(2, 2, 1, 2))
    expect_identical(.s6_ids(dplyr::arrange(data, x, y)), c(3L, 1L, 2L, 4L))
    grouped <- dplyr::group_by(dibble(id = 1:4, g = c("b", "a", "b", "a"),
        x = c(1, 4, 2, 3)), g)
    expect_identical(.s6_ids(dplyr::arrange(grouped, x)), c(1L, 3L, 4L, 2L))
    expect_identical(.s6_ids(dplyr::arrange(grouped, x, .by_group = TRUE)), c(4L, 2L, 1L, 3L))
})

test_that("S6-O03 arrange uses explicit C collation and validates locale", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:4, x = c("A", "a", "b", "B"))
    expect_identical(.s6_ids(dplyr::arrange(data, x, .locale = "C")), c(1L, 4L, 2L, 3L))
    expect_identical(.s6_ids(dplyr::arrange(data, dplyr::desc(x), .locale = "C")),
                     c(3L, 2L, 4L, 1L))
    expect_error(dplyr::arrange(data, x, .locale = 1))
    expect_error(dplyr::arrange(data, x, .locale = c("C", "en")))
})

test_that("S6-O04 arrange supports optional ICU collation", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("stringi", "1.5.3")
    data <- dibble(id = 1:4, x = c("A", "a", "b", "B"))
    expect_identical(.s6_ids(dplyr::arrange(data, x, .locale = "en")), c(2L, 1L, 3L, 4L))
})

test_that("S6-D01 distinct types each computed key before a dependent key", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:3, g = c("b", "a", "b"))
    sizes <- integer()
    out <- dplyr::distinct(dplyr::group_by(data, g),
        s = { sizes <<- c(sizes, dplyr::n()); c(NA_character_, "", "a") },
        blank = s == "", .keep_all = TRUE)
    expect_identical(sizes, 3L)
    expect_identical(as.character(out$s), c("", "", "a"))
    expect_identical(out$blank, c(TRUE, TRUE, FALSE))
    expect_type(out$s, "character")
    expect_identical(dta_storage_type(out$s), "str1")
    # Stata numeric missing is ordered above finite values before the next key.
    numeric <- dplyr::distinct(data, z = c(NA_real_, 1, 1), high = z > 0)
    expect_identical(numeric$high, c(TRUE, TRUE))
    expect_s3_class(numeric$z, "dta_numeric")
})

test_that("S6-D02 distinct keeps first rows and only prepends missing group keys", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:4, g = c("b", "a", "b", "a"), x = c(1, 2, 1, 2))
    grouped <- dplyr::group_by(data, g)
    expect_identical(names(dplyr::distinct(grouped, x)), c("g", "x"))
    expect_identical(names(dplyr::distinct(grouped, x, g)), c("x", "g"))
    expect_identical(names(dplyr::distinct(data, x, x)), "x")
    out <- dplyr::distinct(grouped, x, .keep_all = TRUE)
    expect_identical(.s6_ids(out), 1:2)
    expect_identical(as.list(dplyr::group_rows(out)), list(2L, 1L))
    expect_error(dplyr::distinct(data, absent), "absent")
    expect_identical(names(data), c("id", "g", "x"))
})

test_that("S6-D03 distinct handles list keys and zero-column row counts", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:4, key = list(1:2, NULL, 1:2, NULL))
    expect_identical(.s6_ids(dplyr::distinct(data, key, .keep_all = TRUE)), 1:2)
    for (n in c(0L, 3L)) {
        empty <- as_dibble(tibble::new_tibble(list(), nrow = n))
        expect_identical(nrow(dplyr::distinct(empty)), if (n) 1L else 0L)
        expect_identical(ncol(dplyr::distinct(empty)), 0L)
    }
})

test_that("S6-D04 computed grouping keys rebuild before subsequent group operations", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dplyr::group_by(dibble(id = 1:2, g = c("a", "b")), g)
    out <- dplyr::distinct(data, g = "z", .keep_all = TRUE)
    expect_identical(.s6_ids(out), 1L)
    expect_identical(as.character(dplyr::group_keys(out)$g), "z")
    expect_identical(as.list(dplyr::group_rows(out)), list(1L))
    out <- dplyr::distinct(data, g = c("z", "z"), id)
    expect_identical(as.character(dplyr::group_keys(out)$g), "z")
    expect_identical(as.list(dplyr::group_rows(out)), list(1:2))
    expect_identical(.s6_ids(dplyr::filter(out, dplyr::n() == 2L)), 1:2)
    expect_identical(as.character(data$g), c("a", "b"))
})

test_that("S6-D05 caller symbols are typed while data columns retain precedence", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(x = 1:2)
    caller <- new.env(parent = environment())
    caller$data <- data
    caller$calls <- 0L
    makeActiveBinding("strings", function() {
        caller$calls <- caller$calls + 1L
        c(NA_character_, "")
    }, caller)
    out <- evalq(dplyr::distinct(data, strings), caller)
    expect_identical(caller$calls, 1L)
    expect_identical(names(out), "strings")
    expect_identical(as.character(out$strings), "")
    expect_identical(dta_storage_type(out$strings), "str1")
    makeActiveBinding("x", function() stop("caller x must stay unforced"), caller)
    out <- evalq(dplyr::distinct(data, x), caller)
    expect_identical(as.integer(out$x), 1:2)
    expect_identical(names(data), "x")
    expect_identical(as.integer(data$x), 1:2)
})

test_that("S6-O07 arrange expands pick before each independent key", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:2, x = 2:1)
    events <- list()
    out <- dplyr::arrange(data, {
        events[[length(events) + 1L]] <<- c("body", dplyr::n(), dplyr::cur_group_id())
        dplyr::pick(tidyselect::where(function(column) {
            events[[length(events) + 1L]] <<- c("selector", dplyr::n(), dplyr::cur_group_id())
            identical(as.integer(column), 2:1)
        }))
    })
    expect_identical(events, list(c("selector", "0", "0"),
        c("selector", "0", "0"), c("body", "2", "1")))
    expect_identical(.s6_ids(out), 2:1)
})

test_that("S6-O05 typed ordering and equality retain tagged missing identity", {
    skip_if_not_installed("dplyr", "1.2.1")
    constructors <- list(dta_byte, dta_int, dta_long, dta_float, dta_double)
    for (constructor in constructors) {
        key <- constructor(c(2, NA_real_, tagged_missing("a"), 1, tagged_missing("a")))
        data <- dibble(id = 1:5, key = key)
        ordered <- dplyr::arrange(data, key)
        expect_identical(.s6_ids(ordered), c(4L, 1L, 2L, 3L, 5L))
        expect_identical(class(ordered$key), class(data$key))
        expect_identical(.s6_ids(dplyr::distinct(data, key, .keep_all = TRUE)), 1:4)
    }
})

test_that("S6-O06 legacy collation and nested proxy directions retain stable locations", {
    skip_if_not_installed("dplyr", "1.2.1")
    withr::local_locale(c(LC_COLLATE = "C"))
    withr::local_options(dplyr.legacy_locale = TRUE, lifecycle_verbosity = "warning")
    data <- dibble(id = 1:4, x = c("b", "A", "a", "A"))
    expect_warning(out <- dplyr::arrange(data, x), "dplyr[.]legacy_locale")
    expect_identical(.s6_ids(out), c(2L, 4L, 3L, 1L))
    expect_warning(out <- dplyr::arrange(data, dplyr::desc(x)), "dplyr[.]legacy_locale")
    expect_identical(.s6_ids(out), c(1L, 3L, 2L, 4L))
    nested <- dibble(id = 1:4, key = tibble::tibble(a = c(1, 1, 2, 1),
        b = tibble::tibble(c = c("b", "a", "a", "a"))))
    for (legacy in c(FALSE, TRUE)) {
        options(dplyr.legacy_locale = legacy)
        expect_warning(out <- dplyr::arrange(nested, key), "dplyr[.]legacy_locale")
        expect_identical(.s6_ids(out), c(2L, 4L, 1L, 3L))
        expect_warning(out <- dplyr::arrange(nested, dplyr::desc(key)), "dplyr[.]legacy_locale")
        expect_identical(.s6_ids(out), c(3L, 1L, 2L, 4L))
    }
    factor_data <- dibble(id = 1:4,
        key = ordered(c("b", "a", "b", "c"), levels = c("c", "b", "a")))
    expect_warning(out <- dplyr::arrange(factor_data, key), "dplyr[.]legacy_locale")
    expect_identical(.s6_ids(out), c(4L, 1L, 3L, 2L))
    expect_warning(out <- dplyr::arrange(factor_data, key), "dplyr[.]legacy_locale")
    expect_identical(levels(out$key), c("c", "b", "a"))
})
