test_that("one := creates a missing column and overwrites an existing one", {
    data <- dibble(x = c(1, 2, 3))
    # `[` forces its result visible after dispatch; autoprint is skipped
    # through the print method instead (tested below).
    result <- data[, y := x * 2]
    expect_identical(result, data)
    expect_true(is_dibble(result))
    expect_identical(names(data), c("x", "y"))
    expect_identical(as.double(data$y), c(2, 4, 6))
    expect_identical(dta_storage_type(data$y), "double")

    data[, y := 0]
    expect_identical(as.double(data$y), c(0, 0, 0))
    expect_identical(names(data), c("x", "y"))

    # The overwrite goes through the replace path: declared storage holds.
    expect_error(data[, y := "text"], "logical, integer, or double")
    expect_identical(as.double(data$y), c(0, 0, 0))
})

test_that("i selects rows as a logical, positions, or nothing", {
    data <- dibble(x = c(1, 2, 3, 4))
    data[x > 2, y := 1]
    expect_identical(as.double(data$y), c(NA, NA, 1, 1))
    data[c(1, 2), y := 5]
    expect_identical(as.double(data$y), c(5, 5, 1, 1))
    data[, y := 9]
    expect_identical(as.double(data$y), c(9, 9, 9, 9))
    data[NULL, y := 7]
    expect_identical(as.double(data$y), c(7, 7, 7, 7))
    data[.n == .N, y := .N]
    expect_identical(as.double(data$y), c(7, 7, 7, 4))
    data[x < 3, z := .n * 10]
    expect_identical(as.double(data$z), c(10, 20, NA, NA))

    expect_error(data[5, y := 1], "row positions")
    expect_error(data["a", y := 1], "logical values or numeric")
})

test_that("bracket assignments chain", {
    data <- dibble(x = c(1, 2, 3))
    data[x > 1, y := 1][x > 2, z := 2][, w := y + 1]
    expect_identical(names(data), c("x", "y", "z", "w"))
    expect_identical(as.double(data$y), c(NA, 1, 1))
    expect_identical(as.double(data$z), c(NA, NA, 2))
    expect_identical(as.double(data$w), c(NA, 2, 2))
})

test_that("several assignments apply left to right", {
    data <- dibble(x = c(1, 2, 3))
    data[, `:=`(y = x + 1, z = y * 10)]
    expect_identical(as.double(data$y), c(2, 3, 4))
    expect_identical(as.double(data$z), c(20, 30, 40))

    data[x > 1, c("a", "b") := list(x, a + 100)]
    expect_identical(as.double(data$a), c(NA, 2, 3))
    expect_identical(as.double(data$b), c(NA, 102, 103))

    # A later assignment may overwrite a column an earlier one created.
    data[, `:=`(fresh = 0, fresh2 = fresh + 1)][, fresh := fresh2]
    expect_identical(as.double(data$fresh), c(1, 1, 1))
})

test_that("each assignment in j commits or fails on its own", {
    data <- dibble(x = dta_byte(c(1, 2, 3)))
    before <- names(data)
    expect_error(data[2, `:=`(y = 1, x = 1000)], "byte")
    expect_identical(names(data), c(before, "y"))
    expect_identical(as.double(data$y), c(NA, 1, NA))
    expect_identical(as.double(data$x), c(1, 2, 3))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))

    # A failure in the first assignment leaves the rest unwritten.
    expect_error(data[2, `:=`(x = 1000, z = 1)], "byte")
    expect_false("z" %in% names(data))
})

test_that("rows are selected once before any assignment writes", {
    data <- dibble(x = c(1, 2, 3))
    data[x > 1, `:=`(x = 0, w = 1)]
    expect_identical(as.double(data$x), c(1, 0, 0))
    expect_identical(as.double(data$w), c(NA, 1, 1))

    # Same rule under groups: `x` is zeroed for the selected rows, and
    # `w` still lands on the rows `i` chose from the original `x`.
    grouped <- dibble(id = c(1, 1, 2, 2), x = c(1, 2, 3, 4))
    grouped[x == max(x), `:=`(x = 0, w = .n), by = id]
    expect_identical(as.double(grouped$x), c(1, 0, 3, 0))
    expect_identical(as.double(grouped$w), c(NA, 2, NA, 2))
})

test_that("the target name takes .(), !!, strings, and string vectors", {
    data <- dibble(x = c(1, 2))
    name <- "first"
    names <- c("second", "third")
    data[, .(name) := 1]
    data[, !!name := 2]
    data[, "fourth" := 4]
    data[, !!names := list(x, x * 2)]
    data[, c("fifth", .(name)) := list(5, 6)]
    expect_identical(
        names(data),
        c("x", "first", "fourth", "second", "third", "fifth")
    )
    expect_identical(as.double(data$first), c(6, 6))
    expect_identical(as.double(data$fourth), c(4, 4))
    expect_identical(as.double(data$second), c(1, 2))
    expect_identical(as.double(data$third), c(2, 4))
    expect_identical(as.double(data$fifth), c(5, 5))

    # A single name never takes the list form; `list()` is its value and
    # is rejected as a value type rather than split across columns.
    expect_error(data[, y := list(1, 2)], "numeric, logical, or character")

    expect_error(data[, c("a", "b") := 1], "`list\\(\\)` of 2")
    expect_error(data[, c("a", "b") := list(1)], "`list\\(\\)` of 2")
    expect_error(data[, c("a", "a") := list(1, 2)], "once")
    expect_error(data[, `:=`(a = 1, a = 2)], "once")
    expect_error(data[, "" := 1], "one column name")
    expect_error(data[, .(NA_character_) := 1], "nonempty")
    expect_error(data[, `:=`(a = 1, 2)], "tagged and untagged")
    expect_error(data[, `:=`(y = )], "value for every column")
    expect_error(data[, c("a", "b") := list(p = 1, 2)], "takes no names")
})

test_that("by, bysort, and grouped dibbles follow Stata's order", {
    data <- dibble(id = c(2, 1, 2, 1), x = c(1, 2, 3, 4))
    data[, `:=`(rows = .N, last = .n == .N), by = id]
    expect_identical(as.double(data$rows), c(2, 2, 2, 2))
    expect_identical(as.double(data$last), c(0, 0, 1, 1))
    # `.N` counts the group's rows whatever `i` selects.
    data[x > 2, count := .N, by = id]
    expect_identical(as.double(data$count), c(NA, NA, 2, 2))

    data[, centred := x - mean(x), by = "id"]
    expect_identical(as.double(data$centred), c(-1, -1, 1, 1))

    # data.table's third slot is `by`.
    data[, positional := .N, id]
    expect_identical(as.double(data$positional), c(2, 2, 2, 2))
    expect_error(data[, y := 1, id, id], "takes `i`, `j`")
    expect_error(data[, y := 1, id, by = id], "takes `i`, `j`")

    data[.n == 1, first := x, bysort = id]
    expect_identical(as.double(data$id), c(1, 1, 2, 2))
    expect_identical(as.double(data$x), c(2, 4, 1, 3))
    expect_identical(as.double(data$first), c(2, NA, 1, NA))

    grouped <- dplyr::group_by(dibble(id = c(1, 2, 1), x = 1:3), id)
    grouped[, total := sum(x)]
    expect_true(is_dibble(grouped))
    expect_identical(dplyr::group_vars(grouped), "id")
    expect_identical(as.double(grouped$total), c(4, 2, 4))
    expect_error(grouped[, y := 1, by = id], "already grouped")
    expect_error(grouped[, y := 1, bysort = id], "already grouped")
    expect_error(data[, y := 1, by = id, bysort = id], "not both")
    expect_error(data[, y := 1, by = missing_column], "does not exist")
})

test_that("by and bysort need a := in j", {
    data <- dibble(id = c(1, 2), x = c(1, 2))
    expect_error(data[, "x", by = id], "need a `:=`")
    expect_error(data[1, , bysort = id], "need a `:=`")
    expect_error(data[1, x := 1, drop = TRUE], "takes `i`, `j`")
})

test_that("the shadow check fires in i and in values", {
    x <- 5
    data <- dibble(x = c(1, 2, 3))
    expect_error(data[x > 1, y := 1], "both a column and an object")
    expect_error(data[, y := x], "both a column and an object")
    expect_false("y" %in% names(data))
    data[.data$x > .env$x - 4, y := .data$x]
    expect_identical(as.double(data$y), c(NA, 2, 3))
    withr::with_options(list(dtatools.shadow_check = FALSE), {
        data[x > 2, y := 0]
    })
    expect_identical(as.double(data$y), c(NA, 2, 0))
})

test_that("a compact target stays compact after a bracket replacement", {
    data <- dibble(id = c(1, 1, 2), x = dta_int(1:3))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    data[2, x := 9L]
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_identical(as.double(data$x), c(1, 9, 3))
    data[x > 1, x := 0L]
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_identical(as.double(data$x), c(1, 0, 0))
    data[.n == .N, x := 7L, by = id]
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_identical(as.double(data$x), c(1, 7, 7))
    expect_identical(dta_storage_type(data$x), "int")

    data[, y := dta_byte(.n)]
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$y))
    expect_identical(dta_storage_type(data$y), "byte")
})

test_that("brackets without := subset the current contents into a dibble", {
    data <- dibble(x = c(1, 2, 3), y = c("a", "b", "c"))
    gen(data, z = x * 2)
    snapshot <- tibble::as_tibble(data)
    # A dibble is closed under subsetting: the pieces are the snapshot's,
    # held in a fresh dibble.
    as_plain <- function(value) tibble::as_tibble(value)
    expect_true(is_dibble(data[1, ]))
    expect_identical(as_plain(data[1, ]), snapshot[1, ])
    expect_identical(as_plain(data[, "x"]), snapshot[, "x"])
    expect_identical(as_plain(data["x"]), snapshot["x"])
    expect_identical(data[["z"]], snapshot[["z"]])
    expect_identical(as_plain(data[data$x > 1, c("x", "y")]),
                     snapshot[snapshot$x > 1, c("x", "y")])
    expect_identical(as_plain(data[2]), snapshot[2])
    expect_identical(as.character(data[[2, "y"]]), "b")
    expect_identical(data[, "x", drop = TRUE], snapshot[, "x", drop = TRUE])
    expect_error(data[, "missing"], "missing")
    expect_identical(names(data), c("x", "y", "z"))
    # The subset is its own dataset: assigning into it leaves the source.
    piece <- data[1:2, ]
    piece[, w := 1]
    expect_identical(names(piece), c("x", "y", "z", "w"))
    expect_identical(names(data), c("x", "y", "z"))
})

test_that("plain containers do not gain bracket assignment", {
    frame <- data.frame(x = 1)
    expect_error(frame[1, y := 1])
    expect_identical(names(frame), "x")
    tbl <- tibble::tibble(x = 1)
    expect_error(tbl[1, y := 1])
    expect_identical(names(tbl), "x")
    # A base frame with reference state is not a dibble, but it carries
    # the class, so the method applies to it as well.
    marked <- data.frame(x = c(1, 2))
    gen(marked, y = x)
    marked[x > 1, z := 1]
    expect_identical(as.double(marked$z), c(NA, 1))
})

test_that("the next top-level print after a bracket assignment is skipped", {
    data <- dibble(x = 1)
    dtatools:::.suppress_bracket_autoprint(data)
    # Inside a test the print sits deep in the call stack, so it is never
    # taken for the assignment's autoprint; the record is spent regardless.
    expect_output(print(data), "A tibble")
    expect_null(dtatools:::.bracket_print$skip)
    expect_output(print(data), "A tibble")
})

test_that("the autoprint skip does not outlive its top-level statement", {
    # Only a real top-level loop autoprints, so drive a child R session.
    script <- tempfile(fileext = ".R")
    writeLines(c(
        "library(dtatools)",
        "data <- dibble(x = 1:2)",
        "cat('A\\n')",
        "data[1, y := 9]",            # autoprint skipped
        "cat('B\\n')",
        "data",                       # prints
        "cat('C\\n')",
        "result <- data[2, y := 1]",  # nothing to skip; record must die
        "data",                       # prints
        "cat('D\\n')",
        "for (i in 1:2) data[i, z := i]",
        "data",                       # prints
        "cat('E\\n')",
        "invisible(data[, w := 0])",
        "data",                       # prints
        "cat('F\\n')",
        "print(data[, v := 1])",      # explicit print shows the result
        "cat('G\\n')"
    ), script)
    skip_if_not_installed("callr")
    # callr passes the parent's library paths to the child on every
    # platform, where a hand-built `R_LIBS` would need the OS separator.
    # Only the child's standard output carries printed tables.
    output <- callr::rscript(
        script, libpath = .libPaths(), show = FALSE, fail_on_status = TRUE
    )$stdout
    output <- strsplit(output, "\r?\n")[[1L]]
    markers <- match(c("A", "B", "C", "D", "E", "F", "G"), output)
    expect_false(anyNA(markers), info = paste(output, collapse = "\n"))
    section <- function(index) {
        # `seq.int(a, b)` counts down when `b < a`, so size the run first.
        start <- markers[[index]] + 1L
        output[seq.int(start, length.out = markers[[index + 1L]] - start)]
    }
    expect_identical(
        section(1L), character(), info = paste(output, collapse = "\n")
    )
    for (index in 2:6) {
        expect_true(
            any(grepl("tibble", section(index), fixed = TRUE)),
            info = paste("section", index)
        )
    }
})
