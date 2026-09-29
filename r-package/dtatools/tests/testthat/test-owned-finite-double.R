test_that("scalar arithmetic certifies only its exact untouched double backing", {
    skip_if_not(.dtatools_numeric_entry_expected())
    withr::local_options(dtatools.generate_type = "double")
    n <- 32769L
    input <- rep(c(1, 2, 3, 4), length.out = n)
    native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
    produce <- function() {
        data <- as_dibble(tibble::as_tibble(list(x = input, g = rep(1, n))))
        invisible(native("C_dtatools_patch_slot", data, 1L, NULL, input, TRUE))
        sink <- new.env(parent = emptyenv())
        before <- native("C_dtatools_numeric_entry_stats", FALSE)[["scalar"]]
        condition <- tryCatch(gen(data, y = {
            value <- x + 1
            sink$value <- value
            stop("captured before publication", call. = FALSE)
        }), error = identity)
        expect_identical(conditionMessage(condition), "captured before publication")
        list(value = sink$value,
             successes = native("C_dtatools_numeric_entry_stats", FALSE)[["scalar"]] - before)
    }

    invisible(produce()) # Settle one-time native helper qualification.
    produced <- produce()
    expect_identical(produced$successes, 1)
    value <- produced$value
    info <- native("C_dtatools_owned_info", value)
    expect_true(info$finite_double)
    expect_false(info$shared)
    expect_false(info$exposed)
    expect_identical(native("C_dtatools_replacement_fits", value, NULL, FALSE, 4L), TRUE)

    fork <- native("C_dtatools_capture_column", value)
    expect_true(native("C_dtatools_owned_info", fork)$finite_double)
    expect_identical(native("C_dtatools_owned_info", value)$backing,
                     native("C_dtatools_owned_info", fork)$backing)
    pointer <- native("C_dtatools_owned_pointer", value, TRUE)
    expect_false(native("C_dtatools_owned_info", value)$finite_double)
    expect_true(native("C_dtatools_owned_info", fork)$finite_double)
    native("C_dtatools_owned_pointer_write", pointer, 16385L, Inf)
    expect_identical(native("C_dtatools_replacement_fits", value, NULL, FALSE, 4L), FALSE)
    expect_identical(native("C_dtatools_replacement_fits", fork, NULL, FALSE, 4L), TRUE)

    value <- produce()$value
    subset <- native("C_dtatools_owned_subset", value, c(1L, 2L))
    expect_false(native("C_dtatools_owned_info", subset)$finite_double)
    expect_true(native("C_dtatools_owned_info", value)$finite_double)
    native("C_dtatools_patch_vector", value, 16385L, Inf)
    expect_false(native("C_dtatools_owned_info", value)$finite_double)
    expect_identical(native("C_dtatools_replacement_fits", value, NULL, FALSE, 4L), FALSE)

    value <- produce()$value
    target <- dibble(x = dta_double(rep(9, n)))
    invisible(native("C_dtatools_patch_slot", target, 1L, NULL, value, FALSE))
    expect_identical(as.double(target[["x"]]), input + 1)
    expect_true(native("C_dtatools_owned_info", value)$finite_double)
})
