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

test_that("S7-S14 current group keys omit drop policy across summary, mutation and filter masks", {
    for (drop in c(FALSE, TRUE)) for (verb in c("summarise", "reframe", "mutate", "filter")) {
        data <- dplyr::group_by(.s7_grouped(), g, .drop = drop)
        seen <- list()
        observe <- function() {
            seen[[length(seen) + 1L]] <<- dplyr::cur_group()
            1L
        }
        result <- switch(verb,
            summarise = dplyr::summarise(data, value = observe(), .groups = "keep"),
            reframe = dplyr::reframe(data, value = observe()),
            mutate = dplyr::mutate(data, value = observe()),
            filter = dplyr::filter(data, { observe(); TRUE }))
        expect_identical(lapply(seen, function(key) as.character(key$g)), list("a", "b"))
        expect_identical(lapply(seen, function(key) attr(key, ".drop", exact = TRUE)), list(NULL, NULL))
        expect_identical(attr(attr(data, "groups"), ".drop"), drop)
        if (verb != "reframe") expect_identical(attr(attr(result, "groups"), ".drop"), drop)
    }
})

test_that("S7-S15 summary errors retain the trigger or named incompatible groups", {
    for (verb in list(dplyr::summarise, dplyr::reframe)) {
        trigger <- tryCatch(verb(.s7_grouped(), value =
            rlang::abort("deliberate summary trigger", class = "stage7_trigger")), error = identity)
        expect_identical(class(trigger), c("rlang_error", "error", "condition"))
        expect_s3_class(trigger$parent, "stage7_trigger")
        pair <- list(ordered("a"), ordered("b"))
        incompatible <- tryCatch(verb(.s7_grouped(),
            value = pair[[dplyr::cur_group_id()]]), error = identity)
        expect_identical(class(incompatible), c("rlang_error", "error", "condition"))
        expect_identical(class(incompatible$parent),
            c("dplyr:::error_incompatible_combine", "rlang_error", "error", "condition"))
        message <- conditionMessage(incompatible$parent)
        expect_match(message, "`value` must return compatible vectors across groups.", fixed = TRUE)
        expect_match(message, 'g = "a"', fixed = TRUE)
        expect_match(message, 'g = "b"', fixed = TRUE)
        expect_match(message, "Result of type <ordered", fixed = TRUE)
        expect_false(grepl("..1", message, fixed = TRUE))
        expect_error(dplyr::n(), "Must only be used")
    }
})

test_that("S7-S16 tagged payloads survive common typing and dependent summaries", {
    for (verb in list(dplyr::summarise, dplyr::reframe)) {
        pair <- list(tagged_missing("a"), NA_real_)
        result <- verb(.s7_grouped(), value = pair[[dplyr::cur_group_id()]], after = value)
        expect_identical(missing_tag(result$value), c("a", NA_character_))
        expect_identical(missing_tag(result$after), c("a", NA_character_))
        expect_identical(is.na(result$value), c(TRUE, TRUE))
    }
})

test_that("S7-S17 zero-group prototypes retain their observed contexts and size rules", {
    empty <- dibble(g = factor(character(), levels = c("a", "b")), x = integer())
    for (shape in c("zero_groups", "rowwise")) for (verb in list(dplyr::summarise, dplyr::reframe)) {
        data <- if (shape == "rowwise") dplyr::rowwise(empty, g) else dplyr::group_by(empty, g)
        for (value in list(integer(), 1L)) {
            seen <- list()
            result <- verb(data, value = {
                seen[[length(seen) + 1L]] <<- list(n = dplyr::n(), id = dplyr::cur_group_id(),
                    rows = dplyr::cur_group_rows(), key = dplyr::cur_group())
                value
            })
            expect_length(seen, 1L)
            expect_identical(seen[[1L]][c("n", "id", "rows")], list(n = 0L, id = 1L, rows = integer()))
            expect_identical(dim(seen[[1L]]$key), c(0L, 1L))
            expect_null(attr(seen[[1L]]$key, ".drop", exact = TRUE))
            expect_identical(levels(seen[[1L]]$key$g), c("a", "b"))
            expect_identical(dim(result), c(0L, 2L))
            expect_identical(names(result), c("g", "value"))
            expect_identical(dta_storage_type(result$value), "long")
        }
        # These final-assembly errors already occur on the typed predecessor.
        expect_error(verb(data, value = 1:2), class = "vctrs_error_recycle_incompatible_size")
        expect_error(verb(data, value = vctrs::new_data_frame(list(), n = 2L)),
            class = "vctrs_error_recycle_incompatible_size")
    }
    retained <- dplyr::group_by(empty, g, .drop = FALSE)
    keys <- list()
    result <- dplyr::summarise(retained, value = {
        keys[[length(keys) + 1L]] <<- dplyr::cur_group(); dplyr::n()
    }, .groups = "drop")
    expect_identical(lapply(keys, function(key) as.character(key$g)), list("a", "b"))
    expect_identical(as.integer(result$value), c(0L, 0L))
    expect_error(dplyr::summarise(retained, value = integer()), "size 1")
    expect_identical(nrow(dplyr::reframe(retained, value = integer())), 0L)
})

test_that("S7-S18 nested calls expire inner columns but restore dynamic helpers", {
    for (kind in c("success", "error", "interrupt")) {
        events <- list(); saved <- list()
        trigger <- switch(kind, success = function() 1L,
            error = function() stop("inner deliberate error"),
            interrupt = function() rlang::interrupt())
        result <- dplyr::summarise(.s7_grouped(), value = {
            before <- list(n = dplyr::n(), id = dplyr::cur_group_id(), rows = dplyr::cur_group_rows())
            capture <- new.env(parent = emptyenv())
            status <- tryCatch({
                dplyr::summarise(dibble(z = 1:3), value = {
                    capture$column <- function() z
                    capture$helper <- function() dplyr::n()
                    trigger()
                }); "success"
            }, error = function(cnd) "error", interrupt = function(cnd) "interrupt")
            after <- list(n = dplyr::n(), id = dplyr::cur_group_id(), rows = dplyr::cur_group_rows())
            # Invoke the expired promise once: repeated reads warn about restart.
            column_error <- tryCatch(capture$column(), error = conditionMessage)
            events[[length(events) + 1L]] <<- list(status = status, restored = identical(before, after),
                helper = capture$helper(), column_error = column_error)
            temporary <- sum(x)
            saved[[length(saved) + 1L]] <<- list(temporary = function() temporary, helper = capture$helper)
            1L
        }, .groups = "drop")
        expect_identical(as.integer(result$value), c(1L, 1L))
        expect_identical(vapply(events, `[[`, character(1), "status"), rep(kind, 2L))
        expect_true(all(vapply(events, `[[`, logical(1), "restored")))
        expect_identical(vapply(events, `[[`, integer(1), "helper"), c(2L, 2L))
        expect_true(all(vapply(events, function(event) grepl("Obsolete data mask", event$column_error), logical(1))))
        expect_identical(vapply(saved, function(entry) as.double(entry$temporary()), double(1)), c(6, 4))
        for (entry in saved) expect_error(entry$helper(), "Must only be used")
        saved <- NULL
    }
})

test_that("S7-S19 reframe reuse follows final group sizes and isolates nested captures", {
    result <- dplyr::reframe(.s7_grouped(), a = dplyr::cur_group_id(),
        b = if (dplyr::cur_group_id() == 1L) integer() else c(20L, 21L))
    # Equal total sizes cannot establish equality of every group's final size.
    expect_identical(as.integer(result$a), c(2L, 2L))
    expect_identical(as.integer(result$b), c(20L, 21L))
    expect_identical(as.character(result$g), c("b", "b"))
    skip_if_not_installed("data.table")
    foreign <- data.table::data.table(value = 1:2)
    source <- dplyr::rowwise(dibble(id = 1L, nested = list(foreign)))
    captured <- NULL
    result <- dplyr::reframe(source, old = list(nested), changed = {
        captured <<- nested
        data.table::set(nested, i = 1L, j = "value", value = 9L)
        list(nested)
    })
    expect_identical(foreign$value, 1:2)
    expect_identical(source$nested[[1L]]$value, 1:2)
    expect_identical(result$old[[1L]]$value, 1:2)
    expect_identical(result$changed[[1L]]$value, c(9L, 2L))
    data.table::set(captured, i = 2L, j = "value", value = 8L)
    expect_identical(captured$value, c(9L, 8L))
    expect_identical(result$changed[[1L]]$value, c(9L, 2L))
    data.table::set(result$old[[1L]], i = 1L, j = "value", value = 7L)
    expect_identical(result$old[[1L]]$value, c(7L, 2L))
    expect_identical(source$nested[[1L]]$value, 1:2)
    expect_identical(result$changed[[1L]]$value, c(9L, 2L))
})

test_that("S7-S20 unchanged reframe chunks avoid extra restoration callbacks", {
    events <- character()
    mark <- function(event) events <<- c(events, event)
    make <- function(x) vctrs::new_vctr(x, class = "stage7_reframe_restore")
    registerS3method("vec_ptype2", "stage7_reframe_restore.stage7_reframe_restore",
        function(x, y, ...) { mark("ptype2"); make(double()) }, envir = asNamespace("vctrs"))
    registerS3method("vec_cast", "stage7_reframe_restore.stage7_reframe_restore",
        function(x, to, ...) { mark("cast"); x }, envir = asNamespace("vctrs"))
    registerS3method("vec_restore", "stage7_reframe_restore",
        function(x, to, ...) { mark("restore"); make(x) }, envir = asNamespace("vctrs"))
    result <- dplyr::reframe(.s7_grouped(), value = make(c(1, 2)))
    # Capture before value inspection can itself invoke restoration methods.
    observed <- events
    reference_data <- dplyr::group_by(tibble::tibble(
        g = c("b", "a", "b", "a"), x = c(1, 2, 3, 4), y = c(10, 20, 30, 40)), g)
    events <- character()
    reference <- dplyr::reframe(reference_data, value = make(c(1, 2)))
    expected <- events
    expect_identical(observed, expected)
    expect_identical(as.character(result$g), c("a", "a", "b", "b"))
    expect_s3_class(result$value, "stage7_reframe_restore")
    expect_identical(vctrs::vec_data(result$value), c(1, 2, 1, 2))
    expect_identical(vctrs::vec_data(result$value), vctrs::vec_data(reference$value))
})
