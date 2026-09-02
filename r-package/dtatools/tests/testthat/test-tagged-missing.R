test_that("tagged_missing creates canonical Stata extended missings", {
    tags <- structure(
        matrix(c("a", "Z"), nrow = 1L),
        dimnames = list("row" = "first", "column" = c("low", "high")),
        names = c("first tag", "second tag"),
        provenance = "input"
    )

    values <- tagged_missing(tags)

    expect_identical(
        list(
            missing = is.na(values),
            bytes = lapply(as.vector(values), function(value) {
                writeBin(value, raw(), size = 8L, endian = "big")
            }),
            dimensions = dim(values),
            dimension_names = dimnames(values),
            names = names(values),
            provenance = attr(values, "provenance", exact = TRUE)
        ),
        list(
            missing = matrix(
                rep(TRUE, 2L),
                nrow = 1L,
                dimnames = list(
                    "row" = "first", "column" = c("low", "high")
                )
            ),
            bytes = list(
                as.raw(c(0x7f, 0xf0, 0x00, 0x61, 0x00, 0x00, 0x07, 0xa2)),
                as.raw(c(0x7f, 0xf0, 0x00, 0x7a, 0x00, 0x00, 0x07, 0xa2))
            ),
            dimensions = c(1L, 2L),
            dimension_names = list(
                "row" = "first", "column" = c("low", "high")
            ),
            names = c("first tag", "second tag"),
            provenance = NULL
        )
    )
})

test_that("missing_tag inspects imported missing codes without materializing", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    values <- read_dta(path, col_select = x_byte, n_max = 30)$x_byte

    tags <- missing_tag(values)

    expect_identical(
        list(
            tags = tags[seq_len(27L)],
            source_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(values)
        ),
        list(
            tags = c(NA_character_, letters),
            source_is_unmaterialized = TRUE
        )
    )
})

test_that("is_tagged_missing matches one or more tags without materializing", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    values <- read_dta(path, col_select = x_byte, n_max = 30)$x_byte

    any_tag <- is_tagged_missing(values)
    selected_tags <- is_tagged_missing(values, c("A", "f"))

    expect_identical(
        list(
            any_tag = any_tag[seq_len(27L)],
            selected_tags = selected_tags[seq_len(27L)],
            source_is_unmaterialized =
                dtatools:::.is_unmaterialized_numeric_altrep(values)
        ),
        list(
            any_tag = c(FALSE, rep(TRUE, 26L)),
            selected_tags = c(FALSE, letters %in% c("a", "f")),
            source_is_unmaterialized = TRUE
        )
    )
})

test_that("tagged-missing inspectors reject nonnumeric vectors", {
    invalid <- list(
        character = c("a", "b"),
        factor = factor(c("a", "b")),
        list = list(1, 2)
    )

    rejected <- vapply(invalid, function(value) {
        calls <- list(
            function() missing_tag(value),
            function() is_tagged_missing(value)
        )
        all(vapply(calls, function(call) {
            inherits(try(call(), silent = TRUE), "try-error")
        }, logical(1)))
    }, logical(1))

    expect_identical(
        rejected,
        setNames(rep(TRUE, length(invalid)), names(invalid))
    )
})

test_that("tag arguments reject values outside Stata's extended missings", {
    invalid <- list(
        system_missing = ".",
        empty = "",
        missing = NA_character_,
        long = "ab",
        punctuation = "?",
        multibyte = "é",
        non_character = 1L
    )

    rejected <- vapply(invalid, function(tag) {
        calls <- list(
            function() tagged_missing(tag),
            function() is_tagged_missing(1, tag)
        )
        all(vapply(calls, function(call) {
            inherits(try(call(), silent = TRUE), "try-error")
        }, logical(1)))
    }, logical(1))

    expect_identical(
        rejected,
        setNames(rep(TRUE, length(invalid)), names(invalid))
    )
})

test_that("inspectors preserve shape but not source metadata", {
    values <- structure(
        matrix(c(tagged_missing("a"), NA_real_, 1, tagged_missing("z")),
               nrow = 2L),
        dimnames = list(row = c("first", "second"), column = c("x", "y")),
        names = c("first value", "second value", "third value", "fourth value"),
        label = "Source variable",
        provenance = "imported"
    )

    tags <- missing_tag(values)
    selected <- is_tagged_missing(values, character())
    integers <- structure(c(1L, NA_integer_), names = c("one", "missing"))

    expect_identical(
        list(
            tags = tags,
            tags_label = attr(tags, "label", exact = TRUE),
            tags_provenance = attr(tags, "provenance", exact = TRUE),
            tags_names = names(tags),
            selected = selected,
            selected_names = names(selected),
            integer_tags = missing_tag(integers),
            integer_selected = is_tagged_missing(integers)
        ),
        list(
            tags = structure(
                matrix(
                    c("a", NA_character_, NA_character_, "z"),
                    nrow = 2L,
                    dimnames = list(
                        row = c("first", "second"), column = c("x", "y")
                    )
                ),
                names = c(
                    "first value", "second value", "third value", "fourth value"
                )
            ),
            tags_label = NULL,
            tags_provenance = NULL,
            tags_names = c(
                "first value", "second value", "third value", "fourth value"
            ),
            selected = structure(
                matrix(
                    rep(FALSE, 4L),
                    nrow = 2L,
                    dimnames = list(
                        row = c("first", "second"), column = c("x", "y")
                    )
                ),
                names = c(
                    "first value", "second value", "third value", "fourth value"
                )
            ),
            selected_names = c(
                "first value", "second value", "third value", "fourth value"
            ),
            integer_tags = c(one = NA_character_, missing = NA_character_),
            integer_selected = c(one = FALSE, missing = FALSE)
        )
    )
})

test_that("inspectors reject noncanonical NaN payloads", {
    value <- readBin(
        as.raw(c(0x7f, 0xf8, 0x00, 0x61, 0x00, 0x00, 0x00, 0x01)),
        "double",
        n = 1L,
        size = 8L,
        endian = "big"
    )

    expect_identical(
        list(tag = missing_tag(value), selected = is_tagged_missing(value)),
        list(tag = NA_character_, selected = FALSE)
    )
})

test_that("extended missing constants match the tagged missing constructor", {
    constants <- mget(paste0(".", letters), asNamespace("dtatools"))

    expect_identical(unname(unlist(constants)), tagged_missing(letters))
    expect_identical(.a, tagged_missing("a"))
    expect_identical(.z, tagged_missing("z"))
})
