test_that("replacement isolates unchanged columns and caller bindings", {
    replacements <- list(
        function(d) { d$x <- 4:6; d },
        function(d) { d[["x"]] <- 4:6; d },
        function(d) { d[1, "x"] <- 4L; d },
        function(d) { attr(d$x, "format.stata") <- "%18.0g"; d },
        function(d) { names(d)[1] <- "renamed"; d },
        function(d) { dimnames(d)[[2]][1] <- "renamed"; d },
        function(d) { row.names(d) <- letters[1:3]; d }
    )
    for (replace in replacements) {
        source <- dibble(x = 1:3, y = 11:13)
        before <- serialize(source, NULL)
        changed <- suppressWarnings(replace(source))
        expect_identical(serialize(source, NULL), before)
        alias <- changed
        repl(changed, y = 21L)
        expect_identical(as.integer(alias$y), rep(21L, 3))
        expect_identical(as.integer(source$y), 11:13)
        repl(source, y = 31L)
        expect_identical(as.integer(changed$y), rep(21L, 3))
        expect_true(is_dibble(changed))
    }
})

test_that("explicit helpers isolate distinct tables while preserving table and slot aliases", {
    factories <- list(
        function(x) dibble(x = x, selector = x),
        function(x) tibble::tibble(x = x, selector = x),
        function(x) data.frame(x = x, selector = x)
    )
    if (requireNamespace("data.table", quietly = TRUE)) {
        factories <- c(factories, list(function(x) {
            d <- data.table::data.table(x = x)
            # Set exactly the same vector in both physical slots.
            data.table::set(d, j = "selector", value = d$x)
            .Call(dtatools:::C_dtatools_set_data_column, d, 2L, d$x)
            d
        }))
    }
    for (factory in factories) {
        data <- factory(dta_int(c(2L, 1L, 1L)))
        alias <- data
        copied <- data
        attr(copied, "source") <- "copy"
        repl(data, x = 7, where = selector)
        expect_identical(as.integer(alias$x), c(7L, 7L, 1L))
        expect_identical(as.integer(alias$selector), c(7L, 7L, 1L))
        expect_identical(as.integer(copied$x), c(2L, 1L, 1L))
        repl(copied, x = 8L)
        expect_identical(as.integer(data$x), c(7L, 7L, 1L))
        expect_identical(as.integer(copied$selector), rep(8L, 3))
    }
})

test_that("base copies read physical columns and never rewrite source bookkeeping", {
    for (mutate_original in c(FALSE, TRUE)) {
        source <- dibble(x = 1:3, y = 11:13)
        original_state <- dtatools:::.reference_state(source)
        copied <- source
        attr(copied, "names") <- c("y", "x")
        expect_true(is_dibble(copied))
        expect_false(dtatools:::.reference_state_valid(copied))
        expect_true(dtatools:::.reference_state_valid(source))
        target <- if (mutate_original) source else copied
        other <- if (mutate_original) copied else source
        before <- serialize(other, NULL)
        repl(target, x = 99L)
        set_var_format(target, x, "%18.0g")
        expect_identical(as.integer(target$x), rep(99L, 3))
        expect_identical(as.integer(target$y), if (mutate_original) 11:13 else 1:3)
        expect_identical(serialize(other, NULL), before)
        expect_identical(original_state$physical_names, c("x", "y"))
        expect_null(original_state$object)
    }
    # Old serialized states had cached locations and owning back-pointers.
    old <- dibble(x = 1:3, y = 11:13)
    state <- dtatools:::.reference_state(old)
    state$locations <- list2env(list(x = 1L, y = 2L), parent = emptyenv())
    state$object <- old
    old <- unserialize(serialize(old, NULL))
    attr(old, "names") <- c("y", "x")
    repl(old, x = 99L)
    expect_identical(as.integer(old$x), rep(99L, 3))
    expect_identical(as.integer(old$y), 1:3)
})

test_that("assigned repair isolates serialized copies and restores growth aliases", {
    for (rds in c(FALSE, TRUE)) {
        source <- dibble(x = 1:3)
        copied <- source
        attr(copied, "source") <- "copy"
        pair <- list(source, copied)
        if (rds) {
            path <- tempfile(fileext = ".rds")
            saveRDS(pair, path)
            restored <- readRDS(path)
            unlink(path)
        } else restored <- unserialize(serialize(pair, NULL))
        expect_true(is_dibble(restored[[1L]]))
        expect_true(is_dibble(restored[[2L]]))
        expect_false(dtatools:::.reference_state_valid(restored[[2L]]))
        prepared <- reserve_columns(restored[[2L]], 2L)
        expect_true(dtatools:::.reference_state_valid(prepared))
        alias <- prepared
        gen(prepared, z = 7L)
        repl(prepared, x = 8L)
        expect_identical(names(alias), c("x", "z"))
        for (original in restored) {
            expect_identical(names(original), "x")
            expect_identical(as.integer(original$x), 1:3)
        }
        expect_identical(length(unclass(prepared)), 2L)
        expect_identical(attributes(prepared)$names, names(prepared))
    }
})

test_that("legacy generated columns can be explicitly replaced after preparation", {
    data <- dibble(x = 1:3)
    dtatools:::.append_generated_column(dtatools:::.reference_state(data),
                                      "y", dta_long(4:6))
    expect_warning(repl(data, y = 7L), "reallocation")
    expect_identical(as.integer(data$y), rep(7L, 3))
    expect_identical(length(unclass(data)), 2L)
})

test_that("preparation and ordinary metadata replacement preserve within-table aliases", {
    changes <- list(
        reserve_columns,
        function(d) { names(d) <- c("a", "b"); d },
        function(d) { dataset_label(d) <- "Survey"; d },
        function(d) { var_label(d) <- list(); d },
        function(d) { val_labels(d) <- list(); d }
    )
    for (change in changes) {
        column <- dta_long(1:3)
        source <- dibble(x = column, y = column)
        changed <- change(source)
        expect_true(is_dibble(changed))
        expect_identical(rlang::obj_address(changed[[1L]]),
                         rlang::obj_address(changed[[2L]]))
        name <- names(changed)[[1L]]
        repl(changed, .(name) := 8L)
        expect_identical(as.integer(changed[[2L]]), rep(8L, 3))
        expect_identical(as.integer(source$x), 1:3)
        expect_identical(as.integer(source$y), 1:3)
    }
    for (clear in c(FALSE, TRUE)) {
        source <- dibble(x = 1:3, y = 11:13)
        changed <- source
        var_label(changed) <- if (clear) NULL else list(x = "X")
        val_labels(changed) <- if (clear) NULL else list(x = c(One = 1))
        expect_true(is_dibble(changed))
        repl(changed, y = 9L)
        expect_identical(as.integer(source$y), 11:13)
    }
})

test_that("all changed same-vector data.table columns invalidate lookup state", {
    skip_if_not_installed("data.table")
    for (fused in c(FALSE, TRUE)) {
        data <- data.table::data.table(x = 1:3, selector = 1:3)
        data.table::setkeyv(data, "selector")
        data.table::setindexv(data, "selector")
        column <- dta_long(1:3)
        .Call(dtatools:::C_dtatools_set_data_column, data, 1L, column)
        .Call(dtatools:::C_dtatools_set_data_column, data, 2L, column)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
        alias <- data
        copied <- copy_data(data)
        if (fused) repl(data, x = 3L, where = x == 1L) else repl(data, x = 3L, where = 1L)
        expect_identical(as.integer(alias$selector), c(3L, 2L, 3L))
        expect_null(data.table::key(data))
        expect_length(data.table::indices(data), 0L)
        expect_identical(as.integer(copied$selector), 1:3)
    }
})

test_that("promotion replaces its named column without promoting other slots", {
    column <- dta_byte(1:3)
    data <- dibble(x = column, y = column)
    alias <- data
    copied <- data
    attr(copied, "source") <- "copy"
    expect_message(repl(data, x = 1000L), "byte now int")
    expect_identical(as.integer(alias$x), rep(1000L, 3))
    expect_identical(dta_storage_type(data$x), "int")
    expect_identical(as.integer(data$y), 1:3)
    expect_identical(dta_storage_type(data$y), "byte")
    expect_identical(as.integer(copied$x), 1:3)
})

test_that("ordinary duplication of compact metadata wrappers keeps both sides compact", {
    skip_if_not_installed("data.table")
    numeric <- dtatools:::.metadata_copy(structure(dta_int(1:3), label = "Count"))
    copied <- data.table::copy(numeric)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(numeric))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(copied))
    expect_identical(attributes(copied), attributes(numeric))
    left <- data.frame(x = numeric)
    right <- data.frame(x = copied)
    repl(left, x = 9L)
    expect_identical(as.integer(right$x), 1:3)

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    source <- read_arrow(path, output = "tibble")
    set_var_label(source, text, "Text")
    column <- dtatools:::.metadata_copy(source$text)
    copied <- data.table::copy(column)
    expect_true(dtatools:::.is_unmaterialized_dictstring(column))
    expect_true(dtatools:::.is_unmaterialized_dictstring(copied))
    expect_identical(attributes(copied), attributes(column))
    left <- data.frame(text = column)
    right <- data.frame(text = copied)
    repl(left, text = "c", where = 1L)
    expect_identical(as.character(right$text), c("a", "b", "a"))
    expect_identical(as.character(source$text), c("a", "b", "a"))
})
