.group_validation_frame <- function(value, key, rows, owned = FALSE) {
    if (owned) {
        value <- .Call(dtatools:::C_dtatools_capture_column, value)
        key <- .Call(dtatools:::C_dtatools_capture_column, key)
    }
    dplyr::new_grouped_df(tibble::new_tibble(list(g = value), nrow = NROW(value)),
        tibble::new_tibble(list(g = key, .rows = rows), nrow = NROW(key)))
}

test_that("character group validation preserves equality and owned source state", {
    utf8 <- enc2utf8("é")
    latin1 <- iconv(utf8, from = "UTF-8", to = "latin1")
    for (owned in c(FALSE, TRUE)) {
        value <- structure(c(latin1, "longer", utf8, NA_character_),
            stata.string.storage = "str1", label = "Unchanged declaration")
        key <- structure(c("unused", utf8, "longer", NA_character_),
            stata.string.storage = "str1")
        data <- .group_validation_frame(value, key,
            vctrs::list_of(integer(), c(1L, 3L), 2L, 4L), owned)
        before <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        expect_silent(dtatools:::.validate_group_metadata(data))
        expect_identical(.Call(dtatools:::C_dtatools_owned_info, data$g), before)
        expect_identical(as.character(data$g), as.character(value))
        expect_identical(attributes(data$g), attributes(value))
    }
    # Individual keys may repeat while complete group tuples are unique.
    data <- dplyr::group_by(tibble::tibble(g = c("a", "a", "b", "a"),
        h = c(1, 2, 1, 1)), g, h)
    expect_silent(dtatools:::.validate_group_metadata(data))
    attr(data, "groups")$g[1L] <- "wrong"
    expect_error(dtatools:::.validate_group_metadata(data), "keys that do not match")
    expect_silent(dtatools:::.validate_group_metadata(.group_validation_frame(
        character(), character(), vctrs::list_of(.ptype = integer()))))
})

test_that("group validation retains declaration errors and foreign length fallback", {
    for (side in c("value", "key")) for (storage in list(1L, c("byte", "int"))) {
        value <- c("b", "a", "b"); key <- c("b", "a")
        if (side == "value") attr(value, "stata.storage") <- storage else
            attr(key, "stata.storage") <- storage
        data <- .group_validation_frame(value, key, vctrs::list_of(c(1L, 3L), 2L))
        expect_error(dtatools:::.validate_group_metadata(data), "values must be")
    }
    effects <- new.env(parent = emptyenv()); effects$count <- 0L
    value <- .Call(dtatools:::C_dtatools_callback_length, c("b", "a", "b"), function() NULL)
    data <- .group_validation_frame(value, c("b", "a"), vctrs::list_of(c(1L, 3L), 2L))
    .Call(dtatools:::C_dtatools_arm_callback_character, value, function() {
        effects$count <- effects$count + 1L
        gc(FALSE)
        invisible(NULL)
    })
    expect_silent(dtatools:::.validate_group_metadata(data))
    expect_identical(effects$count, 1L)
})

test_that("ordinary character group validation avoids full key expansion allocations", {
    skip_if_not(capabilities("profmem"))
    data <- dplyr::group_by(dibble(
        g = rep(sprintf("g%03d", 1:16), length.out = 100000L),
        x = rep(TRUE, 100000L)), g)
    dtatools:::.validate_group_metadata(data)
    before <- .Call(dtatools:::C_dtatools_owned_info, data$g)
    profile <- tempfile()
    on.exit(unlink(profile), add = TRUE)
    gc(FALSE)
    Rprofmem(profile)
    tryCatch(dtatools:::.validate_group_metadata(data), finally = Rprofmem(NULL))
    lines <- readLines(profile, warn = FALSE)
    bytes <- as.double(sub(" .*", "", lines[grepl("^[0-9]+ :", lines)]))
    expect_lt(sum(bytes), 3000000)
    expect_identical(.Call(dtatools:::C_dtatools_owned_info, data$g), before)
})
