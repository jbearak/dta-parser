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

test_that("ordinary containers are never mutation targets and never gain dibble identity", {
    factories <- list(data.frame, tibble::tibble)
    if (requireNamespace("data.table", quietly = TRUE)) {
        factories <- c(factories, list(data.table::data.table))
    }
    for (factory in factories) {
        data <- factory(x = 1:3, text = c("a", NA, ""))
        columns <- lapply(data, attributes)
        before <- serialize(data, NULL)
        expect_error(reserve_columns(data, 1L), "must be a dibble")
        expect_error(gen(data, y = 1L), "must be a dibble")
        expect_error(copy_data(data), "must be a dibble")
        expect_false(inherits(data, "dibble"))
        expect_false(inherits(data, "dtatools_ref_data"))
        expect_false(is_dibble(data))
        expect_identical(attributes(data$x), columns$x)
        expect_identical(attributes(data$text), columns$text)
        expect_identical(serialize(data, NULL), before)
    }
})

.check_optional_split_dibble_class_44 <- function(include_dplyr) {
    data <- dibble(g = c(1L, 1L, 2L), x = 1:3)
    base <- c("tbl_df", "tbl", "data.frame")
    for (kind in c("plain", "grouped", "rowwise")) {
        input <- if (include_dplyr) switch(kind, plain = data,
                        grouped = dplyr::group_by(data, g),
                        rowwise = dplyr::rowwise(data, g)) else switch(kind,
                        plain = data,
                        grouped = as_dibble(.group_fixture("g_112_i_typed")$data),
                        rowwise = as_dibble(.group_fixture("g_112_i_typed_rowwise")$data))
        grouping <- switch(kind, plain = character(), grouped = "grouped_df",
                           rowwise = "rowwise_df")
        expected <- c("dibble", "dtatools_ref_data", grouping, base)
        expect_identical(class(input), expected)
        operations <- list(as_dibble, copy_data, reserve_columns,
                           function(x) x[1:2, ],
                           function(x) vctrs::vec_slice(x, 1:2))
        if (include_dplyr) operations <- c(operations, list(
            function(x) dplyr::select(x, g, x),
            function(x) dplyr::mutate(x, y = x + 1L),
            function(x) dplyr::dplyr_reconstruct(tibble::as_tibble(x), x)))
        for (operation in operations) {
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
}

test_that("grouping and metadata classes follow dibble identity", {
    .check_optional_split_dibble_class_44(FALSE)
})

test_that("grouping and metadata class identity through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_class_44(TRUE)
})
.check_optional_split_dibble_class_78 <- function(include_dplyr) {
    {
        data <- dibble(x = 1:3, text = c("a", "b", "c"))
        legacy <- unserialize(serialize(data, NULL))
        alias <- legacy
        state <- dtatools:::.reference_state(legacy)
        before <- serialize(legacy, NULL)
        expect_true(is_dibble(legacy))
        expect_false(dtatools:::.reference_state_valid(legacy))
        expect_match(format(legacy)[[1L]], "^# A dibble:")
        expect_identical(capture.output(print(legacy)), format(legacy))
        # A serialized dibble keeps its identity, so `as_dibble()` returns
        # it unchanged; the assigned preparation helpers rebuild it.
        expect_identical(as_dibble(legacy), legacy)
        operations <- list(copy_data, reserve_columns,
                           function(x) x[1:2, ])
        if (include_dplyr) operations <- c(operations, list(
            function(x) dplyr::mutate(x, y = x + 1L)))
        for (operation in operations) {
            result <- operation(legacy)
            expect_s3_class(result, "dibble")
            expect_true(dtatools:::.reference_state_valid(result))
            expect_false(identical(dtatools:::.reference_state(result), state))
            repl(result, x = 0L)
            expect_identical(as.integer(alias$x), 1:3)
            expect_identical(serialize(alias, NULL), before)
        }
    }
    ordinary <- tibble::tibble(x = 1:3)
    expect_error(gen(ordinary, y = 1L), "must be a dibble")
    expect_null(dtatools:::.reference_state(ordinary))
    restored <- unserialize(serialize(ordinary, NULL))
    expect_false(is_dibble(restored))
    expect_error(reserve_columns(restored), "must be a dibble")
    expect_match(format(restored)[[1L]], "^# A tibble:")
}

test_that("serialized dibbles keep identity and assigned upgrade isolates aliases", {
    .check_optional_split_dibble_class_78(FALSE)
})

test_that("serialized dibble upgrade through dplyr", {
    skip_if_not_installed("dplyr", "1.2.1")
    .check_optional_split_dibble_class_78(TRUE)
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

test_that("grouped restoration preserves memberships and later write isolation", {
    source <- as_dibble(.group_fixture("g_112_i_typed")$data)
    before <- attr(source, "groups", exact = TRUE)
    result <- vctrs::vec_slice(source, c(3L, 1L, 3L))
    expect_identical(as.integer(result$x), c(3L, 1L, 3L))
    expect_identical(as.integer(attr(result, "groups")$g), 1:2)
    expect_identical(as.list(attr(result, "groups")$.rows), list(2L, c(1L, 3L)))
    empty <- vctrs::vec_slice(source, integer())
    expect_identical(nrow(empty), 0L)
    expect_identical(nrow(attr(empty, "groups")), 0L)
    expect_identical(.row_names_info(attr(empty, "groups"), 0L), integer())
    renamed <- source
    withCallingHandlers(dimnames(renamed) <- list(row.names(renamed), c("key", "x")),
        warning = function(warning) {
            if (identical(conditionMessage(warning),
                "Setting row names on a tibble is deprecated.")) invokeRestart("muffleWarning")
        })
    expect_identical(.row_names_info(renamed, 0L), c(NA_integer_, -3L))
    result$g <- c(1L, 2L, 1L)
    expect_identical(as.list(attr(result, "groups")$.rows), list(c(1L, 3L), 2L))
    repl(result, x = 0L)
    expect_identical(as.integer(result$x), c(0L, 0L, 0L))
    expect_identical(as.integer(source$x), 1:3)
    expect_identical(as.integer(source$g), c(1L, 1L, 2L))
    expect_identical(attr(source, "groups", exact = TRUE), before)
    wise <- as_dibble(.group_fixture("g_112_i_typed_rowwise")$data)
    wise[, "g"] <- 3:1
    expect_identical(attr(wise, "groups")$g, 3:1)
    sliced <- vctrs::vec_slice(wise, c(3L, 1L, 3L))
    expect_identical(as.integer(sliced$x), c(3L, 1L, 3L))
    expect_identical(names(attr(sliced, "groups")), ".rows")
    expect_identical(as.list(attr(sliced, "groups")$.rows), list(1L, 2L, 3L))
    expect_s3_class(sliced, "rowwise_df")
})

test_that("bracket replacement retains a caller-local grouping method", {
    source <- as_dibble(.group_fixture("g_212_i_typed")$data)
    before <- attr(source, "groups", exact = TRUE)
    caller <- new.env(parent = environment())
    caller$source <- source
    caller$`[<-.grouped_df` <- function(x, i, j, ..., value) {
        classes <- class(x)
        groups <- attr(x, "groups", exact = TRUE)
        class(x) <- setdiff(classes, "grouped_df")
        x[, j] <- value
        groups <- vctrs::vec_slice(groups, order(as.double(groups$g), decreasing = TRUE))
        attr(x, "groups") <- groups
        attr(x, "caller_group_method") <- TRUE
        class(x) <- classes
        x
    }
    # Keep this witness on caller dispatch; later promotion has its own regrouping policy.
    result <- eval(quote({ changed <- source; changed[, "x"] <- dta_long(4:6); changed }), caller)
    expect_true(attr(result, "caller_group_method", exact = TRUE))
    expect_identical(as.integer(result$x), 4:6)
    expect_identical(as.double(attr(result, "groups")$g), c(2, 1))
    expect_identical(as.list(attr(result, "groups")$.rows), list(c(1L, 3L), 2L))
    expect_identical(as.integer(source$x), 1:3)
    expect_identical(attr(source, "groups", exact = TRUE), before)
})

test_that("dibble row duplicates match the base data frame methods", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    base_any <- getS3method("anyDuplicated", "data.frame")
    labelled <- dta_byte(c(1, 1, 2, 2, NA, NA, 1, 1))
    val_labels(labelled) <- c(yes = 1, no = 2)
    accented <- "café"
    data <- dibble(
        x = dta_double(c(1, 1, tagged_missing("a"), tagged_missing("b"), 0, -0, 2, 2)),
        y = labelled,
        f = dta_float(c(1.5, 1.5, NA, NA, 2, 2, 1.5, 1.5)),
        s = dta_string(c("a", "a", accented, iconv(accented, "UTF-8", "latin1"),
                         "b", "b", "a", "a")),
        l = c(TRUE, TRUE, NA, NA, FALSE, FALSE, TRUE, FALSE)
    )
    expect_s3_class(data$y, "haven_labelled")
    expect_false(is.null(dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated")))
    # Cells compare with every NA equal, tagged missings included, and -0
    # equal to 0.
    expect_identical(duplicated(data), c(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, FALSE))
    for (from_last in c(FALSE, TRUE)) {
        expect_identical(duplicated(data, fromLast = from_last),
                         base_duplicated(data, fromLast = from_last))
        expect_identical(anyDuplicated(data, fromLast = from_last),
                         base_any(data, fromLast = from_last))
        expect_identical(anyDuplicated(data[c(1, 3, 5, 7, 8), ], fromLast = from_last), 0L)
    }
    expect_identical(as.data.frame(unique(data)),
                     as.data.frame(data[c(1, 3, 5, 7, 8), ]))
    empty <- data[0, ]
    expect_identical(duplicated(empty), base_duplicated(empty))
    expect_identical(anyDuplicated(empty), base_any(empty))
    for (id in c("g_1122_typed", "g_112_i_typed_rowwise")) {
        grouped <- vctrs::vec_slice(as_dibble(.group_fixture(id)$data),
                                    c(1L, 1L, 3L, 2L, 3L))
        expect_false(is.null(dtatools:::.dibble_row_key(grouped, FALSE, FALSE, "duplicated")))
        expect_identical(duplicated(grouped), c(FALSE, TRUE, FALSE, FALSE, TRUE))
        expect_identical(duplicated(grouped), base_duplicated(grouped))
    }
})

test_that("dibble row duplicates compare only rows that still share a group", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    base_any <- getS3method("anyDuplicated", "data.frame")
    set.seed(20261006)
    rows <- 300L
    data <- dibble(
        a = dta_byte(sample(c(1, 2, 3, NA), rows, TRUE)),
        b = dta_double(sample(c(0.5, -0, 0, NA, tagged_missing("c")), rows, TRUE)),
        c = dta_string(sample(c("", "x", "y"), rows, TRUE)),
        d = sample(c(TRUE, FALSE), rows, TRUE),
        e = dta_long(sample(1:4, rows, TRUE))
    )
    for (columns in list(1:2, 1:5, c(5L, 1L, 3L), c(2L, 4L), c(3L, 4L))) {
        subset <- data[columns]
        for (from_last in c(FALSE, TRUE)) {
            expect_identical(duplicated(subset, fromLast = from_last),
                             base_duplicated(subset, fromLast = from_last))
            expect_identical(anyDuplicated(subset, fromLast = from_last),
                             base_any(subset, fromLast = from_last))
        }
    }
})

test_that("dibble row duplicates leave other tables and columns to base", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    base_any <- getS3method("anyDuplicated", "data.frame")
    # Base sends one column to the column's method, which tells tagged
    # missings apart, but compares cells for anyDuplicated().
    tagged <- dibble(x = dta_double(tagged_missing(c("a", "b"))))
    expect_identical(duplicated(tagged), c(FALSE, FALSE))
    expect_identical(anyDuplicated(tagged), 2L)
    expect_identical(anyDuplicated(tagged), base_any(tagged))
    bytes <- "caf\xe9"
    Encoding(bytes) <- "bytes"
    others <- list(
        date = dibble(t = as.Date(c("2020-01-01", "2020-01-01", "2020-01-02")),
                      a = dta_byte(c(1, 1, 1))),
        factor = dibble(f = factor(c("a", "a", "b")), a = dta_byte(c(1, 1, 1))),
        list = dibble(l = I(list(1, 1, 2)), a = dta_byte(c(1, 1, 1))),
        bytes = dibble(s = dta_string(c(bytes, bytes, "a")), a = dta_byte(c(1, 1, 1)))
    )
    for (data in others) {
        expect_null(dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated"))
        expect_identical(duplicated(data), base_duplicated(data))
        expect_identical(duplicated(data), c(FALSE, TRUE, FALSE))
        expect_identical(anyDuplicated(data), base_any(data))
    }
    data <- dibble(a = dta_byte(c(1, 2, 1)), b = dta_byte(c(1, 2, 1)))
    expect_identical(duplicated(data[0]), base_duplicated(data[0]))
    expect_identical(anyDuplicated(data[0]), base_any(data[0]))
    for (incomparables in list(NA, 1)) {
        expect_identical(
            tryCatch(duplicated(data, incomparables = incomparables), error = conditionMessage),
            tryCatch(base_duplicated(data, incomparables = incomparables), error = conditionMessage)
        )
    }
    expect_identical(
        tryCatch(duplicated(data, fromLast = NA), error = conditionMessage),
        tryCatch(base_duplicated(data, fromLast = NA), error = conditionMessage)
    )
})

test_that("dibble row duplicates construct cells as their [[ method does", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    data <- dibble(a = dta_double(c(1, 1, 1)), f = dta_float(c(1, 1, 1)))
    table <- function(...) {
        structure(list(...), class = class(data), row.names = c(NA, -3L))
    }
    # A float column without compact backing rounds each cell to float.
    unrounded <- structure(c(1.1, 1.1 + 1e-12, 1.2), stata.storage = "float",
                           class = class(data$f))
    rounded <- table(a = data$a, f = unrounded)
    expect_false(is.null(dtatools:::.dibble_row_key(rounded, FALSE, FALSE, "duplicated")))
    expect_identical(duplicated(rounded), c(FALSE, TRUE, FALSE))
    expect_identical(duplicated(rounded), base_duplicated(rounded))
    # Integer backing takes base's comparison.
    integers <- data$a
    storage.mode(integers) <- "integer"
    backed <- table(a = integers, f = data$f)
    expect_null(dtatools:::.dibble_row_key(backed, FALSE, FALSE, "duplicated"))
    expect_identical(duplicated(backed), base_duplicated(backed))
    expect_identical(duplicated(backed), c(FALSE, TRUE, TRUE))
    # A value its storage cannot hold leaves base to signal the error, even
    # when an earlier column already tells every row apart.
    invalid <- structure(c(1, NaN, 1), stata.storage = "double", class = class(data$a))
    for (bad in list(table(a = data$a, f = invalid),
                     table(a = dta_double(1:3), f = invalid))) {
        expect_null(dtatools:::.dibble_row_key(bad, FALSE, FALSE, "duplicated"))
        message <- tryCatch(base_duplicated(bad), error = conditionMessage)
        expect_match(message, "No Stata numeric storage can represent")
        expect_identical(tryCatch(duplicated(bad), error = conditionMessage), message)
    }
})

test_that("dibble row duplicates leave invalid compact values to base", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(path, 0L, list(x_byte = as.raw(0x80)))
    data <- read_dta(path, col_select = c("x_int", "x_byte"))
    expect_identical(as.double(data$x_byte)[[1L]], -128)
    expect_null(dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated"))
    message <- tryCatch(base_duplicated(data), error = conditionMessage)
    expect_match(message, "byte storage cannot represent")
    expect_identical(tryCatch(duplicated(data), error = conditionMessage), message)
})

test_that("dibble row duplicates defer to another cell method", {
    data <- dibble(a = dta_byte(c(1, 2, 1)), b = dta_byte(c(1, 2, 3)))
    expect_identical(duplicated(data), c(FALSE, FALSE, FALSE))
    assign("[[.dta_byte", function(x, i, ...) "same", envir = globalenv())
    removed <- FALSE
    on.exit(if (!removed) rm("[[.dta_byte", envir = globalenv()), add = TRUE)
    expect_null(dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated"))
    expect_identical(duplicated(data), c(FALSE, TRUE, TRUE))
    rm("[[.dta_byte", envir = globalenv())
    removed <- TRUE
    expect_false(is.null(dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated")))
})

test_that("dibble row duplicates keep read columns compact", {
    data <- read_dta(fixture("all_types_v118.dta"))
    data <- data[c(seq_len(nrow(data)), 1L), ]
    expect_false(is.null(dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated")))
    expect_identical(duplicated(data), c(rep(FALSE, nrow(data) - 1L), TRUE))
    expect_true(dtatools:::.is_unmaterialized_dictstring(data$v_str20))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(data$v_byte))
})

test_that("unique dibble rows read the arguments, not same-named columns", {
    data <- dibble(
        x = dta_double(c(1, 1, 2, 2)),
        fromLast = c(TRUE, FALSE, TRUE, TRUE)
    )
    expect_identical(as.data.frame(unique(data)), as.data.frame(data[c(1, 2, 3), ]))
    expect_identical(as.data.frame(unique(data, fromLast = TRUE)),
                     as.data.frame(data[c(1, 2, 4), ]))
    expect_error(unique(data, incomparables = 1), "not used")
})

test_that("dibble row duplicates defer to a next method local to the caller", {
    data <- dibble(a = dta_byte(c(1, 2, 1)), b = dta_byte(c(1, 2, 1)))
    local_methods <- function(data) {
        duplicated.tbl_df <- function(x, ...) rep(FALSE, nrow(x))
        anyDuplicated.tbl_df <- function(x, ...) -1L
        unique.tbl_df <- function(x, ...) "local"
        list(
            key = dtatools:::.dibble_row_key(data, FALSE, FALSE, "duplicated", environment()),
            duplicated = duplicated(data),
            any = anyDuplicated(data),
            unique = unique(data)
        )
    }
    result <- local_methods(data)
    expect_null(result$key)
    expect_identical(result$duplicated, c(FALSE, FALSE, FALSE))
    expect_identical(result$any, -1L)
    expect_identical(result$unique, "local")
    expect_identical(duplicated(data), c(FALSE, FALSE, TRUE))
    expect_identical(anyDuplicated(data), 3L)
    # A caller whose top environment is the base environment.
    expect_identical(eval(quote(duplicated(d)), list(d = data), baseenv()),
                     c(FALSE, FALSE, TRUE))
    expect_identical(eval(quote(anyDuplicated(d)), list(d = data), baseenv()), 3L)
    expect_identical(as.data.frame(eval(quote(unique(d)), list(d = data), baseenv())),
                     as.data.frame(data[1:2, ]))
})

test_that("dibble row duplicates follow the dispatch chain past a changed class", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    data <- dibble(a = dta_byte(c(1, 2, 1)), b = dta_byte(c(1, 2, 1)))
    sub <- data
    class(sub) <- c("dtatools_test_sub", class(data))
    duplicated.dtatools_test_sub <- function(x, ...) {
        class(x) <- "data.frame"
        NextMethod()
    }
    anyDuplicated.dtatools_test_sub <- duplicated.dtatools_test_sub
    unique.dtatools_test_sub <- duplicated.dtatools_test_sub
    plain <- data
    class(plain) <- "data.frame"
    expect_identical(duplicated(sub), base_duplicated(plain))
    expect_identical(duplicated(sub), c(FALSE, FALSE, TRUE))
    expect_identical(anyDuplicated(sub), 3L)
    expect_identical(unique(sub), plain[1:2, , drop = FALSE])
})

test_that("dibble row duplicates leave restoration warnings to base", {
    base_duplicated <- getS3method("duplicated", "data.frame")
    capture_warnings_and_value <- function(expr) {
        warnings <- character()
        value <- withCallingHandlers(expr, warning = function(condition) {
            warnings <<- c(warnings, conditionMessage(condition))
            invokeRestart("muffleWarning")
        })
        list(value = value, warnings = warnings)
    }
    data <- dibble(a = dta_byte(c(1, 2, 1)), b = dta_string(c("x", "y", "x")))
    for (name in c("a", "b")) {
        columns <- list(a = data$a, b = data$b)
        attr(columns[[name]], "dtatools_custom") <- TRUE
        odd <- structure(columns, class = class(data), row.names = c(NA, -3L))
        expect_null(dtatools:::.dibble_row_key(odd, FALSE, FALSE, "duplicated"))
        observed <- capture_warnings_and_value(duplicated(odd))
        expect_identical(observed, capture_warnings_and_value(base_duplicated(odd)))
        expect_identical(observed$value, c(FALSE, FALSE, TRUE))
        expect_match(observed$warnings[[1L]], "Dropped unknown attribute")
    }
})

test_that("dibble row values fit their storage by the replacement rules", {
    bits <- function(high, low) {
        readBin(writeBin(c(as.integer(low), as.integer(high)), raw(), size = 4L,
                         endian = "little"), "double", endian = "little")
    }
    cases <- list(
        c(1, 2), -127, 100, -128, 101, 1.5, -32767, 32740, -32768, 32741,
        2147483620, 2147483621, -2147483647, 1.1, 3.4e38,
        2^126 * (2 - 2^-23), Inf, -Inf, NaN, NA_real_, -0, 1e308,
        unclass(tagged_missing("a")), unclass(tagged_missing("z")),
        bits(0x7ff00000L, 1955L), bits(0x7ff8007bL, 1954L), bits(0x7ff00041L, 1954L),
        c(1, NaN), c(NA, 1.5)
    )
    for (values in cases) {
        for (kind in 0:4) {
            replacement <- .Call(dtatools:::C_dtatools_replacement_fits,
                                 values, NULL, FALSE, kind)
            expect_identical(.Call(dtatools:::C_dtatools_numeric_values_fit, values, kind),
                             isTRUE(replacement))
        }
    }
})
