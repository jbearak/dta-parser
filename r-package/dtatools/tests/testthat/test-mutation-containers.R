container_factories <- function() {
    result <- list(frame = data.frame, tibble = tibble::tibble, dibble = dibble)
    if (requireNamespace("data.table", quietly = TRUE,
                         versionCheck = list(op = ">=", version = "1.18.2.1"))) {
        result$table <- data.table::data.table
    }
    result
}

operations <- list(
    gen = function(d, touch) gen(d, y = !!touch(1L)),
    egen = function(d, touch) egen(d, y = dta_mean(x), where = touch(TRUE)),
    repl = function(d, touch) repl(d, x = !!touch(1L)),
    keep = function(d, touch) keep_vars(d, tidyselect::all_of(touch("x"))),
    drop = function(d, touch) drop_vars(d, tidyselect::all_of(touch("x"))),
    order = function(d, touch) order_vars(d, tidyselect::all_of(touch("x"))),
    rename = function(d, touch) rename_vars(d, .names = touch("z")),
    rows = function(d, touch) reorder_dta_rows(d, touch(3:1)),
    label = function(d, touch) set_var_label(d, .(touch("x")), touch("Label")),
    labels = function(d, touch) set_var_labels(d, x = touch("Label")),
    values = function(d, touch) set_val_labels(d, x = touch(c(One = 1))),
    format = function(d, touch) set_var_format(d, .(touch("x")), touch("%9.0g")),
    formats = function(d, touch) set_var_formats(d, x, touch("%9.0g")),
    metadata = function(d, touch) set_dta_metadata(d, source = touch("survey")),
    note = function(d, touch) set_dta_note(d, touch(1L), "note", variable = "x"),
    add_note = function(d, touch) add_dta_note(d, touch("note"), variable = "x"),
    drop_note = function(d, touch) drop_dta_notes(d, touch(1L), variable = "x"),
    number_note = function(d, touch) renumber_dta_notes(d, touch(2L), variable = "x"),
    char = function(d, touch) set_dta_characteristic(d, touch("source"), "survey", variable = "x"),
    drop_char = function(d, touch) drop_dta_characteristics(d, touch("source"), variable = "x"),
    reserve = function(d, touch) reserve_columns(d, touch(2)),
    capacity = function(d, touch) can_add_columns(d, touch(2)),
    copy = function(d, touch) copy_data(d)
)

test_that("every mutation helper rejects plain containers before evaluating arguments", {
    factories <- list(frame = data.frame, tibble = tibble::tibble)
    if (requireNamespace("data.table", quietly = TRUE,
                         versionCheck = list(op = ">=", version = "1.18.2.1"))) {
        factories$table <- data.table::data.table
    }
    for (make in factories) for (operation in operations) {
        d <- make(x = 1:3)
        alias <- d
        before <- serialize(d, NULL)
        effects <- 0L
        touch <- function(x) { effects <<- effects + 1L; x }
        expect_error(operation(d, touch), "must be a dibble")
        expect_identical(effects, 0L)
        expect_false(inherits(d, "dtatools_ref_data"))
        expect_identical(serialize(alias, NULL), before)
    }
})

test_that("explicit helper boundaries reject dibble subclasses before evaluating updates", {
    for (operation in operations) {
        d <- dibble(x = 1:3)
        class(d) <- c("custom_container", class(d))
        alias <- d
        before <- serialize(d, NULL)
        effects <- 0L
        touch <- function(x) { effects <<- effects + 1L; x }
        expect_error(operation(d, touch), "assign `data <- as_dibble\\(data\\)`")
        expect_identical(effects, 0L)
        expect_identical(serialize(alias, NULL), before)
    }
    d <- dibble(x = 1:3)
    class(d) <- c("custom_container", class(d))
    effects <- 0L
    name <- function() { effects <<- effects + 1L; "y" }
    expect_error(d[, .(name()) := 1], "as_dibble")
    expect_identical(effects, 0L)
    expect_identical(names(d), "x")
    assignment <- function() { effects <<- effects + 1L; quote(y := 1L) }
    run_assignment <- function() d[, !!assignment()]
    expect_error(run_assignment(), "as_dibble")
    expect_identical(effects, 0L)
})

test_that("a data.table carrying the dibble classes is rejected before any write", {
    skip_if_not_installed("data.table")
    hybrid <- data.table::as.data.table(data.frame(x = c(1, 2, 3)))
    data.table::setkey(hybrid, x)
    class(hybrid) <- c("dibble", "dtatools_ref_data", "data.table", "data.frame")
    expect_error(repl(hybrid, x, 0, where = 3L), "cannot be a data.table")
    expect_error(gen(hybrid, y = 1), "cannot be a data.table")
    expect_error(keep_vars(hybrid, x), "cannot be a data.table")
    expect_identical(as.double(.subset2(hybrid, "x")), c(1, 2, 3))
    expect_identical(names(hybrid), "x")
})

test_that("explicit conversion removes custom container classes in isolation", {
    for (make in container_factories()) {
        d <- make(x = 1:3, text = c("a", "b", "c"))
        class(d) <- c("custom_container", class(d))
        attr(d, "label") <- "Dataset"
        before <- serialize(d, NULL)
        converted <- as_dibble(d)
        expect_true(is_dibble(converted))
        expect_false(inherits(converted, "custom_container"))
        expect_true(can_add_columns(converted))
        expect_identical(dataset_label(converted), "Dataset")
        expect_s3_class(converted$x, "dta_numeric")
        expect_identical(attr(converted$text, "stata.string.storage"), "str1")
        repl(converted, x = 9L)
        gen(converted, added = 1L)
        expect_equal(as.integer(converted$x), rep(9L, 3))
        expect_identical(serialize(d, NULL), before)
    }
})

test_that("a dibble preserves existing column classes and true aliases", {
    d <- reserve_columns(dibble(
        x = 1:3, text = c("a", "b", "c"), flag = c(TRUE, FALSE, TRUE),
        factor = factor(c("a", "b", "a")), date = as.Date("2020-01-01") + 0:2,
        datetime = as.POSIXct("2020-01-01", tz = "UTC") + 0:2,
        owned = dta_byte(1:3)
    ), 2)
    classes <- lapply(d, class)
    container_class <- class(d)
    alias <- d
    gen(d, generated = .data$x + 1L)
    repl(d, x = 7L)
    set_var_format(d, text, "%8s")
    set_dta_note(d, 1L, "Checked", variable = "date")
    markers <- c("dtatools_ref_data", "dtatools_dta_metadata")
    expect_identical(setdiff(class(d), markers), setdiff(container_class, markers))
    expect_equal(as.integer(alias$x), rep(7L, 3))
    expect_equal(as.integer(alias$generated), 2:4)
    expect_identical(attr(alias$text, "format.stata"), "%8s")
    # The note marker supplies restoration dispatch without changing the
    # vector's existing Date or Stata temporal/storage classes.
    for (name in names(classes)) {
        expect_identical(setdiff(class(d[[name]]), "dtatools_dta_metadata_vector"),
                         setdiff(classes[[name]], "dtatools_dta_metadata_vector"))
    }
})

test_that("grouped and rowwise metadata writes preserve grouping", {
    for (rowwise in c(FALSE, TRUE)) {
        id <- paste0("g_112_i_typed", if (rowwise) "_rowwise" else "")
        d <- as_dibble(.group_fixture(id)$data)
        d <- reserve_columns(d, 3)
        alias <- d
        groups <- attr(d, "groups", exact = TRUE)
        set_var_format(d, .("x"), "%9.0g")
        set_var_label(d, x, "Value")
        set_val_labels(d, x = c(First = 1))
        set_dta_note(d, 1L, "Note", variable = "x")
        set_dta_characteristic(d, "source", "survey", variable = "x")
        expect_identical(attr(alias, "groups", exact = TRUE), groups)
        expect_identical(var_label(alias$x), "Value")
        expect_identical(dta_note(alias, 1L, "x"), "Note")
        expect_identical(dta_characteristic(alias, "source", "x"), "survey")
        copied <- copy_data(d)
        expect_identical(attr(copied, "groups", exact = TRUE), groups)
        for (operation in list(function() keep_vars(d, x), function() drop_vars(d, x),
            function() order_vars(d, x), function() rename_vars(d, y = x),
            function() reorder_dta_rows(d, 3:1))) {
            expect_error(operation(), "ungrouped")
        }
        if (rowwise) {
            expect_error(gen(d, y = 1L), "ungrouped")
            expect_error(egen(d, y = dta_mean(x)), "ungrouped")
            expect_error(repl(d, x = 2L), "ungrouped")
        } else {
            gen(d, size = .N)
            egen(d, average = dta_mean(x))
            repl(d, g = 1L)
            expect_equal(as.integer(alias$size), c(2L, 2L, 1L))
            expect_equal(as.numeric(alias$average), c(1.5, 1.5, 3))
            expect_identical(length(attr(alias, "groups", exact = TRUE)$.rows), 1L)
        }
        class(copied) <- c("custom_group", class(copied))
        converted <- as_dibble(copied)
        expect_false(inherits(converted, "custom_group"))
        expect_identical(attr(converted, "groups", exact = TRUE)$.rows, groups$.rows)
        expect_equal(as.integer(attr(converted, "groups", exact = TRUE)$g), as.integer(groups$g))
    }
})

test_that("malformed frames and grouping fail before metadata evaluation", {
    malformed <- list(
        structure(list(x = 1:3), class = "data.frame", row.names = 1:2),
        structure(list(x = 1:3, x = 1:3), class = "data.frame", row.names = 1:3)
    )
    grouped <- .group_fixture("g_112")$data
    attr(grouped, "groups")$.rows[[1L]] <- c(1L, 3L)
    malformed[[3L]] <- grouped
    partitioned <- .group_fixture("g_112")$data
    attr(partitioned, "groups")$.rows <- list(c(1L, 3L), 2L)
    malformed[[4L]] <- partitioned
    for (d in malformed) {
        before <- serialize(d, NULL)
        effects <- 0L
        expect_error(set_var_formats(d, x = { effects <- effects + 1L; "%9.0g" }))
        expect_identical(effects, 0L)
        expect_identical(serialize(d, NULL), before)
    }
})

test_that("dropping the last column keeps the dibble's public empty shape", {
    d <- reserve_columns(dibble(x = 1:3), 2)
    alias <- d
    drop_vars(d, x)
    expect_identical(nrow(alias), 3L)
    expect_identical(abs(.row_names_info(alias, 2L)), 3L)
    expect_identical(nrow(copy_data(d)), 3L)
    expect_identical(nrow(as_dibble(d)), 3L)
    expect_identical(nrow(unserialize(serialize(d, NULL))), 3L)
    gen(d, added = 1L)
    expect_identical(nrow(alias), 3L)
    expect_identical(length(alias$added), 3L)
})

test_that("ordinary dibble brackets keep omitted-column forms", {
    for (grouped in c(FALSE, TRUE)) {
        d <- dibble(g = c(1L, 1L, 2L), x = 1:3)
        if (grouped) d <- as_dibble(.group_fixture("g_112_i_typed")$data)
        for (result in list(d[], d[, ], d[, , drop = FALSE])) {
            expect_true(is_dibble(result))
            expect_equal(as.integer(result$x), 1:3)
        }
        for (result in list(d[1:2, ], d[1:2, , drop = FALSE])) {
            expect_true(is_dibble(result))
            expect_equal(as.integer(result$x), 1:2)
            if (grouped) expect_equal(as.integer(attr(result, "groups", exact = TRUE)$g), 1L)
        }
    }
})

test_that("duplicate grouped keys cannot split a logical group", {
    d <- as_dibble(.group_fixture("g_112_i_typed")$data)
    attr(d, "groups") <- tibble::new_tibble(list(g = c(1L, 1L, 2L),
        .rows = vctrs::list_of(1L, 2L, 3L)), nrow = 3L)
    alias <- d
    before <- serialize(d, NULL)
    effects <- 0L
    for (operation in list(
        function() gen(d, size = .N),
        function() egen(d, total = dta_total(x)),
        function() set_dta_metadata(d, source = { effects <<- effects + 1L; "survey" })
    )) expect_error(operation(), "duplicated grouping keys")
    expect_identical(effects, 0L)
    expect_identical(serialize(alias, NULL), before)
    attr(d, "groups") <- .group_fixture("g_112_i_typed")$groups
    d <- reserve_columns(d, 2)
    gen(d, size = .N)
    egen(d, total = dta_total(x))
    expect_equal(as.integer(d$size), c(2L, 2L, 1L))
    expect_equal(as.integer(d$total), c(3L, 3L, 3L))
})

test_that("grouping validation ignores label wrappers on keys and identifiers", {
    for (rowwise in c(FALSE, TRUE)) {
        d <- as_dibble(.group_fixture(if (rowwise) "g_112_i_typed_rowwise" else "g_112_i_typed")$data)
        d <- reserve_columns(d, 1)
        alias <- d
        groups <- attr(d, "groups", exact = TRUE)
        set_val_labels(d, g = c(One = 1L, Two = 2L))
        set_var_format(d, g, "%9.0g")
        set_dta_note(d, 1L, "Identifier", variable = "g")
        set_dta_characteristic(d, "source", "survey", variable = "g")
        expect_identical(attr(alias, "groups", exact = TRUE), groups)
        expect_identical(attr(alias$g, "format.stata"), "%9.0g")
        expect_identical(val_labels(alias$g), c(One = 1L, Two = 2L))
        if (!rowwise) {
            gen(d, size = .N)
            expect_equal(as.integer(alias$size), c(2L, 2L, 1L))
        }
    }
})

test_that("group row positions follow physical order before using dot-n", {
    d <- as_dibble(.group_fixture("g_112_i_typed")$data)
    attr(d, "groups")$.rows[[1L]] <- c(2L, 1L)
    before <- serialize(d, NULL)
    effects <- 0L
    expect_error(gen(d, position = .n), "malformed grouping")
    expect_error(set_var_formats(d, x = { effects <- effects + 1L; "%9.0g" }),
                 "malformed grouping")
    expect_identical(effects, 0L)
    expect_identical(serialize(d, NULL), before)
})

test_that("rowwise grouping frames reject ambiguous or inconsistent columns", {
    for (damage in list(
        function(groups) { groups$extra <- groups$g; names(groups)[3L] <- "g"; groups },
        function(groups) { attr(groups, "names") <- c(NA_character_, ".rows"); groups },
        function(groups) { attr(groups, "names") <- c("", ".rows"); groups },
        function(groups) { attr(groups, "row.names") <- .set_row_names(2L); groups }
    )) {
        d <- as_dibble(.group_fixture("g_112_i_typed_rowwise")$data)
        attr(d, "groups") <- damage(attr(d, "groups"))
        alias <- d
        before <- serialize(d, NULL)
        effects <- 0L
        expect_error(set_var_format(d, x, { effects <- effects + 1L; "%9.0g" }),
                     "malformed grouping metadata")
        expect_identical(effects, 0L)
        expect_identical(serialize(alias, NULL), before)
    }
})

