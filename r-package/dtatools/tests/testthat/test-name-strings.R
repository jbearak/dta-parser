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
    data <- reserve_columns(data.frame(cluster = c(1, 2), hh1 = c(5, 6)))
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
    gen(data, !!"compact", dta_float(income))
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(data$compact)
    )
    repl(data, !!"compact", 3, where = 2L)
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(data$compact)
    )
    expect_equal(as.double(data$compact), c(10, 3))
})

test_that("`.()` names the target and reads columns at run time", {
    data <- data.frame(income = c(10, 20), hh1 = c(5, 6))
    target <- "income"
    origin <- "hh1"

    repl(data, .(target), .(origin) + 1)
    expect_equal(as.double(data$income), c(6, 7))

    repl(data, .(target), 0, where = .(origin) > 5)
    expect_equal(as.double(data$income), c(6, 0))

    # `.()` sits inside a larger expression, which `!!` cannot do.
    gen(data, .(paste0(target, "_flag")), .(origin) * 2 + income)
    expect_equal(as.double(data$income_flag), c(16, 12))
})

test_that("`.()` rejects invalid runtime names", {
    data <- data.frame(income = c(10, 20))
    expect_error(
        repl(data, .(1), 0),
        "takes one nonempty, non-missing string"
    )
    expect_error(
        repl(data, .(c("a", "b")), 0),
        "takes one nonempty, non-missing string"
    )
    expect_error(
        repl(data, .("income", "extra"), 0),
        "takes one nonempty, non-missing string"
    )
    absent <- "absent"
    expect_error(repl(data, income, .(absent)), "does not exist")
    expect_identical(names(data), "income")
})

test_that("`set_var_label()` accepts a `.()` runtime name", {
    data <- data.frame(income = c(10, 20))
    target <- "income"
    set_var_label(data, .(target), "Income")
    expect_identical(var_label(data$income), "Income")
})

test_that("`.()` tags name columns in the plural label setters", {
    data <- data.frame(a = c(1, 2), b = c(3, 4))
    first <- "a"
    set_var_labels(data, .(first) := "First", b = "Second")
    expect_identical(var_label(data$a), "First")
    expect_identical(var_label(data$b), "Second")

    second <- "b"
    set_val_labels(data, .(second) := c(yes = 3, no = 4))
    expect_identical(val_labels(data$b), c(yes = 3, no = 4))
})

test_that("`.()` tags coexist with splices and `:=` names", {
    data <- data.frame(a = c(1, 2), b = c(3, 4), c = c(5, 6))
    tag <- "a"
    others <- list(b = "Second")
    third <- "c"
    set_var_labels(data, .(tag) := "First", !!!others, !!third := "Third")
    expect_identical(var_label(data$a), "First")
    expect_identical(var_label(data$b), "Second")
    expect_identical(var_label(data$c), "Third")

    # Overlapping updates still fail atomically alongside a tag.
    expect_error(
        set_var_labels(data, .(tag) := "x", a = "y"),
        "must not contain duplicate column names"
    )
    expect_identical(var_label(data$a), "First")
    expect_identical(var_label(data$b), "Second")
    expect_identical(var_label(data$c), "Third")
})

test_that("`.()` tags keep a spliced value's own frame and reject empties", {
    data <- data.frame(a = c(1, 2), b = c(3, 4))
    tag <- "a"
    relabel <- function(data, ...) set_var_labels(data, ...)
    from_caller <- function(data) {
        second <- "b"
        spliced <- list(b = "Spliced")
        relabel(data, .(tag) := "Tagged", !!second := "Named")
        relabel(data, .(tag) := "Tagged", !!!spliced)
    }
    from_caller(data)
    expect_identical(var_label(data$a), "Tagged")
    expect_identical(var_label(data$b), "Spliced")

    expect_error(set_var_labels(data, .(tag) := "x", ), "can't be empty")
    expect_identical(var_label(data$a), "Tagged")
})

test_that("forwarded dots keep their own frames alongside a `.()` tag", {
    relabel <- function(data, ...) set_var_labels(data, ...)
    revalue <- function(data, ...) set_val_labels(data, ...)
    from_caller <- function(data) {
        tag_name <- "a"
        caller_label <- "From the caller"
        relabel(data, .(tag_name) := "Tagged", b = caller_label)
        revalue(data, .(tag_name) := c(low = 1))
    }
    data <- data.frame(a = c(1, 2), b = c(3, 4))
    from_caller(data)
    expect_identical(var_label(data$a), "Tagged")
    expect_identical(var_label(data$b), "From the caller")
    expect_identical(val_labels(data$a), c(low = 1))
})
