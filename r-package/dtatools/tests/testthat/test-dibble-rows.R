# Group and reconstruction cases adapt dplyr 1.2.1 test-group-by.R,
# test-generics.R, test-grouped-df.R and test-rowwise.R. See installed NOTICE.
.row_result_plain <- function(data) {
    attr(data, ".dtatools_ref_state") <- NULL
    class(data) <- dtatools:::.reference_base_classes(class(data))
    data
}

test_that("bracket row plans preserve tibble call shapes and index policies", {
    plain <- tibble::tibble(x = dta_long(1:4), s = dta_string(letters[1:4]),
                            flag = c(TRUE, FALSE, NA, TRUE))
    indices <- list(c(4L, 1L, 1L), c(2L, NA_integer_), -2L,
                    c(TRUE, NA, FALSE, TRUE), integer(), NULL,
                    c("4", "unknown", NA_character_))
    for (named in c(FALSE, TRUE)) {
        data <- as_dibble(plain)
        if (named) attr(data, "row.names") <- letters[1:4]
        source <- dtatools:::.reference_snapshot(data)
        for (i in indices) {
            for (j in list(c("s", "x"), "x", integer(), NULL)) {
                for (drop in c(FALSE, TRUE)) {
                    expected <- suppressWarnings(source[i, j, drop = drop])
                    if (is.data.frame(expected)) expected <- as_dibble(expected)
                    actual <- suppressWarnings(data[i, j, drop = drop])
                    if (is.data.frame(actual)) {
                        expect_identical(.row_result_plain(actual), .row_result_plain(expected))
                    } else expect_identical(actual, expected)
                }
            }
        }
        for (expr in alist(d[], d[, ], d[NULL], d[, NULL], d[NULL, ],
                           d[2], d[j = "x"], d[i = 2], d[, "x"],
                           d[drop = TRUE], d[, drop = TRUE], d[, "x", TRUE],
                           d[1L, "x", TRUE])) {
            actual <- suppressWarnings(eval(expr, list(d = data)))
            expected <- suppressWarnings(eval(expr, list(d = source)))
            if (is.data.frame(expected)) expected <- as_dibble(expected)
            if (is.data.frame(actual)) {
                expect_identical(.row_result_plain(actual), .row_result_plain(expected))
            } else expect_identical(actual, expected)
        }
    }
    expect_warning(data["x", drop = TRUE], "ignored")
    expect_error(data[c(1L, -2L), ], "[Nn]egative")
    expect_error(data[c(TRUE, FALSE), ], "size")
    expect_error(data[, "absent"], "absent")
    expect_error(data[, c("x", "x")], "unique")
})

test_that("bracket subscript evaluation is once, ordered, and outside the data mask", {
    data <- dibble(x = 1:3, y = 4:6)
    events <- character()
    i <- function() { events <<- c(events, "i"); c(3L, 1L) }
    j <- function() { events <<- c(events, "j"); "y" }
    drop <- function() { events <<- c(events, "drop"); FALSE }
    out <- data[i(), j(), drop = drop()]
    expect_identical(events, c("i", "j", "drop"))
    expect_identical(as.double(out$y), c(6, 4))
    events <- character()
    i_error <- function() { events <<- c(events, "i"); stop("i failed") }
    expect_error(data[i_error(), j()], "i failed")
    expect_identical(events, "i")
    events <- character()
    data[j()]
    expect_identical(events, "j")
})

test_that("plain reference containers retain base and tibble row rules", {
    for (tibble in c(FALSE, TRUE)) {
        source <- data.frame(x = dta_long(1:4), y = letters[1:4],
                             row.names = paste0("row", 1:4))
        if (tibble) source <- tibble::as_tibble(source)
        attr(source, "custom") <- list(key = "kept")
        attr(source, "notes") <- "also kept"
        data <- reserve_columns(source)
        gen(data, z = x)
        source <- dtatools:::.reference_snapshot(data)
        for (expr in alist(d[c(4L, 1L, NA_integer_), ], d[-2L, "x"],
                           d["row", ], d[NULL, ], d[, NULL], d[, "x"],
                           d[1L, , drop = TRUE], d[2L], d[, ])) {
            expected <- suppressWarnings(eval(expr, list(d = source)))
            actual <- suppressWarnings(eval(expr, list(d = data)))
            expect_identical(actual, expected)
        }
    }
})

test_that("group metadata rebuild matches sorted factor expansion", {
    fixtures <- list(
        tibble::tibble(f = factor(c("b", "a", NA), levels = c("a", "b", "c")),
                       g = c("z", "x", "z"), h = ordered(c("v", "u", "u"), c("u", "v", "w"))),
        tibble::tibble(f = factor(character(), levels = c("a", "b")),
                       g = character(), h = factor(character(), levels = c("u", "v"))),
        tibble::tibble(f = factor(c("a", NA), levels = c("a", "b")),
                       g = c(NA_real_, NaN), h = factor(c("u", "v")))
    )
    key_sets <- list("f", c("f", "g"), c("g", "f"), c("f", "g", "h"), c("g", "h", "f"))
    for (fixture_index in seq_along(fixtures)) for (key_index in seq_along(key_sets)) {
        data <- fixtures[[fixture_index]]
        keys <- key_sets[[key_index]]
        for (drop in c(FALSE, TRUE)) {
            entry <- .group_fixture(paste0("factor_expand_", fixture_index, "_", key_index,
                "_", if (drop) "drop" else "keep"))
            expect_identical(.group_fixture_spec(data), entry$plain_spec)
            expected <- entry$groups
            actual <- dtatools:::.build_group_metadata(as.list(data), keys, nrow(data), drop)
            expect_identical(actual, expected)
        }
    }
})

test_that("group validation preserves empty keys and equality casting", {
    values <- list(dta_byte(c(2, 1, 2)), dta_int(c(2, 1, 2)),
                   dta_long(c(2, 1, 2)), dta_float(c(2, 1, 2)),
                   dta_double(c(2, 1, 2)),
                   dta_double(c(NA_real_, tagged_missing("a"), tagged_missing("b"))),
                   factor(c("b", "a", "b"), levels = c("a", "b", "unused")),
                   as.Date(c("2020-01-01", "2020-01-02", "2020-01-01")),
                   list(1:2, NULL, 1:2),
                   tibble::tibble(a = c(2, 1, 2), b = c("z", "a", "z")))
    key_names <- c("byte", "int", "long", "float", "double", "tags", "factor", "date", "list", "frame")
    for (key_index in seq_along(values)) for (empty in c(FALSE, TRUE)) {
        value <- values[[key_index]]
        if (empty) value <- vctrs::vec_slice(value, integer())
        plain <- tibble::tibble(g = value)
        grouped <- .group_fixture_attach(paste0("key_", key_names[[key_index]],
            "_", if (empty) "empty" else "full"), plain, .group_fixture_spec(plain))
        before <- serialize(grouped, NULL)
        expect_silent(dtatools:::.validate_group_metadata(grouped))
        expect_identical(serialize(grouped, NULL), before)
    }
    explicit <- function(value, key, id) {
        plain <- tibble::new_tibble(list(g = value), nrow = NROW(value))
        .group_fixture_attach(id, plain, .group_fixture_spec(plain),
            groups = tibble::new_tibble(list(g = key, .rows = vctrs::list_of(c(1L, 3L), 2L)),
                                       nrow = NROW(key)))
    }
    pairs <- list(list(c(1L, 2L, 1L), c(1, 2)),
                  list(factor(c("a", "b", "a")), c("a", "b")),
                  list(dta_byte(c(1, 2, 1)), dta_double(c(1, 2))))
    pair_ids <- c("cast_integer_double", "cast_factor_character", "cast_byte_double")
    for (i in seq_along(pairs)) {
        pair <- pairs[[i]]
        expect_silent(dtatools:::.validate_group_metadata(explicit(pair[[1L]], pair[[2L]], pair_ids[[i]])))
    }
    # A native-declined matrix key retains the public fallback's row shape.
    value <- structure(matrix(c(1, 2, 1, 3, 4, 3), 3, 2), stata.storage = "double")
    key <- structure(matrix(c(1, 2, 3, 4), 2, 2), stata.storage = "double")
    expect_silent(dtatools:::.validate_group_metadata(explicit(value, key, "cast_matrix")))
    wrong <- explicit(c(1, 2, 1), c(1, 2), "cast_double_double")
    attr(wrong, "groups")$g <- c(3, 2)
    wrong$h <- c(1, 2, 1)
    groups <- attr(wrong, "groups")
    groups$h <- c("one", "two")
    attr(wrong, "groups") <- groups[c("g", "h", ".rows")]
    expect_error(dtatools:::.validate_group_metadata(wrong),
                 "grouping keys that do not match", class = "simpleError")
    incompatible <- explicit(c(1, 2, 1), c(1, 2), "cast_double_double")
    attr(incompatible, "groups")$g <- c("one", "two")
    expect_error(dtatools:::.validate_group_metadata(incompatible),
                 "`x`.*`y`", class = "vctrs_error_ptype2")
})

test_that("group partitions reject repeated rows and retain rowwise order", {
    grouped <- .group_fixture("g_121_only")$data
    attr(grouped, "groups")$.rows <- vctrs::list_of(c(1L, 3L), 1L)
    expect_error(dtatools:::.validate_group_metadata(grouped), "malformed grouping")
    for (n in c(0L, 3L)) {
        rowwise <- .group_fixture(paste0("rowwise_x", n))$data
        expect_silent(dtatools:::.validate_group_metadata(rowwise))
        if (n) {
            attr(rowwise, "groups")$.rows <- rev(attr(rowwise, "groups")$.rows)
            expect_error(dtatools:::.validate_group_metadata(rowwise), "malformed grouping")
        }
    }
})

.check_optional_split_dibble_rows_162 <- function(include_dplyr) {
    plain <- dibble(g = factor(c("b", "a", "b", "a"), levels = c("a", "b", "c")),
                    id = c(2L, 1L, 2L, 1L), x = dta_double(c(1, 2, 3, 4)))
    fixture_ids <- c("row_entry_keep", "row_entry_drop", "row_entry_ids", "row_entry_no_ids")
    containers <- if (include_dplyr) list(
        dplyr::group_by(plain, g, id, .drop = FALSE),
        dplyr::group_by(plain, g, id),
        dplyr::rowwise(plain, id, g), dplyr::rowwise(plain)) else
        lapply(fixture_ids, function(id) as_dibble(.group_fixture(id)$data))
    for (container_index in seq_along(containers)) {
        container <- containers[[container_index]]
        entry <- if (!include_dplyr) .group_fixture(fixture_ids[[container_index]])
        data <- container
        snapshot <- dtatools:::.reference_snapshot(data)
        row_indices <- if (include_dplyr) list(c(3L, 1L, 3L), -2L,
            c(TRUE, FALSE, TRUE, FALSE), integer()) else entry$indices$rows
        for (row_index in seq_along(row_indices)) {
            rows <- row_indices[[row_index]]
            if (include_dplyr) {
                for (preserve in c(FALSE, TRUE)) {
                    actual <- dplyr::dplyr_row_slice(data, rows, preserve = preserve)
                    expected <- as_dibble(dplyr::dplyr_row_slice(snapshot, rows, preserve = preserve))
                    expect_identical(.row_result_plain(actual), .row_result_plain(expected))
                    expect_silent(dtatools:::.as_mutation_data(actual, allow_grouped = TRUE))
                }
            }
            column_indices <- if (include_dplyr) list(names(data), c("x", "g"), "x", character()) else
                entry$indices$columns
            for (column_index in seq_along(column_indices)) {
                cols <- column_indices[[column_index]]
                actual <- data[rows, cols]
                expected <- if (include_dplyr) as_dibble(snapshot[rows, cols]) else
                    entry$expected$bracket[[row_index]][[column_index]]
                expect_identical(.row_result_plain(actual), .row_result_plain(expected))
            }
            actual <- slice_dta_rows(data, rows)
            expected <- if (include_dplyr) as_dibble(
                if (inherits(snapshot, "rowwise_df")) dplyr::dplyr_row_slice(snapshot, rows) else snapshot[rows, ]) else
                entry$expected$slice[[row_index]]
            expect_identical(.row_result_plain(actual), .row_result_plain(expected))
        }
    }
}

test_that("row entry points retain their grouped and rowwise policies", {
    .check_optional_split_dibble_rows_162(FALSE)
})

test_that("grouped and rowwise entry policies through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_162(TRUE)
})
.check_optional_split_dibble_rows_189 <- function(include_dplyr) {
    data <- if (include_dplyr) dplyr::group_by(dibble(g = c("a", "b"), x = 1:2), g) else
        as_dibble(.group_fixture("string_ab_typed")$data)
    for (operation in list(function(d) d[c(2L, NA_integer_, 2L), ],
                          function(d) slice_dta_rows(d, c(2L, NA_integer_, 2L)))) {
        result <- operation(data)
        expect_identical(as.character(result$g), c("b", "", "b"))
        expect_identical(as.character(attr(result, "groups", exact = TRUE)$g), c("", "b"))
        expect_identical(attr(result, "groups", exact = TRUE)$.rows, vctrs::list_of(2L, c(1L, 3L)))
        expect_silent(dtatools:::.as_mutation_data(result, allow_grouped = TRUE))
    }
    if (include_dplyr) {
        expect_error(dplyr::dplyr_row_slice(data, NA_integer_))
    }
}

test_that("padding is typed before rebuilding grouped string keys", {
    .check_optional_split_dibble_rows_189(FALSE)
})

test_that("typed string padding row hooks through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_189(TRUE)
})
.check_optional_split_dibble_rows_202 <- function(include_dplyr) {
    operations <- list(function(d) d[c(3L, 1L, 1L), ],
                       function(d) d[, ],
                       function(d) slice_dta_rows(d, c(3L, 1L, 1L)))
    if (include_dplyr) operations <- c(operations, list(
        function(d) dplyr::dplyr_row_slice(d, c(3L, 1L, 1L))))
    for (operation in operations) {
        for (roundtrip in c(FALSE, TRUE)) {
            source <- dibble(x = dta_double(1:3), s = c("a", "b", "c"), flag = c(TRUE, FALSE, TRUE))
            alias <- source
            standalone <- source$x
            add_dta_note(source, "dataset note")
            attr(source, "custom") <- list(key = 42L)
            source <- reserve_columns(source)
            result <- operation(source)
            expect_identical(dta_notes(result), dta_notes(source))
            expect_identical(attr(result, "custom"), attr(source, "custom"))
            pair <- list(source, result)
            if (roundtrip) pair <- unserialize(serialize(pair, NULL))
            source <- pair[[1L]]; result <- pair[[2L]]
            before_source <- as.double(source$x); before_result <- as.double(result$x)
            repl(source, x = 9, where = 1L)
            expect_identical(as.double(result$x), before_result)
            repl(result, x = 8, where = 1L)
            expect_identical(as.double(source$x), c(9, before_source[-1L]))
            expect_identical(as.double(standalone), c(1, 2, 3))
            expect_identical(as.double(alias$x), c(1, 2, 3))
            expect_true(is_dibble(result))
            if (roundtrip) {
                expect_false(can_add_columns(result))
                result <- reserve_columns(result)
            }
            gen(result, new = x)
            expect_false("new" %in% names(source))
        }
    }
}

test_that("row results preserve metadata and symmetric later-write isolation", {
    .check_optional_split_dibble_rows_202(FALSE)
})

test_that("row metadata and later-write isolation through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_202(TRUE)
})
.check_optional_split_dibble_rows_238 <- function(include_dplyr) {
    template <- if (include_dplyr) dplyr::group_by(dibble(g = c(1L, 2L), s = c("a", "b")), g) else
        as_dibble(.group_fixture("g12_string_ab_typed")$data)
    add_dta_note(template, "kept")
    borrowed <- structure(c("wide", NA_character_), class = "dta_string",
                          stata.string.storage = "str1")
    data <- tibble::tibble(g = dta_long(c(2, 2)), s = borrowed)
    result <- if (include_dplyr) dplyr::dplyr_reconstruct(data, template) else
        dtatools:::.reconstruct_dibble(data, template)
    expect_identical(as.character(result$s), c("wide", ""))
    expect_identical(dta_notes(result), dta_notes(template))
    observed_rows <- if (include_dplyr) dplyr::group_rows(result) else
        attr(result, "groups", exact = TRUE)$.rows
    expect_identical(observed_rows, vctrs::list_of(1:2))
    repl(result, s = "x", where = 1L)
    expect_identical(as.character(borrowed), c("wide", NA_character_))
    expect_silent(dtatools:::.as_mutation_data(result, allow_grouped = TRUE))
    expect_error(dtatools:::.reconstruct_dibble(structure(list(x = 1:3),
        class = "data.frame", row.names = c(NA_integer_, -2L)), template), "inconsistent")
}

test_that("direct reconstruction isolates and validates unknown columns", {
    .check_optional_split_dibble_rows_238(FALSE)
})

test_that("unknown column reconstruction through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_238(TRUE)
})
test_that("bracket planning never executes language-valued indices", {
    data <- dibble(x = 1:3, y = 4:6)
    for (index in list(quote(stop("index executed")), quote(x), expression(stop("index executed")))) {
        for (operation in list(function(d) d[index], function(d) d[, index], function(d) d[index, ])) {
            expected <- tryCatch(operation(dtatools:::.reference_snapshot(data)), error = identity)
            if (inherits(expected, "error")) {
                actual <- tryCatch(operation(data), error = identity)
                expect_s3_class(actual, "error")
                expect_identical(class(actual), class(expected))
                expect_false(identical(conditionMessage(actual), "index executed"))
            } else expect_identical(.row_result_plain(operation(data)),
                                    .row_result_plain(as_dibble(expected)))
        }
    }
})

.check_optional_split_dibble_rows_272 <- function(include_dplyr) {
    for (drop in c(FALSE, TRUE)) {
        plain <- tibble::tibble(g = c(1L, 1L, 2L), x = 1:3)
        entry <- if (!include_dplyr) .group_fixture(
            if (drop) "g_112_i_drop" else "g_112_i_keep")
        grouped <- if (include_dplyr) dplyr::group_by(plain, g, .drop = drop) else entry$data
        data <- reserve_columns(grouped)
        gen(data, y = x)
        snapshot <- dtatools:::.reference_snapshot(data)
        result <- slice_dta_rows(data, 2:1)
        expect_false(is_dibble(result))
        if (include_dplyr) expect_identical(result, snapshot[2:1, ]) else
            expect_identical(.row_result_plain(result),
                .row_result_plain(entry$expected$generated_y_bracket_21))
        if (include_dplyr) {
            result <- dplyr::dplyr_row_slice(data, 2:1)
            expect_false(is_dibble(result))
            expect_identical(result, dplyr::dplyr_row_slice(snapshot, 2:1))
        }
    }
}

test_that("plain grouped reference frames retain row slicing support", {
    .check_optional_split_dibble_rows_272(FALSE)
})

test_that("plain grouped reference slicing through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_272(TRUE)
})
.check_optional_split_dibble_rows_289 <- function(include_dplyr) {
    for (kind in c("plain", "grouped", "rowwise")) {
        data <- dibble(x = 1:3, y = 4:6)
        entry <- if (!include_dplyr && kind != "plain") .group_fixture(
            if (kind == "grouped") "xy_123_456_typed" else "xy_123_456_typed_rowwise")
        if (kind == "grouped") data <- if (include_dplyr) dplyr::group_by(data, x) else as_dibble(entry$data)
        if (kind == "rowwise") data <- if (include_dplyr) dplyr::rowwise(data, x) else as_dibble(entry$data)
        snapshot <- dtatools:::.reference_snapshot(data)
        drops <- list(NA, integer(), TRUE, FALSE)
        for (drop_index in seq_along(drops)) {
            drop <- drops[[drop_index]]
            expected <- if (include_dplyr || kind == "plain") tryCatch(snapshot[1, , drop = drop], error = identity) else
                entry$expected$drop[[drop_index]]
            if (inherits(expected, "error")) expect_error(data[1, , drop = drop]) else {
                expect_identical(.row_result_plain(data[1, , drop = drop]),
                                 .row_result_plain(if (include_dplyr || kind == "plain") as_dibble(expected) else expected))
            }
        }
        expressions <- alist(d[1L, drop = TRUE], d[drop = TRUE], d[, drop = TRUE], d[1L, drop = NA])
        for (expression_index in seq_along(expressions)) {
            expr <- expressions[[expression_index]]
            expected <- if (include_dplyr || kind == "plain")
                suppressWarnings(tryCatch(eval(expr, list(d = snapshot)), error = identity)) else
                entry$expected$one_dim[[expression_index]]
            if (inherits(expected, "error")) {
                expect_error(suppressWarnings(eval(expr, list(d = data))))
            } else {
                actual <- suppressWarnings(eval(expr, list(d = data)))
                expect_identical(.row_result_plain(actual),
                    .row_result_plain(if (include_dplyr || kind == "plain") as_dibble(expected) else expected))
            }
        }
        if (kind != "plain") expect_error(data[, , extra = 1], "unused argument")
    }
    for (tibble in c(FALSE, TRUE)) {
        plain <- data.frame(x = 1:3, y = 4:6)
        if (tibble) plain <- tibble::as_tibble(plain)
        data <- reserve_columns(plain)
        gen(data, z = x)
        expect_s3_class(data, "dtatools_ref_data")
        events <- character()
        i <- function() { events <<- c(events, "i"); 1L }
        j <- function() { events <<- c(events, "j"); 1L }
        data[i(), j(), drop = FALSE]
        expect_identical(events, if (tibble) c("i", "j") else c("j", "i"))
        events <- character()
        i_error <- function() { events <<- c(events, "i"); stop("row expression") }
        j_error <- function() { events <<- c(events, "j"); stop("column expression") }
        expect_error(data[i_error(), j_error(), drop = FALSE],
                     if (tibble) "row expression" else "column expression")
        expect_identical(events, if (tibble) "i" else "j")
    }
}

test_that("drop and unused-argument validation follows each bracket container", {
    .check_optional_split_dibble_rows_289(FALSE)
})

test_that("bracket container argument validation through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_289(TRUE)
})
.check_optional_split_dibble_rows_334 <- function(include_dplyr) {
    operations <- list(function(d) d[c(3L, 1L, 1L), ],
                       function(d) slice_dta_rows(d, c(3L, 1L, 1L)))
    if (include_dplyr) operations <- c(operations, list(
        function(d) dplyr::dplyr_row_slice(d, c(3L, 1L, 1L))))
    for (operation in operations) {
        source <- dibble(x = dta_double(1:3), y = dta_double(1:3))
        .Call(dtatools:::C_dtatools_set_data_column, source, 2L, source$x)
        alias <- source
        standalone <- source$x
        shallow <- source
        attr(shallow, "custom") <- TRUE
        result <- operation(source)
        source_before <- as.double(source$x)
        result_before <- as.double(result$x)
        repl(source, x = 7, where = 1L)
        expect_identical(as.double(alias$x), c(7, 2, 3))
        expect_identical(as.double(source$y), c(7, 2, 3))
        expect_identical(as.double(standalone), source_before)
        expect_identical(as.double(shallow$x), source_before)
        expect_identical(as.double(result$x), result_before)
        repl(result, x = 8, where = 1L)
        expect_identical(as.double(source$x), c(7, 2, 3))
    }
    skip_if_not_installed("data.table", minimum_version = "1.18.2.1")
    foreign <- data.table::data.table(x = dta_double(1:3), s = c("a", "b", "c"))
    result <- if (include_dplyr)
        dplyr::dplyr_reconstruct(foreign, dibble(x = double(), s = character())) else
        dtatools:::.reconstruct_dibble(foreign, dibble(x = double(), s = character()))
    data.table::set(foreign, i = 1L, j = "s", value = "z")
    expect_identical(as.character(result$s), c("a", "b", "c"))
    repl(result, x = 9, where = 1L)
    expect_identical(as.double(foreign$x), c(1, 2, 3))
}

test_that("row gather and reconstruction isolate aliases and foreign columns", {
    .check_optional_split_dibble_rows_334(FALSE)
})

test_that("row gather and unknown foreign columns through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_334(TRUE)
})
test_that("serialized grouping works without loading the dplyr namespace", {
    skip_if_not_installed("callr")
    fixture <- tempfile(fileext = ".rds")
    on.exit(unlink(fixture), add = TRUE)
    grouped <- as_dibble(.group_fixture("g_212_i_typed")$data)
    rowwise <- as_dibble(.group_fixture("g123_x456_rowwise_typed")$data)
    plain <- reserve_columns(.group_fixture("g_212_i")$data)
    gen(plain, y = x)
    saveRDS(list(grouped, rowwise, plain), fixture)
    result <- .dtatools_child_r("serialized-groups", function(path) {
        library(dtatools)
        stopifnot(!"dplyr" %in% loadedNamespaces())
        fixtures <- readRDS(path)
        results <- lapply(fixtures, function(data) list(data[3:1, ], slice_dta_rows(data, 3:1)))
        data <- reserve_columns(fixtures[[1L]])
        gen(data, size = .N)
        egen(data, average = dta_mean(x))
        repl(data, g = 1L)
        gen(data, updated_size = .N)
        stopifnot(!"dplyr" %in% loadedNamespaces())
        list(results = results, size = as.double(data$size),
             updated_size = as.double(data$updated_size),
             groups = attr(data, "groups"))
    }, args = list(path = fixture), libpath = .libPaths())
    expect_identical(result$size, c(2, 1, 2))
    expect_identical(result$updated_size, c(3, 3, 3))
    expect_identical(result$groups$.rows, vctrs::list_of(1:3))
    expect_length(result$results, 3L)
    for (pair in result$results) {
        for (data in pair) expect_silent(dtatools:::.as_mutation_data(data, allow_grouped = TRUE))
    }
})


test_that("the dplyr row hook keeps vctrs row-name repair", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (tibble in c(FALSE, TRUE)) for (dibble in c(FALSE, TRUE)) {
        data <- data.frame(x = dta_long(1:3), y = letters[1:3])
        if (tibble) data <- tibble::as_tibble(data)
        if (dibble) data <- as_dibble(data) else {
            data <- reserve_columns(data)
            gen(data, z = x)
        }
        attr(data, "row.names") <- c("abc", "def", "ghi")
        snapshot <- dtatools:::.reference_snapshot(data)
        for (rows in list(c(3L, 1L, 1L), c(NA_integer_, NA_integer_, 2L), integer())) {
            actual <- dplyr::dplyr_row_slice(data, rows)
            expected <- dplyr::dplyr_row_slice(snapshot, rows)
            if (dibble) expected <- dtatools:::.close_dibble(data, expected)
            expect_identical(.row_result_plain(actual), .row_result_plain(expected))
        }
    }
})


.check_optional_split_dibble_rows_419 <- function(include_dplyr) {
    withr::local_options(list(dplyr.legacy_locale = TRUE))
    if (!include_dplyr) withr::local_collate("C")
    data <- dibble(g = c("Z", "a", "b", "A", "\u00e1", "\u00e4"), x = 1:6)
    entry <- if (!include_dplyr) .group_fixture("legacy_C_strings")
    grouped <- if (include_dplyr) suppressWarnings(dplyr::group_by(data, g)) else
        as_dibble(entry$data)
    snapshot <- dtatools:::.reference_snapshot(grouped)
    actual_groups <- attr(grouped[6:1, ], "groups", exact = TRUE)
    expected_groups <- if (include_dplyr) suppressWarnings(dplyr::group_data(snapshot[6:1, ])) else
        entry$expected$reversed_groups
    expect_identical(actual_groups, expected_groups)
    data <- tibble::tibble(g = factor(c("b", "a", NA), levels = c("a", "b", "c")),
                           nested = tibble::tibble(x = c("Z", "a", "A")))
    expect_identical(dtatools:::.build_group_metadata(as.list(data), names(data), nrow(data), FALSE),
                     if (include_dplyr) suppressWarnings(attr(dplyr::grouped_df(data, names(data), drop = FALSE), "groups")) else
                         .group_fixture("legacy_C_nested")$groups)
    options(dplyr.legacy_locale = NA)
    expect_error(dtatools:::.build_group_metadata(as.list(data), names(data), nrow(data)),
                 "single `TRUE` or `FALSE`")
}

test_that("group rebuild honors the legacy locale compatibility option", {
    .check_optional_split_dibble_rows_419(FALSE)
})

test_that("legacy ambient locale comparison through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_419(TRUE)
})
test_that("bracket planning does not introduce named-argument warnings", {
    data <- reserve_columns(data.frame(x = 1:3, y = 4:6))
    gen(data, z = x)
    expect_silent(data[2L])
    expect_silent(data[2:1, ])
    expect_warning(data[i = 2:1, ], "named arguments")
})


test_that("base reference gathers retain base observation metadata and drop shapes", {
    plain <- data.frame(x = 1:4, y = 5:8)
    plain$named <- stats::setNames(11:14, letters[1:4])
    plain$matrix <- I(matrix(1:8, nrow = 4L, dimnames = list(letters[1:4], c("a", "b"))))
    plain$nested <- data.frame(value = 21:24)
    data <- reserve_columns(plain)
    gen(data, generated = x)
    snapshot <- dtatools:::.reference_snapshot(data)
    for (rows in list(c(NA_integer_, 2L), c(4L, 1L, 1L))) {
        expect_identical(data[rows, , drop = FALSE], snapshot[rows, , drop = FALSE])
    }
    for (expr in alist(d[1L, c(1L, 1L), drop = TRUE],
                       d[1L, integer(), drop = TRUE],
                       d[1L, 99L, drop = TRUE])) {
        expect_identical(eval(expr, list(d = data)), eval(expr, list(d = snapshot)))
    }
    expect_error(data[, 99L, drop = TRUE], "undefined columns")
    empty <- reserve_columns(data.frame(row.names = letters[1:4]))
    gen(empty, temporary = 1L)
    drop_vars(empty, temporary)
    expect_s3_class(empty, "dtatools_ref_data")
    snapshot <- dtatools:::.reference_snapshot(empty)
    expect_identical(empty[1L, , drop = TRUE], snapshot[1L, , drop = TRUE])
    expect_identical(empty[1L, 1L, drop = TRUE], snapshot[1L, 1L, drop = TRUE])
})

test_that("reference row subsets preserve the metadata wrapper's policies", {
    for (tibble in c(FALSE, TRUE)) for (mark in c("raw", "dataset", "variable", "both")) {
        source <- data.frame(x = 1:3, y = letters[1:3])
        if (tibble) source <- tibble::as_tibble(source)
        attr(source, "custom") <- list(key = "kept")
        attr(source, "notes") <- "raw note"
        data <- reserve_columns(source)
        gen(data, z = x)
        if (mark %in% c("dataset", "both")) add_dta_note(data, "dataset")
        if (mark %in% c("variable", "both")) add_dta_note(data, "column", variable = "x")
        expect_s3_class(data, "dtatools_ref_data")
        snapshot <- dtatools:::.reference_snapshot(data)
        for (expr in alist(d[, NULL], d[, c("x", "y"), drop = FALSE],
                           d[c(NA_integer_, 2L), c("x", "y"), drop = FALSE],
                           d[2:1, ], d[NULL, "x", drop = TRUE],
                           d[1L, "x", drop = TRUE], d[1L, , drop = TRUE])) {
            expect_identical(eval(expr, list(d = data)), eval(expr, list(d = snapshot)))
        }
        events <- character()
        rows <- function() { events <<- c(events, "i"); 1L }
        cols <- function() { events <<- c(events, "j"); 1L }
        data[rows(), cols(), drop = FALSE]
        expected_order <- if (tibble && mark == "raw") c("i", "j") else c("j", "i")
        expect_identical(events, expected_order)
    }
})

test_that("metadata subscript forcing precedes container argument validation", {
    for (kind in c("base", "tibble", "grouped", "rowwise")) {
        data <- data.frame(x = 1:3, y = 4:6)
        if (kind != "base") data <- tibble::as_tibble(data)
        if (kind == "grouped") data <- .group_fixture("xy_123_456")$data
        if (kind == "rowwise") data <- as_dibble(.group_fixture("xy_123_456_typed_rowwise")$data) else {
            data <- reserve_columns(data)
            gen(data, marker = x)
        }
        add_dta_note(data, "dataset")
        expect_s3_class(data, "dtatools_ref_data")
        expect_error(data[, stop("column expression"), extra = 1], "column expression")
        if (kind != "base") {
            expect_error(data[stop("row expression"), "absent"], "row expression")
        }
        events <- character()
        cols <- function() { events <<- c(events, "j"); "absent" }
        rows <- function() { events <<- c(events, "i"); stop("row expression") }
        suppressWarnings(try(data[rows(), cols()], silent = TRUE))
        expect_identical(events, c("j", "i"))
    }
})

.check_optional_split_dibble_rows_520 <- function(include_dplyr) {
    withr::local_options(list(dplyr.legacy_locale = TRUE))
    if (!include_dplyr) withr::local_collate("C")
    plain <- tibble::tibble(n = c(NA_real_, NaN, NA_real_), s = c("a", "b", "c"),
                           f = factor(rep("u", 3L), levels = c("u", "v")), x = 1:3)
    entry <- if (!include_dplyr) .group_fixture("legacy_C_prefix")
    data <- reserve_columns(if (include_dplyr)
        suppressWarnings(dplyr::group_by(plain, n, s, f, .drop = FALSE)) else entry$data)
    gen(data, marker = x)
    expect_s3_class(data, "dtatools_ref_data")
    snapshot <- dtatools:::.reference_snapshot(data)
    expect_identical(attr(data[3:1, ], "groups"),
                     if (include_dplyr) suppressWarnings(attr(snapshot[3:1, ], "groups")) else
                         entry$expected$marker_reversed_groups)
}

test_that("legacy factor expansion retains contiguous missing-value prefixes", {
    .check_optional_split_dibble_rows_520(FALSE)
})

test_that("legacy missing prefix expansion through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_520(TRUE)
})
.check_optional_split_dibble_rows_532 <- function(include_dplyr) {
    for (explicit in c(FALSE, TRUE)) {
        data <- dibble(x = 1:3, s = c("a", "b", "c"))
        if (explicit) attr(data, "row.names") <- 1:3
        snapshot <- dtatools:::.reference_snapshot(data)
        for (rows in list(1:3, 3:1, c(NA_integer_, 2L), integer())) {
            operations <- list(function(d) d[rows, ])
            if (include_dplyr) operations <- c(operations, list(
                function(d) dplyr::dplyr_row_slice(d, rows)))
            for (operation in operations) {
                expected <- dtatools:::.close_dibble(data, operation(snapshot))
                expect_identical(.row_names_info(operation(data), 0L),
                                 .row_names_info(expected, 0L))
            }
        }
        if (include_dplyr) {
            candidate <- snapshot[2:1, ]
            expect_identical(.row_names_info(dplyr::dplyr_reconstruct(candidate, data), 0L),
                             .row_names_info(dplyr::dplyr_reconstruct(candidate, snapshot), 0L))
        }
    }
    if (include_dplyr) {
        joined <- dplyr::full_join(dibble(id = 1:2, s = c("a", "b")),
                                   tibble::tibble(id = 3L), by = "id")
        expect_identical(.row_names_info(joined, 0L), c(NA_integer_, -3L))
        path <- tempfile(fileext = ".arrow")
        on.exit(unlink(path), add = TRUE)
        expect_no_warning(save_arrow(joined, path))

    }
}

test_that("row results retain automatic versus explicit row-name bookkeeping", {
    .check_optional_split_dibble_rows_532(FALSE)
})

test_that("row-name bookkeeping through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_rows_532(TRUE)
})
test_that("plain-reference reconstruction preserves raw payload row names", {
    skip_if_not_installed("dplyr", "1.2.1")
    for (tibble in c(FALSE, TRUE)) for (explicit in c(FALSE, TRUE)) {
        data <- data.frame(x = 1:3, y = 4:6)
        if (tibble) data <- tibble::as_tibble(data)
        data <- reserve_columns(data)
        gen(data, z = x)
        expect_s3_class(data, "dtatools_ref_data")
        payload <- data.frame(x = 4:5)
        if (explicit) attr(payload, "row.names") <- c("a", "b")
        expect_identical(.row_names_info(dplyr::dplyr_reconstruct(payload, data), 0L),
                         .row_names_info(payload, 0L))
    }
})


test_that("the row helper retains its shell's raw row-name policy", {
    for (tibble in c(FALSE, TRUE)) for (row_names in list(NULL, 1:3, c("a", "b", "c"))) {
        data <- data.frame(x = 1:3, y = 4:6)
        if (tibble) data <- tibble::as_tibble(data)
        if (!is.null(row_names)) attr(data, "row.names") <- row_names
        data <- reserve_columns(data)
        gen(data, z = x)
        snapshot <- dtatools:::.reference_snapshot(data)
        for (rows in list(1:3, 3:1, c(NA_integer_, 2L))) {
            expect_identical(.row_names_info(slice_dta_rows(data, rows), 0L),
                             .row_names_info(snapshot[rows, integer(), drop = FALSE], 0L))
        }
    }
})

test_that("native legacy string grouping follows the current base collation", {
    withr::local_options(list(dplyr.legacy_locale = TRUE))
    values <- c("Z", "a", "b", "A", "\u00e1", "\u00e4")[6:1]
    positions <- order(values)
    expected <- tibble::new_tibble(list(
        g = values[positions],
        .rows = vctrs::list_of(!!!as.list(positions), .ptype = integer())
    ), nrow = 6L)
    attr(expected, ".drop") <- TRUE
    actual <- dtatools:::.build_group_metadata(list(g = values), "g", 6L, TRUE)
    expect_identical(actual, expected)
})
