test_that("dta_string infers UTF-8 byte storage and validates declarations", {
    expect_identical(
        attr(dta_string(c("a", "é")), "stata.string.storage"),
        "str2"
    )
    expect_identical(
        attr(dta_string(strrep("x", 2046)), "stata.string.storage"),
        "strL"
    )
    expect_error(dta_string(NA_character_), "use `\\\"\\\"`")
    expect_error(dta_string("wide", "str2"), "str4")
    expect_error(dta_string("x", "str0"), "str1.*str2045")
})

test_that("dta_storage_type reports declared string storage", {
    expect_identical(dta_storage_type(dta_string(c("a", "bb"))), "str2")
    expect_identical(
        dta_storage_type(dta_string(strrep("x", 2046))), "strL"
    )
    # A `gen()` string carries the declaration without the `dta_string`
    # class, so the attribute alone has to be enough.
    bare <- structure("ab", `stata.string.storage` = "str4")
    expect_identical(dta_storage_type(bare), "str4")
    expect_null(dta_storage_type("undeclared"))
    expect_identical(dta_storage_type(dta_int(1)), "int")
})

test_that("Stata strings restore metadata through slicing and conversion", {
    x <- dta_string(stats::setNames(c("a", "bb", "c"), letters[1:3]))
    attr(x, "label") <- "Answer"
    attr(x, "format.stata") <- "%9s"

    repeated <- x[c(2, 2, 1)]
    empty <- x[integer()]
    expect_s3_class(repeated, "dta_string")
    expect_identical(as.character(repeated), c(b = "bb", b = "bb", a = "a"))
    expect_identical(attr(repeated, "label"), "Answer")
    expect_identical(attr(empty, "stata.string.storage"), "str2")
    expect_identical(attr(empty, "label"), "Answer")
    expect_identical(unname(as.character(empty)), character())
    expect_identical(names(empty), character())

    plain <- as.character(x)
    expect_identical(plain, c(a = "a", b = "bb", c = "c"))
    expect_null(attr(plain, "stata.string.storage", exact = TRUE))
    expect_null(attr(plain, "label", exact = TRUE))
})

test_that("Stata string concatenation widens and replacement stays strict", {
    narrow <- dta_string("a", "str1")
    wide <- dta_string("wide", "str4")
    attr(narrow, "label") <- "Left"

    combined <- vctrs::vec_c(narrow, wide)
    expect_identical(as.character(combined), c("a", "wide"))
    expect_identical(attr(combined, "stata.string.storage"), "str4")
    expect_identical(attr(combined, "label"), "Left")
    expect_identical(attr(c(narrow, wide), "stata.string.storage"), "str4")

    expect_error(narrow[1] <- "wide", "str1")
    expect_error(narrow[1] <- NA_character_, "use `\\\"\\\"`")
    narrow[2] <- "b"
    expect_identical(as.character(narrow), c("a", "b"))
    # Extending the vector takes the common storage, as concatenation
    # does, and a gap the extension opens is Stata's `""`.
    narrow[4] <- "wide"
    expect_identical(attr(narrow, "stata.string.storage"), "str4")
    expect_identical(as.character(narrow), c("a", "b", "", "wide"))
    expect_error(narrow[5] <- NA_character_, "NA_character_")
    # A vctrs cast spells `NA` as `""`, as a join's padding needs.
    padded <- vctrs::vec_cast(c("x", NA), dta_string("a"))
    expect_identical(as.character(padded), c("x", ""))
    expect_identical(
        as.character(vctrs::vec_c(dta_string("a"), NA_character_)),
        c("a", "")
    )
})

test_that("common type with bare character can hold values chosen later", {
    value <- dta_string(c("alpha", "beta"), storage = "str5")
    result <- dplyr::if_else(value == "alpha", "recoded", value)

    expect_s3_class(result, "dta_string")
    expect_identical(as.character(result), c("recoded", "beta"))
    expect_identical(attr(result, "stata.string.storage", exact = TRUE), "strL")
})

test_that("Stata string sorting preserves metadata and rejects partial sorting", {
    value <- dta_string(c("b", "", "a"), storage = "str3")
    attr(value, "label") <- "Text"

    result <- sort(value, method = "shell")
    expect_s3_class(result, "dta_string")
    expect_identical(as.character(result), c("", "a", "b"))
    expect_identical(attr(result, "label", exact = TRUE), "Text")
    expect_warning(sort(value, na.last = FALSE), "has no effect")
    expect_error(sort(value, partial = 1L), "not supported yet")
})

test_that("Stata restoration drops unknown attributes once", {
    numeric <- dta_int(c(1, 2))
    attr(numeric, "mystery") <- "unknown"
    expect_warning(
        restored <- numeric[c(2, 2, 1)],
        "Dropped unknown attribute.*mystery"
    )
    expect_null(attr(restored, "mystery", exact = TRUE))
    expect_identical(dta_storage_type(restored), "int")

    string <- dta_string(c("a", "b"))
    attr(string, "mystery") <- "unknown"
    expect_warning(empty <- string[integer()], "Dropped unknown attribute")
    expect_null(attr(empty, "mystery", exact = TRUE))
    expect_s3_class(empty, "dta_string")
})

test_that("Stata string subset and restore padding use empty missing strings", {
    for (storage in c("str3", "strL")) {
        value <- dta_string(c(a = "a", b = "bb"), storage)
        attr(value, "label") <- "Text"
        attr(value, "format.stata") <- "%9s"
        results <- list(
            value[c(1L, 3L, NA_integer_)],
            value[c("a", "absent", NA_character_)],
            value[c(TRUE, NA, TRUE)],
            vctrs::vec_slice(value, c(1L, NA_integer_, NA_integer_)),
            vctrs::vec_restore(c("a", NA_character_, NA_character_), value)
        )
        for (result in results) {
            expect_identical(unname(as.character(result)), c("a", "", ""))
            expect_identical(dta_storage_type(result), storage)
            expect_identical(attr(result, "label"), "Text")
            expect_identical(attr(result, "format.stata"), "%9s")
        }
        expect_identical(names(results[[1L]]), c("a", "", ""))
        expect_identical(as.character(vctrs::vec_init(value, 2L)), c("", ""))
        expect_length(value[integer()], 0L)
        expect_error(value[1L] <- NA_character_, "NA_character_")
    }
})
