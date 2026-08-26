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
