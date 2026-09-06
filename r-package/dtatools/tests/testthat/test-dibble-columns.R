# Selector cases follow the public contracts covered by upstream dplyr tests.
# See inst/NOTICE for source revisions and attribution.
expect_column_result <- function(actual, expected) {
    expect_true(is_dibble(actual))
    expect_identical(names(actual), names(expected))
    expect_identical(dim(actual), dim(expected))
    expect_identical(lapply(actual, attributes), lapply(expected, attributes))
    expect_identical(lapply(actual, as.vector), lapply(expected, as.vector))
    expect_identical(dplyr::group_vars(actual), dplyr::group_vars(expected))
    if (inherits(expected, c("grouped_df", "rowwise_df"))) {
        expect_equal(dplyr::group_data(actual), dplyr::group_data(expected))
    }
    expect_identical(inherits(actual, "grouped_df"), inherits(expected, "grouped_df"))
    expect_identical(inherits(actual, "rowwise_df"), inherits(expected, "rowwise_df"))
}

test_that("direct column selectors match typed tibble selections", {
    data <- dibble(a = dta_int(1:3), b = dta_string(c("a", "", "bb"), "str12"),
                   c = c(TRUE, FALSE, NA), `other name` = factor(c("a", "b", "a")))
    set_var_label(data, a, "identifier")
    set_var_format(data, b, "%12s")
    input <- dtatools:::.reference_snapshot(data)
    runtime <- c(text = "b", number = "a")
    operations <- list(
        function(x) dplyr::select(x),
        function(x) dplyr::select(x, NULL, -dplyr::everything()),
        function(x) dplyr::select(x, dplyr::everything()),
        function(x) dplyr::select(x, two = a, one = a, b),
        function(x) dplyr::select(x, dplyr::all_of(runtime)),
        function(x) dplyr::select(x, dplyr::where(~ inherits(.x, "dta_numeric"))),
        function(x) dplyr::select(x, dplyr::where(~ identical(var_label(.x), "identifier"))),
        function(x) dplyr::select(x, -dplyr::starts_with("absent")),
        function(x) dplyr::rename(x, !!!runtime),
        function(x) dplyr::rename(x, first = a, last = a),
        function(x) dplyr::relocate(x, last = a, again = a, .after = b),
        function(x) dplyr::relocate(x, b, .before = dplyr::any_of("absent")),
        function(x) dplyr::relocate(x, b, .after = dplyr::any_of("absent")),
        function(x) dplyr::relocate(x, c, .before = c(a, b)),
        function(x) dplyr::relocate(x, a, .after = c(b, `other name`)),
        function(x) dplyr::relocate(x, dplyr::where(is.character))
    )
    for (operation in operations) expect_column_result(operation(data), operation(input))
    expect_identical(names(data), names(input))
    for (rows in c(0L, 3L)) {
        empty <- dibble(.rows = rows)
        expected <- dtatools:::.reference_snapshot(empty)
        expect_column_result(dplyr::select(empty), dplyr::select(expected))
        expect_column_result(dplyr::rename(empty), dplyr::rename(expected))
        expect_column_result(dplyr::relocate(empty, .after = dplyr::everything()),
                             dplyr::relocate(expected, .after = dplyr::everything()))
    }
})

test_that("direct selectors retain grouped and rowwise policies", {
    plain <- dibble(g = factor(c("a", "a", "b"), levels = c("a", "b", "c")),
                    h = dta_int(c(1, 2, 2)), x = 4:6)
    containers <- list(dplyr::group_by(plain, g, h, .drop = FALSE),
                       dplyr::rowwise(plain, h, g), dplyr::rowwise(plain))
    operations <- list(
        function(x) dplyr::select(x),
        function(x) dplyr::select(x, x),
        function(x) dplyr::select(x, key = g, duplicate = g, h),
        function(x) dplyr::select(x, g = x),
        function(x) dplyr::select(x, g = x, h = g),
        function(x) dplyr::rename(x, key = g),
        function(x) dplyr::rename(x, second = g, last = g),
        function(x) dplyr::relocate(x, h, .before = g),
        function(x) dplyr::relocate(x, key = g, .after = x)
    )
    for (data in containers) {
        input <- dtatools:::.reference_snapshot(data)
        for (operation in operations) {
            expect_column_result(suppressMessages(operation(data)),
                                 suppressMessages(operation(input)))
        }
    }
    data <- containers[[1L]]
    expect_message(dplyr::select(data, x), "Adding missing grouping variables: `g`, `h`")
})

test_that("shadowing every omitted grouping key clears the grouping attribute", {
    data <- dplyr::group_by(dibble(g = c(1, 2), x = c(3, 4)), g)
    out <- dplyr::select(data, g = x)
    expected <- dplyr::select(dtatools:::.reference_snapshot(data), g = x)
    expect_column_result(out, expected)
    expect_false(inherits(out, "grouped_df"))
    expect_null(attr(out, "groups", exact = TRUE))
    expect_silent(reserve_columns(out))
})

test_that("selector expressions run once in their captured environment", {
    data <- dibble(a = 1, b = 2, c = 3)
    calls <- 0L
    choose <- function() { calls <<- calls + 1L; "b" }
    before <- function() { calls <<- calls + 1L; "a" }
    out <- dplyr::relocate(data, dplyr::all_of(choose()),
                          .before = dplyr::all_of(before()))
    expect_named(out, c("b", "a", "c"))
    expect_identical(calls, 2L)
    expect_error(dplyr::relocate(data, .before = a, .after = b), "Can't supply both")
    expect_error(dplyr::select(data, absent), "doesn't exist")
    expect_error(dplyr::rename(data, a = b), "unique")
    expect_error(dplyr::select(data, a = a, a = b), "unique")
})

test_that("column results isolate later writes in both directions and duplicated slots", {
    operations <- list(
        function(x) dplyr::select(x, x = x, again = x, s, flag),
        function(x) dplyr::rename(x, renamed = x),
        function(x) dplyr::relocate(x, s)
    )
    for (operation in operations) {
        data <- dibble(x = dta_double(c(1, 2)), s = dta_string(c("a", "b"), "str4"),
                       flag = c(TRUE, FALSE))
        alias <- data
        column_alias <- data$x
        out <- operation(data)
        out_alias <- out
        target <- if ("renamed" %in% names(out)) "renamed" else "x"
        repl(out, .(target), 9, where = 1L)
        expect_identical(as.double(out_alias[[target]]), c(9, 2))
        expect_identical(as.double(data$x), c(1, 2))
        expect_identical(as.double(column_alias), c(1, 2))
        if ("again" %in% names(out)) expect_identical(as.double(out$again), c(9, 2))
        repl(data, s = "z", where = 2L)
        expect_identical(as.character(alias$s), c("a", "z"))
        expect_identical(as.character(out$s), c("a", "b"))
        set_var_label(out, s, "output")
        expect_null(var_label(data$s))
        ordinary <- out
        ordinary$s <- dta_string(c("c", "d"))
        expect_identical(as.character(out$s), c("a", "b"))
        expect_true(can_add_columns(out, 1L))
        gen(out, added = 1L)
        expect_true("added" %in% names(out_alias))
        expect_false("added" %in% names(data))
        pair <- unserialize(serialize(list(data, out), NULL))
        restored <- dplyr::select(pair[[2L]], dplyr::everything())
        expect_true(can_add_columns(restored, 1L))
        repl(restored, s = "q", where = 1L)
        expect_identical(as.character(pair[[1L]]$s), c("a", "z"))
        expect_identical(as.character(pair[[2L]]$s), c("a", "b"))
    }
})

test_that("borrowed and stale strings are checked on every column result", {
    skip_if_not_installed("data.table", "1.18.2.1")
    foreign <- data.table::data.table(s = structure(c("a", "b"),
        stata.string.storage = "str1"))
    borrowed <- dibble(s = foreign$s)
    # Ingress can borrow an already-declared vector. A foreign write does not
    # call any dtatools invalidation hook and can leave a stale declaration.
    data.table::set(foreign, i = 1L, j = "s", value = "longer")
    before <- dplyr::rename(borrowed, text = s)
    expect_identical(as.character(before$text), c("longer", "b"))
    expect_identical(attr(before$text, "stata.string.storage"), "str6")
    data.table::set(foreign, i = 2L, j = "s", value = NA_character_)
    after <- dplyr::select(borrowed, s)
    expect_identical(as.character(after$s), c("longer", ""))
    expect_identical(as.character(before$text), c("longer", "b"))
    data.table::set(foreign, i = 1L, j = "s", value = "external")
    expect_identical(as.character(after$s), c("longer", ""))
    for (declared in c("str1", "strL", "str01", "invalid")) {
        stale <- structure(c("long", NA_character_),
                           class = c("dta_string", "vctrs_vctr", "character"),
                           stata.string.storage = declared, label = "kept")
        data <- dibble(id = 1:2)
        # Install a stale classed vector without routing it through replacement.
        .Call(dtatools:::C_dtatools_set_data_column, data, 1L, stale)
        repaired <- dplyr::relocate(data, id)
        expect_identical(as.character(repaired$id), c("long", ""))
        expect_identical(attr(repaired$id, "stata.string.storage"), "str4")
        expect_identical(var_label(repaired$id), "kept")
    }
})

test_that("string validation counts current UTF-8 bytes", {
    latin <- iconv("\u00e9", from = "UTF-8", to = "latin1")
    Encoding(latin) <- "latin1"
    for (value in list(character(), c("", "a"), "\u00e9", latin)) {
        declared <- structure(value, stata.string.storage = "str2")
        expect_true(dtatools:::.string_declaration_holds(declared))
    }
    expect_false(dtatools:::.string_declaration_holds(
        structure(latin, stata.string.storage = "str1")))
    expect_false(dtatools:::.string_declaration_holds(
        structure(NA_character_, stata.string.storage = "strL")))
    bytes <- rawToChar(as.raw(255L))
    Encoding(bytes) <- "bytes"
    expect_true(dtatools:::.string_declaration_holds(
        structure(bytes, stata.string.storage = "str1")))
})

test_that("isolated string results preserve encodings and complete metadata", {
    latin <- iconv("\u00e9", from = "UTF-8", to = "latin1")
    Encoding(latin) <- "latin1"
    bytes <- rawToChar(as.raw(255L))
    Encoding(bytes) <- "bytes"
    for (values in list(character(), c("", "a"), "\u00e9", latin, bytes)) {
        for (storage in c("str12", "strL")) {
            for (classed in c(FALSE, TRUE)) {
                column <- structure(values, stata.string.storage = storage,
                    label = "A variable", notes = "Keep", custom = list(a = 1L))
                if (classed) class(column) <- c("dta_string", "vctrs_vctr", "character")
                names(column) <- if (length(column))
                    paste0("row", seq_along(column)) else character()
                x <- dibble(s = column)
                before <- x$s
                out <- dplyr::rename(x, text = s)
                expect_identical(out$text, before)
                expect_identical(Encoding(out$text), Encoding(before))
                if (length(values)) {
                    set_var_label(out, text, "Changed")
                    expect_identical(attr(x$s, "label"), "A variable")
                }
            }
        }
    }
    for (storage in list(NA_character_, character(), "str01", "str2046", 1L)) {
        x <- dibble(s = c("long", "short"))
        stale <- structure(c("long", NA_character_), stata.string.storage = storage)
        .Call(dtatools:::C_dtatools_set_data_column, x, 1L, stale)
        out <- dplyr::rename(x, text = s)
        expect_identical(as.character(out$text), c("long", ""))
        expect_identical(attr(out$text, "stata.string.storage"), "str4")
    }
    column <- structure(c("a", "b"), class = "foreign_character",
                        stata.string.storage = "str12", label = "Keep")
    x <- dibble(s = column)
    expect_identical(dplyr::rename(x, text = s)$text, x$s)
    expect_identical(class(x$s), "foreign_character")
})

test_that("column results preserve metadata, compact columns and legacy recognition", {
    data <- read_dta(fixture("auto_v118.dta"))
    set_dta_metadata(data, notes = "dataset note", stata.note.numbers = 2L)
    set_dta_metadata(data, variable = "price", notes = "variable note",
                     stata.note.numbers = 3L)
    metadata <- dtatools:::.reference_snapshot(data)
    out <- dplyr::rename(data, cost = price)
    expect_identical(attr(out, "notes"), attr(metadata, "notes"))
    expect_identical(attr(out$cost, "notes"), attr(data$price, "notes"))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(out$cost))
    repl(data, price = 1, where = 1L)
    expect_false(identical(as.double(out$cost), as.double(data$price)))
    legacy <- data
    class(legacy) <- setdiff(class(legacy), "dibble")
    expect_true(is_dibble(legacy))
    expect_s3_class(dplyr::select(legacy, price), "dibble")
    frame <- reserve_columns(data.frame(x = c(1, 2)))
    gen(frame, y = 3L)
    plain <- dplyr::rename(frame, value = x)
    expect_false(is_dibble(plain))
    expect_identical(class(plain), "data.frame")
    expect_identical(plain$value, c(1, 2))
})
