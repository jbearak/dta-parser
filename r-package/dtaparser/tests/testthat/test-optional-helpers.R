test_that("haven helpers manipulate tagged missings read by dtaparser", {
    skip_if_not_installed("haven")
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)

    values <- read_dta(path, col_select = x_byte, n_max = 30)$x_byte
    expected_tags <- c(NA_character_, letters)

    expect_identical(haven::na_tag(values[seq_len(27L)]), expected_tags)
    expect_identical(
        haven::is_tagged_na(values[seq_len(27L)]),
        c(FALSE, rep(TRUE, 26L))
    )
    expect_true(haven::is_tagged_na(values, "a")[[2L]])

    values[[28L]] <- haven::tagged_na("f")
    expect_identical(haven::na_tag(values[[28L]]), "f")
    expect_true(is.na(values[[28L]]))
})

test_that("labelled getters and setters work with dtaparser metadata", {
    skip_if_not_installed("haven")
    skip_if_not_installed("labelled")
    data <- read_dta(fixture("value_labels_v118.dta"))
    values <- data$foreign
    original_data <- vctrs::vec_data(values)

    expect_identical(labelled::var_label(values), "Car origin")
    expect_identical(
        labelled::val_labels(values),
        c(Domestic = 0, Foreign = 1)
    )
    expect_identical(
        as.character(haven::as_factor(values)),
        rep(c("Foreign", "Domestic"), 5L)
    )

    labelled::var_label(values) <- "Vehicle origin"
    labelled::val_labels(values) <- c(Domestic = 0, Imported = 1)

    expect_identical(labelled::var_label(values), "Vehicle origin")
    expect_identical(
        labelled::val_labels(values),
        c(Domestic = 0, Imported = 1)
    )
    expect_identical(vctrs::vec_data(values), original_data)
    expect_s3_class(values, "haven_labelled")
    expect_identical(
        dimnames(tab(values))[[1L]], c("Domestic", "Imported")
    )

    updated <- labelled::set_variable_labels(
        data,
        foreign = "Vehicle origin",
        rep78 = "Repair rating"
    )
    updated <- labelled::set_value_labels(
        updated,
        foreign = c(Domestic = 0, Imported = 1)
    )
    expect_identical(labelled::var_label(updated$foreign), "Vehicle origin")
    expect_identical(labelled::var_label(updated$rep78), "Repair rating")
    expect_identical(
        labelled::val_labels(updated$foreign),
        c(Domestic = 0, Imported = 1)
    )
})
