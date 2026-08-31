test_that("note accessors preserve gaps, empty text, scope, and stable renumbering", {
    data <- data.frame(x = 1:2, y = 3:4)
    original <- data
    data <- set_stata_note(data, 4, "four")
    data <- set_stata_note(data, 1, "")
    data <- set_stata_note(data, 2, "variable", variable = "x")

    expect_identical(stata_notes(data), c(`1` = "", `4` = "four"))
    expect_identical(stata_note(data, 4), "four")
    expect_null(stata_note(data, 3))
    expect_identical(stata_notes(data, "x"), c(`2` = "variable"))
    expect_length(stata_notes(data, "y"), 0L)
    expect_length(stata_notes(original), 0L)

    data <- add_stata_note(data, "five")
    expect_identical(stata_note(data, 5), "five")
    data <- drop_stata_notes(data, c(1, 5))
    expect_identical(stata_notes(data), c(`4` = "four"))
    data <- renumber_stata_notes(data, 2)
    expect_identical(stata_notes(data), c(`2` = "four"))
    expect_length(stata_notes(drop_stata_notes(data)), 0L)
})

test_that("characteristic accessors preserve order, Unicode, and empty values", {
    data <- data.frame(x = 1)
    data <- set_stata_characteristic(data, "source", "")
    data <- set_stata_characteristic(data, "café", "naïve")
    data <- set_stata_characteristic(data, "role", "id", variable = "x")

    expect_identical(
        stata_characteristics(data),
        c(source = "", café = "naïve")
    )
    expect_identical(stata_characteristic(data, "source"), "")
    expect_null(stata_characteristic(data, "absent"))
    expect_identical(stata_characteristics(data, "x"), c(role = "id"))

    data <- set_stata_characteristic(data, "source", "updated")
    expect_identical(names(stata_characteristics(data)), c("source", "café"))
    data <- drop_stata_characteristics(data, "source")
    expect_identical(stata_characteristics(data), c(café = "naïve"))
    expect_length(stata_characteristics(drop_stata_characteristics(data)), 0L)
})

test_that("metadata accessors reject malformed and reserved input atomically", {
    data <- data.frame(x = 1)
    expect_error(set_stata_note(data, 0, "bad"), "1 through 9,999")
    expect_error(set_stata_note(data, 10000, "bad"), "1 through 9,999")
    expect_error(set_stata_note(data, 1.5, "bad"), "1 through 9,999")
    expect_error(set_stata_note(data, 1, NA_character_), "non-missing")
    expect_error(add_stata_note(data, NULL), "non-missing")
    expect_error(set_stata_note(data, 1, strrep("x", 67785L)), "67,784-byte")
    expect_error(
        set_stata_characteristic(data, "source", strrep("x", 67785L)),
        "67,784-byte"
    )
    expect_error(
        set_stata_characteristic(data, "note1", "collision"),
        "cannot be a numeric `note\\*` key"
    )
    expect_error(
        set_stata_characteristic(data, "1bad", "value"),
        "valid Stata name"
    )
    expect_error(
        set_stata_characteristic(data, "_lang_list", "default"),
        "language-control key"
    )
    expect_error(
        set_stata_characteristic(data, "_lang_v_en", "English label"),
        "language-control key"
    )
    expect_error(
        set_stata_characteristic(data, "_lang_l_en", "English labels"),
        "language-control key"
    )
    malformed_dataset <- data
    attr(malformed_dataset, "stata.characteristics") <- c(
        `_lang_c` = "default"
    )
    expect_error(
        stata_characteristics(malformed_dataset),
        "malformed Stata characteristic metadata"
    )
    malformed_variable <- data
    attr(malformed_variable$x, "stata.characteristics") <- c(
        `_lang_v_en` = "English label"
    )
    expect_error(
        stata_characteristics(malformed_variable, "x"),
        "malformed Stata characteristic metadata"
    )
    oversized_notes <- data
    attr(oversized_notes, "notes") <- strrep("x", 67785L)
    attr(oversized_notes, "stata.note.numbers") <- 1L
    expect_error(stata_notes(oversized_notes), "malformed Stata note metadata")
    oversized_characteristics <- data
    attr(oversized_characteristics, "stata.characteristics") <- c(
        source = strrep("x", 67785L)
    )
    expect_error(
        stata_characteristics(oversized_characteristics),
        "malformed Stata characteristic metadata"
    )
    expect_error(stata_notes(data, "missing"), "does not exist")
    expect_identical(attributes(data), attributes(data.frame(x = 1)))
})

test_that("writers reject manually attached over-limit metadata safely", {
    data <- data.frame(x = 1)
    expect_error(
        set_stata_characteristic(data, "source", strrep("x", 67785L)),
        "67,784-byte"
    )
    attr(data, "stata.characteristics") <- c(source = strrep("x", 67785L))
    for (extension in c("dta", "arrow")) {
        path <- tempfile(fileext = paste0(".", extension))
        writeBin(charToRaw("existing"), path)
        save <- if (extension == "dta") save_dta else save_arrow
        expect_error(save(data, path), "malformed Stata characteristic metadata")
        expect_identical(readBin(path, "raw", n = 8L), charToRaw("existing"))
        unlink(path)
    }
})

test_that("native metadata envelopes validate counts before allocation", {
    marker <- paste0(intToUtf8(30L), "dtatools:stata-metadata:1")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    specification <- function(metadata) list("", metadata, list(), "")

    expect_error(
        .Call(
            dtatools:::C_dtatools_write,
            specification(c(marker, "1000000000", "0")),
            path
        ),
        "note count exceeds 9,999"
    )
    expect_error(
        .Call(
            dtatools:::C_dtatools_write,
            specification(c(marker, "0", "0", "trailing")),
            path
        ),
        "counts do not match"
    )
    expect_false(file.exists(path))
})

test_that("empty write metadata uses one native sentinel at high column counts", {
    column_count <- 4096L
    data <- structure(
        rep(list(integer()), column_count),
        names = paste0("v", seq_len(column_count)),
        row.names = .set_row_names(0L),
        class = "data.frame"
    )

    dta <- dtatools:::.prepare_dta_write(data, NULL, 2045L, TRUE)
    arrow <- dtatools:::.prepare_arrow_write(data, NULL, TRUE)
    expect_null(dta[[2L]])
    expect_true(all(vapply(dta[[3L]], function(column) {
        is.null(column[[11L]])
    }, logical(1))))
    expect_null(arrow[[2L]])
    expect_true(all(vapply(arrow[[3L]], function(column) {
        is.null(column[[16L]])
    }, logical(1))))

    paths <- c(
        dta = tempfile(fileext = ".dta"),
        arrow = tempfile(fileext = ".arrow")
    )
    on.exit(unlink(paths), add = TRUE)
    input <- data.frame(x = integer())
    save_dta(input, paths[["dta"]])
    save_arrow(input, paths[["arrow"]])
    expect_identical(names(read_dta(paths[["dta"]])), "x")
    expect_identical(names(read_arrow(paths[["arrow"]])), "x")
})

test_that("Arrow retains `_dta` variable metadata that DTA cannot represent", {
    data <- data.frame(`_dta` = 1, check.names = FALSE)
    data <- set_stata_note(data, 1, "variable note", variable = "_dta")
    arrow <- tempfile(fileext = ".arrow")
    dta <- tempfile(fileext = ".dta")
    on.exit(unlink(c(arrow, dta)), add = TRUE)

    save_arrow(data, arrow)
    from_arrow <- read_arrow(arrow)
    expect_identical(stata_notes(from_arrow, "_dta"), c(`1` = "variable note"))
    for (value in list(data, from_arrow)) {
        writeBin(charToRaw("existing"), dta)
        expect_error(
            save_dta(value, dta),
            "variable named `_dta`",
            class = "dtatools_write_error"
        )
        expect_identical(readBin(dta, "raw", n = 8L), charToRaw("existing"))
    }
})

test_that("DTA and Arrow round trips retain dataset and projected variable metadata", {
    data <- data.frame(x = stata_int(c(1, 2)), y = c("a", "b"))
    attr(data$x, "labels") <- c(one = 1L, two = 2L)
    data <- set_stata_note(data, 3, "dataset gap")
    data <- set_stata_characteristic(data, "source", "survey")
    data <- set_stata_note(data, 2, "x note", variable = "x")
    data <- set_stata_characteristic(data, "role", "id", variable = "x")
    data <- set_stata_note(data, 1, "y note", variable = "y")

    dta <- tempfile(fileext = ".dta")
    arrow <- tempfile(fileext = ".arrow")
    dta_again <- tempfile(fileext = ".dta")
    arrow_again <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta, arrow, dta_again, arrow_again)), add = TRUE)

    save_dta(data, dta)
    from_dta <- read_dta(dta)
    expect_identical(stata_notes(from_dta), c(`3` = "dataset gap"))
    expect_identical(stata_characteristics(from_dta), c(source = "survey"))
    expect_identical(stata_notes(from_dta, "x"), c(`2` = "x note"))
    expect_identical(stata_characteristics(from_dta, "x"), c(role = "id"))
    expect_identical(attr(from_dta$x, "labels"), c(one = 1, two = 2))

    projected <- read_dta(dta, col_select = x)
    expect_identical(stata_notes(projected, "x"), c(`2` = "x note"))
    expect_false("y" %in% names(projected))
    windowed <- read_dta(dta, col_select = x, skip = 1, n_max = 1)
    expect_identical(stata_notes(windowed, "x"), c(`2` = "x note"))
    expect_identical(stata_notes(windowed), c(`3` = "dataset gap"))

    save_arrow(from_dta, arrow)
    from_arrow <- read_arrow(arrow)
    expect_identical(stata_notes(from_arrow), stata_notes(from_dta))
    expect_identical(
        stata_characteristics(from_arrow, "x"),
        stata_characteristics(from_dta, "x")
    )
    expect_identical(attr(from_arrow$x, "labels"), c(one = 1, two = 2))
    projected_arrow <- read_arrow(arrow, col_select = y)
    expect_identical(stata_notes(projected_arrow, "y"), c(`1` = "y note"))
    expect_false("x" %in% names(projected_arrow))
    windowed_arrow <- read_arrow(arrow, col_select = y, skip = 1, n_max = 1)
    expect_identical(stata_notes(windowed_arrow, "y"), c(`1` = "y note"))
    expect_identical(stata_notes(windowed_arrow), c(`3` = "dataset gap"))

    save_dta(from_arrow, dta_again)
    final <- read_dta(dta_again)
    expect_identical(stata_notes(final), stata_notes(data))
    expect_identical(stata_characteristics(final), stata_characteristics(data))
    expect_identical(stata_notes(final, "x"), stata_notes(data, "x"))

    save_arrow(final, arrow_again)
    arrow_final <- read_arrow(arrow_again)
    expect_identical(stata_notes(arrow_final), stata_notes(data))
    expect_identical(
        stata_characteristics(arrow_final, "x"),
        stata_characteristics(data, "x")
    )
})
