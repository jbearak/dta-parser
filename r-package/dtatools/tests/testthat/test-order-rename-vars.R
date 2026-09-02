overlay_table <- function(names_out = FALSE) {
    path <- withr::local_tempfile(fileext = ".dta", .local_envir = parent.frame())
    save_dta(
        data.frame(id = stata_int(1:5), v = stata_int(1:5), w = stata_int(6:10)),
        path
    )
    read_dta(path, encoding = "UTF-8", output = "tibble")
}

nums <- function(x) as.double(vctrs::vec_data(x))

test_that("order_vars moves selected columns to the front", {
    data <- data.frame(a = 1:3, b = 4:6, c = 7:9)
    expect_identical(order_vars(data, c, a), invisible(data))
    expect_identical(names(data), c("c", "a", "b"))
    expect_identical(data$c, 7:9)
})

test_that("order_vars permutes a tibble and a data.table by reference", {
    table <- tibble::tibble(a = 1:3, b = 4:6, c = 7:9)
    alias <- table
    order_vars(table, c, b, a)
    expect_identical(names(table), c("c", "b", "a"))
    expect_identical(names(alias), c("c", "b", "a"))
    expect_true(tibble::is_tibble(table))
    expect_identical(table$a, 1:3)

    stata_table <- data.table::data.table(a = 1:3, b = 4:6, c = 7:9)
    order_vars(stata_table, b)
    expect_identical(names(stata_table), c("b", "a", "c"))
    expect_true(data.table::is.data.table(stata_table))
})

test_that("order_vars leaves an unchanged order alone", {
    table <- tibble::tibble(a = 1:3, b = 4:6)
    order_vars(table, a)
    expect_identical(names(table), c("a", "b"))
})

test_that("order_vars moves generated columns alongside physical ones", {
    data <- overlay_table()
    gen(data, doubled, v * 2)
    gen(data, tripled, v * 3)
    alias <- data
    order_vars(data, tripled, id)
    expect_identical(names(data), c("tripled", "id", "v", "w", "doubled"))
    expect_identical(names(alias), names(data))
    expect_identical(nums(data$tripled), c(3, 6, 9, 12, 15))
    expect_identical(nums(data$v), c(1, 2, 3, 4, 5))
    gen(data, more, v + 1)
    expect_identical(
        names(data), c("tripled", "id", "v", "w", "doubled", "more")
    )
})

test_that("order_vars keeps compact columns unmaterialized", {
    data <- overlay_table()
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data[["v"]]))
    order_vars(data, v)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data[["v"]]))
    expect_identical(names(data), c("v", "id", "w"))
})

test_that("order_vars permutes a structural reference state", {
    data <- overlay_table()
    gen(data, first_generated, v + 1)
    gen(data, second_generated, v + 2)
    drop_vars(data, id)
    order_vars(data, second_generated, v)
    expect_identical(
        names(data), c("second_generated", "v", "w", "first_generated")
    )
    expect_identical(nums(data$second_generated), c(3, 4, 5, 6, 7))
})

test_that("order_vars rejects absent and empty selections", {
    data <- data.frame(a = 1:2, b = 3:4)
    expect_error(order_vars(data, absent))
    expect_error(order_vars(data))
})

test_that("rename_vars renames by reference", {
    data <- data.frame(id = 1:3, v1 = 4:6, v2 = 7:9)
    expect_identical(rename_vars(data, age_years = v1), invisible(data))
    expect_identical(names(data), c("id", "age_years", "v2"))
    expect_identical(data$age_years, 4:6)

    table <- tibble::tibble(a = 1:3, b = 4:6)
    alias <- table
    rename_vars(table, x = a, y = "b")
    expect_identical(names(table), c("x", "y"))
    expect_identical(names(alias), c("x", "y"))
    expect_true(tibble::is_tibble(table))
})

test_that("rename_vars accepts a permutation of existing names", {
    table <- tibble::tibble(a = 1:3, b = 4:6)
    rename_vars(table, b = a, a = b)
    expect_identical(names(table), c("b", "a"))
    expect_identical(table$b, 1:3)
})

test_that("rename_vars renames generated columns and keeps them writable", {
    data <- overlay_table()
    gen(data, doubled, v * 2)
    alias <- data
    rename_vars(data, wide_doubled = doubled, identifier = id)
    expect_identical(names(data), c("identifier", "v", "w", "wide_doubled"))
    expect_identical(names(alias), names(data))
    expect_identical(nums(data$wide_doubled), c(2, 4, 6, 8, 10))
    gen(data, extra, v + 1)
    expect_identical(
        names(data), c("identifier", "v", "w", "wide_doubled", "extra")
    )
})

test_that("rename_vars keeps compact columns and metadata", {
    data <- overlay_table()
    set_var_label(data, v, "a label")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data[["v"]]))
    rename_vars(data, value = v)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data[["value"]]))
    expect_identical(unname(var_label(data)[["value"]]), "a label")
})

test_that("rename_vars rejects malformed replacements", {
    data <- data.frame(id = 1:2, v1 = 3:4, v2 = 5:6)
    expect_error(rename_vars(data, x = absent))
    expect_error(rename_vars(data, v2 = id), "collides")
    expect_error(rename_vars(data, id), "new_name = old_name")
    expect_error(rename_vars(data), "at least one")
    expect_error(rename_vars(data, p = id, q = id), "only once")
})

test_that("rename_vars replaces every name through .names", {
    table <- tibble::tibble(a = 1:3, b = 4:6)
    alias <- table
    rename_vars(table, .names = c("x", "y"))
    expect_identical(names(table), c("x", "y"))
    expect_identical(names(alias), c("x", "y"))
    expect_identical(table$x, 1:3)

    data <- overlay_table()
    gen(data, doubled, v * 2)
    rename_vars(data, .names = toupper(names(data)))
    expect_identical(names(data), c("ID", "V", "W", "DOUBLED"))
    expect_identical(nums(data$DOUBLED), c(2, 4, 6, 8, 10))
    gen(data, extra, V + 1)
    expect_identical(names(data), c("ID", "V", "W", "DOUBLED", "extra"))
})

test_that("rename_vars rejects a malformed .names", {
    table <- tibble::tibble(a = 1:3, b = 4:6)
    expect_error(rename_vars(table, .names = "x"), "must give 2 names")
    expect_error(rename_vars(table, .names = c("x", "x")), "distinct")
    expect_error(rename_vars(table, .names = 1:2), "character vector")
    expect_error(rename_vars(table, x = a, .names = c("x", "y")), "not both")
})
