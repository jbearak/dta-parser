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
    expect_error(stata_float(Inf), "use `NA_real_` for system missing")
    expect_error(stata_int(-Inf), "use `NA_real_` for system missing")
    expect_error(stata_double(Inf), "No Stata numeric storage")
    expect_error(stata_byte(NaN), "No Stata numeric storage")
    expect_error(
        stata_byte(.Machine$double.xmax), "No Stata numeric storage"
    )
})

test_that("constructors preserve Stata extended missing codes", {
    input <- c(1, NA_real_, tagged_missing(c("a", "z")))

    for (constructor in list(stata_byte, stata_int, stata_long, stata_float,
                             stata_double)) {
        value <- constructor(input)
        expect_identical(missing_tag(value), c(NA_character_, NA, "a", "z"))
    }
})

test_that("native construction rejects unsupported tagged missing payloads", {
    constructor <- get(
        "C_dtaparser_construct_numeric",
        envir = asNamespace("dtaparser")
    )

    for (tag in c("?", "A")) {
        expect_error(
            .Call(constructor, tagged_nan_for_test(tag), 0L, 0L),
            "accept only system missing and `.a` through `.z`",
            info = tag
        )
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

test_that("serialization preserves compact numeric backing", {
    source <- stata_byte(rep(c(-1, 0, 1, NA_real_), 25000L))

    serialized <- serialize(source, NULL)
    restored <- unserialize(serialized)

    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(source))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(restored))
    expect_identical(restored, source)
    expect_lt(length(serialized), length(serialize(as.double(source), NULL)))
})

test_that("saveRDS preserves compact numeric backing", {
    source <- read_dta(fixture("all_types_v118.dta"))$v_int
    path <- tempfile(fileext = ".rds")
    on.exit(unlink(path), add = TRUE)

    saveRDS(source, path, compress = FALSE)
    restored <- readRDS(path)

    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(source))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(restored))
    expect_identical(restored, source)
})

test_that("serialization preserves writable materialized values", {
    source <- stata_int(c(1, 2, 3))
    source <- dtaparser:::.mutate_first_numeric_altrep(source, 99)

    expect_false(dtaparser:::.is_unmaterialized_numeric_altrep(source))
    restored <- unserialize(serialize(source, NULL))

    expect_identical(as.double(restored), c(99, 2, 3))
    expect_identical(attributes(restored), attributes(source))
    expect_false(dtaparser:::.is_unmaterialized_numeric_altrep(restored))
})

test_that("base subsetting and duplication preserve compact backing", {
    source <- read_dta(fixture("all_types_v118.dta"))$v_long
    selected <- source[c(5L, 2L, NA_integer_, 2L)]
    copied <- rlang::duplicate(source)

    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(source))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(selected))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(copied))
    expect_identical(
        as.double(selected),
        c(as.double(source[c(5L, 2L)]), NA_real_, as.double(source[2L]))
    )
    expect_identical(copied, source)
})

test_that("vctrs proxy slicing preserves compact backing", {
    constructors <- list(stata_byte, stata_int, stata_long, stata_float)

    for (construct in constructors) {
        source <- construct(c(1, 2, NA_real_, tagged_missing("a")))
        proxy <- vctrs::vec_proxy(source)
        selected <- vctrs::vec_slice(
            proxy, c(4L, 2L, NA_integer_, 1L)
        )

        expect_true(
            dtaparser:::.is_unmaterialized_numeric_altrep(selected)
        )
        expect_identical(missing_tag(selected), c("a", NA, NA, NA))
        expect_identical(as.double(selected)[c(2L, 4L)], c(2, 1))
    }
})

test_that("vctrs restoration does not relabel different compact storage", {
    int_proxy <- vctrs::vec_proxy(stata_int(200))

    expect_error(
        vctrs::vec_restore(int_proxy, stata_byte()),
        "stata_int\\(x\\)"
    )
})

test_that("legacy compact widths preserve system missing encoding", {
    data <- read_dta(fixture("synthetic_v111.dta"))

    for (name in c("b", "i", "l", "f")) {
        source <- data[[name]]
        selected <- source[c(1L, 4L, NA_integer_)]
        restored <- unserialize(serialize(source, NULL))

        expect_true(
            dtaparser:::.is_unmaterialized_numeric_altrep(selected),
            info = name
        )
        expect_true(
            dtaparser:::.is_unmaterialized_numeric_altrep(restored),
            info = name
        )
        expect_identical(as.double(selected), c(as.double(source[1]), NA, NA))
        expect_identical(as.double(restored), as.double(source), info = name)
    }
})

test_that("narrow dates validate and encode in Stata source units", {
    byte_path <- fixture_with_temporal_storage("foreign")
    int_path <- fixture_with_temporal_storage("price")
    on.exit(unlink(c(byte_path, int_path)), add = TRUE)

    byte_date <- read_dta(byte_path)$foreign
    expect_s3_class(byte_date, "Date")
    expect_identical(stata_storage_type(byte_date), "byte")
    expect_identical(stata_storage_type(byte_date[1]), "byte")
    expect_identical(stata_storage_type(byte_date[[1]]), "byte")
    expect_identical(stata_storage_type(byte_date + 1), "byte")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(byte_date[1]))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(byte_date + 1))
    conditional <- dplyr::if_else(
        rep(TRUE, length(byte_date)), byte_date, byte_date
    )
    expect_identical(stata_storage_type(conditional), "byte")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(conditional))
    expect_identical(
        stata_storage_type(dplyr::slice(
            tibble::tibble(value = byte_date), 1:2
        )$value),
        "byte"
    )

    updated <- byte_date
    updated[1] <- as.Date(-3553, origin = "1970-01-01")
    expect_identical(stata_storage_type(updated), "byte")
    expect_identical(as.double(updated[[1]]), -3553)
    expect_error({
        updated[1] <- as.Date(-3552, origin = "1970-01-01")
    }, "stata_int\\(x\\)")
    expect_error(
        replace(
            byte_date, 1,
            structure(-3652.5, class = "Date")
        ),
        "stata_float\\(x\\)"
    )

    int_date <- read_dta(int_path)$price
    int_date[1] <- as.Date(29087, origin = "1970-01-01")
    expect_identical(stata_storage_type(int_date), "int")
    expect_identical(as.double(int_date[[1]]), 29087)
    expect_error({
        int_date[1] <- as.Date(29088, origin = "1970-01-01")
    }, "stata_long\\(x\\)")
    expect_identical(stata_storage_type(int_date[[1]] + 1), "long")
})

test_that("temporal summaries, concatenation, and recodes retain storage", {
    path <- fixture_with_temporal_storage("foreign")
    on.exit(unlink(path), add = TRUE)
    values <- read_dta(path)$foreign

    expect_identical(stata_storage_type(min(values)), "byte")
    expect_identical(stata_storage_type(mean(values)), "float")
    expect_identical(stata_storage_type(c(values, values)), "byte")
    expect_identical(stata_storage_type(rep(values, 2)), "byte")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(
        c(values, values)
    ))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(rep(values, 2)))
    expect_identical(
        stata_storage_type(vctrs::vec_c(
            values[1], as.Date(-3652, origin = "1970-01-01")
        )),
        "byte"
    )

    unlabelled <- set_variable_labels(set_value_labels(values), NULL)
    for (combined in list(
        vctrs::vec_c(values, unlabelled),
        vctrs::vec_c(unlabelled, values),
        dplyr::if_else(
            rep(c(TRUE, FALSE), length.out = length(values)),
            values,
            unlabelled
        )
    )) {
        expect_identical(var_label(combined), "Car origin")
        expect_identical(
            val_labels(combined), c(Domestic = 0, Foreign = 1)
        )
    }

    recoded <- dtaparser::recode(
        values,
        `-3653` = as.Date(-3651, origin = "1970-01-01")
    )
    expect_s3_class(recoded, "Date")
    expect_identical(stata_storage_type(recoded), "byte")
    expect_true(all(as.double(recoded[as.double(values) == -3653]) == -3651))
})

test_that("temporal common operations reject mixed kinds", {
    date_path <- fixture_with_temporal_storage("foreign", "%td")
    datetime_path <- fixture_with_temporal_storage("foreign", "%tc")
    on.exit(unlink(c(date_path, datetime_path)), add = TRUE)
    date <- read_dta(date_path)$foreign[1]
    datetime <- read_dta(datetime_path)$foreign[1]

    expect_error(c(date, datetime), "combine")
    expect_error(c(datetime, date), "combine")
    expect_error(min(date, datetime), "combine")
    expect_error(min(datetime, date), "combine")
    expect_error(max(date, datetime), "combine")
    expect_error(max(datetime, date), "combine")
    expect_error(range(date, datetime), "combine")
    expect_error(range(datetime, date), "combine")
    expect_error(
        c(date, as.Date(-3552, origin = "1970-01-01")),
        "stata_int\\(x\\)"
    )
})

test_that("empty temporal extrema retain base infinity behavior", {
    path <- fixture_with_temporal_storage("foreign")
    on.exit(unlink(path), add = TRUE)
    empty <- read_dta(path)$foreign[0]

    minimum <- suppressWarnings(min(empty))
    maximum <- suppressWarnings(max(empty))
    interval <- suppressWarnings(range(empty))
    expect_identical(as.double(minimum), Inf)
    expect_identical(as.double(maximum), -Inf)
    expect_identical(as.double(interval), c(Inf, -Inf))
    expect_null(stata_storage_type(minimum))
    expect_null(stata_storage_type(maximum))
    expect_null(stata_storage_type(interval))
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

test_that("base right and full merges can append native Stata keys", {
    left <- data.frame(
        id = set_variable_labels(
            set_value_labels(stata_byte(c(1, 2)), One = 1),
            "Identifier"
        ),
        left_value = c("a", "b")
    )
    right <- data.frame(
        id = set_value_labels(stata_byte(c(2, 3)), Three = 3),
        right_value = c("c", "d")
    )

    right_result <- merge(left, right, by = "id", all.y = TRUE)
    full_result <- merge(left, right, by = "id", all = TRUE)

    expect_identical(as.double(right_result$id), c(2, 3))
    expect_identical(as.double(full_result$id), c(1, 2, 3))
    expect_identical(stata_storage_type(right_result$id), "byte")
    expect_identical(stata_storage_type(full_result$id), "byte")
    expect_identical(var_label(full_result$id), "Identifier")
    expect_identical(val_labels(full_result$id), c(One = 1, Three = 3))
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(full_result$id))

    wider <- data.frame(
        id = set_value_labels(stata_int(c(2, 200)), TwoHundred = 200)
    )
    promoted <- merge(left, wider, by = "id", all = TRUE)
    expect_identical(as.double(promoted$id), c(1, 2, 200))
    expect_identical(stata_storage_type(promoted$id), "int")
    expect_identical(
        val_labels(promoted$id), c(One = 1, TwoHundred = 200)
    )
})

test_that("base full merges promote native Stata temporal keys", {
    byte_path <- fixture_with_temporal_storage("foreign")
    int_path <- fixture_with_temporal_storage("price")
    on.exit(unlink(c(byte_path, int_path)), add = TRUE)
    byte_date <- read_dta(byte_path)$foreign[1]
    int_date <- read_dta(int_path)$price[1]

    result <- merge(
        data.frame(id = byte_date),
        data.frame(id = int_date),
        by = "id",
        all = TRUE
    )

    expect_s3_class(result$id, "Date")
    expect_identical(stata_storage_type(result$id), "int")
    expect_identical(var_label(result$id), var_label(byte_date))
    expect_identical(val_labels(result$id), val_labels(byte_date))
    expect_identical(
        as.double(result$id), sort(c(as.double(byte_date), as.double(int_date)))
    )
})

test_that("extension promotes declared inputs without weakening assignment", {
    extended <- set_value_labels(stata_byte(1), One = 1)
    extended[3] <- set_value_labels(stata_int(200), TwoHundred = 200)

    expect_identical(as.double(extended), c(1, NA, 200))
    expect_identical(stata_storage_type(extended), "int")
    expect_identical(
        val_labels(extended), c(One = 1, TwoHundred = 200)
    )

    strict <- stata_byte(1)
    expect_error({
        strict[3] <- 101
    }, "stata_int\\(x\\)")

    fractional <- stata_byte(c(1, 2))
    expect_error({
        fractional[2.5] <- stata_int(200)
    })

    named <- stats::setNames(stata_byte(1), "one")
    named["two"] <- stats::setNames(stata_int(2), "source")
    expect_identical(names(named), c("one", "two"))
    expect_identical(stata_storage_type(named), "int")
})

test_that("dplyr joins preserve compatible Stata key information", {
    left_key <- set_variable_labels(
        set_value_labels(stata_byte(c(1, 2)), One = 1),
        "Identifier"
    )
    right_key <- set_value_labels(
        stata_int(c(2, 200)), TwoHundred = 200
    )
    left <- tibble::tibble(id = left_key, left_value = c("a", "b"))
    right <- tibble::tibble(id = right_key, right_value = c("c", "d"))

    coalesced <- dplyr::full_join(
        left, right, dplyr::join_by(id), relationship = "one-to-one"
    )
    retained <- dplyr::full_join(
        left, right, dplyr::join_by(id),
        relationship = "one-to-one", keep = TRUE
    )

    expect_identical(as.double(coalesced$id), c(1, 2, 200))
    expect_identical(stata_storage_type(coalesced$id), "int")
    expect_identical(var_label(coalesced$id), "Identifier")
    expect_identical(
        val_labels(coalesced$id), c(One = 1, TwoHundred = 200)
    )
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(coalesced$id))
    expect_identical(stata_storage_type(retained$id.x), "byte")
    expect_identical(stata_storage_type(retained$id.y), "int")
    expect_identical(val_labels(retained$id.x), c(One = 1))
    expect_identical(val_labels(retained$id.y), c(TwoHundred = 200))
})

test_that("value labels compose with declared storage classes", {
    values <- stata_byte(c(0, 1))
    values <- set_value_labels(values, No = 0, Yes = 1)

    expect_s3_class(values, "haven_labelled")
    expect_identical(stata_storage_type(values), "byte")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(values))

    values[1] <- 1
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(values))

    values <- set_value_labels(values)
    expect_false(inherits(values, "haven_labelled"))
    expect_s3_class(values, "stata_numeric")
    expect_identical(stata_storage_type(values), "byte")
})

test_that("common types reconcile value and variable labels", {
    left <- set_variable_labels(
        set_value_labels(stata_byte(c(1, 2)), One = 1),
        "Left variable"
    )
    right <- set_variable_labels(
        set_value_labels(stata_int(c(2, 3)), Three = 3),
        "Right variable"
    )
    unlabelled <- stata_byte(c(2, 3))
    variable_only <- set_variable_labels(
        stata_byte(c(1, 2)), "Only variable"
    )

    for (result in list(
        vctrs::vec_c(left, unlabelled),
        vctrs::vec_c(unlabelled, left),
        dplyr::if_else(c(TRUE, FALSE), left, unlabelled)
    )) {
        expect_s3_class(result, "haven_labelled")
        expect_identical(val_labels(result), c(One = 1))
    }

    for (result in list(
        vctrs::vec_c(variable_only, unlabelled),
        vctrs::vec_c(unlabelled, variable_only),
        dplyr::if_else(c(TRUE, FALSE), variable_only, unlabelled)
    )) {
        expect_identical(var_label(result), "Only variable")
    }

    left_right <- vctrs::vec_c(left, right)
    right_left <- vctrs::vec_c(right, left)
    conditional <- dplyr::if_else(c(TRUE, FALSE), left, right)
    expect_identical(val_labels(left_right), c(One = 1, Three = 3))
    expect_identical(val_labels(right_left), c(Three = 3, One = 1))
    expect_identical(val_labels(conditional), c(One = 1, Three = 3))
    expect_identical(var_label(left_right), "Left variable")
    expect_identical(var_label(right_left), "Right variable")

    conflict <- set_value_labels(stata_byte(1), Uno = 1)
    expect_warning(
        resolved <- vctrs::vec_c(left, conflict),
        "conflicting value labels"
    )
    expect_identical(val_labels(resolved)[[1L]], 1)
    expect_identical(names(val_labels(resolved))[[1L]], "One")
    expect_warning(
        reversed <- vctrs::vec_c(conflict, left),
        "conflicting value labels"
    )
    expect_identical(names(val_labels(reversed))[[1L]], "Uno")
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
    expect_identical(!stata_int(c(0, 1, NA_real_)), c(TRUE, FALSE, NA))
})

test_that("Complex group members use value-dependent storage", {
    argument <- Arg(stata_int(-1))
    modulus <- Mod(stata_int(-32767))

    expect_identical(stata_storage_type(argument), "float")
    expect_equal(as.double(argument), pi, tolerance = 1e-6)
    expect_identical(stata_storage_type(modulus), "long")
    expect_identical(as.double(modulus), 32767)
    expect_identical(stata_storage_type(Re(stata_byte(2))), "byte")
    expect_identical(stata_storage_type(Im(stata_byte(2))), "byte")
    expect_identical(stata_storage_type(Conj(stata_byte(2))), "byte")
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

test_that("Summary generics accept bare numeric and logical arguments", {
    total <- sum(stata_byte(1), 2)
    extremes <- range(stata_byte(1), 101)

    expect_identical(stata_storage_type(total), "byte")
    expect_identical(as.double(total), 3)
    expect_identical(stata_storage_type(extremes), "int")
    expect_identical(as.double(extremes), c(1, 101))
    expect_identical(all(stata_byte(1), TRUE), TRUE)
    expect_identical(any(stata_byte(0), TRUE), TRUE)
})

test_that("base ifelse strips declared storage as documented", {
    result <- ifelse(c(TRUE, FALSE), stata_byte(c(1, 2)), 0)

    expect_null(stata_storage_type(result))
    expect_identical(result, c(1, 0))
})

test_that("undefined Stata arithmetic becomes system missing", {
    divided <- stata_int(1) / 0
    rooted <- sqrt(stata_int(-1))

    expect_identical(stata_storage_type(divided), "int")
    expect_identical(as.double(divided), NA_real_)
    expect_identical(stata_storage_type(rooted), "int")
    expect_identical(as.double(rooted), NA_real_)
})
