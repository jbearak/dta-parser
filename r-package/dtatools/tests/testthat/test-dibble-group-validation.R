.group_validation_frame <- function(value, key, rows, owned = FALSE) {
    if (owned) {
        value <- .Call(dtatools:::C_dtatools_capture_column, value)
        key <- .Call(dtatools:::C_dtatools_capture_column, key)
    }
    dplyr::new_grouped_df(tibble::new_tibble(list(g = value), nrow = NROW(value)),
        tibble::new_tibble(list(g = key, .rows = rows), nrow = NROW(key)))
}

.group_validation_snapshot <- function(x) list(
    values = vapply(seq_along(x), function(i) x[[i]], ""),
    encodings = Encoding(x), attributes = attributes(x),
    attribute_encodings = lapply(attributes(x), function(value)
        if (is.character(value)) Encoding(value) else NULL))

test_that("character group validation preserves equality and owned backing", {
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
        # Public matching may create a temporary encoding-normalization fork.
        # Its conservative shared flag may persist; backing and exposure must not change.
        after <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        fields <- c("backing", "exposed", "bytes", "depth")
        expect_identical(after[fields], before[fields])
        expect_identical(as.character(data$g), as.character(value))
        expect_identical(Encoding(data$g), Encoding(value))
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


test_that("encoding normalization preserves later foreign-write isolation", {
    skip_if_not_installed("data.table")
    utf8 <- enc2utf8("é")
    latin1 <- iconv(utf8, from = "UTF-8", to = "latin1")
    for (case in c("payload", "label", "names")) for (side in c("source", "copy")) {
        value <- c("a", "b", "a", NA_character_)
        key <- c("a", "b", NA_character_)
        if (case == "payload") {
            value[c(1L, 3L)] <- c(latin1, utf8); key[[1L]] <- utf8
        } else attr(value, case) <- if (case == "names") rep(latin1, 4L) else latin1
        attr(value, "stata.string.storage") <- "str8"
        expected <- .group_validation_snapshot(value)
        data <- .group_validation_frame(value, key, vctrs::list_of(c(1L, 3L), 2L, 4L), TRUE)
        before <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        expect_silent(dtatools:::.validate_group_metadata(data))
        after <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        fields <- c("backing", "exposed", "bytes", "depth")
        expect_identical(after[fields], before[fields])
        expect_identical(.group_validation_snapshot(data$g), expected)
        copy <- .Call(dtatools:::C_dtatools_capture_column, data$g)
        source_frame <- tibble::new_tibble(list(g = data$g), nrow = 4L)
        copy_frame <- tibble::new_tibble(list(g = copy), nrow = 4L)
        expect_silent(data.table::set(if (side == "source") source_frame else copy_frame,
            i = 1L, j = "g", value = "changed"))
        changed <- expected
        changed$values[[1L]] <- "changed"; changed$encodings[[1L]] <- "unknown"
        expect_identical(.group_validation_snapshot(source_frame$g), if (side == "source") changed else expected)
        expect_identical(.group_validation_snapshot(copy_frame$g), if (side == "copy") changed else expected)
    }
})

test_that("bytes-encoded group attributes retain their existing error boundary", {
    bytes <- rawToChar(as.raw(233L)); Encoding(bytes) <- "bytes"
    for (side in c("value", "key")) for (attribute in c("label", "names")) {
        value <- c("a", "b", "a"); key <- c("a", "b")
        target <- if (side == "value") value else key
        attr(target, attribute) <- if (attribute == "names") rep(bytes, length(target)) else bytes
        if (side == "value") value <- target else key <- target
        expected_value <- .group_validation_snapshot(value)
        expected_key <- .group_validation_snapshot(key)
        data <- .group_validation_frame(value, key, vctrs::list_of(c(1L, 3L), 2L), TRUE)
        expect_error(dtatools:::.validate_group_metadata(data),
            'translating strings with "bytes" encoding is not allowed', class = "simpleError")
        expect_identical(.group_validation_snapshot(data$g), expected_value)
        expect_identical(.group_validation_snapshot(attr(data, "groups")$g), expected_key)
    }
})
