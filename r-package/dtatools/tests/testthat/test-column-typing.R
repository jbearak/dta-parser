typed <- function(value, caller = "as_dibble()") {
    dtatools:::.typed_column(value, length(value), caller)
}

promoted <- function(values, prior, declared = NULL) {
    dtatools:::.promoted_column(values, prior, length(values), "`:=`", declared)
}

same_object <- function(x, y) {
    identical(rlang::obj_address(x), rlang::obj_address(y))
}

test_that("the container mapping types a value with no prior column", {
    # ADR 0021: one mapping wherever a column enters a dibble.
    # A typed string carries its declaration as an attribute, without
    # the `dta_string` class, and a logical stays a bare logical.
    cases <- list(
        list(value = c(TRUE, NA), storage = NULL, class = "logical"),
        list(value = c(1L, NA), storage = "long", class = "dta_long"),
        list(value = c(1.5, NA), storage = "double", class = "dta_double"),
        list(value = as.Date(c("2020-01-01", NA)), storage = "float",
             class = "dta_date"),
        list(value = as.POSIXct("2020-01-01 12:00:00", tz = "UTC"),
             storage = "double", class = "dta_datetime"),
        list(value = c("ab", "abc"), storage = "str3", class = "character"),
        list(value = c("", NA), storage = "str1", class = "character"),
        list(value = strrep("a", 2046), storage = "strL", class = "character")
    )
    for (case in cases) {
        result <- typed(case$value)
        expect_identical(dta_storage_type(result), case$storage,
                         info = paste(class(case$value), collapse = "/"))
        expect_true(inherits(result, case$class))
        expect_true(dtatools:::.dta_typed_column(result))
    }
    expect_identical(as.character(typed(c("", NA))), c("", ""))
    # A typed value is the same vector, and a factor stays a factor.
    for (value in list(dta_byte(c(1, 2)), dta_string(c("a", "b")),
                       factor(c("a", "b")), dta_int(c(1, 2)) * 2)) {
        expect_true(same_object(typed(value), value))
    }
    # A column no Stata storage can hold passes through unchanged.
    for (value in list(as.raw(1:2), list(1, 2), matrix(1:4, 2),
                       as.difftime(c(1, 2), units = "secs"),
                       structure(c("a", "b"), class = "foreign_character"),
                       complex(real = 1:2, imaginary = 0))) {
        expect_true(same_object(typed(value), value))
    }
    skip_if_not_installed("bit64")
    big <- bit64::as.integer64(c(1, 2))
    expect_true(same_object(typed(big), big))
})

test_that("a stale string declaration is retyped from the values", {
    stale <- structure(c("long", NA_character_), stata.string.storage = "str2",
                       label = "Kept")
    result <- typed(stale)
    expect_true(dtatools:::.dta_typed_column(result))
    expect_identical(as.character(result), c("long", ""))
    expect_identical(dta_storage_type(result), "str4")
    expect_identical(attr(result, "label"), "Kept")
    # A `dta_string` an operation padded with `NA` behind its class.
    padded <- structure(c("a", "b", NA), stata.string.storage = "str1",
                        class = c("dta_string", "vctrs_vctr", "character"))
    expect_false(dtatools:::.string_declaration_holds(padded))
    expect_identical(as.character(typed(padded)), c("a", "b", ""))
    expect_identical(dta_storage_type(typed(padded)), "str1")
})

test_that("compact reader columns stay compact through typing", {
    data <- read_dta(fixture("auto_v118.dta"))
    for (name in c("price", "make")) {
        column <- data[[name]]
        expect_true(same_object(typed(column), column))
    }
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(typed(data$price)))
})

test_that("promotion widens to the narrowest storage that holds the values", {
    # CONTEXT.md "Storage promotion"; ADR 0024. `from` is the prior's
    # storage, `values` the whole new column, `to` the promoted storage.
    ladder <- list(
        list(from = "byte", values = c(1, 100), to = "byte"),
        list(from = "byte", values = c(1, 200), to = "int"),
        list(from = "byte", values = c(1, 40000), to = "long"),
        list(from = "byte", values = c(1, 0.5), to = "float"),
        list(from = "byte", values = c(1, 0.1), to = "double"),
        list(from = "int", values = c(1, 40000), to = "long"),
        list(from = "int", values = c(1, 3e9), to = "float"),
        list(from = "int", values = c(1, 3000000001), to = "double"),
        list(from = "long", values = c(1, 3e9), to = "double"),
        list(from = "long", values = c(1, 0.5), to = "double"),
        list(from = "float", values = c(1, 16777216), to = "float"),
        list(from = "float", values = c(1, 16777217), to = "double"),
        list(from = "float", values = c(1, NA), to = "float"),
        list(from = "double", values = c(1, 2), to = "double")
    )
    for (step in ladder) {
        prior <- get(paste0("dta_", step$from))(c(1, 2))
        result <- promoted(step$values, prior)
        expect_identical(dta_storage_type(result), step$to,
                         info = sprintf("%s <- %s", step$from,
                                        paste(step$values, collapse = ",")))
        expect_identical(as.double(result), step$values)
    }
})

test_that("promotion keeps a fitting storage and the prior's metadata", {
    prior <- dta_byte(c(1, 2))
    attr(prior, "label") <- "A label"
    attr(prior, "format.stata") <- "%8.0g"
    kept <- promoted(c(3, 4), prior)
    expect_identical(dta_storage_type(kept), "byte")
    expect_identical(attr(kept, "label"), "A label")
    widened <- promoted(c(3, 400), prior)
    expect_identical(dta_storage_type(widened), "int")
    expect_identical(attr(widened, "label"), "A label")
    expect_identical(attr(widened, "format.stata"), "%8.0g")
    # Strings widen and never narrow, and carry their metadata too.
    text <- dta_string(c("abc", "de"), "str8")
    attr(text, "label") <- "Text"
    expect_identical(dta_storage_type(promoted(c("a", "b"), text)), "str8")
    wider <- promoted(c("abcdefghij", NA), text)
    expect_identical(dta_storage_type(wider), "str10")
    expect_identical(as.character(wider), c("abcdefghij", ""))
    expect_identical(attr(wider, "label"), "Text")
})

test_that("promotion's other rules: logicals, declared storage, kind changes", {
    prior <- dta_byte(c(1, 2))
    # A bare logical over a numeric keeps the column's storage.
    flags <- promoted(c(TRUE, FALSE), prior)
    expect_identical(dta_storage_type(flags), "byte")
    expect_identical(as.double(flags), c(1, 0))
    # A value that declares its storage keeps it; an untypable one passes.
    expect_identical(dta_storage_type(promoted(dta_double(c(1, 2)), prior)),
                     "double")
    raw_values <- as.raw(1:2)
    expect_true(same_object(promoted(raw_values, prior), raw_values))
    # `declared` names storage the caller settled on, and only widens.
    expect_identical(dta_storage_type(promoted(c(1, 2), prior, "long")), "long")
    expect_identical(dta_storage_type(promoted(c(1, 3000000001), prior, "int")),
                     "double")
    # A change of kind, or a temporal or factor prior, types afresh.
    expect_identical(dta_storage_type(promoted(c("a", "bb"), prior)), "str2")
    expect_identical(dta_storage_type(promoted(c(1, 2), dta_string(c("a", "b")))),
                     "double")
    dates <- typed(as.Date(c("2020-01-01", "2020-01-02")))
    expect_identical(dta_storage_type(promoted(c(1.5, 2), dates)), "double")
    expect_identical(dta_storage_type(promoted(c(1L, 2L), factor(c("a", "b")))),
                     "long")
})

test_that("the dispatcher types a fresh column and promotes a replaced one", {
    fresh <- dtatools:::.retyped_column(c(1L, 2L), NULL, 2L, "mutate()")
    expect_identical(dta_storage_type(fresh), "long")
    replaced <- dtatools:::.retyped_column(c(1, 300), dta_byte(c(1, 2)), 2L,
                                           "mutate()")
    expect_identical(dta_storage_type(replaced), "int")
})

test_that("Stata string text and the declaration accessor are one rule each", {
    plain <- c("a", "b")
    expect_true(same_object(dtatools:::.stata_string_text(plain), plain))
    expect_identical(dtatools:::.stata_string_text(c("a", NA)), c("a", ""))
    expect_identical(dtatools:::.stata_string_text(dta_string(c("a", "b"))),
                     c("a", "b"))
    expect_identical(dtatools:::.declared_string_storage(dta_string("ab")),
                     "str2")
    expect_null(dtatools:::.declared_string_storage("ab"))
    expect_null(dtatools:::.declared_string_storage(dta_byte(1)))
})

test_that("the one-pass string check answers missing, width, and encoding", {
    fits <- function(x, width, bytes = TRUE) {
        .Call(dtatools:::C_dtatools_string_fits, x, width, bytes)
    }
    expect_true(fits(c("ab", "c"), 2))
    expect_false(fits(c("ab", "c"), 1))
    expect_false(fits(c("ab", NA), 2))
    expect_true(fits(character(), 1))
    expect_true(fits("\u00e9", 2))
    expect_false(fits("\u00e9", 1))
    latin <- iconv("\u00e9", from = "UTF-8", to = "latin1")
    Encoding(latin) <- "latin1"
    expect_true(fits(latin, 2))
    expect_false(fits(latin, 1))
    bytes <- rawToChar(as.raw(255L))
    Encoding(bytes) <- "bytes"
    expect_true(fits(bytes, 1))
    expect_false(fits(bytes, 1, bytes = FALSE))
    expect_true(fits(strrep("a", 3000), Inf))
    expect_null(fits(1:2, 2))
    declared <- structure(c("ab", bytes), stata.string.storage = "str2")
    expect_true(dtatools:::.string_declaration_holds(declared))
    expect_false(dtatools:::.string_declaration_copyable(declared))
    expect_true(dtatools:::.string_declaration_copyable(
        structure(c("ab", "c"), stata.string.storage = "str2")))
})

test_that("a result column with a holding declaration is copied natively", {
    skip_if_not_installed("dplyr", "1.2.1")
    # The fast path: a plain declared character column comes back with
    # the same values and attributes, as a Stata string.
    column <- structure(c("ab", "c"), stata.string.storage = "str4",
                        label = "Keep")
    out <- dplyr::mutate(dibble(k = c(1, 2)), s = column)
    expect_identical(as.character(out$s), c("ab", "c"))
    expect_identical(attr(out$s, "stata.string.storage"), "str4")
    expect_identical(attr(out$s, "label"), "Keep")
    # A bytes-encoded value is kept out of the kernel and typed the
    # ordinary way, keeping its encoding.
    bytes <- rawToChar(as.raw(255L))
    Encoding(bytes) <- "bytes"
    declared <- structure(c("a", bytes), stata.string.storage = "str4")
    out <- dplyr::mutate(dibble(k = c(1, 2)), s = declared)
    expect_identical(Encoding(out$s), c("unknown", "bytes"))
    expect_identical(attr(out$s, "stata.string.storage"), "str4")
})
