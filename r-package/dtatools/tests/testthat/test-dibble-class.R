test_that("dibble class is public identity independently of reference ownership", {
    expected <- c("dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame")
    data <- dibble(x = 1:3)
    expect_identical(class(data), expected)
    expect_true(is_dibble(data))
    expect_true(dtatools:::.reference_state_valid(data))
    restored <- unserialize(serialize(data, NULL))
    expect_identical(class(restored), expected)
    expect_true(is_dibble(restored))
    expect_false(dtatools:::.reference_state_valid(restored))
    expect_false(can_add_columns(restored))
    state <- dtatools:::.reference_state(restored)
    state$dibble <- FALSE
    expect_true(is_dibble(restored))
    attr(restored, ".dtatools_ref_state") <- NULL
    expect_true(is_dibble(restored))
    expect_false(dtatools:::.reference_state_valid(restored))
    expect_identical(class(tibble::as_tibble(restored)), expected[-(1:2)])
    prepared <- reserve_columns(restored, 1L)
    expect_identical(class(prepared), expected)
    expect_true(dtatools:::.reference_state_valid(prepared))
    gen(prepared, y = 1L)
    expect_identical(names(restored), "x")
})

test_that("reference support does not grant ordinary containers dibble identity", {
    factories <- list(data.frame, tibble::tibble)
    if (requireNamespace("data.table", quietly = TRUE)) {
        factories <- c(factories, list(data.table::data.table))
    }
    for (factory in factories) {
        data <- reserve_columns(factory(x = 1:3, text = c("a", NA, "")), 1L)
        columns <- lapply(data, attributes)
        gen(data, y = 1L)
        expect_false(inherits(data, "dibble"))
        expect_false(is_dibble(data))
        expect_identical(attributes(data$x), columns$x)
        expect_identical(attributes(data$text), columns$text)
        expect_false(inherits(copy_data(data), "dibble"))
        expect_false(inherits(reserve_columns(data), "dibble"))
    }
})

test_that("grouping and metadata classes follow dibble identity", {
    data <- dibble(g = c(1L, 1L, 2L), x = 1:3)
    base <- c("tbl_df", "tbl", "data.frame")
    for (kind in c("plain", "grouped", "rowwise")) {
        input <- switch(kind, plain = data,
                        grouped = dplyr::group_by(data, g),
                        rowwise = dplyr::rowwise(data, g))
        grouping <- switch(kind, plain = character(), grouped = "grouped_df",
                           rowwise = "rowwise_df")
        expected <- c("dibble", "dtatools_ref_data", grouping, base)
        expect_identical(class(input), expected)
        for (operation in list(as_dibble, copy_data, reserve_columns,
                               function(x) x[1:2, ],
                               function(x) vctrs::vec_slice(x, 1:2),
                               function(x) dplyr::select(x, g, x),
                               function(x) dplyr::mutate(x, y = x + 1L),
                               function(x) dplyr::dplyr_reconstruct(
                                   tibble::as_tibble(x), x))) {
            result <- operation(input)
            expect_identical(class(result), expected)
            expect_true(is_dibble(result))
        }
        set_dta_note(input, 1L, "dataset note")
        noted <- c("dibble", "dtatools_ref_data", "dtatools_dta_metadata",
                   grouping, base)
        expect_identical(class(input), noted)
        expect_identical(class(copy_data(input)), noted)
        expect_identical(class(reserve_columns(input)), noted)
        expect_identical(class(input[1:2, ]), noted)
        set_dta_note(input, 1L, NULL)
        expect_identical(class(input), expected)
    }
})

test_that("legacy flags recognize type and assigned upgrade isolates aliases", {
    for (flag in list(TRUE, NULL)) {
        data <- dibble(x = 1:3, text = c("a", "b", "c"))
        state <- dtatools:::.reference_state(data)
        state$dibble <- flag
        class(data) <- setdiff(class(data), "dibble")
        legacy <- unserialize(serialize(data, NULL))
        alias <- legacy
        state <- dtatools:::.reference_state(legacy)
        before <- serialize(legacy, NULL)
        expect_true(is_dibble(legacy))
        expect_false(inherits(legacy, "dibble"))
        expect_match(format(legacy)[[1L]], "^# A dibble:")
        expect_identical(capture.output(print(legacy)), format(legacy))
        for (operation in list(as_dibble, copy_data, reserve_columns,
                               function(x) x[1:2, ],
                               function(x) dplyr::mutate(x, y = x + 1L))) {
            result <- operation(legacy)
            expect_s3_class(result, "dibble")
            expect_true(dtatools:::.reference_state_valid(result))
            expect_false(identical(dtatools:::.reference_state(result), state))
            repl(result, x = 0L)
            expect_identical(as.integer(alias$x), 1:3)
            expect_identical(serialize(alias, NULL), before)
        }
    }
    ordinary <- reserve_columns(tibble::tibble(x = 1:3))
    gen(ordinary, y = 1L)
    expect_identical(dtatools:::.reference_state(ordinary)$dibble, FALSE)
    restored <- unserialize(serialize(ordinary, NULL))
    expect_false(is_dibble(restored))
    expect_false(inherits(reserve_columns(restored), "dibble"))
    expect_match(format(restored)[[1L]], "^# A tibble:")
})

test_that("class snapshots and display dispatch preserve compact source columns", {
    data <- read_dta(fixture("all_types_v118.dta"))
    alias <- data
    source_attributes <- attributes(data)
    column_attributes <- lapply(data, attributes)
    compact <- data$v_str20
    cached <- dtatools:::.dictstring_cached_count(compact)
    expect_s3_class(data, "dibble")
    for (operation in list(tibble::as_tibble, as.data.frame,
                           dtatools:::.reference_snapshot)) {
        result <- operation(data)
        expect_false(inherits(result, "dibble"))
        expect_false(inherits(result, "dtatools_ref_data"))
        expect_null(attr(result, ".dtatools_ref_state", exact = TRUE))
    }
    display <- dtatools:::.dibble_display_snapshot(data)
    expect_s3_class(display, "dibble")
    expect_false(inherits(display, "dtatools_ref_data"))
    expect_identical(names(pillar::tbl_sum(data))[[1L]], "A dibble")
    expect_identical(names(pillar::tbl_sum(display))[[1L]], "A dibble")
    expect_identical(capture.output(print(data, width = 90)),
                     format(data, width = 90))
    expect_identical(attributes(alias), source_attributes)
    expect_identical(lapply(alias, attributes), column_attributes)
    expect_identical(dtatools:::.dictstring_cached_count(compact), cached)
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
})

test_that("class-preserving replacement and structural helpers retain alias contracts", {
    data <- dibble(x = 1:3, y = 4:6)
    alias <- data
    changed <- data
    changed$x <- 7:9
    expect_s3_class(changed, "dibble")
    expect_identical(as.integer(alias$x), 1:3)
    repl(changed, y = 0L)
    expect_identical(as.integer(alias$y), 4:6)
    keep_vars(data, x)
    expect_s3_class(alias, "dibble")
    expect_identical(names(alias), "x")
    gen(data, z = 1L)
    order_vars(data, z)
    rename_vars(data, flag = z)
    expect_s3_class(alias, "dibble")
    expect_identical(names(alias), c("flag", "x"))
    drop_vars(data, flag)
    expect_s3_class(alias, "dibble")
})
