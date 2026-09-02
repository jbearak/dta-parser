test_that("stata_string infers UTF-8 byte storage and validates declarations", {
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

test_that("Stata strings restore metadata through slicing and conversion", {
    x <- dta_string(stats::setNames(c("a", "bb", "c"), letters[1:3]))
    attr(x, "label") <- "Answer"
    attr(x, "format.stata") <- "%9s"

    repeated <- x[c(2, 2, 1)]
    empty <- x[integer()]
    expect_s3_class(repeated, "stata_string")
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
})

test_that("common type with bare character can hold values chosen later", {
    value <- dta_string(c("alpha", "beta"), storage = "str5")
    result <- dplyr::if_else(value == "alpha", "recoded", value)

    expect_s3_class(result, "stata_string")
    expect_identical(as.character(result), c("recoded", "beta"))
    expect_identical(attr(result, "stata.string.storage", exact = TRUE), "strL")
})

test_that("Stata string sorting preserves metadata and rejects partial sorting", {
    value <- dta_string(c("b", "", "a"), storage = "str3")
    attr(value, "label") <- "Text"

    result <- sort(value, method = "shell")
    expect_s3_class(result, "stata_string")
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
    expect_s3_class(empty, "stata_string")
})
