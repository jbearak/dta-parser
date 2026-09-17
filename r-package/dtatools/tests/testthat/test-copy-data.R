test_that("copy_data preserves dibble identity and independent reference writes", {
    original <- dibble(x = dta_byte(1:2))
    copied <- copy_data(original)
    alias <- copied

    expect_true(is_dibble(copied))
    expect_identical(class(copied), class(original))
    expect_identical(dta_storage_type(copied$x), "byte")

    mutate_copy <- function(data) {
        gen(data, y = 3)
        replace_values(data, x = 9, where = 1)
    }
    expect_silent(mutate_copy(copied))
    expect_identical(names(copied), c("x", "y"))
    expect_identical(names(alias), c("x", "y"))
    expect_identical(as.double(alias$x), c(9, 2))
    expect_identical(as.double(alias$y), c(3, 3))
    expect_identical(names(original), "x")
    expect_identical(as.double(original$x), c(1, 2))

    replace_values(original, x = 8, where = 2)
    expect_identical(as.double(copied$x), c(9, 2))
})

test_that("copied dibbles share explicit metadata writes with aliases, including zero rows", {
    for (n in c(2L, 0L)) {
        original <- dibble(x = seq_len(n))
        var_label(original$x) <- "Source"
        copied <- copy_data(original)
        alias <- copied

        expect_true(is_dibble(copied))
        expect_identical(class(copied), class(original))
        expect_identical(nrow(copied), n)

        mutate_copy <- function(data) {
            gen(data, y = 3)
            replace_values(data, x = 9L)
            set_var_label(data, x, "Copy")
        }
        expect_silent(mutate_copy(copied))
        expect_identical(names(alias), c("x", "y"))
        expect_identical(nrow(alias), n)
        expect_identical(as.integer(alias$x), rep(9L, n))
        expect_identical(as.double(alias$y), rep(3, n))
        expect_identical(var_label(alias$x), "Copy")
        expect_identical(var_label(copied$x), "Copy")
        expect_identical(var_label(original$x), "Source")
        expect_identical(names(original), "x")
        expect_identical(as.integer(original$x), seq_len(n))
    }
})

test_that("copy_data rejects ordinary containers and leaves them unchanged", {
    containers <- list(data.frame(x = 1:2), tibble::tibble(x = 1:2))
    if (requireNamespace("data.table", quietly = TRUE)) {
        containers <- c(containers, list(data.table::data.table(x = 1:2)))
    }
    for (original in containers) {
        before <- serialize(original, NULL)
        expect_error(copy_data(original), "must be a dibble")
        expect_identical(serialize(original, NULL), before)
        expect_false(inherits(original, "dtatools_ref_data"))
    }
})
