test_that("dibble printing names its container and declared storage", {
    data <- dibble(x = 1:2, y = 1.0:2.0, z = c("a", NA))
    output <- format(data, width = 100)
    expect_match(output[[1L]], "^# A dibble: 2")
    expect_match(output[[3L]], "<long> +<long> +<str1>")
    expect_identical(capture.output(print(data, width = 100)), output)
    capture.output(visible <- withVisible(print(data, width = 100)))
    expect_false(visible$visible)
    expect_identical(visible$value, data)

    storage <- c("byte", "int", "long", "float", "double")
    columns <- lapply(storage, function(type) {
        get(paste0("dta_", type))(c(1, NA_real_, .a))
    })
    names(columns) <- storage
    typed <- dibble(!!!columns)
    output <- paste(format(typed, width = 150), collapse = "\n")
    for (type in storage) {
        expect_match(output, paste0("<", type, ">"), fixed = TRUE)
        expect_identical(vctrs::vec_ptype_abbr(typed[[type]]), type)
        expect_identical(vctrs::vec_ptype_abbr(typed[[type]][0]), type)
    }
})

test_that("declared string labels cover constructed generated and imported columns", {
    constructed <- dibble(
        short = dta_string(c("a", ""), "str20"),
        long = dta_string(c("a", ""), "strL")
    )
    gen(constructed, generated = "wide")
    expect_identical(class(constructed$generated), "character")
    output <- paste(format(constructed, width = 100), collapse = "\n")
    for (type in c("str20", "strL", "str4")) {
        expect_match(output, paste0("<", type, ">"), fixed = TRUE)
    }
    empty <- dibble(
        short = dta_string(character(), "str80"),
        long = dta_string(character(), "strL"),
        bare = character()
    )
    gen(empty, generated = character())
    output <- paste(format(empty, width = 200), collapse = "\n")
    for (type in c("str80", "strL", "str1")) {
        expect_match(output, paste0("<", type, ">"), fixed = TRUE)
    }
    imported <- read_dta(fixture("all_types_v118.dta"))
    output <- paste(format(imported, width = 400), collapse = "\n")
    for (name in c("v_str5", "v_str20", "v_strL")) {
        type <- dta_storage_type(imported[[name]])
        expect_match(output, paste0("<", type, ">"), fixed = TRUE)
    }
})

test_that("temporal labels show storage and meaning in dibbles and tibbles", {
    data <- dibble(
        day = as.Date(c("2020-01-01", NA)),
        time = as.POSIXct(c("2020-01-01 12:34:56", NA), tz = "UTC")
    )
    expect_identical(vctrs::vec_ptype_abbr(data$day), "float/date")
    expect_identical(vctrs::vec_ptype_abbr(data$time), "double/dttm")
    for (table in list(data, tibble::as_tibble(data))) {
        output <- paste(format(table, width = 100), collapse = "\n")
        expect_match(output, "<float/date>", fixed = TRUE)
        expect_match(output, "<double/dttm>", fixed = TRUE)
        expect_match(output, "2020-01-01", fixed = TRUE)
        expect_match(output, "12:34:56", fixed = TRUE)
    }
    empty <- data[FALSE, ]
    expect_match(paste(format(empty), collapse = "\n"), "<float/date>", fixed = TRUE)
    expect_match(paste(format(empty), collapse = "\n"), "<double/dttm>", fixed = TRUE)
    imported <- read_dta(fixture_with_temporal_storage("foreign"))
    expect_identical(vctrs::vec_ptype_abbr(imported$foreign), "byte/date")
})

test_that("metadata wrappers preserve string storage labels and cell formatting", {
    data <- dibble(identifier = 1:3, text = c("a", "", "b"))
    set_dta_note(data, 1L, "note", variable = "text")
    set_dta_characteristic(data, "source", "survey", variable = "text")
    alias <- data
    before <- attributes(data$text)
    expect_identical(class(data$text), "dtatools_dta_metadata_vector")
    grouped <- as_dibble(.group_fixture("identifier_123_text_typed")$data)
    set_dta_note(grouped, 1L, "note", variable = "text")
    set_dta_characteristic(grouped, "source", "survey", variable = "text")
    for (table in list(data, grouped)) {
        wide <- paste(format(table, width = 100L), collapse = "\n")
        narrow <- paste(format(table, width = 12L, n = 1L), collapse = "\n")
        expect_match(wide, "<str1>", fixed = TRUE)
        expect_match(narrow, "text <str1>", fixed = TRUE)
        display <- dtatools:::.dibble_display_snapshot(table)
        expect_identical(vctrs::vec_ptype_abbr(vctrs::vec_slice(display, 1L)$text), "str1")
    }
    expect_identical(attributes(data$text), before)
    expect_identical(attributes(alias$text), before)
    expect_identical(dta_note(data, 1L, variable = "text"), "note")
    expect_identical(dta_characteristic(data, "source", variable = "text"), "survey")
})

test_that("metadata setters leave declared string types visible", {
    withr::local_options(pillar.max_extra_cols = 100L, pillar.max_footer_lines = 100L)
    factories <- list(
        bare = function() dibble(id = 1:2, text = c("a", "")),
        owned = function() dibble(id = 1:2, text = dta_string(c("a", ""), "str80")),
        generated = function() {
            data <- dibble(id = 1:2)
            gen(data, text = "a")
            data
        },
        imported = function() {
            data <- read_dta(fixture("all_types_v118.dta"))
            rename_vars(data, text = v_str5)
            data
        }
    )
    setters <- list(
        format = function(data) set_var_format(data, text, "%20s"),
        formats = function(data) set_var_formats(data, text = "%20s"),
        label = function(data) set_var_label(data, text, "Text"),
        note = function(data) set_dta_note(data, 1L, "note", variable = "text"),
        characteristic = function(data) set_dta_characteristic(data, "source", "survey", variable = "text"),
        bundle = function(data) set_dta_metadata(data, notes = "note", stata.note.numbers = 1L, variable = "text")
    )
    for (factory in factories) {
        for (setter in setters) {
            data <- factory()
            setter(data)
            before <- attributes(data$text)
            type <- paste0("<", dta_storage_type(data$text), ">")
            expect_match(paste(format(data, width = 400L), collapse = "\n"), type, fixed = TRUE)
            expect_match(paste(format(data, width = 10L, n = 1L), collapse = "\n"), paste("text", type), fixed = TRUE)
            expect_identical(attributes(data$text), before)
            if (inherits(data$text, "dta_string")) {
                ordinary <- tibble::tibble(text = data$text)
                expect_match(format(ordinary)[[1L]], "^# A tibble:")
                expect_match(paste(format(ordinary), collapse = "\n"), type, fixed = TRUE)
            }
        }
    }
})

test_that("display snapshots retain grouping and empty dimensions", {
    source <- dibble(group = c("a", "b", "a"), value = 1:3)
    for (data in list(as_dibble(.group_fixture("group_aba_typed")$data),
                      as_dibble(.group_fixture("group_aba_typed_rowwise")$data))) {
        output <- format(data, width = 100)
        expect_match(output[[1L]], "^# A dibble: 3")
        expect_match(output[[2L]], if (inherits(data, "grouped_df")) "Groups:.*group" else "Rowwise:.*group")
        expect_identical(capture.output(print(data, width = 100)), output)
    }
    for (rows in c(0L, 3L)) {
        data <- dibble(.rows = rows)
        expect_match(format(data)[[1L]], paste0("^# A dibble: ", rows, " .* 0$"))
        expect_identical(capture.output(print(data)), format(data))
    }
    expect_match(format(source[FALSE, ])[[1L]], "^# A dibble: 0 .* 2$")
})

test_that("narrow output and row slicing retain omitted string declarations", {
    withr::local_options(pillar.min_chars = 3L, pillar.max_extra_cols = 100L)
    data <- dibble(identifier = 1:20)
    gen(data, generated = "a")
    gen(data, declared = dta_string(rep("b", 20), "str80"))
    snapshot <- dtatools:::.dibble_display_snapshot(data)
    for (rows in list(integer(), 1L, c(1L, 20L))) {
        sliced <- vctrs::vec_slice(snapshot, rows)
        expect_identical(vctrs::vec_ptype_abbr(sliced$generated), "str1")
        expect_identical(vctrs::vec_ptype_abbr(sliced$declared), "str80")
    }
    for (n in c(0L, 1L, 3L)) {
        output <- format(data, width = 12L, n = n)
        text <- paste(output, collapse = "\n")
        expect_match(text, "generated <str1>", fixed = TRUE)
        expect_match(text, "declared <str80>", fixed = TRUE)
        expect_identical(paste(capture.output(print(data, width = 12L, n = n)), collapse = "\n"), text)
    }
    withr::local_options(tibble.print_max = 2L, tibble.print_min = 1L)
    expect_match(paste(format(data), collapse = "\n"), "19 more rows", fixed = TRUE)
})

test_that("ordinary containers keep their usual display and reject by-reference helpers", {
    tbl <- tibble::tibble(x = 1:2, string = c("a", NA))
    before <- serialize(tbl, NULL)
    expect_error(gen(tbl, typed = dta_int(c(1, 2))), "must be a dibble")
    expect_false(is_dibble(tbl))
    expect_identical(serialize(tbl, NULL), before)
    expect_match(format(tbl)[[1L]], "^# A tibble:")
    expect_match(paste(format(tbl), collapse = "\n"), "<int>", fixed = TRUE)
    expect_match(paste(format(tbl), collapse = "\n"), "<chr>", fixed = TRUE)
    frame <- data.frame(x = 1:2)
    expect_error(gen(frame, y = 1L), "must be a dibble")
    expect_identical(format(frame), format(data.frame(x = 1:2)))
})
test_that("printing preserves cells metadata aliases and compact backing", {
    data <- read_dta(fixture("all_types_v118.dta"))
    gen(data, generated = c("a", "", "b"), where = 1:3)
    alias <- data
    columns <- as.list(data)
    before <- lapply(columns, attributes)
    table_attributes <- attributes(data)
    state <- as.list(dtatools:::.reference_state(data))
    compact <- function() c(
        vapply(c("v_byte", "v_int", "v_long", "v_float"), function(name) {
            dtatools:::.is_unmaterialized_numeric_altrep(data[[name]])
        }, logical(1)),
        vapply(c("v_str5", "v_str20", "v_strL"), function(name) {
            dtatools:::.is_unmaterialized_dictstring(data[[name]])
        }, logical(1))
    )
    expect_true(all(compact()))
    # Widen columns equally so changing the type header cannot change cell
    # padding. Drop headings and type rows to compare the existing formatter.
    withr::local_options(pillar.min_chars = 20L)
    old <- format(dtatools:::.reference_snapshot(data), width = 1000L)
    printed <- capture.output(print(data, width = 1000L))
    cell_rows <- function(lines) lines[grepl("^[0-9]", lines)]
    expect_identical(cell_rows(printed), cell_rows(old))
    for (width in c(15L, 80L, 1000L)) {
        expect_identical(paste(capture.output(print(data, width = width)), collapse = "\n"), paste(format(data, width = width), collapse = "\n"))
    }
    expect_true(all(compact()))
    expect_identical(attributes(data), table_attributes)
    expect_identical(lapply(as.list(data), attributes), before)
    expect_identical(as.list(dtatools:::.reference_state(data)), state)
    expect_identical(as.list(alias), columns)
    expect_identical(class(data$generated), "character")
})

test_that("Stata numerics format and print missing values as Stata spells them", {
    values <- dta_double(c(a = 1.5, b = 100, c = NA, d = tagged_missing("a")))
    expect_identical(
        format(values), c(a = "  1.5", b = "100.0", c = "    .", d = "   .a")
    )
    expect_identical(format(values, trim = TRUE), c(a = "1.5", b = "100.0", c = ".", d = ".a"))
    expect_identical(format(dta_byte(c(1, NA, .z))), c(" 1", " .", ".z"))
    expect_identical(format(dta_byte(double())), character())
    expect_identical(format(dta_int(c(7, 8))), format(c(7, 8)))

    printed <- capture.output(print(dta_byte(c(1, 2, .a, NA))))
    expect_identical(printed[[1L]], "<dta_numeric[4]>")
    expect_match(printed[[2L]], "^\\[1\\] +1 +2 +\\.a +\\.$")

    # A labelled vector lists its table under the values, codes in the
    # same spelling; a table-less vector prints no footer.
    labelled <- set_val_labels(
        dta_byte(c(1, 2, .a, NA)), One = 1, Refused = .a
    )
    printed <- capture.output(print(labelled))
    expect_identical(printed[[1L]], "<dta_numeric[4]>")
    expect_true(any(printed == "Labels:"))
    expect_match(paste(printed, collapse = "\n"), "\\.a +Refused")
    expect_match(paste(printed, collapse = "\n"), "1 +One")
    expect_length(capture.output(print(dta_byte(c(1, 2)))), 2L)

    # Dibble, tibble, and data frame columns show the same spelling.
    data <- dibble(
        v = dta_double(c(1.5, 100, NA, .a)),
        w = dta_byte(c(1, 2, NA, .z)),
        x = labelled
    )
    output <- capture.output(print(data, width = 100))
    body <- paste(output[-(1:3)], collapse = "\n")
    expect_match(body, "\\. +\\. +\\.a")
    expect_match(body, "\\.a +\\.z +\\.")
    expect_false(grepl("NA", body, fixed = TRUE))
    tbl <- capture.output(print(tibble::as_tibble(data), width = 100))
    expect_false(any(grepl("NA", tbl[-(1:3)], fixed = TRUE)))
    frame <- capture.output(print(data.frame(v = dta_byte(c(1, NA, .b)))))
    expect_match(frame[[3L]], "\\.$")
    expect_match(frame[[4L]], "\\.b$")

    # Dates and datetimes keep their calendar formatting.
    dated <- dibble(i = 1:2)
    gen(dated, day = as.Date(c("2020-01-01", NA)))
    dated_output <- paste(capture.output(print(dated, width = 100)), collapse = "\n")
    expect_match(dated_output, "2020-01-01")
    expect_identical(format(dated$day), format(as.Date(c("2020-01-01", NA))))

    # The shared spelling covers every code the reader reports.
    expect_identical(
        dtatools:::.stata_missing_text(c(NA, 0L, utf8ToInt("a"), utf8ToInt("z"), 256L)),
        c(NA, ".", ".a", ".z", "NaN")
    )

    # A caller's width is honoured when every value is missing.
    expect_identical(format(dta_byte(c(NA, .a)), width = 8), c("       .", "      .a"))
    expect_identical(format(dta_byte(c(1, NA)), width = 8), c("       1", "       ."))
    # `trim` is base's second positional argument, and an explicit `width`
    # survives `trim`, as it does in base.
    expect_identical(format(dta_byte(c(1, NA)), TRUE), c("1", "."))
    expect_identical(format(dta_double(c(1.234, NA)), FALSE, 2L), c("1.2", "  ."))
    expect_identical(
        format(dta_byte(c(1, NA)), trim = TRUE, width = 8), c("       1", "       .")
    )
    expect_identical(format(dta_byte(c(1, 100, NA)), trim = TRUE), c("1", "100", "."))
    # `width` passed by position, as base's sixth argument.
    expect_identical(
        format(dta_byte(c(1, NA)), TRUE, NULL, 0L, "right", 8L),
        c("       1", "       .")
    )
    expect_identical(format(dta_double(c(1.5, NA)), nsmall = 2L), c("1.50", "   ."))
    # Each missing cell takes the width base gave the `NA` it replaces, so
    # a narrow `width` under `trim` leaves the observed cells as base has
    # them, and `width = 0` still lines the spellings up.
    expect_identical(
        format(dta_double(c(-1234.5, 0, NA)), trim = TRUE, width = 1),
        c("-1234.5", "0.0", ".")
    )
    expect_identical(format(dta_byte(c(1, 100, NA)), width = 0), c("  1", "100", "  ."))
    expect_identical(format(dta_byte(c(1, NA)), width = 3), c("  1", "  ."))
})

test_that("a value-labelled column annotates its cells and the option turns it off", {
    labelled <- set_val_labels(
        dta_byte(c(1, 2, .a, NA)), One = 1, Refused = .a
    )
    data <- dibble(x = labelled, y = dta_double(c(1.5, 100, NA, .a)))
    cells <- function(...) {
        lines <- capture.output(print(data, width = 100, ...))
        lines[grepl("^[0-9]", lines)]
    }
    shown <- cells()
    expect_match(shown[[1L]], "1 \\[One\\] +1\\.5$")
    expect_match(shown[[2L]], "^2 +2 +100")
    expect_match(shown[[3L]], "\\.a \\[Refused\\] +\\.$")
    expect_match(shown[[4L]], "^4 +\\. +\\.a$")
    expect_false(any(grepl("NA", shown, fixed = TRUE)))

    withr::with_options(list(dtatools.show_pillar_labels = FALSE), {
        hidden <- cells()
        expect_false(any(grepl("[", hidden, fixed = TRUE)))
        expect_match(hidden[[3L]], "\\.a +\\.$")
    })
    # haven's option of the same meaning is honoured when ours is unset.
    withr::with_options(list(haven.show_pillar_labels = FALSE), {
        expect_false(any(grepl("[", cells(), fixed = TRUE)))
    })
    withr::with_options(
        list(haven.show_pillar_labels = FALSE, dtatools.show_pillar_labels = TRUE),
        expect_true(any(grepl("[One]", cells(), fixed = TRUE)))
    )

    # A code matches by value, whatever the other observations look like,
    # and `show_labels` on the shaft itself is honoured.
    mixed <- set_val_labels(dta_double(c(1, 1.5, .a)), One = 1, Refused = .a)
    rows <- capture.output(print(dibble(m = mixed), width = 100))
    expect_match(rows[[4L]], "1 +\\[One\\]")
    expect_match(rows[[6L]], "\\.a \\[Refused\\]")
    expect_no_warning(shaft <- pillar::pillar_shaft(mixed, show_labels = FALSE))
    expect_false(any(grepl("[", format(shaft, width = 20), fixed = TRUE)))

    # Label text is escaped so a control character cannot break the row.
    tricky <- set_val_labels(dta_byte(c(1, 2)), "hello\nworld" = 1, "tab\there" = 2)
    rows <- capture.output(print(dibble(t = tricky), width = 100))
    expect_length(rows, 5L)
    expect_match(rows[[4L]], "hello\\\\nworld", fixed = FALSE)
    expect_match(rows[[5L]], "tab\\\\there", fixed = FALSE)

    # An empty labelled column is a valid shaft, as pillar asks for one on
    # a prototype.
    empty <- set_val_labels(dta_byte(double()), One = 1)
    expect_no_warning(shaft <- pillar::pillar_shaft(empty))
    expect_length(format(shaft, width = 10), 0L)
    expect_output(print(dibble(e = empty)), "A dibble: 0")

    # A wide-glyph label is cut by display width, so the cell never
    # overruns the width the shaft declared.
    wide <- set_val_labels(dta_byte(c(1, 2)), "\u4e2d\u6587\u6807\u7b7e\u5f88\u957f" = 1)
    shaft <- pillar::pillar_shaft(wide)
    for (w in c(6L, 8L, 9L, 12L)) {
        cells <- as.character(format(shaft, width = w))
        expect_true(all(pillar::get_extent(cells) <= w), info = w)
    }
    # With colours on, the cut falls on the text and never on the escape
    # sequence, so each cell holds a whole, closed style.
    local({
        testthat::local_reproducible_output(crayon = TRUE)
        # pillar caches its colour count on first use, so an earlier
        # uncoloured test would otherwise leave styling off here.
        testthat::local_mocked_bindings(
            num_colors = function(forget = FALSE) 8L, .package = "pillar"
        )
        long <- set_val_labels(dta_byte(c(1, 2)), "a label that runs long" = 1)
        shaft <- pillar::pillar_shaft(long)
        for (w in c(6L, 10L, 16L)) {
            cells <- as.character(format(shaft, width = w))
            plain <- cli::ansi_strip(cells)
            expect_true(all(pillar::get_extent(plain) <= w), info = w)
            escape <- "\033\\[[0-9;]*m"
            expect_match(cells[[1L]], paste0("^1", escape, " \\[a.*\u2026", escape, "$"),
                         info = as.character(w))
            expect_identical(cli::ansi_nchar(cells[[1L]]), pillar::get_extent(plain[[1L]]))
        }
    })

    # A long label never costs a value its digits: while the full value and
    # a cut label fit, the value is rendered whole and the label is cut.
    big <- set_val_labels(dta_double(c(123456789, 1)), "a label that runs long" = 1)
    shaft <- pillar::pillar_shaft(big)
    inner <- pillar::pillar_shaft(c(123456789, 1))
    full <- attr(inner, "width")
    cells <- as.character(format(shaft, width = full + 6L))
    expect_match(cells[[1L]], "^123456789 *$")
    expect_match(cells[[2L]], "^ *1 \\[a.*…$")
    expect_true(all(pillar::get_extent(cells) <= full + 6L))
    narrow <- as.character(format(shaft, width = attr(shaft, "min_width")))
    expect_true(all(pillar::get_extent(narrow) <= attr(shaft, "min_width")))
    expect_match(narrow[[1L]], "e8|e\\+08")

    # The observed cells are pillar's own rendering, so `sigfig` and the
    # `pillar.sigfig` option apply to a labelled column as to any double.
    precise <- set_val_labels(dta_double(c(pi, 1 / 3, NA)), One = 1)
    shaft <- pillar::pillar_shaft(precise, sigfig = 3)
    cells <- as.character(format(shaft, width = 20))
    expect_match(cells[[1L]], "^ *3\\.14 ")
    expect_match(cells[[2L]], "^ *0\\.333")
    expect_match(cells[[3L]], "^ *\\. *$")
    withr::with_options(list(pillar.sigfig = 3), {
        lines <- capture.output(print(dibble(p = precise), width = 100))
        expect_match(lines[[4L]], "3\\.14 ")
        expect_false(any(grepl("3.141593", lines, fixed = TRUE)))
    })

    # A table-less column has no annotation and stays right-aligned.
    plain <- dibble(x = dta_byte(c(1, 22, NA)))
    lines <- capture.output(print(plain, width = 100))
    expect_match(lines[[4L]], " 1$")
    expect_match(lines[[5L]], "22$")
    expect_match(lines[[6L]], " \\.$")
})
