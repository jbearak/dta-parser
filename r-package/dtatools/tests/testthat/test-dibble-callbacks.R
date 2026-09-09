# Summary/callback policies adapted from pinned dplyr tests; see inst/NOTICE.
# The original fifteen-block draft was qualified on the Stage6 predecessor.
test_that("S7-C01 grouped callbacks receive ordered keys and .keep uses TRUE only", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (keep in list(FALSE, TRUE, 1L)) {
        seen <- list()
        data <- dplyr::group_by(dibble(g = c("b", "a", "b"), x = 1:3), g)
        result <- dplyr::group_modify(data, function(.x, .y, increment) {
            seen[[length(seen) + 1L]] <<- list(names = names(.x), key = as.character(.y$g),
                                             rows = as.integer(.x$x), grouped = inherits(.x, "grouped_df"))
            tibble::tibble(z = sum(.x$x) + increment)
        }, increment = 10L, .keep = keep)
        expect_identical(lapply(seen, `[[`, "key"), list("a", "b"))
        expect_identical(lapply(seen, `[[`, "names"), rep(list(if (isTRUE(keep)) c("g", "x") else "x"), 2L))
        expect_identical(lapply(seen, `[[`, "rows"), list(2L, c(1L, 3L)))
        expect_false(any(vapply(seen, `[[`, logical(1), "grouped")))
        expect_identical(as.integer(result$z), c(12L, 14L))
        expect_identical(dplyr::group_vars(result), "g")
        expect_true(is_dibble(result))
    }
    data <- dplyr::group_by(dibble(g = c("a", "b"), x = 1:2), g)
    expect_error(dplyr::group_modify(data, function(.x) .x))
    expect_error(dplyr::group_modify(data, function(.x, .y) 1L))
    expect_error(dplyr::group_modify(data, function(.x, .y) .x, .keep = TRUE), "grouping variables")
})

test_that("S7-C02 plain and rowwise group_modify invoke one whole-table callback", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (rowwise in c(FALSE, TRUE)) {
        data <- dibble(id = 1:3, x = 4:6)
        if (rowwise) data <- dplyr::rowwise(data, id)
        calls <- 0L; seen <- NULL
        result <- dplyr::group_modify(data, function(.x, .y) {
            calls <<- calls + 1L
            seen <<- list(x_rows = nrow(.x), y_rows = nrow(.y), y_names = names(.y))
            tibble::tibble(total = sum(.x$x))
        })
        expect_identical(calls, 1L)
        expect_identical(seen, list(x_rows = 3L, y_rows = if (rowwise) 3L else 1L,
                                   y_names = if (rowwise) "id" else character()))
        expect_identical(as.integer(result$total), 15L)
    }
})

test_that("S7-C03 zero groups still invoke the callback once on prototypes", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dplyr::group_by(dibble(g = character(), x = integer()), g)
    calls <- 0L; seen <- NULL
    result <- dplyr::group_modify(data, function(.x, .y) {
        calls <<- calls + 1L
        seen <<- list(x_rows = nrow(.x), y_rows = nrow(.y), x_names = names(.x), y_names = names(.y))
        tibble::tibble(z = integer())
    })
    expect_identical(calls, 1L)
    expect_identical(seen, list(x_rows = 0L, y_rows = 0L, x_names = "x", y_names = "g"))
    expect_identical(dim(result), c(0L, 2L))
    expect_identical(names(result), c("g", "z"))
    expect_identical(dplyr::group_vars(result), "g")
})

test_that("S7-C04 nesting distinguishes no dots whole input from grouped list-of chunks", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (rows in c(0L, 3L)) {
        data <- dibble(id = seq_len(rows), x = seq_len(rows))
        result <- dplyr::group_nest(data)
        expect_identical(dim(result), c(1L, 1L))
        expect_type(result$data, "list")
        expect_false(inherits(result$data, "vctrs_list_of"))
        expect_identical(nrow(result$data[[1L]]), rows)
    }
    grouped <- dplyr::group_by(dibble(g = c("b", "a", "b"), x = 1:3), g)
    nested <- dplyr::group_nest(grouped)
    expect_s3_class(nested$data, "vctrs_list_of")
    expect_identical(lapply(nested$data, names), list("x", "x"))
    expect_identical(lapply(nested$data, function(x) as.integer(x$x)), list(2L, c(1L, 3L)))
    expect_identical(dplyr::group_vars(nested), character())
    expect_warning(dplyr::group_nest(grouped, ignored = stop("must not force")), "ignores")
    expect_error(dplyr::nest_by(grouped, x))
    rowwise <- dplyr::nest_by(grouped, .keep = TRUE)
    expect_s3_class(rowwise, "rowwise_df")
    expect_identical(dplyr::group_vars(rowwise), "g")
    expect_identical(lapply(rowwise$data, names), rep(list(c("g", "x")), 2L))
})

test_that("S7-C05 computed nesting keys use sequential Stata typing", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dibble(id = 1:2)
    for (verb in list(dplyr::group_nest, dplyr::nest_by)) {
        result <- verb(data, g = c(NA_character_, ""), observed = g == "")
        expect_identical(nrow(result), 1L)
        expect_identical(as.character(result$g), "")
        expect_identical(result$observed, TRUE)
        expect_identical(nrow(result$data[[1L]]), 2L)
    }
})

test_that("S7-C06 nested foreign writes cannot reach scalar constants or either source", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("callr")
    skip_if_not_installed("data.table")
    # Keep the historical singleton corruption inside disposable R children.
    for (verb in c("group_nest", "nest_by")) {
        primitive_record <- tempfile("nested-primitive-", fileext = ".txt")
        observed <- callr::r(function(library, primitive_record, verb) {
            .libPaths(library)
            library(dtatools)
            anchor <- .subset(c(TRUE, FALSE), 1L)
            false <- .subset(c(FALSE, TRUE), 1L)
            primitives <- function() c(as.integer(anchor), as.integer(false),
                as.integer(TRUE), as.integer(FALSE))
            before <- primitives()
            source <- dibble(g = c("a", "b"), flag = c(TRUE, FALSE))
            attr(source$flag, "label") <- "source"
            grouped <- dplyr::group_by(source, g)
            operation <- getExportedValue("dplyr", verb)
            nested <- operation(grouped)
            target <- nested$data[[1L]]
            data.table::set(target, i = 1L, j = "flag", value = FALSE)
            writeLines(as.character(c(before, primitives())), primitive_record)
            # Retain primitive evidence before any second operation. Character
            # dispatch avoids depending on a potentially damaged TRUE scalar.
            switch(paste0(primitives(), collapse = ""), "1010" = NULL,
                stop("Nested write changed a logical constant"))
            data.table::setattr(target$flag, "label", "result")
            first <- list(constants = primitives(), source = as.integer(source$flag),
                grouped = as.integer(grouped$flag), result = as.integer(target$flag),
                source_label = attr(grouped$flag, "label"), result_label = attr(target$flag, "label"))
            other <- operation(grouped)
            data.table::set(grouped, i = 2L, j = "flag", value = TRUE)
            data.table::setattr(grouped$flag, "label", "changed source")
            list(before = before, first = first,
                saved = as.integer(other$data[[2L]]$flag),
                saved_label = attr(other$data[[2L]]$flag, "label"),
                changed_source = as.integer(grouped$flag), changed_source_label = attr(grouped$flag, "label"),
                after = primitives())
        }, args = list(.libPaths(), primitive_record, verb), libpath = .libPaths())
        expect_identical(readLines(primitive_record), rep(c("1", "0", "1", "0"), 2L))
        expect_identical(observed, list(before = c(1L, 0L, 1L, 0L),
            first = list(constants = c(1L, 0L, 1L, 0L), source = c(1L, 0L),
                grouped = c(1L, 0L), result = 0L, source_label = "source", result_label = "result"),
            saved = 0L, saved_label = "source", changed_source = c(1L, 1L),
            changed_source_label = "changed source", after = c(1L, 0L, 1L, 0L)))
    }
})

test_that("S7-C07 nested frame capture retains containers, prototypes and reference objects", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("data.table")
    foreign <- data.table::data.table(x = c(TRUE, FALSE))
    attr(foreign$x, "label") <- "logical label"
    inner <- dibble(y = 1:2)
    alias <- inner
    environment <- new.env(parent = emptyenv())
    closure <- function() environment
    source <- dibble(id = 1L, payload = list(list(foreign, inner, environment, closure)))
    out <- dplyr::summarise(source, payload = payload)
    expect_s3_class(out$payload[[1L]][[1L]], "data.table")
    expect_true(is_dibble(out$payload[[1L]][[2L]]))
    expect_identical(out$payload[[1L]][[3L]], environment)
    expect_identical(out$payload[[1L]][[4L]], closure)
    data.table::set(foreign, i = 1L, j = "x", value = FALSE)
    repl(alias, y = 9L)
    expect_identical(out$payload[[1L]][[1L]]$x, structure(c(TRUE, FALSE), label = "logical label"))
    expect_identical(as.integer(out$payload[[1L]][[2L]]$y), 1:2)
    data.table::set(out$payload[[1L]][[1L]], i = 2L, j = "x", value = TRUE)
    repl(out$payload[[1L]][[2L]], y = 7L)
    expect_identical(as.integer(alias$y), c(9L, 9L))
    expect_identical(foreign$x, structure(c(FALSE, FALSE), label = "logical label"))
    empty <- dplyr::group_nest(dplyr::group_by(dibble(g = character(), x = integer()), g))
    expect_s3_class(empty$data, "vctrs_list_of")
    expect_identical(names(attr(empty$data, "ptype")), "x")
    expect_identical(nrow(attr(empty$data, "ptype")), 0L)
})

test_that("S7-C08 callback return capture happens before later callbacks mutate the same table", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("data.table")
    shared <- data.table::data.table(value = 0L)
    source <- dplyr::group_by(dibble(g = c("a", "b"), x = 1:2), g)
    result <- dplyr::group_modify(source, function(.x, .y) {
        data.table::set(shared, j = "value", value = as.integer(.x$x))
        tibble::tibble(nested = list(shared))
    })
    expect_identical(vapply(result$nested, function(x) x$value, integer(1)), 1:2)
    data.table::set(shared, j = "value", value = 8L)
    expect_identical(vapply(result$nested, function(x) x$value, integer(1)), 1:2)
})

test_that("S7-C09 callback data and fun arguments are forwarded without helper collisions", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (grouped in c(FALSE, TRUE)) {
        source <- dibble(g = c("a", "b"), x = 1:2)
        if (grouped) source <- dplyr::group_by(source, g)
        result <- dplyr::group_modify(source, function(.x, .y, data, fun) {
            tibble::tibble(value = fun(sum(.x$x), data))
        }, data = 10L, fun = `+`)
        expect_identical(as.integer(result$value), if (grouped) c(11L, 12L) else 13L)
    }
})

test_that("S7-C10 nested publication validates dibbles, reuses siblings and rejects cycles", {
    skip_if_not_installed("dplyr", "1.2.1")
    stale <- dibble(x = c("a", "b"))
    .Call(dtatools:::C_dtatools_set_data_column, stale, 1L,
        structure(c(NA_character_, "widened"), class = "dta_string", stata.string.storage = "str1"))
    result <- dplyr::summarise(dibble(id = 1L), nested = list(stale))
    expect_identical(as.character(result$nested[[1L]]$x), c("", "widened"))
    expect_identical(attr(result$nested[[1L]]$x, "stata.string.storage"), "str7")
    expect_true(dtatools:::.reference_state_valid(result$nested[[1L]]))
    expect_true(can_add_columns(result$nested[[1L]]))
    skip_if_not_installed("callr")
    # The unguarded candidate and plain upstream summary overflowed the C stack.
    # Keep this boundary isolated so a regression cannot end the entire suite.
    observed <- callr::r(function(libraries) {
        .libPaths(libraries); library(dtatools)
        cycle <- list(NULL)
        invisible(.Call(dtatools:::C_dtatools_set_data_column, cycle, 1L, cycle))
        message <- tryCatch({
            dplyr::summarise(dibble(id = 1L), nested = list(cycle))
            NULL
        }, error = function(e) conditionMessage(e))
        list(message = message,
            healthy = as.integer(dplyr::summarise(dibble(x = 1:2), value = sum(x))$value),
            constants = as.integer(c(TRUE, FALSE)))
    }, args = list(.libPaths()), libpath = .libPaths())
    expect_match(observed$message, "Cyclic nested list or data frame")
    expect_identical(observed$healthy, 3L)
    expect_identical(observed$constants, c(1L, 0L))
})

test_that("S7-C20 native nested capture reuses siblings", {
    shared <- list(value = 1L)
    captured <- dtatools:::.capture_dibble_nested(list(list(shared), list(shared)))
    expect_identical(rlang::obj_address(captured[[1L]][[1L]]),
        rlang::obj_address(captured[[2L]][[1L]]))
    expect_false(identical(rlang::obj_address(captured[[1L]][[1L]]), rlang::obj_address(shared)))
})

test_that("S7-C11 callbacks observe a fixed source generation across groups", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("data.table")
    source <- dplyr::group_by(dibble(g = c("a", "b"), x = 1:2), g)
    attr(source$x, "label") <- "original"
    seen <- list()
    result <- dplyr::group_modify(source, function(.x, .y) {
        seen[[length(seen) + 1L]] <<- .x
        if (as.character(.y$g) == "a") {
            data.table::setattr(source$x, "label", "changed")
            repl(source, x = 9L)
        }
        tibble::tibble(value = .x$x)
    })
    expect_identical(as.integer(result$value), 1:2)
    expect_identical(as.integer(seen[[2L]]$x), 2L)
    expect_identical(attr(seen[[2L]]$x, "label"), "original")
    expect_identical(as.integer(source$x), c(9L, 9L))
})

test_that("S7-C12 a zero-group prototype callback can produce padded key rows", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (size in 0:2) {
        source <- dplyr::group_by(dibble(g = character(), x = integer()), g)
        result <- dplyr::group_modify(source, function(.x, .y)
            tibble::tibble(z = seq_len(size)))
        expect_identical(as.character(result$g), rep("", size))
        expect_identical(as.integer(result$z), seq_len(size))
        expect_identical(dplyr::group_vars(result), "g")
    }
})

test_that("S7-C13 opaque pairlists and classed list slots retain representation", {
    skip_if_not_installed("dplyr", "1.2.1")
    pair <- pairlist(a = 1L, b = quote(x))
    classed <- structure(list(1L, 2L), class = "stage7_opaque_list", names = c("a", "b"))
    rlang::local_bindings(as.list.stage7_opaque_list = function(...) stop("must not dispatch"),
        .env = globalenv())
    array <- array(list(1L, NULL), c(1L, 2L))
    result <- dplyr::summarise(dibble(id = 1L), value = list(list(pair, classed, array)))
    expect_identical(result$value[[1L]][[1L]], pair)
    expect_identical(result$value[[1L]][[2L]], classed)
    expect_identical(result$value[[1L]][[3L]], array)
})

test_that("S7-C14 grouped chunks drop table metadata while whole-input nesting retains it", {
    skip_if_not_installed("dplyr", "1.2.1")
    source <- dibble(g = c("a", "b"), x = 1:2)
    attr(source, "label") <- "dataset"
    attr(source$x, "label") <- "variable"
    whole <- dplyr::group_nest(source)
    expect_identical(attr(whole$data[[1L]], "label"), "dataset")
    grouped <- dplyr::group_by(source, g)
    for (verb in list(dplyr::group_nest, dplyr::nest_by)) {
        result <- verb(grouped)
        expect_null(attr(result$data[[1L]], "label", exact = TRUE))
        expect_null(attr(attr(result$data, "ptype"), "label", exact = TRUE))
        expect_identical(attr(result$data[[1L]]$x, "label"), "variable")
    }
    seen <- list()
    dplyr::group_modify(grouped, function(.x, .y) {
        seen[[length(seen) + 1L]] <<- attributes(.x)
        tibble::tibble(x = sum(.x$x))
    })
    expect_true(all(vapply(seen, function(x) is.null(x$label), logical(1))))
})

test_that("S7-C15 plain and rowwise callback return policies preserve reference identity", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (rowwise in c(FALSE, TRUE)) for (form in c("null", "scalar", "list", "environment")) {
        data <- dibble(id = 1:2, x = 3:4)
        if (rowwise) data <- dplyr::rowwise(data, id)
        token <- new.env(parent = emptyenv())
        seen <- list()
        answer <- tryCatch(dplyr::group_modify(data, function(.x, .y, extra) {
            seen[[length(seen) + 1L]] <<- list(rows = nrow(.x), key_names = names(.y), extra = extra)
            switch(form, null = NULL, scalar = 7L, list = list(answer = 7L), environment = token)
        }, extra = "forwarded"), error = identity)
        expect_identical(seen, list(list(rows = 2L, key_names = if (rowwise) "id" else character(), extra = "forwarded")))
        switch(form, null = expect_null(answer), scalar = expect_identical(answer, 7L),
            environment = expect_identical(answer, token),
            list = {
                expect_s3_class(answer, "error")
                expect_match(conditionMessage(answer), "invalid reference generation row count", fixed = TRUE)
            })
    }
})

test_that("S7-C16 nesting preserves key policy, empty prototypes and unforced grouped dots", {
    skip_if_not_installed("dplyr", "1.2.1")
    data <- dplyr::group_by(dibble(g = c("b", "a"), x = 1:2), g)
    for (verb in list(dplyr::group_nest, dplyr::nest_by)) {
        collision <- verb(data, .key = "g")
        expect_identical(names(collision), "g")
        expect_s3_class(collision$g, "vctrs_list_of")
        expect_identical(lapply(collision$g, names), list("x", "x"))
        expect_identical(names(verb(data, .key = NA_character_)), c("g", "NA"))
        expect_error(verb(data, .key = ""))
        expect_error(verb(data, .key = c("a", "b")))
        for (keep in c(FALSE, TRUE)) {
            empty <- dibble(g = character(), x = dta_double(numeric()))
            attr(empty$x, "label") <- "prototype variable"
            grouped <- dplyr::group_by(empty, g)
            result <- if (identical(verb, dplyr::group_nest)) verb(grouped, keep = keep) else verb(grouped, .keep = keep)
            prototype <- attr(result$data, "ptype", exact = TRUE)
            expect_identical(nrow(result), 0L)
            expect_s3_class(result$data, "vctrs_list_of")
            expect_identical(dim(prototype), c(0L, if (keep) 2L else 1L))
            expect_identical(names(prototype), if (keep) c("g", "x") else "x")
            expect_identical(attr(prototype$x, "label", exact = TRUE), "prototype variable")
            expect_identical(dta_storage_type(prototype$x), "double")
        }
    }
    events <- new.env(parent = emptyenv()); events$forced <- FALSE
    expect_warning(dplyr::group_nest(data, ignored = { events$forced <- TRUE; stop("forced ignored dot") }), "ignores")
    expect_false(events$forced)
    expect_error(dplyr::nest_by(data, ignored = { events$forced <- TRUE; stop("forced ignored dot") }), "re-group")
    expect_false(events$forced)
})

test_that('S7-C17 repeated nesting does not retain per-call address history', {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed('callr')
    observed <- callr::r(function(libraries) {
        .libPaths(libraries)
        library(dtatools)
        source <- dplyr::group_by(dibble(g = rep(seq_len(128L), each = 2L),
            x = seq_len(256L)), g)
        heap <- function() {
            gc(full = TRUE)
            gc(full = TRUE)[, 'used']
        }
        # Warm dispatch and prototype work before comparing live source/latest
        # checkpoints. Every call starts from the same original source.
        for (i in seq_len(5L)) output <- dplyr::group_nest(source)
        before <- heap()
        for (i in seq_len(100L)) output <- dplyr::group_nest(source)
        after <- heap()
        list(before = before, after = after, delta = after - before,
            source = as.integer(source$x), rows = nrow(output),
            values = unlist(lapply(output$data, function(chunk) as.integer(chunk$x)),
                use.names = FALSE), package = find.package('dtatools'))
    }, args = list(.libPaths()), libpath = .libPaths())
    expect_identical(observed$package, find.package('dtatools'))
    expect_identical(observed$source, seq_len(256L))
    expect_identical(observed$rows, 128L)
    expect_identical(observed$values, seq_len(256L))
    # This guards retained small objects, not cumulative allocation or RSS.
    # The budget allows fixed dispatch/measurement overhead after warming.
    expect_lt(unname(observed$delta[['Ncells']]), 1000)
})


test_that("S7-C18 nesting allocation scales with the number of groups", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not(capabilities("profmem"))
    output <- tempfile("nesting-scaling-")
    dir.create(output)
    on.exit(unlink(output, recursive = TRUE), add = TRUE)
    allocated <- numeric(2L)
    numeric_equal <- function(value, expected) {
        typeof(value) %in% c("integer", "double") &&
            identical(as.double(value), as.double(expected))
    }
    for (index in seq_along(allocated)) {
        groups <- c(1024L, 4096L)[[index]]
        input <- dibble(g = rep(seq_len(groups), each = 2L), x = seq_len(2L * groups))
        attr(input, "label") <- "High-cardinality nesting fixture"
        input <- dplyr::group_by(input, g)
        result <- dplyr::group_nest(input, keep = FALSE)
        expect_identical(nrow(result), groups)
        rm(result)
        invisible(gc())
        path <- file.path(output, paste0(groups, "-Rprofmem.log"))
        Rprofmem(path)
        result <- tryCatch(dplyr::group_nest(input, keep = FALSE),
            finally = Rprofmem(NULL))
        expect_identical(nrow(result), groups)
        expect_true(numeric_equal(input$g, rep(seq_len(groups), each = 2L)))
        expect_true(numeric_equal(input$x, seq_len(2L * groups)))
        expect_true(numeric_equal(result$g, seq_len(groups)))
        expect_true(all(vapply(seq_len(groups), function(i) {
            numeric_equal(result$data[[i]]$x, seq.int(2L * i - 1L, 2L * i))
        }, logical(1))))
        lines <- readLines(path, warn = FALSE)
        records <- grepl("^[0-9]+ :", lines)
        expect_true(all(records | grepl("^new page:", lines)))
        allocated[[index]] <- sum(as.numeric(sub(" .*", "", lines[records])))
        rm(result, input)
        invisible(gc())
    }
    # Four times as many two-row groups must not restore the former ~15-fold
    # allocation growth. This is a cumulative R-allocation gate, not a timer.
    expect_gt(allocated[[1L]], 0)
    expect_lte(allocated[[2L]], 6 * allocated[[1L]])
})

test_that("S7-C19 nested capture preserves physical sibling identities after GC", {
    capture <- get(".capture_dibble_nested", asNamespace("dtatools"))
    atomic <- structure(c(1, 2), label = "shared atomic")
    other <- structure(c(1, 2), label = "shared atomic")
    owned <- .subset2(dibble(x = c(TRUE, FALSE)), 1L)
    shared <- list(atomic, owned)
    input <- list(atomic, atomic, other, owned, owned, shared, list(shared))
    result <- capture(input)
    same <- function(i, j) identical(rlang::obj_address(result[[i]]),
        rlang::obj_address(result[[j]]))
    expect_true(same(1L, 2L))
    expect_false(same(1L, 3L))
    expect_true(same(4L, 5L))
    expect_identical(rlang::obj_address(result[[6L]]),
        rlang::obj_address(result[[7L]][[1L]]))
    expect_false(identical(rlang::obj_address(result[[6L]]), rlang::obj_address(shared)))
    rm(input, atomic, other, owned, shared)
    invisible(gc())
    expect_identical(result[[1L]], structure(c(1, 2), label = "shared atomic"))
    expect_identical(as.logical(result[[4L]]), c(TRUE, FALSE))
    expect_identical(result[[6L]][[1L]], result[[1L]])
    expect_identical(as.logical(result[[7L]][[1L]][[2L]]), c(TRUE, FALSE))
})
