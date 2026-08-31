test_that("reference mutation exports one coherent API", {
    expect_identical(repl, replace_values)
    expect_identical(
        formals(replace_values),
        as.pairlist(alist(data = , variable = , values = , where = NULL))
    )
    expect_identical(formals(repl), formals(replace_values))
    expect_identical(formals(gen), formals(replace_values))

    data <- data.frame(x = c(1, 2, 3), eligible = c(TRUE, FALSE, TRUE))
    alias <- data
    result <- withVisible(replace_values(data, x, 0, where = eligible))

    expect_false(result$visible)
    expect_identical(result$value, data)
    expect_identical(data$x, c(0, 2, 0))
    expect_identical(alias$x, data$x)
    expect_false(inherits(data, "dtatools_ref_data"))
})

test_that("matrix columns use data-frame row sizes", {
    make_frame <- function() {
        data.frame(x = 1:3, matrix = I(matrix(1:6, nrow = 3)))
    }

    replaced <- make_frame()
    replace_values(replaced, x, 9L, where = 1)
    expect_identical(replaced$x, c(9L, 2L, 3L))
    expect_identical(replaced$matrix, I(matrix(1:6, nrow = 3)))

    generated <- make_frame()
    gen(generated, y, x * 2)
    expect_identical(as.double(generated$y), c(2, 4, 6))
    expect_identical(generated$matrix, I(matrix(1:6, nrow = 3)))

    original <- make_frame()
    copied <- copy_data(original)
    expect_identical(copied, original)
    expect_identical(dim(copied$matrix), c(3L, 2L))
})

test_that("targets are bare names and support tidy injection", {
    data <- data.frame(x = 1:2)
    expect_error(replace_values(data, "x", 0), "unquoted")
    expect_error(replace_values(data, , 0), "unquoted")
    expect_error(replace_values(data, unknown, 0), "does not exist")
    expect_error(gen(data, "new", 0), "unquoted")

    target <- rlang::sym("x")
    expect_silent(replace_values(data, !!target, 4L))
    expect_identical(data$x, c(4L, 4L))

    generated <- rlang::sym("new")
    expect_silent(gen(data, !!generated, 5))
    expect_identical(as.double(data$new), c(5, 5))
})

test_that("data masks, formulas, and alias calls use the right environments", {
    data <- data.frame(
        x = c(1L, 2L, 3L),
        adjustment = c(2L, 3L, 4L),
        eligible = c(TRUE, FALSE, TRUE),
        constant = c(10L, 20L, 30L)
    )
    constant <- 100L
    value_rule <- ~ x * adjustment + .env$constant
    selection_rule <- ~ eligible

    repl(data, x, value_rule, where = selection_rule)
    expect_identical(data$x, c(102L, 2L, 112L))

    gen(data, from_column, constant)
    expect_identical(as.double(data$from_column), c(10, 20, 30))
    gen(data, from_environment, .env$constant)
    expect_identical(as.double(data$from_environment), rep(100, 3))
    gen(data, inline_formula_environment, ~ .env$constant)
    expect_identical(
        as.double(data$inline_formula_environment),
        rep(100, 3)
    )
    cutoff <- 2L
    selection_data <- data.frame(x = 1:3)
    replace_values(selection_data, x, 0L, where = ~ x >= .env$cutoff)
    expect_identical(selection_data$x, c(1L, 0L, 0L))

    local_repl <- function(data) {
        offset <- 7L
        repl(data, x, x + .env$offset, where = eligible)
    }
    local_repl(data)
    expect_identical(data$x, c(109L, 2L, 119L))

    expect_error(repl(data, x, x ~ x + 1), "one-sided")
    expect_error(repl(data, x, 1, where = x ~ eligible), "one-sided")
})

test_that("values and selection see the unchanged dataset", {
    data <- data.frame(x = 1:4, source = 11:14)
    replace_values(data, x, x + source, where = x <= 2)
    expect_identical(data$x, c(12L, 14L, 3L, 4L))

    gen(data, created, source * 2)
    expect_identical(as.double(data$created), c(22, 24, 26, 28))

    for (constructor in list(identity, stata_byte)) {
        target <- constructor(c(2L, 1L, 1L))
        direct <- data.frame(x = target)
        replace_values(direct, x, 9, where = x)
        expect_identical(as.double(direct$x), c(9, 9, 1))

        target <- constructor(c(2L, 1L, 1L))
        aliased <- data.frame(x = target, selector = target)
        replace_values(aliased, x, 7, where = selector)
        expect_identical(as.double(aliased$x), c(7, 7, 1))
        expect_identical(as.double(aliased$selector), c(7, 7, 1))
    }
})

test_that("where has documented logical and position semantics", {
    data <- data.frame(x = 1:5)
    replace_values(data, x, 8L, where = TRUE)
    expect_identical(data$x, rep(8L, 5))

    replace_values(data, x, 1:5, where = c(TRUE, NA, FALSE, FALSE, TRUE))
    expect_identical(data$x, c(1L, 8L, 8L, 8L, 5L))

    replace_values(data, x, c(20L, 30L, 40L), where = c(2, 2, 4))
    expect_identical(data$x, c(1L, 30L, 8L, 40L, 5L))

    compact_positions <- data.frame(x = 1:3)
    replace_values(
        compact_positions, x, c(8L, 9L),
        where = stata_byte(c(3, 1))
    )
    expect_identical(compact_positions$x, c(9L, 2L, 8L))

    replace_values(
        compact_positions, x, c(6L, 7L, 5L),
        where = stata_long(c(3, 1, 3))
    )
    expect_identical(compact_positions$x, c(6L, 2L, 5L))

    all_rows <- data.frame(x = stata_byte(1:3))
    replace_values(all_rows, x, 4, where = rep(TRUE, 3))
    expect_identical(as.double(all_rows$x), rep(4, 3))

    unchanged <- data$x
    replace_values(data, x, integer(), where = integer())
    expect_identical(data$x, unchanged)

    for (selection in list(FALSE, integer())) {
        fresh <- data.frame(x = 1:3)
        before <- serialize(fresh, NULL)
        replace_values(fresh, x, 9L, where = selection)
        expect_identical(serialize(fresh, NULL), before)
        expect_false(inherits(fresh, "dtatools_ref_data"))
    }

    for (bad in list(0, -1, NA_real_, Inf, 1.5, 6)) {
        expect_error(replace_values(data, x, 0L, where = bad), "row positions")
        expect_identical(data$x, unchanged)
    }
    expect_error(replace_values(data, x, 1:2, where = TRUE), "has size")
    expect_error(replace_values(data, x, 1L, where = c(TRUE, FALSE)),
                 "has size")
})

test_that("full-dataset values are gathered by selected row", {
    rows <- stata_long(c(5, 2, 5))
    values <- 11:15

    replaced <- data.frame(x = stata_byte(1:5))
    replace_values(replaced, x, values, where = rows)
    expect_identical(as.double(replaced$x), c(1, 12, 3, 4, 15))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(replaced$x))

    generated <- data.frame(x = 1:5)
    gen(generated, y, values, where = rows)
    expect_identical(as.double(generated$y), c(NA, 12, NA, NA, 15))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(generated$y))

    strings <- data.frame(x = 1:5)
    string_values <- structure(letters[1:5], label = "letters")
    gen(strings, y, string_values, where = stata_long(c(3, 1)))
    expect_identical(as.character(strings$y), c("a", "", "c", "", ""))
    expect_identical(attr(strings$y, "label"), "letters")
    expect_identical(attr(strings$y, "stata.string.storage"), "str1")
})

test_that("native mutation writers reject untrusted row plans", {
    namespace <- asNamespace("dtatools")
    patch <- get("C_dtatools_patch_vector", namespace)
    generate <- get("C_dtatools_generate_numeric", namespace)
    generate_character <- get(
        "C_dtatools_generate_character", namespace
    )
    generated_attributes <- attributes(stata_byte(double()))

    target <- stata_byte(1:3)
    expect_error(.Call(patch, target, 0L, 9), "mutation row")
    expect_error(.Call(patch, target, 4L, 9), "mutation row")
    expect_identical(as.double(target), c(1, 2, 3))

    expect_error(
        .Call(generate, 9, 0L, 3, 0L, 0L, generated_attributes),
        "mutation row"
    )
    expect_error(
        .Call(generate, 9, 4L, 3, 0L, 0L, generated_attributes),
        "mutation row"
    )
    expect_error(
        .Call(generate_character, "x", 0L, 3, NULL, NULL),
        "mutation row"
    )
    expect_error(
        .Call(generate_character, "x", 4L, 3, NULL, NULL),
        "mutation row"
    )
})

test_that("validation errors leave an unmarked dataset unchanged", {
    cases <- list(
        quote(replace_values(data, x, 1:2)),
        quote(replace_values(data, x, "bad")),
        quote(replace_values(data, x, NaN)),
        quote(replace_values(data, x, Inf)),
        quote(replace_values(data, x, stop("value failure"))),
        quote(replace_values(data, x, 0, where = stop("where failure"))),
        quote(gen(data, x, 0)),
        quote(gen(data, new, list(1, 2, 3)))
    )
    for (call in cases) {
        data <- data.frame(x = 1:3, text = letters[1:3])
        before <- serialize(data, NULL)
        expect_error(eval(call))
        expect_identical(serialize(data, NULL), before)
        expect_false(inherits(data, "dtatools_ref_data"))
    }
})

test_that("evaluation interrupts leave the dataset unchanged", {
    data <- data.frame(x = 1:3)
    before <- serialize(data, NULL)
    condition <- rlang::catch_cnd(
        replace_values(data, x, rlang::interrupt())
    )
    expect_s3_class(condition, "interrupt")
    expect_identical(serialize(data, NULL), before)

    condition <- rlang::catch_cnd(
        gen(data, y, 1, where = rlang::interrupt())
    )
    expect_s3_class(condition, "interrupt")
    expect_identical(serialize(data, NULL), before)
})

test_that("native write interrupts roll back values and compact state", {
    skip_on_os("windows")
    skip_if_not_installed("callr")

    result <- callr::r(
        function() {
            library(dtatools)
            interrupt_patch <- function(compact) {
                size <- 20000000L
                target <- if (compact) {
                    stata_float(rep.int(1L, size))
                } else {
                    rep(1, size)
                }
                data <- data.frame(target = target)
                parent <- Sys.getpid()
                signal <- parallel::mcparallel({
                    Sys.sleep(if (compact) 0.02 else 0.03)
                    tools::pskill(parent, tools::SIGINT)
                }, silent = TRUE)
                condition <- tryCatch(
                    {
                        replace_values(data, target, 2)
                        NULL
                    },
                    condition = identity
                )
                tryCatch(
                    suppressWarnings(parallel::mccollect(signal)),
                    condition = function(...) NULL
                )
                list(
                    interrupted = inherits(condition, "interrupt"),
                    compact = !compact ||
                        dtatools:::.is_unmaterialized_numeric_altrep(
                            data$target
                        ),
                    no_missing = !anyNA(data$target),
                    sum = as.double(sum(data$target)),
                    minimum = as.double(min(data$target)),
                    maximum = as.double(max(data$target)),
                    size = size
                )
            }
            list(
                compact = interrupt_patch(TRUE),
                ordinary = interrupt_patch(FALSE),
                dictionary = local({
                    size <- 10000000L
                    path <- tempfile(fileext = ".arrow")
                    on.exit(unlink(path), add = TRUE)
                    save_arrow(data.frame(
                        target = rep(c("a", "b"), length.out = size)
                    ), path)
                    data <- read_arrow(path)
                    parent <- Sys.getpid()
                    signal <- parallel::mcparallel({
                        Sys.sleep(0.22)
                        tools::pskill(parent, tools::SIGINT)
                    }, silent = TRUE)
                    condition <- tryCatch(
                        {
                            replace_values(data, target, "changed")
                            NULL
                        },
                        condition = identity
                    )
                    tryCatch(
                        suppressWarnings(parallel::mccollect(signal)),
                        condition = function(...) NULL
                    )
                    sample <- tryCatch(
                        as.character(data$target[c(1L, size / 2L, size)]),
                        condition = identity
                    )
                    list(
                        interrupted = inherits(condition, "interrupt"),
                        compact = dtatools:::.is_unmaterialized_dictstring(
                            data$target
                        ),
                        readable = !inherits(sample, "condition"),
                        sample = if (inherits(sample, "condition")) {
                            character()
                        } else {
                            sample
                        }
                    )
                })
            )
        },
        libpath = .libPaths(),
        timeout = 120
    )

    for (case in result[c("compact", "ordinary")]) {
        expect_true(case$interrupted)
        expect_true(case$compact)
        expect_true(case$no_missing)
        expect_identical(case$sum, as.double(case$size))
        expect_identical(case$minimum, 1)
        expect_identical(case$maximum, 1)
    }
    expect_true(result$dictionary$interrupted)
    expect_true(result$dictionary$compact)
    expect_true(result$dictionary$readable)
    expect_identical(result$dictionary$sample, c("a", "b", "b"))
})

test_that("compact replacement patches every storage without materializing", {
    constructors <- list(
        byte = stata_byte,
        int = stata_int,
        long = stata_long,
        float = stata_float
    )
    for (storage in names(constructors)) {
        target <- constructors[[storage]](c(
            1, 2, NA_real_, tagged_missing("a"), tagged_missing("z")
        ))
        attr(target, "label") <- paste(storage, "label")
        attr(target, "format.stata") <- "%9.0g"
        attr(target, "labels") <- c(One = 1)
        data <- data.frame(target = target)

        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$target))
        replace_values(
            data, target,
            c(9, tagged_missing("b"), NA_real_),
            where = c(1, 2, 3)
        )
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$target))
        expect_identical(stata_storage_type(data$target), storage)
        expect_equal(as.double(data$target)[c(1, 4, 5)],
                     c(9, tagged_missing("a"), tagged_missing("z")))
        expect_true(is_tagged_missing(data$target[[2]], "b"))
        expect_true(is.na(data$target[[3]]))
        expect_identical(attr(data$target, "label"), paste(storage, "label"))
        expect_identical(attr(data$target, "format.stata"), "%9.0g")
        expect_identical(attr(data$target, "labels"), c(One = 1))
    }
})

test_that("compact validation is strict and atomic", {
    data <- data.frame(x = stata_byte(c(1, 2, 3)))
    for (bad in list(101, 1.5, NaN, Inf)) {
        before <- serialize(data$x, NULL)
        expect_error(replace_values(data, x, bad, where = 2))
        expect_identical(serialize(data$x, NULL), before)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    }
    expect_error(replace_values(data, x, 101, where = 2), "stata_int")
    expect_identical(stata_storage_type(data$x), "byte")
})

test_that("compact replacement updates the missing-value cache", {
    data <- data.frame(x = stata_byte(1:3))
    expect_false(anyNA(data$x))
    replace_values(data, x, NA_real_, where = 2)
    expect_true(anyNA(data$x))
    replace_values(data, x, 2, where = 2)
    expect_false(anyNA(data$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))

    late_missing <- data.frame(x = stata_byte(c(1, 2, NA_real_)))
    replace_values(late_missing, x, 9, where = 1)
    expect_true(anyNA(late_missing$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(late_missing$x))

    duplicate <- data.frame(x = stata_byte(1:3))
    replace_values(
        duplicate, x, c(NA_real_, 2), where = c(1, 1)
    )
    expect_false(anyNA(duplicate$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(duplicate$x))

    generated <- data.frame(x = 1:3)
    gen(generated, y, stata_byte(1), where = 2)
    expect_true(anyNA(generated$y))
    replace_values(generated, y, 1, where = c(1, 3))
    expect_false(anyNA(generated$y))

    restored <- unserialize(serialize(
        data.frame(x = stata_byte(c(NA_real_, 1))), NULL
    ))
    replace_values(restored, x, 1, where = 1)
    expect_false(anyNA(restored$x))

    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    save_arrow(data.frame(x = stata_byte(c(NA_real_, 1))), arrow_path)
    arrow <- read_arrow(arrow_path)
    replace_values(arrow, x, 1, where = 1)
    expect_false(anyNA(arrow$x))
})

test_that("DTA-loaded compact and temporal columns use native patching", {
    data <- read_dta(fixture("all_types_v118.dta"))
    compact <- names(data)[vapply(
        data,
        function(column) isTRUE(stata_storage_type(column) %in%
            c("byte", "int", "long", "float")),
        logical(1)
    )]
    for (name in compact) {
        target <- rlang::sym(name)
        replace_values(data, !!target, 1, where = 1)
        expect_true(
            dtatools:::.is_unmaterialized_numeric_altrep(data[[name]]),
            info = name
        )
    }

    path <- fixture_with_temporal_storage("price")
    on.exit(unlink(path), add = TRUE)
    dated <- read_dta(path)
    replacement <- as.Date("1970-01-05")
    replace_values(dated, price, replacement, where = 1)
    expect_identical(as.double(dated$price[[1]]), as.double(replacement))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(dated$price))

    replacements <- replacement + seq_len(nrow(dated))
    replace_values(dated, price, replacements)
    expect_identical(as.double(dated$price), as.double(replacements))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(dated$price))
})

test_that("legacy compact columns reject scalar extended missing values", {
    data <- read_dta(fixture("synthetic_v111.dta"))
    before <- serialize(data, NULL)
    expect_error(
        replace_values(data, b, tagged_missing("a"), where = 1),
        "legacy compact column"
    )
    expect_identical(serialize(data, NULL), before)
})

test_that("ordinary, materialized, temporal, and character columns mutate", {
    data <- data.frame(
        doubles = c(1, 2, 3),
        integers = 1:3,
        logicals = c(TRUE, FALSE, TRUE),
        strings = c("a", "b", "c"),
        dates = as.Date("2020-01-01") + 0:2
    )
    replace_values(data, doubles, 4, where = 2)
    replace_values(data, integers, 8L, where = 2)
    replace_values(data, logicals, FALSE, where = 1)
    replace_values(data, strings, "z", where = 3)
    replace_values(data, dates, as.Date("2021-01-01"), where = 2)
    expect_identical(data$doubles, c(1, 4, 3))
    expect_identical(data$integers, c(1L, 8L, 3L))
    expect_identical(data$logicals, c(FALSE, FALSE, TRUE))
    expect_identical(data$strings, c("a", "b", "z"))
    expect_identical(data$dates[[2]], as.Date("2021-01-01"))

    compact <- stata_int(1:3)
    dtatools:::.force_altrep_materialization(compact)
    materialized <- data.frame(x = compact)
    replace_values(materialized, x, 7, where = 1)
    expect_false(dtatools:::.is_unmaterialized_numeric_altrep(materialized$x))
    expect_identical(as.double(materialized$x), c(7, 2, 3))

    fixed <- data.frame(text = c("a", "b"))
    attr(fixed$text, "stata.string.storage") <- "str2"
    before <- serialize(fixed, NULL)
    expect_error(replace_values(fixed, text, "long"), "do not fit")
    expect_identical(serialize(fixed, NULL), before)
})

test_that("gen appends one variable with Stata missing and storage rules", {
    data <- tibble::tibble(x = c(1, 2, 3), eligible = c(TRUE, FALSE, TRUE))
    alias <- data
    result <- withVisible(gen(data, generated, x * 2, where = eligible))
    expect_false(result$visible)
    expect_identical(names(data), c("x", "eligible", "generated"))
    expect_identical(names(alias), names(data))
    expect_identical(as.double(data$generated), c(2, NA, 6))
    expect_identical(stata_storage_type(data$generated), "float")
    expect_s3_class(data, "tbl_df")
    expect_equal(dim(data), c(3L, 3L))
    expect_error(gen(data, generated, 1), "already exists")
    expect_identical(ncol(data), 3L)

    gen(data, declared, stata_int(x))
    expect_identical(stata_storage_type(data$declared), "int")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$declared))

    dates <- as.Date("2020-01-01") + 0:2
    datetimes <- as.POSIXct(
        "2020-01-01 00:00:01", tz = "UTC"
    ) + 0:2
    temporal <- data.frame(x = 1:3)
    gen(temporal, date, dates)
    gen(temporal, datetime, datetimes)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(temporal$date))
    expect_identical(dtatools:::.metadata_proxy_depth(temporal$date), 0L)
    replace_values(temporal, date, dates[[1L]], where = 1L)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(temporal$date))
    expect_identical(as.double(temporal$date), as.double(dates))
    expect_identical(as.double(temporal$datetime), as.double(datetimes))
    expect_s3_class(temporal$date, "stata_date")
    expect_s3_class(temporal$datetime, "stata_datetime")
    expect_identical(stata_storage_type(temporal$date), "float")
    expect_identical(stata_storage_type(temporal$datetime), "double")

    compact_source <- data.frame(x = stata_byte(1:3))
    gen(compact_source, y, x)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact_source$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact_source$y))
    expect_identical(stata_storage_type(compact_source$y), "byte")
    expect_identical(as.double(compact_source$y), c(1, 2, 3))

    integer_source <- data.frame(x = 1:3)
    gen(integer_source, y, x)
    expect_identical(dtatools:::.metadata_proxy_depth(integer_source$y), 0L)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(integer_source$y))
    replace_values(integer_source, y, 4, where = 1L)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(integer_source$y))
    expect_identical(as.double(integer_source$y), c(4, 2, 3))

    labelled <- stata_byte(c(1, 2, 3))
    attr(labelled, "label") <- "Generated label"
    attr(labelled, "labels") <- c(One = 1)
    attr(labelled, "format.stata") <- "%8.0g"
    gen(data, labelled, labelled)
    expect_identical(attr(data$labelled, "label"), "Generated label")
    expect_identical(attr(data$labelled, "labels"), c(One = 1))
    expect_identical(attr(data$labelled, "format.stata"), "%8.0g")

    authored <- set_variable_labels(
        set_value_labels(c(1, 2, 3), One = 1),
        "Authored label"
    )
    attr(authored, "format.stata") <- "%9.0g"
    gen(data, authored, authored)
    expect_identical(as.double(data$authored), c(1, 2, 3))
    expect_identical(var_label(data$authored), "Authored label")
    expect_identical(val_labels(data$authored), c(One = 1))
    expect_identical(attr(data$authored, "format.stata"), "%9.0g")
    expect_s3_class(data$authored, "haven_labelled")

    attributed <- structure(
        c(4, 5, 6),
        label = "Attributed label",
        labels = c(Four = 4),
        format.stata = "%8.0g"
    )
    gen(data, attributed, attributed)
    expect_identical(var_label(data$attributed), "Attributed label")
    expect_identical(val_labels(data$attributed), c(Four = 4))
    expect_identical(attr(data$attributed, "format.stata"), "%8.0g")

    gen(data, string, c("a", "long", "z"), where = eligible)
    expect_identical(as.vector(data$string), c("a", "", "z"))
    expect_identical(attr(data$string, "stata.string.storage"), "str1")

    strings <- data.frame(x = 1:3)
    authored_string <- structure(
        c("one", NA_character_, "three"),
        label = "Authored string",
        stata.string.storage = "str5"
    )
    gen(strings, y, authored_string, where = stata_long(c(3, 1, 3)))
    expect_identical(as.character(strings$y), c("one", "", "three"))
    expect_identical(attr(strings$y, "label"), "Authored string")
    expect_identical(attr(strings$y, "stata.string.storage"), "str5")

    too_narrow <- structure("wide", stata.string.storage = "str2")
    expect_error(gen(strings, too_wide, too_narrow), "do not fit")
    expect_false("too_wide" %in% names(strings))

    wide <- paste(rep("x", 2046), collapse = "")
    gen(data, long_string, wide)
    expect_identical(attr(data$long_string, "stata.string.storage"), "strL")
})

test_that("gen handles zero rows and evaluates before insertion", {
    empty <- data.frame(x = integer())
    gen(empty, y, x + 1L)
    expect_equal(dim(empty), c(0L, 2L))
    expect_identical(length(empty$y), 0L)

    data <- data.frame(x = 1:2)
    expect_error(gen(data, y, y + 1), "object 'y' not found")
    expect_identical(names(data), "x")
})

test_that("copy_data isolates every mutable column backing", {
    data <- data.frame(
        compact = stata_long(c(1, tagged_missing("a"), 3)),
        ordinary = c(4, 5, 6),
        string = c("a", "b", "c")
    )
    attr(data, "label") <- "source"
    attr(data, "notes") <- c("first note", "second note")
    attr(data, "characteristics") <- list(source = "survey")
    attr(data$compact, "label") <- "compact label"
    isolated <- copy_data(data)

    expect_s3_class(isolated, "data.frame")
    expect_false(inherits(isolated, "dtatools_ref_data"))
    expect_identical(attr(isolated, "label"), "source")
    expect_identical(attr(isolated, "notes"), c("first note", "second note"))
    expect_identical(
        attr(isolated, "characteristics"),
        list(source = "survey")
    )
    expect_identical(attr(isolated$compact, "label"), "compact label")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(isolated$compact))

    replace_values(isolated, compact, 9, where = 1)
    replace_values(isolated, ordinary, 9, where = 1)
    replace_values(isolated, string, "z", where = 1)
    expect_equal(as.double(data$compact)[[1]], 1)
    expect_identical(data$ordinary[[1]], 4)
    expect_identical(data$string[[1]], "a")

    replace_values(data, compact, 8, where = 3)
    expect_equal(as.double(isolated$compact)[[3]], 3)

    gen(data, generated, compact + ordinary)
    generated_copy <- copy_data(data)
    replace_values(generated_copy, generated, 0, where = 1)
    expect_false(identical(
        as.double(data$generated)[[1]],
        as.double(generated_copy$generated)[[1]]
    ))
})

test_that("subsets, metadata proxies, and serialized data stay isolated", {
    source <- data.frame(x = stata_int(c(1, 2, 3)))
    subset <- source[1:2, , drop = FALSE]
    replace_values(subset, x, 9, where = 1)
    expect_identical(as.double(source$x), c(1, 2, 3))

    proxy <- data.frame(x = dtatools:::.metadata_copy(source$x))
    replace_values(proxy, x, 8, where = 1)
    replace_values(proxy, x, 6, where = 2)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(proxy$x))
    expect_identical(as.double(source$x), c(1, 2, 3))
    expect_identical(as.double(proxy$x), c(8, 6, 3))

    restored <- unserialize(serialize(source, NULL))
    replace_values(restored, x, 7, where = 1)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(restored$x))
    expect_identical(as.double(source$x), c(1, 2, 3))

    gen(source, generated, x + 1)
    generated_subset <- source[1:2, c("x", "generated")]
    replace_values(generated_subset, generated, 0, where = 1)
    expect_identical(as.double(source$generated), c(2, 3, 4))
})

test_that("detached metadata payloads do not retain former proxy owners", {
    finalized <- new.env(parent = emptyenv())
    finalized$done <- FALSE
    make_downstream_proxy <- function() {
        source <- stata_byte(rep(1, 100))
        proxy <- dtatools:::.metadata_copy(source)
        tracker <- new.env(parent = emptyenv())
        reg.finalizer(
            tracker,
            function(environment) finalized$done <- TRUE,
            onexit = FALSE
        )
        attr(proxy, "tracker") <- tracker
        data <- data.frame(x = proxy)
        replace_values(data, x, 2, where = 1)
        proxy <- data$x
        downstream <- dtatools:::.metadata_copy(proxy)
        attr(downstream, "tracker") <- NULL
        invisible(dtatools:::.force_altrep_materialization(proxy))
        downstream
    }
    downstream <- make_downstream_proxy()
    for (iteration in seq_len(5L)) {
        if (finalized$done) break
        gc(full = TRUE)
    }
    expect_true(finalized$done)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(downstream))
})

test_that("downstream metadata proxies revoke exclusive patch ownership", {
    first <- data.frame(x = dtatools:::.metadata_copy(stata_byte(1:3)))
    replace_values(first, x, 4, where = 1)
    second <- data.frame(x = dtatools:::.metadata_copy(first$x))

    replace_values(first, x, 7, where = 1)

    expect_identical(as.double(first$x), c(7, 2, 3))
    expect_identical(as.double(second$x), c(4, 2, 3))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(second$x))
})

test_that("metadata helpers remain isolated from later source patches", {
    compact_source <- data.frame(x = stata_byte(1:3))
    compact_copy <- set_variable_labels(compact_source, x = "Copy")
    replace_values(compact_source, x, 9, where = 1)
    expect_identical(as.double(compact_source$x), c(9, 2, 3))
    expect_identical(as.double(compact_copy$x), c(1, 2, 3))

    materialized_source <- data.frame(x = stata_byte(1:3))
    materialized_copy <- set_variable_labels(
        materialized_source, x = "Copy"
    )
    invisible(dtatools:::.force_altrep_materialization(
        materialized_source$x
    ))
    replace_values(materialized_source, x, 9, where = 1)
    expect_identical(as.double(materialized_source$x), c(9, 2, 3))
    expect_identical(as.double(materialized_copy$x), c(1, 2, 3))

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    string_source <- read_arrow(path)
    expect_true(dtatools:::.is_unmaterialized_dictstring(
        string_source$text
    ))
    string_copy <- set_variable_labels(string_source, text = "Copy")
    replace_values(string_source, text, "changed", where = 1)
    expect_identical(as.character(string_source$text), c("changed", "b", "a"))
    expect_true(dtatools:::.is_unmaterialized_dictstring(string_copy$text))
    expect_identical(as.character(string_copy$text), c("a", "b", "a"))
})

test_that("writable access detaches shared materialized payloads", {
    numeric <- stata_byte(1:3)
    invisible(dtatools:::.force_altrep_materialization(numeric))
    numeric_copy <- dtatools:::.metadata_copy(numeric)
    numeric <- dtatools:::.mutate_first_numeric_altrep(numeric, 99)
    expect_identical(as.double(numeric), c(99, 2, 3))
    expect_identical(as.double(numeric_copy), c(1, 2, 3))

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    string <- read_arrow(path)$text
    invisible(dtatools:::.force_altrep_materialization(string))
    string_copy <- dtatools:::.metadata_copy(string)
    string <- dtatools:::.mutate_first_dictstring_altrep(string, "changed")
    expect_identical(as.character(string), c("changed", "b", "a"))
    expect_identical(as.character(string_copy), c("a", "b", "a"))
})

test_that("materialized metadata-proxy copies remain independent", {
    numeric <- dtatools:::.metadata_copy(stata_byte(1:3))
    invisible(dtatools:::.force_altrep_materialization(numeric))
    numeric_copy <- dtatools:::.metadata_copy(numeric)
    numeric_data <- data.frame(x = numeric)
    replace_values(numeric_data, x, 9, where = 1)
    expect_identical(as.double(numeric_data$x), c(9, 2, 3))
    expect_identical(as.double(numeric_copy), c(1, 2, 3))

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    string <- dtatools:::.metadata_copy(read_arrow(path)$text)
    invisible(dtatools:::.force_altrep_materialization(string))
    string_copy <- dtatools:::.metadata_copy(string)
    string_data <- data.frame(text = string)
    replace_values(string_data, text, "changed", where = 1)
    expect_identical(
        as.character(string_data$text), c("changed", "b", "a")
    )
    expect_identical(as.character(string_copy), c("a", "b", "a"))
})

test_that("materialized metadata proxies release former sources", {
    finalized <- new.env(parent = emptyenv())
    finalized$numeric <- FALSE
    finalized$string <- FALSE

    materialized_chain <- function(value, key) {
        former <- dtatools:::.metadata_copy(value)
        tracker <- new.env(parent = emptyenv())
        reg.finalizer(
            tracker,
            function(environment) finalized[[key]] <- TRUE,
            onexit = FALSE
        )
        attr(former, "tracker") <- tracker
        invisible(dtatools:::.force_altrep_materialization(former))
        downstream <- dtatools:::.metadata_copy(former)
        attr(downstream, "tracker") <- NULL
        invisible(dtatools:::.force_altrep_materialization(downstream))
        downstream
    }

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    string <- read_arrow(path)$text
    retained <- list(
        numeric = materialized_chain(stata_byte(1:3), "numeric"),
        string = materialized_chain(string, "string")
    )
    for (iteration in seq_len(5L)) {
        if (finalized$numeric && finalized$string) break
        gc(full = TRUE)
    }
    expect_true(finalized$numeric)
    expect_true(finalized$string)
    expect_identical(as.double(retained$numeric), c(1, 2, 3))
    expect_identical(retained$string, c("a", "b", "a"))
})

test_that("copy_data keeps Arrow dictionary strings independent and compact", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = rep(c("alpha", "beta"), 50)), path)
    source <- read_arrow(path)
    dictionary <- which(vapply(
        source, dtatools:::.is_unmaterialized_dictstring, logical(1)
    ))
    skip_if(length(dictionary) == 0L, "fixture did not produce dictionary strings")
    name <- names(source)[dictionary[[1L]]]
    target <- rlang::sym(name)
    isolated <- copy_data(source)
    expect_true(dtatools:::.is_unmaterialized_dictstring(isolated[[name]]))
    replace_values(isolated, !!target, "changed", where = 1)
    expect_false(identical(isolated[[name]][[1]], source[[name]][[1]]))
})

test_that("generated variables participate in package writes", {
    data <- data.frame(x = stata_byte(1:3))
    gen(data, y, stata_int(x * 10))
    path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(path, arrow_path)), add = TRUE)
    expect_identical(save_dta(data, path), data)
    actual <- read_dta(path)
    expect_identical(names(actual), c("x", "y"))
    expect_identical(as.double(actual$y), c(10, 20, 30))

    expect_warning(
        arrow_result <- save_arrow(data, arrow_path),
        NA
    )
    expect_identical(arrow_result, data)
    arrow_actual <- read_arrow(arrow_path)
    expect_identical(names(arrow_actual), c("x", "y"))
    expect_identical(as.double(arrow_actual$y), c(10, 20, 30))
})

test_that("reference data preserves base and tibble access semantics", {
    frame <- data.frame(x = 1:3, y = 4:6, foobar = 7:9)
    row.names(frame) <- c("a", "b", "c")
    gen(frame, z, x + y)
    expected_x <- data.frame(x = 1:3, row.names = c("a", "b", "c"))
    expect_identical(frame[1], expected_x)
    expect_identical(frame$foo, 7:9)
    rows <- frame[1:2, ]
    expect_identical(rows$x, 1:2)
    expect_identical(rows$y, 4:5)
    expect_identical(as.double(rows$z), c(5, 7))
    expect_identical(row.names(rows), c("a", "b"))
    expect_identical(frame[, "x"], 1:3)
    expect_identical(as.double(frame[2, "z"]), 7)
    expect_identical(
        as.double(frame[, "z", drop = FALSE]$z),
        c(5, 7, 9)
    )
    expect_identical(as.double(with(frame, z)), c(5, 7, 9))
    expect_identical(unname(as.matrix(frame)[, "z"]), c(5, 7, 9))
    expect_identical(as.double(subset(frame, z >= 7)$z), c(7, 9))
    expect_identical(as.double(transform(frame, a = z + 1)$a), c(6, 8, 10))
    expect_identical(as.double(within(frame, a <- z + 1)$a), c(6, 8, 10))
    expect_equal(dim(rbind(frame, frame)), c(6L, 4L))
    expect_equal(dim(cbind(frame, extra = 10:12)), c(3L, 5L))
    plain <- as.data.frame(frame)
    expect_equal(dim(rbind(plain, as.data.frame(frame))), c(6L, 4L))

    tbl <- tibble::tibble(x = 1:3)
    gen(tbl, y, x * 2)
    expect_warning(tbl$missing, "Unknown or uninitialised column")
    expect_s3_class(tbl[, "x"], "tbl_df")
    expect_identical(names(tibble::as_tibble(tbl)), c("x", "y"))
    expect_identical(names(dplyr::mutate(tbl, z = y + 1)), c("x", "y", "z"))
    expect_identical(names(dplyr::select(tbl, y)), "y")
    expect_identical(
        as.double(dplyr::arrange(tbl, dplyr::desc(y))$y),
        c(6, 4, 2)
    )
    expect_identical(names(dplyr::relocate(tbl, y)), c("y", "x"))
    expect_identical(names(dplyr::rename(tbl, doubled = y)), c("x", "doubled"))
    expect_identical(as.double(dplyr::filter(tbl, y >= 4)$y), c(4, 6))
    expect_identical(as.double(dplyr::slice(tbl, 2:3)$y), c(4, 6))
    expect_identical(names(dplyr::transmute(tbl, z = y + 1)), "z")
    expect_identical(nrow(dplyr::distinct(tbl, y)), 3L)
    grouped <- dplyr::group_by(tbl, y)
    expect_identical(names(grouped), c("x", "y"))
    expect_identical(dplyr::group_vars(grouped), "y")
    expect_identical(
        dplyr::summarise(grouped, n = dplyr::n())$n,
        rep(1L, 3)
    )
    expect_s3_class(dplyr::rowwise(tbl), "rowwise_df")
    combined <- dplyr::bind_rows(
        tibble::as_tibble(tbl), tibble::as_tibble(tbl)
    )
    expect_equal(dim(combined), c(6L, 2L))
})

test_that("target-vector aliases observe replacement while row subsets isolate", {
    column <- stata_int(1:3)
    left <- data.frame(x = column)
    right <- data.frame(x = column)
    replace_values(left, x, 9, where = 1)
    expect_identical(as.double(right$x), c(9, 2, 3))

    column_subset <- left[, "x", drop = FALSE]
    replace_values(column_subset, x, 8, where = 2)
    expect_identical(as.double(left$x), c(9, 8, 3))

    row_subset <- left[1:2, , drop = FALSE]
    replace_values(row_subset, x, 7, where = 1)
    expect_identical(as.double(left$x), c(9, 8, 3))
})

test_that("grouped and rowwise inputs fail before reference mutation", {
    grouped <- dplyr::group_by(tibble::tibble(x = 1:2), x)
    rowwise <- dplyr::rowwise(tibble::tibble(x = 1:2))
    for (data in list(grouped, rowwise)) {
        before <- serialize(data, NULL)
        expect_error(replace_values(data, x, 1L), "ungrouped")
        expect_error(gen(data, y, 1L), "ungrouped")
        expect_identical(serialize(data, NULL), before)

        isolated <- copy_data(data)
        expect_identical(class(isolated), class(data))
        expect_identical(dplyr::group_vars(isolated), dplyr::group_vars(data))
        expect_identical(as.data.frame(isolated), as.data.frame(data))
    }
})

test_that("ordinary assignments and metadata helpers materialize current state", {
    data <- data.frame(x = 1:3)
    alias <- data
    gen(data, y, x + 1)

    data$x <- 4:6
    expect_false(inherits(data, "dtatools_ref_data"))
    expect_identical(data$x, 4:6)
    expect_identical(as.double(data$y), c(2, 3, 4))
    expect_identical(alias$x, 1:3)

    gen(alias, z, y + 1)
    labelled <- set_variable_labels(alias, x = "X", y = "Y", z = "Z")
    labelled <- set_value_labels(labelled, x = c(One = 1))
    expect_false(inherits(labelled, "dtatools_ref_data"))
    expect_identical(var_label(labelled), list(x = "X", y = "Y", z = "Z"))
    expect_identical(val_labels(labelled$x), c(One = 1))

    dataset_label(alias) <- "updated"
    isolated <- copy_data(alias)
    expect_identical(dataset_label(isolated), "updated")
    expect_identical(names(isolated), c("x", "y", "z"))

    renamed <- alias
    names(renamed) <- c("a", "b", "c")
    expect_false(inherits(renamed, "dtatools_ref_data"))
    expect_identical(names(renamed), c("a", "b", "c"))
})

test_that("sparse compact replacement and generation keep existing payloads", {
    size <- 1000000L
    data <- data.frame(x = stata_byte(rep(1, size)), keep = runif(size))
    keep_trace <- tracemem(data$keep)
    on.exit(untracemem(data$keep), add = TRUE)
    before <- object.size(data$x)

    replace_values(data, x, 2, where = size)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_lte(as.numeric(object.size(data$x)), as.numeric(before) + 1024)
    expect_identical(tracemem(data$keep), keep_trace)

    x_trace <- tracemem(data$x)
    on.exit(untracemem(data$x), add = TRUE)
    gen(data, added, 3)
    expect_identical(tracemem(data$x), x_trace)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$added))
})
