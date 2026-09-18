test_that("keep_vars keeps physical order and resolves generated columns", {
    data <- dibble(a = 1:2, b = 3:4, c = 5:6)
    alias <- data
    gen(data, generated, a + b)

    result <- withVisible(keep_vars(data, generated, a))

    expect_false(result$visible)
    expect_identical(result$value, data)
    expect_named(data, c("a", "generated"))
    expect_named(alias, c("a", "generated"))
    expect_identical(as.double(data$generated), c(4, 6))
    expect_s3_class(data, "dtatools_ref_data")
})

test_that("drop_vars removes physical and generated columns", {
    data <- dibble(a = 1:2, b = 3:4, c = 5:6)
    alias <- data
    gen(data, generated, a + b)

    expect_invisible(drop_vars(data, b, generated))

    expect_named(data, c("a", "c"))
    expect_named(alias, c("a", "c"))
    expect_s3_class(data, "tbl_df")
    expect_true(is_dibble(data))
    expect_identical(as.integer(data$a), 1:2)
    expect_identical(as.integer(data$c), 5:6)
})

test_that("structural mutation does not alter shared names vectors", {
    data <- dibble(a = 1:2, b = 3:4, c = 5:6)
    name_alias <- names(data)
    other <- data.frame(x = 1:2, y = 3:4, z = 5:6)
    names(other) <- names(data)

    drop_vars(data, b)

    expect_identical(name_alias, c("a", "b", "c"))
    expect_named(other, c("a", "b", "c"))
    expect_named(data, c("a", "c"))
})

test_that("same-size selection materializes generated columns", {
    data <- dibble(a = 1:2, b = 3:4)
    gen(data, generated, a + b)

    drop_vars(data, b)

    expect_named(data, c("a", "generated"))
    expect_true(inherits(data, "dtatools_ref_data"))
    expect_identical(as.double(data$generated), c(4, 6))
    gen(data, later, generated + a)
    expect_identical(as.double(data$later), c(5, 8))
})

test_that("ALTREP data-frame wrappers support structural mutation", {
    data <- structure(
        lapply(1:100, function(index) index),
        names = sprintf("v%05d", 1:100),
        row.names = 1L,
        class = "data.frame"
    )
    data <- as_dibble(data)
    alias <- data

    drop_vars(data, v00100)

    expect_named(data, sprintf("v%05d", 1:99))
    expect_named(alias, sprintf("v%05d", 1:99))
    expect_identical(as.integer(data$v00099), 99L)
})

test_that("selection errors are atomic", {
    make_data <- function() {
        data <- dibble(a = 1, b = 2)
        gen(data, generated, a + b)
        data
    }

    for (operation in list(keep_vars, drop_vars)) {
        data <- make_data()
        before <- serialize(data, NULL)
        expect_error(operation(data, a, absent), "absent|doesn't exist")
        expect_identical(serialize(data, NULL), before)

        expect_error(
            operation(data, tidyselect::any_of(c("a", "absent"))),
            "all_of"
        )
        expect_identical(serialize(data, NULL), before)

        aof <- tidyselect::any_of
        expect_error(
            operation(data, aof(c("a", "absent"))),
            "all_of"
        )
        expect_identical(serialize(data, NULL), before)

        ns <- asNamespace("tidyselect")
        wrapped <- function(x) tidyselect::any_of(x)
        expect_error(
            operation(data, ns$any_of(c("a", "absent"))),
            "all_of"
        )
        expect_error(
            operation(data, wrapped(c("a", "absent"))),
            "all_of"
        )
        expect_error(
            operation(data, tidyselect:::any_of(c("a", "absent"))),
            "all_of"
        )
        expect_error(
            operation(
                data,
                do.call(tidyselect::any_of, list(c("a", "absent")))
            ),
            "all_of"
        )
        expect_error(
            operation(
                data,
                tidyselect::all_of(
                    do.call(tidyselect::any_of, list(c("a", "absent")))
                )
            ),
            "all_of.*character vector"
        )
        expect_identical(serialize(data, NULL), before)

        expect_error(
            operation(data, tidyselect::all_of(character())),
            "at least one"
        )
        expect_identical(serialize(data, NULL), before)
    }
})

test_that("strict name selection supports ranges, c, and all_of", {
    data <- dibble(a = 1, b = 2, c = 3, d = 4)
    config <- list(requested = c("d", "a"))

    keep_vars(data, c(a:b), tidyselect::all_of(config$requested))

    expect_named(data, c("a", "b", "d"))

    all_of <- tidyselect::all_of
    data <- dibble(a = 1, b = 2, c = 3)
    keep_vars(data, all_of(c("c", "a")))
    expect_named(data, c("a", "c"))
})

test_that("multiple ranges resolve together", {
    data <- dibble(!!!setNames(as.list(1:8), letters[1:8]))

    keep_vars(data, c(a:b, d:e), g:h)

    expect_named(data, c("a", "b", "d", "e", "g", "h"))
})

test_that("all_of snapshots promises as character names before selection", {
    wrapper <- function(data, requested) {
        keep_vars(data, tidyselect::all_of(requested))
    }
    data <- dibble(a = 1, b = 2)
    before <- serialize(data, NULL)

    expect_error(
        wrapper(data, tidyselect::any_of(c("a", "absent"))),
        "all_of.*character vector|selection context|selecting function"
    )
    expect_identical(serialize(data, NULL), before)
    expect_error(wrapper(data, 1L), "all_of.*character vector")
    expect_identical(serialize(data, NULL), before)

    all_of <- function(...) stop("custom helper ran")
    expect_error(keep_vars(data, all_of("a")), "custom helpers")
    expect_identical(serialize(data, NULL), before)
})

test_that("validated keep-all is a structural no-op", {
    data <- dibble(a = 1:2, b = 3:4, c = 5:6)
    alias <- data

    keep_vars(data, c, a:b)

    expect_identical(data, alias)
    expect_named(data, c("a", "b", "c"))
})

test_that("structural mutation uses values installed by repl", {
    data <- dibble(a = 1:3, b = 4:6)
    gen(data, generated, a + b)
    repl(data, a, 9L, where = 2)
    repl(data, generated, 20, where = 3)

    keep_vars(data, generated, a)

    expect_identical(as.integer(data$a), c(1L, 9L, 3L))
    expect_identical(as.double(data$generated), c(5, 7, 20))
    drop_vars(data, generated)
    expect_named(data, "a")
    repl(data, a, 7L, where = 1)
    expect_identical(as.integer(data$a), c(7L, 9L, 3L))
})

test_that("surviving columns keep Stata values and metadata", {
    values <- dta_byte(c(1, tagged_missing("a"), NA_real_))
    attr(values, "label") <- "Status"
    attr(values, "labels") <- c(Active = 1)
    data <- dibble(discard = 1:3, status = values)
    before <- serialize(data$status, NULL)

    keep_vars(data, status)

    expect_identical(serialize(data$status, NULL), before)
    expect_identical(dta_storage_type(data$status), "byte")
    expect_identical(missing_tag(data$status), c(NA, "a", NA))
    expect_identical(var_label(data$status), "Status")
    expect_identical(val_labels(data$status), dta_double(c(Active = 1)))
})

test_that("keep and drop support zero-row and zero-column results", {
    empty <- dibble(a = integer(), b = character())
    gen(empty, generated, numeric())
    keep_vars(empty, generated, a)
    expect_identical(dim(empty), c(0L, 2L))
    expect_named(empty, c("a", "generated"))

    drop_vars(empty, a, generated)
    expect_identical(dim(empty), c(0L, 0L))
    expect_identical(names(empty), character())
})

test_that("later reference mutations see a consistent overlay", {
    data <- dibble(a = 1:2, b = 3:4, c = 5:6)
    gen(data, first, a + b)
    gen(data, second, first + c)

    drop_vars(data, b, first)
    gen(data, third, a + second)
    repl(data, second, 99, where = 1)

    expect_named(data, c("a", "c", "second", "third"))
    expect_identical(as.double(data$second), c(99, 12))
    expect_identical(as.double(data$third), c(10, 14))
    expect_identical(as.integer(as.data.frame(data)$a), 1:2)
    expect_identical(names(copy_data(data)), names(data))

    restored <- unserialize(serialize(data, NULL))
    expect_identical(names(restored), names(data))
    expect_identical(as.data.frame(restored), as.data.frame(data))
})

test_that("keep_vars and drop_vars reject plain containers", {
    plain <- list(
        data.frame(a = 1:2, b = 3:4),
        tibble::tibble(a = 1:2, b = 3:4)
    )
    if (requireNamespace("data.table", quietly = TRUE)) {
        plain <- append(plain, list(data.table::data.table(a = 1:2, b = 3:4)))
    }
    for (data in plain) {
        expect_error(keep_vars(data, a), "must be a dibble")
        expect_error(drop_vars(data, b), "must be a dibble")
        expect_named(data, c("a", "b"))
    }
})
