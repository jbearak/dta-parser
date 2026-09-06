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
    for (table in list(data, dplyr::group_by(data, identifier))) {
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
    for (data in list(dplyr::group_by(source, group), dplyr::rowwise(source, group))) {
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

test_that("ordinary reference containers keep their usual display", {
    tbl <- reserve_columns(tibble::tibble(x = 1:2, string = c("a", NA)))
    gen(tbl, typed = dta_int(c(1, 2)))
    expect_false(is_dibble(tbl))
    expect_match(format(tbl)[[1L]], "^# A tibble:")
    expect_match(paste(format(tbl), collapse = "\n"), "<int>", fixed = TRUE)
    expect_match(paste(format(tbl), collapse = "\n"), "<chr>", fixed = TRUE)
    expect_identical(format(tbl), format(dtatools:::.reference_snapshot(tbl)))
    frame <- reserve_columns(data.frame(x = 1:2))
    gen(frame, y = 1L)
    expect_identical(format(frame), format(dtatools:::.reference_snapshot(frame)))
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
