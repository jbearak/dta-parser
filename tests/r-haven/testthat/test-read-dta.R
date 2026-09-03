test_that("dplyr recoding preserves unselected Stata missing codes", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")
    expected_tags <- c(NA_character_, letters)
    recoded_tags <- expected_tags
    recoded_tags[c(2L, 7L)] <- NA_character_
    recoded_missing <- rep(TRUE, 27L)
    recoded_missing[c(2L, 7L)] <- FALSE

    recode_tags <- function(data) {
        dplyr::mutate(
            data,
            dplyr::across(
                dplyr::everything(),
                function(values) {
                    dplyr::case_when(
                        is_tagged_missing(values, "a") ~ -1,
                        is_tagged_missing(values, "f") ~ -6,
                        .default = values
                    )
                }
            )
        )
    }
    recode_observed <- function(data) {
        dplyr::mutate(
            data,
            dplyr::across(
                dplyr::everything(),
                function(values) {
                    dplyr::if_else(is.na(values), values, values + 1)
                }
            )
        )
    }

    paths <- character()
    on.exit(unlink(paths), add = TRUE)
    for (name in c("missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture_with_all_numeric_missing_codes(name)
        paths <- c(paths, path)
        storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")
        reference_tags <- recode_tags(haven::read_dta(path, n_max = 27))
        reference_observed <- recode_observed(
            haven::read_dta(path, n_max = 30)
        )

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            tagged <- recode_tags(read_dta(
                path,
                n_max = 27,
                use_numeric_altrep = use_numeric_altrep
            ))
            source <- read_dta(
                path,
                n_max = 30,
                use_numeric_altrep = use_numeric_altrep
            )
            observed <- recode_observed(source)
            mode <- if (use_numeric_altrep) "default" else "eager"

            for (index in seq_along(tagged)) {
                info <- paste(name, storage[[index]], mode)
                expect_identical(
                    as.double(tagged[[index]]),
                    as.double(reference_tags[[index]]),
                    info = paste(info, "selective recode matches haven")
                )
                expect_identical(
                    missing_tag(tagged[[index]]),
                    recoded_tags,
                    info = paste(info, "unselected tags")
                )
                expect_identical(
                    is.na(tagged[[index]]),
                    recoded_missing,
                    info = paste(info, "missing positions")
                )
                expect_identical(
                    unname(as.double(tagged[[index]][c(2L, 7L)])),
                    c(-1, -6),
                    info = paste(info, "selected replacements")
                )
                expect_identical(
                    as.double(observed[[index]]),
                    as.double(reference_observed[[index]]),
                    info = paste(info, "observed recode matches haven")
                )
                expect_identical(
                    missing_tag(observed[[index]][seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "observed recode tags")
                )

                condition <- source[[index]] == source[[index]][[28L]]
                expect_false(
                    anyNA(condition),
                    info = paste(info, "Stata comparison predicate")
                )
                comparison_if_else <- dplyr::if_else(
                    condition, -1, source[[index]]
                )
                expect_identical(
                    missing_tag(comparison_if_else[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "Stata comparison if_else tags")
                )

                registered_recode <- rlang::exec(
                    dplyr::recode,
                    source[[index]],
                    !!!stats::setNames(
                        list(-1), as.character(source[[index]][[28L]])
                    )
                )
                expect_identical(
                    missing_tag(registered_recode[seq_len(27L)]),
                    expected_tags,
                    info = paste(info, "registered recode tags")
                )
                expect_identical(
                    unname(as.double(registered_recode[[28L]])),
                    -1,
                    info = paste(info, "registered recode replacement")
                )
            }
        }
    }
})

test_that("dplyr manipulation matches haven for every storage type", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")

    manipulate <- function(data) {
        dplyr::mutate(
            data,
            dplyr::across(
                dplyr::everything(),
                function(values) {
                    if (is.character(values)) {
                        dplyr::if_else(
                            is.na(values), values, paste0(values, "-recoded")
                        )
                    } else {
                        dplyr::if_else(is.na(values), values, values + 1)
                    }
                }
            )
        )
    }

    for (name in c("all_types_v115.dta", "all_types_v118.dta")) {
        path <- fixture(name)
        reference <- haven::read_dta(path)
        expected <- manipulate(reference)
        storage <- attr(dtatools:::.dta_metadata(path), "dta_storage")

        for (use_numeric_altrep in c(TRUE, FALSE)) {
            source <- read_dta(
                path,
                use_numeric_altrep = use_numeric_altrep
            )
            actual <- manipulate(source)
            mode <- if (use_numeric_altrep) "default" else "eager"
            expect_identical(names(actual), names(expected))
            for (index in seq_along(actual)) {
                actual_value <- without_stata_storage(actual[[index]])
                expected_value <- expected[[index]]
                attr(actual_value, "label") <- NULL
                attr(expected_value, "label") <- NULL
                if (identical(storage[[index]], "character")) {
                    expect_identical(
                        attr(actual_value, "format.stata", exact = TRUE),
                        attr(source[[index]], "format.stata", exact = TRUE),
                        info = paste(name, storage[[index]], mode, "format")
                    )
                    attr(actual_value, "format.stata") <- NULL
                }
                expect_equal(
                    actual_value,
                    expected_value,
                    tolerance = if (identical(storage[[index]], "float")) {
                        1e-6
                    } else {
                        0
                    },
                    info = paste(name, storage[[index]], mode)
                )
                if (!identical(storage[[index]], "character")) {
                    expect_identical(
                        var_label(actual[[index]]),
                        var_label(reference[[index]]),
                        info = paste(name, storage[[index]], mode, "label")
                    )
                }
            }
        }
    }
})

test_that("dplyr manipulation matches haven for labelled and temporal data", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    tagged_date <- structure(
        c(0, unclass(tagged_missing("a")), NA_real_),
        class = "Date"
    )
    tagged_instant <- structure(
        c(0, unclass(tagged_missing("b")), NA_real_),
        class = c("POSIXct", "POSIXt"),
        tzone = "UTC"
    )
    input <- tibble::tibble(
        labelled = labelled_for_test(
            c(1, tagged_missing("c"), NA_real_),
            labels = c(one = 1)
        ),
        date = tagged_date,
        instant = tagged_instant,
        text = c("alpha", "", "omega")
    )
    haven::write_dta(input, path, version = 15)

    manipulate <- function(data) {
        dplyr::mutate(
            data,
            labelled = dplyr::case_when(
                labelled == 1 ~ 2,
                .default = labelled
            ),
            date = dplyr::if_else(is.na(date), date, date + 1),
            instant = dplyr::if_else(
                is.na(instant), instant, instant + 1
            ),
            text = dplyr::if_else(text == "alpha", "recoded", text)
        )
    }
    expected <- manipulate(haven::read_dta(path))
    unmanipulated <- read_dta(path)

    classed_labelled <- dplyr::recode(unmanipulated$labelled, `1` = 2)
    classed_date <- dplyr::recode(unmanipulated$date, `0` = 1)
    classed_instant <- dplyr::recode(unmanipulated$instant, `0` = 1)
    expect_s3_class(classed_labelled, "haven_labelled")
    expect_s3_class(classed_date, "Date")
    expect_s3_class(classed_instant, "POSIXct")
    expect_identical(
        missing_tag(unclass(classed_labelled)),
        c(NA_character_, "c", NA_character_)
    )
    expect_identical(
        missing_tag(unclass(classed_date)),
        c(NA_character_, "a", NA_character_)
    )
    expect_identical(
        missing_tag(unclass(classed_instant)),
        c(NA_character_, "b", NA_character_)
    )

    for (use_numeric_altrep in c(TRUE, FALSE)) {
        actual <- manipulate(read_dta(
            path,
            use_numeric_altrep = use_numeric_altrep
        ))
        mode <- if (use_numeric_altrep) "default" else "eager"
        expect_identical(data_values(actual), data_values(expected), info = mode)
        expect_s3_class(actual$labelled, "haven_labelled")
        expect_s3_class(actual$date, "Date")
        expect_s3_class(actual$instant, "POSIXct")
        expect_identical(
            missing_tag(unclass(actual$labelled)),
            c(NA_character_, "c", NA_character_),
            info = paste(mode, "labelled tag")
        )
        expect_identical(
            missing_tag(unclass(actual$date)),
            c(NA_character_, "a", NA_character_),
            info = paste(mode, "Date tag")
        )
        expect_identical(
            missing_tag(unclass(actual$instant)),
            c(NA_character_, "b", NA_character_),
            info = paste(mode, "POSIXct tag")
        )
    }

    source <- fixture("auto_v118.dta")
    bytes <- readBin(source, "raw", n = file.info(source)[["size"]])
    data_tag <- charToRaw("<data>")
    data_start <- grepRaw(data_tag, bytes, fixed = TRUE)[[1L]] +
        length(data_tag)
    closing_start <- grepRaw(
        charToRaw("</data>"), bytes, fixed = TRUE
    )[[1L]]
    row_width <- as.integer((closing_start - data_start) / 74L)
    expect_identical(row_width, 43L)

    # `foreign` is the final one-byte field; make its first value `.a` while
    # retaining its value-label table and haven_labelled class.
    bytes[[data_start + row_width - 1L]] <- as.raw(102L)

    # `price` follows the 18-byte `make` field and is a two-byte int. Change
    # its first value to `.a` and its display format to `%td`, making it an
    # integer-backed Date. The second format match is `price`; the first occurs
    # outside its fixed-width format entry in this fixture.
    bytes[data_start + 18L + 0:1] <- writeBin(
        as.integer(32742L), raw(), size = 2L, endian = "little"
    )
    old_format <- charToRaw("%8.0gc")
    format_matches <- grepRaw(old_format, bytes, fixed = TRUE, all = TRUE)
    expect_gte(length(format_matches), 2L)
    price_format <- format_matches[[2L]]
    bytes[price_format + seq_along(old_format) - 1L] <- c(
        charToRaw("%td"), raw(length(old_format) - 3L)
    )

    narrow_path <- tempfile(fileext = ".dta")
    on.exit(unlink(narrow_path), add = TRUE)
    writeBin(bytes, narrow_path)
    narrow <- read_dta(narrow_path)
    narrow_reference <- haven::read_dta(narrow_path)
    expect_true(dtatools:::.is_numeric_altrep(narrow$foreign))
    expect_true(dtatools:::.is_numeric_altrep(narrow$price))
    expect_s3_class(narrow$foreign, "haven_labelled")
    expect_s3_class(narrow$price, "Date")
    expect_identical(missing_tag(unclass(narrow$foreign))[[1L]], "a")
    expect_identical(missing_tag(unclass(narrow$price))[[1L]], "a")

    manipulate_narrow <- function(data) {
        dplyr::mutate(
            data,
            foreign = dplyr::case_when(
                foreign == 0 ~ 2,
                .default = foreign
            ),
            price = dplyr::if_else(is.na(price), price, price + 1)
        )
    }
    narrow_input <- read_dta(narrow_path)
    expect_true(dtatools:::.is_numeric_altrep(narrow_input$foreign))
    expect_true(dtatools:::.is_numeric_altrep(narrow_input$price))
    narrow_transformed <- manipulate_narrow(narrow_input)
    narrow_expected <- manipulate_narrow(narrow_reference)
    expect_identical(
        data_values(narrow_transformed), data_values(narrow_expected)
    )
    expect_identical(
        missing_tag(unclass(narrow_transformed$foreign))[[1L]],
        "a"
    )
    expect_identical(
        missing_tag(unclass(narrow_transformed$price))[[1L]],
        "a"
    )
})

test_that("all bundled fixtures agree with haven", {
    skip_if_not_installed("haven")
    paths <- list.files(
        system.file("extdata", package = "dtatools"),
        pattern = "[.]dta$",
        full.names = TRUE
    )
    expect_gt(length(paths), 20L)

    for (path in paths) {
        # The Rust-vector collector builds a tibble, so compare against a
        # tibble read; the default dibble carries reference state on top.
        actual <- read_dta(path, output = "tibble")
        rust_vectors <- dtatools:::.read_dta_rust_vectors(path)
        expected <- without_haven_note_count(haven::read_dta(path))
        info <- basename(path)
        metadata <- dtatools:::.dta_metadata(normalizePath(path))
        storage <- stats::setNames(
            attr(metadata, "dta_storage", exact = TRUE),
            as.character(metadata)
        )

        expect_identical(actual, rust_vectors,
                         info = paste(info, "direct and Rust-vector collectors"))
        expect_identical(dim(actual), dim(expected), info = info)
        expect_identical(names(actual), names(expected), info = info)
        expect_identical(attr(actual, "label", exact = TRUE),
                         attr(expected, "label", exact = TRUE), info = info)
        expect_identical(attr(actual, "notes", exact = TRUE),
                         attr(expected, "notes", exact = TRUE), info = info)
        expect_null(attr(actual, "dta_format_version", exact = TRUE), info = info)
        expect_identical(
            attributes(without_stata_storage_data(actual)),
            attributes(expected),
            info = info
        )
        expect_true(attr(metadata, "dta_format_version", exact = TRUE) %in%
                    c(105L, 108L, 110L, 111L, 113L, 114L, 115L,
                      117L, 118L, 119L), info = info)

        for (name in names(actual)) {
            if (storage[[name]] %in% c("float", "double")) {
                expect_equal(without_stata_storage(actual[[name]]),
                             expected[[name]], tolerance = 1e-7,
                             info = paste(info, name))
            } else {
                expect_equal(without_stata_storage(actual[[name]]),
                             expected[[name]], tolerance = 0,
                             info = paste(info, name, "exact"))
            }
            expect_identical(is.na(actual[[name]]), is.na(expected[[name]]),
                             info = paste(info, name, "missing positions"))
            if (is.numeric(actual[[name]])) {
                expect_identical(
                    missing_tag(actual[[name]]),
                    missing_tag(expected[[name]]),
                    info = paste(info, name, "missing tags")
                )
            }
        }
    }
})

test_that("dataset-note cardinality, ordering, and empty values are semantic", {
    skip_if_not_installed("haven")
    source <- fixture("auto_v118.dta")
    multiple <- readBin(source, "raw", file.info(source)$size)
    one <- replace_first_byte(multiple, "note0", utf8ToInt("x"))
    empty <- replace_first_byte(
        multiple, "From Consumer Reports with permission", 0
    )
    zero <- replace_first_byte(one, "note1", utf8ToInt("x"))

    variants <- list(multiple = multiple, one = one, empty = empty, zero = zero)
    expected_notes <- list(
        multiple = "From Consumer Reports with permission",
        one = "From Consumer Reports with permission",
        empty = "",
        zero = NULL
    )
    for (name in names(variants)) {
        variant <- variants[[name]]
        expected <- without_haven_note_count(haven::read_dta(
            variant, col_select = make, skip = 2, n_max = 3
        ))
        actual <- read_dta(
            variant, col_select = make, skip = 2, n_max = 3,
            output = "tibble"
        )
        rust_vectors <- dtatools:::.read_dta_rust_vectors(
            variant, col_select = make, skip = 2, n_max = 3
        )

        expect_identical(actual, rust_vectors)
        expect_identical(
            attr(actual, "notes", exact = TRUE), expected_notes[[name]]
        )
        if (name != "empty") {
            expect_identical(attr(actual, "notes", exact = TRUE),
                             attr(expected, "notes", exact = TRUE))
        } else {
            # Haven drops an empty note; dtatools preserves its value.
            expect_null(attr(expected, "notes", exact = TRUE))
        }
    }
})

test_that("projection, renaming, and row bounds match haven", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4,
        output = "tibble"
    )
    rust_vectors <- dtatools:::.read_dta_rust_vectors(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4
    )
    expected <- without_haven_note_count(
        haven::read_dta(path, skip = 5, n_max = 4)
    )

    expect_identical(actual, rust_vectors)
    expect_identical(names(actual), c("origin", "make", "price"))
    expect_equal(without_stata_storage(actual$origin), expected$foreign)
    expect_equal(without_stata_storage(actual$make), expected$make)
    expect_equal(without_stata_storage(actual$price), expected$price)
    expect_identical(attr(actual, "label"), attr(expected, "label"))
    expect_identical(attr(actual, "notes"), attr(expected, "notes"))
    expect_null(attr(actual, "dta_format_version", exact = TRUE))
})

test_that("safe row-window inputs align with haven in both collectors", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")
    cases <- list(
        integer = list(skip = 2L, n_max = 3L),
        integer_valued_double = list(skip = 2, n_max = 3),
        zero = list(skip = 0, n_max = 0),
        skip_beyond_rows = list(skip = 1000, n_max = 3),
        n_max_beyond_rows = list(skip = 72, n_max = 1000),
        bare_na_unlimited = list(skip = 2, n_max = NA),
        real_na_unlimited = list(skip = 2, n_max = NA_real_),
        positive_infinity_unlimited = list(skip = 2, n_max = Inf),
        negative_infinity_unlimited = list(skip = 2, n_max = -Inf),
        negative_integer_unlimited = list(skip = 2, n_max = -1L),
        negative_double_unlimited = list(skip = 2, n_max = -1.5)
    )

    for (name in names(cases)) {
        arguments <- c(
            list(path, col_select = c("make", "price")), cases[[name]]
        )
        actual <- do.call(
            read_dta, c(arguments, list(output = "tibble"))
        )
        rust_vectors <- do.call(
            dtatools:::.read_dta_rust_vectors, arguments
        )
        expected <- without_haven_note_count(
            do.call(haven::read_dta, arguments)
        )

        expect_identical(actual, rust_vectors,
                         info = paste(name, "materialization"))
        expect_identical(
            without_stata_storage_data(actual), expected, info = name
        )
    }
})

test_that("normalized windows cover empty data and zero-column projections", {
    skip_if_not_installed("haven")
    empty <- tempfile(fileext = ".dta")
    on.exit(unlink(empty), add = TRUE)
    haven::write_dta(data.frame(number = double(), text = character()), empty)

    for (n_max in list(0L, NA, Inf, -Inf, -1)) {
        actual <- read_dta(empty, n_max = n_max, output = "tibble")
        rust_vectors <- dtatools:::.read_dta_rust_vectors(
            empty, n_max = n_max
        )
        expected <- haven::read_dta(empty, n_max = n_max)
        expect_identical(actual, rust_vectors)
        expect_identical(without_stata_storage_data(actual), expected)
    }

    path <- fixture("auto_v118.dta")
    windows <- list(
        zero = list(skip = 0, n_max = 0),
        unlimited = list(skip = 2, n_max = NA),
        out_of_range = list(skip = 1000, n_max = 10)
    )
    for (name in names(windows)) {
        arguments <- c(
            list(path, col_select = character()), windows[[name]]
        )
        actual <- do.call(
            read_dta, c(arguments, list(output = "tibble"))
        )
        rust_vectors <- do.call(
            dtatools:::.read_dta_rust_vectors, arguments
        )
        expected_rows <- do.call(
            haven::read_dta, c(list(path), windows[[name]])
        )
        expect_identical(actual, rust_vectors, info = name)
        expect_identical(nrow(actual), nrow(expected_rows), info = name)
        expect_identical(ncol(actual), 0L, info = name)
    }
})

test_that("repeated string patterns can diverge without changing values", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    values <- c("alpha", "beta", "alpha", "beta", "alpha", "gamma",
                "alpha", "beta", rep(c("delta", "epsilon", "zeta"), 8L))
    haven::write_dta(data.frame(value = values), path, version = 15)

    actual <- read_dta(path, output = "tibble")
    expect_identical(as.vector(actual$value), values)
    expect_identical(actual, dtatools:::.read_dta_rust_vectors(path))
})

test_that("wide materialization uses bounded native protection", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    column_count <- 5500L
    input <- as.data.frame(
        stats::setNames(rep.int(list(1), column_count),
                        sprintf("v%05d", seq_len(column_count))),
        check.names = FALSE
    )
    haven::write_dta(input, path, version = 15)

    result <- read_dta(path)
    expect_identical(dim(result), c(1L, column_count))
    expect_identical(as.double(result[[column_count]]), 1)
})

test_that("date and datetime storage become native R temporal vectors", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    input <- data.frame(
        date = as.Date(c("1960-01-01", "2024-02-29")),
        instant = as.POSIXct(c("1960-01-01 00:00:00", "2024-02-29 12:34:56"),
                            tz = "UTC")
    )
    haven::write_dta(input, path, version = 15)

    actual <- read_dta(path)
    eager <- read_dta(path, use_numeric_altrep = FALSE)
    expected <- haven::read_dta(path)
    expect_equal(without_stata_storage(actual$date), expected$date)
    expect_s3_class(actual$date, "Date")
    expect_equal(without_stata_storage(actual$instant), expected$instant)
    expect_s3_class(actual$instant, "POSIXct")
    expect_identical(attr(actual$instant, "tzone"), "UTC")
    expect_identical(eager, actual)
    expect_false(any(vapply(
        eager, dtatools:::.is_numeric_altrep, logical(1)
    )))
})

test_that("imported strings use owned Stata string vectors", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    haven::write_dta(data.frame(text = c("a", "wide", "")), path, version = 15)

    text <- read_dta(path)$text
    expect_s3_class(text, "stata_string")
    expect_identical(attr(text, "stata.string.storage", exact = TRUE), "str4")
    expect_identical(as.character(text[c(2, 2, 3)]), c("wide", "wide", ""))
    expect_s3_class(text[integer()], "stata_string")
})

test_that("legacy and custom daily-date formats match haven", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    formats <- c(
        daily_td = "%td",
        daily_d = "%d",
        daily_custom = "%dCY-N-D",
        daily_unusual = "%dollars",
        daily_other = "%dfoo",
        datetime_tc = "%tc",
        datetime_tC = "%tC",
        near_uppercase_d = "%D",
        near_width_d = "%9d",
        weekly = "%tw",
        monthly = "%tm",
        quarterly = "%tq",
        halfyear = "%th",
        yearly = "%ty",
        incomplete_temporal = "%t",
        bare_d = "d"
    )
    values <- c(0, 3653, tagged_missing("a"), NA_real_)
    input <- as.data.frame(lapply(formats, function(format) {
        column <- values
        attr(column, "format.stata") <- format
        column
    }), check.names = FALSE)
    haven::write_dta(input, path, version = 15)

    actual <- read_dta(path, output = "tibble")
    rust_vectors <- dtatools:::.read_dta_rust_vectors(path)
    expected <- haven::read_dta(path)

    expect_identical(actual, rust_vectors)
    for (name in names(formats)) {
        expect_identical(
            without_stata_storage(actual[[name]]), expected[[name]], info = name
        )
        expect_identical(attr(actual[[name]], "format.stata"), formats[[name]],
                         info = name)
        expect_identical(missing_tag(actual[[name]]),
                         missing_tag(expected[[name]]), info = name)
    }

    date_names <- names(formats)[startsWith(formats, "%d") |
                                 startsWith(formats, "%td")]
    datetime_names <- names(formats)[startsWith(formats, "%tc") |
                                     startsWith(formats, "%tC")]
    numeric_names <- setdiff(names(formats), c(date_names, datetime_names))
    expect_true(all(vapply(actual[date_names], inherits, logical(1), "Date")))
    expect_true(all(vapply(actual[datetime_names], inherits, logical(1),
                           "POSIXct")))
    expect_true(all(vapply(actual[datetime_names], function(column) {
        identical(attr(column, "tzone"), "UTC")
    }, logical(1))))
    expect_true(all(vapply(
        actual[numeric_names], inherits, logical(1), "stata_numeric"
    )))

    selected_names <- c("daily_custom", "datetime_tC", "near_uppercase_d")
    selected <- read_dta(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2,
        output = "tibble"
    )
    selected_rust_vectors <- dtatools:::.read_dta_rust_vectors(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2
    )
    selected_expected <- haven::read_dta(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2
    )
    expect_identical(selected, selected_rust_vectors)
    expect_identical(
        without_stata_storage_data(selected), selected_expected
    )
})

test_that("explicit encodings match haven across ordinary textual surfaces", {
    skip_if_not_installed("haven")
    for (version in c(115L, 118L)) local({
        source <- fixture(sprintf("auto_v%d.dta", version))
        bytes <- readBin(source, "raw", file.info(source)$size)
        for (text in c(
            "1978 automobile data", "Make and model", "AMC Concord", "Domestic"
        )) {
            bytes <- replace_first_byte(bytes, text, 0x80)
        }
        path <- tempfile(fileext = ".dta")
        on.exit(unlink(path), add = TRUE)
        writeBin(bytes, path)

        for (encoding in c("Windows-1252", "ISO-8859-1")) {
            actual <- read_dta(
                path, encoding = encoding, output = "tibble"
            )
            rust_vectors <- dtatools:::.read_dta_rust_vectors(
                path, encoding = encoding
            )
            expected <- haven::read_dta(path, encoding = encoding)
            info <- paste("release", version, encoding)

            expect_identical(actual, rust_vectors,
                             info = paste(info, "materialization"))
            expect_identical(without_stata_storage(actual$make), expected$make,
                             info = paste(info, "fixed string"))
            expect_identical(attr(actual, "label"), attr(expected, "label"),
                             info = paste(info, "dataset label"))
            expect_identical(attr(actual$make, "label"),
                             attr(expected$make, "label"),
                             info = paste(info, "variable label"))
            expect_identical(attr(actual$foreign, "labels"),
                             attr(expected$foreign, "labels"),
                             info = paste(info, "value labels"))
        }
    })

    modern <- fixture("auto_v118.dta")
    expect_identical(read_dta(modern, encoding = "utf_8"),
                     read_dta(modern, encoding = "UTF8"))
    expect_identical(without_stata_storage(
                         read_dta(modern, encoding = "UTF-8")$make
                     ),
                     haven::read_dta(modern, encoding = "UTF-8")$make)

    note_bytes <- readBin(modern, "raw", file.info(modern)$size)
    note_bytes <- replace_first_byte(
        note_bytes, "From Consumer Reports with permission", 0x80
    )
    cp1252 <- read_dta(
        note_bytes, encoding = "Windows-1252", output = "tibble"
    )
    latin1 <- read_dta(
        note_bytes, encoding = "ISO-8859-1", output = "tibble"
    )
    expect_identical(cp1252, dtatools:::.read_dta_rust_vectors(
        note_bytes, encoding = "CP1252"
    ))
    expect_identical(latin1, dtatools:::.read_dta_rust_vectors(
        note_bytes, encoding = "latin1"
    ))
    expect_true(startsWith(attr(cp1252, "notes")[[1L]], "\u20ac"))
    expect_true(startsWith(attr(latin1, "notes")[[1L]], "\u0080"))
})

test_that("deliberate row-window divergences from haven are stable", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")

    expect_identical(nrow(haven::read_dta(path, n_max = 2.9)), 2L)
    expect_error(read_dta(path, n_max = 2.9), "whole number")
    expect_identical(nrow(haven::read_dta(path, n_max = NaN)), 74L)
    expect_error(read_dta(path, n_max = NaN), "must not be NaN")

    expect_identical(nrow(haven::read_dta(path, skip = -1, n_max = 2)), 2L)
    expect_error(read_dta(path, skip = -1, n_max = 2), "non-negative whole")
    expect_identical(nrow(haven::read_dta(path, skip = NA, n_max = 2)), 2L)
    expect_error(read_dta(path, skip = NA, n_max = 2), "integer or double")
    expect_s3_class(haven::read_dta(path, skip = Inf, n_max = 2), "tbl_df")
    expect_error(read_dta(path, skip = Inf, n_max = 2), "non-negative whole")
    expect_error(haven::read_dta(path, skip = 2.9, n_max = 2),
                 "single integer")
    expect_error(read_dta(path, skip = 2.9, n_max = 2),
                 "non-negative whole")
})
