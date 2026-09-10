.growth_warning <- "Column reallocation created an isolated table"

test_that("automatic growth defaults to 1024 spare slots and isolates old tables", {
    withr::local_options(dtatools.auto_grow = NULL, dtatools.alloccol = NULL)
    for (make in list(data.frame, tibble::tibble, dibble)) {
        for (damage in list(function(x) reserve_columns(x, 0),
                            function(x) unserialize(serialize(x, NULL)))) {
            x <- damage(make(x = 1:3))
            old <- x
            expect_warning(result <- gen(x, y = .data$x + 1), .growth_warning)
            expect_identical(rlang::obj_address(x), rlang::obj_address(result))
            expect_false(identical(rlang::obj_address(x), rlang::obj_address(old)))
            expect_equal(column_capacity(x) - ncol(x), 1024)
            expect_identical(names(x), c("x", "y"))
            expect_identical(names(old), "x")
            expect_equal(as.integer(x$y), 2:4)
            repl(x, x = 0L)
            expect_identical(as.integer(old$x), 1:3)
            repl(old, x = 9L)
            expect_identical(as.integer(x$x), rep(0L, 3))
        }
    }
})

test_that("functions return their grown local target while spare capacity shares identity", {
    withr::local_options(dtatools.auto_grow = TRUE)
    f <- function(data) { gen(data, y = .data$x + 1L); data }
    x <- reserve_columns(dibble(x = 1:3), 0)
    old <- x
    expect_warning(x <- f(x), .growth_warning)
    expect_identical(names(x), c("x", "y"))
    expect_identical(names(old), "x")
    untouched <- reserve_columns(dibble(x = 1:3), 0)
    expect_warning(f(untouched), .growth_warning)
    expect_identical(names(untouched), "x")
    ready <- reserve_columns(dibble(x = 1:3), 1)
    alias <- ready
    address <- rlang::obj_address(ready)
    expect_silent(f(ready))
    expect_identical(rlang::obj_address(ready), address)
    expect_identical(names(alias), c("x", "y"))
})

test_that("strict and invalid growth options reject callbacks before preparation", {
    for (option in list(FALSE, NA, 1, "yes", logical(), c(TRUE, FALSE))) {
        withr::local_options(dtatools.auto_grow = option)
        for (verb in c("gen", "egen")) {
            x <- reserve_columns(dibble(id = c(2L, 1L), x = 3:4), 0)
            old <- serialize(x, NULL)
            expected <- if (identical(option, FALSE)) "Assign.*reserve_columns" else "dtatools.auto_grow"
            call <- substitute(FUN(x, y = stop("RHS"), where = stop("where"), bysort = id), list(FUN = as.name(verb)))
            expect_error(eval(call), expected)
            expect_identical(serialize(x, NULL), old)
        }
        x <- reserve_columns(dibble(id = c(2L, 1L), x = 3:4), 0)
        expect_error(x[stop("where"), `:=`(x = 0L, y = stop("RHS")), bysort = id], expected)
    }
    withr::local_options(dtatools.auto_grow = TRUE, warn = 2)
    x <- reserve_columns(dibble(x = 1:3), 0)
    before <- serialize(x, NULL)
    expect_error(gen(x, y = stop("RHS")), .growth_warning)
    expect_identical(serialize(x, NULL), before)
})

test_that("growth respects spare overrides and leaves nongrowth preparation strict", {
    withr::local_options(dtatools.auto_grow = TRUE, dtatools.alloccol = 3L)
    x <- data.frame(x = 1:2)
    expect_warning(gen(x, y = 1L), .growth_warning)
    expect_equal(column_capacity(x) - ncol(x), 3)
    x <- unserialize(serialize(dibble(x = 1:2, y = 3:4), NULL))
    expect_error(drop_vars(x, y), "Assign.*reserve_columns")
    expect_error(keep_vars(x, x), "Assign.*reserve_columns")
    expect_silent(repl(x, x = 0L))
    expect_identical(names(x), c("x", "y"))
    withr::local_options(dtatools.alloccol = -1)
    expect_error(gen(x, z = stop("RHS")), "whole number")
})

test_that("captured generation targets and getter arguments run exactly once", {
    withr::local_options(dtatools.auto_grow = TRUE)
    for (getter in c("get", "get0")) {
        e <- new.env(); e$data <- data.frame(x = 1:2)
        old <- e$data
        nc <- ec <- 0L
        name <- function() { nc <<- nc + 1L; "data" }
        environment <- function() { ec <<- ec + 1L; e }
        call <- substitute(gen(FUN(name(), envir = environment()), y = 1L), list(FUN = as.name(getter)))
        expect_warning(eval(call), .growth_warning)
        expect_identical(c(nc, ec), c(1L, 1L))
        expect_identical(names(e$data), c("x", "y"))
        expect_identical(names(old), "x")
    }
    box <- list(a = data.frame(x = 1:2), b = data.frame(z = 3:4))
    old <- box$a; calls <- 0L
    key <- function() { calls <<- calls + 1L; "a" }
    expect_warning(gen(box[[key()]], y = 1L), .growth_warning)
    expect_identical(calls, 1L)
    expect_identical(names(box$a), c("x", "y"))
    expect_identical(names(box$b), "z")
    expect_identical(names(old), "x")
})

test_that("growth never overwrites a target changed by a callback", {
    withr::local_options(dtatools.auto_grow = TRUE)
    x <- data.frame(x = 1:2)
    replacement <- data.frame(other = 3:4)
    warnings <- character()
    change_x <- function() { x <<- replacement; 1L }
    result <- withCallingHandlers(gen(x, y = change_x()), warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
    expect_length(warnings, 2L)
    expect_match(warnings[[1L]], .growth_warning)
    expect_match(warnings[[2L]], "Mutation target changed")
    expect_identical(x, replacement)
    expect_identical(names(result), c("x", "y"))
    box <- list(data = data.frame(x = 1:2))
    replacement_box <- list(other = 4L)
    warnings <- character()
    change_box <- function() { box <<- replacement_box; 1L }
    result <- withCallingHandlers(gen(box$data, y = change_box()), warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
    expect_length(warnings, 2L)
    expect_identical(box, replacement_box)
    expect_identical(names(result), c("x", "y"))
})

test_that("bracket growth preflights every new name and publishes sequential commits", {
    withr::local_options(dtatools.auto_grow = TRUE, dtatools.alloccol = 2L)
    x <- reserve_columns(dibble(x = 1:2), 0)
    old <- x
    warnings <- character()
    expect_error(withCallingHandlers(x[, `:=`(
        y = .data$x + 1L,
        z = { stopifnot("y" %in% names(.env$x)); .data$y + 1L },
        fail = stop("last RHS")
    )], warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }), "last RHS")
    expect_length(warnings, 1L)
    expect_match(warnings, .growth_warning)
    expect_identical(names(x), c("x", "y", "z"))
    expect_identical(as.integer(x$z), 3:4)
    expect_identical(names(old), "x")
    expect_equal(column_capacity(x) - ncol(x), 3)
    x <- reserve_columns(dibble(x = 1:2), 0)
    expect_warning(expect_error(x[, y := stop("first RHS")], "first RHS"), .growth_warning)
    expect_identical(names(x), "x")
})

test_that("egen and grouped generation evaluate on the rebuilt table", {
    withr::local_options(dtatools.auto_grow = TRUE)
    x <- reserve_columns(dibble(id = c(2L, 1L, 2L), x = c(3L, 4L, 5L)), 0)
    old <- x
    expect_warning(egen(x, average = dta_mean(.data$x), bysort = id), .growth_warning)
    expect_identical(as.integer(x$id), c(1L, 2L, 2L))
    expect_equal(as.double(x$average), c(4, 4, 4))
    expect_identical(as.integer(old$id), c(2L, 1L, 2L))
    grouped <- reserve_columns(as_dibble(.group_fixture("id_12")$data), 0)
    old <- grouped
    expect_warning(gen(grouped, size = .N), .growth_warning)
    expect_identical(attr(grouped, "groups"), attr(old, "groups"))
    expect_identical(names(old), setdiff(names(grouped), "size"))
    expect_equal(as.integer(grouped$size), c(1L, 1L))
})

test_that("implicit publication never forces changed lazy or active bindings", {
    withr::local_options(dtatools.auto_grow = TRUE)
    for (kind in c("lazy", "active")) {
        e <- new.env(); e$x <- data.frame(x = 1:2)
        reads <- writes <- 0L
        change <- function() {
            rm("x", envir = e)
            if (kind == "lazy") delayedAssign("x", { reads <<- reads + 1L; 99L }, assign.env = e)
            else makeActiveBinding("x", function(value) {
                if (missing(value)) { reads <<- reads + 1L; 99L } else writes <<- writes + 1L
            }, e)
            1L
        }
        result <- suppressWarnings(gen(get("x", envir = e), y = change()))
        expect_identical(reads, 0L)
        expect_identical(writes, 0L)
        expect_identical(names(result), c("x", "y"))
    }
    e <- new.env(); calls <- 0L; target <- data.frame(x = 1:2)
    makeActiveBinding("x", function(value) {
        if (!missing(value)) stop("implicit setter")
        calls <<- calls + 1L; target
    }, e)
    result <- suppressWarnings(gen(e$x, y = 1L))
    expect_identical(calls, 1L)
    expect_identical(names(result), c("x", "y"))
    expect_identical(names(target), "x")
})

test_that("bracket literals rebind while computed targets return without replay", {
    withr::local_options(dtatools.auto_grow = TRUE)
    box <- list(data = reserve_columns(dibble(x = 1:2), 0))
    old <- box$data
    expect_warning(box$data[, y := 1L], .growth_warning)
    expect_identical(names(box$data), c("x", "y"))
    expect_identical(names(old), "x")
    x <- reserve_columns(dibble(x = 1:2), 0)
    calls <- 0L
    name <- function() { calls <<- calls + 1L; "x" }
    expect_warning(result <- get(name())[, y := 1L], .growth_warning)
    expect_identical(calls, 1L)
    expect_identical(names(x), "x")
    expect_identical(names(result), c("x", "y"))
    get <- function(...) { calls <<- calls + 1L; x }
    expect_warning(result <- gen(get("x"), y = 1L), .growth_warning)
    expect_identical(calls, 2L)
    expect_identical(names(x), "x")
    expect_identical(names(result), c("x", "y"))
})

test_that("metadata and forwarded functions preserve explicit result assignment", {
    withr::local_options(dtatools.auto_grow = TRUE)
    x <- dibble(x = 1:2)
    add_dta_note(x, "owned note")
    x <- reserve_columns(x, 0)
    old <- x
    expect_warning(x[, y := 1L], .growth_warning)
    expect_identical(names(x), c("x", "y"))
    expect_identical(dta_notes(x), dta_notes(old))
    forwarded <- function(data) { data[, z := 2L]; data }
    x <- reserve_columns(x, 0)
    before <- x
    expect_warning(x <- forwarded(x), .growth_warning)
    expect_identical(names(x), c("x", "y", "z"))
    expect_identical(names(before), c("x", "y"))
    expect_identical(dta_notes(x), dta_notes(before))
})

test_that("automatic growth repairs serialized data.table only for new columns", {
    skip_if_not_installed("data.table")
    .datatable.aware <- TRUE
    withr::local_options(dtatools.auto_grow = TRUE, dtatools.alloccol = 4L)
    for (verb in c("gen", "egen")) {
        x <- data.table::data.table(id = c(2L, 1L), x = 3:4)
        data.table::setkeyv(x, "id")
        x <- unserialize(serialize(x, NULL))
        old <- x
        call <- if (verb == "gen") quote(gen(x, y = .data$x + 1L)) else quote(egen(x, y = dta_mean(.data$x)))
        expect_warning(eval(call), .growth_warning)
        expect_true(data.table::is.data.table(x))
        expect_identical(names(x), c("id", "x", "y"))
        expect_identical(names(old), c("id", "x"))
        expect_true(can_add_columns(x, 4L))
        repl(x, x = 0L)
        expect_identical(as.integer(old$x), c(4L, 3L))
    }
})

test_that("unsupported lazy target lookups are left to the original call", {
    withr::local_options(dtatools.auto_grow = TRUE)
    e <- new.env(parent = environment())
    original <- data.frame(x = 1:2)
    other <- data.frame(other = 3:4)
    tracker <- new.env(); tracker$forces <- 0L; tracker$getters <- 0L
    e$original <- original; e$other <- other
    `$.auto_growth_holder` <- function(x, name) {
        tracker$getters <- tracker$getters + 1L
        unclass(x)[[name]]
    }
    delayedAssign("box", {
        tracker$forces <- tracker$forces + 1L
        e$box <- list(data = other)
        structure(list(data = original), class = "auto_growth_holder")
    }, assign.env = e)
    expect_warning(result <- evalq(gen(box$data, y = 1L), e), .growth_warning)
    expect_identical(c(tracker$forces, tracker$getters), c(1L, 1L))
    expect_identical(names(result), c("x", "y"))
    expect_identical(names(e$box$data), "other")
    expect_identical(names(original), "x")
    tracker$forces <- 0L; replaced_get_calls <- 0L
    e$x <- original
    delayedAssign("get", {
        tracker$forces <- tracker$forces + 1L
        e$get <- function(...) { replaced_get_calls <<- replaced_get_calls + 1L; other }
        base::get
    }, assign.env = e)
    expect_warning(result <- evalq(gen(get("x", pos = -1L), y = 1L), e), .growth_warning)
    expect_identical(tracker$forces, 1L)
    expect_identical(replaced_get_calls, 0L)
    expect_identical(names(result), c("x", "y"))
    expect_identical(names(e$x), "x")
})

test_that("bracket destinations are captured before assignment-name callbacks", {
    withr::local_options(dtatools.auto_grow = TRUE)
    for (change_parent in c(FALSE, TRUE)) {
        e <- new.env(parent = environment())
        e$change_parent <- change_parent
        evalq({
            original <- reserve_columns(dibble(x = 1:2), 0)
            box <- list(data = original)
            calls <- 0L
            name <- function() {
                calls <<- calls + 1L
                if (change_parent) box <<- list(data = original, marker = "callback")
                "y"
            }
        }, e)
        warnings <- character()
        result <- withCallingHandlers(eval(quote(box$data[, .(name()) := 1L]), e),
            warning = function(w) {
                warnings <<- c(warnings, conditionMessage(w))
                invokeRestart("muffleWarning")
            })
        expect_identical(e$calls, 1L)
        expect_identical(names(e$original), "x")
        expect_identical(names(result), c("x", "y"))
        expect_identical(as.integer(result$y), c(1L, 1L))
        expect_match(warnings[[1L]], .growth_warning)
        if (change_parent) {
            expect_length(warnings, 2L)
            expect_match(warnings[[2L]], "Mutation target changed")
            expect_identical(e$box$marker, "callback")
            expect_identical(rlang::obj_address(e$box$data), rlang::obj_address(e$original))
        } else {
            expect_length(warnings, 1L)
            expect_identical(rlang::obj_address(e$box$data), rlang::obj_address(result))
        }
    }
    e <- new.env(parent = environment())
    evalq({
        original <- reserve_columns(dibble(x = 1:2), 0)
        where <- new.env(); where$data <- original
        old_where <- where
        calls <- 0L
        name <- function() {
            calls <<- calls + 1L
            where <<- new.env(); where$data <- original
            "y"
        }
    }, e)
    expect_warning(result <- eval(quote(get("data", envir = where)[, .(name()) := 1L]), e), .growth_warning)
    expect_identical(e$calls, 1L)
    expect_identical(rlang::obj_address(e$old_where$data), rlang::obj_address(result))
    expect_identical(names(e$where$data), "x")
    expect_identical(names(e$original), "x")
})

test_that("whole assignment injection retains function-local bare targets", {
    withr::local_options(dtatools.auto_grow = TRUE)
    assignment <- quote(y := 1L)
    f <- function(data) { data[, !!assignment]; data }
    x <- reserve_columns(dibble(x = 1:2), 0)
    old <- x
    expect_warning(x <- f(x), .growth_warning)
    expect_identical(names(x), c("x", "y"))
    expect_identical(as.integer(x$y), c(1L, 1L))
    expect_identical(names(old), "x")
    box <- list(data = reserve_columns(dibble(x = 1:2), 0))
    warnings <- character()
    # Do not let an expectation's own enquo() inject j before bracket dispatch.
    result <- withCallingHandlers(box$data[, !!assignment], warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    })
    expect_length(warnings, 1L)
    expect_match(warnings[[1L]], .growth_warning)
    expect_identical(names(result), c("x", "y"))
    expect_identical(names(box$data), "x")
})
