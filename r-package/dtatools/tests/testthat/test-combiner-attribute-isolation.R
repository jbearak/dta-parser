.combiner_attribute_isolation_record <- function(indexed, attribute, replacement) {
    namespace <- asNamespace("dtatools")
    counter <- function(name, reset) {
        if (!exists(name, namespace, inherits = FALSE)) return(NULL)
        .Primitive(".Call")(get(name, namespace, inherits = FALSE), reset)
    }
    fixture <- function() dibble(
        x = dta_double(c(1, 2, 3, 4)), g = dta_long(c(1, 2, 1, 2)))
    operation <- if (indexed) {
        function() dplyr::mutate(fixture(), y = x + 1, .by = g)
    } else function() gen(fixture(), y = x + 1, by = g)
    values <- rep(c(1, 4), length.out = 2048L)
    source <- dta_double(values)
    numeric_operations <- list(
        construct = function() dta_double(values),
        computed = function() sqrt(source),
        scalar = function() source + 1)
    for (i in 1:3) {
        invisible(operation())
        for (numeric_operation in numeric_operations) invisible(numeric_operation())
    }
    observe_numeric <- function() lapply(numeric_operations, function(operation) {
        invisible(counter("C_dtatools_numeric_entry_stats", TRUE))
        result <- operation()
        list(counts = counter("C_dtatools_numeric_entry_stats", FALSE),
             values = as.double(result), attributes = attributes(result))
    })
    observe_combination <- function() {
        invisible(counter("C_dtatools_native_copy_stats", TRUE))
        result <- operation()
        list(result = result, counts = counter("C_dtatools_native_copy_stats", FALSE))
    }
    before <- observe_numeric()
    first <- observe_combination()
    second <- observe_combination()
    original <- attr(first$result$y, attribute, exact = TRUE)
    original_first <- paste0(original[[1L]])
    holder <- structure(list(value = original), class = "data.frame",
                        row.names = .set_row_names(length(original)))
    # A caller can retain and change a returned attribute vector by reference.
    # Restore it even on failure, since the regression exposed native profiles.
    on.exit(data.table::set(holder, i = 1L, j = "value", value = original_first), add = TRUE)
    data.table::set(holder, i = 1L, j = "value", value = replacement)
    later <- observe_combination()
    after <- observe_numeric()
    # Preserve the observations before cleanup repairs the deliberately changed
    # vector. Otherwise restoration could hide a shared attribute regression.
    unserialize(serialize(list(
        first_attribute = attr(first$result$y, attribute, exact = TRUE),
        first_counts = first$counts, second_counts = second$counts,
        second_values = tryCatch(as.double(second$result$y), error = conditionMessage),
        second_attributes = attributes(second$result$y),
        later_values = as.double(later$result$y),
        later_attributes = attributes(later$result$y),
        before = before, after = after, source = as.double(source)
    ), NULL))
}

.expect_combiner_attribute_isolation <- function(indexed) {
    classes <- c("dta_numeric", "dta_double", "vctrs_vctr", "double")
    expected_attributes <- list(stata.storage = "double", class = classes)
    native <- .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
    for (attribute in c("class", "stata.storage")) {
        replacement <- if (attribute == "class") "changed_numeric" else "byte"
        observed <- .combiner_attribute_isolation_record(
            indexed, attribute, replacement)
        expect_identical(observed$first_attribute,
                         if (attribute == "class") c(replacement, classes[-1L]) else replacement,
                         info = attribute)
        expect_identical(observed$second_values, c(2, 3, 4, 5), info = attribute)
        expect_identical(observed$second_attributes, expected_attributes, info = attribute)
        expect_identical(observed$later_values, c(2, 3, 4, 5), info = attribute)
        expect_identical(observed$later_attributes, expected_attributes, info = attribute)
        expect_identical(observed$source, rep(c(1, 4), length.out = 2048L), info = attribute)
        for (counts in list(observed$first_counts, observed$second_counts)) {
            # Main predates these fields; its public behavior is also an
            # independent oracle for this same regression file.
            if ("combine_copied_payload_bytes" %in% names(counts)) {
                expect_identical(counts[["combine_copied_payload_bytes"]],
                                 if (native) 32 else 0, info = attribute)
                expect_identical(counts[["combine_partition_r_bytes"]],
                                 if (native && indexed) 1 else 0, info = attribute)
            }
        }
        for (route in names(observed$before)) {
            expected_values <- switch(route,
                construct = rep(c(1, 4), length.out = 2048L),
                computed = rep(c(1, 2), length.out = 2048L),
                scalar = rep(c(2, 5), length.out = 2048L))
            for (record in list(observed$before[[route]], observed$after[[route]])) {
                expect_identical(record$values, expected_values, info = paste(attribute, route))
                expect_identical(record$attributes, expected_attributes, info = paste(attribute, route))
                if (!is.null(record$counts)) {
                    expected_counts <- c(construct = 0, computed = 0, scalar = 0, holds = 0)
                    if (native) expected_counts[[route]] <- 1
                    expect_identical(record$counts, expected_counts, info = paste(attribute, route))
                }
            }
        }
    }
}

test_that("grouped mutation keeps returned numeric attributes independent", {
    skip_if_not_installed("dplyr", "1.2.1")
    .expect_combiner_attribute_isolation(TRUE)
})

test_that("grouped generation keeps returned numeric attributes independent", {
    .expect_combiner_attribute_isolation(FALSE)
})
