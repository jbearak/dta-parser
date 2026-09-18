test_that("egen, gen and := agree without filters and distinguish filtered inputs", {
    d <- dibble(household = c(1, 1, 2, 2), income = c(10, 100, 4, NA),
                eligible = c(TRUE, FALSE, TRUE, TRUE))
    egen(d, a = dta_total(income), by = household)
    gen(d, b = dta_total(income), by = household)
    d[, c := dta_total(income), by = household]
    expect_identical(d$a, d$b)
    expect_identical(d$a, d$c)
    egen(d, selected = dta_total(income), where = eligible, by = household)
    d[eligible, equivalent := dta_total(income[eligible]), by = household]
    gen(d, whole = dta_total(income), where = eligible, by = household)
    expect_identical(d$selected, d$equivalent)
    expect_equal(as.double(d$selected), c(10, NA, 4, 4))
    expect_equal(as.double(d$whole), c(110, NA, 4, 4))
    expect_error(egen(d, selected = dta_total(income)), "already exists")
    d[eligible, selected := 9]
    expect_equal(as.double(d$selected), c(9, NA, 9, 9))
})

test_that("egen reuses target capture and formula conventions", {
    d <- dibble(x = c(1, 2, 3), ok = c(TRUE, FALSE, TRUE))
    name <- "positional"
    egen(d, !!name, dta_mean(x))
    egen(d, "literal", dta_mean(x))
    name <- "dynamic"
    egen(d, .(name) := dta_mean(x))
    cols <- c("x", "ok")
    egen(d, row_sum = dta_row_total(!!!rlang::syms(cols)))
    stored <- ~dta_mean(x)
    selected <- ~ok
    egen(d, formula = stored, where = selected)
    egen(d, inline = ~dta_mean(x), ~ok)
    expect_equal(as.double(d$positional), rep(2, 3))
    expect_equal(as.double(d$literal), rep(2, 3))
    expect_equal(as.double(d$dynamic), rep(2, 3))
    expect_equal(as.double(d$row_sum), c(2, 2, 4))
    expect_equal(as.double(d$formula), c(2, NA, 2))
    expect_identical(d$formula, d$inline)
    expect_error(egen(d, bad = x ~ dta_mean(x)), "one-sided")
})

test_that("egen calls actual functions and supports namespace qualification", {
    d <- dibble(x = 1:3)
    helper <- dta_mean
    egen(d, alias = helper(x))
    egen(d, qualified = dtatools::dta_mean(x))
    egen(d, typed = dta_double(dta_mean(x)))
    egen(d, subset = dta_max(x[]))
    ext <- matrix(c(1, 2, 3), ncol = 1L)
    egen(d, matrix_column = dta_max(ext[, 1]))
    expect_equal(as.double(d$alias), rep(2, 3))
    expect_identical(d$alias, d$qualified)
    expect_identical(dta_storage_type(d$typed), "double")
    expect_equal(as.double(d$subset), rep(3, 3))
    expect_equal(as.double(d$matrix_column), rep(3, 3))
    expect_error(egen(d, bad = mean(x)), "requires a value call")
    expect_error(egen(d, bad = sum(x)), "requires a value call")
    expect_false("bad" %in% names(d))
})

test_that("egen type, placement and row positions validate before mutation", {
    d <- dibble(g = c(1, 1, 2, 2), x = c(1, 9, 3, 8))
    alias <- d
    egen(d, y = dta_total(x), by = g, rows = 1, type = "long", before = x)
    expect_identical(names(alias), c("g", "y", "x"))
    expect_identical(dta_storage_type(d$y), "long")
    expect_equal(as.double(d$y), c(1, NA, 3, NA))
    egen(d, z = dta_mean(x), after = "g")
    expect_identical(names(d), c("g", "z", "y", "x"))
    before <- as.data.frame(copy_data(d))
    expect_error(egen(d, bad = dta_mean(x), before = g, after = x), "either")
    expect_error(egen(d, bad = dta_mean(x), before = absent), "does not exist")
    expect_error(egen(d, bad = dta_mean(x), rows = c(1, 1)), "unique")
    expect_error(egen(d, bad = dta_mean(x), rows = 5), "beyond")
    expect_error(egen(d, bad = dta_mean(x), type = "str1"), "type")
    expect_error(egen(d, bad = dta_total(x * 100), type = "byte"),
                 "Stata byte storage cannot represent")
    expect_identical(as.data.frame(d), before)
})

test_that("egen uses Stata key identity and does not reorder for by", {
    d <- dibble(g = c(tagged_missing("b"), 1, NA, tagged_missing("a"), 1),
                x = c(5, 1, 7, 9, 3))
    before <- as.double(d$g)
    egen(d, y = dta_total(x), by = g)
    expect_identical(as.double(d$g), before)
    expect_equal(as.double(d$y), c(5, 4, 7, 9, 4))
    untyped <- dibble(g = before, x = c(5, 1, 7, 9, 3))
    egen(untyped, y = dta_total(x), by = g)
    expect_equal(as.double(untyped$y), c(5, 4, 7, 9, 4))
})

test_that("egen stages bysort and commits only after success", {
    d <- dibble(g = c(2, 1, 2, 1), x = c(8, 9, 3, 1))
    alias <- d
    old <- as.data.frame(copy_data(d))
    expect_error(egen(d, y = dta_total(x * 100), bysort = g, type = "byte"),
                 "Stata byte storage cannot represent")
    expect_identical(as.data.frame(d), old)
    egen(d, y = dta_total(x), bysort = g)
    expect_equal(as.double(alias$g), c(1, 1, 2, 2))
    expect_equal(as.double(alias$x), c(9, 1, 8, 3))
    expect_equal(as.double(alias$y), c(10, 10, 11, 11))
    expect_error(egen(d, bad = dta_mean(x), by = g, bysort = g), "either")
    expect_error(egen(d, bad = dta_mean(x), by = c(g, g)), "unique")
    expect_error(egen(d, bad = dta_mean(x), by = absent), "does not exist")
})

test_that("egen shares gen()'s group plan: factor keys, empty dplyr groups, zero rows", {
    # Any vctrs-orderable key groups, as it does for gen().
    d <- dibble(f = factor(c("b", "a", "b")), x = c(1, 2, 3))
    egen(d, total = dta_total(x), by = f)
    expect_equal(as.double(d$total), c(4, 2, 4))
    gen(d, total_gen = sum(x), by = f)
    expect_identical(as.double(d$total_gen), as.double(d$total))
    egen(d, sorted_total = dta_total(x), bysort = f)
    expect_identical(as.character(d$f), c("a", "b", "b"))
    expect_equal(as.double(d$sorted_total), c(2, 4, 4))

    # `.drop = FALSE` grouping records an empty group; it admits nothing.
    factor_grouped <- as_dibble(.group_fixture("factor_unused")$data)
    egen(factor_grouped, n = dta_total(rep(1, .N)))
    expect_equal(as.double(factor_grouped$n), c(2, 2))

    # A grouped read of a dataset with no rows still types the result.
    empty <- dibble(g = numeric(), x = numeric())
    egen(empty, m = dta_mean(x), by = g)
    expect_identical(nrow(empty), 0L)
    expect_true("m" %in% names(empty))
})

test_that("egen grouped inputs supply groups and counters describe the sample", {
    d <- as_dibble(.group_fixture("g_1122_double_x_typed")$data)
    egen(d, y = dta_total(x), where = .n == 1)
    expect_equal(as.double(d$y), c(1, NA, 3, NA))
    egen(d, size = dta_total(rep(1, .N)), where = .n == 1)
    expect_equal(as.double(d$size), c(1, NA, 1, NA))
    expect_identical(setdiff(names(attr(d, "groups", exact = TRUE)), ".rows"), "g")
    expect_error(egen(d, bad = dta_mean(x), by = g), "already grouped")
    expect_error(egen(d, bad = dta_group_id(g)), "does not allow outer")
})

test_that("egen tag fills excluded rows with zero and forces byte", {
    d <- dibble(g = c(1, 1, 2, 2, NA), ok = c(FALSE, TRUE, TRUE, TRUE, TRUE))
    egen(d, tag = dta_group_tag(g), where = ok, type = "double")
    expect_equal(as.double(d$tag), c(0, 1, 1, 0, 0))
    expect_identical(dta_storage_type(d$tag), "byte")
    expect_identical(var_label(d$tag), "tag(g)")
    egen(d, id = dta_group_id(g, label = TRUE), where = ok)
    expect_equal(as.double(d$id), c(NA, 1, 2, 2, NA))
    expect_true(length(val_labels(d$id)) == 2L)
    egen(d, wrapped = dta_double(dta_group_id(g, label = TRUE)), where = ok)
    expect_identical(val_labels(d$wrapped), val_labels(d$id))
    expect_identical(var_label(d$wrapped), var_label(d$id))
    expect_identical(dta_storage_type(d$wrapped), "double")
    expect_error(egen(d, bad = dta_group_tag(g), by = g), "does not allow")
    expect_error(egen(d, bad = dta_row_max(g), by = g), "does not allow")
})

test_that("egen does not evaluate values separately for each admitted row", {
    d <- dibble(g = c(1, 1, 2, 2), x = 1:4, ok = c(TRUE, FALSE, TRUE, TRUE))
    seen <- list()
    record <- function(x) {
        seen[[length(seen) + 1L]] <<- as.double(x)
        x
    }
    egen(d, y = dta_total(record(x)), by = g, where = ok)
    expect_identical(seen, list(1, c(3, 4)))
    expect_equal(as.double(d$y), c(1, NA, 7, 7))
})

test_that("egen validates source NaN and normalizes arithmetic NaN", {
    d <- dibble(x = c(0, 1))
    egen(d, y = dta_mean(x / x))
    expect_equal(as.double(d$y), c(1, 1))
    egen(d, extracted = dta_total((x / x)[[1]]))
    expect_equal(as.double(d$extracted), c(0, 0))
    # dibble() refuses NaN on construction; plant it behind the class to
    # reach egen's own source validation.
    invalid <- unclass(dibble(x = c(0, 1)))
    invalid$x <- c(NaN, 1)
    class(invalid) <- class(d)
    expect_error(egen(invalid, y = dta_mean(x)), "NaN")
    expect_identical(names(invalid), "x")
    # A group key is a source too, read or not by the calculation. (A
    # grouped tibble with such a key is refused at the door by every
    # by-reference command, so only `by` and `bysort` reach this check.)
    keyed <- unclass(dibble(k = c(1, 2, 1, 3), x = c(1, 2, 3, 4)))
    keyed$k <- c(1, NaN, 1, Inf)
    class(keyed) <- class(d)
    expect_error(egen(keyed, m = dta_mean(x), by = k), "NaN")
    expect_error(egen(keyed, m = dta_mean(x), bysort = k), "NaN")
    expect_identical(as.double(keyed$x), c(1, 2, 3, 4))
    expect_identical(names(keyed), c("k", "x"))
    # ... whatever the key's class: a class the calculations do not take
    # still groups, so its payload is checked directly.
    plant <- function(key) {
        planted <- unclass(dibble(k = c(1, 2, 1, 3), x = c(1, 2, 3, 4)))
        planted$k <- key
        class(planted) <- class(d)
        planted
    }
    expect_error(egen(plant(I(c(1, NaN, 1, 2))), m = dta_mean(x), by = k),
                 "NaN")
    wrapped <- plant(I(c(1, Inf, 1, 2)))
    expect_error(egen(wrapped, m = dta_mean(x), bysort = k), "infinities")
    expect_identical(as.double(wrapped$x), c(1, 2, 3, 4))
    # A matrix key groups by its rows, and a complex key by its values;
    # both are checked by payload.
    expect_error(egen(plant(matrix(c(1, NaN, 1, 2), 4)), m = dta_mean(x), by = k),
                 "NaN")
    expect_error(egen(plant(complex(real = c(1, Inf, 1, 2), imaginary = 0)),
                      m = dta_mean(x), bysort = k), "infinities")
    fine <- plant(complex(real = c(1, 2, 1, 2), imaginary = 0))
    egen(fine, m = dta_mean(x), by = k)
    expect_identical(as.double(fine$m), c(2, 3, 2, 3))
    skip_if_not_installed("bit64")
    # An integer64 key groups by its values, whatever their bit patterns
    # read as when taken for doubles.
    big <- plant(bit64::as.integer64(c("9221120237041090560", "1",
                                       "9221120237041090560", "2")))
    egen(big, m = dta_mean(x), by = k)
    expect_identical(as.double(big$m), c(2, 2, 2, 4))
    raw <- NaN
    expect_error(egen(d, bad = dta_mean(raw)), "NaN")
    expect_error(egen(d, bad = dta_mean(.env$raw)), "NaN")
    expect_error(egen(d, bad = dta_mean(.env[["raw"]])), "NaN")
    holder <- list(value = NaN)
    expect_error(egen(d, bad = dta_mean(holder$value)), "NaN")
    expect_error(egen(d, bad = dta_mean(.env$holder$value)), "NaN")
    matrix_source <- matrix(NaN, 1, 1)
    expect_error(egen(d, bad = dta_mean(matrix_source[1])), "NaN")
    good <- 2
    calls <- 0L
    selector <- function() {
        calls <<- calls + 1L
        "good"
    }
    egen(d, external = dta_mean(.env[[selector()]]))
    expect_identical(calls, 1L)
    expect_equal(as.double(d$external), c(2, 2))
    expect_error(egen(d, bad = dta_mean(NaN)), "NaN")
    expect_false(dtatools:::.dta_egen_evaluation$allow_nan)
    expect_error(dta_mean(NaN), "NaN")
})

test_that("egen handles empty samples without inventing observations", {
    d <- dibble(x = 1:3, g = c(1, 1, 2))
    egen(d, y = dta_total(x), where = FALSE, by = g)
    egen(d, tag = dta_group_tag(g), where = FALSE)
    expect_equal(as.double(d$y), rep(NA_real_, 3))
    expect_equal(as.double(d$tag), rep(0, 3))
    empty <- dibble(x = numeric(), g = numeric())
    egen(empty, y = dta_mean(x), by = g)
    egen(empty, tag = dta_group_tag(g))
    expect_identical(as.double(empty$y), numeric())
    expect_identical(as.double(empty$tag), numeric())
})

test_that("egen preserves aliases and copy isolation through pipelines", {
    d <- dibble(x = 1:3)
    alias <- d
    isolated <- copy_data(d)
    d |> egen(y = dta_mean(x)) |> egen(z = dta_max(x))
    expect_identical(names(alias), c("x", "y", "z"))
    expect_identical(names(isolated), "x")
    expect_identical(dta_storage_type(d$y), "float")
    withr::local_options(dtatools.generate_type = "double")
    egen(d, double = dta_mean(x))
    expect_identical(dta_storage_type(d$double), "double")
})

test_that("egen rejects containers that are not dibbles", {
    expect_error(
        egen(data.frame(x = c(1, 2)), y = dta_total(x)),
        "must be a dibble"
    )
    expect_error(
        egen(tibble::tibble(x = c(1, 2)), y = dta_total(x)),
        "must be a dibble"
    )
    skip_if_not_installed("data.table")
    d <- data.table::data.table(g = c(2, 1), x = c(1, 2))
    data.table::setkeyv(d, "x")
    expect_error(egen(d, y = dta_total(x), by = g), "must be a dibble")
    expect_identical(names(d), c("g", "x"))
    expect_identical(data.table::key(d), "x")
})

test_that("egen grouped calculations leave compact source columns untouched", {
    d <- read_dta(fixture("auto_v118.dta"))
    price <- d$price
    unrelated <- d$weight
    price_address <- rlang::obj_address(price)
    unrelated_address <- rlang::obj_address(unrelated)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(price))
    egen(d, average = dta_mean(.data$price), by = foreign)
    expect_identical(rlang::obj_address(d$price), price_address)
    expect_identical(rlang::obj_address(d$weight), unrelated_address)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(price))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(unrelated))
    expected <- ave(as.double(price), as.double(d$foreign), FUN = mean)
    expect_equal(as.double(d$average), as.double(dta_float(expected)))
})

test_that("egen calculations read private views, so a retained column cannot alias the dataset", {
    data <- dibble(x = dta_double(c(1, 2, 3)))
    escaped <- NULL
    keep <- function(value) { escaped <<- value; value }
    egen(data, total = dta_total(keep(x)))
    expect_identical(as.double(data$total), c(6, 6, 6))
    expect_false(is.null(escaped))
    expect_identical(as.double(escaped), c(1, 2, 3))
    # The retained handle is a view, not the column's own vector: a later
    # write reaches the dataset and leaves the retained value alone.
    expect_false(identical(rlang::obj_address(escaped), rlang::obj_address(.subset2(data, "x"))))
    replace_values(data, x, 9, where = 1L)
    expect_identical(as.double(data$x), c(9, 2, 3))
    expect_identical(as.double(escaped), c(1, 2, 3))
})

test_that("egen growth rebuilds its view on the new table and keeps aliases on the old one", {
    withr::local_options(dtatools.auto_grow = TRUE)
    data <- dibble(x = dta_double(c(1, 2)))
    data <- reserve_columns(data, n = 0L)
    alias <- data
    expect_false(can_add_columns(data))
    expect_warning(result <- egen(data, y = dta_total(x)), "isolated table")
    expect_true(is_dibble(result))
    expect_identical(names(result), c("x", "y"))
    expect_identical(as.double(result$y), c(3, 3))
    expect_identical(names(alias), "x")
})

