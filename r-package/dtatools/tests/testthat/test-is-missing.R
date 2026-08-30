test_that("is_missing classifies Stata and R missing values", {
    numeric_values <- c(
        -Inf, -1, 0, Inf, NA_real_, NaN, tagged_missing(c("a", "z"))
    )

    expect_identical(
        is_missing(numeric_values),
        c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE)
    )
    expect_identical(
        is_missing(c(TRUE, FALSE, NA)),
        c(FALSE, FALSE, TRUE)
    )
    expect_identical(
        is_missing(c("text", "", NA_character_)),
        c(FALSE, TRUE, TRUE)
    )
})

test_that("is_missing uses rowwise any with size-one recycling", {
    expect_identical(
        is_missing(c(1, NA), c("", "x")),
        c(TRUE, TRUE)
    )
    expect_identical(
        is_missing(c(1, 2, NA), ""),
        rep(TRUE, 3L)
    )
    expect_identical(
        is_missing(NA_real_, c("x", "y")),
        c(TRUE, TRUE)
    )

    expect_error(is_missing(), "requires at least one argument")
    expect_error(
        is_missing(1:2, 1:3),
        "size 3.*argument 1 of size 2.*size-one recycling"
    )
    expect_error(
        is_missing(double(), 1:2),
        "size 2.*argument 1 of size 0.*size-one recycling"
    )
})

test_that("is_missing handles zero-length vectors and names", {
    expect_identical(is_missing(double()), logical())
    expect_identical(is_missing(character(), NA_real_), logical())

    x <- c(first = 1, second = NA_real_)
    y <- c(left = "x", right = "")
    expect_identical(is_missing(x, y), c(first = FALSE, second = TRUE))
    expect_identical(
        is_missing(1, y),
        c(left = FALSE, right = TRUE)
    )
})

test_that("is_missing supports semantic atomic classes", {
    dates <- as.Date(c("2020-01-01", NA))
    datetimes <- as.POSIXct(
        c("2020-01-01 00:00:00", NA), tz = "UTC"
    )
    labelled_strings <- labelled_for_test(c("seen", "", NA_character_))
    labelled_numbers <- labelled_for_test(c(1, NA_real_))

    expect_identical(is_missing(dates), c(FALSE, TRUE))
    expect_identical(is_missing(datetimes), c(FALSE, TRUE))
    expect_identical(
        is_missing(labelled_strings), c(FALSE, TRUE, TRUE)
    )
    expect_identical(is_missing(labelled_numbers), c(FALSE, TRUE))
})

test_that("is_missing rejects containers and unsupported classes", {
    invalid <- list(
        factor = factor(c("", "seen")),
        matrix = matrix(c(1, NA_real_), nrow = 1L),
        array = array(c(1, NA_real_), dim = c(1L, 1L, 2L)),
        list = list(1, NA_real_),
        data_frame = data.frame(x = c(1, NA_real_)),
        posixlt = as.POSIXlt(c("2020-01-01", NA), tz = "UTC"),
        difftime = as.difftime(c(1, NA), units = "days"),
        raw = as.raw(c(0, 1)),
        complex = c(1 + 1i, NA_complex_),
        custom = structure(c(1, NA_real_), class = "custom")
    )

    for (name in names(invalid)) {
        expect_error(is_missing(invalid[[name]]), info = name)
    }
})

test_that("is_missing preserves tagged payloads and does not mutate attributes", {
    values <- structure(
        c(1, tagged_missing("f"), NA_real_),
        names = c("one", "tag", "system"),
        label = "source",
        provenance = "fixture"
    )
    before <- serialize(values, NULL)

    result <- is_missing(values)

    expect_identical(result, c(one = FALSE, tag = TRUE, system = TRUE))
    expect_identical(serialize(values, NULL), before)
    expect_identical(
        missing_tag(values),
        c(one = NA_character_, tag = "f", system = NA_character_)
    )
    expect_null(attr(result, "label", exact = TRUE))
    expect_null(attr(result, "provenance", exact = TRUE))
})

test_that("is_missing inspects compact DTA numerics without materializing", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    values <- read_dta(path, col_select = x_byte, n_max = 30)$x_byte

    result <- is_missing(values)

    expect_identical(result[seq_len(27L)], rep(TRUE, 27L))
    expect_false(any(result[-seq_len(27L)]))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(values))
})

test_that("is_missing matches compact and eager Arrow numerics", {
    data <- tibble::tibble(
        value = stata_int(c(1, NA_real_, tagged_missing("m"), 2))
    )
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path)
    compact <- read_arrow(path)
    eager <- read_arrow(path, use_numeric_altrep = FALSE)

    expect_identical(is_missing(compact$value), is_missing(eager$value))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$value))
})

test_that("is_missing works in bare and stored data-mask expressions", {
    data <- data.frame(
        woman = c(1, 1, 2, 2),
        bh_line_number = c(1, NA_real_, tagged_missing("a"), 2),
        birth_order = c(1, 2, NA_real_, tagged_missing("z"))
    )
    bare <- rlang::expr(!is_missing(bh_line_number))
    stored <- ~ !is_missing(birth_order)

    expect_identical(
        rlang::eval_tidy(bare, data),
        c(TRUE, FALSE, FALSE, TRUE)
    )
    expect_identical(
        rlang::eval_tidy(rlang::f_rhs(stored), data, env = environment(stored)),
        c(TRUE, TRUE, FALSE, FALSE)
    )

    # Translations of fertility-surveys' `egen total(!mi(...)), by(...)`
    # and `egen total(!missing(...)), by(...)` expression shapes.
    count_observed <- function(value, group) {
        unname(ave(!is_missing(value), group, FUN = sum))
    }
    expect_identical(
        count_observed(data$bh_line_number, data$woman),
        c(1L, 1L, 1L, 1L)
    )
    expect_identical(
        count_observed(data$birth_order, data$woman),
        c(2L, 2L, 0L, 0L)
    )
})
