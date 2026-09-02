test_that("the accessors keep their vector and whole-data-frame shapes", {
    status <- c(1, 2, 1)
    var_label(status) <- "Interview status"
    val_labels(status) <- c(Complete = 1, Refused = 2)

    expect_identical(var_label(status), "Interview status")
    expect_identical(val_labels(status), c(Complete = 1, Refused = 2))

    survey <- data.frame(status = status, stratum = c(1, 1, 2))
    expect_identical(
        var_label(survey),
        list(status = "Interview status", stratum = NULL)
    )
    expect_identical(
        val_labels(survey),
        list(status = c(Complete = 1, Refused = 2), stratum = NULL)
    )
})

test_that("the accessors read one column in the (data, variable) shape", {
    status <- c(1, 2, 1)
    var_label(status) <- "Interview status"
    val_labels(status) <- c(Complete = 1, Refused = 2)
    survey <- data.frame(status = status, stratum = c(1, 1, 2))
    status_name <- paste0("sta", "tus")

    expect_identical(var_label(survey, status), "Interview status")
    expect_identical(var_label(survey, "status"), "Interview status")
    expect_identical(var_label(survey, !!status_name), "Interview status")
    expect_identical(var_label(survey, .(status_name)), "Interview status")
    expect_null(var_label(survey, stratum))

    codes <- c(Complete = 1, Refused = 2)
    expect_identical(val_labels(survey, status), codes)
    expect_identical(val_labels(survey, "status"), codes)
    expect_identical(val_labels(survey, !!status_name), codes)
    expect_identical(val_labels(survey, .(status_name)), codes)
    expect_null(val_labels(survey, stratum))
})

test_that("a symbol names the column literally, not a caller variable", {
    survey <- data.frame(status = c(1, 2), stratum = c(1, 1))
    var_label(survey) <- list(status = "Interview status")
    status <- "stratum"

    expect_identical(var_label(survey, status), "Interview status")
    expect_null(var_label(survey, !!status))
})

test_that("asking for an absent column names it in the error", {
    survey <- data.frame(status = c(1, 2))
    expect_error(
        var_label(survey, absent), "Column `absent` does not exist"
    )
    expect_error(
        val_labels(survey, "absent"), "Column `absent` does not exist"
    )
})

test_that("a variable argument requires a data frame", {
    status <- c(1, 2, 1)
    expect_error(
        var_label(status, status),
        "must be a data frame when `variable` is supplied"
    )
    expect_error(
        val_labels(status, status),
        "must be a data frame when `variable` is supplied"
    )
})

test_that("set_var_label accepts a bare vector and a label", {
    status <- c(1, 2, 1)
    status <- set_var_label(status, "Interview status")
    expect_identical(var_label(status), "Interview status")

    status <- set_var_label(status, NULL)
    expect_null(var_label(status))
})

test_that("set_var_label still rejects other non-data-frame calls", {
    status <- c(1, 2, 1)
    expect_error(set_var_label(status), "`data` must be a data frame")
    expect_error(
        set_var_label(status, status, "Interview status"),
        "`data` must be a data frame"
    )
})

test_that("set_var_labels accepts the positional (data, variable) shape", {
    survey <- data.frame(status = c(1, 2), stratum = c(1, 1))
    status_name <- paste0("sta", "tus")

    set_var_labels(survey, status, "Interview status")
    expect_identical(var_label(survey, status), "Interview status")
    set_var_labels(survey, "status", "By string")
    expect_identical(var_label(survey, status), "By string")
    set_var_labels(survey, !!status_name, "By bang bang")
    expect_identical(var_label(survey, status), "By bang bang")
    set_var_labels(survey, .(status_name), "By dot call")
    expect_identical(var_label(survey, status), "By dot call")

    expect_null(var_label(survey, stratum))
})

test_that("set_val_labels accepts the positional (data, variable) shape", {
    survey <- data.frame(status = c(1, 2), stratum = c(1, 1))
    status_name <- paste0("sta", "tus")
    codes <- c(yes = 1, no = 2)

    set_val_labels(survey, status, codes)
    expect_identical(val_labels(survey, status), codes)
    set_val_labels(survey, "status", c(maybe = 3))
    expect_identical(val_labels(survey, status), c(maybe = 3))

    # The exact call from issue #133.
    set_val_labels(survey, !!status_name, c(yes = 1))
    expect_identical(val_labels(survey, status), c(yes = 1))

    set_val_labels(survey, .(status_name), codes)
    expect_identical(val_labels(survey, status), codes)

    expect_null(val_labels(survey, stratum))
})

test_that("the positional labels argument evaluates in the caller", {
    survey <- data.frame(status = c(1, 2))
    status <- c(yes = 1, no = 2)

    # `status` on the right is the caller's vector, not the column.
    set_val_labels(survey, status, status)
    expect_identical(val_labels(survey, status), c(yes = 1, no = 2))
})

test_that("every pre-existing setter convention still works", {
    survey <- data.frame(status = c(1, 2), stratum = c(1, 1))
    stratum_name <- "stratum"

    # Tagged dots.
    set_var_labels(survey, status = "Interview status")
    expect_identical(var_label(survey, status), "Interview status")
    set_val_labels(survey, status = c(yes = 1))
    expect_identical(val_labels(survey, status), c(yes = 1))

    # `!!name :=` and `.(name) :=` tags.
    set_var_labels(survey, !!stratum_name := "Sampling stratum")
    expect_identical(var_label(survey, stratum), "Sampling stratum")
    set_var_labels(survey, .(stratum_name) := "Stratum again")
    expect_identical(var_label(survey, stratum), "Stratum again")
    set_val_labels(survey, !!stratum_name := c(urban = 1))
    expect_identical(val_labels(survey, stratum), c(urban = 1))
    set_val_labels(survey, .(stratum_name) := c(rural = 2))
    expect_identical(val_labels(survey, stratum), c(rural = 2))

    # `.labels`, alone and combined with tagged dots.
    set_var_labels(survey, .labels = list(status = "From .labels"))
    expect_identical(var_label(survey, status), "From .labels")
    set_var_labels(
        survey, status = "Tagged",
        .labels = list(stratum = "Listed")
    )
    expect_identical(var_label(survey, status), "Tagged")
    expect_identical(var_label(survey, stratum), "Listed")
    set_val_labels(survey, .labels = list(status = c(no = 2)))
    expect_identical(val_labels(survey, status), c(no = 2))

    # The vector branch.
    status <- c(1, 2)
    status <- set_var_labels(status, "Vector label")
    expect_identical(var_label(status), "Vector label")
    status <- set_val_labels(status, yes = 1, no = 2)
    expect_identical(val_labels(status), c(yes = 1, no = 2))
})

test_that("dots forwarded from a wrapper keep the tagged path", {
    survey <- data.frame(status = c(1, 2))
    label_through_wrapper <- function(data, ...) {
        set_var_labels(data, ...)
    }
    label_through_wrapper(survey, status = "Forwarded")
    expect_identical(var_label(survey, status), "Forwarded")
})

test_that("dots forwarded from a wrapper keep the positional shape", {
    survey <- data.frame(status = c(1, 2))
    codes_through_wrapper <- function(data, ...) {
        set_val_labels(data, ...)
    }
    codes_through_wrapper(survey, "status", c(yes = 1))
    expect_identical(val_labels(survey, status), c(yes = 1))
})

test_that("a computed first argument still errors as before", {
    survey <- data.frame(status = c(1, 2))
    expect_error(
        set_val_labels(survey, paste0("sta", "tus"), c(yes = 1)),
        "must have one non-empty name per update"
    )
    expect_error(
        set_var_labels(survey, paste0("sta", "tus"), "Interview status"),
        "must have one non-empty name per update"
    )
    expect_null(val_labels(survey, status))
    expect_null(var_label(survey, status))
})

test_that("the positional shape validates the column and the labels", {
    survey <- data.frame(status = c(1, 2))
    expect_error(
        set_var_labels(survey, absent, "Nope"), "Unknown column: absent"
    )
    expect_error(
        set_val_labels(survey, status, c(1, 2)),
        "must name every value-label code"
    )
})
