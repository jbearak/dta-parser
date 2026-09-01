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
    expect_error(
        set_stata_characteristic(data, "fralias_from", "source frame"),
        "structural key"
    )
    expect_error(
        set_stata_characteristic(data, "fralias_varname", "source variable"),
        "structural key"
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

test_that("base and tibble subsetting preserve Stata metadata", {
    inputs <- list(
        base = data.frame(x = 1:2, y = 3:4),
        tibble = tibble::tibble(x = 1:2, y = 3:4)
    )
    for (kind in names(inputs)) {
        data <- inputs[[kind]]
        data <- set_stata_note(data, 3, "dataset")
        data <- set_stata_characteristic(data, "source", "survey")
        data <- set_stata_note(data, 2, "x note", variable = "x")
        data <- set_stata_characteristic(data, "role", "id", variable = "x")

        subsets <- list(
            rows = data[1L, , drop = FALSE],
            columns = data[c("y", "x")],
            one_column = data[, "x", drop = FALSE]
        )
        for (subset_name in names(subsets)) {
            subset <- subsets[[subset_name]]
            expect_identical(
                stata_notes(subset), c(`3` = "dataset"),
                info = paste(kind, subset_name)
            )
            expect_identical(
                stata_characteristics(subset), c(source = "survey"),
                info = paste(kind, subset_name)
            )
            if ("x" %in% names(subset)) {
                expect_identical(
                    stata_notes(subset, "x"), c(`2` = "x note"),
                    info = paste(kind, subset_name)
                )
                expect_identical(
                    stata_characteristics(subset, "x"), c(role = "id"),
                    info = paste(kind, subset_name)
                )
            }
        }

        extracted <- data[, "x"]
        if (is.data.frame(extracted)) {
            expect_identical(stata_notes(extracted), c(`3` = "dataset"))
            expect_identical(
                stata_notes(extracted, "x"), c(`2` = "x note")
            )
        } else {
            expect_identical(stata_notes(extracted), c(`2` = "x note"))
            expect_identical(
                stata_characteristics(extracted), c(role = "id")
            )
        }

        for (extension in c("dta", "arrow")) {
            path <- tempfile(fileext = paste0(".", extension))
            on.exit(unlink(path), add = TRUE)
            save <- if (extension == "dta") save_dta else save_arrow
            read <- if (extension == "dta") read_dta else read_arrow
            suppressWarnings(save(subsets$rows, path))
            restored <- read(path)
            expect_identical(stata_notes(restored), c(`3` = "dataset"))
            expect_identical(
                stata_characteristics(restored), c(source = "survey")
            )
            expect_identical(stata_notes(restored, "x"), c(`2` = "x note"))
            expect_identical(
                stata_characteristics(restored, "x"), c(role = "id")
            )
        }

        cleared <- drop_stata_notes(data)
        cleared <- drop_stata_characteristics(cleared)
        cleared <- drop_stata_notes(cleared, variable = "x")
        cleared <- drop_stata_characteristics(cleared, variable = "x")
        expect_false(inherits(cleared, "dtatools_stata_metadata"))
    }
})

test_that("vctrs preserves metadata on supported plain vector types", {
    values <- list(
        character = c("a", "b"),
        logical = c(TRUE, FALSE),
        factor = factor(c("a", "b")),
        ordered = ordered(c("a", "b")),
        raw = as.raw(c(1L, 2L)),
        integer = 1:2,
        double = c(1, 2)
    )
    for (kind in names(values)) {
        plain <- values[[kind]]
        left <- set_stata_note(plain, 3L, "left note")
        left <- set_stata_characteristic(left, "source", "master")
        right <- set_stata_note(plain, 7L, "right note")
        right <- set_stata_characteristic(right, "source", "using")

        left_right <- vctrs::vec_c(left, right)
        right_left <- vctrs::vec_c(right, left)
        fallback <- vctrs::vec_c(plain, right)
        prototype <- vctrs::vec_ptype2(left, right)
        cast_to_plain <- vctrs::vec_cast(left, plain[0])
        expect_identical(
            stata_notes(left_right), c(`3` = "left note"), info = kind
        )
        expect_identical(
            stata_characteristics(left_right), c(source = "master"),
            info = kind
        )
        expect_identical(
            stata_notes(right_left), c(`7` = "right note"), info = kind
        )
        expect_identical(
            stata_characteristics(fallback), c(source = "using"),
            info = kind
        )
        expect_identical(
            stata_characteristics(prototype), c(source = "master"),
            info = kind
        )
        expect_identical(cast_to_plain, plain, info = kind)
        expect_false(
            inherits(cast_to_plain, "dtatools_stata_metadata_vector"),
            info = kind
        )
        expect_length(stata_notes(cast_to_plain), 0L)
        expect_length(stata_characteristics(cast_to_plain), 0L)
    }

    ordinary <- vctrs::vec_c("a", "b")
    expect_null(attr(ordinary, "class", exact = TRUE))
    expect_false(inherits(ordinary, "dtatools_stata_metadata_vector"))
})

test_that("dplyr recode treats metadata vector markers as transparent", {
    numeric <- set_stata_note(c(1, 2), 4L, "numeric note")
    numeric <- set_stata_characteristic(numeric, "source", "numeric")
    character <- set_stata_note(c("a", "b"), 5L, "character note")
    character <- set_stata_characteristic(
        character, "source", "character"
    )

    recoded_numeric <- dplyr::recode(numeric, `1` = 10)
    recoded_character <- dplyr::recode(character, a = "A")

    expect_identical(as.vector(recoded_numeric), c(10, 2))
    expect_identical(stata_notes(recoded_numeric), c(`4` = "numeric note"))
    expect_identical(
        stata_characteristics(recoded_numeric), c(source = "numeric")
    )
    expect_identical(as.vector(recoded_character), c("A", "b"))
    expect_identical(
        stata_notes(recoded_character), c(`5` = "character note")
    )
    expect_identical(
        stata_characteristics(recoded_character), c(source = "character")
    )
})

test_that("metadata vector markers remain writable", {
    character <- set_stata_note(c("a", "b"), 1L, "character note")
    logical <- set_stata_note(c(TRUE, FALSE), 1L, "logical note")
    factor <- set_stata_note(factor(c("a", "b")), 1L, "factor note")
    integer <- set_stata_note(1:2, 1L, "integer note")
    double <- set_stata_note(c(1, 2), 1L, "double note")
    raw <- set_stata_note(as.raw(c(1L, 2L)), 1L, "raw note")

    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta_path, arrow_path)), add = TRUE)
    dta <- data.frame(
        text = character, flag = logical, group = factor,
        count = integer, measure = double
    )
    arrow <- data.frame(
        text = character, flag = logical, group = factor,
        count = integer, measure = double, bytes = raw
    )
    expected <- c(
        text = "character note", flag = "logical note",
        group = "factor note", count = "integer note",
        measure = "double note", bytes = "raw note"
    )
    suppressWarnings(save_dta(dta, dta_path))
    suppressWarnings(save_arrow(arrow, arrow_path))

    from_dta <- read_dta(dta_path)
    from_arrow <- read_arrow(arrow_path)
    for (name in names(dta)) {
        expect_identical(
            stata_note(from_dta, 1L, variable = name),
            unname(expected[[name]])
        )
    }
    for (name in names(arrow)) {
        expect_identical(
            stata_note(from_arrow, 1L, variable = name),
            unname(expected[[name]])
        )
    }
})

test_that("Arrow writes labelled numeric vectors with Stata metadata", {
    integer <- 1:2
    val_labels(integer) <- c(one = 1L, two = 2L)
    integer <- set_stata_note(integer, 2L, "integer note")
    integer <- set_stata_characteristic(integer, "source", "integer")

    double <- c(1, 2)
    val_labels(double) <- c(one = 1, two = 2)
    double <- set_stata_note(double, 3L, "double note")
    double <- set_stata_characteristic(double, "source", "double")

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(tibble::tibble(integer, double), path)
    restored <- read_arrow(path)

    expect_identical(stata_notes(restored$integer), c(`2` = "integer note"))
    expect_identical(
        stata_characteristics(restored$integer), c(source = "integer")
    )
    expect_identical(stata_notes(restored$double), c(`3` = "double note"))
    expect_identical(
        stata_characteristics(restored$double), c(source = "double")
    )
    expect_equal(val_labels(restored$integer), c(one = 1, two = 2))
    expect_equal(val_labels(restored$double), c(one = 1, two = 2))
})

test_that("wide subsets restore only metadata-bearing variables", {
    original <- dtatools:::.copy_stata_metadata_attributes
    calls <- 0L
    testthat::local_mocked_bindings(
        .copy_stata_metadata_attributes = function(...) {
            calls <<- calls + 1L
            original(...)
        },
        .package = "dtatools"
    )

    work <- integer()
    for (width in c(4000L, 8000L)) {
        data <- structure(
            rep(list(integer()), width),
            names = paste0("v", seq_len(width)),
            row.names = .set_row_names(0L),
            class = "data.frame"
        )
        attr(data, "notes") <- "dataset"
        attr(data, "stata.note.numbers") <- 1L
        data <- dtatools:::.as_stata_metadata_frame(data)
        calls <- 0L
        subset <- data[rev(names(data))]
        work <- c(work, calls)
        expect_identical(stata_note(subset, 1L), "dataset")
    }
    expect_identical(work, c(1L, 1L))

    data <- structure(
        rep(list(integer()), 8000L),
        names = paste0("v", seq_len(8000L)),
        row.names = .set_row_names(0L),
        class = "data.frame"
    )
    attr(data[[1L]], "stata.characteristics") <- c(role = "first")
    attr(data[[8000L]], "stata.characteristics") <- c(role = "last")
    data <- dtatools:::.as_stata_metadata_frame(data)
    calls <- 0L
    subset <- data[rev(names(data))]
    expect_identical(calls, 3L)
    expect_identical(
        stata_characteristic(subset, "role", variable = "v1"), "first"
    )
    expect_identical(
        stata_characteristic(subset, "role", variable = "v8000"), "last"
    )
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

test_that("legacy decoded metadata survives R access and Arrow round trips", {
    bytes <- readBin(
        fixture("synthetic_v111.dta"), "raw",
        n = file.info(fixture("synthetic_v111.dta"))[["size"]]
    )
    note_start <- grepRaw(
        charToRaw("note1"), bytes, fixed = TRUE, all = TRUE
    )[[1L]]
    name_width <- 33L
    header_width <- 5L
    payload_start <- note_start - name_width
    header_start <- payload_start - header_width
    endian <- if (bytes[[2L]] == as.raw(1L)) "big" else "little"
    old_payload <- readBin(
        bytes[header_start + 1:4], integer(), n = 1L, size = 4L,
        endian = endian
    )
    value_start <- note_start + name_width
    payload_end <- payload_start + old_payload - 1L
    source_value <- rep(as.raw(0x80), 22595L)
    new_payload <- 2L * name_width + length(source_value) + 1L
    bytes <- c(
        bytes[seq_len(value_start - 1L)], source_value, as.raw(0L),
        bytes[(payload_end + 1L):length(bytes)]
    )
    bytes[header_start + 1:4] <- writeBin(
        new_payload, raw(), size = 4L, endian = endian
    )
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    modern_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(dta_path, arrow_path, modern_path)), add = TRUE)
    writeBin(bytes, dta_path)

    expected <- strrep(intToUtf8(0x20acL), 22595L)
    expect_identical(nchar(expected, type = "bytes"), 67785L)
    data <- read_dta(dta_path)
    expect_identical(stata_note(data, 1L), expected)
    expect_no_error(save_arrow(data, arrow_path))
    expect_identical(stata_note(read_arrow(arrow_path), 1L), expected)
    modern <- data.frame(x = 1L)
    attr(modern, "notes") <- expected
    expect_error(save_dta(modern, modern_path), "invalid internal Stata note metadata")
    expect_false(file.exists(modern_path))
})

test_that("native metadata envelopes validate counts before allocation", {
    marker <- paste0(intToUtf8(30L), "dtatools:stata-metadata:1")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    specification <- function(metadata) list("", metadata, list(), "", list())

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
        is.null(column[["stata_metadata"]])
    }, logical(1))))
    expect_null(arrow[[2L]])
    expect_true(all(vapply(arrow[[3L]], function(column) {
        is.null(column[["stata_metadata"]])
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
