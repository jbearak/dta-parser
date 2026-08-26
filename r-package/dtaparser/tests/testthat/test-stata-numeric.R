test_that("storage constructors create declared compact vectors", {
    constructors <- list(
        byte = stata_byte,
        int = stata_int,
        long = stata_long,
        float = stata_float,
        double = stata_double
    )

    for (storage in names(constructors)) {
        value <- constructors[[storage]](c(-1, 0, 1, NA_real_))

        expect_identical(stata_storage_type(value), storage, info = storage)
        expect_s3_class(value, paste0("stata_", storage))
        expect_identical(
            as.double(value), c(-1, 0, 1, NA_real_), info = storage
        )
        expect_identical(typeof(value), "double", info = storage)
        expect_identical(
            dtaparser:::.is_numeric_altrep(value),
            storage != "double",
            info = storage
        )
    }
})

test_that("size allocation creates system-missing compact vectors", {
    constructors <- list(
        byte = stata_byte,
        int = stata_int,
        long = stata_long,
        float = stata_float,
        double = stata_double
    )

    for (storage in names(constructors)) {
        value <- constructors[[storage]](.size = 3)

        expect_identical(as.double(value), rep(NA_real_, 3L), info = storage)
        expect_identical(stata_storage_type(value), storage, info = storage)
    }

    expect_error(stata_byte(1, .size = 1), "Supply `x` or `.size`")
    expect_error(stata_byte(.size = -1), "non-negative whole number")
})

test_that("constructors enforce Stata ranges and precision rules", {
    expect_identical(as.double(stata_byte(c(-127, 100))), c(-127, 100))
    expect_identical(
        as.double(stata_int(c(-32767, 32740))), c(-32767, 32740)
    )
    expect_identical(
        as.double(stata_long(c(-2147483647, 2147483620))),
        c(-2147483647, 2147483620)
    )
    expect_identical(
        as.double(stata_float(0.1)),
        0.10000000149011612
    )

    expect_error(stata_byte(101), "stata_int\\(x\\)")
    expect_error(stata_int(1.5), "stata_float\\(x\\)")
    expect_error(stata_int(32741), "stata_long\\(x\\)")
    expect_error(stata_long(2147483621), "stata_double\\(x\\)")
    expect_error(stata_float(Inf), "stata_double\\(x\\)")
    expect_error(stata_double(Inf), "cannot represent")
})

test_that("constructors preserve Stata extended missing codes", {
    input <- c(1, NA_real_, tagged_missing(c("a", "z")))

    for (constructor in list(stata_byte, stata_int, stata_long, stata_float,
                             stata_double)) {
        value <- constructor(input)
        expect_identical(missing_tag(value), c(NA_character_, NA, "a", "z"))
    }
})

test_that("storage inspection does not materialize imported columns", {
    path <- fixture("all_types_v118.dta")
    metadata <- dtaparser:::.dta_metadata(path)
    expected <- attr(metadata, "dta_storage", exact = TRUE)
    data <- read_dta(path)
    numeric <- expected != "character"

    actual <- vapply(data[numeric], stata_storage_type, character(1))

    expect_identical(unname(actual), expected[numeric])
    compact <- expected[numeric] != "double"
    expect_true(all(vapply(
        data[numeric][compact],
        dtaparser:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_null(stata_storage_type(1:3))
})

test_that("imported temporal columns retain storage through supported mutation", {
    skip_if_not_installed("haven")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    haven::write_dta(
        data.frame(date = as.Date(c("1960-01-01", "2020-01-01"))),
        path,
        version = 15
    )
    values <- read_dta(path)$date
    shifted <- values + 1
    selected <- dplyr::if_else(c(TRUE, FALSE), values, shifted)

    expect_s3_class(values, "Date")
    expect_s3_class(values, "stata_temporal")
    expect_s3_class(shifted, "Date")
    expect_s3_class(selected, "Date")
    expect_identical(stata_storage_type(shifted), "double")
    expect_identical(stata_storage_type(selected), "double")
    expect_identical(
        as.character(selected), c("1960-01-01", "2020-01-02")
    )
})

test_that("common types follow the Stata storage promotion lattice", {
    types <- c("byte", "int", "long", "float", "double")
    constructors <- stats::setNames(
        list(stata_byte, stata_int, stata_long, stata_float, stata_double),
        types
    )
    expected <- matrix(c(
        "byte",   "int",    "long",   "float",  "double",
        "int",    "int",    "long",   "float",  "double",
        "long",   "long",   "long",   "double", "double",
        "float",  "float",  "double", "float",  "double",
        "double", "double", "double", "double", "double"
    ), nrow = 5L, byrow = TRUE, dimnames = list(types, types))

    for (left in types) {
        for (right in types) {
            common <- vctrs::vec_ptype2(
                constructors[[left]](), constructors[[right]]()
            )
            expect_identical(
                stata_storage_type(common), expected[left, right],
                info = paste(left, right)
            )
        }
    }
})

test_that("declared storage wins over bare numeric and logical vectors", {
    prototypes <- list(double(), integer(), logical())

    for (prototype in prototypes) {
        expect_identical(
            stata_storage_type(vctrs::vec_ptype2(stata_int(), prototype)),
            "int"
        )
        expect_identical(
            stata_storage_type(vctrs::vec_ptype2(prototype, stata_int())),
            "int"
        )
    }

    combined <- vctrs::vec_c(stata_byte(c(1, 2)), 3L, TRUE)
    expect_identical(stata_storage_type(combined), "byte")
    expect_identical(as.double(combined), c(1, 2, 3, 1))
    expect_true(dtaparser:::.is_numeric_altrep(combined))
})

test_that("casts into declared storage are strict and preserve missing tags", {
    input <- stata_double(c(1, NA_real_, tagged_missing("f")))
    cast <- vctrs::vec_cast(input, stata_byte())

    expect_identical(stata_storage_type(cast), "byte")
    expect_identical(as.double(cast)[1:2], c(1, NA_real_))
    expect_identical(missing_tag(cast), c(NA_character_, NA, "f"))
    expect_error(
        vctrs::vec_cast(stata_double(101), stata_byte()),
        "stata_int\\(x\\)"
    )
    expect_error(
        vctrs::vec_cast(stata_double(1.5), stata_int()),
        "stata_float\\(x\\)"
    )
    expect_identical(
        as.double(vctrs::vec_cast(stata_double(0.1), stata_float())),
        0.10000000149011612
    )
})

test_that("assignment and vctrs recodes re-encode compact storage", {
    values <- stata_byte(c(1, 2, 3, tagged_missing("a")))
    values[2] <- 10
    replaced <- replace(values, 1, 20)
    conditional <- dplyr::if_else(
        c(TRUE, FALSE, FALSE, FALSE), 30, values
    )

    for (result in list(values, replaced, conditional)) {
        expect_identical(stata_storage_type(result), "byte")
        expect_true(dtaparser:::.is_numeric_altrep(result))
        expect_identical(missing_tag(result)[4], "a")
    }
    expect_identical(as.double(values)[1:3], c(1, 10, 3))
    expect_identical(as.double(replaced)[1:3], c(20, 10, 3))
    expect_identical(as.double(conditional)[1:3], c(30, 10, 3))

    expect_error({
        values[1] <- 101
    }, "stata_int\\(x\\)")
    expect_error(replace(values, 1, 101), "stata_int\\(x\\)")
    expect_error(
        dplyr::if_else(rep(TRUE, length(values)), 101, values),
        "stata_int\\(x\\)"
    )
})

test_that("value labels compose with declared storage classes", {
    values <- stata_byte(c(0, 1))
    values <- set_value_labels(values, No = 0, Yes = 1)

    expect_s3_class(values, "haven_labelled")
    expect_identical(stata_storage_type(values), "byte")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(values))

    values <- set_value_labels(values)
    expect_false(inherits(values, "haven_labelled"))
    expect_s3_class(values, "stata_numeric")
    expect_identical(stata_storage_type(values), "byte")
})

test_that("arithmetic promotes from operand storage according to result values", {
    cases <- list(
        byte_stays_byte = list(stata_byte(c(1, 2)) + 1, "byte", c(2, 3)),
        byte_overflow = list(stata_byte(100) + 1, "int", 101),
        int_overflow = list(stata_int(32740) + 1, "long", 32741),
        int_fraction = list(stata_int(1) / 2, "float", 0.5),
        long_fraction = list(stata_long(1) / 2, "double", 0.5),
        float_stays_float = list(stata_float(1) / 2, "float", 0.5),
        long_float_meet = list(
            stata_long(1) + stata_float(2), "double", 3
        ),
        unary_overflow = list(-stata_byte(-127), "int", 127)
    )

    for (name in names(cases)) {
        result <- cases[[name]][[1L]]
        expect_identical(
            stata_storage_type(result), cases[[name]][[2L]], info = name
        )
        expect_identical(
            as.double(result), cases[[name]][[3L]], info = name
        )
    }
})

test_that("arithmetic preserves tags and returns bare logical comparisons", {
    values <- stata_int(c(1, tagged_missing("a"), NA_real_))
    result <- values + 1

    expect_identical(stata_storage_type(result), "int")
    expect_identical(as.double(result)[1], 2)
    expect_identical(missing_tag(result), c(NA_character_, "a", NA))
    expect_identical(values == 1, c(TRUE, NA, NA))
    expect_null(stata_storage_type(values == 1))
})

test_that("math and summary generics use value-dependent storage", {
    absolute <- abs(stata_byte(c(-127, 1)))
    exact_root <- sqrt(stata_int(c(4, 9)))
    rounded_root <- sqrt(stata_int(c(2, 4)))
    total <- sum(stata_byte(c(100, 100)))
    average <- mean(stata_int(c(1, 2)))
    cumulative <- cumsum(stata_byte(c(50, 50, 50)))

    expect_identical(stata_storage_type(absolute), "int")
    expect_identical(as.double(absolute), c(127, 1))
    expect_identical(stata_storage_type(exact_root), "int")
    expect_identical(as.double(exact_root), c(2, 3))
    expect_identical(stata_storage_type(rounded_root), "float")
    expect_identical(
        as.double(rounded_root), c(1.4142135381698608, 2)
    )
    expect_identical(stata_storage_type(total), "int")
    expect_identical(as.double(total), 200)
    expect_identical(stata_storage_type(average), "float")
    expect_identical(as.double(average), 1.5)
    expect_identical(stata_storage_type(cumulative), "int")
    expect_identical(as.double(cumulative), c(50, 100, 150))
    expect_identical(is.finite(stata_float(c(1, NA_real_))), c(TRUE, FALSE))
})

test_that("undefined Stata arithmetic becomes system missing", {
    divided <- stata_int(1) / 0
    rooted <- sqrt(stata_int(-1))

    expect_identical(stata_storage_type(divided), "int")
    expect_identical(as.double(divided), NA_real_)
    expect_identical(stata_storage_type(rooted), "int")
    expect_identical(as.double(rooted), NA_real_)
})
