fixture <- function(name) {
    system.file("extdata", name, package = "dtaparser", mustWork = TRUE)
}

replace_first_byte <- function(bytes, text, replacement) {
    needle <- charToRaw(text)
    starts <- seq_len(length(bytes) - length(needle) + 1L)
    matches <- vapply(starts, function(start) {
        identical(bytes[start:(start + length(needle) - 1L)], needle)
    }, logical(1))
    stopifnot(any(matches))
    bytes[starts[which(matches)[[1L]]]] <- as.raw(replacement)
    bytes
}

test_that("read_dta has the haven-compatible public signature", {
    expected <- c("file", "encoding", "col_select", "skip", "n_max", ".name_repair")
    expect_identical(names(formals(read_dta)), expected)
    expect_null(formals(read_dta)$encoding)
    expect_null(formals(read_dta)$col_select)
    expect_identical(formals(read_dta)$skip, 0)
    expect_identical(formals(read_dta)$n_max, Inf)
    expect_identical(formals(read_dta)$.name_repair, "unique")
})

test_that("internal metadata projection is bounded and preserves attributes", {
    path <- fixture("all_types_v118.dta")
    full <- dtaparser:::.dta_metadata(path)
    middle <- dtaparser:::.dta_metadata(path, column_start = 3L, column_count = 2L)
    suffix <- dtaparser:::.dta_metadata(path, column_start = 7L)
    empty <- dtaparser:::.dta_metadata(path, column_start = 2L, column_count = 0L)
    past <- dtaparser:::.dta_metadata(path, column_start = 100L, column_count = 2L)

    expect_identical(as.character(middle), as.character(full[3:4]))
    expect_identical(attr(middle, "dta_storage"), attr(full, "dta_storage")[3:4])
    expect_identical(attr(middle, "dta_format_version"),
                     attr(full, "dta_format_version"))
    expect_identical(as.character(suffix), as.character(full[7:8]))
    expect_length(empty, 0L)
    expect_length(attr(empty, "dta_storage"), 0L)
    expect_length(past, 0L)

    invalid <- list(-1, 1.5, NA_real_, NaN, c(1, 2), "1")
    for (value in invalid) {
        expect_error(dtaparser:::.dta_metadata(path, column_start = value))
        expect_error(dtaparser:::.dta_metadata(path, column_count = value))
    }
})

test_that("all bundled fixtures agree with haven", {
    skip_if_not_installed("haven")
    paths <- list.files(
        system.file("extdata", package = "dtaparser"),
        pattern = "[.]dta$",
        full.names = TRUE
    )
    expect_gt(length(paths), 20L)

    for (path in paths) {
        actual <- read_dta(path)
        rust_vectors <- dtaparser:::.read_dta_rust_vectors(path)
        expected <- haven::read_dta(path)
        info <- basename(path)
        metadata <- dtaparser:::.dta_metadata(normalizePath(path))
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
        expect_identical(attributes(actual), attributes(expected), info = info)
        expect_true(attr(metadata, "dta_format_version", exact = TRUE) %in%
                    c(105L, 108L, 110L, 111L, 113L, 114L, 115L,
                      117L, 118L, 119L), info = info)

        for (name in names(actual)) {
            if (storage[[name]] %in% c("float", "double")) {
                expect_equal(actual[[name]], expected[[name]], tolerance = 1e-7,
                             info = paste(info, name))
            } else {
                expect_equal(actual[[name]], expected[[name]], tolerance = 0,
                             info = paste(info, name, "exact"))
            }
            expect_identical(is.na(actual[[name]]), is.na(expected[[name]]),
                             info = paste(info, name, "missing positions"))
            if (is.numeric(actual[[name]])) {
                expect_identical(
                    haven::na_tag(actual[[name]]),
                    haven::na_tag(expected[[name]]),
                    info = paste(info, name, "missing tags")
                )
            }
        }
    }
})

test_that("dataset-note cardinality, ordering, and empty values match haven", {
    skip_if_not_installed("haven")
    source <- fixture("auto_v118.dta")
    multiple <- readBin(source, "raw", file.info(source)$size)
    one <- replace_first_byte(multiple, "note0", utf8ToInt("x"))
    empty <- replace_first_byte(
        multiple, "From Consumer Reports with permission", 0
    )
    zero <- replace_first_byte(one, "note1", utf8ToInt("x"))

    for (variant in list(multiple = multiple, one = one, empty = empty,
                         zero = zero)) {
        expected <- haven::read_dta(
            variant, col_select = make, skip = 2, n_max = 3
        )
        actual <- read_dta(
            variant, col_select = make, skip = 2, n_max = 3
        )
        rust_vectors <- dtaparser:::.read_dta_rust_vectors(
            variant, col_select = make, skip = 2, n_max = 3
        )

        expect_identical(actual, rust_vectors)
        expect_identical(attr(actual, "notes", exact = TRUE),
                         attr(expected, "notes", exact = TRUE))
    }
})

test_that("projection, renaming, and row bounds match haven", {
    skip_if_not_installed("haven")
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4
    )
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path,
        col_select = c(origin = foreign, make, price),
        skip = 5,
        n_max = 4
    )
    expected <- haven::read_dta(path, skip = 5, n_max = 4)

    expect_identical(actual, rust_vectors)
    expect_identical(names(actual), c("origin", "make", "price"))
    expect_equal(actual$origin, expected$foreign)
    expect_equal(actual$make, expected$make)
    expect_equal(actual$price, expected$price)
    expect_identical(attr(actual, "label"), attr(expected, "label"))
    expect_identical(attr(actual, "notes"), attr(expected, "notes"))
    expect_null(attr(actual, "dta_format_version", exact = TRUE))
})

test_that("an empty projection retains the selected row count", {
    path <- fixture("auto_v118.dta")
    result <- read_dta(path, col_select = character(), skip = 2, n_max = 3)
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path, col_select = character(), skip = 2, n_max = 3
    )
    expect_identical(result, rust_vectors)
    expect_identical(dim(result), c(3L, 0L))
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
        actual <- do.call(read_dta, arguments)
        rust_vectors <- do.call(
            dtaparser:::.read_dta_rust_vectors, arguments
        )
        expected <- do.call(haven::read_dta, arguments)

        expect_identical(actual, rust_vectors,
                         info = paste(name, "materialization"))
        expect_identical(actual, expected, info = name)
    }
})

test_that("the largest exact skip is deterministic in both collectors", {
    path <- fixture("auto_v118.dta")
    actual <- read_dta(
        path, col_select = c("make", "price"), skip = 2^53, n_max = 3
    )
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path, col_select = c("make", "price"), skip = 2^53, n_max = 3
    )

    expect_identical(actual, rust_vectors)
    expect_identical(dim(actual), c(0L, 2L))
})

test_that("normalized windows cover empty data and zero-column projections", {
    skip_if_not_installed("haven")
    empty <- tempfile(fileext = ".dta")
    on.exit(unlink(empty), add = TRUE)
    haven::write_dta(data.frame(number = double(), text = character()), empty)

    for (n_max in list(0L, NA, Inf, -Inf, -1)) {
        actual <- read_dta(empty, n_max = n_max)
        rust_vectors <- dtaparser:::.read_dta_rust_vectors(
            empty, n_max = n_max
        )
        expected <- haven::read_dta(empty, n_max = n_max)
        expect_identical(actual, rust_vectors)
        expect_identical(actual, expected)
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
        actual <- do.call(read_dta, arguments)
        rust_vectors <- do.call(
            dtaparser:::.read_dta_rust_vectors, arguments
        )
        expected_rows <- do.call(
            haven::read_dta, c(list(path), windows[[name]])
        )
        expect_identical(actual, rust_vectors, info = name)
        expect_identical(nrow(actual), nrow(expected_rows), info = name)
        expect_identical(ncol(actual), 0L, info = name)
    }
})

test_that("typed predicates and duplicate selections are deterministic", {
    path <- fixture("auto_v118.dta")

    strings <- read_dta(path, col_select = where(is.character), n_max = 2)
    expect_identical(names(strings), "make")
    expect_type(strings$make, "character")

    numerics <- read_dta(path, col_select = where(is.numeric), n_max = 2)
    expect_identical(names(numerics), setdiff(
        names(read_dta(path, n_max = 0)), "make"
    ))
    expect_true(all(vapply(numerics, is.numeric, logical(1))))

    duplicated <- read_dta(
        path,
        col_select = c(first_price = price, price, make),
        n_max = 2
    )
    expect_identical(names(duplicated), c("first_price", "make"))
    expect_equal(duplicated$first_price, read_dta(path, n_max = 2)$price)
})

test_that("native materialization survives forced garbage collection", {
    path <- normalizePath(fixture("auto_v118.dta"))
    gctorture(TRUE)
    on.exit(gctorture(FALSE), add = TRUE)

    result <- read_dta(path, col_select = make, n_max = 1)
    expect_identical(dim(result), c(1L, 1L))
    expect_identical(result[[1L]][[1L]], "AMC Concord")
})

test_that("native strings serialize and preserve copy-on-modify semantics", {
    path <- normalizePath(fixture("auto_v118.dta"))
    reference <- dtaparser:::.read_dta_rust_vectors(path)

    encoded <- serialize(read_dta(path), NULL)
    invisible(gc())
    expect_identical(unserialize(encoded), reference)

    original <- read_dta(path)
    modified <- original
    modified$make[[1L]] <- "replacement"
    expect_identical(original$make[[1L]], reference$make[[1L]])
    expect_identical(modified$make[[1L]], "replacement")

    with_missing <- read_dta(path)$make
    expect_false(anyNA(with_missing))
    with_missing[[1L]] <- NA_character_
    expect_true(anyNA(with_missing))
    expect_identical(with_missing[[1L]], NA_character_)

    retained <- read_dta(path)$make
    invisible(gc())
    expect_identical(retained[[2L]], reference$make[[2L]])
})

test_that("repeated string patterns can diverge without changing values", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    values <- c("alpha", "beta", "alpha", "beta", "alpha", "gamma",
                "alpha", "beta", rep(c("delta", "epsilon", "zeta"), 8L))
    haven::write_dta(data.frame(value = values), path, version = 15)

    actual <- read_dta(path)
    expect_identical(as.vector(actual$value), values)
    expect_identical(actual, dtaparser:::.read_dta_rust_vectors(path))
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
    expected <- haven::read_dta(path)
    expect_equal(actual$date, expected$date)
    expect_s3_class(actual$date, "Date")
    expect_equal(actual$instant, expected$instant)
    expect_s3_class(actual$instant, "POSIXct")
    expect_identical(attr(actual$instant, "tzone"), "UTC")
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
    values <- c(0, 3653, haven::tagged_na("a"), NA_real_)
    input <- as.data.frame(lapply(formats, function(format) {
        column <- values
        attr(column, "format.stata") <- format
        column
    }), check.names = FALSE)
    haven::write_dta(input, path, version = 15)

    actual <- read_dta(path)
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(path)
    expected <- haven::read_dta(path)

    expect_identical(actual, rust_vectors)
    for (name in names(formats)) {
        expect_identical(actual[[name]], expected[[name]], info = name)
        expect_identical(attr(actual[[name]], "format.stata"), formats[[name]],
                         info = name)
        expect_identical(haven::na_tag(actual[[name]]),
                         haven::na_tag(expected[[name]]), info = name)
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
    expect_true(all(vapply(actual[numeric_names], function(column) {
        identical(class(column), "numeric")
    }, logical(1))))

    selected_names <- c("daily_custom", "datetime_tC", "near_uppercase_d")
    selected <- read_dta(
        path,
        col_select = all_of(selected_names),
        skip = 1,
        n_max = 2
    )
    selected_rust_vectors <- dtaparser:::.read_dta_rust_vectors(
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
    expect_identical(selected, selected_expected)
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
            actual <- read_dta(path, encoding = encoding)
            rust_vectors <- dtaparser:::.read_dta_rust_vectors(
                path, encoding = encoding
            )
            expected <- haven::read_dta(path, encoding = encoding)
            info <- paste("release", version, encoding)

            expect_identical(actual, rust_vectors,
                             info = paste(info, "materialization"))
            expect_identical(actual$make, expected$make,
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
    expect_identical(read_dta(modern, encoding = "UTF-8")$make,
                     haven::read_dta(modern, encoding = "UTF-8")$make)

    note_bytes <- readBin(modern, "raw", file.info(modern)$size)
    note_bytes <- replace_first_byte(
        note_bytes, "From Consumer Reports with permission", 0x80
    )
    cp1252 <- read_dta(note_bytes, encoding = "Windows-1252")
    latin1 <- read_dta(note_bytes, encoding = "ISO-8859-1")
    expect_identical(cp1252, dtaparser:::.read_dta_rust_vectors(
        note_bytes, encoding = "CP1252"
    ))
    expect_identical(latin1, dtaparser:::.read_dta_rust_vectors(
        note_bytes, encoding = "latin1"
    ))
    expect_true(startsWith(attr(cp1252, "notes")[[1L]], "\u20ac"))
    expect_true(startsWith(attr(latin1, "notes")[[1L]], "\u0080"))
})

test_that("explicit encodings apply consistently to strL text", {
    source <- fixture("strl_test_v118.dta")
    bytes <- readBin(source, "raw", file.info(source)$size)
    bytes <- replace_first_byte(bytes, "This is observation 1", 0x80)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    writeBin(bytes, path)

    cp1252 <- read_dta(path, encoding = "CP1252")
    latin1 <- read_dta(path, encoding = "latin-1")
    expect_identical(cp1252, dtaparser:::.read_dta_rust_vectors(
        path, encoding = "windows_1252"
    ))
    expect_identical(latin1, dtaparser:::.read_dta_rust_vectors(
        path, encoding = "ISO 8859 1"
    ))
    expect_true(startsWith(cp1252$long_text[[1L]], "\u20ac"))
    expect_true(startsWith(latin1$long_text[[1L]], "\u0080"))
})

test_that("explicit UTF-8 replaces malformed sequences in both collectors", {
    source <- fixture("auto_v118.dta")
    bytes <- readBin(source, "raw", file.info(source)$size)
    bytes <- replace_first_byte(bytes, "1978 automobile data", 0xff)
    bytes <- replace_first_byte(bytes, "AMC Concord", 0xff)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    writeBin(bytes, path)

    direct <- read_dta(path, encoding = "UTF-8")
    rust_vectors <- dtaparser:::.read_dta_rust_vectors(
        path, encoding = "UTF8"
    )
    expect_identical(direct, rust_vectors)
    expect_true(startsWith(attr(direct, "label"), "\ufffd"))
    expect_true(startsWith(direct$make[[1L]], "\ufffd"))
})

test_that("argument and native parse failures are ordinary R errors", {
    path <- fixture("auto_v118.dta")
    expect_error(read_dta(path, encoding = "KOI8-R"), "unsupported.*encoding")
    expect_error(read_dta(path, encoding = NA_character_), "non-missing")
    expect_error(read_dta(path, encoding = character()), "one non-missing")
    expect_error(read_dta(path, encoding = c("UTF-8", "latin1")),
                 "one non-missing")
    expect_error(read_dta(path, encoding = 1), "one non-missing")
    expect_error(read_dta(path, col_select = absent), "absent")

    corrupt <- tempfile(fileext = ".dta")
    on.exit(unlink(corrupt), add = TRUE)
    writeBin(as.raw(1:8), corrupt)
    expect_error(read_dta(corrupt), "header|format|small|read|I/O", ignore.case = TRUE)
    expect_error(dtaparser:::.read_dta_rust_vectors(corrupt),
                 "header|format|small|read|I/O", ignore.case = TRUE)
})

test_that("unsafe row-window coercions fail before parsing", {
    missing_path <- tempfile(fileext = ".dta")
    invalid <- list(
        list(arguments = list(skip = -1), error = "non-negative whole"),
        list(arguments = list(skip = NA_real_), error = "non-negative whole"),
        list(arguments = list(skip = NaN), error = "non-negative whole"),
        list(arguments = list(skip = Inf), error = "non-negative whole"),
        list(arguments = list(skip = -Inf), error = "non-negative whole"),
        list(arguments = list(skip = 1.5), error = "non-negative whole"),
        list(arguments = list(skip = 2^53 + 2), error = "no larger than"),
        list(arguments = list(skip = c(1, 2)), error = "length 1"),
        list(arguments = list(skip = TRUE), error = "integer or double"),
        list(arguments = list(skip = "1"), error = "integer or double"),
        list(arguments = list(n_max = 1.5), error = "whole number"),
        list(arguments = list(n_max = NaN), error = "must not be NaN"),
        list(arguments = list(n_max = 2^53 + 2), error = "no larger than"),
        list(arguments = list(n_max = c(1, 2)), error = "length 1"),
        list(arguments = list(n_max = TRUE), error = "integer or double"),
        list(arguments = list(n_max = NA_character_), error = "integer or double")
    )
    readers <- list(read_dta, dtaparser:::.read_dta_rust_vectors)

    for (reader in readers) {
        for (case in invalid) {
            expect_error(
                do.call(reader, c(list(missing_path), case$arguments)),
                case$error
            )
        }
    }
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
