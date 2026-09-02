test_that("storage constructors create declared compact vectors", {
    constructors <- list(
        byte = dta_byte,
        int = dta_int,
        long = dta_long,
        float = dta_float,
        double = dta_double
    )

    for (storage in names(constructors)) {
        value <- constructors[[storage]](c(-1, 0, 1, NA_real_))

        expect_identical(dta_storage_type(value), storage, info = storage)
        expect_s3_class(value, paste0("stata_", storage))
        expect_identical(
            as.double(value), c(-1, 0, 1, NA_real_), info = storage
        )
        expect_identical(typeof(value), "double", info = storage)
        expect_identical(
            dtatools:::.is_numeric_altrep(value),
            storage != "double",
            info = storage
        )
    }
})

test_that("size allocation creates system-missing compact vectors", {
    constructors <- list(
        byte = dta_byte,
        int = dta_int,
        long = dta_long,
        float = dta_float,
        double = dta_double
    )

    for (storage in names(constructors)) {
        value <- constructors[[storage]](.size = 3)

        expect_identical(as.double(value), rep(NA_real_, 3L), info = storage)
        expect_identical(dta_storage_type(value), storage, info = storage)
    }

    expect_error(dta_byte(1, .size = 1), "Supply `x` or `.size`")
    expect_error(dta_byte(.size = -1), "non-negative whole number")
})

test_that("constructors enforce Stata ranges and precision rules", {
    expect_identical(as.double(dta_byte(c(-127, 100))), c(-127, 100))
    expect_identical(
        as.double(dta_int(c(-32767, 32740))), c(-32767, 32740)
    )
    expect_identical(
        as.double(dta_long(c(-2147483647, 2147483620))),
        c(-2147483647, 2147483620)
    )
    expect_identical(
        as.double(dta_float(0.1)),
        0.10000000149011612
    )

    expect_error(dta_byte(101), "dta_int\\(x\\)")
    expect_error(dta_int(1.5), "dta_float\\(x\\)")
    expect_error(dta_int(32741), "dta_long\\(x\\)")
    expect_error(dta_long(2147483621), "dta_double\\(x\\)")
    expect_error(dta_float(Inf), "use `NA_real_` for system missing")
    expect_error(dta_int(-Inf), "use `NA_real_` for system missing")
    expect_error(dta_double(Inf), "No Stata numeric storage")
    expect_error(dta_byte(NaN), "No Stata numeric storage")
    expect_error(
        dta_byte(.Machine$double.xmax), "No Stata numeric storage"
    )
})

test_that("constructors preserve Stata extended missing codes", {
    input <- c(1, NA_real_, tagged_missing(c("a", "z")))

    for (constructor in list(dta_byte, dta_int, dta_long, dta_float,
                             dta_double)) {
        value <- constructor(input)
        expect_identical(missing_tag(value), c(NA_character_, NA, "a", "z"))
    }
})

test_that("Stata numeric comparisons use missing-code identity and order", {
    values <- dta_double(c(
        -1, 1, NA_real_, tagged_missing("a"), tagged_missing("z")
    ))

    expect_identical(values == values, rep(TRUE, 5L))
    expect_identical(values[3] < values[4], TRUE)
    expect_identical(values[4] < values[5], TRUE)
    expect_identical(values[2] < values[3], TRUE)
    expect_identical(values[4] == tagged_missing("a"), TRUE)
    expect_identical(values[4] == tagged_missing("b"), FALSE)
    expect_identical(dta_byte(100) < 101, TRUE)
})

test_that("Stata numeric comparisons return empty results for empty operands", {
    empty <- dta_byte()

    expect_identical(empty == dta_byte(1), logical())
    expect_identical(dta_int(1) != empty, logical())
    expect_identical(empty < c(1, 2), logical())
    expect_identical(c(1, 2) >= empty, logical())
})

test_that("Stata numeric ordering retains and ranks missing codes", {
    values <- dta_byte(c(
        tagged_missing("b"), 2, NA_real_, tagged_missing("a"), 1
    ))
    names(values) <- letters[1:5]

    ascending <- sort(values)
    descending <- sort(values, decreasing = TRUE)

    expect_identical(as.double(ascending)[1:2], c(1, 2))
    expect_identical(
        unname(missing_tag(ascending)), c(NA, NA, NA, "a", "b")
    )
    expect_identical(names(ascending), c("e", "b", "c", "d", "a"))
    expect_identical(
        unname(missing_tag(descending)), c("b", "a", NA, NA, NA)
    )
    expect_identical(order(values), c(5L, 2L, 3L, 4L, 1L))
    expect_identical(as.double(sort(values, method = "shell")), as.double(ascending))
    expect_warning(
        retained <- sort(values, na.last = FALSE),
        "does not relocate or remove"
    )
    expect_identical(as.double(retained), as.double(ascending))
    expect_error(sort(values, partial = 2), "not supported yet")
})

test_that("vctrs identity distinguishes Stata missing codes", {
    values <- dta_double(c(
        NA_real_, NA_real_, tagged_missing("a"), tagged_missing("a"),
        tagged_missing("b")
    ))

    expect_identical(
        vctrs::vec_equal(values, values), rep(TRUE, length(values))
    )
    expect_false(any(vctrs::vec_detect_missing(values)))
    expect_identical(duplicated(values), c(FALSE, TRUE, FALSE, TRUE, FALSE))
    expect_identical(anyDuplicated(values), 2L)
    expect_identical(missing_tag(unique(values)), c(NA, "a", "b"))

    expect_identical(
        duplicated(values, incomparables = tagged_missing("a")),
        c(FALSE, TRUE, FALSE, FALSE, FALSE)
    )
    expect_identical(
        missing_tag(unique(values, incomparables = tagged_missing("a"))),
        c(NA, "a", "a", "b")
    )
    expect_identical(
        anyDuplicated(values, incomparables = NA_real_),
        4L
    )
    expect_identical(
        missing_tag(unique(values, fromLast = TRUE)),
        c(NA, "a", "b")
    )
    expect_identical(
        duplicated(values, nmax = 3L),
        c(FALSE, TRUE, FALSE, TRUE, FALSE)
    )
})

test_that("identity operations reject noncanonical NaN payloads", {
    value <- tagged_nan_for_test("?")
    attributes(value) <- attributes(dta_double(1))

    expect_error(value == value, "noncanonical NaN payload")
    expect_error(sort(value), "noncanonical NaN payload")
    expect_error(vctrs::vec_equal(value, value), "NA_real_")
    expect_true(is.na(value))
})

test_that("Stata temporal vectors use numeric missing identity", {
    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    prototype <- read_dta(path)$price
    values <- dtatools:::.restore_stata_temporal(
        c(1, NA_real_, tagged_missing("a")), prototype, "int"
    )

    expect_identical(values == values, rep(TRUE, 3L))
    expect_identical(missing_tag(sort(values)), c(NA, NA, "a"))
    expect_s3_class(sort(values), "Date")
    expect_false(any(vctrs::vec_detect_missing(values)))
})

test_that("native construction rejects unsupported tagged missing payloads", {
    constructor <- get(
        "C_dtatools_construct_numeric",
        envir = asNamespace("dtatools")
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
    metadata <- dtatools:::.dta_metadata(path)
    expected <- attr(metadata, "dta_storage", exact = TRUE)
    data <- read_dta(path)
    numeric <- expected != "character"

    actual <- vapply(data[numeric], dta_storage_type, character(1))

    expect_identical(unname(actual), expected[numeric])
    compact <- expected[numeric] != "double"
    expect_true(all(vapply(
        data[numeric][compact],
        dtatools:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    expect_null(dta_storage_type(1:3))
})

test_that("serialization preserves compact numeric backing", {
    source <- dta_byte(rep(c(-1, 0, 1, NA_real_), 25000L))

    serialized <- serialize(source, NULL)
    restored <- unserialize(serialized)

    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(restored))
    expect_identical(restored, source)
    expect_lt(length(serialized), length(serialize(as.double(source), NULL)))
})

test_that("saveRDS preserves compact numeric backing", {
    source <- read_dta(fixture("all_types_v118.dta"))$v_int
    path <- tempfile(fileext = ".rds")
    on.exit(unlink(path), add = TRUE)

    saveRDS(source, path, compress = FALSE)
    restored <- readRDS(path)

    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(restored))
    expect_identical(restored, source)
})

test_that("serialization preserves writable materialized values", {
    source <- dta_int(c(1, 2, 3))
    source <- dtatools:::.mutate_first_numeric_altrep(source, 99)

    expect_false(dtatools:::.is_unmaterialized_numeric_altrep(source))
    restored <- unserialize(serialize(source, NULL))

    expect_identical(as.double(restored), c(99, 2, 3))
    expect_identical(attributes(restored), attributes(source))
    expect_false(dtatools:::.is_unmaterialized_numeric_altrep(restored))
})

test_that("stored public coercions are isolated from reference mutation", {
    source <- data.frame(x = dta_byte(1:3))
    eager <- as.double(source$x)
    invisible(eager[[1]])
    lazy <- as.double(source$x)
    text <- as.character(source$x)

    replace_values(source, x, 9, where = 1)

    expect_identical(eager, c(1, 2, 3))
    expect_identical(lazy, c(1, 2, 3))
    expect_identical(text, c("1", "2", "3"))
})

test_that("stored vctrs proxies are isolated from reference mutation", {
    numeric_source <- data.frame(x = dta_byte(1:3))
    numeric_proxy <- vctrs::vec_proxy(numeric_source$x)
    replace_values(numeric_source, x, 9, where = 1)
    expect_identical(as.double(numeric_proxy), c(1, 2, 3))

    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    temporal_source <- data.frame(x = read_dta(path)$price)
    before <- as.double(temporal_source$x)
    temporal_proxy <- vctrs::vec_proxy(temporal_source$x)
    replacement <- temporal_source$x[[2]]
    replace_values(temporal_source, x, replacement, where = 1)
    expect_identical(as.double(temporal_proxy), before)
})

test_that("data-frame coercion preserves vector and explicit row names", {
    value <- dta_byte(setNames(1:2, c("source-1", "source-2")))
    implicit <- as.data.frame(value)
    explicit <- as.data.frame(value, row.names = c("row-1", "row-2"))

    expect_identical(row.names(implicit), c("source-1", "source-2"))
    expect_identical(row.names(explicit), c("row-1", "row-2"))
    expect_null(names(implicit[[1L]]))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(implicit[[1L]]))
    expect_error(as.data.frame(value, row.names = "short"), "length 2")
})

test_that("lazy public snapshots release stripped source attributes", {
    finalized <- new.env(parent = emptyenv())
    finalized$done <- FALSE
    snapshot <- local({
        source <- dta_byte(1:3)
        tracker <- new.env(parent = emptyenv())
        reg.finalizer(
            tracker,
            function(environment) finalized$done <- TRUE,
            onexit = FALSE
        )
        attr(source, "obsolete") <- tracker
        as.double(source)
    })

    for (iteration in seq_len(5L)) {
        if (finalized$done) break
        gc(full = TRUE)
    }
    expect_true(finalized$done)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(snapshot))
    expect_identical(snapshot, c(1, 2, 3))
})

test_that("base subsetting and duplication preserve compact backing", {
    source <- read_dta(fixture("all_types_v118.dta"))$v_long
    selected <- source[c(5L, 2L, NA_integer_, 2L)]
    copied <- rlang::duplicate(source)

    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(selected))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(copied))
    expect_identical(
        as.double(selected),
        c(as.double(source[c(5L, 2L)]), NA_real_, as.double(source[2L]))
    )
    expect_identical(copied, source)
})

test_that("vctrs proxy slicing preserves compact backing", {
    constructors <- list(dta_byte, dta_int, dta_long, dta_float)

    for (construct in constructors) {
        source <- construct(c(1, 2, NA_real_, tagged_missing("a")))
        proxy <- vctrs::vec_proxy(source)
        selected <- vctrs::vec_slice(
            proxy, c(4L, 2L, NA_integer_, 1L)
        )

        expect_true(
            dtatools:::.is_unmaterialized_numeric_altrep(selected)
        )
        expect_identical(missing_tag(selected), c("a", NA, NA, NA))
        expect_identical(as.double(selected)[c(2L, 4L)], c(2, 1))
    }
})

test_that("vctrs restoration distinguishes storage and temporal encoding", {
    int_proxy <- vctrs::vec_proxy(dta_int(200))

    expect_error(
        vctrs::vec_restore(int_proxy, dta_byte()),
        "dta_int\\(x\\)"
    )

    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    date <- read_dta(path)$price
    date_proxy <- vctrs::vec_proxy(date)

    expect_false(dtatools:::.compact_stata_storage_matches(
        date_proxy, "int"
    ))
    plain <- vctrs::vec_restore(date_proxy, dta_int())
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(plain))
    expect_identical(as.double(plain), as.double(date))

    plain_proxy <- vctrs::vec_proxy(dta_int(c(0, 1, 2)))
    expect_false(dtatools:::.compact_stata_storage_matches(
        plain_proxy, "int", dtatools:::.stata_temporal_date
    ))
    restored_date <- vctrs::vec_restore(plain_proxy, date[0])
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(restored_date)
    )
    expect_s3_class(restored_date, "Date")
    expect_identical(as.double(restored_date), c(0, 1, 2))
})

test_that("legacy compact widths preserve system missing encoding", {
    data <- read_dta(fixture("synthetic_v111.dta"))

    for (name in c("b", "i", "l", "f")) {
        source <- data[[name]]
        selected <- source[c(1L, 4L, NA_integer_)]
        restored <- unserialize(serialize(source, NULL))

        expect_true(
            dtatools:::.is_unmaterialized_numeric_altrep(selected),
            info = name
        )
        expect_true(
            dtatools:::.is_unmaterialized_numeric_altrep(restored),
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
    expect_identical(dta_storage_type(byte_date), "byte")
    expect_identical(dta_storage_type(byte_date[1]), "byte")
    expect_identical(dta_storage_type(byte_date[[1]]), "byte")
    expect_identical(dta_storage_type(byte_date + 1), "byte")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(byte_date[1]))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(byte_date + 1))
    conditional <- dplyr::if_else(
        rep(TRUE, length(byte_date)), byte_date, byte_date
    )
    expect_identical(dta_storage_type(conditional), "byte")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(conditional))
    expect_identical(
        dta_storage_type(dplyr::slice(
            tibble::tibble(value = byte_date), 1:2
        )$value),
        "byte"
    )

    updated <- byte_date
    updated[1] <- as.Date(-3553, origin = "1970-01-01")
    expect_identical(dta_storage_type(updated), "byte")
    expect_identical(as.double(updated[[1]]), -3553)
    expect_error({
        updated[1] <- as.Date(-3552, origin = "1970-01-01")
    }, "dta_int\\(x\\)")
    expect_error(
        replace(
            byte_date, 1,
            structure(-3652.5, class = "Date")
        ),
        "dta_float\\(x\\)"
    )

    int_date <- read_dta(int_path)$price
    int_date[1] <- as.Date(29087, origin = "1970-01-01")
    expect_identical(dta_storage_type(int_date), "int")
    expect_identical(as.double(int_date[[1]]), 29087)
    expect_error({
        int_date[1] <- as.Date(29088, origin = "1970-01-01")
    }, "dta_long\\(x\\)")
    expect_identical(dta_storage_type(int_date[[1]] + 1), "long")
})

test_that("temporal summaries, concatenation, and recodes retain storage", {
    path <- fixture_with_temporal_storage("foreign")
    on.exit(unlink(path), add = TRUE)
    values <- read_dta(path)$foreign

    expect_identical(dta_storage_type(min(values)), "byte")
    expect_identical(dta_storage_type(mean(values)), "float")
    expect_identical(dta_storage_type(c(values, values)), "byte")
    expect_identical(dta_storage_type(rep(values, 2)), "byte")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(
        c(values, values)
    ))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(rep(values, 2)))
    expect_identical(
        dta_storage_type(vctrs::vec_c(
            values[1], as.Date(-3652, origin = "1970-01-01")
        )),
        "byte"
    )

    unlabelled <- set_var_labels(set_val_labels(values), NULL)
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

    recoded <- dtatools::recode(
        values,
        `-3653` = as.Date(-3651, origin = "1970-01-01")
    )
    expect_s3_class(recoded, "Date")
    expect_identical(dta_storage_type(recoded), "byte")
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
        "dta_int\\(x\\)"
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
    expect_null(dta_storage_type(minimum))
    expect_null(dta_storage_type(maximum))
    expect_null(dta_storage_type(interval))
})



test_that("common types follow the Stata storage promotion lattice", {
    types <- c("byte", "int", "long", "float", "double")
    constructors <- stats::setNames(
        list(dta_byte, dta_int, dta_long, dta_float, dta_double),
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
                dta_storage_type(common), expected[left, right],
                info = paste(left, right)
            )
        }
    }
})

test_that("declared storage wins over bare numeric and logical vectors", {
    prototypes <- list(double(), integer(), logical())

    for (prototype in prototypes) {
        expect_identical(
            dta_storage_type(vctrs::vec_ptype2(dta_int(), prototype)),
            "int"
        )
        expect_identical(
            dta_storage_type(vctrs::vec_ptype2(prototype, dta_int())),
            "int"
        )
    }

    combined <- vctrs::vec_c(dta_byte(c(1, 2)), 3L, TRUE)
    expect_identical(dta_storage_type(combined), "byte")
    expect_identical(as.double(combined), c(1, 2, 3, 1))
    expect_true(dtatools:::.is_numeric_altrep(combined))
})

test_that("casts into declared storage are strict and preserve missing tags", {
    input <- dta_double(c(1, NA_real_, tagged_missing("f")))
    cast <- vctrs::vec_cast(input, dta_byte())

    expect_identical(dta_storage_type(cast), "byte")
    expect_identical(as.double(cast)[1:2], c(1, NA_real_))
    expect_identical(missing_tag(cast), c(NA_character_, NA, "f"))
    expect_error(
        vctrs::vec_cast(dta_double(101), dta_byte()),
        "dta_int\\(x\\)"
    )
    expect_error(
        vctrs::vec_cast(dta_double(1.5), dta_int()),
        "dta_float\\(x\\)"
    )
    expect_identical(
        as.double(vctrs::vec_cast(dta_double(0.1), dta_float())),
        0.10000000149011612
    )
})

test_that("assignment and vctrs recodes re-encode compact storage", {
    values <- dta_byte(c(1, 2, 3, tagged_missing("a")))
    values[2] <- 10
    replaced <- replace(values, 1, 20)
    conditional <- dplyr::if_else(
        c(TRUE, FALSE, FALSE, FALSE), 30, values
    )

    for (result in list(values, replaced, conditional)) {
        expect_identical(dta_storage_type(result), "byte")
        expect_true(dtatools:::.is_numeric_altrep(result))
        expect_identical(missing_tag(result)[4], "a")
    }
    expect_identical(as.double(values)[1:3], c(1, 10, 3))
    expect_identical(as.double(replaced)[1:3], c(20, 10, 3))
    expect_identical(as.double(conditional)[1:3], c(30, 10, 3))

    expect_error({
        values[1] <- 101
    }, "dta_int\\(x\\)")
    expect_error(replace(values, 1, 101), "dta_int\\(x\\)")
    expect_error(
        dplyr::if_else(rep(TRUE, length(values)), 101, values),
        "dta_int\\(x\\)"
    )
})

test_that("base right and full merges can append native Stata keys", {
    left <- data.frame(
        id = set_var_labels(
            set_val_labels(dta_byte(c(1, 2)), One = 1),
            "Identifier"
        ),
        left_value = c("a", "b")
    )
    right <- data.frame(
        id = set_val_labels(dta_byte(c(2, 3)), Three = 3),
        right_value = c("c", "d")
    )

    right_result <- merge(left, right, by = "id", all.y = TRUE)
    full_result <- merge(left, right, by = "id", all = TRUE)

    expect_identical(as.double(right_result$id), c(2, 3))
    expect_identical(as.double(full_result$id), c(1, 2, 3))
    expect_identical(dta_storage_type(right_result$id), "byte")
    expect_identical(dta_storage_type(full_result$id), "byte")
    expect_identical(var_label(full_result$id), "Identifier")
    expect_identical(val_labels(full_result$id), c(One = 1, Three = 3))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(full_result$id))

    wider <- data.frame(
        id = set_val_labels(dta_int(c(2, 200)), TwoHundred = 200)
    )
    promoted <- merge(left, wider, by = "id", all = TRUE)
    expect_identical(as.double(promoted$id), c(1, 2, 200))
    expect_identical(dta_storage_type(promoted$id), "int")
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
    expect_identical(dta_storage_type(result$id), "int")
    expect_identical(var_label(result$id), var_label(byte_date))
    expect_identical(val_labels(result$id), val_labels(byte_date))
    expect_identical(
        as.double(result$id), sort(c(as.double(byte_date), as.double(int_date)))
    )
})

test_that("extension promotes declared inputs without weakening assignment", {
    extended <- set_val_labels(dta_byte(1), One = 1)
    extended[3] <- set_val_labels(dta_int(200), TwoHundred = 200)

    expect_identical(as.double(extended), c(1, NA, 200))
    expect_identical(dta_storage_type(extended), "int")
    expect_identical(
        val_labels(extended), c(One = 1, TwoHundred = 200)
    )

    strict <- dta_byte(1)
    expect_error({
        strict[3] <- 101
    }, "dta_int\\(x\\)")

    fractional <- dta_byte(c(1, 2))
    expect_error({
        fractional[2.5] <- dta_int(200)
    })

    named <- stats::setNames(dta_byte(1), "one")
    named["two"] <- stats::setNames(dta_int(2), "source")
    expect_identical(names(named), c("one", "two"))
    expect_identical(dta_storage_type(named), "int")
})

test_that("dplyr joins preserve compatible Stata key information", {
    left_key <- set_var_labels(
        set_val_labels(dta_byte(c(1, 2)), One = 1),
        "Identifier"
    )
    right_key <- set_val_labels(
        dta_int(c(2, 200)), TwoHundred = 200
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
    expect_identical(dta_storage_type(coalesced$id), "int")
    expect_identical(var_label(coalesced$id), "Identifier")
    expect_identical(
        val_labels(coalesced$id), c(One = 1, TwoHundred = 200)
    )
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(coalesced$id))
    expect_identical(dta_storage_type(retained$id.x), "byte")
    expect_identical(dta_storage_type(retained$id.y), "int")
    expect_identical(val_labels(retained$id.x), c(One = 1))
    expect_identical(val_labels(retained$id.y), c(TwoHundred = 200))
})

test_that("value labels compose with declared storage classes", {
    values <- dta_byte(c(0, 1))
    values <- set_val_labels(values, No = 0, Yes = 1)

    expect_s3_class(values, "haven_labelled")
    expect_identical(dta_storage_type(values), "byte")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(values))

    values[1] <- 1
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(values))

    values <- set_val_labels(values)
    expect_false(inherits(values, "haven_labelled"))
    expect_s3_class(values, "stata_numeric")
    expect_identical(dta_storage_type(values), "byte")
})

test_that("common types reconcile value and variable labels", {
    left <- set_var_labels(
        set_val_labels(dta_byte(c(1, 2)), One = 1),
        "Left variable"
    )
    right <- set_var_labels(
        set_val_labels(dta_int(c(2, 3)), Three = 3),
        "Right variable"
    )
    unlabelled <- dta_byte(c(2, 3))
    variable_only <- set_var_labels(
        dta_byte(c(1, 2)), "Only variable"
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

    conflict <- set_val_labels(dta_byte(1), Uno = 1)
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

test_that("common types reconcile notes and characteristics left first", {
    left <- set_stata_note(dta_byte(c(1, 2)), 3, "left note")
    left <- set_stata_characteristic(left, "source", "master")
    right <- set_stata_note(dta_int(c(3, 4)), 7, "right note")
    right <- set_stata_characteristic(right, "source", "using")
    bare <- dta_byte(c(5, 6))

    left_right <- vctrs::vec_c(left, right)
    right_left <- vctrs::vec_c(right, left)
    fallback <- vctrs::vec_c(bare, right)

    expect_identical(dta_notes(left_right), c(`3` = "left note"))
    expect_identical(dta_characteristics(left_right), c(source = "master"))
    expect_identical(dta_notes(right_left), c(`7` = "right note"))
    expect_identical(dta_characteristics(right_left), c(source = "using"))
    expect_identical(dta_notes(fallback), c(`7` = "right note"))
    expect_identical(dta_characteristics(fallback), c(source = "using"))
})

test_that("arithmetic promotes from operand storage according to result values", {
    cases <- list(
        byte_stays_byte = list(dta_byte(c(1, 2)) + 1, "byte", c(2, 3)),
        byte_overflow = list(dta_byte(100) + 1, "int", 101),
        int_overflow = list(dta_int(32740) + 1, "long", 32741),
        int_fraction = list(dta_int(1) / 2, "float", 0.5),
        long_fraction = list(dta_long(1) / 2, "double", 0.5),
        float_stays_float = list(dta_float(1) / 2, "float", 0.5),
        long_float_meet = list(
            dta_long(1) + dta_float(2), "double", 3
        ),
        unary_overflow = list(-dta_byte(-127), "int", 127)
    )

    for (name in names(cases)) {
        result <- cases[[name]][[1L]]
        expect_identical(
            dta_storage_type(result), cases[[name]][[2L]], info = name
        )
        expect_identical(
            as.double(result), cases[[name]][[3L]], info = name
        )
    }
})

test_that("arithmetic collapses tags and returns bare logical comparisons", {
    values <- dta_int(c(1, tagged_missing("a"), NA_real_))
    result <- values + 1

    expect_identical(dta_storage_type(result), "int")
    expect_identical(as.double(result)[1], 2)
    expect_identical(is.na(result), c(FALSE, TRUE, TRUE))
    expect_identical(missing_tag(result), c(NA_character_, NA, NA))
    expect_identical(values == 1, c(TRUE, FALSE, FALSE))
    expect_null(dta_storage_type(values == 1))
    expect_identical(!dta_int(c(0, 1, NA_real_)), c(TRUE, FALSE, NA))
})

test_that("missing operands yield system missing whatever their tag", {
    tagged <- dta_int(c(1L, tagged_missing("a")))
    expect_identical(missing_tag(tagged), c(NA_character_, "a"))

    year <- dta_int(tagged_missing("a")) - 1900
    expect_true(is_missing(year))
    expect_identical(missing_tag(year), NA_character_)

    both_tagged <- dta_double(tagged_missing("a")) +
        dta_double(tagged_missing("b"))
    expect_true(is.na(both_tagged))
    expect_identical(missing_tag(both_tagged), NA_character_)
    expect_identical(
        missing_tag(dta_double(tagged_missing("b")) + tagged_missing("a")),
        NA_character_
    )
    expect_identical(
        missing_tag(1 - dta_int(tagged_missing("a"))), NA_character_
    )

    negated <- -dta_int(c(1, tagged_missing("a")))
    expect_identical(as.double(negated), c(-1, NA_real_))
    expect_identical(missing_tag(negated), c(NA_character_, NA))

    mixed <- dta_int(c(1, tagged_missing("a"), NA_real_, 5)) * 2
    expect_identical(as.double(mixed), c(2, NA_real_, NA_real_, 10))
    expect_identical(missing_tag(mixed), rep(NA_character_, 4L))
    expect_identical(dta_storage_type(mixed), "int")

    tagged_bytes <- dta_byte(c(2, tagged_missing("a"))) * dta_byte(3)
    expect_identical(dta_storage_type(tagged_bytes), "byte")
    expect_identical(
        dta_storage_type(dta_byte(100) * dta_byte(3)), "int"
    )
    expect_identical(
        dta_storage_type(dta_int(c(1, tagged_missing("a"))) / 2),
        "float"
    )
})

test_that("rounding keeps a missing tag and other math functions drop it", {
    values <- dta_double(c(2.5, tagged_missing("a"), NA_real_))

    for (rounding in c("round", "signif", "floor", "ceiling", "trunc")) {
        rounded <- getExportedValue("base", rounding)(values)
        expect_identical(
            missing_tag(rounded), c(NA_character_, "a", NA), info = rounding
        )
    }
    expect_identical(missing_tag(round(values, 1)), c(NA_character_, "a", NA))

    for (dropping in c("sqrt", "exp", "log", "abs", "sign", "cumsum")) {
        dropped <- getExportedValue("base", dropping)(values)
        expect_identical(is.na(dropped), c(FALSE, TRUE, TRUE), info = dropping)
        expect_identical(
            missing_tag(dropped), rep(NA_character_, 3L), info = dropping
        )
    }

    for (reduction in c("sum", "mean", "min", "max")) {
        reduced <- getExportedValue("base", reduction)(values)
        expect_true(is.na(reduced), info = reduction)
        expect_identical(missing_tag(reduced), NA_character_, info = reduction)
        expect_false(
            is.na(getExportedValue("base", reduction)(values, na.rm = TRUE)),
            info = reduction
        )
    }
})

test_that("computed results preserve Stata construction semantics", {
    constructors <- list(
        byte = dta_byte,
        int = dta_int,
        long = dta_long,
        float = dta_float
    )
    input <- setNames(
        c(1, NA_real_, tagged_missing("a"), tagged_missing("z")),
        letters[1:4]
    )

    for (storage in names(constructors)) {
        source <- constructors[[storage]](input)
        result <- source + 0

        expect_identical(dta_storage_type(result), storage, info = storage)
        expect_identical(names(result), names(input), info = storage)
        expect_identical(
            as.double(result)[1], as.double(source)[1], info = storage
        )
        expect_identical(is.na(result), is.na(source), info = storage)
        expect_identical(
            unname(missing_tag(result)), rep(NA_character_, 4L),
            info = storage
        )
        expect_true(
            dtatools:::.is_unmaterialized_numeric_altrep(result),
            info = storage
        )
    }

    promoted <- dta_int(c(32740, 1)) / 2
    expect_identical(dta_storage_type(promoted), "float")
    expect_identical(as.double(promoted), c(16370, 0.5))
    expect_identical(
        as.double(dta_int(c(1, -1)) / 0), c(NA_real_, NA_real_)
    )
})

test_that("Complex group members use value-dependent storage", {
    argument <- Arg(dta_int(-1))
    modulus <- Mod(dta_int(-32767))

    expect_identical(dta_storage_type(argument), "float")
    expect_equal(as.double(argument), pi, tolerance = 1e-6)
    expect_identical(dta_storage_type(modulus), "long")
    expect_identical(as.double(modulus), 32767)
    expect_identical(dta_storage_type(Re(dta_byte(2))), "byte")
    expect_identical(dta_storage_type(Im(dta_byte(2))), "byte")
    expect_identical(dta_storage_type(Conj(dta_byte(2))), "byte")
})

test_that("math and summary generics use value-dependent storage", {
    absolute <- abs(dta_byte(c(-127, 1)))
    exact_root <- sqrt(dta_int(c(4, 9)))
    rounded_root <- sqrt(dta_int(c(2, 4)))
    total <- sum(dta_byte(c(100, 100)))
    average <- mean(dta_int(c(1, 2)))
    cumulative <- cumsum(dta_byte(c(50, 50, 50)))

    expect_identical(dta_storage_type(absolute), "int")
    expect_identical(as.double(absolute), c(127, 1))
    expect_identical(dta_storage_type(exact_root), "int")
    expect_identical(as.double(exact_root), c(2, 3))
    expect_identical(dta_storage_type(rounded_root), "float")
    expect_identical(
        as.double(rounded_root), c(1.4142135381698608, 2)
    )
    expect_identical(dta_storage_type(total), "int")
    expect_identical(as.double(total), 200)
    expect_identical(dta_storage_type(average), "float")
    expect_identical(as.double(average), 1.5)
    expect_identical(dta_storage_type(cumulative), "int")
    expect_identical(as.double(cumulative), c(50, 100, 150))
    expect_identical(is.finite(dta_float(c(1, NA_real_))), c(TRUE, FALSE))
})

test_that("Summary generics accept bare numeric and logical arguments", {
    total <- sum(dta_byte(1), 2)
    extremes <- range(dta_byte(1), 101)

    expect_identical(dta_storage_type(total), "byte")
    expect_identical(as.double(total), 3)
    expect_identical(dta_storage_type(extremes), "int")
    expect_identical(as.double(extremes), c(1, 101))
    expect_identical(all(dta_byte(1), TRUE), TRUE)
    expect_identical(any(dta_byte(0), TRUE), TRUE)
})

test_that("base ifelse strips declared storage as documented", {
    result <- ifelse(c(TRUE, FALSE), dta_byte(c(1, 2)), 0)

    expect_null(dta_storage_type(result))
    expect_identical(result, c(1, 0))
})

test_that("undefined Stata arithmetic becomes system missing", {
    divided <- dta_int(1) / 0
    rooted <- sqrt(dta_int(-1))

    expect_identical(dta_storage_type(divided), "int")
    expect_identical(as.double(divided), NA_real_)
    expect_identical(dta_storage_type(rooted), "int")
    expect_identical(as.double(rooted), NA_real_)
})
