# The column export ladder shared by save_dta(), save_arrow() and datasig()
# (ADR 0037).

kind_of <- function(column) dtatools:::.write_column_kind(column)

meta_class <- dtatools:::.dta_metadata_vector_class

one_column <- function(value) {
    structure(
        list(v = value), class = "data.frame",
        row.names = .set_row_names(length(value))
    )
}

test_that("the ladder names every kind both writers know", {
    expect_identical(kind_of(factor("a")), "factor")
    expect_identical(kind_of(factor("a", ordered = TRUE)), "factor")
    expect_identical(kind_of(dta_byte(c(1, 2))), "stata")
    expect_identical(kind_of(structure(1:2, stata.storage = "long")), "stata")
    expect_identical(
        kind_of(structure(c(TRUE, NA), stata.storage = "byte")), "stata"
    )
    expect_identical(kind_of(as.Date("2020-01-01")), "date")
    expect_identical(kind_of(as.POSIXct("2020-01-01", tz = "UTC")), "datetime")
    expect_identical(kind_of(as.difftime(1, units = "secs")), "difftime")
    expect_identical(kind_of(c("a", NA)), "character")
    expect_identical(kind_of(dta_string(c("a", "bb"))), "character")
    expect_identical(kind_of(as.raw(1:2)), "raw")
    expect_identical(kind_of(c(TRUE, NA)), "logical")
    expect_identical(kind_of(1:2), "integer")
    expect_identical(kind_of(c(1, 2)), "double")
    expect_identical(
        kind_of(set_val_labels(c(1, 2), .labels = c(a = 1))), "double"
    )
    expect_identical(kind_of(structure(c(1, 2), class = meta_class)), "double")
})

test_that("a Stata declaration classifies before the R type", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data.frame(
        d = as.Date("2020-01-01"), t = as.POSIXct("2020-01-01", tz = "UTC")
    ), path)
    read <- read_dta(path)
    expect_identical(kind_of(read$d), "stata")
    expect_identical(kind_of(read$t), "stata")
    expect_identical(
        kind_of(structure(1e9, class = c("POSIXct", "POSIXt"), stata.storage = "double")),
        "stata"
    )
})

test_that("columns no writer exports are NA", {
    expect_identical(kind_of(matrix(1:4, 2)), NA_character_)
    expect_identical(kind_of(I(list(1))), NA_character_)
    expect_identical(kind_of(complex(real = 1)), NA_character_)
    expect_identical(kind_of(as.POSIXlt(Sys.time())), NA_character_)
    expect_identical(kind_of(structure(1, class = "integer64")), NA_character_)
    expect_identical(
        kind_of(structure(factor("a"), class = c("myf", "factor"))),
        NA_character_
    )
    expect_identical(kind_of(vctrs::new_vctr(c(1, 2))), NA_character_)
    expect_identical(
        kind_of(structure(18000, class = c("haven_labelled", "Date"))),
        NA_character_
    )
    expect_identical(
        kind_of(structure(
            18000, class = c("haven_labelled", "Date"), stata.storage = "long"
        )),
        NA_character_
    )
    expect_identical(
        kind_of(structure(
            c(TRUE, FALSE),
            class = c("haven_labelled", "vctrs_vctr", "logical")
        )),
        NA_character_
    )
    expect_identical(
        kind_of(structure(as.raw(1), class = "bytes")), NA_character_
    )
})

test_that("save_dta refuses only the kinds a DTA file cannot hold", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    for (value in list(
        as.difftime(c(1, 2), units = "hours"), as.raw(1:2)
    )) {
        expect_error(
            save_dta(one_column(value), path),
            "Unsupported columns: `v` (",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
    }
    expect_error(
        save_dta(one_column(vctrs::new_vctr(c(1, 2))), path),
        "Unsupported columns: `v` (vctrs_vctr)",
        fixed = TRUE,
        class = "dtatools_write_validation_error"
    )
    expect_false(file.exists(path))
})

test_that("both writers export a Stata declaration on any numeric R type", {
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta_path, arrow_path)), add = TRUE)
    data <- one_column(structure(1:2, stata.storage = "long"))
    data$w <- structure(c(TRUE, NA), stata.storage = "byte")
    data$x <- structure(
        c(1, 2), class = c("dta_numeric", "dta_double", "vctrs_vctr", "double")
    )

    save_dta(data, dta_path)
    save_arrow(data, arrow_path)
    from_dta <- read_dta(dta_path)
    from_arrow <- read_arrow(arrow_path)
    expect_identical(dta_storage_type(from_arrow$v), "long")
    expect_identical(dta_storage_type(from_arrow$w), "byte")
    expect_identical(dta_storage_type(from_arrow$x), "double")
    expect_identical(as.double(from_arrow$v), c(1, 2))
    expect_identical(as.double(from_arrow$w), c(1, NA))
    expect_identical(datasig(from_dta), datasig(from_arrow))
})

test_that("a declared integer with haven classes exports through Arrow", {
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    x <- set_val_labels(1:2, .labels = c(a = 1L))
    attr(x, "stata.storage") <- "long"
    data <- one_column(x)
    save_arrow(data, arrow_path)
    actual <- read_arrow(arrow_path)
    expect_identical(dta_storage_type(actual$v), "long")
    expect_identical(as.double(actual$v), c(1, 2))
    expect_identical(val_labels(actual$v), c(a = 1))
    expect_identical(datasig(data), datasig(actual))
})

test_that("a calendar class on a non-numeric payload is unsupported everywhere", {
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta_path, arrow_path)), add = TRUE)
    for (value in list(
        structure(as.raw(1:2), class = "Date"),
        structure(as.raw(1:2), class = "Date", stata.storage = "long"),
        structure(c("a", "b"), class = c("POSIXct", "POSIXt"))
    )) {
        expect_identical(kind_of(value), NA_character_)
        expect_error(
            save_dta(one_column(value), dta_path),
            "Unsupported columns: `v` (",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
        expect_error(
            save_arrow(one_column(value), arrow_path),
            "Unsupported columns: `v` (",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
    }
    expect_false(file.exists(dta_path))
    expect_false(file.exists(arrow_path))
})

test_that("a table datasig signs is a table save_dta saves", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    data <- data.frame(
        i = 1:2, l = c(TRUE, NA), d = c(1.5, NA), s = c("a", NA),
        f = factor(c("x", "y")), dt = as.Date(c("2020-01-01", NA)),
        ts = as.POSIXct(c("2020-01-01 10:00", NA), tz = "America/New_York")
    )
    data$b <- dta_byte(c(1, tagged_missing("a")))
    data$g <- set_val_labels(c(1, 2), .labels = c(one = 1, two = 2))
    signature <- datasig(data)
    suppressWarnings(save_dta(data, path))
    expect_type(signature, "character")
    expect_true(file.exists(path))
})

test_that("both writers name a malformed Stata declaration", {
    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta_path, arrow_path)), add = TRUE)
    for (value in list(
        structure(c(1, 2), stata.storage = "bogus"),
        structure(1:2, stata.storage = "bogus"),
        structure(c(1, 2), stata.storage = c("byte", "int"))
    )) {
        expect_error(
            save_dta(one_column(value), dta_path),
            "Column `v` has an invalid `stata.storage` declaration",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
        expect_error(
            save_arrow(one_column(value), arrow_path),
            "Column `v` has an invalid `stata.storage` declaration",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
    }
    for (value in list(
        structure("a", stata.string.storage = "str0"),
        structure("a", stata.string.storage = "str2046"),
        structure("a", stata.string.storage = 12L)
    )) {
        expect_error(
            save_dta(one_column(value), dta_path),
            "Column `v` has an invalid `stata.string.storage` declaration",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
        expect_error(
            save_arrow(one_column(value), arrow_path),
            "Column `v` has an invalid `stata.string.storage` declaration",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
    }
})

test_that("the shared string declaration reports storage and width", {
    declaration <- dtatools:::.write_string_declaration
    expect_null(declaration("a", "v"))
    expect_identical(
        declaration(structure("a", stata.string.storage = "str12"), "v"),
        list(storage = "str12", width = 12L)
    )
    expect_identical(
        declaration(structure("a", stata.string.storage = "strL"), "v"),
        list(storage = "strL", width = NULL)
    )
})

test_that("the shared default format follows storage and calendar", {
    default <- dtatools:::.write_default_numeric_format
    expect_identical(default("byte"), "%8.0g")
    expect_identical(default("long"), "%12.0g")
    expect_identical(default("double"), "%10.0g")
    expect_identical(default("double", "date"), "%td")
    expect_identical(default("double", "datetime"), "%tc")
})
