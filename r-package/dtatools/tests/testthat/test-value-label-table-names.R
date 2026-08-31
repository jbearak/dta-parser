value_label_name <- function(x) {
    attr(x, "value.label.name", exact = TRUE)
}

named_labelled <- function(values, labels, table = NULL) {
    result <- stata_long(values)
    attr(result, "labels") <- labels
    attr(result, "class") <- c(
        "stata_numeric", "stata_long", "haven_labelled", "vctrs_vctr",
        "double"
    )
    if (!is.null(table)) attr(result, "value.label.name") <- table
    result
}

test_that("DTA reads retain nondefault table names across releases", {
    for (file in c(
        "value_labels_v115.dta", "value_labels_v117.dta",
        "value_labels_v118.dta"
    )) {
        data <- read_dta(fixture(file), col_select = foreign)
        expect_identical(
            value_label_name(data$foreign), "foreign_lbl", info = file
        )
    }

    default <- read_dta(fixture("auto_v118.dta"), col_select = foreign)
    expect_identical(value_label_name(default$foreign), "origin")
})

test_that("shared DTA tables survive projection and emit one table record", {
    labels <- c(
        `Refusé` = tagged_missing("a"),
        `Not ascertained` = tagged_missing("a"),
        Yes = 1,
        No = 0
    )
    data <- data.frame(
        first = named_labelled(c(0, 1), labels, "answer_set"),
        second = named_labelled(c(1, 0), labels, "answer_set")
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(save_dta(data, path))
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    expect_length(grepRaw(charToRaw("<lbl>"), bytes, fixed = TRUE, all = TRUE), 1L)

    full <- read_dta(path)
    projected <- read_dta(path, col_select = second)
    expect_identical(value_label_name(full$first), "answer_set")
    expect_identical(value_label_name(full$second), "answer_set")
    expect_identical(value_label_name(projected$second), "answer_set")
    expect_identical(val_labels(full$first), val_labels(full$second))
    expect_identical(
        tracemem(val_labels(full$first)), tracemem(val_labels(full$second))
    )
})

test_that("the variable matching a shared table name still retains identity", {
    labels <- c(No = 0, Yes = 1)
    data <- data.frame(
        first = named_labelled(c(0, 1), labels, "answer"),
        answer = named_labelled(c(1, 0), labels)
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(save_dta(data, path))
    actual <- read_dta(path)
    expect_identical(value_label_name(actual$first), "answer")
    expect_identical(value_label_name(actual$answer), "answer")
})

test_that("DTA and Arrow round trips preserve table identity", {
    labels <- c(`Mañana` = 1, `拒否` = tagged_missing("z"))
    original <- data.frame(
        left = named_labelled(c(1, tagged_missing("z")), labels, "unicode_labels"),
        right = named_labelled(c(tagged_missing("z"), 1), labels, "unicode_labels")
    )
    dta <- tempfile(fileext = ".dta")
    arrow <- tempfile(fileext = ".arrow")
    via_dta <- tempfile(fileext = ".dta")
    via_arrow <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta, arrow, via_dta, via_arrow)), add = TRUE)

    save_dta(original, dta)
    from_dta <- read_dta(dta)
    expect_silent(save_arrow(from_dta, arrow))
    projected <- read_arrow(arrow, col_select = right)
    expect_identical(value_label_name(projected$right), "unicode_labels")

    save_dta(read_arrow(arrow), via_dta)
    from_second_dta <- read_dta(via_dta)
    save_arrow(from_second_dta, via_arrow)
    final <- read_arrow(via_arrow)
    expect_identical(
        lapply(final, value_label_name),
        list(left = "unicode_labels", right = "unicode_labels")
    )
    expect_identical(lapply(final, val_labels), lapply(from_dta, val_labels))
    expect_identical(lapply(final, missing_tag), lapply(from_dta, missing_tag))
})

test_that("conflicting names warn once and fall back without harming other tables", {
    data <- data.frame(
        x = named_labelled(1, c(One = 1), "conflict"),
        y = named_labelled(2, c(Two = 2), "conflict"),
        u = named_labelled(0, c(No = 0, Yes = 1), "shared_ok"),
        v = named_labelled(1, c(No = 0, Yes = 1), "shared_ok")
    )

    for (extension in c("dta", "arrow")) {
        path <- tempfile(fileext = paste0(".", extension))
        on.exit(unlink(path), add = TRUE)
        warning <- expect_warning(
            if (extension == "dta") {
                save_dta(data, path)
            } else {
                save_arrow(data, path)
            },
            class = "dtatools_write_value_label_name_conflict_warning"
        )
        expect_match(conditionMessage(warning), "`conflict`", fixed = TRUE)
        expect_match(conditionMessage(warning), "`x`, `y`", fixed = TRUE)

        actual <- if (extension == "dta") read_dta(path) else read_arrow(path)
        expect_null(value_label_name(actual$x))
        expect_null(value_label_name(actual$y))
        expect_identical(value_label_name(actual$u), "shared_ok")
        expect_identical(value_label_name(actual$v), "shared_ok")
        expect_identical(val_labels(actual$x), c(One = 1))
        expect_identical(val_labels(actual$y), c(Two = 2))
    }
})

test_that("explicit and implicit name collisions share or fall back safely", {
    identical_data <- data.frame(
        first = named_labelled(0, c(No = 0, Yes = 1), "answer"),
        answer = named_labelled(1, c(No = 0, Yes = 1))
    )
    different_data <- data.frame(
        first = named_labelled(0, c(No = 0), "answer"),
        answer = named_labelled(1, c(Yes = 1))
    )

    for (writer in list(save_dta, save_arrow)) {
        extension <- if (identical(writer, save_dta)) ".dta" else ".arrow"
        reader <- if (identical(writer, save_dta)) read_dta else read_arrow
        shared_path <- tempfile(fileext = extension)
        fallback_path <- tempfile(fileext = extension)
        on.exit(unlink(c(shared_path, fallback_path)), add = TRUE)

        expect_silent(writer(identical_data, shared_path))
        shared <- reader(shared_path)
        expect_identical(value_label_name(shared$first), "answer")
        expect_identical(value_label_name(shared$answer), "answer")

        expect_warning(
            writer(different_data, fallback_path),
            class = "dtatools_write_value_label_name_conflict_warning"
        )
        fallback <- reader(fallback_path)
        expect_null(value_label_name(fallback$first))
        expect_null(value_label_name(fallback$answer))
        expect_identical(val_labels(fallback$first), c(No = 0))
        expect_identical(val_labels(fallback$answer), c(Yes = 1))
    }
})

test_that("fallback names are checked for secondary collisions", {
    data <- data.frame(
        x = named_labelled(1, c(One = 1), "zz_conflict"),
        y = named_labelled(2, c(Two = 2), "zz_conflict"),
        z = named_labelled(3, c(Three = 3), "x")
    )

    for (writer in list(save_dta, save_arrow)) {
        extension <- if (identical(writer, save_dta)) ".dta" else ".arrow"
        reader <- if (identical(writer, save_dta)) read_dta else read_arrow
        path <- tempfile(fileext = extension)
        on.exit(unlink(path), add = TRUE)

        warning <- expect_warning(
            writer(data, path),
            class = "dtatools_write_value_label_name_conflict_warning"
        )
        expect_match(conditionMessage(warning), "`zz_conflict`", fixed = TRUE)
        expect_match(conditionMessage(warning), "`x`", fixed = TRUE)
        actual <- reader(path)
        expect_null(value_label_name(actual$x))
        expect_null(value_label_name(actual$y))
        expect_null(value_label_name(actual$z))
        expect_identical(lapply(actual, val_labels), lapply(data, val_labels))
    }
})

test_that("mapping order participates in shared-name comparison", {
    data <- data.frame(
        x = named_labelled(1, c(One = 1, Two = 2), "ordered"),
        y = named_labelled(2, c(Two = 2, One = 1), "ordered")
    )

    for (writer in list(save_dta, save_arrow)) {
        path <- tempfile(fileext = if (identical(writer, save_dta)) ".dta" else ".arrow")
        on.exit(unlink(path), add = TRUE)
        expect_warning(
            writer(data, path),
            class = "dtatools_write_value_label_name_conflict_warning"
        )
    }
})

test_that("different tagged missing codes conflict even with identical text", {
    data <- data.frame(
        x = named_labelled(tagged_missing("a"), c(Missing = tagged_missing("a")), "tags"),
        y = named_labelled(tagged_missing("b"), c(Missing = tagged_missing("b")), "tags")
    )

    for (writer in list(save_dta, save_arrow)) {
        extension <- if (identical(writer, save_dta)) ".dta" else ".arrow"
        reader <- if (identical(writer, save_dta)) read_dta else read_arrow
        path <- tempfile(fileext = extension)
        on.exit(unlink(path), add = TRUE)

        expect_warning(
            writer(data, path),
            class = "dtatools_write_value_label_name_conflict_warning"
        )
        actual <- reader(path)
        expect_identical(missing_tag(unname(val_labels(actual$x))), "a")
        expect_identical(missing_tag(unname(val_labels(actual$y))), "b")
    }
})

test_that("shared write mappings use one prepared vector", {
    labels <- stats::setNames(as.double(seq_len(1000L)), paste0("label", seq_len(1000L)))
    data <- data.frame(
        first = named_labelled(1, labels, "large_shared"),
        second = named_labelled(2, labels, "large_shared")
    )
    validation_count <- 0L
    original_validation <- dtatools:::.validate_write_value_label_structure
    local_mocked_bindings(
        .validate_write_value_label_structure = function(column, name) {
            validation_count <<- validation_count + 1L
            original_validation(column, name)
        },
        .package = "dtatools"
    )

    dta <- dtatools:::.prepare_dta_write(data, NULL, 2045L, TRUE)
    arrow <- dtatools:::.prepare_arrow_write(data, NULL, TRUE)
    expect_identical(validation_count, 2L)
    expect_identical(
        names(dta[[3L]][[1L]]),
        c(
            "name", "type_code", "format", "label", "values",
            "numeric_shift", "numeric_scale", "value_label_index"
        )
    )
    expect_identical(
        names(arrow[[3L]][[1L]]),
        c(
            "name", "kind", "values", "levels", "ordered", "label",
            "format", "storage", "tz", "units", "haven_labelled",
            "string_storage", "value_label_index"
        )
    )
    expect_length(dta[[5L]], 1L)
    expect_length(arrow[[4L]], 1L)
    expect_identical(dta[[5L]][[1L]]$label_values, unname(labels))
    expect_identical(arrow[[4L]][[1L]]$label_texts, names(labels))
    expect_identical(arrow[[3L]][[1L]]$values, data$first)
})

test_that("shared tables never hide malformed later claimants", {
    valid <- named_labelled(1, c(One = 1), "shared")
    bad <- named_labelled(1, c(One = 1), "shared")
    malformed <- matrix(1)
    attr(malformed, "names") <- "One"
    attr(bad, "labels") <- malformed

    for (data in list(
        data.frame(valid = valid, bad = bad),
        data.frame(bad = bad, valid = valid)
    )) {
        expect_error(
            save_dta(data, tempfile(fileext = ".dta")),
            "must be a named numeric vector", fixed = TRUE
        )
        expect_error(
            save_arrow(data, tempfile(fileext = ".arrow")),
            "must be a named numeric vector", fixed = TRUE
        )
    }

    invalid_factor <- factor(1, levels = 1, labels = "")
    attr(invalid_factor, "value.label.name") <- "shared"
    numeric <- named_labelled(1, stats::setNames(1, ""), "shared")
    for (data in list(
        data.frame(numeric = numeric, invalid_factor = invalid_factor),
        data.frame(invalid_factor = invalid_factor, numeric = numeric)
    )) {
        expect_error(
            save_dta(data, tempfile(fileext = ".dta")),
            "empty or missing level", fixed = TRUE
        )
    }
})

test_that("empty mappings are usable and missing mappings are malformed", {
    empty <- named_labelled(
        c(1, 2), stats::setNames(double(), character()), "empty_table"
    )
    missing <- stata_long(c(1, 2))
    attr(missing, "value.label.name") <- "missing_table"

    for (writer in list(save_dta, save_arrow)) {
        extension <- if (identical(writer, save_dta)) ".dta" else ".arrow"
        reader <- if (identical(writer, save_dta)) read_dta else read_arrow
        path <- tempfile(fileext = extension)
        on.exit(unlink(path), add = TRUE)

        expect_silent(writer(data.frame(x = empty), path))
        actual <- reader(path)$x
        expect_identical(value_label_name(actual), "empty_table")
        expect_identical(
            val_labels(actual), stats::setNames(double(), character())
        )
        expect_error(
            writer(data.frame(x = missing), path),
            "no usable `labels` mapping", fixed = TRUE
        )
    }
})

test_that("malformed table names fail before touching destinations", {
    value <- named_labelled(1, c(One = 1), "not valid")
    sentinel <- charToRaw("existing destination")

    for (extension in c("dta", "arrow")) {
        path <- tempfile(fileext = paste0(".", extension))
        writeBin(sentinel, path)
        on.exit(unlink(path), add = TRUE)
        writer <- if (extension == "dta") save_dta else save_arrow
        expect_error(writer(data.frame(x = value), path), "invalid `value.label.name`")
        expect_identical(readBin(path, "raw", n = length(sentinel)), sentinel)
    }
})

test_that("conflict warning handlers run before output starts", {
    data <- data.frame(
        x = named_labelled(1, c(One = 1), "same"),
        y = named_labelled(2, c(Two = 2), "same")
    )
    sentinel <- charToRaw("existing destination")

    for (extension in c("dta", "arrow")) {
        path <- tempfile(fileext = paste0(".", extension))
        writeBin(sentinel, path)
        on.exit(unlink(path), add = TRUE)
        writer <- if (extension == "dta") save_dta else save_arrow
        expect_error(
            withCallingHandlers(
                writer(data, path),
                dtatools_write_value_label_name_conflict_warning = function(warning) {
                    stop("warning handler stopped the write", call. = FALSE)
                }
            ),
            "warning handler stopped the write", fixed = TRUE
        )
        expect_identical(readBin(path, "raw", n = length(sentinel)), sentinel)
    }
})

test_that("metadata operations preserve or clear table identity deliberately", {
    source <- read_dta(fixture("value_labels_v118.dta"))$foreign
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
    expect_identical(value_label_name(source), "foreign_lbl")

    copied <- dtatools:::.metadata_copy(source)
    labelled <- set_variable_labels(source, "Vehicle origin")
    relabelled <- set_value_labels(source, Domestic = 0, Imported = 1)
    sliced <- vctrs::vec_slice(source, c(2L, 1L))
    for (value in list(copied, labelled, relabelled, sliced)) {
        expect_identical(value_label_name(value), "foreign_lbl")
    }
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(labelled))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(relabelled))

    cleared <- set_value_labels(source)
    expect_null(value_label_name(cleared))
    data <- data.frame(x = source, y = source)
    val_labels(data) <- list(x = c(No = 0, Yes = 1), y = NULL)
    expect_identical(value_label_name(data$x), "foreign_lbl")
    expect_null(value_label_name(data$y))
})

test_that("renaming R columns does not rename preserved tables", {
    data <- read_dta(fixture("value_labels_v118.dta"), col_select = foreign)
    names(data) <- "renamed"
    dta <- tempfile(fileext = ".dta")
    arrow <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta, arrow)), add = TRUE)

    save_dta(data, dta)
    save_arrow(data, arrow)
    expect_identical(value_label_name(read_dta(dta)$renamed), "foreign_lbl")
    expect_identical(value_label_name(read_arrow(arrow)$renamed), "foreign_lbl")
})
