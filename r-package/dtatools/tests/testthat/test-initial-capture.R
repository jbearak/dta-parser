source(test_path("fixtures", "initial-capture-helpers.R"), local = TRUE)

.initial_capture_test_expected <- function() {
    .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
}

test_that("initial capture publishes wide owned and compact columns and declines narrow inputs early", {
    .initial_capture_test_warm()
    supported <- .initial_capture_test_expected()
    expect_identical(.initial_capture_test_call("C_dtatools_initial_capture_mode", NULL), 3L)
    for (width in c(2L, 63L, 64L, 100L, 128L, 129L, 144L, 256L)) {
        columns <- .initial_capture_test_columns(width)
        data <- do.call(dibble, columns)
        invisible(.initial_capture_test_counts(TRUE))
        context <- dtatools:::.begin_dibble_result(data, "mutate()", "columns")
        mask <- dtatools:::.new_dibble_expression_mask(
            context$columns, .initial_capture_test_groups(), 4L, "mutate()")
        counts <- .initial_capture_test_counts()
        values <- mask$values()
        mask$forget()
        shell <- as.double(supported && width >= 64L)
        batch <- as.double(supported && width > 128L)
        expect_identical(counts[["shell_admitted"]], shell, info = width)
        expect_identical(counts[["batch_admitted"]], batch, info = width)
        expect_identical(counts[["generations"]], batch * width, info = width)
        expect_identical(counts[["owned"]], batch * (width - 1L), info = width)
        expect_identical(counts[["compact"]], batch, info = width)
        expect_identical(lapply(values, as.double), lapply(columns, as.double), info = width)
        expect_identical(names(values), names(columns), info = width)
        if (width < 64L) {
            expect_identical(counts[["shape_decline"]], 2, info = width)
            expect_identical(counts[["frame_decline"]], 0, info = width)
            expect_identical(counts[["dependency_decline"]], 0, info = width)
        } else if (width <= 128L) {
            expect_identical(counts[["shape_decline"]], 1, info = width)
            expect_identical(counts[["frame_decline"]], 0, info = width)
            expect_identical(counts[["dependency_decline"]], 0, info = width)
        }
    }
})

test_that("bounded-width fallback matches the original R capture loop", {
    .initial_capture_test_warm()
    supported <- .initial_capture_test_expected()
    previous <- .initial_capture_test_call("C_dtatools_initial_capture_mode", NULL)
    on.exit(.initial_capture_test_call("C_dtatools_initial_capture_mode", previous))
    for (width in c(63L, 64L, 100L, 128L, 129L, 144L, 256L)) {
        columns <- .initial_capture_test_columns(width)
        data <- do.call(dibble, columns)
        run <- function(mode) {
            .initial_capture_test_call("C_dtatools_initial_capture_mode", mode)
            invisible(.initial_capture_test_counts(TRUE))
            context <- .begin_dibble_result(data, "mutate()", "columns")
            mask <- .new_dibble_expression_mask(
                context$columns, .initial_capture_test_groups(), 4L, "mutate()")
            values <- mask$values()
            mask$forget()
            list(values = values, counts = .initial_capture_test_counts())
        }
        enabled <- run(3L)
        fallback <- run(1L)
        info <- paste("width", width)
        expect_identical(enabled$values, fallback$values, info = info)
        expect_identical(lapply(enabled$values, attributes),
                         lapply(columns, attributes), info = info)
        expect_identical(enabled$counts[["shell_admitted"]],
                         as.double(supported && width >= 64L), info = info)
        admitted <- as.double(supported && width > 128L)
        expect_identical(enabled$counts[["batch_admitted"]], admitted, info = info)
        expect_identical(enabled$counts[["generations"]], admitted * width, info = info)
        expect_identical(fallback$counts[["batch_attempts"]], 0, info = info)
    }
})

test_that("initial capture preserves unknown operand forcing and original errors", {
    begin <- dtatools:::.begin_dibble_result
    for (width in c(63L, 64L)) {
        data <- do.call(dibble, .initial_capture_test_columns(width))
        events <- character()
        invisible(.initial_capture_test_counts(TRUE))
        observed <- begin({ events <- c(events, "call"); data }, "mutate()", "columns")
        expect_identical(events, "call")
        expect_identical(.initial_capture_test_counts()[["shell_admitted"]], 0)
        expect_identical(.initial_capture_test_counts()[["shape_decline"]], 1)
        expect_identical(lapply(observed$columns, as.double), lapply(data, as.double))
        env <- new.env(parent = environment())
        makeActiveBinding("operand", function() { events <<- c(events, "active"); data }, env)
        events <- character()
        invisible(.initial_capture_test_counts(TRUE))
        observed <- eval(quote(begin(operand, "mutate()", "columns")), env)
        expect_identical(events, "active")
        expect_identical(.initial_capture_test_counts()[["shell_admitted"]], 0)
        expect_identical(lapply(observed$columns, as.double), lapply(data, as.double))
        missing <- function(data) begin(data, "mutate()", "columns")
        recursive <- function(data = data) begin(data, "mutate()", "columns")
        expect_error(missing(), "missing")
        expect_error(recursive(), "promise already under evaluation")
    }
})

test_that("initial capture retains replaced and executable traced helper callbacks", {
    .initial_capture_test_warm()
    columns <- .initial_capture_test_columns()
    data <- do.call(dibble, columns)
    ns <- asNamespace("dtatools")
    targets <- c(.data_columns = "shell", .capture_dibble_nested = "batch",
                 .metadata_copy = "batch", new_weakref = "batch")
    for (helper in names(targets)) for (mode in c("replace", "trace")) {
        where <- if (helper == "new_weakref") asNamespace("rlang") else ns
        original <- get(helper, where)
        hits <- 0L
        if (mode == "replace") .initial_capture_test_set(where, helper, function(...) {
            hits <<- hits + 1L
            original(...)
        }) else trace(helper, tracer = function() hits <<- hits + 1L, where = where, print = FALSE)
        observed <- tryCatch({
            invisible(.initial_capture_test_counts(TRUE))
            value <- .initial_capture_test_run(targets[[helper]], columns, data)
            list(value = value, counts = .initial_capture_test_counts(), hits = hits)
        }, finally = .initial_capture_test_set(where, helper, original))
        info <- paste(helper, mode)
        expect_true(observed$hits > 0L, info = info)
        expect_identical(observed$counts[[paste0(targets[[helper]], "_admitted")]], 0, info = info)
        expect_identical(lapply(observed$value, as.double), lapply(columns, as.double), info = info)
    }
})

test_that("bounded-width fallback retains current helper callbacks", {
    .initial_capture_test_warm()
    columns <- .initial_capture_test_columns(100L)
    data <- do.call(dibble, columns)
    ns <- asNamespace("dtatools")
    name <- ".capture_dibble_nested"
    original <- get(name, ns)
    previous <- .initial_capture_test_call("C_dtatools_initial_capture_mode", NULL)
    on.exit(.initial_capture_test_call("C_dtatools_initial_capture_mode", previous))
    for (kind in c("replace", "trace")) {
        hits <- 0L
        if (kind == "replace") .initial_capture_test_set(ns, name, function(...) {
            hits <<- hits + 1L
            original(...)
        }) else trace(name, tracer = function() hits <<- hits + 1L,
                     where = ns, print = FALSE)
        observed <- tryCatch({
            lapply(c(3L, 1L), function(mode) {
                .initial_capture_test_call("C_dtatools_initial_capture_mode", mode)
                invisible(.initial_capture_test_counts(TRUE))
                before <- hits
                values <- .initial_capture_test_run("batch", columns, data)
                list(values = values, hits = hits - before,
                     counts = .initial_capture_test_counts())
            })
        }, finally = .initial_capture_test_set(ns, name, original))
        expect_identical(observed[[1L]]$values, observed[[2L]]$values, info = kind)
        expect_true(observed[[1L]]$hits > 0L, info = kind)
        expect_identical(observed[[1L]]$hits, observed[[2L]]$hits, info = kind)
        expect_identical(observed[[1L]]$counts[["batch_admitted"]], 0, info = kind)
        expect_identical(observed[[1L]]$counts[["shape_decline"]], 1, info = kind)
    }
})

test_that("initial capture qualifies executing constructors after recompilation and self-untracing", {
    columns <- .initial_capture_test_columns()
    data <- do.call(dibble, columns)
    ns <- asNamespace("dtatools")
    for (route in c("shell", "batch")) for (mode in c("body", "optimize0", "self-untrace")) {
        name <- if (route == "shell") ".begin_dibble_result" else ".new_dibble_expression_mask"
        original <- get(name, ns)
        retained <- new.env(parent = emptyenv())
        retained$frame <- NULL
        if (mode == "self-untrace") {
            tracer <- substitute({
                assign("frame", environment(), envir = RETAINED)
                untrace(NAME, where = NS)
            }, list(RETAINED = retained, NAME = name, NS = ns))
            trace(name, tracer = tracer, where = ns, print = FALSE)
        } else {
            changed <- original
            body(changed) <- body(changed)
            if (mode == "optimize0") changed <- compiler::cmpfun(changed, options = list(optimize = 0L))
            .initial_capture_test_set(ns, name, changed)
        }
        observed <- tryCatch({
            invisible(.initial_capture_test_counts(TRUE))
            value <- .initial_capture_test_run(route, columns, data)
            list(value = value, counts = .initial_capture_test_counts())
        }, finally = .initial_capture_test_set(ns, name, original))
        info <- paste(route, mode)
        expect_identical(observed$counts[[paste0(route, "_admitted")]], 0, info = info)
        expect_identical(lapply(observed$value, as.double), lapply(columns, as.double), info = info)
        if (mode == "self-untrace") {
            expect_true(is.environment(retained$frame), info = info)
            if (route == "batch") {
                expect_identical(get("name", retained$frame), "g")
                expect_null(get("columns", retained$frame))
            } else expect_identical(names(get("columns", retained$frame)), names(columns))
        }
    }
})

test_that("initial capture isolates public results and retained generation registries", {
    .initial_capture_test_warm()
    columns <- .initial_capture_test_columns()
    columns[[2L]] <- columns[[1L]]
    data <- do.call(dibble, columns)
    invisible(.initial_capture_test_counts(TRUE))
    output <- dplyr::mutate(data, x = 3)
    counts <- .initial_capture_test_counts()
    expected <- as.double(.initial_capture_test_expected())
    expect_identical(counts[["shell_admitted"]], expected)
    expect_identical(counts[["batch_admitted"]], expected)
    expect_identical(as.double(data$x), as.double(1:4))
    repl(output, x = 999, where = 1L)
    expect_identical(as.double(data$x), as.double(1:4))
    repl(data, g = 777, where = 2L)
    expect_identical(as.double(output$g), as.double(1:4))

    mask <- dtatools:::.new_dibble_expression_mask(columns, .initial_capture_test_groups(), 4L, "mutate()")
    withr::defer(mask$forget())
    state <- get("state", environment(mask$evaluate))
    names_before <- paste0(names(columns))
    data.table::setattr(columns, "class", "data.frame")
    data.table::setnames(columns, paste0("renamed_", seq_along(columns)))
    expect_identical(state$names, names_before)
    expect_identical(names(state$current), names_before)
    expect_false(identical(rlang::obj_address(state$names), rlang::obj_address(names(state$current))))
    expect_false(identical(state$current$x, state$current$v1))
    values <- mask$values()
    expect_false(identical(rlang::obj_address(values$x), rlang::obj_address(values$v1)))
    saved <- mask$evaluate(rlang::quo(function() x), 1L)
    mask$add("x", .initial_capture_test_owned(11:14))
    expect_identical(as.double(saved()), as.double(1:2))
    mask$forget()
    expect_error(saved(), "Obsolete data mask", fixed = TRUE)
})

test_that("initial capture retains roots under forced GC and independent reentrant finalizers", {
    skip_if_not_installed("callr")
    helper <- normalizePath(test_path("fixtures", "initial-capture-helpers.R"))
    observed <- .dtatools_child_r("initial-capture-finalizers", function(libraries, helper) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        source(helper, local = TRUE)
        .initial_capture_test_warm()
        columns <- .initial_capture_test_columns()
        data <- do.call(dibble, columns)
        inner_columns <- .initial_capture_test_columns()
        groups <- .initial_capture_test_groups()
        constructor <- dtatools:::.new_dibble_expression_mask
        fired <- 0L
        inner_values <- inner_expiry <- NULL
        finalizer <- function(key) {
            fired <<- fired + 1L
            inner <- constructor(inner_columns, groups, 4L, "mutate()")
            saved <- inner$evaluate(rlang::quo(function() x), 1L)
            inner_values <<- lapply(inner$values(), as.double)
            inner$forget()
            inner_expiry <<- tryCatch(saved(), error = conditionMessage)
        }
        invisible(.initial_capture_test_counts(TRUE))
        token <- new.env(parent = emptyenv())
        reg.finalizer(token, finalizer, onexit = FALSE)
        rm(token)
        prior <- gctorture2(10L)
        on.exit(gctorture2(prior), add = TRUE)
        context <- dtatools:::.begin_dibble_result(data, "mutate()", "columns")
        outer <- constructor(columns, groups, 4L, "mutate()")
        gctorture2(prior)
        invisible(gc())
        counts <- .initial_capture_test_counts()
        state <- get("state", environment(outer$evaluate))
        rooted <- vapply(state$generations, function(ref) is.environment(rlang::wref_key(ref)), logical(1))
        values <- lapply(outer$values(), as.double)
        outer$forget()
        list(fired = fired, inner = inner_values, expiry = inner_expiry,
             outer = values, shell = lapply(context$columns, as.double),
             expected = lapply(columns, as.double), counts = counts, rooted = rooted)
    }, args = list(libraries = .libPaths(), helper = helper))
    expected <- as.double(.initial_capture_test_expected())
    expect_identical(observed$fired, 1L)
    expect_identical(observed$inner, observed$expected)
    expect_identical(observed$outer, observed$expected)
    expect_identical(observed$shell, observed$expected)
    expect_match(observed$expiry, "Obsolete data mask", fixed = TRUE)
    expect_identical(observed$rooted, rep(TRUE, 256L))
    expect_identical(observed$counts[["shell_admitted"]], expected)
    expect_identical(observed$counts[["batch_admitted"]], 2 * expected)
    expect_identical(observed$counts[["generations"]], 512 * expected)
})

test_that("initial capture leaves genuine database lookups on the original forcing path", {
    skip_if_not_installed("callr")
    helper <- normalizePath(test_path("fixtures", "initial-capture-helpers.R"))
    fixture <- normalizePath(test_path("fixtures", "initial-capture-userdb.c"))
    records <- .dtatools_child_r("initial-capture-userdb", function(libraries, helper, fixture) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        source(helper, local = TRUE)
        scratch <- tempfile("initial-capture-userdb-")
        dir.create(scratch)
        on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
        prior <- setwd(scratch)
        on.exit(setwd(prior), add = TRUE)
        stopifnot(file.copy(fixture, "initial-capture-userdb.c"))
        output <- system2(file.path(R.home("bin"), "R"),
                          c("CMD", "SHLIB", "initial-capture-userdb.c"), stdout = TRUE, stderr = TRUE)
        if (!is.null(attr(output, "status"))) stop(paste(output, collapse = "\n"))
        # The table finalizers point into this DLL; keep it loaded until exit.
        dyn.load(file.path(scratch, paste0("initial-capture-userdb", .Platform$dynlib.ext)))
        ns <- asNamespace("dtatools")
        run <- function(width, traced) {
            data <- do.call(dibble, .initial_capture_test_columns(width))
            pointer <- .Call("initial_capture_userdb_create", data)
            table_name <- paste("initial-capture-userdb", width, traced, sep = "-")
            database <- attach(pointer, name = table_name, warn.conflicts = FALSE)
            on.exit(detach(table_name, character.only = TRUE), add = TRUE)
            events <- character()
            original <- get(".begin_dibble_result", ns)
            if (traced) {
                entry <- function() {
                    events <<- c(events, "entry")
                    untrace(".begin_dibble_result", where = ns)
                }
                trace(".begin_dibble_result", tracer = as.call(list(entry)), where = ns, print = FALSE)
                on.exit(.initial_capture_test_set(ns, ".begin_dibble_result", original), add = TRUE)
            }
            scope <- new.env(parent = database)
            scope$begin <- get(".begin_dibble_result", ns)
            invisible(.Call("initial_capture_userdb_gets", pointer, TRUE))
            invisible(.initial_capture_test_counts(TRUE))
            result <- eval(quote(begin(operand, "mutate()", "columns")), scope)
            list(width = width, traced = traced, events = events,
                 gets = .Call("initial_capture_userdb_gets", pointer, FALSE),
                 counts = .initial_capture_test_counts(), values = lapply(result$columns, as.double),
                 expected = lapply(data, as.double))
        }
        records <- list()
        for (width in c(63L, 64L)) for (traced in c(FALSE, TRUE))
            records[[paste(width, traced)]] <- run(width, traced)
        records
    }, args = list(libraries = .libPaths(), helper = helper, fixture = fixture))
    expect_length(records, 4L)
    for (name in names(records)) {
        observed <- records[[name]]
        expect_identical(observed$gets, 1L, info = name)
        expect_identical(observed$events, if (observed$traced) "entry" else character(), info = name)
        expect_identical(observed$counts[["shell_admitted"]], 0, info = name)
        expect_identical(observed$counts[["shape_decline"]], 1, info = name)
        expect_identical(observed$counts[["frame_decline"]], 0, info = name)
        expect_identical(observed$counts[["dependency_decline"]], 0, info = name)
        expect_identical(observed$values, observed$expected, info = name)
    }
})

test_that("initial capture expected profiles remain independent of public source literal mutation", {
    skip_if_not_installed("callr")
    helper <- normalizePath(test_path("fixtures", "initial-capture-helpers.R"))
    observed <- .dtatools_child_r("initial-capture-literals", function(libraries, helper) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        source(helper, local = TRUE)
        .initial_capture_test_warm()
        ns <- asNamespace("dtatools")
        profile <- get(".initial_capture_profile", ns)
        columns <- .initial_capture_test_columns()
        data <- do.call(dibble, columns)
        run <- function(route) {
            if (route == "shell") return(dtatools:::.begin_dibble_result(
                data, "mutate()", "computed")$columns)
            .initial_capture_test_run(route, columns, data)
        }
        collect <- function(value) {
            if (is.character(value) && length(value)) return(list(value))
            out <- list()
            if (is.call(value) || is.expression(value) || is.pairlist(value))
                for (i in seq_along(value)) {
                    element <- tryCatch(value[[i]], error = function(e) NULL)
                    if (missing(element)) next
                    if (!identical(element, quote(expr = ))) out <- c(out, collect(element))
                }
            out
        }
        invisible(.initial_capture_test_counts(TRUE))
        for (route in c("shell", "batch")) run(route)
        positive <- .initial_capture_test_counts()
        records <- list()
        for (name in c(".begin_dibble_result", ".new_dibble_expression_mask", ".capture_dibble_nested")) {
            actual <- get(name, ns)
            literal <- collect(body(actual))[[1L]]
            old <- paste0(literal[[1L]])
            holder <- structure(list(value = literal), class = "data.frame",
                                row.names = .set_row_names(length(literal)))
            source_before <- serialize(body(actual), NULL)
            profile_before <- serialize(profile, NULL)
            route <- if (name == ".begin_dibble_result") "shell" else "batch"
            record <- tryCatch({
                data.table::set(holder, i = 1L, j = "value", value = paste0("changed_", old))
                changed <- !identical(source_before, serialize(body(actual), NULL))
                independent <- identical(profile_before, serialize(profile, NULL))
                invisible(.initial_capture_test_counts(TRUE))
                tryCatch(run(route), error = identity)
                list(changed = changed, independent = independent,
                     attempts = .initial_capture_test_counts()[[paste0(route, "_attempts")]],
                     admitted = .initial_capture_test_counts()[[paste0(route, "_admitted")]])
            }, finally = data.table::set(holder, i = 1L, j = "value", value = old))
            record$restored <- identical(source_before, serialize(body(actual), NULL))
            records[[name]] <- record
        }
        invisible(.initial_capture_test_counts(TRUE))
        for (route in c("shell", "batch")) run(route)
        list(positive = positive, records = records, restored = .initial_capture_test_counts())
    }, args = list(libraries = .libPaths(), helper = helper))
    expected <- as.double(.initial_capture_test_expected())
    for (route in c("shell", "batch")) {
        expect_identical(observed$positive[[paste0(route, "_admitted")]], expected, info = route)
        expect_identical(observed$restored[[paste0(route, "_admitted")]], expected, info = route)
    }
    expect_length(observed$records, 3L)
    for (name in names(observed$records)) {
        record <- observed$records[[name]]
        expect_true(record$changed, info = name)
        expect_true(record$independent, info = name)
        expect_true(record$restored, info = name)
        expect_identical(record$attempts, 1, info = name)
        expect_identical(record$admitted, 0, info = name)
    }
})
