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

test_that("restoration matches attribute names as the set operations would", {
    variables <- .dta_variable_attribute_names
    known <- c("names", "class", variables)
    source <- structure(c(1, 2), zeta = 1, format.stata = "%9.0g",
        class = c("dta_numeric", "dta_double", "vctrs_vctr", "double"),
        alpha = 2, notes = "n", stata.storage = "double", label = "L",
        names = c("a", "b"))
    attributes_seen <- attributes(source)
    message <- sprintf(
        "Dropped unknown attributes during Stata vector restoration: %s",
        paste(setdiff(names(attributes_seen), known), collapse = ", ")
    )
    warnings <- character()
    collect <- function(expr) withCallingHandlers(expr, warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
    })

    planned <- collect(.dta_attribute_plan(source, "double", c("x", "y")))
    expected <- attributes_seen[intersect(names(attributes_seen), variables)]
    expected$stata.storage <- "double"
    expected$class <- class(source)
    expected$names <- c("x", "y")
    expect_identical(planned, expected)
    expect_identical(warnings, message)

    warnings <- character()
    value <- dta_double(c(3, 4))
    restored <- collect(.restore_dta_variable_metadata(value, source, names = NULL))
    for (name in intersect(names(attributes_seen), variables)) {
        attr(value, name) <- attributes_seen[[name]]
    }
    expect_identical(attributes(restored), attributes(value))
    expect_identical(warnings, message)

    bare <- dta_double(c(3, 4))
    expect_identical(.restore_dta_variable_metadata(bare, c(1, 2), names = NULL), bare)
})

native_restore <- function(value, prototype, storage) {
    .Call(C_dtatools_restore_numeric_metadata, value, prototype, storage,
          .dta_variable_attribute_names, .dta_storage)
}

test_that("native restoration builds the R plan's attributes in its order", {
    by_plan <- function(value, prototype, storage) {
        .replace_dta_attributes(value, .dta_attribute_plan(
            prototype, storage, result_names = names(value), temporal = FALSE
        ))
    }
    labelled <- dta_byte(c(1, 2, NA, 2))
    val_labels(labelled) <- c(yes = 1, no = 2)
    var_label(labelled) <- "Answer"
    attr(labelled, "format.stata") <- "%8.0g"
    named <- dta_int(c(1, 300))
    names(named) <- c("a", "b")
    # Variable attributes on either side of the class, and a storage class
    # in the middle of the class vector.
    reordered <- structure(c(1, 2), label = "L",
        class = c("custom", "dta_numeric", "dta_double", "vctrs_vctr", "double"),
        format.stata = "%9.0g", stata.storage = "double")
    unstored <- reordered
    attr(unstored, "stata.storage") <- NULL
    cases <- list(
        list(vctrs::vec_slice(vctrs::vec_proxy(labelled), c(2L, 1L)), labelled, "byte"),
        list(vctrs::vec_slice(vctrs::vec_proxy(labelled), integer()), labelled, "byte"),
        list(vctrs::vec_proxy(labelled), labelled, "int"),
        list(vctrs::vec_slice(vctrs::vec_proxy(named), 2L), named, "int"),
        list(c(3, 4), reordered, "double"),
        list(c(3, 4), reordered, "float"),
        list(c(3, 4), unstored, "long"),
        list(dta_long(c(5, 6)), labelled, "long")
    )
    for (case in cases) {
        restored <- do.call(native_restore, case)
        expect_false(is.null(restored))
        expected <- do.call(by_plan, case)
        expect_identical(names(attributes(restored)), names(attributes(expected)))
        expect_identical(serialize(restored, NULL), serialize(expected, NULL))
        expect_identical(do.call(.restore_dta_metadata, case), expected)
    }
    expect_identical(names(attributes(native_restore(c(3, 4), unstored, "long"))),
                     c("label", "format.stata", "stata.storage", "class"))
    expect_identical(class(native_restore(c(3, 4), reordered, "float")),
        c("custom", "dta_numeric", "dta_float", "vctrs_vctr", "double"))
})

test_that("native restoration returns a value that already has its storage and classes", {
    value <- dta_byte(c(1, 2))
    expect_identical(native_restore(value, value, "byte"), value)
    # A plain attribute to set sends it through the copy instead.
    labelled <- value
    var_label(labelled) <- "Label"
    restored <- native_restore(value, labelled, "byte")
    expect_identical(var_label(restored), "Label")
    expect_null(var_label(value))
})

test_that("native restoration declines what the R code handles itself", {
    plain <- dta_double(c(1, 2))
    unknown <- plain
    attr(unknown, "mystery") <- TRUE
    expect_null(native_restore(c(1, 2), unknown, "double"))
    expect_warning(.restore_dta_metadata(c(1, 2), unknown, "double"),
                   "Dropped unknown attribute during Stata vector restoration: mystery",
                   fixed = TRUE)
    for (storage in list("strL", NA_character_, c("double", "double"), 1,
                         structure("double", note = TRUE))) {
        expect_null(native_restore(c(1, 2), plain, storage))
    }
    no_storage_class <- structure(c(1, 2), stata.storage = "double",
        class = c("dta_numeric", "vctrs_vctr", "double"))
    expect_null(native_restore(c(1, 2), no_storage_class, "double"))
    expect_identical(class(.restore_dta_metadata(c(1, 2), no_storage_class, "double")),
                     .dta_storage_class("double"))
    named_classes <- plain
    attr(named_classes, "class") <- structure(class(plain), names = letters[1:4])
    expect_null(native_restore(c(1, 2), named_classes, "double"))
    expect_null(native_restore(c(1, 2), structure(c(1, 2), stata.storage = "double"), "double"))
    expect_null(native_restore(structure(c(1, 2), class = "data.table"), plain, "double"))
    s4_classes <- plain
    attr(s4_classes, "class") <- asS4(class(plain))
    expect_null(native_restore(c(1, 2), s4_classes, "double"))
    expect_true(isS4(class(.restore_dta_metadata(c(1, 2), s4_classes, "double"))))
    # Reading an ALTREP vector can run R code between the native reads.
    callback_classes <- plain
    attr(callback_classes, "class") <- .Call(C_dtatools_callback_character,
                                             class(plain), function() NULL)
    expect_null(native_restore(c(1, 2), callback_classes, "double"))
    expect_null(native_restore(c(1, 2), plain, .Call(C_dtatools_callback_character,
                                                     "double", function() NULL)))
})

test_that("restoration reads the value's names once, after the R code's warnings", {
    calls <- 0L
    warned <- FALSE
    table <- get(".__S3MethodsTable__.", envir = baseenv())
    registerS3method("names", "dtatools_counted_names", function(x) {
        calls <<- calls + 1L
        if (warned) c("a", "b")
    }, envir = baseenv())
    withr::defer(rm(list = "names.dtatools_counted_names", envir = table))
    unknown <- dta_double(c(1, 2))
    attr(unknown, "mystery") <- TRUE
    value <- structure(c(1, 2), class = "dtatools_counted_names")
    restored <- withCallingHandlers(
        .restore_dta_metadata(value, unknown, "double"),
        warning = function(condition) {
            warned <<- TRUE
            invokeRestart("muffleWarning")
        })
    expect_true(warned)
    expect_identical(calls, 1L)
    expect_identical(attr(restored, "names"), c("a", "b"))

    # The native call reads them once too.
    calls <- 0L
    restored <- .restore_dta_metadata(value, dta_double(c(1, 2)), "double")
    expect_identical(calls, 1L)
    expect_identical(attr(restored, "names"), c("a", "b"))
    expect_identical(class(restored), .dta_storage_class("double"))
})
