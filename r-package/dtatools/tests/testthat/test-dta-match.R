test_that("matching distinguishes every Stata missing identity", {
    values <- c(1, NA_real_, tagged_missing(c("a", "b")))
    column <- stata_double(values)

    expect_identical(dta_match(values, column), 1:4)
    expect_identical(dta_in(values, column), rep(TRUE, 4))
    expect_identical(
        dta_match(values, column, incomparables = tagged_missing("a")),
        c(1L, 2L, NA_integer_, 4L)
    )
})

test_that("matching retains names and rejects noncanonical NaNs", {
    x <- c(first = 1, missing = tagged_missing("a"))
    expect_identical(names(dta_in(x, stata_double(x))), names(x))
    expect_identical(names(dta_match(x, stata_double(x))), names(x))

    expect_error(dta_in(c(1, NaN), stata_double(1)), "noncanonical NaN")
    expect_error(dta_in(c(1, Inf), stata_double(1)), "infinite value")
    expect_true(dta_setequal(-0, 0))
})

test_that("base matching interoperates with bare vectors", {
    numeric <- stata_double(c(1, 2, NA_real_, tagged_missing("a")))
    bare_numeric <- c(2, NA_real_, 3)

    expect_identical(bare_numeric %in% numeric, c(TRUE, TRUE, FALSE))
    expect_identical(numeric %in% bare_numeric, c(FALSE, TRUE, TRUE, FALSE))
    expect_identical(
        match(bare_numeric, numeric),
        c(2L, 3L, NA_integer_)
    )
    expect_identical(
        match(numeric, bare_numeric),
        c(NA_integer_, 1L, 2L, NA_integer_)
    )
    expect_identical(
        match(.Machine$double.xmax, stata_double(tagged_missing("a"))),
        NA_integer_
    )

    left <- stata_double(c(tagged_missing("a"), tagged_missing("b")))
    right <- stata_int(c(tagged_missing("b"), tagged_missing("a")))
    expect_identical(match(left, right), c(2L, 1L))

    strings <- stata_string(c("a", "b", ""))
    bare_strings <- c("b", "", "c")
    expect_identical(bare_strings %in% strings, c(TRUE, TRUE, FALSE))
    expect_identical(strings %in% bare_strings, c(FALSE, TRUE, TRUE))
})

test_that("base matching supports Stata-backed dates and datetimes", {
    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    prototype <- read_dta(path)$price
    date <- dtatools:::.restore_stata_temporal(
        c(1, NA_real_, tagged_missing("a")), prototype, "int"
    )
    bare_date <- as.Date(c(1, NA_real_), origin = "1970-01-01")

    expect_identical(bare_date %in% date, c(TRUE, TRUE))
    expect_identical(date %in% bare_date, c(TRUE, TRUE, FALSE))
    expect_identical(match(date, date[c(3, 1, 2)]), c(2L, 3L, 1L))

    datetime_prototype <- structure(
        as.POSIXct(prototype),
        class = c("stata_temporal", "stata_datetime", "POSIXct", "POSIXt")
    )
    datetime <- dtatools:::.restore_stata_temporal(
        c(1000, NA_real_, tagged_missing("b")), datetime_prototype, "double"
    )
    bare_datetime <- as.POSIXct(
        c(1000, NA_real_), origin = "1970-01-01", tz = "UTC"
    )

    expect_identical(bare_datetime %in% datetime, c(TRUE, TRUE))
    expect_identical(datetime %in% bare_datetime, c(TRUE, TRUE, FALSE))
    expect_identical(match(datetime, datetime[c(3, 1, 2)]), c(2L, 3L, 1L))
})

test_that("matching and sets support owned Stata strings", {
    x <- stata_string(c(first = "a", empty = ""), storage = "str2")
    y <- stata_string(c("b", "a"), storage = "str5")

    expect_identical(dta_match(c("a", "b", ""), y), c(2L, 1L, NA_integer_))
    expect_identical(dta_in(c("a", "c"), y), c(TRUE, FALSE))
    result <- dta_union(x, y)
    expect_s3_class(result, "stata_string")
    expect_identical(attr(result, "stata.string.storage"), "str5")
    expect_identical(as.character(result), c("a", "", "b"))
    expect_null(names(result))
})

test_that("union accepts bare tagged missings on either side", {
    left <- c(1, tagged_missing("a"))
    right <- stata_double(c(2, tagged_missing("b")))

    expect_identical(
        dta_match(
            dta_union(left, right),
            stata_double(c(1, tagged_missing("a"), 2, tagged_missing("b")))
        ),
        1:4
    )
})

test_that("union widens losslessly for bare numeric operands in either order", {
    narrow <- stata_byte(c(1, 2))

    left_bare <- dta_union(c(1, 200.5), narrow)
    right_bare <- dta_union(narrow, c(1, 200.5))

    expect_identical(stata_storage_type(left_bare), "double")
    expect_identical(stata_storage_type(right_bare), "double")
    expect_identical(as.double(left_bare), c(1, 200.5, 2))
    expect_identical(as.double(right_bare), c(1, 2, 200.5))
})

test_that("union widens Stata-backed dates with bare dates in either order", {
    prototype <- structure(
        as.Date(numeric(), origin = "1970-01-01"),
        class = c("stata_temporal", "stata_date", "Date"),
        stata.storage = "int",
        format.stata = "%td",
        label = "typed date"
    )
    typed <- dtatools:::.restore_stata_temporal(
        as.Date(c(1, 2), origin = "1970-01-01"), prototype, "int"
    )
    bare <- as.Date(c(2, 200), origin = "1970-01-01")

    typed_first <- dta_union(typed, bare)
    bare_first <- dta_union(bare, typed)

    expect_s3_class(typed_first, "stata_date")
    expect_s3_class(bare_first, "stata_date")
    expect_identical(stata_storage_type(typed_first), "double")
    expect_identical(stata_storage_type(bare_first), "double")
    expect_identical(as.double(typed_first), c(1, 2, 200))
    expect_identical(as.double(bare_first), c(2, 200, 1))
    expect_identical(attr(typed_first, "format.stata"), "%td")
    expect_identical(attr(bare_first, "format.stata"), "%td")
    expect_identical(attr(typed_first, "label"), "typed date")
    expect_identical(attr(bare_first, "label"), "typed date")
})

test_that("union widens Stata-backed datetimes with bare datetimes in either order", {
    prototype <- structure(
        as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"),
        class = c("stata_temporal", "stata_datetime", "POSIXct", "POSIXt"),
        stata.storage = "long",
        format.stata = "%tc",
        label = "typed datetime"
    )
    stata_origin <- as.POSIXct("1960-01-01", tz = "UTC")
    typed <- dtatools:::.restore_stata_temporal(
        stata_origin + c(1, 2),
        prototype,
        "long"
    )
    bare <- stata_origin + c(2, 3e6)

    typed_first <- dta_union(typed, bare)
    bare_first <- dta_union(bare, typed)

    expect_s3_class(typed_first, "stata_datetime")
    expect_s3_class(bare_first, "stata_datetime")
    expect_identical(stata_storage_type(typed_first), "double")
    expect_identical(stata_storage_type(bare_first), "double")
    expect_identical(
        as.double(typed_first), as.double(stata_origin + c(1, 2, 3e6))
    )
    expect_identical(
        as.double(bare_first), as.double(stata_origin + c(2, 3e6, 1))
    )
    expect_identical(attr(typed_first, "tzone"), "UTC")
    expect_identical(attr(bare_first, "tzone"), "UTC")
    expect_identical(attr(typed_first, "format.stata"), "%tc")
    expect_identical(attr(bare_first, "format.stata"), "%tc")
    expect_identical(attr(typed_first, "label"), "typed datetime")
    expect_identical(attr(bare_first, "label"), "typed datetime")
})

test_that("matching rejects incompatible kinds", {
    expect_error(dta_in(1, "1"), "incompatible kinds")
    expect_error(
        dta_in(as.Date("2020-01-01"), as.POSIXct("2020-01-01", tz = "UTC")),
        "incompatible kinds"
    )
})

test_that("date and datetime operands keep separate identity domains", {
    date <- as.Date("2020-01-01") + 0:1
    datetime <- as.POSIXct("2020-01-01", tz = "UTC") + 0:1

    expect_identical(dta_match(rev(date), date), 2:1)
    expect_identical(dta_match(rev(datetime), datetime), 2:1)
    expect_error(dta_union(date, datetime), "incompatible kinds")
})

test_that("set operations use stable Stata identity", {
    x <- stata_byte(c(
        first = 2, duplicate = 2, system = NA_real_, a = tagged_missing("a")
    ))
    y <- stata_int(c(
        system = NA_real_, b = tagged_missing("b"), one = 1
    ))

    union <- dta_union(x, y)
    expect_identical(stata_storage_type(union), "int")
    expect_null(names(union))
    expect_identical(
        dta_match(union, stata_int(c(
            2, NA_real_, tagged_missing(c("a", "b")), 1
        ))),
        1:5
    )

    intersection <- dta_intersect(x, y)
    expect_identical(stata_storage_type(intersection), "byte")
    expect_null(names(intersection))
    expect_identical(dta_match(intersection, stata_byte(NA_real_)), 1L)

    difference <- dta_setdiff(x, y)
    expect_identical(stata_storage_type(difference), "byte")
    expect_identical(
        dta_match(difference, stata_byte(c(2, tagged_missing("a")))),
        1:2
    )
    expect_true(dta_setequal(x, rev(x)))
    expect_false(dta_setequal(x, y))
})

test_that("set operations follow base NULL behavior", {
    x <- stata_byte(c(1, 1, 2))

    expect_identical(dta_union(NULL, NULL), NULL)
    expect_identical(as.double(dta_union(NULL, x)), c(1, 2))
    expect_null(dta_intersect(NULL, x))
    expect_null(dta_setdiff(NULL, x))
    expect_identical(as.double(dta_setdiff(x, NULL)), c(1, 2))
    expect_true(dta_setequal(NULL, numeric()))
})

test_that("set operations retain left metadata where promised", {
    x <- stata_byte(c(1, 2, 3))
    attr(x, "label") <- "left"
    y <- stata_int(c(2, 4))
    attr(y, "label") <- "right"

    expect_identical(attr(dta_intersect(x, y), "label"), "left")
    expect_identical(attr(dta_setdiff(x, y), "label"), "left")
    expect_warning(union <- dta_union(x, y), "variable label")
    expect_identical(attr(union, "label"), "left")
})

test_that("union reconciles metadata left-first with one warning", {
    x <- stata_byte(c(1, 2))
    attr(x, "format.stata") <- "%8.0g"
    attr(x, "label") <- "left"
    attr(x, "labels") <- c(one = 1, left_two = 2)
    attr(x, "notes") <- "left note"
    attr(x, "stata.note.numbers") <- 1L
    attr(x, "stata.characteristics") <- c(source = "left")
    attr(x, "left.extra") <- TRUE

    y <- stata_int(c(2, 3))
    attr(y, "format.stata") <- "%12.0g"
    attr(y, "label") <- "right"
    attr(y, "labels") <- c(right_two = 2, three = 3)
    attr(y, "notes") <- "right note"
    attr(y, "stata.note.numbers") <- 2L
    attr(y, "stata.characteristics") <- c(source = "right")
    attr(y, "right.extra") <- TRUE

    warnings <- character()
    result <- withCallingHandlers(
        dta_union(x, y),
        warning = function(condition) {
            warnings <<- c(warnings, conditionMessage(condition))
            invokeRestart("muffleWarning")
        }
    )

    expect_length(warnings, 1L)
    expect_match(warnings, "display format")
    expect_match(warnings, "variable label")
    expect_match(warnings, "value labels")
    expect_match(warnings, "notes")
    expect_match(warnings, "characteristics")
    expect_match(warnings, "left.extra, right.extra", fixed = TRUE)
    expect_identical(attr(result, "format.stata"), "%8.0g")
    expect_identical(attr(result, "label"), "left")
    expect_identical(
        attr(result, "labels"), c(one = 1, left_two = 2, three = 3)
    )
    expect_identical(attr(result, "notes"), "left note")
    expect_identical(attr(result, "stata.characteristics"), c(source = "left"))
    expect_null(attr(result, "left.extra", exact = TRUE))
    expect_null(attr(result, "right.extra", exact = TRUE))
})

test_that("union chooses the first compatible display format", {
    x <- stata_byte(1)
    attr(x, "format.stata") <- "%td"
    y <- stata_int(2)
    attr(y, "format.stata") <- "%12.0g"

    expect_warning(result <- dta_union(x, y), "display format")
    expect_identical(attr(result, "format.stata"), "%12.0g")
})

test_that("temporal union reconciles variable metadata left-first", {
    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    prototype <- read_dta(path)$price
    x <- dtatools:::.restore_stata_temporal(c(1, 2), prototype, "int")
    y <- dtatools:::.restore_stata_temporal(c(2, 3), prototype, "int")
    attr(x, "label") <- "left date"
    attr(y, "label") <- "right date"

    expect_warning(result <- dta_union(x, y), "variable label")
    expect_s3_class(result, "stata_temporal")
    expect_identical(attr(result, "format.stata"), "%td")
    expect_identical(attr(result, "label"), "left date")
})

test_that("base matching transforms two Stata-backed operands", {
    x <- stata_double(c(NA_real_, tagged_missing(c("a", "b"))))
    expect_identical(match(x, rev(x)), 3:1)
    expect_true(all(x %in% rev(x)))
})
