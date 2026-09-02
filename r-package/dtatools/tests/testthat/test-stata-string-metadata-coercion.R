# read_dta() wraps a labelled or noted Stata string column in the metadata
# vector class, while a locally constructed column stays a bare
# `stata_string`. Appending ragged sources mixes the two shapes, so they
# need a common type.

metadata_wrapped_string <- function(x, storage = NULL, notes = NULL,
                                    label = NULL) {
    value <- stata_string(x, storage = storage)
    if (!is.null(label)) var_label(value) <- label
    if (!is.null(notes)) attr(value, "notes") <- notes
    dtatools:::.as_stata_metadata_vector(value)
}

test_that("a wrapped Stata string has a common type with a bare one", {
    bare <- stata_string(c("ab", "cd"), storage = "str6")
    wrapped <- metadata_wrapped_string("efgh", storage = "str4",
                                       notes = "source note")

    expect_s3_class(wrapped, "dtatools_stata_metadata_vector")
    expect_s3_class(wrapped, "stata_string")

    prototype <- vctrs::vec_ptype2(bare, wrapped)
    expect_s3_class(prototype, "stata_string")
    expect_identical(attr(prototype, "stata.string.storage"), "str6")
})

test_that("vec_c() combines wrapped and bare Stata strings either way", {
    bare <- stata_string(c("ab", "cd"), storage = "str6")
    wrapped <- metadata_wrapped_string("efgh", storage = "str4")

    forward <- vctrs::vec_c(bare, wrapped)
    expect_identical(as.character(forward), c("ab", "cd", "efgh"))
    expect_identical(attr(forward, "stata.string.storage"), "str6")

    backward <- vctrs::vec_c(wrapped, bare)
    expect_identical(as.character(backward), c("efgh", "ab", "cd"))
    expect_identical(attr(backward, "stata.string.storage"), "str6")
})

test_that("c() combines wrapped and bare Stata strings", {
    bare <- stata_string("ab", storage = "str2")
    wrapped <- metadata_wrapped_string("cdefg")

    expect_identical(
        as.character(c(bare, wrapped)), c("ab", "cdefg")
    )
    expect_identical(
        attr(c(bare, wrapped), "stata.string.storage"), "str5"
    )
})

test_that("combining keeps the variable label and dataset-level notes", {
    labelled <- metadata_wrapped_string(
        "ab", label = "contraceptive plan", notes = "from MICS"
    )
    bare <- stata_string("cde")

    combined <- vctrs::vec_c(labelled, bare)
    expect_identical(var_label(combined), "contraceptive plan")
    expect_identical(attr(combined, "notes"), "from MICS")
    expect_identical(attr(combined, "stata.string.storage"), "str3")
})

test_that("casting works in both directions", {
    wrapped <- metadata_wrapped_string("abcd", notes = "kept")
    bare <- stata_string(character(), storage = "str8")

    to_bare <- vctrs::vec_cast(wrapped, bare)
    expect_s3_class(to_bare, "stata_string")
    expect_false(inherits(to_bare, "dtatools_stata_metadata_vector"))
    expect_identical(as.character(to_bare), "abcd")

    to_wrapped <- vctrs::vec_cast(stata_string("xy"), wrapped)
    expect_s3_class(to_wrapped, "dtatools_stata_metadata_vector")
    expect_identical(attr(to_wrapped, "notes"), "kept")
})
