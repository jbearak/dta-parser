test_that("canonical attribute plans preserve storage classes and result names", {
    for (storage in c("byte", "int", "long", "float", "double")) {
        source <- get(paste0("dta_", storage))(c(1, 2))
        result <- .dta_attribute_plan(source, "float", c("a", "b"), labelled = TRUE)
        expect_identical(result, list(
            stata.storage = "float",
            class = c("dta_numeric", "dta_float", "vctrs_vctr", "double"),
            names = c("a", "b")
        ))
    }
    source <- dta_double(c(1, 2))
    class(source) <- c("custom_numeric", class(source))
    expect_identical(.dta_attribute_plan(source, "int")$class,
        c("custom_numeric", "dta_numeric", "dta_int", "vctrs_vctr", "double"))
    expect_identical(.dta_attribute_plan(source, "int", temporal = TRUE)$class,
                     class(source))
})

test_that("attribute plans retain metadata order and unknown-attribute warnings", {
    source <- structure(c(1, 2), label = "Values", labels = c(one = 1),
        class = c("dta_numeric", "dta_double", "vctrs_vctr", "double"),
        stata.storage = "double", unknown = "discard")
    expect_warning(result <- .dta_attribute_plan(source, "int", labelled = TRUE),
                   "Dropped unknown attribute during Stata vector restoration: unknown",
                   fixed = TRUE)
    expect_identical(result, list(
        label = "Values", labels = c(one = 1), stata.storage = "int",
        class = c("dta_numeric", "dta_int", "haven_labelled", "vctrs_vctr", "double")
    ))
})

test_that("attribute plans do not read foreign or classed source names", {
    reads <- 0L
    foreign <- .Call(C_dtatools_callback_character, c("a", "b"), function() {
        reads <<- reads + 1L
    })
    for (value_names in list(foreign, structure(c("a", "b"), class = "custom_names"))) {
        source <- dta_double(c(1, 2))
        attr(source, "names") <- value_names
        reads <- 0L
        result <- .dta_attribute_plan(source, "double")
        expect_identical(reads, 0L)
        expect_identical(result, list(stata.storage = "double", class = class(source)))
    }
})
