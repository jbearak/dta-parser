test_that("keep_vars keeps physical order and resolves generated columns", {
    data <- data.frame(a = 1:2, b = 3:4, c = 5:6)
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
    data <- tibble::tibble(a = 1:2, b = 3:4, c = 5:6)
    alias <- data
    gen(data, generated, a + b)

    expect_invisible(drop_vars(data, b, generated))

    expect_named(data, c("a", "c"))
    expect_named(alias, c("a", "c"))
    expect_s3_class(data, "tbl_df")
    expect_identical(data$a, 1:2)
    expect_identical(data$c, 5:6)
})

test_that("physical-only selection mutates ordinary data aliases", {
    data <- data.frame(a = 1:2, b = 3:4, c = 5:6)
    alias <- data
    kept_a <- data$a
    kept_c <- data$c

    drop_vars(data, b)

    expect_named(data, c("a", "c"))
    expect_named(alias, c("a", "c"))
    expect_identical(data$a, kept_a)
    expect_identical(data$c, kept_c)
})

test_that("structural mutation does not alter shared names vectors", {
    data <- data.frame(a = 1:2, b = 3:4, c = 5:6)
    name_alias <- names(data)
    other <- data.frame(x = 1:2, y = 3:4, z = 5:6)
    names(other) <- names(data)

    drop_vars(data, b)

    expect_identical(name_alias, c("a", "b", "c"))
    expect_named(other, c("a", "b", "c"))
    expect_named(data, c("a", "c"))
})

test_that("same-size selection materializes generated columns", {
    data <- data.frame(a = 1:2, b = 3:4)
    gen(data, generated, a + b)

    drop_vars(data, b)

    expect_named(data, c("a", "generated"))
    expect_false(inherits(data, "dtatools_ref_data"))
    expect_identical(as.double(data$generated), c(4, 6))
    gen(data, later, generated + a)
    expect_identical(as.double(data$later), c(5, 8))
})

test_that("ordinary gen keeps physical columns authoritative", {
    data <- data.frame(a = 1:3)
    gen(data, generated, a + 1L)

    repl(data, a, NA_integer_, where = 1)

    expect_identical(data$a, c(NA_integer_, 2L, 3L))
    expect_identical(unclass(data)[[1L]], data$a)
    expect_identical(complete.cases(data), c(FALSE, TRUE, TRUE))
})

test_that("legacy serialized reference state remains readable", {
    data <- data.frame(a = 1:2, b = 3:4)
    gen(data, generated, a + b)
    state <- attr(data, ".dtatools_ref_state", exact = TRUE)
    rm("physical_names", "physical_overlay", envir = state)
    data <- unserialize(serialize(data, NULL))

    expect_named(data, c("a", "b", "generated"))
    expect_identical(as.data.frame(data)$a, 1:2)
    repl(data, a, 9L, where = 1)
    expect_identical(data$a, c(9L, 2L))
})

test_that("ALTREP data-frame wrappers support structural mutation", {
    data <- structure(
        lapply(1:100, function(index) index),
        names = sprintf("v%05d", 1:100),
        row.names = 1L,
        class = "data.frame"
    )
    alias <- data

    drop_vars(data, v00100)

    expect_named(data, sprintf("v%05d", 1:99))
    expect_named(alias, sprintf("v%05d", 1:99))
    expect_identical(data$v00099, 99L)
})

test_that("selection errors are atomic", {
    make_data <- function() {
        data <- data.frame(a = 1, b = 2)
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
    data <- data.frame(a = 1, b = 2, c = 3, d = 4)
    config <- list(requested = c("d", "a"))

    keep_vars(data, c(a:b), tidyselect::all_of(config$requested))

    expect_named(data, c("a", "b", "d"))

    all_of <- tidyselect::all_of
    data <- data.frame(a = 1, b = 2, c = 3)
    keep_vars(data, all_of(c("c", "a")))
    expect_named(data, c("a", "c"))
})

test_that("multiple ranges resolve together", {
    data <- as.data.frame(setNames(as.list(1:8), letters[1:8]))

    keep_vars(data, c(a:b, d:e), g:h)

    expect_named(data, c("a", "b", "d", "e", "g", "h"))
})

test_that("all_of snapshots promises as character names before selection", {
    wrapper <- function(data, requested) {
        keep_vars(data, tidyselect::all_of(requested))
    }
    data <- data.frame(a = 1, b = 2)
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

test_that("data.table materialization clears keys and indexes", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(a = 1:2, b = 3:4, c = 5:6)
    data.table::setkeyv(data, "a")
    data.table::setindexv(data, "b")
    gen(data, generated, a + c)

    drop_vars(data, a, b)

    expect_false(inherits(data, "dtatools_ref_data"))
    expect_named(data, c("c", "generated"))
    expect_null(data.table::key(data))
    expect_length(data.table::indices(data), 0L)
    data.table::set(
        data,
        j = "later",
        value = data$c + data$generated
    )
    expect_identical(as.double(data$later), c(11, 14))
})

test_that("validated keep-all is a structural no-op", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(a = 1:2, b = 3:4, c = 5:6)
    data.table::setkeyv(data, "a")
    data.table::setindexv(data, "b")
    alias <- data

    keep_vars(data, c, a:b)

    expect_identical(data, alias)
    expect_identical(data.table::key(data), "a")
    expect_identical(data.table::indices(data), "b")
})

test_that("non-resizable data.tables fail before mutation", {
    skip_if_not_installed("data.table")
    data <- unserialize(serialize(
        data.table::data.table(a = 1:2, b = 3:4),
        NULL
    ))
    before <- serialize(data, NULL)

    expect_error(drop_vars(data, b), "non-resizable data.table")

    expect_identical(serialize(data, NULL), before)

    expect_error(drop_vars(data, a, b), "non-resizable data.table")

    expect_identical(serialize(data, NULL), before)
})

test_that("structural mutation uses values installed by repl", {
    data <- data.frame(a = 1:3, b = 4:6)
    gen(data, generated, a + b)
    repl(data, a, 9L, where = 2)
    repl(data, generated, 20, where = 3)

    keep_vars(data, generated, a)

    expect_identical(data$a, c(1L, 9L, 3L))
    expect_identical(as.double(data$generated), c(5, 7, 20))
    drop_vars(data, generated)
    expect_named(data, "a")
    repl(data, a, 7L, where = 1)
    expect_identical(data$a, c(7L, 9L, 3L))
})

test_that("surviving columns keep Stata values and metadata", {
    values <- stata_byte(c(1, tagged_missing("a"), NA_real_))
    attr(values, "label") <- "Status"
    attr(values, "labels") <- c(Active = 1)
    data <- data.frame(discard = 1:3, status = values)
    before <- serialize(data$status, NULL)

    keep_vars(data, status)

    expect_identical(serialize(data$status, NULL), before)
    expect_identical(stata_storage_type(data$status), "byte")
    expect_identical(missing_tag(data$status), c(NA, "a", NA))
    expect_identical(var_label(data$status), "Status")
    expect_identical(val_labels(data$status), c(Active = 1))
})

test_that("keep and drop support zero-row and zero-column results", {
    empty <- data.frame(a = integer(), b = character())
    gen(empty, generated, numeric())
    keep_vars(empty, generated, a)
    expect_identical(dim(empty), c(0L, 2L))
    expect_named(empty, c("a", "generated"))

    drop_vars(empty, a, generated)
    expect_identical(dim(empty), c(0L, 0L))
    expect_identical(names(empty), character())
})

test_that("later reference mutations see a consistent overlay", {
    data <- data.frame(a = 1:2, b = 3:4, c = 5:6)
    gen(data, first, a + b)
    gen(data, second, first + c)

    drop_vars(data, b, first)
    gen(data, third, a + second)
    repl(data, second, 99, where = 1)

    expect_named(data, c("a", "c", "second", "third"))
    expect_identical(as.double(data$second), c(99, 12))
    expect_identical(as.double(data$third), c(10, 14))
    expect_identical(as.data.frame(data)$a, 1:2)
    expect_identical(names(copy_data(data)), names(data))

    restored <- unserialize(serialize(data, NULL))
    expect_identical(names(restored), names(data))
    expect_identical(as.data.frame(restored), as.data.frame(data))
})

test_that("renaming a data.table carries its key and indexes over", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(a = 1:2, b = 3:4, c = 5:6)
    data.table::setkeyv(data, "a")
    data.table::setindexv(data, "b")
    data.table::setindexv(data, c("b", "c"))

    rename_vars(data, x = a, y = b)

    expect_named(data, c("x", "y", "c"))
    expect_identical(data.table::key(data), "x")
    expect_identical(
        data.table::indices(data, vectors = TRUE),
        list("y", c("y", "c"))
    )
})

test_that("renaming every data.table column carries its key over", {
    skip_if_not_installed("data.table")
    data <- data.table::data.table(a = 1:2, b = 3:4)
    data.table::setkeyv(data, "a")
    data.table::setindexv(data, "b")

    rename_vars(data, .names = c("first", "second"))

    expect_identical(data.table::key(data), "first")
    expect_identical(data.table::indices(data), "second")
})
