# Summary/callback policies adapted from pinned dplyr tests; see inst/NOTICE.
# The original fifteen-block draft was qualified on the Stage6 predecessor.
.s7_grouped <- function() dplyr::group_by(
    dibble(g = c("b", "a", "b", "a"), x = c(1, 2, 3, 4), y = c(10, 20, 30, 40)), g)

test_that("S7-S01 summary expressions run in dot then group order with dependent typing", {
    seen <- character()
    mark <- function(dot) { seen <<- c(seen, paste0(dot, dplyr::cur_group_id())); invisible(NULL) }
    result <- dplyr::summarise(.s7_grouped(),
        a = { mark("a"); sum(x) },
        b = { mark("b"); a + dplyr::n() },
        s = NA_character_, missing = s == "", .groups = "drop")
    expect_identical(seen, c("a1", "a2", "b1", "b2"))
    expect_identical(as.character(result$g), c("a", "b"))
    expect_identical(as.double(result$a), c(6, 4))
    expect_identical(as.double(result$b), c(8, 6))
    expect_identical(as.character(result$s), c("", ""))
    expect_identical(result$missing, c(TRUE, TRUE))
    expect_true(is_dibble(result))
})

test_that("S7-S02 across siblings finish before any sibling enters the summary mask", {
    seen <- character()
    result <- dplyr::summarise(.s7_grouped(),
        dplyr::across(c(x, y), ~ {
            seen <<- c(seen, paste(dplyr::cur_column(), dplyr::cur_group_id()))
            sum(.x) + sum(x)
        }), .groups = "drop")
    # The typed predecessor keeps across inside one expression, evaluated per group.
    expect_identical(seen, c("x 1", "y 1", "x 2", "y 2"))
    expect_identical(as.double(result$x), c(12, 8))
    expect_identical(as.double(result$y), c(66, 44))
})

test_that("S7-S03 summary size validation waits for later dots and retains repeated chunks", {
    seen <- integer()
    expect_error(dplyr::summarise(.s7_grouped(), bad = 1:2,
        later = { seen <<- c(seen, dplyr::cur_group_id()); 1L }, .groups = "drop"))
    expect_identical(seen, 1:2)
    seen <- integer()
    expect_error(dplyr::summarise(.s7_grouped(), repeated = 1:2,
        repeated = { seen <<- c(seen, dplyr::cur_group_id()); 1L }, .groups = "drop"))
    expect_identical(seen, 1:2)
    expect_error(dplyr::summarise(.s7_grouped(), bad = integer(),
        later = stop("later deliberate error"), .groups = "drop"), "later deliberate error")
})

test_that("S7-S04 all NULL skips installation and does not erase earlier summaries", {
    result <- dplyr::summarise(.s7_grouped(), x = 1L, x = NULL,
        after = x, fresh = NULL, .groups = "drop")
    expect_identical(names(result), c("g", "x", "after"))
    expect_identical(as.double(result$x), c(1, 1))
    expect_identical(as.double(result$after), c(1, 1))
    expect_error(dplyr::summarise(.s7_grouped(),
        mixed = if (dplyr::cur_group_id() == 1L) NULL else 1L, .groups = "drop"))
})

test_that("S7-S05 packed and unpacked zero-column frames have distinct size rules", {
    empty_two <- function() vctrs::new_data_frame(list(), n = 2L)
    summary <- dplyr::summarise(.s7_grouped(), empty_two(), .groups = "drop")
    expect_identical(dim(summary), c(2L, 1L))
    expect_error(dplyr::summarise(.s7_grouped(), packed = empty_two(), .groups = "drop"))
    reframed <- dplyr::reframe(.s7_grouped(), empty_two())
    expect_identical(dim(reframed), c(2L, 1L))
    packed <- dplyr::reframe(.s7_grouped(), packed = empty_two())
    expect_identical(as.character(packed$g), c("a", "a", "b", "b"))
    expect_s3_class(packed$packed, "data.frame")
    expect_identical(dim(packed$packed), c(4L, 0L))
})

test_that("S7-S06 reframe defers horizontal recycling until all dots finish", {
    result <- dplyr::reframe(.s7_grouped(), a = 7L, b = 1:2, observed = length(a))
    expect_identical(as.integer(result$a), rep(7L, 4L))
    expect_identical(as.integer(result$b), rep(1:2, 2L))
    expect_identical(as.integer(result$observed), rep(1L, 4L))
    empty <- dplyr::reframe(.s7_grouped(), a = 7L, b = integer(), observed = length(a))
    expect_identical(nrow(empty), 0L)
    expect_identical(names(empty), c("g", "a", "b", "observed"))
    expect_error(dplyr::reframe(.s7_grouped(), a = 1:2, b = 1:3))
})

test_that("S7-S07 summary helper context retains original group rows after shortening", {
    seen <- list()
    helper <- function() list(n = dplyr::n(), id = dplyr::cur_group_id(),
        rows = dplyr::cur_group_rows(), key = as.character(dplyr::cur_group()$g))
    result <- dplyr::summarise(.s7_grouped(), x = sum(x),
        observed = { seen[[length(seen) + 1L]] <<- helper(); length(x) }, .groups = "drop")
    expect_identical(as.integer(result$observed), c(1L, 1L))
    expect_identical(seen, list(list(n = 2L, id = 1L, rows = c(2L, 4L), key = "a"),
                              list(n = 2L, id = 2L, rows = c(1L, 3L), key = "b")))
    expect_error(dplyr::n(), "Must only be used")
})

test_that("S7-S08 reframe unboxes rowwise lists and always returns ungrouped output", {
    data <- dplyr::rowwise(dibble(id = 1:2, x = list(1:2, 3L)), id)
    result <- dplyr::reframe(data, x)
    expect_identical(as.integer(result$id), c(1L, 1L, 2L))
    expect_identical(as.integer(result$x), 1:3)
    expect_identical(dplyr::group_vars(result), character())
    expect_false(inherits(result, "rowwise_df"))
    expect_true(is_dibble(result))
})

test_that("S7-S09 summary grouping policies distinguish plain grouped and rowwise input", {
    plain <- dibble(g = c("b", "a", "b"), h = c(2L, 1L, 2L), x = 1:3)
    by <- dplyr::summarise(plain, n = dplyr::n(), .by = g)
    expect_identical(as.character(by$g), c("b", "a"))
    expect_identical(dplyr::group_vars(by), character())
    expect_false(inherits(dplyr::summarise(plain, n = dplyr::n(), .groups = "ignored"), "grouped_df"))
    grouped <- dplyr::group_by(plain, g, h)
    expect_identical(dplyr::group_vars(dplyr::summarise(grouped, n = dplyr::n(), .groups = "keep")), c("g", "h"))
    expect_identical(dplyr::group_vars(dplyr::summarise(grouped, n = dplyr::n(), .groups = "drop_last")), "g")
    expect_s3_class(dplyr::summarise(grouped, n = dplyr::n(), .groups = "rowwise"), "rowwise_df")
    expect_error(dplyr::summarise(grouped, n = dplyr::n(), .groups = "ignored"))
    expect_error(dplyr::summarise(grouped, n = dplyr::n(), .by = g))
    rowwise <- dplyr::rowwise(plain, g)
    kept <- dplyr::summarise(rowwise, n = dplyr::n(), .groups = "keep")
    expect_s3_class(kept, "grouped_df")
    expect_false(inherits(kept, "rowwise_df"))
    expect_error(dplyr::summarise(rowwise, n = dplyr::n(), .groups = "drop_last"))
})

test_that("S7-S10 summary drops arbitrary table attributes and keeps column metadata", {
    data <- dibble(x = dta_double(c(1, 2)))
    attr(data, "label") <- "source dataset"
    attr(data$x, "label") <- "source variable"
    add_dta_note(data, "source note")
    result <- dplyr::summarise(data, x = x[1L])
    expect_null(attr(result, "label", exact = TRUE))
    expect_length(dta_notes(result), 0L)
    expect_identical(attr(result$x, "label", exact = TRUE), "source variable")
    expect_identical(attr(data, "label", exact = TRUE), "source dataset")
})

test_that("S7-S11 nested mask bindings isolate expression writes from source and earlier results", {
    skip_if_not_installed("data.table")
    foreign <- data.table::data.table(flag = c(TRUE, FALSE))
    source <- dplyr::rowwise(dibble(id = 1L, nested = list(foreign)))
    captured <- NULL
    result <- dplyr::summarise(source,
        old = list(nested),
        changed = { captured <<- nested; data.table::set(nested, i = 1L, j = "flag", value = FALSE); list(nested) },
        .groups = "drop")
    expect_identical(foreign$flag, c(TRUE, FALSE))
    expect_identical(source$nested[[1L]]$flag, c(TRUE, FALSE))
    expect_identical(result$old[[1L]]$flag, c(TRUE, FALSE))
    expect_identical(result$changed[[1L]]$flag, c(FALSE, FALSE))
    data.table::set(captured, i = 2L, j = "flag", value = TRUE)
    expect_identical(result$changed[[1L]]$flag, c(FALSE, FALSE))
})

test_that("S7-S12 summaries retain fresh masks and reset helper context after errors", {
    saved <- NULL
    result <- dplyr::summarise(.s7_grouped(),
        first = { local <- 7L; saved <<- function() x; sum(x) },
        second = exists("local", inherits = FALSE), .groups = "drop")
    expect_identical(result$second, c(FALSE, FALSE))
    expect_error(saved(), "Obsolete data mask")
    expect_error(dplyr::summarise(.s7_grouped(), broken = stop("summary failure")), "summary failure")
    expect_error(dplyr::n(), "Must only be used")
    expect_identical(as.integer(dplyr::summarise(.s7_grouped(), n = dplyr::n(), .groups = "drop")$n), c(2L, 2L))
})

test_that("S7-S13 bare replacement references promote only after dependent dots", {
    for (verb in list(dplyr::summarise, dplyr::reframe)) {
        data <- dibble(x = dta_int(2), flag = TRUE)
        result <- verb(data, x = flag, seen = is.logical(x))
        expect_identical(dta_storage_type(result$x), "int")
        expect_identical(as.double(result$x), 1)
        expect_identical(result$seen, TRUE)
        result <- verb(data, x = .data$flag, seen = is.logical(x))
        expect_identical(dta_storage_type(result$x), "int")
        expect_identical(result$seen, TRUE)
    }
})
