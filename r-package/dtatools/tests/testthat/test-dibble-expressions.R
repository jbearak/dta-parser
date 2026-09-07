# Helper and evaluation-order witnesses adapt dplyr 1.2.1 tests and the bounded
# Stage 5 helper proof. See inst/NOTICE for exact source and modifications.

expression_context_snapshot <- function() {
    context <- get("context_env", asNamespace("dplyr"))
    slots <- c("mask", "column", "across_if_fn", "across_frame")
    lapply(stats::setNames(slots, slots), function(name) {
        list(present = exists(name, context, inherits = FALSE),
             value = get0(name, context, inherits = FALSE))
    })
}

test_that("the core evaluator accepts ordinary quosures without whole verbs", {
    data <- dibble(id = 1:2)
    groups <- dtatools:::.dibble_expression_groups(data)
    plain <- list(run = function(mask, action) action(),
        reset_column = function() NULL, column = function(name) NULL,
        expand = function(quo, mask, name, index) list(list(
            quo = quo, name = name, named = TRUE, column = NULL)))
    result <- dtatools:::.dibble_evaluate_columns(
        dtatools:::.data_columns(data), groups, 2L,
        rlang::quos(y = c(NA_real_, 1), z = y > 0), adapter = plain)
    expect_identical(result$columns$z, c(TRUE, TRUE))
    expect_identical(result$modified, c("y", "z"))
    expect_identical(names(data), "id")
})

test_that("qualified and aliased helpers see original group rows and keys", {
    data <- dibble(g = c("b", "a", "b"), x = 1:3, y = 4:6)
    alias <- dplyr::n
    read_context <- function() list(n = alias(), id = dplyr::cur_group_id(),
        key = as.character(dplyr::cur_group()$g), rows = dplyr::cur_group_rows())
    for (by in c(FALSE, TRUE)) {
        input <- if (by) data else dplyr::group_by(data, g)
        result <- if (by) dplyr::mutate(input, ctx = list(read_context()), .by = g) else
            dplyr::mutate(input, ctx = list(read_context()))
        expect_identical(vapply(result$ctx, `[[`, integer(1), "n"), c(2L, 1L, 2L))
        expect_identical(vapply(result$ctx, `[[`, integer(1), "id"),
            if (by) c(1L, 2L, 1L) else c(2L, 1L, 2L))
        expect_identical(result$ctx[[1L]]$rows, c(1L, 3L))
        expect_identical(result$ctx[[2L]]$key, "a")
    }
    x <- 100L
    result <- dplyr::mutate(data, z = .data$x + .env$x + dplyr::n(), .by = g)
    expect_identical(as.double(result$z), c(103, 103, 105))
})

test_that("pick expansion and arbitrary fallback preserve selection rules", {
    data <- dplyr::group_by(dibble(g = c(1, 1, 2, 2),
        x = c(0, 0, 1, 1), y = c(1, 1, 0, 0)), g)
    alias <- dplyr::pick
    expanded <- dplyr::mutate(data, picked = list(dplyr::pick(tidyselect::where(~ all(.x == 0)))))
    fallback <- dplyr::mutate(data, picked = list(alias(tidyselect::where(~ all(.x == 0)))))
    expect_identical(lapply(expanded$picked, names), rep(list(character()), 4L))
    expect_identical(lapply(fallback$picked, names), list("x", "x", "y", "y"))
    choice <- "y"
    for (q in list(rlang::quo({ choice <- "x"; dplyr::pick(tidyselect::all_of(choice)) }),
                   rlang::quo({ choice <- "x"; alias(tidyselect::all_of(choice)) }))) {
        result <- dplyr::mutate(data, picked = list(!!q))
        expect_identical(lapply(result$picked, names), rep(list("y"), 4L))
    }
    wrapper <- function(cols) dplyr::pick({{ cols }})
    result <- dplyr::mutate(data, selected = wrapper(x:y))
    expect_identical(names(result$selected), c("x", "y"))
    empty <- dplyr::mutate(data, selected = dplyr::pick(tidyselect::all_of(character())))
    expect_identical(dim(empty$selected), c(4L, 0L))
})

test_that("across expansion counts and side effects follow real dplyr", {
    data <- dplyr::group_by(dibble(g = c(1, 1, 2), x = 1:3, y = 4:6), g)
    alias <- dplyr::across
    for (mode in c("expanded", "aliased", "named", "unpacked")) {
        setup <- 0L
        events <- character()
        factory <- function() {
            setup <<- setup + 1L
            function(value) {
                events <<- c(events, paste(dplyr::cur_column(), dplyr::cur_group_id(), sep = ":"))
                if (mode == "unpacked") tibble::tibble(value = value) else value
            }
        }
        result <- switch(mode,
            expanded = dplyr::mutate(data, dplyr::across(x:y, factory())),
            aliased = dplyr::mutate(data, alias(x:y, factory())),
            named = dplyr::mutate(data, cols = dplyr::across(x:y, factory())),
            unpacked = dplyr::mutate(data, dplyr::across(x:y, factory(), .unpack = TRUE)))
        expect_true(is_dibble(result))
        expect_identical(setup, if (mode == "expanded") 1L else 4L)
        expect_identical(events, if (mode == "expanded") c("x:1", "x:2", "y:1", "y:2") else
            c("x:1", "y:1", "x:2", "y:2"))
    }
    # Ingest only after every expanded result has evaluated against old x.
    result <- dplyr::mutate(data, dplyr::across(x:y, ~ .x + x))
    expect_identical(as.double(result$x), c(2, 4, 6))
    expect_identical(as.double(result$y), c(5, 7, 9))
    expect_error(dplyr::mutate(data, dplyr::across(x, identity), z = dplyr::cur_column()),
                 "Must only be used inside")
})

test_that("across fallback supports dots unpacking and logical helpers", {
    data <- dplyr::group_by(dibble(g = c(1, 1, 2), x = 1:3, y = 4:6), g)
    count <- 0L
    amount <- function() { count <<- count + 1L; 10L }
    result <- suppressWarnings(dplyr::mutate(data, dplyr::across(x:y,
        function(value, add) value + add, add = amount())))
    expect_identical(count, 2L)
    expect_identical(as.double(result$x), c(11, 12, 13))
    unpacked <- dplyr::mutate(data, dplyr::across(x:y,
        ~ tibble::tibble(value = .x, n = dplyr::n()), .unpack = TRUE))
    expect_identical(names(unpacked), c("g", "x", "y", "x_value", "x_n", "y_value", "y_n"))
    expect_identical(as.integer(unpacked$x_n), c(2L, 2L, 1L))
    helper <- function() dplyr::if_any(x:y, ~ .x > 3)
    logical <- dplyr::mutate(data, any = helper(), all = dplyr::if_all(x:y, ~ .x > 0))
    expect_identical(logical$any, rep(TRUE, 3L))
    expect_identical(logical$all, rep(TRUE, 3L))
})

test_that("nested verbs and failures restore every helper context binding", {
    data <- dplyr::group_by(dibble(g = c(1, 1, 2), x = 1:3), g)
    real <- dplyr::group_by(tibble::tibble(g = c(1, 2, 2), x = 4:6), g)
    check <- function(value, inner) {
        before <- expression_context_snapshot()
        n <- dplyr::n(); id <- dplyr::cur_group_id(); column <- dplyr::cur_column()
        dplyr::mutate(inner, y = dplyr::n() + dplyr::cur_group_id())
        expect_identical(dplyr::n(), n)
        expect_identical(dplyr::cur_group_id(), id)
        expect_identical(dplyr::cur_column(), column)
        expect_error(dplyr::mutate(data, y = stop("inner failure")), "inner failure")
        expect_identical(expression_context_snapshot(), before)
        value
    }
    dplyr::mutate(data, dplyr::across(x, ~ check(.x, real)))
    dplyr::mutate(real, dplyr::across(x, ~ check(.x, data)))
    before <- expression_context_snapshot()
    interrupt <- structure(list(message = "test interrupt", call = NULL), class = c("interrupt", "condition"))
    caught <- tryCatch(dplyr::mutate(data, y = stop(interrupt)), interrupt = identity)
    expect_s3_class(caught, "interrupt")
    expect_identical(expression_context_snapshot(), before)
    expect_error(dplyr::n(), "Must only be used")
})

test_that("captures retain earlier values while deferred column resolution expires", {
    data <- dplyr::group_by(dibble(g = c(2, 1, 2), x = c(10, 20, 30)), g)
    saved <- list(); closures <- list(); pronouns <- list(); quosures <- list()
    late <- new.env(parent = emptyenv())
    save_promise <- function(value, name) {
        delayedAssign(name, value, eval.env = environment(), assign.env = late)
        0L
    }
    result <- dplyr::mutate(data, y = {
        i <- dplyr::cur_group_id()
        saved[[i]] <<- x
        closures[[i]] <<- function() x
        pronouns[[i]] <<- .data
        quosures[[i]] <<- rlang::quo(x)
        save_promise(x, paste0("g", i))
        x
    }, x = x + 100)
    expect_identical(lapply(saved, as.double), list(20, c(10, 30)))
    for (i in seq_along(saved)) {
        expect_error(suppressWarnings(closures[[i]]()), "Obsolete data mask")
        expect_error(suppressWarnings(pronouns[[i]]$x), "Obsolete data mask")
        expect_error(suppressWarnings(rlang::eval_tidy(quosures[[i]])), "Obsolete data mask")
        expect_error(suppressWarnings(get(paste0("g", i), late)), "Obsolete data mask")
    }
    repl(result, y = 999, where = 1L)
    repl(data, x = 888, where = 1L)
    expect_identical(lapply(saved, as.double), list(20, c(10, 30)))
    expect_identical(as.double(result$x), c(110, 120, 130))
})

test_that("mask snapshots survive explicit writes inside arbitrary helpers", {
    data <- dibble(x = c(1, 2), y = c(3, 4))
    write_source <- function(pronoun) {
        repl(data, y = 99, where = 1L)
        pronoun$y
    }
    out <- dplyr::mutate(data, z = write_source(.data))
    expect_identical(as.double(out$z), c(3, 4))
    expect_identical(as.double(out$y), c(3, 4))
    expect_identical(as.double(data$y), c(99, 4))
    read_name <- function(pronoun) pronoun[["y"]]
    out <- dplyr::mutate(data, z = read_name(.data), .keep = "used")
    expect_identical(names(out), c("y", "z"))
})

test_that("foreign callback values are captured before the next group", {
    skip_if_not_installed("data.table")
    foreign <- data.table::data.table(x = c(1, 2), s = c("a", "b"))
    data <- dplyr::group_by(dibble(g = c(1, 1, 2, 2)), g)
    take <- function() {
        if (dplyr::cur_group_id() == 2L) data.table::set(foreign, i = 1L, j = "x", value = 99)
        foreign$x
    }
    out <- dplyr::mutate(data, x = take())
    expect_identical(as.double(out$x), c(1, 2, 99, 2))
    data.table::set(foreign, i = 2L, j = "x", value = 88)
    expect_identical(as.double(out$x), c(1, 2, 99, 2))
})

test_that("empty groups and empty rowwise list prototypes remain observable", {
    for (input in list(dibble(x = integer()),
                       dplyr::group_by(dibble(g = character(), x = integer()), g),
                       dplyr::rowwise(dibble(x = integer())))) {
        seen <- list()
        out <- dplyr::mutate(input, y = { seen[[length(seen) + 1L]] <<- dplyr::n(); 1L })
        expect_identical(nrow(out), 0L)
        expect_identical(seen, list(0L))
    }
    input <- dplyr::group_by(dibble(g = factor("a", levels = c("a", "b")), x = 1L), g, .drop = FALSE)
    seen <- integer()
    out <- dplyr::mutate(input, y = { seen <<- c(seen, dplyr::n()); 2L })
    expect_identical(seen, c(1L, 0L))
    expect_identical(lengths(dplyr::group_rows(out)), c(1L, 0L))
    for (column in list(list(), vctrs::new_list_of(list(), ptype = integer()))) {
        seen <- NULL
        input <- dplyr::rowwise(dibble(x = column))
        out <- dplyr::mutate(input, y = { seen <<- x; 0L })
        expect_identical(seen, if (inherits(column, "vctrs_list_of")) integer() else logical())
        expect_identical(nrow(out), 0L)
    }
    input <- dplyr::rowwise(dibble(id = 1:2, x = list(1:2, 3:5)), id)
    out <- dplyr::mutate(input, n = length(x), sum = sum(dplyr::c_across(x)))
    expect_identical(as.integer(out$n), c(2L, 3L))
    expect_identical(as.double(out$sum), c(3, 12))
    expect_error(dplyr::mutate(input, z = x), "must be size")
})

test_that("placement keep and transmute retain their separate column order", {
    data <- dibble(x = 1:3, y = 4:6, z = 7:9)
    expect_identical(names(dplyr::mutate(data, new = y + 1, .keep = "used", .before = x)), c("new", "y"))
    expect_identical(names(dplyr::mutate(data, new = y + 1, .keep = "unused")), c("x", "z", "new"))
    expect_identical(names(dplyr::mutate(data, new = y + 1, .keep = "none")), "new")
    expect_identical(names(dplyr::transmute(data, z, x)), c("z", "x"))
    expect_identical(names(dplyr::mutate(data, z, x, .keep = "none")), c("x", "z"))
    expect_identical(names(dplyr::mutate(data, y = NULL, y = 1)), c("x", "z", "y"))
    expect_error(dplyr::transmute(data, .keep = "all"), "not supported")
    expect_error(dplyr::mutate(data, new = 1, .before = x, .after = y), "both")
    grouped <- dplyr::group_by(data, y)
    expect_error(dplyr::mutate(grouped, z = 1, .by = x), "Can't supply")
})

test_that("computed grouping ignores old partitions and owns its metadata", {
    input <- dplyr::group_by(dibble(g = c("b", "a", "b"), x = c(10, 20, 30)), g)
    out <- dplyr::group_by(input, k = dplyr::n(), s = c(NA_character_, "", "a"), .add = TRUE)
    expect_identical(as.integer(out$k), rep(3L, 3L))
    expect_identical(as.character(out$s), c("", "", "a"))
    expect_identical(dplyr::group_vars(out), c("g", "k", "s"))
    expect_identical(dplyr::group_vars(dplyr::ungroup(out, k)), c("g", "s"))
    expect_identical(dplyr::group_vars(dplyr::ungroup(out)), character())
    expect_s3_class(dplyr::rowwise(input), "rowwise_df")
    expect_identical(dplyr::group_vars(dplyr::rowwise(input)), "g")
    expect_error(dplyr::rowwise(input, x), "Can't re-group")
    expect_error(dplyr::ungroup(dplyr::rowwise(input), x), "must be empty")
    repl(out, x = 999, where = 1L)
    expect_identical(as.double(input$x), c(10, 20, 30))
})


test_that("duplicate unpacked names and grouped warning aggregation retain their contracts", {
    data <- dibble(x = 1:3)
    result <- dplyr::mutate(data, tibble::new_tibble(list(a = 1:3, a = 4:6), nrow = 3L))
    expect_identical(as.integer(result$a), 4:6)
    grouped <- dplyr::group_by(data, x)
    warnings <- list()
    result <- withCallingHandlers(dplyr::mutate(grouped, y = { warning("sample"); x }),
        warning = function(condition) {
            warnings[[length(warnings) + 1L]] <<- condition
            invokeRestart("muffleWarning")
        })
    expect_length(warnings, 1L)
    expect_match(conditionMessage(warnings[[1L]]), "3 warnings")
    records <- utils::tail(dplyr::last_dplyr_warnings(Inf), 3L)
    expect_length(records, 3L)
    expect_true(all(vapply(records, function(w) grepl("sample", conditionMessage(w)), logical(1))))
})


test_that("persistent grouping keys cannot be removed by mutation", {
    data <- dibble(g = c(1, 1, 2), x = 1:3)
    for (input in list(dplyr::group_by(data, g), dplyr::rowwise(data, g))) {
        expect_error(dplyr::mutate(input, g = NULL), "Grouping variables must remain")
        expect_error(dplyr::transmute(input, g = NULL, y = x), "Grouping variables must remain")
    }
    expect_identical(names(dplyr::mutate(data, g = NULL, .by = g)), "x")
})


test_that("symbol results preserve attributes and rowwise frame columns remain frames", {
    x <- dta_double(1:3)
    attr(x, "other") <- list(a = 1:3)
    data <- dplyr::group_by(dibble(g = c(1, 1, 2), x = x), g)
    result <- dplyr::mutate(data, y = x)
    expect_identical(attr(result$y, "other"), list(a = 1:3))
    input <- dplyr::rowwise(dibble(x = data.frame(a = 1:3, b = 4:6)))
    result <- dplyr::mutate(input, y = list(x), z = x, q = list(z))
    expect_identical(vapply(result$y, nrow, integer(1)), rep(1L, 3L))
    expect_identical(result$z, input$x)
    expect_identical(result$y, result$q)
})

test_that("diagnostics identify the actual expression entry point", {
    data <- dibble(x = 1:2)
    for (verb in list(dplyr::mutate, dplyr::transmute, dplyr::group_by)) {
        name <- if (identical(verb, dplyr::mutate)) "mutate()" else
            if (identical(verb, dplyr::transmute)) "transmute()" else "group_by()"
        condition <- rlang::catch_cnd(verb(data, y = stop("diagnostic")))
        expect_identical(condition$call, str2lang(name))
        expect_warning(verb(data, y = { warning("diagnostic"); 1 }), name, fixed = TRUE)
    }
})


test_that("within-call captures keep their original generation and group", {
    input <- dplyr::group_by(dibble(g = c(1, 1, 2, 2), x = c(1, 2, 3, 4)), g)
    closures <- list(); pronouns <- list(); quosures <- list()
    promises <- new.env(parent = emptyenv())
    capture <- function(value, key) {
        delayedAssign(key, value, eval.env = environment(), assign.env = promises)
        0
    }
    result <- dplyr::mutate(input, captured = {
        id <- dplyr::cur_group_id()
        closures[[id]] <<- function() x
        pronouns[[id]] <<- .data
        quosures[[id]] <<- rlang::quo(x)
        capture(x, paste0("g", id))
    }, x = x + 10, observed = {
        expect_identical(as.double(closures[[1L]]()), c(1, 2))
        expect_identical(as.double(pronouns[[1L]]$x), c(1, 2))
        expect_identical(as.double(rlang::eval_tidy(quosures[[1L]])), c(1, 2))
        expect_identical(as.double(get("g1", promises)), c(1, 2))
        sum(closures[[dplyr::cur_group_id()]]())
    })
    expect_identical(as.double(result$observed), c(3, 3, 7, 7))
    expect_error(closures[[1L]](), "Obsolete data mask")
    # This promise was forced during evaluation, so it now holds a saved value.
    expect_identical(as.double(get("g1", promises)), c(1, 2))
    expect_error(dplyr::ungroup(input, renamed = g), "Can't rename")
})


test_that("expired capture masks release source payloads on success and failure", {
    for (kind in c("closure", "pronoun", "quosure", "promise")) {
        for (fail in c(FALSE, TRUE)) {
            probe <- function() {
                sentinel <- new.env(parent = emptyenv())
                weak <- rlang::new_weakref(sentinel)
                x <- dta_double(1:3)
                attr(x, "capture_lifetime") <- sentinel
                groups <- list(rows = list(1:3), names = character(),
                    keys = tibble::new_tibble(list(), nrow = 1L), type = "ungrouped")
                mask <- dtatools:::.new_dibble_expression_mask(list(x = x), groups, 3L, "mutate()")
                if (kind == "promise") {
                    saved <- new.env(parent = emptyenv())
                    capture <- function(value) delayedAssign("value", value,
                        eval.env = environment(), assign.env = saved)
                    mask$evaluate(rlang::quo(capture(x)), 1L)
                    resolve <- function() saved$value
                } else {
                    q <- switch(kind, closure = rlang::quo(function() x),
                        pronoun = rlang::quo(.data), quosure = rlang::quo(rlang::quo(x)))
                    saved <- mask$evaluate(q, 1L)
                    resolve <- switch(kind, closure = saved,
                        pronoun = function() saved$x, quosure = function() rlang::eval_tidy(saved))
                }
                if (fail) expect_error(mask$evaluate(rlang::quo(stop("failure")), 1L), "failure")
                mask$forget()
                rm(sentinel, x, groups, mask)
                list(weak = weak, resolve = resolve)
            }
            out <- probe()
            invisible(gc()); invisible(gc())
            expect_null(rlang::wref_key(out$weak))
            expect_error(out$resolve(), "Obsolete data mask")
        }
    }
})


test_that("ungroup preserves raw row names on an already ungrouped dibble", {
    data <- dibble(x = 1:2)
    attr(data, "row.names") <- c("r1", "r2")
    result <- dplyr::ungroup(data)
    expect_identical(.row_names_info(result, 0L), c("r1", "r2"))
    expect_true(is_dibble(result))
    repl(result, x = 99, where = 1L)
    expect_identical(as.double(data$x), c(1, 2))
})


test_that("expired column promises retain repeated-resolution warnings", {
    data <- dplyr::group_by(dibble(g = 1:2, x = c(10, 20)), g)
    closures <- list()
    dplyr::mutate(data, y = {
        closures[[length(closures) + 1L]] <<- function() x
        0L
    })
    warnings <- character()
    observe <- function(fn) withCallingHandlers(tryCatch(fn(), error = identity),
        warning = function(condition) {
            warnings <<- c(warnings, conditionMessage(condition))
            invokeRestart("muffleWarning")
        })
    first <- observe(closures[[1L]])
    expect_length(warnings, 0L)
    second <- observe(closures[[2L]])
    expect_length(warnings, 1L)
    expect_match(warnings, "restarting interrupted promise evaluation", fixed = TRUE)
    expect_match(conditionMessage(first), "Obsolete data mask", fixed = TRUE)
    expect_match(conditionMessage(second), "Obsolete data mask", fixed = TRUE)
})

test_that("mutate preserves existing group order until a key changes", {
    data <- dplyr::group_by(dibble(g = c(1, 1, 2), x = 1:3), g)
    attr(data, "groups") <- attr(data, "groups")[2:1, ]
    original <- attr(data, "groups")
    result <- dplyr::mutate(data, first = dplyr::cur_group_id())
    expect_identical(attr(result, "groups"), original)
    result <- dplyr::mutate(result, second = dplyr::cur_group_id())
    expect_identical(as.double(result$first), c(2, 2, 1))
    expect_identical(as.double(result$second), c(2, 2, 1))
    expect_identical(attr(dplyr::transmute(data, y = x), "groups"), original)
    regrouped <- dplyr::mutate(data, g = g + 1)
    expect_identical(as.double(dplyr::group_keys(regrouped)$g), c(2, 3))
})
