test_that("a runtime string names the target through `!!`", {
    data <- data.frame(income = c(10, 20))
    target_name <- paste0("adj", "usted")

    gen(data, !!target_name, income + 5)
    expect_identical(names(data), c("income", "adjusted"))
    expect_equal(as.double(data$adjusted), c(15, 25))

    repl(data, !!target_name, 0)
    expect_equal(as.double(data$adjusted), c(0, 0))

    replace_values(data, !!target_name, 1, where = income > 15)
    expect_equal(as.double(data$adjusted), c(0, 1))

    # `rlang::sym()` remains equivalent, and neither form needs `inject()`.
    repl(data, !!rlang::sym(target_name), 5)
    expect_equal(as.double(data$adjusted), c(5, 5))
})

test_that("a string literal names the target", {
    data <- data.frame(income = c(10, 20))
    gen(data, "adjusted", income + 5)
    expect_identical(names(data), c("income", "adjusted"))
    repl(data, "adjusted", 0)
    expect_equal(as.double(data$adjusted), c(0, 0))
})

test_that("an unquoted string reads as a name, not a caller variable", {
    data <- data.frame(income = c(10, 20), adjusted = c(1, 2))
    adjusted <- "income"

    repl(data, !!adjusted, 99)
    expect_equal(as.double(data$income), c(99, 99))
    expect_equal(as.double(data$adjusted), c(1, 2))
})

test_that("a column named like the caller variable is not selected", {
    data <- data.frame(target_name = c(1, 2), income = c(10, 20))
    target_name <- "income"

    repl(data, !!target_name, 7)
    expect_equal(as.double(data$income), c(7, 7))
    expect_equal(as.double(data$target_name), c(1, 2))

    # The unquoted symbol still names the column, not the caller's string.
    repl(data, target_name, 3)
    expect_equal(as.double(data$target_name), c(3, 3))
    expect_equal(as.double(data$income), c(7, 7))
})

test_that("empty, missing, and non-scalar strings are rejected", {
    data <- data.frame(income = c(10, 20))
    the_bad_names <- list(
        character(), c("income", "income"), NA_character_, ""
    )
    for (my_name in the_bad_names) {
        expect_error(
            repl(data, !!my_name, 0),
            "must be one unquoted column name or one nonempty, non-missing"
        )
        expect_error(
            gen(data, !!my_name, 0),
            "must be one unquoted column name or one nonempty, non-missing"
        )
    }
    expect_identical(names(data), "income")
})

test_that("a string target keeps the existence checks", {
    data <- data.frame(income = c(10, 20))
    expect_error(
        repl(data, !!"absent", 0), "Column `absent` does not exist"
    )
    expect_error(
        gen(data, !!"income", 0), "Column `income` already exists"
    )
})

test_that("invalid non-string targets still error as before", {
    data <- data.frame(income = c(10, 20))
    expect_error(replace_values(data, , 0), "unquoted")
    expect_error(replace_values(data, income + 1, 0), "unquoted")
    expect_error(replace_values(data, !!1, 0), "unquoted")
    expect_error(replace_values(data, !!list("income"), 0), "unquoted")
})

test_that("existing unquoted forms are untouched", {
    data <- data.frame(income = c(10, 20), eligible = c(TRUE, FALSE))
    repl(data, income, income * 2, where = eligible)
    expect_equal(as.double(data$income), c(20, 20))

    gen(data, adjusted, income + 5)
    expect_equal(as.double(data$adjusted), c(25, 25))

    repl(data, income, ~ income + 1)
    expect_equal(as.double(data$income), c(21, 21))
})

test_that("the `.data` pronoun reaches a runtime name in values and where", {
    data <- data.frame(cluster = c(1, 2), hh1 = c(5, NA))
    hh1_name <- "hh1"

    repl(data, cluster, .data[[hh1_name]])
    expect_equal(as.double(data$cluster), c(5, NA))

    repl(data, cluster, 0, where = !is_missing(.data[[hh1_name]]))
    expect_equal(as.double(data$cluster), c(0, NA))

    gen(data, doubled, .data[[hh1_name]] * 2)
    expect_equal(as.double(data$doubled), c(10, NA))
})

test_that("the `.data` pronoun does not name a target", {
    data <- data.frame(income = c(10, 20))
    target_name <- "income"
    expect_error(repl(data, .data[[target_name]], 0), "unquoted")
})

test_that("the downstream call shapes work without inject or sym", {
    # Shape one: a resolved runtime name in both the target and the value
    # source, formerly `inject(repl(data, cluster, !!sym(name)))`.
    data <- data.frame(cluster = c(1, 2), hh1 = c(5, 6))
    hh1_name <- resolve_var_name(data, "hh1")
    target_name <- resolve_var_name(data, "cluster")
    repl(data, !!target_name, .data[[hh1_name]])
    expect_equal(as.double(data$cluster), c(5, 6))

    # Shape two: a wrapper relaying an enquo'd argument, formerly
    # `rlang::inject(gen(data, !!variable, .env$result))`.
    add_variable <- function(data, variable, result) {
        variable <- rlang::enquo(variable)
        gen(data, !!variable, .env$result)
    }
    add_variable(data, created, c(7, 8))
    expect_equal(as.double(data$created), c(7, 8))

    # The same wrapper relaying a string rather than a symbol.
    add_variable(data, !!"also_created", c(1, 2))
    expect_equal(as.double(data$also_created), c(1, 2))
})

test_that("`set_var_label()` accepts a runtime string name", {
    data <- data.frame(income = c(10, 20))
    label_target <- "income"

    set_var_label(data, !!label_target, "Income")
    expect_identical(var_label(data$income), "Income")

    set_var_label(data, !!rlang::sym(label_target), "Older spelling")
    expect_identical(var_label(data$income), "Older spelling")

    set_var_label(data, income, "Unquoted still works")
    expect_identical(var_label(data$income), "Unquoted still works")

    expect_error(
        set_var_label(data, !!NA_character_, "Income"),
        "must be one unquoted column name or one nonempty, non-missing"
    )
    expect_error(
        set_var_label(data, !!"", "Income"),
        "must be one unquoted column name or one nonempty, non-missing"
    )
})

test_that("a string target leaves a compact column unmaterialized", {
    data <- data.frame(income = c(10, 20))
    gen(data, !!"compact", stata_float(income))
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(data$compact)
    )
    repl(data, !!"compact", 3, where = 2L)
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(data$compact)
    )
    expect_equal(as.double(data$compact), c(10, 3))
})
