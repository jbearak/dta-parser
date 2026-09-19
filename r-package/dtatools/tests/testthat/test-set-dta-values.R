# set_dta_values() is the loop-friendly assigner: name or position, no
# tidy evaluation, one storage rule, by reference on a dibble. ADR 0043.

test_that("set_dta_values is exported with the documented signature", {
    expect_true("set_dta_values" %in% getNamespaceExports("dtatools"))
    expect_identical(names(formals(set_dta_values)),
                     c("data", "variable", "value", "rows", "create"))
})

test_that("set_dta_values writes by reference by name or position", {
    data <- dibble(id = 1:4, x = as.double(1:4), b = dta_byte(c(1, 1, 1, 1)))
    alias <- data
    expect_invisible(set_dta_values(data, "x", 9, rows = 2))
    expect_identical(as.double(data$x), c(1, 9, 3, 4))
    expect_identical(as.double(alias$x), c(1, 9, 3, 4))
    set_dta_values(data, 3, 5, rows = c(TRUE, FALSE, FALSE, TRUE))
    expect_identical(as.double(data$b), c(5, 1, 1, 5))
    expect_identical(dta_storage_type(data$b), "byte")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$b))
    # Every row, one value per selected row, and one value per data row.
    set_dta_values(data, "x", 0)
    expect_identical(as.double(data$x), c(0, 0, 0, 0))
    set_dta_values(data, "x", c(7, 8), rows = c(1, 4))
    expect_identical(as.double(data$x), c(7, 0, 0, 8))
    set_dta_values(data, "x", c(10, 20, 30, 40), rows = c(2, 3))
    expect_identical(as.double(data$x), c(7, 20, 30, 8))
    set_dta_values(data, "id", 99L, rows = 1)
    expect_identical(as.integer(data$id), c(99L, 2L, 3L, 4L))
    expect_identical(dta_storage_type(data$id), "long")
    expect_identical(names(data), c("id", "x", "b"))
})

test_that("set_dta_values keeps the declared storage and refuses what it cannot hold", {
    data <- dibble(b = dta_byte(c(1, 2, 3)), s = dta_string(c("a", "b", "c")))
    before <- as.data.frame(copy_data(data))
    expect_error(set_dta_values(data, "b", 1000, rows = 1), "cannot represent")
    expect_error(set_dta_values(data, "b", 1.5, rows = 1), "cannot represent")
    expect_error(set_dta_values(data, "s", "long", rows = 1), "str1")
    expect_error(set_dta_values(data, "b", NaN, rows = 1), "NaN")
    expect_identical(as.data.frame(data), before)
    expect_identical(dta_storage_type(data$b), "byte")
    # The same write through repl() promotes; the assigner never does.
    expect_message(repl(data, b = 1000, where = .n == 1), "byte now int")
    # Stata missing values fit every storage; character NA is "".
    set_dta_values(data, "b", tagged_missing("a"), rows = 2)
    expect_identical(dtatools:::.stata_missing_text(dtatools:::.tab_missing_codes(data$b))[[2L]], ".a")
    set_dta_values(data, "b", NA_real_, rows = 3)
    expect_true(is.na(as.double(data$b)[[3L]]))
    set_dta_values(data, "s", NA_character_, rows = 1)
    expect_identical(as.character(data$s), c("", "b", "c"))
    expect_identical(attr(data$s, "stata.string.storage"), "str1")
})

test_that("set_dta_values checks its arguments before writing", {
    data <- dibble(x = c(1, 2, 3))
    before <- as.data.frame(copy_data(data))
    expect_error(set_dta_values(data, "y", 1), "does not exist; pass `create = TRUE`")
    expect_error(set_dta_values(data, 2, 1), "one existing column name or position")
    expect_error(set_dta_values(data, 0, 1), "one existing column name or position")
    expect_error(set_dta_values(data, 1.5, 1), "one existing column name or position")
    expect_error(set_dta_values(data, c("x", "x"), 1), "one existing column name or position")
    expect_error(set_dta_values(data, NA_character_, 1), "one existing column name or position")
    expect_error(set_dta_values(data, "", 1), "one existing column name or position")
    expect_error(set_dta_values(data, "x", 1, create = NA), "`create`")
    expect_error(set_dta_values(data, "x", c(1, 2), rows = 1), "has size 2")
    expect_error(set_dta_values(data, "x", 1, rows = 4), "`rows` row positions")
    expect_error(set_dta_values(data, "x", 1, rows = c(TRUE, FALSE)), "`rows` has size 2")
    expect_error(set_dta_values(data, "x", 1, rows = "a"), "`rows` must yield")
    expect_error(set_dta_values(data.frame(x = 1), "x", 1), "must be a dibble")
    expect_error(set_dta_values(tibble::tibble(x = 1), "x", 1), "must be a dibble")
    expect_identical(as.data.frame(data), before)
    # No tidy evaluation: a symbol is an ordinary R value, not a column.
    y <- "x"
    set_dta_values(data, y, 5, rows = 1)
    expect_identical(as.double(data$x), c(5, 2, 3))
    expect_error(set_dta_values(data, x, 1), "object 'x' not found")
})

test_that("set_dta_values evaluates its arguments before reading the table", {
    # An argument that reorders the table by reference is honoured: the
    # write lands in the named column at its new position.
    data <- dibble(x = c(1, 2), y = c(3, 4))
    set_dta_values(data, "x", 9, rows = { order_vars(data, y, x); 1 })
    expect_identical(names(data), c("y", "x"))
    expect_identical(as.double(data$x), c(9, 2))
    expect_identical(as.double(data$y), c(3, 4))
    set_dta_values(data, { drop_vars(data, y); "x" }, 8, rows = 2)
    expect_identical(names(data), "x")
    expect_identical(as.double(data$x), c(9, 8))
    set_dta_values(data, "x", { gen(data, z = 0); 7 })
    expect_identical(names(data), c("x", "z"))
    expect_identical(as.double(data$x), c(7, 7))
    # A value whose size method reorders the table when the size rule runs,
    # after the target was first resolved, still writes the named column.
    late <- structure(list(5), class = "late_value")
    registerS3method("vec_proxy", "late_value", function(x, ...) { order_vars(data, z, x); 5 },
                     envir = asNamespace("vctrs"))
    expect_error(set_dta_values(data, "x", late))
    expect_identical(names(data), c("z", "x"))
    expect_identical(as.double(data$x), c(7, 7))
    # A callback that adds the column being created turns creation into a
    # write to that column, never a duplicate name.
    added <- structure(list(1), class = "adding_value")
    registerS3method("vec_proxy", "adding_value", function(x, ...) { gen(data, w = 0); 1 },
                     envir = asNamespace("vctrs"))
    expect_error(set_dta_values(data, "w", added, create = TRUE))
    expect_identical(names(data), c("z", "x", "w"))
    expect_identical(as.double(data$w), c(0, 0))
    # A container no writer accepts is refused before any argument runs.
    touched <- 0L
    touch <- function(value) { touched <<- touched + 1L; value }
    odd <- structure(dibble(x = 1), class = c("dibble", "dtatools_ref_data", "odd_df", "tbl_df", "tbl", "data.frame"))
    expect_error(set_dta_values(odd, touch("x"), touch(1), create = touch(FALSE)), "as_dibble")
    expect_identical(touched, 0L)
    skip_if_not_installed("dplyr")
    rowwise <- dplyr::rowwise(dibble(x = c(1, 2)))
    expect_error(set_dta_values(rowwise, touch("x"), touch(0)), "ungroup")
    expect_identical(touched, 0L)
})

test_that("set_dta_values settles a value that runs code when it is read", {
    ns <- asNamespace("dtatools")
    # A foreign ALTREP value whose element read reorders the table: the
    # value is copied before the layout is read, so the write lands in the
    # named column at its new position and the other column is untouched.
    data <- dibble(x = c(1, 2), y = c(3, 4))
    moving <- .Call(ns$C_dtatools_callback_double, c(9, 9),
                    function() order_vars(data, y, x), 1L)
    set_dta_values(data, "x", moving)
    expect_identical(names(data), c("y", "x"))
    expect_identical(as.double(data$x), c(9, 9))
    expect_identical(as.double(data$y), c(3, 4))
    # The same through `rows`.
    moving_rows <- .Call(ns$C_dtatools_callback_integer, 2L,
                         function() order_vars(data, x, y))
    set_dta_values(data, "y", 0, rows = moving_rows)
    expect_identical(names(data), c("x", "y"))
    expect_identical(as.double(data$y), c(3, 0))
    # A callback that adds the column being created, or removes the column
    # being written, is refused with nothing written and no duplicate name.
    adding <- .Call(ns$C_dtatools_callback_double, 1,
                    function() gen(data, w = 5), 1L)
    expect_error(set_dta_values(data, "w", adding, create = TRUE), "changed")
    expect_identical(names(data), c("x", "y", "w"))
    expect_identical(as.double(data$w), c(5, 5))
    removing <- .Call(ns$C_dtatools_callback_double, 1,
                      function() rename_vars(data, z = w), 1L)
    expect_error(set_dta_values(data, "w", removing, create = TRUE), "changed")
    expect_identical(names(data), c("x", "y", "z"))
    expect_identical(as.double(data$z), c(5, 5))
    # A callback that writes the same column first is sequenced before this
    # write, which then lands on top of it.
    writing <- .Call(ns$C_dtatools_callback_double, 1,
                     function() repl(data, z := 7), 1L)
    set_dta_values(data, "z", writing, rows = 1)
    expect_identical(as.double(data$z), c(1, 7))
    # A foreign value is settled before the target is resolved, so one
    # that replaces the column object, here by promoting its storage, is
    # sequenced before the write, which lands in the promoted column.
    set_dta_values(data, "n", 1L, create = TRUE)
    expect_identical(dta_storage_type(data$n), "long")
    promoting <- .Call(ns$C_dtatools_callback_double, 2,
                       function() repl(data, n := 1.5), 1L)
    expect_message(set_dta_values(data, "n", promoting), "long now double")
    expect_identical(dta_storage_type(data$n), "double")
    expect_identical(as.double(data$n), c(2, 2))
    # A vector with methods runs them during the cast, after the target was
    # resolved. One that replaces the column object then is refused: the
    # cast was made against a column the slot no longer holds.
    set_dta_values(data, "m", 1L, create = TRUE)
    late_promotion <- structure(3L, class = "promoting_value")
    registerS3method("vec_proxy", "promoting_value", function(x, ...) unclass(x),
                     envir = asNamespace("vctrs"))
    registerS3method("vec_cast", "dta_numeric.promoting_value",
                     function(x, to, ...) { repl(data, m := 1.5); vctrs::vec_cast(unclass(x), to) },
                     envir = asNamespace("vctrs"))
    expect_message(
        expect_error(set_dta_values(data, "m", late_promotion), "changed"),
        "long now double"
    )
    expect_identical(dta_storage_type(data$m), "double")
    expect_identical(as.double(data$m), c(1.5, 1.5))
    # A position that reorders the table when it is read names the column
    # at that position afterwards.
    moving_position <- .Call(ns$C_dtatools_callback_integer, 1L,
                             function() order_vars(data, y, x))
    set_dta_values(data, moving_position, 6)
    expect_identical(names(data)[[1L]], "y")
    expect_identical(as.double(data$y), c(6, 6))
    expect_identical(as.double(data$x), c(9, 9))
    # A foreign value that breaks the size rule is refused by its length
    # alone, before any element is read.
    reads <- 0L
    oversized <- .Call(ns$C_dtatools_callback_double, c(1, 2, 3),
                       function() reads <<- reads + 1L, 1L)
    expect_error(set_dta_values(data, "x", oversized), "size 3")
    expect_identical(reads, 0L)
    # The value is read once in R and never by the native patch.
    reads <- 0L
    counted <- .Call(ns$C_dtatools_callback_double, c(4, 4),
                     function() reads <<- reads + 1L, 1L)
    set_dta_values(data, "x", counted)
    expect_identical(reads, 1L)
    expect_identical(as.double(data$x), c(4, 4))
})

test_that("set_dta_values creates a missing column only when asked", {
    data <- dibble(id = 1:3)
    result <- set_dta_values(data, "flag", TRUE, rows = c(1, 3), create = TRUE)
    expect_identical(names(data), c("id", "flag"))
    expect_identical(as.logical(data$flag), c(TRUE, NA, TRUE))
    expect_identical(rlang::obj_address(result), rlang::obj_address(data))
    set_dta_values(data, "score", 2.5, create = TRUE)
    expect_identical(dta_storage_type(data$score), "float")
    expect_identical(as.double(data$score), c(2.5, 2.5, 2.5))
    set_dta_values(data, "n", 7L, rows = 2, create = TRUE)
    expect_identical(dta_storage_type(data$n), "long")
    expect_identical(as.integer(data$n), c(NA, 7L, NA))
    set_dta_values(data, "s", "a", rows = 1, create = TRUE)
    expect_identical(as.character(data$s), c("a", "", ""))
    expect_identical(attr(data$s, "stata.string.storage"), "str1")
    # An existing column with create = TRUE is an ordinary write.
    set_dta_values(data, "n", 8L, rows = 1, create = TRUE)
    expect_identical(as.integer(data$n), c(8L, 7L, NA))
    expect_identical(names(data), c("id", "flag", "score", "n", "s"))
    # A position cannot create.
    expect_error(set_dta_values(data, 9, 1, create = TRUE), "one existing column name or position")
    expect_error(set_dta_values(data, "bad", c(1, 2), rows = 1, create = TRUE), "has size 2")
    expect_identical(names(data), c("id", "flag", "score", "n", "s"))
    # Growth past capacity returns an isolated table, as gen() does.
    small <- reserve_columns(dibble(a = 1:2), 0L)
    expect_warning(grown <- set_dta_values(small, "b", 1L, create = TRUE), "isolated table")
    expect_identical(names(grown), c("a", "b"))
    expect_identical(names(small), "a")
    withr::local_options(dtatools.auto_grow = FALSE)
    full <- reserve_columns(dibble(a = 1:2), 0L)
    expect_error(set_dta_values(full, "b", 1L, create = TRUE), "reserve_columns")
    # Capacity fails before `value` and `rows` are evaluated.
    touched <- 0L
    touch <- function(value) { touched <<- touched + 1L; value }
    expect_error(set_dta_values(full, "b", touch(1L), rows = touch(1), create = TRUE),
                 "reserve_columns")
    expect_identical(touched, 0L)
    expect_identical(names(full), "a")
    # A malformed table is refused before any argument is evaluated.
    broken <- dibble(a = 1:2, b = 3:4)
    attr(broken, "names") <- c("a", "a")
    expect_error(set_dta_values(broken, touch("a"), touch(1L)), "unique")
    expect_identical(touched, 0L)
})

test_that("set_dta_values works on grouped dibbles and refuses rowwise ones", {
    skip_if_not_installed("dplyr")
    data <- dplyr::group_by(dibble(g = c(1, 1, 2), x = c(1, 2, 3)), g)
    set_dta_values(data, "x", 0, rows = 2)
    expect_identical(as.double(data$x), c(1, 0, 3))
    expect_s3_class(data, "grouped_df")
    # Writing a grouping key rebuilds the groups.
    set_dta_values(data, "g", 2, rows = 1)
    expect_identical(nrow(attr(data, "groups")), 2L)
    expect_identical(attr(data, "groups")$.rows[[1L]], 2L)
    set_dta_values(data, "y", 1, create = TRUE)
    expect_identical(names(data), c("g", "x", "y"))
    expect_s3_class(data, "grouped_df")
    rowwise <- dplyr::rowwise(dibble(x = c(1, 2)))
    expect_error(set_dta_values(rowwise, "x", 0), "ungroup")
})

test_that("set_dta_values matches repl(promote = FALSE) on every storage", {
    columns <- list(
        byte = dta_byte(c(1, 2, 3)), int = dta_int(c(1, 2, 3)),
        long = dta_long(c(1, 2, 3)), float = dta_float(c(1, 2, 3)),
        double = dta_double(c(1, 2, 3)), plain = c(1, 2, 3),
        integer = 1:3, logical = c(TRUE, FALSE, TRUE),
        string = dta_string(c("a", "b", "c"), storage = "str3"),
        character = c("a", "b", "c")
    )
    values <- list(byte = 7, int = 7, long = 7, float = 7.5, double = 7.5,
                   plain = 7.5, integer = 7L, logical = FALSE,
                   string = "zzz", character = "z")
    for (name in names(columns)) {
        via_set <- dibble(!!name := columns[[name]])
        via_repl <- dibble(!!name := columns[[name]])
        set_dta_values(via_set, name, values[[name]], rows = 2)
        repl(via_repl, !!name := values[[name]], where = .n == 2, promote = FALSE)
        expect_identical(as.data.frame(via_set), as.data.frame(via_repl), info = name)
        expect_identical(attributes(via_set[[name]]), attributes(via_repl[[name]]), info = name)
    }
})

test_that("set_dta_values detaches a column shared with another table", {
    data <- dibble(x = as.double(1:3))
    other <- tibble::as_tibble(data)
    set_dta_values(data, "x", 9, rows = 1)
    expect_identical(as.double(data$x), c(9, 2, 3))
    expect_identical(as.double(other$x), c(1, 2, 3))
    imported <- read_dta(fixture("auto_v118.dta"))
    copy <- imported$rep78
    set_dta_values(imported, "rep78", 5, rows = 1)
    expect_identical(as.double(imported$rep78)[[1L]], 5)
    expect_identical(as.double(copy)[[1L]], 3)
})

test_that("a set_dta_values loop allocates nothing proportional to the table", {
    data <- dibble(x = as.double(seq_len(100000)))
    set_dta_values(data, "x", 0, rows = 1)
    before <- sum(gc(full = TRUE)[, 6L])
    for (i in seq_len(500)) set_dta_values(data, "x", 0, rows = i)
    allocated_mb <- sum(gc(full = FALSE)[, 6L]) - before
    expect_identical(as.double(data$x)[1:500], rep(0, 500))
    # 500 writes to an 800 KB column: a copy per write would be 400 MB.
    expect_lt(allocated_mb, 8)
})
