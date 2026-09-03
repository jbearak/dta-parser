test_that("reference mutation exports one coherent API", {
    expect_identical(repl, replace_values)
    expect_identical(
        formals(replace_values),
        as.pairlist(alist(
            data = , ... = , where = NULL, by = NULL, bysort = NULL
        ))
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
    expect_error(replace_values(data, , 0), "unquoted")
    expect_error(replace_values(data, unknown, 0), "does not exist")

    # One string names a column, because `!!name` unquotes to one.
    expect_silent(replace_values(data, "x", 0L))
    expect_identical(data$x, c(0L, 0L))
    expect_silent(gen(data, "quoted", 0))
    expect_identical(as.double(data$quoted), c(0, 0))

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

    expect_error(
        gen(data, from_column, constant),
        "`constant` is both a column and an object"
    )
    gen(data, from_column, .data$constant)
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

    for (constructor in list(identity, dta_byte)) {
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
        where = dta_byte(c(3, 1))
    )
    expect_identical(compact_positions$x, c(9L, 2L, 8L))

    replace_values(
        compact_positions, x, c(6L, 7L, 5L),
        where = dta_long(c(3, 1, 3))
    )
    expect_identical(compact_positions$x, c(6L, 2L, 5L))

    all_rows <- data.frame(x = dta_byte(1:3))
    replace_values(all_rows, x, 4, where = rep(TRUE, 3))
    expect_identical(as.double(all_rows$x), rep(4, 3))

    unchanged <- data$x
    replace_values(data, x, integer(), where = integer())
    expect_identical(data$x, unchanged)

    all_false <- data.frame(x = 1:3)
    replace_values(all_false, x, 9L, where = rep(FALSE, 3))
    expect_identical(all_false$x, 1:3)

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

    for (shaped in list(
        matrix(c(TRUE, FALSE, TRUE, FALSE), nrow = 2),
        array(c(TRUE, FALSE, TRUE, FALSE), dim = c(2, 1, 2))
    )) {
        replace_target <- data.frame(x = 1:4)
        replace_before <- serialize(replace_target, NULL)
        expect_error(
            replace_values(replace_target, x, 0L, where = shaped),
            "logical values or numeric row positions"
        )
        expect_identical(serialize(replace_target, NULL), replace_before)

        generate_target <- data.frame(x = 1:4)
        generate_before <- serialize(generate_target, NULL)
        expect_error(
            gen(generate_target, y, 0L, where = shaped),
            "logical values or numeric row positions"
        )
        expect_identical(serialize(generate_target, NULL), generate_before)
    }
})

test_that("full-dataset values are gathered by selected row", {
    rows <- dta_long(c(5, 2, 5))
    values <- 11:15

    replaced <- data.frame(x = dta_byte(1:5))
    replace_values(replaced, x, values, where = rows)
    expect_identical(as.double(replaced$x), c(1, 12, 3, 4, 15))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(replaced$x))

    generated <- data.frame(x = 1:5)
    gen(generated, y, values, where = rows)
    expect_identical(as.double(generated$y), c(NA, 12, NA, NA, 15))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(generated$y))

    strings <- data.frame(x = 1:5)
    string_values <- structure(letters[1:5], label = "letters")
    gen(strings, y, string_values, where = dta_long(c(3, 1)))
    expect_identical(as.character(strings$y), c("a", "", "c", "", ""))
    expect_identical(attr(strings$y, "label"), "letters")
    expect_identical(attr(strings$y, "stata.string.storage"), "str1")
})

test_that("metadata-bearing numerics remain valid row positions", {
    rows <- set_dta_note(c(3, 1), 2L, "selection note")
    data <- data.frame(value = 1:3)

    replace_values(data, value, c(30L, 10L), where = rows)

    expect_identical(data$value, c(10L, 2L, 30L))

    full_values <- data.frame(value = 1:3)
    replace_values(full_values, value, c(10L, 20L, 30L), where = rows)

    expect_identical(full_values$value, c(10L, 2L, 30L))
})

test_that("compact selected positions use one native patch plan", {
    data <- data.frame(value = dta_byte(rep(1, 10)))
    rows <- dta_long(c(2, 5, 9))
    expect_identical(dtatools:::.reference_row_reads(TRUE), 0)
    replace_values(data, value, c(3, 4, 5), where = rows)
    row_reads <- dtatools:::.reference_row_reads(FALSE)
    expect_gt(row_reads, 0)
    expect_lte(row_reads, 12)
    expect_identical(as.double(data$value[c(2, 5, 9)]), c(3, 4, 5))
})

test_that("excluded full-dataset values do not affect validation", {
    ordinary <- data.frame(x = 1:3)
    replace_values(ordinary, x, c(1.5, 9, Inf), where = 2L)
    expect_identical(ordinary$x, c(1L, 9L, 3L))

    materialized <- data.frame(x = dta_byte(1:3))
    invisible(dtatools:::.force_altrep_materialization(materialized$x))
    replace_values(materialized, x, c(101, 9, 101), where = 2L)
    expect_identical(as.double(materialized$x), c(1, 9, 3))

    strings <- data.frame(text = structure(
        c("a", "b", "c"), stata.string.storage = "str1"
    ))
    replace_values(
        strings, text, c("too wide", "z", "also too wide"), where = 2L
    )
    expect_identical(as.character(strings$text), c("a", "z", "c"))

    zero_selection <- data.frame(text = structure(
        "a", stata.string.storage = "str1"
    ))
    zero_before <- serialize(zero_selection, NULL)
    expect_error(
        replace_values(zero_selection, text, "wide", where = FALSE),
        "do not fit"
    )
    expect_identical(serialize(zero_selection, NULL), zero_before)

    zero_altrep <- data.frame(x = 1:3)
    zero_altrep_before <- serialize(zero_altrep, NULL)
    replace_values(zero_altrep, x, 1L, where = FALSE)
    expect_identical(serialize(zero_altrep, NULL), zero_altrep_before)
    expect_true(dtatools:::.is_altrep(zero_altrep$x))

    generated <- data.frame(x = 1:3)
    declared <- structure(
        c("too wide", "z", "also too wide"),
        stata.string.storage = "str1"
    )
    gen(generated, text, declared, where = 2L)
    expect_identical(as.character(generated$text), c("", "z", ""))
})

test_that("native mutation writers reject untrusted row plans", {
    namespace <- asNamespace("dtatools")
    patch <- get("C_dtatools_patch_vector", namespace)
    generate <- get("C_dtatools_generate_numeric", namespace)
    generate_character <- get(
        "C_dtatools_generate_character", namespace
    )
    generated_attributes <- attributes(dta_byte(double()))

    target <- dta_byte(1:3)
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

test_that("gen rejects unsupported classed numeric results atomically", {
    cases <- list(
        difftime = as.difftime(1:3, units = "hours"),
        integer64 = structure(as.double(1:3), class = "integer64")
    )
    for (name in names(cases)) {
        data <- data.frame(x = 1:3)
        before <- serialize(data, NULL)
        values <- cases[[name]]
        expect_error(
            gen(data, generated, .env$values),
            "does not support this classed numeric result",
            info = name
        )
        expect_identical(serialize(data, NULL), before, info = name)
        expect_false(inherits(data, "dtatools_ref_data"), info = name)
        expect_identical(names(data), "x", info = name)
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

    package_path <- getNamespaceInfo(asNamespace("dtatools"), "path")
    result <- callr::r(
        function(package_path, load_package) {
            load_package(package_path)
            interrupt_patch <- function(compact) {
                size <- 100000L
                target <- if (compact) {
                    dta_float(rep.int(1L, size))
                } else {
                    rep(1, size)
                }
                data <- data.frame(target = target)
                condition <- tryCatch(
                    {
                        dtatools:::.inject_reference_write_interrupt(TRUE)
                        replace_values(data, target, 2)
                        NULL
                    },
                    condition = identity
                )
                dtatools:::.inject_reference_write_interrupt(FALSE)
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
            dictionary_size <- 100000L
            dictionary_path <- tempfile(fileext = ".arrow")
            on.exit(unlink(dictionary_path), add = TRUE)
            replacement_dictionary <- sprintf("value-%05d", 1:10000)
            save_arrow(data.frame(
                target = rep(c("a", "b"), length.out = dictionary_size),
                replacement = rep(
                    replacement_dictionary, length.out = dictionary_size
                )
            ), dictionary_path)
            dictionary_matches <- function(value) {
                chunk_size <- 25000L
                starts <- seq.int(1L, dictionary_size, by = chunk_size)
                all(vapply(starts, function(first) {
                    last <- min(first + chunk_size - 1L, dictionary_size)
                    expected_pair <- if (first %% 2L == 1L) {
                        c("a", "b")
                    } else {
                        c("b", "a")
                    }
                    expected <- rep(
                        expected_pair, length.out = last - first + 1L
                    )
                    identical(as.character(value[first:last]), expected)
                }, logical(1)))
            }
            interrupt_dictionary <- function(
                shared, mutate_proxy = FALSE, source_values = FALSE
            ) {
                source <- read_arrow(dictionary_path, output = "tibble")
                if (mutate_proxy) {
                    alias <- source
                    data <- source
                    data$target <- `var_label<-`(
                        source$target, "Target"
                    )
                    shared <- TRUE
                } else {
                    data <- source
                    alias <- if (shared) {
                        result <- source
                        result$target <- `var_label<-`(
                            source$target, "Alias"
                        )
                        result
                    } else {
                        NULL
                    }
                }
                cache_before <- dtatools:::.dictstring_cached_count(
                    data$target
                )
                alias_cache_before <- if (shared) {
                    dtatools:::.dictstring_cached_count(alias$target)
                } else {
                    cache_before
                }
                values_cache_before <- dtatools:::.dictstring_cached_count(
                    data$replacement
                )
                condition <- tryCatch(
                    {
                        dtatools:::.inject_reference_write_interrupt(TRUE)
                        if (source_values) {
                            replace_values(data, target, replacement)
                        } else {
                            replace_values(data, target, "changed")
                        }
                        NULL
                    },
                    condition = identity
                )
                dtatools:::.inject_reference_write_interrupt(FALSE)
                compact <- dtatools:::.is_unmaterialized_dictstring(
                    data$target
                )
                alias_compact <- !shared ||
                    dtatools:::.is_unmaterialized_dictstring(alias$target)
                cache_after <- if (compact) {
                    dtatools:::.dictstring_cached_count(data$target)
                } else {
                    NA_real_
                }
                alias_cache_after <- if (shared && alias_compact) {
                    dtatools:::.dictstring_cached_count(alias$target)
                } else {
                    cache_after
                }
                values_compact <- dtatools:::.is_unmaterialized_dictstring(
                    data$replacement
                )
                values_cache_after <- if (values_compact) {
                    dtatools:::.dictstring_cached_count(data$replacement)
                } else {
                    NA_real_
                }
                selected <- c(1L, dictionary_size / 2L, dictionary_size)
                sample <- tryCatch(
                    as.character(data$target[selected]),
                    condition = identity
                )
                alias_sample <- if (shared) {
                    tryCatch(
                        as.character(alias$target[selected]),
                        condition = identity
                    )
                } else {
                    c("a", "b", "b")
                }
                list(
                    interrupted = inherits(condition, "interrupt"),
                    compact = compact,
                    cache_before = cache_before,
                    cache_after = cache_after,
                    readable = !inherits(sample, "condition"),
                    sample = if (inherits(sample, "condition")) {
                        character()
                    } else {
                        sample
                    },
                    payload_matches = dictionary_matches(data$target),
                    alias_compact = alias_compact,
                    alias_cache_before = alias_cache_before,
                    alias_cache_after = alias_cache_after,
                    values_compact = values_compact,
                    values_cache_before = values_cache_before,
                    values_cache_after = values_cache_after,
                    alias_readable = !inherits(alias_sample, "condition"),
                    alias_sample = if (inherits(alias_sample, "condition")) {
                        character()
                    } else {
                        alias_sample
                    },
                    alias_payload_matches = !shared ||
                        dictionary_matches(alias$target)
                )
            }
            list(
                compact = interrupt_patch(TRUE),
                ordinary = interrupt_patch(FALSE),
                dictionary = interrupt_dictionary(FALSE),
                shared_dictionary = interrupt_dictionary(TRUE),
                proxy_dictionary = interrupt_dictionary(TRUE, TRUE),
                dictionary_values = interrupt_dictionary(
                    FALSE, source_values = TRUE
                )
            )
        },
        args = list(
            package_path = package_path,
            load_package = load_dtatools_for_subprocess
        ),
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
    for (case in result[c(
        "dictionary", "shared_dictionary", "proxy_dictionary",
        "dictionary_values"
    )]) {
        expect_true(case$interrupted)
        expect_true(case$compact)
        expect_identical(case$cache_after, case$cache_before)
        expect_true(case$readable)
        expect_identical(case$sample, c("a", "b", "b"))
        expect_true(case$payload_matches)
        expect_true(case$alias_compact)
        expect_identical(case$alias_cache_after, case$alias_cache_before)
        expect_true(case$values_compact)
        expect_identical(case$values_cache_after, case$values_cache_before)
        expect_true(case$alias_readable)
        expect_identical(case$alias_sample, c("a", "b", "b"))
        expect_true(case$alias_payload_matches)
    }
})

test_that("native generation interrupts leave reference state unchanged", {
    skip_on_os("windows")
    skip_if_not_installed("callr")

    package_path <- getNamespaceInfo(asNamespace("dtatools"), "path")
    result <- callr::r(
        function(package_path, load_package) {
            load_package(package_path)
            interrupt_generation <- function(character, existing) {
                size <- 20000000L
                data <- data.frame(anchor = dta_byte(.size = size))
                if (existing) gen(data, prior, 1)
                values <- if (character) "x" else seq_len(size)
                before <- serialize(data, NULL)
                names_before <- names(data)
                reference_before <- inherits(data, "dtatools_ref_data")
                parent <- Sys.getpid()
                signal <- parallel::mcparallel({
                    Sys.sleep(0.02)
                    tools::pskill(parent, tools::SIGINT)
                }, silent = TRUE)
                condition <- tryCatch(
                    {
                        gen(data, created, .env$values)
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
                    unchanged = identical(serialize(data, NULL), before),
                    names = identical(names(data), names_before),
                    reference = identical(
                        inherits(data, "dtatools_ref_data"),
                        reference_before
                    )
                )
            }
            interrupt_dictionary_generation <- function() {
                size <- 10000000L
                path <- tempfile(fileext = ".arrow")
                on.exit(unlink(path), add = TRUE)
                dictionary <- sprintf("value-%05d", 1:10000)
                save_arrow(data.frame(
                    source = rep(dictionary, length.out = size)
                ), path)
                source <- read_arrow(path)$source
                data <- data.frame(anchor = dta_byte(.size = size))
                before <- serialize(data, NULL)
                cache_before <- dtatools:::.dictstring_cached_count(source)
                parent <- Sys.getpid()
                signal <- parallel::mcparallel({
                    Sys.sleep(0.02)
                    tools::pskill(parent, tools::SIGINT)
                }, silent = TRUE)
                condition <- tryCatch(
                    {
                        gen(data, created, .env$source)
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
                    unchanged = identical(serialize(data, NULL), before),
                    names = identical(names(data), "anchor"),
                    reference = !inherits(data, "dtatools_ref_data"),
                    source_compact =
                        dtatools:::.is_unmaterialized_dictstring(source),
                    cache_before = cache_before,
                    cache_after =
                        dtatools:::.dictstring_cached_count(source)
                )
            }
            list(
                numeric_first = interrupt_generation(FALSE, FALSE),
                numeric_existing = interrupt_generation(FALSE, TRUE),
                character_first = interrupt_generation(TRUE, FALSE),
                character_existing = interrupt_generation(TRUE, TRUE),
                dictionary = interrupt_dictionary_generation()
            )
        },
        args = list(
            package_path = package_path,
            load_package = load_dtatools_for_subprocess
        ),
        libpath = .libPaths(),
        timeout = 120
    )

    for (case in result) {
        expect_true(case$interrupted)
        expect_true(case$unchanged)
        expect_true(case$names)
        expect_true(case$reference)
    }
    expect_true(result$dictionary$source_compact)
    expect_identical(
        result$dictionary$cache_after,
        result$dictionary$cache_before
    )
})

test_that("generic ALTREP detachment interrupts before installation", {
    skip_on_os("windows")
    skip_if_not_installed("callr")

    package_path <- getNamespaceInfo(asNamespace("dtatools"), "path")
    result <- callr::r(
        function(package_path, load_package) {
            load_package(package_path)
            size <- 20000000L
            data <- data.frame(x = seq_len(size))
            before <- serialize(data, NULL)
            parent <- Sys.getpid()
            signal <- parallel::mcparallel({
                Sys.sleep(0.01)
                tools::pskill(parent, tools::SIGINT)
            }, silent = TRUE)
            condition <- tryCatch(
                {
                    replace_values(data, x, 2L)
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
                unchanged = identical(serialize(data, NULL), before),
                altrep = dtatools:::.is_altrep(data$x),
                range = range(data$x),
                sum = sum(data$x),
                size = size
            )
        },
        args = list(
            package_path = package_path,
            load_package = load_dtatools_for_subprocess
        ),
        libpath = .libPaths(),
        timeout = 120
    )

    expect_true(result$interrupted)
    expect_true(result$unchanged)
    expect_true(result$altrep)
    expect_identical(result$range, c(1L, result$size))
    expect_equal(result$sum, result$size * (result$size + 1) / 2)
})

test_that("compact replacement patches every storage without materializing", {
    constructors <- list(
        byte = dta_byte,
        int = dta_int,
        long = dta_long,
        float = dta_float
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
        expect_identical(dta_storage_type(data$target), storage)
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
    data <- data.frame(x = dta_byte(c(1, 2, 3)))
    for (bad in list(101, 1.5, NaN, Inf)) {
        before <- serialize(data$x, NULL)
        expect_error(replace_values(data, x, bad, where = 2))
        expect_identical(serialize(data$x, NULL), before)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    }
    expect_error(replace_values(data, x, 101, where = 2), "dta_int")
    expect_identical(dta_storage_type(data$x), "byte")
})

test_that("compact replacement updates the missing-value cache", {
    data <- data.frame(x = dta_byte(1:3))
    expect_false(anyNA(data$x))
    replace_values(data, x, NA_real_, where = 2)
    expect_true(anyNA(data$x))
    replace_values(data, x, 2, where = 2)
    expect_false(anyNA(data$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))

    late_missing <- data.frame(x = dta_byte(c(1, 2, NA_real_)))
    replace_values(late_missing, x, 9, where = 1)
    expect_true(anyNA(late_missing$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(late_missing$x))

    duplicate <- data.frame(x = dta_byte(1:3))
    replace_values(
        duplicate, x, c(NA_real_, 2), where = c(1, 1)
    )
    expect_false(anyNA(duplicate$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(duplicate$x))

    generated <- data.frame(x = 1:3)
    gen(generated, y, dta_byte(1), where = 2)
    expect_true(anyNA(generated$y))
    replace_values(generated, y, 1, where = c(1, 3))
    expect_false(anyNA(generated$y))

    restored <- unserialize(serialize(
        data.frame(x = dta_byte(c(NA_real_, 1))), NULL
    ))
    replace_values(restored, x, 1, where = 1)
    expect_false(anyNA(restored$x))

    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    save_arrow(data.frame(x = dta_byte(c(NA_real_, 1))), arrow_path)
    arrow <- read_arrow(arrow_path)
    replace_values(arrow, x, 1, where = 1)
    expect_false(anyNA(arrow$x))
})

test_that("DTA-loaded compact and temporal columns use native patching", {
    data <- read_dta(fixture("all_types_v118.dta"))
    compact <- names(data)[vapply(
        data,
        function(column) isTRUE(dta_storage_type(column) %in%
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
    replace_values(data, strings, NA_character_, where = 1)
    replace_values(data, dates, as.Date("2021-01-01"), where = 2)
    expect_identical(data$doubles, c(1, 4, 3))
    expect_identical(data$integers, c(1L, 8L, 3L))
    expect_identical(data$logicals, c(FALSE, FALSE, TRUE))
    expect_identical(data$strings, c("", "b", "z"))
    expect_identical(data$dates[[2]], as.Date("2021-01-01"))

    self_replacement <- data.frame(text = c(NA_character_, "value"))
    replace_values(self_replacement, text, text)
    expect_identical(self_replacement$text, c("", "value"))

    compact <- dta_int(1:3)
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

test_that("base numeric ALTREP columns remain internally consistent", {
    columns <- list(
        integer = seq_len(1000L),
        double = as.double(seq_len(1000L))
    )
    for (name in names(columns)) {
        data <- data.frame(x = columns[[name]])
        data_alias <- data
        column_alias <- data$x
        subset_alias <- data["x"]
        expect_true(dtatools:::.is_altrep(data$x), info = name)
        replacement <- if (name == "integer") 2L else 2
        replace_values(data, x, replacement)
        expect_identical(range(data$x), c(replacement, replacement), info = name)
        expect_equal(sum(data$x), 2000, info = name)
        expect_identical(data_alias$x, data$x, info = name)
        expect_identical(column_alias, columns[[name]], info = name)
        expect_identical(subset_alias$x, columns[[name]], info = name)
        restored <- unserialize(serialize(data, NULL))
        expect_identical(
            range(restored$x), c(replacement, replacement), info = name
        )
        expect_equal(sum(restored$x), 2000, info = name)
    }
})

test_that("gen appends one variable with Stata missing and storage rules", {
    data <- tibble::tibble(x = c(1, 2, 3), eligible = c(TRUE, FALSE, TRUE))
    alias <- data
    result <- withVisible(gen(data, generated, x * 2, where = eligible))
    expect_false(result$visible)
    expect_identical(names(data), c("x", "eligible", "generated"))
    expect_identical(names(alias), names(data))
    expect_identical(as.double(data$generated), c(2, NA, 6))
    expect_identical(dta_storage_type(data$generated), "double")
    expect_s3_class(data, "tbl_df")
    expect_equal(dim(data), c(3L, 3L))
    expect_error(gen(data, generated, 1), "already exists")
    expect_identical(ncol(data), 3L)

    gen(data, declared, dta_int(x))
    expect_identical(dta_storage_type(data$declared), "int")
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
    expect_identical(dta_storage_type(temporal$date), "float")
    expect_identical(dta_storage_type(temporal$datetime), "double")

    compact_source <- data.frame(x = dta_byte(1:3))
    gen(compact_source, y, x)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact_source$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact_source$y))
    expect_identical(dta_storage_type(compact_source$y), "byte")
    expect_identical(as.double(compact_source$y), c(1, 2, 3))

    integer_source <- data.frame(x = 1:3)
    gen(integer_source, y, x)
    expect_identical(dtatools:::.metadata_proxy_depth(integer_source$y), 0L)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(integer_source$y))
    replace_values(integer_source, y, 4, where = 1L)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(integer_source$y))
    expect_identical(as.double(integer_source$y), c(4, 2, 3))

    labelled <- dta_byte(c(1, 2, 3))
    attr(labelled, "label") <- "Generated label"
    attr(labelled, "labels") <- c(One = 1)
    attr(labelled, "format.stata") <- "%8.0g"
    gen(data, labelled, labelled)
    expect_identical(attr(data$labelled, "label"), "Generated label")
    expect_identical(attr(data$labelled, "labels"), c(One = 1))
    expect_identical(attr(data$labelled, "format.stata"), "%8.0g")

    authored <- set_var_labels(
        set_val_labels(c(1, 2, 3), One = 1),
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
    gen(strings, y, authored_string, where = dta_long(c(3, 1, 3)))
    expect_identical(as.character(strings$y), c("one", "", "three"))
    expect_identical(attr(strings$y, "label"), "Authored string")
    expect_identical(attr(strings$y, "stata.string.storage"), "str5")

    full_strings <- data.frame(x = 1:3)
    gen(full_strings, y, c("one", "long", NA_character_))
    expect_identical(as.character(full_strings$y), c("one", "long", ""))
    expect_identical(
        attr(full_strings$y, "stata.string.storage"), "str4"
    )

    duplicate <- data.frame(x = 1:3)
    invisible(dtatools:::.reference_row_reads(TRUE))
    gen(
        duplicate, y, c("overwritten", "x"),
        where = c(1, 1)
    )
    duplicate_row_reads <- dtatools:::.reference_row_reads(FALSE)
    expect_identical(as.character(duplicate$y), c("x", "", ""))
    expect_identical(attr(duplicate$y, "stata.string.storage"), "str1")
    expect_gt(duplicate_row_reads, 0)
    expect_lte(duplicate_row_reads, 6)

    too_narrow <- structure("wide", stata.string.storage = "str2")
    expect_error(gen(strings, too_wide, too_narrow), "do not fit")
    expect_false("too_wide" %in% names(strings))

    wide <- paste(rep("x", 2046), collapse = "")
    gen(data, long_string, wide)
    expect_identical(attr(data$long_string, "stata.string.storage"), "strL")
})

test_that("gen preserves metadata on otherwise supported numeric classes", {
    sources <- list(
        numeric = c(1, 2, 3),
        date = as.Date("2020-01-01") + 0:2,
        labelled = set_val_labels(c(1, 2, 1), One = 1, Two = 2)
    )
    for (kind in names(sources)) {
        source <- set_dta_note(sources[[kind]], 3L, "source note")
        source <- set_dta_characteristic(source, "source", kind)
        data <- data.frame(anchor = 1:3)

        gen(data, copied, .env$source)

        expect_identical(
            dta_notes(data$copied), c(`3` = "source note"), info = kind
        )
        expect_identical(
            dta_characteristics(data$copied), c(source = kind), info = kind
        )
        if (identical(kind, "date")) {
            expect_s3_class(data$copied, "stata_date")
        }
        if (identical(kind, "labelled")) {
            expect_identical(val_labels(data$copied), c(One = 1, Two = 2))
        }
    }
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

test_that("repeated gen appends ordered reference-state bindings", {
    data <- data.frame(anchor = 1:2)
    for (index in seq_len(100L)) {
        name <- rlang::sym(sprintf("generated_%03d", index))
        gen(data, !!name, anchor + .env$index)
    }
    expect_identical(
        names(data),
        c("anchor", sprintf("generated_%03d", seq_len(100L)))
    )
    expect_identical(as.double(data$generated_001), c(2, 3))
    expect_identical(as.double(data$generated_100), c(101, 102))
    replace_values(data, generated_050, 0, where = 1)
    expect_identical(as.double(data$generated_050), c(0, 52))
})

test_that("copy_data isolates every mutable column backing", {
    data <- data.frame(
        compact = dta_long(c(1, tagged_missing("a"), 3)),
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

    names_alias <- data.frame(name = names(isolated))
    replace_values(names_alias, name, "changed", where = 1)
    expect_identical(
        names(data), c("compact", "ordinary", "string", "generated")
    )
    expect_identical(names(isolated), c("changed", "ordinary", "string"))

    grouped <- dplyr::group_by(
        data.frame(group = c("a", "b"), value = 1:2), group
    )
    grouped_copy <- copy_data(grouped)
    copied_groups <- attr(grouped_copy, "groups", exact = TRUE)
    replace_values(copied_groups, group, "changed", where = 1)
    expect_identical(
        attr(grouped, "groups", exact = TRUE)$group,
        c("a", "b")
    )
    expect_identical(
        attr(grouped_copy, "groups", exact = TRUE)$group,
        c("changed", "b")
    )

    reference_attribute <- data.frame(value = 1)
    attr(reference_attribute, "owner") <- list(new.env(parent = emptyenv()))
    expect_error(
        copy_data(reference_attribute),
        "cannot isolate environments"
    )

    embedded_environment <- new.env(parent = emptyenv())
    reference_call <- as.call(list(
        as.name("identity"), embedded_environment
    ))
    reference_column <- data.frame(
        value = I(list(reference_call))
    )
    expect_error(
        copy_data(reference_column),
        "cannot isolate environments"
    )

    as.list.hidden_contents <- function(x, ...) list()
    hidden_contents_list <- structure(
        list(embedded_environment), class = "hidden_contents"
    )
    hidden_contents_column <- data.frame(
        value = I(list(hidden_contents_list))
    )
    expect_error(
        copy_data(hidden_contents_column),
        "cannot isolate environments"
    )
    hidden_contents_call <- structure(
        reference_call, class = "hidden_contents"
    )
    hidden_contents_call_column <- data.frame(
        value = I(list(hidden_contents_call))
    )
    expect_error(
        copy_data(hidden_contents_call_column),
        "cannot isolate environments"
    )

    length.hidden_length <- function(x) 0L
    hidden_length_list <- structure(
        list(embedded_environment), class = "hidden_length"
    )
    hidden_length_column <- data.frame(value = I(list(hidden_length_list)))
    expect_error(
        copy_data(hidden_length_column),
        "cannot isolate environments"
    )

    hidden_length_call <- structure(reference_call, class = "hidden_length")
    hidden_length_call_column <- data.frame(
        value = I(list(hidden_length_call))
    )
    expect_error(
        copy_data(hidden_length_call_column),
        "cannot isolate environments"
    )

    embedded_bytecode <- compiler::compile(as.call(list(
        as.name("identity"), embedded_environment
    )))
    expect_identical(typeof(embedded_bytecode), "bytecode")
    bytecode_column <- data.frame(value = I(list(embedded_bytecode)))
    expect_error(
        copy_data(bytecode_column),
        "cannot isolate environments"
    )
})

test_that("subsets, metadata proxies, and serialized data stay isolated", {
    source <- data.frame(x = dta_int(c(1, 2, 3)))
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
        source <- dta_byte(rep(1, 100))
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
    first <- data.frame(x = dtatools:::.metadata_copy(dta_byte(1:3)))
    replace_values(first, x, 4, where = 1)
    second <- data.frame(x = dtatools:::.metadata_copy(first$x))

    replace_values(first, x, 7, where = 1)

    expect_identical(as.double(first$x), c(7, 2, 3))
    expect_identical(as.double(second$x), c(4, 2, 3))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(second$x))
})

test_that("metadata copies remain isolated from later source patches", {
    compact_source <- data.frame(x = dta_byte(1:3))
    compact_copy <- copy_data(compact_source)
    set_var_labels(compact_copy, x = "Copy")
    replace_values(compact_source, x, 9, where = 1)
    expect_identical(as.double(compact_source$x), c(9, 2, 3))
    expect_identical(as.double(compact_copy$x), c(1, 2, 3))

    materialized_source <- data.frame(x = dta_byte(1:3))
    materialized_copy <- copy_data(materialized_source)
    set_var_labels(materialized_copy, x = "Copy")
    invisible(dtatools:::.force_altrep_materialization(
        materialized_source$x
    ))
    replace_values(materialized_source, x, 9, where = 1)
    expect_identical(as.double(materialized_source$x), c(9, 2, 3))
    expect_identical(as.double(materialized_copy$x), c(1, 2, 3))

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    string_source <- read_arrow(path, output = "tibble")
    expect_true(dtatools:::.is_unmaterialized_dictstring(
        string_source$text
    ))
    string_copy <- copy_data(string_source)
    set_var_labels(string_copy, text = "Copy")
    replace_values(string_source, text, "changed", where = 1)
    expect_identical(as.character(string_source$text), c("changed", "b", "a"))
    expect_true(dtatools:::.is_unmaterialized_dictstring(string_copy$text))
    expect_identical(as.character(string_copy$text), c("a", "b", "a"))

    missing_source <- read_arrow(path)
    missing_alias <- copy_data(missing_source)
    set_var_labels(missing_alias, text = "Copy")
    replace_values(missing_source, text, NA_character_, where = 2)
    expect_identical(as.character(missing_source$text), c("a", "", "a"))
    expect_identical(as.character(missing_alias$text), c("a", "b", "a"))

    # A dibble declares the Arrow string as str1 and replace_values()
    # holds it to that width, so the widening cases use a tibble.
    full_source <- read_arrow(path, output = "tibble")
    full_copy <- copy_data(full_source)
    set_var_labels(full_copy, text = "Copy")
    replace_values(full_source, text, "changed")
    expect_identical(
        as.character(full_source$text), rep("changed", 3)
    )
    expect_true(dtatools:::.is_unmaterialized_dictstring(full_copy$text))
    expect_identical(as.character(full_copy$text), c("a", "b", "a"))

    direct_identity <- read_arrow(path, output = "tibble")
    direct_cache <- dtatools:::.dictstring_cached_count(direct_identity$text)
    replace_values(direct_identity, text, text)
    expect_identical(
        dtatools:::.dictstring_cached_count(direct_identity$text),
        direct_cache
    )
    expect_identical(as.character(direct_identity$text), c("a", "b", "a"))

    proxy_identity <- data.frame(
        text = dtatools:::.metadata_copy(
            read_arrow(path, output = "tibble")$text
        )
    )
    proxy_cache <- dtatools:::.dictstring_cached_count(proxy_identity$text)
    replace_values(proxy_identity, text, text)
    expect_identical(
        dtatools:::.dictstring_cached_count(proxy_identity$text),
        proxy_cache
    )
    expect_identical(as.character(proxy_identity$text), c("a", "b", "a"))

    dependent_source <- read_arrow(path)
    dependent_proxy <- dtatools:::.metadata_copy(dependent_source$text)
    dependent_cache <- dtatools:::.dictstring_cached_count(dependent_proxy)
    replace_values(dependent_source, text, .env$dependent_proxy)
    expect_identical(
        dtatools:::.dictstring_cached_count(dependent_proxy),
        dependent_cache
    )
    expect_identical(
        as.character(dependent_source$text), c("a", "b", "a")
    )

    wide_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(wide_path), add = TRUE)
    save_arrow(data.frame(text = c("wide", "x", "wide")), wide_path)
    dictionary_values <- read_arrow(wide_path)$text
    values_cache <- dtatools:::.dictstring_cached_count(dictionary_values)
    narrow <- data.frame(text = structure(
        c("a", "b", "c"), stata.string.storage = "str1"
    ))
    narrow_before <- serialize(narrow, NULL)
    expect_error(
        replace_values(narrow, text, .env$dictionary_values),
        "do not fit"
    )
    expect_identical(serialize(narrow, NULL), narrow_before)
    expect_identical(
        dtatools:::.dictstring_cached_count(dictionary_values), values_cache
    )
    replace_values(
        narrow, text, .env$dictionary_values, where = 2L
    )
    expect_identical(as.character(narrow$text), c("a", "x", "c"))
    expect_identical(
        dtatools:::.dictstring_cached_count(dictionary_values), values_cache
    )

    generated_values <- read_arrow(wide_path)$text
    generated_cache <- dtatools:::.dictstring_cached_count(generated_values)
    generated <- data.frame(anchor = 1:3)
    gen(generated, text, .env$generated_values)
    expect_identical(
        dtatools:::.dictstring_cached_count(generated_values),
        generated_cache
    )
    expect_identical(as.character(generated$text), c("wide", "x", "wide"))

    scalar_values <- read_arrow(wide_path, n_max = 1)$text
    scalar_cache <- dtatools:::.dictstring_cached_count(scalar_values)
    scalar_generated <- data.frame(anchor = 1:3)
    gen(scalar_generated, text, .env$scalar_values)
    scalar_replaced <- data.frame(text = rep("", 3))
    replace_values(scalar_replaced, text, .env$scalar_values)
    expect_identical(
        dtatools:::.dictstring_cached_count(scalar_values), scalar_cache
    )
    expect_identical(as.character(scalar_generated$text), rep("wide", 3))
    expect_identical(as.character(scalar_replaced$text), rep("wide", 3))

    narrow_generated_values <- dtatools:::.metadata_copy(
        read_arrow(wide_path)$text
    )
    attr(narrow_generated_values, "stata.string.storage") <- "str1"
    expect_true(dtatools:::.is_unmaterialized_dictstring(
        narrow_generated_values
    ))
    narrow_generated_cache <- dtatools:::.dictstring_cached_count(
        narrow_generated_values
    )
    before_generated <- serialize(generated, NULL)
    expect_error(
        gen(generated, rejected, .env$narrow_generated_values),
        "do not fit"
    )
    expect_identical(serialize(generated, NULL), before_generated)
    expect_identical(
        dtatools:::.dictstring_cached_count(narrow_generated_values),
        narrow_generated_cache
    )
})

test_that("writable access detaches shared materialized payloads", {
    numeric <- dta_byte(1:3)
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

test_that("is_missing masks preserve dictionary-string caches and aliases", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(
        text = rep(c("", "seen", "other"), 2L),
        nullable = c("present", NA_character_, rep("present", 4L)),
        target = seq_len(6L)
    ), path)

    replaced <- read_arrow(path, output = "tibble")
    replaced_alias <- replaced
    replaced_text_alias <- replaced$text
    replaced_cache <- dtatools:::.dictstring_cached_count(replaced$text)
    replace_values(
        replaced, target, 99L, where = is_missing(text, nullable)
    )
    expect_identical(
        replaced$target, c(99L, 99L, 3L, 99L, 5L, 6L)
    )
    expect_identical(replaced_alias$target, replaced$target)
    expect_identical(
        dtatools:::.dictstring_cached_count(replaced$text), replaced_cache
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(replaced_alias$text),
        replaced_cache
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(replaced_text_alias),
        replaced_cache
    )
    expect_true(dtatools:::.is_unmaterialized_dictstring(replaced$text))

    generated <- read_arrow(path)
    generated_alias <- generated
    generated_text_alias <- generated$text
    generated_cache <- dtatools:::.dictstring_cached_count(generated$text)
    gen(
        generated, missing_row, 7L,
        where = is_missing(text, nullable)
    )
    expect_identical(
        as.double(generated$missing_row),
        c(7, 7, NA, 7, NA, NA)
    )
    expect_identical(
        as.double(generated_alias$missing_row),
        as.double(generated$missing_row)
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(generated$text), generated_cache
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(generated_alias$text),
        generated_cache
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(generated_text_alias),
        generated_cache
    )
    expect_true(dtatools:::.is_unmaterialized_dictstring(generated$text))
})

test_that("materialized metadata-proxy copies remain independent", {
    numeric <- dtatools:::.metadata_copy(dta_byte(1:3))
    invisible(dtatools:::.force_altrep_materialization(numeric))
    numeric_copy <- dtatools:::.metadata_copy(numeric)
    numeric_data <- data.frame(x = numeric)
    replace_values(numeric_data, x, 9, where = 1)
    expect_identical(as.double(numeric_data$x), c(9, 2, 3))
    expect_identical(as.double(numeric_copy), c(1, 2, 3))

    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(text = c("a", "b", "a")), path)
    string <- dtatools:::.metadata_copy(
        read_arrow(path, output = "tibble")$text
    )
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
    string <- read_arrow(path, output = "tibble")$text
    retained <- list(
        numeric = materialized_chain(dta_byte(1:3), "numeric"),
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
    source <- read_arrow(path, output = "tibble")
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
    data <- data.frame(x = dta_byte(1:3))
    gen(data, y, dta_int(x * 10))
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
        as.integer(dplyr::summarise(grouped, n = dplyr::n())$n),
        rep(1L, 3)
    )
    expect_s3_class(dplyr::rowwise(tbl), "rowwise_df")
    combined <- dplyr::bind_rows(
        tibble::as_tibble(tbl), tibble::as_tibble(tbl)
    )
    expect_equal(dim(combined), c(6L, 2L))
})

test_that("target-vector aliases observe replacement while row subsets isolate", {
    column <- dta_int(1:3)
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

test_that("rowwise inputs fail before reference mutation", {
    rowwise <- dplyr::rowwise(tibble::tibble(x = 1:2))
    before <- serialize(rowwise, NULL)
    expect_error(replace_values(rowwise, x, 1L), "ungrouped")
    expect_error(gen(rowwise, y, 1L), "ungrouped")
    expect_identical(serialize(rowwise, NULL), before)

    isolated <- copy_data(rowwise)
    expect_identical(class(isolated), class(rowwise))
    expect_identical(as.data.frame(isolated), as.data.frame(rowwise))
})

test_that(".n and .N describe the whole dataset without groups", {
    data <- data.frame(x = c(5, 6, 7))
    gen(data, row = .n)
    gen(data, count = .N)
    expect_identical(as.double(data$row), c(1, 2, 3))
    expect_identical(as.double(data$count), c(3, 3, 3))

    repl(data, x = 0, where = .n == .N)
    expect_identical(data$x, c(5, 6, 0))
    repl(data, x = -1, where = ~ .n == 1)
    expect_identical(data$x, c(-1, 6, 0))

    # A caller object named `.N` is not a shadowing conflict.
    .N <- 99
    gen(data, again = .N)
    expect_identical(as.double(data$again), c(3, 3, 3))

    # `.N` on the right of a comparison stays off the fused patch path
    # and still selects correctly.
    compact <- data.frame(x = dta_int(1:4))
    repl(compact, x = 0L, where = x == .N)
    expect_identical(as.double(compact$x), c(1, 2, 3, 0))
})

test_that("by evaluates where and values within each group", {
    data <- data.frame(id = c(2, 1, 2, 1, 3), x = c(1, 2, 3, 4, 5))
    gen(data, n = .n, by = id)
    gen(data, count = .N, by = id)
    expect_identical(as.double(data$n), c(1, 1, 2, 2, 1))
    expect_identical(as.double(data$count), c(2, 2, 2, 2, 1))

    gen(data, centred = x - mean(x), by = id)
    expect_identical(as.double(data$centred), c(-1, -1, 1, 1, 0))

    # Rows a group's `where` leaves out hold missing after gen(), and are
    # untouched by repl().
    gen(data, high = x, where = x > 2, by = id)
    expect_identical(as.double(data$high), c(NA, NA, 3, 4, 5))
    repl(data, x = 0, where = x == max(x), by = id)
    expect_identical(data$x, c(1, 2, 0, 0, 0))

    # Numeric positions count within the group.
    gen(data, first = 1, where = 1, by = id)
    expect_identical(as.double(data$first), c(1, 1, NA, NA, 1))

    # Row order is the dataset's own; nothing was sorted.
    expect_identical(data$id, c(2, 1, 2, 1, 3))
    expect_identical(names(data), c(
        "id", "x", "n", "count", "centred", "high", "first"
    ))
})

test_that("by accepts every column-name spelling", {
    make <- function() data.frame(
        g1 = c(1, 1, 2, 2), g2 = c("a", "b", "a", "a"), x = 1:4
    )
    # (1,a) (1,b) (2,a) (2,a): the fourth row is the second of its group.
    expected_pair <- c(1, 1, 1, 2)

    single <- make()
    gen(single, n = .N, by = g1)
    expect_identical(as.double(single$n), c(2, 2, 2, 2))

    pair <- make()
    gen(pair, n = .n, by = c(g1, g2))
    expect_identical(as.double(pair$n), expected_pair)

    strings <- make()
    gen(strings, n = .n, by = c("g1", "g2"))
    expect_identical(as.double(strings$n), expected_pair)

    name <- "g1"
    injected <- make()
    gen(injected, n = .N, by = !!name)
    expect_identical(as.double(injected$n), c(2, 2, 2, 2))

    runtime <- make()
    gen(runtime, n = .N, by = .(name))
    expect_identical(as.double(runtime$n), c(2, 2, 2, 2))

    names <- c("g1", "g2")
    vector_injected <- make()
    gen(vector_injected, n = .n, by = !!names)
    expect_identical(as.double(vector_injected$n), expected_pair)

    bad <- make()
    expect_error(gen(bad, n = 1, by = absent), "does not exist")
    expect_error(gen(bad, n = 1, by = c()), "at least one column")
    expect_error(gen(bad, n = 1, by = g1 + 1), "column names")
    expect_error(gen(bad, n = 1, by = .(1)), "nonempty, non-missing string")
    expect_false("n" %in% names(bad))
})

test_that("groups follow Stata's by order, not data.table's", {
    # data.table applies `i` first, so `.N` counts the selected rows and
    # `.n == .N` would mark the last *selected* row of each group. Stata
    # forms the group first: `.N` is the group's size and the row must be
    # the group's last row *and* pass the condition.
    data <- data.frame(id = c(1, 1, 2, 2), v = c(5, 1, 1, 5))
    gen(data, last = 0)
    repl(data, last = 1, where = .n == .N & v < 3, by = id)
    expect_identical(as.double(data$last), c(0, 1, 0, 0))

    .datatable.aware <- TRUE
    reference <- data.table::as.data.table(
        data.frame(id = c(1, 1, 2, 2), v = c(5, 1, 1, 5), last = 0)
    )
    reference[v < 3, last := as.double(seq_len(.N) == .N), by = id]
    expect_identical(reference$last, c(0, 1, 1, 0))
    expect_false(identical(as.double(data$last), reference$last))

    # `.N` under a `where` is still the group's row count.
    counts <- data.frame(id = c(1, 1, 2, 2), v = c(5, 1, 1, 5))
    gen(counts, n = .N, where = v < 3, by = id)
    expect_identical(as.double(counts$n), c(NA, 2, 2, NA))
})

test_that("per-group value sizes must be 1, the selection, or .N", {
    data <- data.frame(id = c(1, 1, 2), x = 1:3)
    expect_error(
        gen(data, y = 1:3, by = id),
        paste0(
            "size 3 in group id = 1; expected size 1, the group's ",
            "selected-row count \\(2\\), or the group's row count \\(2\\)"
        )
    )
    expect_false("y" %in% names(data))

    expect_error(
        repl(data, x = c(1L, 2L), where = x == 3, by = id),
        "size 2 in group id = 2"
    )
    expect_identical(data$x, 1:3)

    # A group that selects no rows may evaluate `values` to `NULL`; the
    # empty piece must stay aligned with its rows rather than vanish.
    sparse <- data.frame(id = c(1, 1, 2, 2), x = c(1, 2, 3, 4))
    repl(sparse, x = if (.N == 2 && any(x > 2)) 0 else NULL,
         where = x > 2, by = id)
    expect_identical(sparse$x, c(1, 2, 0, 0))

    # Within a group, a `.N`-length value is indexed by the selection.
    pairs <- data.frame(id = c(1, 1, 2, 2), x = 1:4)
    gen(pairs, z = c(10, 20), where = .n == 2, by = id)
    expect_identical(as.double(pairs$z), c(NA, 20, NA, 20))

    strings <- data.frame(id = c("a", "a", "b"), x = 1:3)
    expect_error(gen(strings, y = 1:3, by = id), 'group id = "a"')
})

test_that("missing values in a by column form their own groups", {
    data <- data.frame(
        id = dta_byte(c(1, NA, 1, NA, 2, NA)), x = dta_int(1:6)
    )
    data$id[4] <- tagged_missing("a")
    gen(data, n = .N, by = id)
    # `.` and `.a` are distinct groups, as in Stata.
    expect_identical(as.double(data$n), c(2, 2, 2, 1, 1, 2))

    # Groups are visited in order of first appearance, so `.a` (one row)
    # is the first group two values do not fit.
    expect_error(gen(data, y = 1:2, by = id), "group id = \\.a;")

    plain <- data.frame(id = c(NA, 1, NA, 1), x = 1:4)
    gen(plain, n = .N, by = id)
    expect_identical(as.double(plain$n), c(2, 2, 2, 2))
    expect_error(gen(plain, y = 1:3, by = id), "group id = \\.;")
})

test_that("bysort sorts by reference and then groups", {
    data <- data.frame(id = c(2, 1, 2, 1), t = c(1, 2, 2, 1), x = 1:4)
    alias <- data
    repl(data, x = 0L, where = t == 1, bysort = c(id, t))
    expect_identical(data$id, c(1, 1, 2, 2))
    expect_identical(data$t, c(1, 2, 1, 2))
    expect_identical(data$x, c(0L, 2L, 0L, 3L))
    # Sorting on both keys and then grouping by both leaves one row per
    # group here, so `.n == 1` everywhere; grouping by `id` alone after a
    # two-key sort is a preceding sort plus `by`.
    gen(data, first = .n == 1, bysort = c(id, t))
    expect_identical(as.double(data$first), c(1, 1, 1, 1))
    expect_identical(alias$x, data$x)
    expect_identical(alias$id, data$id)

    # Stata total order puts `.` and `.a` after every finite value.
    compact <- data.frame(
        id = dta_byte(c(NA, 2, 1, NA)), x = dta_int(1:4)
    )
    compact$id[1] <- tagged_missing("a")
    gen(compact, n = .n, bysort = id)
    expect_identical(as.double(compact$x), c(3, 2, 4, 1))
    expect_identical(as.double(compact$n), c(1, 1, 1, 1))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$x))

    # An already sorted dataset is left alone, and `by` never sorts.
    sorted <- data.frame(id = c(1, 1, 2), x = 1:3)
    gen(sorted, n = .n, bysort = id)
    expect_identical(sorted$x, 1:3)
    unsorted <- data.frame(id = c(2, 1), x = 1:2)
    gen(unsorted, n = .n, by = id)
    expect_identical(unsorted$id, c(2, 1))

    name <- "id"
    runtime <- data.frame(id = c(2, 1), x = 1:2)
    gen(runtime, n = .n, bysort = .(name))
    expect_identical(runtime$id, c(1, 2))
    injected <- data.frame(id = c(2, 1), x = 1:2)
    gen(injected, n = .n, bysort = !!name)
    expect_identical(injected$id, c(1, 2))
})

test_that("by and bysort are exclusive and reject a grouped input", {
    data <- data.frame(id = c(1, 2), x = 1:2)
    expect_error(gen(data, y = 1, by = id, bysort = id), "not both")
    expect_error(repl(data, x = 1L, by = id, bysort = id), "not both")

    grouped <- dplyr::group_by(tibble::tibble(id = c(1, 2), x = 1:2), id)
    before <- serialize(grouped, NULL)
    expect_error(
        gen(grouped, y = 1, by = id),
        "`data` is already grouped; drop `by`/`bysort` or ungroup"
    )
    expect_error(repl(grouped, x = 1L, bysort = id), "already grouped")
    expect_identical(serialize(grouped, NULL), before)
})

test_that("a grouped tibble supplies the assignment groups", {
    grouped <- dplyr::group_by(
        tibble::tibble(id = c(1, 2, 1, 3), x = c(1, 2, 3, 4)), id
    )
    gen(grouped, total = sum(x))
    gen(grouped, n = .n)
    expect_identical(as.double(grouped$total), c(4, 2, 4, 4))
    expect_identical(as.double(grouped$n), c(1, 1, 2, 1))
    repl(grouped, x = 0, where = .n == .N)
    expect_identical(as.double(grouped$x), c(1, 0, 0, 0))
    expect_s3_class(grouped, "grouped_df")
    expect_identical(dplyr::group_vars(grouped), "id")
    expect_identical(
        as.integer(dplyr::summarise(grouped, n = dplyr::n())$n),
        c(2L, 1L, 1L)
    )

    # `.drop = FALSE` may record empty groups; they contribute nothing.
    factor_grouped <- dplyr::group_by(
        tibble::tibble(f = factor(c("a", "a"), levels = c("a", "b")), x = 1:2),
        f, .drop = FALSE
    )
    gen(factor_grouped, n = .N)
    expect_identical(as.double(factor_grouped$n), c(2, 2))

    isolated <- copy_data(grouped)
    expect_s3_class(isolated, "grouped_df")
    expect_identical(dplyr::group_vars(isolated), "id")
    expect_identical(as.data.frame(isolated), as.data.frame(grouped))
})

test_that("compact targets stay compact under by", {
    data <- data.frame(id = c(1, 1, 2, 2), x = dta_int(1:4))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    repl(data, x = 0L, where = .n == .N, by = id)
    expect_identical(as.double(data$x), c(1, 0, 3, 0))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))

    repl(data, x = dta_int(9L), by = id)
    expect_identical(as.double(data$x), c(9, 9, 9, 9))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_error(repl(data, x = 1e6, where = .n == 1, by = id), "int")
    expect_identical(as.double(data$x), c(9, 9, 9, 9))

    gen(data, y = dta_byte(.n), by = id)
    expect_identical(dta_storage_type(data$y), "byte")
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$y))
})

test_that("data.table containers support by and bysort", {
    table <- data.table::data.table(id = c(2, 1, 2), x = c(1, 2, 3))
    gen(table, total = sum(x), by = id)
    expect_identical(as.double(table$total), c(4, 2, 4))
    # Group 2 is rows 1 and 3, group 1 is row 2 alone.
    repl(table, x = 0, where = .n == .N, by = id)
    expect_identical(table$x, c(1, 0, 0))
    expect_s3_class(table, "data.table")
    expect_false(inherits(table, "dtatools_ref_data"))

    data.table::setkey(table, id)
    repl(table, x = 9, where = .n == 1, by = id)
    expect_identical(table$x, c(9, 9, 0))
    expect_identical(data.table::key(table), "id")

    sorted <- data.table::data.table(id = c(2, 1, 2), x = 1:3)
    gen(sorted, n = .n, bysort = id)
    expect_identical(sorted$id, c(1, 2, 2))
    expect_identical(as.double(sorted$n), c(1, 1, 2))
    expect_null(data.table::key(sorted))
})

test_that("the shadow check still fires inside grouped expressions", {
    x <- 5
    data <- data.frame(id = c(1, 1, 2), x = 1:3)
    expect_error(gen(data, y = x + 1, by = id), "both a column and an object")
    expect_error(repl(data, x = 0L, where = x > 1, by = id),
                 "both a column and an object")
    expect_false("y" %in% names(data))
    expect_identical(data$x, 1:3)

    gen(data, y = .data$x + .env$x, by = id)
    expect_identical(as.double(data$y), c(6, 7, 8))

    name <- "x"
    gen(data, z = .(name) * 2, where = .data[[name]] > 1, by = id)
    expect_identical(as.double(data$z), c(NA, 4, 6))
})

test_that("grouped gen keeps value attributes and string storage", {
    data <- data.frame(id = c(1, 2, 1), x = c(1, 2, 3))
    gen(data, labelled = structure(x, label = "L"), by = id)
    expect_identical(attr(data$labelled, "label"), "L")

    gen(data, text = paste0("g", id, .n), by = id)
    expect_identical(as.character(data$text), c("g11", "g21", "g12"))
    gen(data, some = "s", where = .n == 1, by = id)
    expect_identical(as.character(data$some), c("s", "s", ""))
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
    labelled <- set_var_labels(alias, x = "X", y = "Y", z = "Z")
    labelled <- set_val_labels(labelled, x = c(One = 1))
    expect_true(inherits(labelled, "dtatools_ref_data"))
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
    skip_if_not(
        capabilities("profmem"),
        "R was built without memory profiling"
    )
    size <- 1000000L
    data <- data.frame(x = dta_byte(rep(1, size)), keep = runif(size))
    keep_trace <- tracemem(data$keep)
    on.exit(untracemem(data$keep), add = TRUE)
    before <- object.size(data$x)

    replace_values(data, x, 2, where = size)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_lte(as.numeric(object.size(data$x)), as.numeric(before) + 1024)
    expect_identical(tracemem(data$keep), keep_trace)

    x_trace <- tracemem(data$x)
    on.exit(untracemem(data$x), add = TRUE)
    gen(data, added, 3L)
    expect_identical(tracemem(data$x), x_trace)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$x))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$added))
})

test_that("plain-expression evaluation matches tidy-eval semantics", {
    data <- data.frame(x = dta_byte(c(1, 2, 3)), y = c(10, 20, 30))

    # A symbol that is both a column and a local is an error; the pronouns
    # pick one.
    y <- c(999, 999, 999)
    expect_error(gen(data, column_wins, y + 1), "`y` is both a column")
    gen(data, column_wins, .data$y + 1)
    expect_identical(as.double(data$column_wins), c(11, 21, 31))
    rm(y)

    # Environment lookups still reach the caller.
    scale_factor <- 2
    gen(data, uses_env, y * scale_factor)
    expect_identical(as.double(data$uses_env), c(20, 40, 60))

    # Empty call arguments are tolerated by the expression scan.
    matrix_2x3 <- matrix(1:6, nrow = 2)
    gen(data, empty_argument, sum(matrix_2x3[1, ]) + x)
    expect_identical(as.double(data$empty_argument), c(10, 11, 12))

    # Assignments inside expressions never leak into the data or the
    # calling environment.
    gen(data, assignment_isolated, { leaked <- 1; y + leaked })
    expect_identical(as.double(data$assignment_isolated), c(11, 21, 31))
    expect_false(exists("leaked", inherits = FALSE))
    expect_false("leaked" %in% names(data))

    # `.data` pronouns and injected quosures take the tidy-eval path.
    gen(data, pronoun, .data$y)
    expect_identical(as.double(data$pronoun), c(10, 20, 30))
    quo_y <- rlang::quo(y)
    rlang::inject(gen(data, injected, !!quo_y))
    expect_identical(as.double(data$injected), c(10, 20, 30))

    # `where` expressions run through the same fast path.
    repl(data, y, 0, where = x == 2)
    expect_identical(as.double(data$y), c(10, 0, 30))
})

test_that("plain expressions evaluate against reference-state columns", {
    data <- data.frame(x = dta_byte(c(1, 2, 3)))
    offset <- 5
    gen(data, seed_column, x)
    expect_false(is.null(attr(data, ".dtatools_ref_state", exact = TRUE)))
    gen(data, from_state, x + offset)
    expect_identical(as.double(data$from_state), c(6, 7, 8))
    repl(data, from_state, x, where = x >= 2)
    expect_identical(as.double(data$from_state), c(6, 2, 3))
})

test_that("materialized compact replacements retain Stata semantics", {
    constructors <- list(
        byte = dta_byte,
        int = dta_int,
        long = dta_long,
        float = dta_float
    )
    for (storage in names(constructors)) {
        target <- constructors[[storage]](c(
            1, 2, NA_real_, tagged_missing("a"), tagged_missing("z")
        ))
        attr(target, "label") <- paste(storage, "label")
        attr(target, "format.stata") <- "%9.0g"
        attr(target, "labels") <- c(One = 1)
        data <- data.frame(target = target)
        independent <- copy_data(data)
        invisible(dtatools:::.force_altrep_materialization(data$target))

        replace_values(
            data, target,
            c(9, tagged_missing("b"), NA_real_),
            where = c(1, 2, 3)
        )

        expect_false(
            dtatools:::.is_unmaterialized_numeric_altrep(data$target),
            info = storage
        )
        expect_identical(dta_storage_type(data$target), storage)
        expect_equal(
            as.double(data$target),
            c(9, tagged_missing("b"), NA_real_,
              tagged_missing("a"), tagged_missing("z")),
            info = storage
        )
        expect_identical(
            attr(data$target, "label"), paste(storage, "label")
        )
        expect_identical(attr(data$target, "format.stata"), "%9.0g")
        expect_identical(attr(data$target, "labels"), c(One = 1))
        expect_equal(
            as.double(independent$target),
            c(1, 2, NA_real_, tagged_missing("a"), tagged_missing("z")),
            info = storage
        )
    }
})

test_that("materialized compact replacement keeps fallback errors atomic", {
    cases <- list(
        list(value = NaN, message = "cannot contain `NaN` or infinities"),
        list(value = Inf, message = "cannot contain `NaN` or infinities"),
        list(value = 101, message = "cannot represent `x`; use `dta_int")
    )
    for (case in cases) {
        data <- data.frame(x = dta_byte(1:3))
        invisible(dtatools:::.force_altrep_materialization(data$x))
        before <- serialize(data, NULL)

        expect_error(
            replace_values(data, x, case$value, where = 2),
            case$message
        )
        expect_identical(serialize(data, NULL), before)
    }

    data <- data.frame(x = dta_byte(1:3))
    invisible(dtatools:::.force_altrep_materialization(data$x))
    before <- serialize(data, NULL)
    expect_error(replace_values(data, x, 1:2), "has size")
    expect_identical(serialize(data, NULL), before)
})

test_that("fused comparison replacement matches the general path", {
    make_data <- function() data.frame(
        x = dta_byte(c(1, 2, 3, 4, 5, 6)),
        y = dta_byte(c(
            -1, 0, 1, NA_real_, tagged_missing("a"),
            tagged_missing("z")
        )),
        z = dta_long(c(
            0, 0, 0, NA_real_, tagged_missing("b"),
            tagged_missing("z")
        ))
    )
    cases <- list(
        list(value = 9, fused = quote(y < 0), general = quote(I(y < 0))),
        list(
            value = tagged_missing("b"),
            fused = quote(y >= tagged_missing("a")),
            general = quote(I(y >= tagged_missing("a")))
        ),
        list(value = NA_real_, fused = quote(y <= z),
             general = quote(I(y <= z))),
        list(value = 8, fused = quote(0 < y),
             general = quote(I(0 < y)))
    )

    for (case in cases) {
        fused <- make_data()
        general <- make_data()
        value <- case$value
        eval(call(
            "replace_values", quote(fused), quote(x), quote(.env$value),
            where = case$fused
        ))
        eval(call(
            "replace_values", quote(general), quote(x), quote(.env$value),
            where = case$general
        ))

        expect_equal(as.double(fused$x), as.double(general$x))
        expect_identical(attributes(fused$x), attributes(general$x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(fused$x))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(fused$y))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(fused$z))
    }
})

test_that("fused comparison replacement handles full-row values", {
    replacement <- c(9, NaN, 7, 6, 5, 4)
    fused <- data.frame(
        x = dta_byte(1:6),
        y = dta_byte(c(1, 0, 1, 0, 1, 0))
    )
    general <- copy_data(fused)

    replace_values(fused, x, .env$replacement, where = y == 1)
    replace_values(general, x, .env$replacement, where = I(y == 1))

    expect_equal(as.double(fused$x), as.double(general$x))
    expect_identical(as.double(fused$x), c(9, 2, 7, 4, 5, 6))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(fused$x))
})

test_that("fused comparison replacement handles empty and full matches", {
    empty <- data.frame(x = dta_byte(1:3), y = dta_byte(1:3))
    before <- serialize(empty, NULL)
    replace_values(empty, x, 9, where = y < 0)
    expect_identical(serialize(empty, NULL), before)

    full <- data.frame(x = dta_byte(1:3), y = dta_byte(1:3))
    replace_values(full, x, tagged_missing("c"), where = y >= 1)
    expect_true(all(is_tagged_missing(full$x, "c")))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(full$x))
})

test_that("fused replacement preserves recycling errors and shared data", {
    bad <- data.frame(
        x = dta_byte(1:4),
        y = dta_byte(c(1, 0, 1, 0))
    )
    before <- serialize(bad, NULL)
    expect_error(
        replace_values(bad, x, c(8, 9, 10), where = y == 1),
        "has size"
    )
    expect_identical(serialize(bad, NULL), before)

    source <- data.frame(
        x = dta_byte(1:4),
        y = dta_byte(c(1, 0, 1, 0))
    )
    independent <- copy_data(source)
    replace_values(source, x, 9, where = y == 1)

    expect_identical(as.double(source$x), c(9, 2, 9, 4))
    expect_identical(as.double(independent$x), as.double(1:4))
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(independent$x)
    )
})

test_that("threaded fused replacement matches the general path", {
    size <- 600000L
    fused <- data.frame(
        x = dta_byte(rep(1, size)),
        y = dta_long(seq_len(size))
    )
    general <- copy_data(fused)
    previous <- options(dtatools.threads = 2L)
    on.exit(options(previous), add = TRUE)

    replace_values(fused, x, 2, where = y <= size / 2)
    replace_values(general, x, 2, where = I(y <= size / 2))

    expect_identical(as.double(fused$x), as.double(general$x))
    expect_identical(sum(fused$x == 2), as.integer(size / 2))
})

test_that("fused comparison evaluates scalar operands once", {
    calls <- 0L
    cutoff <- function() {
        calls <<- calls + 1L
        1
    }
    data <- data.frame(x = dta_byte(1:3), y = dta_byte(1:3))

    replace_values(data, x, 9, where = y > cutoff())

    expect_identical(calls, 1L)
    expect_identical(as.double(data$x), c(1, 9, 9))

    calls <- 0L
    ordinary <- data.frame(x = 1:3, y = 1:3)
    replace_values(ordinary, x, 9L, where = y > cutoff())
    expect_identical(calls, 1L)
})

test_that("fused row-value errors roll back before the fallback error", {
    values <- c(9, NaN, 7)
    data <- data.frame(
        x = dta_byte(1:3),
        y = dta_byte(c(1, 1, 0))
    )
    before <- serialize(data, NULL)

    expect_error(
        replace_values(data, x, .env$values, where = y == 1),
        "cannot contain `NaN` or unsupported missing tags"
    )
    expect_identical(serialize(data, NULL), before)
})

test_that("targets and values arrive as one tagged pair", {
    data <- data.frame(income = c(10, 20), eligible = c(TRUE, FALSE))
    expect_silent(gen(data, adjusted = income + 5))
    expect_identical(as.double(data$adjusted), c(15, 25))
    expect_silent(repl(data, adjusted = 0, where = eligible))
    expect_identical(as.double(data$adjusted), c(0, 25))
    # A trailing untagged argument is `where`, in both shapes.
    expect_silent(replace_values(data, adjusted = 1, !eligible))
    expect_identical(as.double(data$adjusted), c(0, 1))
    expect_silent(replace_values(data, adjusted, 2, eligible))
    expect_identical(as.double(data$adjusted), c(2, 1))
    # A name held in a string, spelled as a tag.
    target <- "adjusted"
    expect_silent(repl(data, !!target := 3))
    expect_identical(as.double(data$adjusted), c(3, 3))
    expect_silent(repl(data, .(target) := 4, where = eligible))
    expect_identical(as.double(data$adjusted), c(4, 3))
    expect_silent(repl(data, "adjusted" = 5))
    expect_identical(as.double(data$adjusted), c(5, 5))
    # `values` inside a `.() :=` tag keeps the mask and its own `!!`.
    scale <- 10
    expect_silent(gen(data, .(paste0("scaled_", target)) := income * !!scale))
    expect_identical(as.double(data$scaled_adjusted), c(100, 200))
    # Former argument names are ordinary column names.
    expect_silent(gen(data, values = 1))
    expect_identical(as.double(data$values), c(1, 1))
    expect_silent(gen(data, variable = 2, where = eligible))
    expect_identical(as.double(data$variable), c(2, NA))
})

test_that("tagged pairs reach reference, data.table, and compact targets", {
    referenced <- data.frame(x = 1:2)
    gen(referenced, y = x * 2L)
    expect_silent(gen(referenced, z = y + 1L))
    expect_identical(as.double(referenced$z), c(3, 5))
    expect_silent(repl(referenced, z = 0L, where = x == 1L))
    expect_identical(as.double(referenced$z), c(0, 5))

    table <- data.table::data.table(x = 1:2)
    expect_silent(gen(table, y = x + 1L))
    expect_silent(repl(table, y = 0L, x == 2L))
    expect_identical(as.double(table$y), c(2, 0))

    compact <- read_dta(fixture("all_types_v118.dta"))
    target <- names(compact)[vapply(
        compact,
        function(column) isTRUE(dta_storage_type(column) == "int"),
        logical(1)
    )][[1L]]
    original <- as.double(compact[[target]])
    expect_silent(repl(compact, .(target) := 0, where = 1))
    expect_true(
        dtatools:::.is_unmaterialized_numeric_altrep(compact[[target]])
    )
    expect_identical(as.double(compact[[target]]), c(0, original[-1L]))
})

test_that("mutation dots must be one target pair and at most one where", {
    data <- data.frame(x = 1:2, y = 3:4)
    shape <- "`...` must be `variable, values` or one `variable = values`"
    expect_error(gen(data), shape)
    expect_error(gen(data, x, y = 1), shape)
    expect_error(gen(data, a = 1, b = 2), shape)
    expect_error(gen(data, a = 1, x, y = 2), shape)
    expect_error(gen(data, a, 1, x > 1, y), shape)
    expect_error(repl(data, x = 1, x > 1, where = y > 3), shape)
    expect_error(repl(data, x, 1, where = y > 3, y), shape)
    # Empty arguments are rejected rather than dropped.
    expect_error(gen(data, a = ), "`values` is required")
    expect_error(gen(data, a, ), "`values` is required")
    expect_error(gen(data, a, 1, ), shape)
    expect_error(repl(data, x = 1, ), shape)
    # Named `variable`/`values` arguments are gone: this is two tags.
    expect_error(gen(data, variable = a, values = 1), shape)
    expect_error(gen(data, .("") := 1), "nonempty")
    expect_error(gen(data, .(1) := 1), "nonempty")
    expect_identical(data, data.frame(x = 1:2, y = 3:4))
})

test_that("a symbol bound as both column and object is an error", {
    data <- data.frame(x = c(1, 2, 3), rows = c(0, 0, 0))
    rows <- c(TRUE, FALSE, TRUE)
    message <- "`rows` is both a column and an object"

    expect_error(repl(data, x, 9, where = rows), message)
    expect_error(repl(data, x, rows), message)
    expect_error(gen(data, y, x + rows), message)
    expect_error(repl(data, x, 9, where = rows == 0), message)
    expect_identical(data$x, c(1, 2, 3))

    # The fused comparison path, which reads columns without evaluating
    # the expression, is checked too.
    fused <- data.frame(
        x = dta_byte(c(1, 2, 3)), rows = dta_byte(c(0, 0, 0))
    )
    expect_error(repl(fused, x, 9, where = rows == 0), message)
    expect_error(repl(fused, x, 9, where = x == rows), message)
    cutoff <- 2
    fused$cutoff <- dta_byte(c(0, 0, 0))
    expect_error(repl(fused, x, 9, where = x > cutoff), "`cutoff` is both")
    expect_identical(as.double(fused$x), c(1, 2, 3))

    # Namespace qualifiers are not column reads.
    namespace_data <- data.frame(x = c(1, 2, 3), stats = c(0, 0, 0))
    stats <- 5
    repl(namespace_data, x, stats::median(x))
    expect_identical(namespace_data$x, c(2, 2, 2))

    # Both explicit spellings pass, and each reads what it names.
    repl(data, x, 9, where = .env$rows)
    expect_identical(data$x, c(9, 2, 9))
    repl(data, x, 5, where = .data$rows == 0)
    expect_identical(data$x, c(5, 5, 5))
    repl(data, x, .data$rows + 1)
    expect_identical(data$x, c(1, 1, 1))
    repl(data, x, .env$rows)
    expect_identical(data$x, c(1, 0, 1))

    # `.()` is evaluated in the caller's environment, never as a column read.
    name <- "x"
    data <- data.frame(x = c(1, 2), name = c("a", "b"))
    repl(data, x, .(name) + 1)
    expect_identical(data$x, c(2, 3))

    # Function positions and `$` right-hand sides are not column reads.
    data <- data.frame(x = c(1, 2), sum = c(0, 0), value = c(5, 6))
    sum <- 3
    holder <- list(value = 7)
    repl(data, x, sum(value))
    expect_identical(data$x, c(11, 11))
    repl(data, x, holder$value)
    expect_identical(data$x, c(7, 7))

    # Bindings in base and attached packages are not consulted, even when
    # the capture frame sits inside a package namespace.
    data <- data.frame(x = c(1, 2), pi = c(3, 3), T = c(1, 1))
    repl(data, x, pi + T)
    expect_identical(data$x, c(4, 4))
    in_namespace <- function(data) repl(data, x, pi + T)
    environment(in_namespace) <- asNamespace("stats")
    in_namespace(data)
    expect_identical(data$x, c(4, 4))

    # A one-sided formula asks for the data mask outright, so its body is
    # exempt on the fused `where` path and the general path alike.
    data <- data.frame(x = c(1, 2), rows = c(0, 1), y = c(5, 5))
    rows <- c(TRUE, TRUE)
    y <- 100
    expect_error(repl(data, x, 0, where = rows == 1), "`rows` is both")
    repl(data, x, 0, where = ~ rows == 1)
    expect_identical(data$x, c(1, 0))
    repl(data, x, ~ y + 1)
    expect_identical(data$x, c(6, 6))
    stored <- ~ y + 2
    repl(data, x, stored)
    expect_identical(data$x, c(7, 7))
    rm(rows, y)

    # The fused plan's scalar operand is exempt under a formula too.
    compact <- data.frame(x = dta_byte(c(1, 5, 9)), cutoff = c(4, 4, 4))
    cutoff <- 100
    expect_error(repl(compact, x, 0, where = x > cutoff), "`cutoff` is both")
    repl(compact, x, 0, where = ~ x > cutoff)
    expect_identical(as.double(compact$x), c(1, 0, 0))
    rm(cutoff)

    # A function binding does not count: a script may share its column's name.
    data <- data.frame(x = c(1, 2), income = c(5, 6))
    income <- function(data) repl(data, x, income * 2)
    income(data)
    expect_identical(data$x, c(10, 12))

    # The check follows the capture frame up to the global environment.
    data <- data.frame(x = c(1, 2), offset = c(10, 20))
    outer <- function(data) {
        offset <- 1
        inner <- function(data) repl(data, x, x + offset)
        inner(data)
    }
    expect_error(outer(data), "`offset` is both a column")
    no_local <- function(data) repl(data, x, x + offset)
    no_local(data)
    expect_identical(data$x, c(11, 22))

    # The option turns the check off, and columns win as before.
    data <- data.frame(x = c(1, 2, 3), rows = c(0, 0, 0))
    rows <- c(TRUE, FALSE, TRUE)
    withr::with_options(list(dtatools.shadow_check = FALSE), {
        repl(data, x, rows)
    })
    expect_identical(data$x, c(0, 0, 0))
})

test_that("replacing a grouping column rebuilds the dplyr groups", {
    grouped <- dplyr::group_by(
        tibble::tibble(id = c(1, 1, 2), x = 1:3), id
    )
    repl(grouped, id = 1)
    expect_identical(dplyr::group_vars(grouped), "id")
    groups <- attr(grouped, "groups", exact = TRUE)
    expect_identical(groups$id, 1)
    expect_identical(as.integer(groups$.rows[[1L]]), 1:3)
    expect_identical(dplyr::summarise(grouped, n = dplyr::n())$n, 3L)
    gen(grouped, size = .N)
    expect_identical(as.double(grouped$size), c(3, 3, 3))

    # A grouped dibble keeps the rebuilt groups in its snapshot too.
    dib <- dplyr::group_by(dibble(id = c("a", "b", "b"), x = 1:3), id)
    dib[, id := "b"]
    expect_true(is_dibble(dib))
    expect_identical(
        as.character(attr(dib, "groups", exact = TRUE)$id), "b"
    )
    expect_identical(as.integer(dplyr::summarise(dib, n = dplyr::n())$n), 3L)
})

test_that("an aliased grouping column is regrouped after replacement", {
    shared <- dta_int(c(1L, 1L, 2L))
    grouped <- dplyr::group_by(tibble::tibble(id = shared, x = shared), id)
    # `x` and `id` share one compact vector; replacing `x` rewrites `id`.
    repl(grouped, x = 1L)
    expect_identical(as.double(grouped$id), c(1, 1, 1))
    expect_identical(
        as.double(attr(grouped, "groups", exact = TRUE)$id), 1
    )
    expect_identical(dplyr::summarise(grouped, n = dplyr::n())$n, 3L)
})

test_that("row counters mask a column named .n or .N", {
    data <- data.frame(.n = c(100, 200), .N = c(7, 7), x = 1:2)
    gen(data, row = .n)
    gen(data, count = .N)
    expect_identical(as.double(data$row), c(1, 2))
    expect_identical(as.double(data$count), c(2, 2))
    # The pronoun still reaches the column.
    gen(data, from_column = .data$.n)
    expect_identical(as.double(data$from_column), c(100, 200))
    repl(data, x = 0L, where = .data$.N == 7 & .n == 2)
    expect_identical(data$x, c(1L, 0L))

    skip_if_not_installed("data.table")
    table <- data.table::data.table(.n = c(100, 200), x = 1:2)
    gen(table, row = .n)
    expect_identical(as.double(table$row), c(1, 2))
})
