# New Stage8 regression fixtures; join policy follows the pinned dplyr sources
# documented in installed NOTICE. Expected row indices below are independent.

test_that("J11 ordinary reference frames retain their next-method routes", {
    skip_if_not_installed("dplyr", "1.2.1")
    make_reference <- function() {
        value <- reserve_columns(data.frame(k = 1:2, value = c(10, NA_real_)))
        dtatools:::.mark_reference_data(value,
            dtatools:::.new_reference_state(value, dibble = FALSE))
    }
    for (verb in c("inner", "left", "right", "full", "semi", "anti", "cross", "nest")) {
        x <- make_reference()
        expect_false(is_dibble(x))
        expect_true(inherits(x, "dtatools_ref_data"))
        expect_true(dtatools:::.reference_state_valid(x))
        y <- data.frame(k = c(2L, 3L), other = c(20, 30))
        fn <- getExportedValue("dplyr", paste0(verb, "_join"))
        arguments <- if (verb == "cross") list() else list(by = "k")
        if (verb == "nest") arguments$name <- "matches"
        plain <- dtatools:::.reference_snapshot(x)
        expected <- do.call(fn, c(list(plain, y), arguments))
        out <- do.call(fn, c(list(x, y), arguments))
        expect_false(is_dibble(out))
        expect_identical(out, expected)
        expect_identical(dtatools:::.reference_snapshot(x), plain)
    }
    for (verb in c("insert", "append", "update", "patch", "upsert", "delete")) {
        x <- make_reference()
        y <- if (verb %in% c("insert", "append")) data.frame(k = 3L, value = 30) else
            if (verb == "delete") data.frame(k = 2L) else data.frame(k = 2L, value = 99)
        fn <- getExportedValue("dplyr", paste0("rows_", verb))
        arguments <- if (verb == "append") list() else list(by = "k")
        plain <- dtatools:::.reference_snapshot(x)
        expected <- do.call(fn, c(list(plain, y), arguments))
        out <- do.call(fn, c(list(x, y), arguments))
        expect_false(is_dibble(out))
        expect_identical(out, expected)
        expect_identical(dtatools:::.reference_snapshot(x), plain)
    }
})

test_that("J01 direct joins preserve duplicate expansion and unmatched order", {
    skip_if_not_installed("dplyr", "1.2.1")
    x <- dibble(k = c(2L, 1L, 2L, 3L), xid = 1:4)
    y <- dibble(k = c(2L, 4L, 2L), yid = 1:3)
    indices <- list(
        inner = list(x = c(1L, 1L, 3L, 3L), y = c(1L, 3L, 1L, 3L)),
        left = list(x = c(1L, 1L, 2L, 3L, 3L, 4L), y = c(1L, 3L, NA, 1L, 3L, NA)),
        right = list(x = c(1L, 1L, 3L, 3L, NA), y = c(1L, 3L, 1L, 3L, 2L)),
        full = list(x = c(1L, 1L, 2L, 3L, 3L, 4L, NA), y = c(1L, 3L, NA, 1L, 3L, NA, 2L)))
    for (name in names(indices)) {
        out <- getExportedValue("dplyr", paste0(name, "_join"))(x, y,
            by = "k", relationship = "many-to-many")
        expected <- indices[[name]]
        expect_true(is_dibble(out))
        expect_identical(as.double(out$xid), as.double(expected$x))
        expect_identical(as.double(out$yid), as.double(expected$y))
    }
    expect_identical(as.double(dplyr::semi_join(x, y, by = "k")$xid), c(1, 3))
    expect_identical(as.double(dplyr::anti_join(x, y, by = "k")$xid), c(2, 4))
    crossed <- dplyr::cross_join(x, y)
    expect_identical(as.double(crossed$xid), rep(as.double(1:4), each = 3L))
    expect_identical(as.double(crossed$yid), rep(as.double(1:3), times = 4L))
    nested <- dplyr::nest_join(x, y, by = "k", name = "matches")
    expect_identical(as.double(nested$xid), as.double(1:4))
    expect_identical(lapply(nested$matches, function(z) as.double(z$yid)),
        list(c(1, 3), double(), c(1, 3), double()))
    expect_true(all(vapply(nested$matches, is_dibble, logical(1))))
})

test_that("J07 join arguments keep public forcing and nesting names", {
    skip_if_not_installed("dplyr", "1.2.1")
    x <- dibble(k = 1:2, value = c(10, 20))
    right <- dibble(k = 1L, other = 30)
    nested <- dplyr::nest_join(x, right, by = "k")
    expect_identical(names(nested), c("k", "value", "right"))
    expect_identical(vapply(nested$right, nrow, integer(1)), c(1L, 0L))
    local({
        argument <- right
        result <- dplyr::nest_join(x, argument, by = "k")
        expect_identical(names(result), c("k", "value", "argument"))
    })
    for (name in c("inner", "left", "right", "full", "semi", "anti", "cross", "nest")) {
        fn <- getExportedValue("dplyr", paste0(name, "_join"))
        forced <- FALSE
        expect_error(fn(x, { forced <- TRUE; right }, unused = 1), class = "rlib_error_dots_nonempty")
        expect_false(forced)
    }
    trace <- function(input) {
        events <- character()
        mark <- function(name, value) { events <<- c(events, name); value }
        result <- dplyr::left_join(input, mark("y", right),
            by = mark("by", "k"), copy = mark("copy", FALSE),
            suffix = mark("suffix", c(".x", ".y")), keep = mark("keep", NULL),
            na_matches = mark("na", "na"), multiple = mark("multiple", "all"),
            unmatched = mark("unmatched", "drop"), relationship = mark("relationship", NULL))
        list(events = events, names = names(result), value = as.double(result$value))
    }
    expect_identical(trace(x), trace(dtatools:::.reference_snapshot(x)))
})

test_that("J08 foreign join conversion runs once and preserves its conditions", {
    skip_if_not_installed("dplyr", "1.2.1")
    method <- "as_tibble.stage8_installed_join_conversion"
    stopifnot(!exists(method, .GlobalEnv, inherits = FALSE))
    events <- character()
    assign(method, function(x, ..., .name_repair = "check_unique") {
        mode <- attr(x, "mode")
        events <<- c(events, mode)
        if (mode == "error") rlang::abort("join conversion sentinel", class = "stage8_join_conversion_error")
        if (mode == "warning") warning("join conversion warning", call. = FALSE)
        class(x) <- "data.frame"
        x$value <- x$value + 100L
        if (mode == "shrink") x <- x[1L, , drop = FALSE]
        tibble::as_tibble(x, ..., .name_repair = .name_repair)
    }, .GlobalEnv)
    on.exit(rm(list = method, envir = .GlobalEnv), add = TRUE)
    for (verb in c("left", "semi", "cross", "nest")) for (mode in c("transform", "shrink", "warning", "error")) {
        x <- dibble(k = 1:2, source = 3:4)
        y <- structure(data.frame(k = 1:2, value = 7:8),
            class = c("stage8_installed_join_conversion", "data.frame"), mode = mode)
        arguments <- list(x, y)
        if (verb != "cross") arguments$by <- "k"
        if (verb == "nest") arguments$name <- "matches"
        fn <- getExportedValue("dplyr", paste0(verb, "_join"))
        events <- character()
        if (mode == "error") {
            expect_error(do.call(fn, arguments), class = "stage8_join_conversion_error")
        } else {
            if (mode == "warning") expect_warning(out <- do.call(fn, arguments), "join conversion warning") else
                out <- do.call(fn, arguments)
            if (verb == "left") expect_identical(as.double(out$value), if (mode == "shrink") c(107, NA_real_) else c(107, 108))
            if (verb == "semi") expect_identical(as.double(out$source), if (mode == "shrink") 3 else c(3, 4))
            if (verb == "cross") expect_identical(as.double(out$value), if (mode == "shrink") c(107, 107) else c(107, 108, 107, 108))
            if (verb == "nest") expect_identical(lapply(out$matches, function(z) as.double(z$value)),
                if (mode == "shrink") list(107, double()) else list(107, 108))
        }
        expect_identical(events, mode)
        expect_identical(y$value, 7:8)
        expect_identical(as.double(x$source), c(3, 4))
    }
})

test_that("J09 nested join writes preserve sources siblings and scalar constants", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("callr")
    skip_if_not_installed("data.table")
    observed <- callr::r(function(libraries, expected_namespace) {
        .libPaths(libraries)
        library(dtatools)
        stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
            normalizePath(expected_namespace)))
        x <- dibble(k = c(1L, 1L, 2L), value = c(10, 20, 30))
        y <- dibble(k = 1L, flag = TRUE)
        out <- dplyr::nest_join(x, y, by = "k", name = "matches")
        first <- out$matches[[1L]]
        second <- out$matches[[2L]]
        data.table::set(first, i = 1L, j = "flag", value = FALSE)
        # Do no further join or write if a shared R scalar was corrupted.
        if (!identical(as.integer(TRUE), 1L) || !identical(as.integer(FALSE), 0L))
            stop("Nested join write changed a global logical constant")
        stopifnot(!first$flag[[1L]], second$flag[[1L]], y$flag[[1L]])
        data.table::setattr(first$flag, "label", "nested only")
        stopifnot(is.null(attr(second$flag, "label")), is.null(attr(y$flag, "label")))
        data.table::set(y, i = 1L, j = "flag", value = FALSE)
        if (!identical(as.integer(TRUE), 1L) || !identical(as.integer(FALSE), 0L))
            stop("Nested join source write changed a global logical constant")
        data.table::setattr(y$flag, "label", "source only")
        stopifnot(second$flag[[1L]], identical(attr(first$flag, "label"), "nested only"),
            is.null(attr(second$flag, "label")), !y$flag[[1L]],
            nrow(out$matches[[3L]]) == 0L)
        restored <- unserialize(serialize(out, NULL))
        stopifnot(restored$matches[[2L]]$flag[[1L]], !restored$matches[[1L]]$flag[[1L]],
            as.integer(TRUE) == 1L, as.integer(FALSE) == 0L)
        TRUE
    }, args = list(.libPaths(), getNamespaceInfo(asNamespace("dtatools"), "path")),
        libpath = .libPaths(), timeout = 120)
    expect_true(observed)
})

test_that("J02 named outer keys coalesce and string padding remains typed", {
    skip_if_not_installed("dplyr", "1.2.1")
    x <- dibble(left = dta_byte(c(2, 1)), text = dta_string(c("aa", "b"), "str2"))
    y <- dibble(right = dta_long(c(2, 300)), text = dta_string(c("c", "long"), "str4"))
    set_var_label(x, text, "left text")
    set_var_label(y, text, "right text")
    out <- dplyr::full_join(x, y, by = c(left = "right"), suffix = c("_x", "_y"))
    expect_identical(names(out), c("left", "text_x", "text_y"))
    expect_identical(as.double(out$left), c(2, 1, 300))
    expect_identical(as.character(out$text_x), c("aa", "b", ""))
    expect_identical(as.character(out$text_y), c("c", "", "long"))
    expect_identical(attr(out$text_x, "stata.string.storage"), "str2")
    expect_identical(attr(out$text_y, "stata.string.storage"), "str4")
    expect_identical(attr(out$text_x, "label"), "left text")
    expect_identical(attr(out$text_y, "label"), "right text")
    kept <- dplyr::full_join(x, y, by = c(left = "right"), keep = TRUE)
    expect_identical(as.double(kept$left), c(2, 1, NA_real_))
    expect_identical(as.double(kept$right), c(2, NA_real_, 300))
    expect_identical(as.double(x$left), c(2, 1))
    expect_identical(as.double(y$right), c(2, 300))
})

test_that("J03 typed join keys distinguish every Stata missing payload", {
    skip_if_not_installed("dplyr", "1.2.1")
    values <- c(1, NA_real_, vapply(letters, tagged_missing, double(1)))
    encode <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = "little")
    for (type in list(dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        x <- dibble(k = type(values), xid = seq_along(values))
        y <- dibble(k = type(rev(values)), yid = rev(seq_along(values)))
        for (policy in c("na", "never")) {
            out <- dplyr::left_join(x, y, by = "k", keep = TRUE,
                na_matches = policy, relationship = "many-to-many")
            expect_equal(nrow(out), 28L)
            expect_identical(as.double(out$xid), as.double(seq_along(values)))
            expect_identical(as.double(out$yid), as.double(seq_along(values)))
            expect_identical(encode(out$k.x), encode(x$k))
            expect_identical(encode(out$k.y), encode(x$k))
        }
    }
})

test_that("J04 interval and rolling joins honor pair predicates and filters", {
    skip_if_not_installed("dplyr", "1.2.1")
    x <- dibble(point = c(2L, 5L, 8L), xid = 1:3)
    y <- dibble(start = c(1L, 3L, 7L), end = c(3L, 6L, 9L), yid = 1:3)
    out <- dplyr::inner_join(x, y, dplyr::join_by(point >= start, point <= end))
    pairs <- do.call(rbind, lapply(seq_len(nrow(x)), function(i) {
        j <- which(as.double(y$start) <= as.double(x$point)[[i]] &
                   as.double(y$end) >= as.double(x$point)[[i]])
        cbind(x = rep(i, length(j)), y = j)
    }))
    expect_identical(as.double(out$xid), as.double(pairs[, "x"]))
    expect_identical(as.double(out$yid), as.double(pairs[, "y"]))
    rolled <- dplyr::left_join(x, y, dplyr::join_by(closest(point >= start)))
    expect_identical(as.double(rolled$yid), c(1, 2, 3))
    expect_error(dplyr::left_join(x, y, dplyr::join_by(point >= start), keep = FALSE),
        class = "rlang_error")
})

test_that("J05 default warnings and explicit relationship policies stay distinct", {
    skip_if_not_installed("dplyr", "1.2.1")
    x <- dibble(k = c(1L, 1L), xid = 1:2)
    y <- dibble(k = c(1L, 1L), yid = 1:2)
    expect_warning(dplyr::left_join(x, y, by = "k"),
        class = "dplyr_warning_join_relationship_many_to_many")
    expect_silent(dplyr::left_join(x, y, by = "k", relationship = "many-to-many"))
    expect_error(dplyr::left_join(x, y, by = "k", relationship = "one-to-one"),
        class = "dplyr_error_join_relationship_one_to_one")
    expect_identical(as.double(dplyr::left_join(x, y, by = "k", multiple = "first")$yid), c(1, 1))
    expect_identical(as.double(dplyr::left_join(x, y, by = "k", multiple = "last")$yid), c(2, 2))
    expect_error(dplyr::inner_join(dibble(k = 2L), dibble(k = 1L), by = "k", unmatched = "error"),
        class = "dplyr_error_join_matches_nothing")
})

test_that("J06 joined flat payload and labels remain isolated after later writes", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("data.table")
    snapshot <- function(column) {
        out <- numeric(length(column))
        for (i in seq_along(column)) out[[i]] <- as.double(column[[i]])
        out
    }
    for (verb in c("inner", "left", "right", "full", "semi", "anti", "cross")) {
        x <- dibble(k = c(1L, 2L), value = c(10, 20))
        y <- dibble(k = c(1L, 3L), other = c(30, 40))
        out <- if (verb == "cross") dplyr::cross_join(x, y) else
            getExportedValue("dplyr", paste0(verb, "_join"))(x, y, by = "k")
        original <- snapshot(out$value)
        data.table::set(out, i = 1L, j = "value", value = 99)
        data.table::setattr(out$value, "label", "result only")
        expect_identical(snapshot(out$value), replace(original, 1L, 99))
        expect_identical(snapshot(x$value), c(10, 20))
        expect_null(attr(x$value, "label"))
        protected <- snapshot(out$value)
        repl(x, value = 77, where = 1L)
        set_var_label(x, value, "source only")
        expect_identical(snapshot(x$value), c(77, 20))
        expect_identical(attr(x$value, "label"), "source only")
        expect_identical(snapshot(out$value), protected)
        expect_identical(attr(out$value, "label"), "result only")
        expect_identical(protected[-1L], original[-1L])
        if ("other" %in% names(out)) {
            other_before <- snapshot(out$other)
            data.table::set(out, i = 1L, j = "other", value = 88)
            data.table::setattr(out$other, "label", "right result only")
            expect_identical(snapshot(out$other), replace(other_before, 1L, 88))
            expect_identical(snapshot(y$other), c(30, 40))
            expect_null(attr(y$other, "label"))
            other_protected <- snapshot(out$other)
            repl(y, other = 66, where = 1L)
            set_var_label(y, other, "right source only")
            expect_identical(snapshot(y$other), c(66, 40))
            expect_identical(attr(y$other, "label"), "right source only")
            expect_identical(snapshot(out$other), other_protected)
            expect_identical(attr(out$other, "label"), "right result only")
        }
    }
})

# New package-owned regression. Public vctrs methods run in one disposable child;
# no methods or namespace bindings are installed in the parent test process.
test_that("J10 custom join keys retain public common-type cast and matching proxy dispatch", {
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("callr")
    observed <- callr::r(function(libraries, expected_namespace) {
        .libPaths(libraries)
        library(dtatools)
        stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
            normalizePath(expected_namespace)))
        events <- character()
        mark <- function(event) events <<- c(events, event)
        left <- function(x = double()) vctrs::new_vctr(x, class = "stage8_join_key_left")
        right <- function(x = double()) vctrs::new_vctr(x, class = "stage8_join_key_right")
        register <- function(generic, classes, method) {
            registerS3method(generic, classes, method, envir = asNamespace("vctrs"))
        }
        register("vec_ptype2", "stage8_join_key_left.stage8_join_key_left",
            function(x, y, ...) { mark("ptype-left"); left() })
        register("vec_ptype2", "stage8_join_key_left.stage8_join_key_right",
            function(x, y, ...) { mark("ptype-mixed"); left() })
        register("vec_ptype2", "stage8_join_key_right.stage8_join_key_left",
            function(x, y, ...) { mark("ptype-mixed"); left() })
        register("vec_ptype2", "stage8_join_key_right.stage8_join_key_right",
            function(x, y, ...) right())
        register("vec_cast", "stage8_join_key_left.stage8_join_key_left",
            function(x, to, ...) x)
        register("vec_cast", "stage8_join_key_left.stage8_join_key_right",
            function(x, to, ...) { mark("cast-right-left"); left(vctrs::vec_data(x) + 1) })
        register("vec_cast", "stage8_join_key_right.stage8_join_key_right",
            function(x, to, ...) x)
        register("vec_proxy_equal", "stage8_join_key_left",
            function(x, ...) { mark("proxy-equal"); floor(vctrs::vec_data(x) / 10) })
        register("vec_proxy_compare", "stage8_join_key_left",
            function(x, ...) { mark("proxy-compare"); floor(vctrs::vec_data(x) / 10) })
        x <- dibble(k = left(c(11, 12, 21)), xid = 1:3)
        y <- dibble(k = right(c(10, 20, 30)), yid = 1:3)
        stopifnot(inherits(x$k, "stage8_join_key_left"),
            inherits(y$k, "stage8_join_key_right"),
            identical(vctrs::vec_data(x$k), c(11, 12, 21)),
            identical(vctrs::vec_data(y$k), c(10, 20, 30)))
        records <- list()
        for (route in c("direct", "ordinary")) {
            a <- if (route == "direct") x else dtatools:::.reference_snapshot(x)
            b <- if (route == "direct") y else dtatools:::.reference_snapshot(y)
            for (verb in c("full", "semi")) {
                events <- character()
                out <- getExportedValue("dplyr", paste0(verb, "_join"))(a, b, by = "k")
                calls <- events # Retain dispatch facts before result inspection.
                records[[paste(route, verb)]] <- list(
                    events = calls, key_class = class(out$k), key = vctrs::vec_data(out$k),
                    xid = as.double(out$xid),
                    yid = if (verb == "full") as.double(out$yid) else NULL)
            }
        }
        stopifnot(identical(vctrs::vec_data(x$k), c(11, 12, 21)),
            identical(vctrs::vec_data(y$k), c(10, 20, 30)),
            inherits(x$k, "stage8_join_key_left"), inherits(y$k, "stage8_join_key_right"))
        list(records = records, source_class = class(x$k))
    }, args = list(.libPaths(), getNamespaceInfo(asNamespace("dtatools"), "path")),
        libpath = .libPaths(), timeout = 120)
    for (route in c("direct", "ordinary")) {
        full <- observed$records[[paste(route, "full")]]
        semi <- observed$records[[paste(route, "semi")]]
        expect_identical(full$xid, c(1, 2, 3, NA_real_))
        expect_identical(full$yid, c(1, 1, 2, 3))
        expect_identical(full$key, c(11, 12, 21, 31))
        expect_identical(semi$xid, c(1, 2, 3))
        expect_identical(semi$key, c(11, 12, 21))
        expect_identical(full$key_class, observed$source_class)
        expect_identical(semi$key_class, full$key_class)
        for (record in list(full, semi)) {
            expect_true(all(c("ptype-mixed", "cast-right-left") %in% record$events))
            expect_true(any(c("proxy-equal", "proxy-compare") %in% record$events))
        }
    }
})
