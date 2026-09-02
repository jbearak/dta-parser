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

test_that("is_mi is an exported alias for is_missing", {
    expect_identical(is_mi, is_missing)
    expect_identical(
        dtatools::is_mi(c(1, NA_real_, tagged_missing("a"))),
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

test_that("is_missing treats Stata metadata markers as transparent", {
    numeric <- set_dta_note(c(1, NA_real_), 1L, "numeric note")
    character <- set_dta_characteristic(
        c("seen", "", NA_character_), "source", "survey"
    )

    expect_identical(is_missing(numeric), c(FALSE, TRUE))
    expect_identical(is_missing(character), c(FALSE, TRUE, TRUE))

    custom <- set_dta_note(
        structure(c(1, NA_real_), class = "custom"),
        1L,
        "custom note"
    )
    expect_error(is_missing(custom), "unsupported class")
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

test_that("compact non-Stata float NaNs match eager R missing semantics", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(
        path,
        row = 0L,
        values = list(x_float = .raw_little_integer(0x7fc00001, 4L))
    )
    compact <- read_dta(path, col_select = x_float, n_max = 1L)$x_float
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact))

    expect_identical(is_missing(compact), TRUE)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact))
    expect_identical(is_missing(compact), is_missing(as.double(compact)))
})

test_that("is_missing matches compact and eager Arrow numerics", {
    data <- tibble::tibble(
        value = dta_int(c(1, NA_real_, tagged_missing("m"), 2))
    )
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path)
    compact <- read_arrow(path)
    eager <- read_arrow(path, use_numeric_altrep = FALSE)

    expect_identical(is_missing(compact$value), is_missing(eager$value))
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$value))
})

test_that("is_missing leaves dictionary-string caches untouched", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    values <- rep(c("", "seen", "other"), 4L)
    save_arrow(tibble::tibble(value = values), path)
    compact <- read_arrow(path)$value
    alias <- compact
    metadata_alias <- dtatools:::.metadata_copy(compact)
    cache_before <- dtatools:::.dictstring_cached_count(compact)

    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    expect_identical(
        is_missing(compact),
        rep(c(TRUE, FALSE, FALSE), 4L)
    )
    expect_identical(
        is_missing(metadata_alias),
        rep(c(TRUE, FALSE, FALSE), 4L)
    )
    expect_identical(
        is_missing(c(NA_character_, "", "seen")),
        c(TRUE, TRUE, FALSE)
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(compact), cache_before
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(alias), cache_before
    )
    expect_identical(
        dtatools:::.dictstring_cached_count(metadata_alias), cache_before
    )
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    expect_true(dtatools:::.is_unmaterialized_dictstring(metadata_alias))
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
})

test_that("fertility-surveys egen total expressions translate exactly", {
    group_total <- function(value, group) {
        unname(ave(as.integer(value), group, FUN = sum))
    }

    # fertility_surveys d39ecc4, dhs/bh_vars/bh_birth_order.do:
    # total(!mi(bidx)) and total(!mi(cm_birth) & !mi(bidx)), by wm_id.
    dhs <- data.frame(
        wm_id = c(10, 10, 10, 20, 20, 20),
        bidx = c(1, 2, tagged_missing("a"), 1, NA_real_, 3),
        cm_birth = c(700, NA_real_, 680, 800, 790, tagged_missing("z"))
    )
    expect_identical(
        group_total(!is_missing(dhs$bidx), dhs$wm_id),
        c(2L, 2L, 2L, 2L, 2L, 2L)
    )
    expect_identical(
        group_total(
            !is_missing(dhs$cm_birth) & !is_missing(dhs$bidx),
            dhs$wm_id
        ),
        c(1L, 1L, 1L, 1L, 1L, 1L)
    )

    # fertility_surveys 77645fe, mics/bh_vars/cm_lastbirth.do:
    # total(!missing(bh_line_number)), by id.
    mics <- data.frame(
        id = c(1, 1, 1, 2, 2),
        bh_line_number = c(1, "", "3", NA_character_, "2")
    )
    expect_identical(
        group_total(!is_missing(mics$bh_line_number), mics$id),
        c(2L, 2L, 2L, 1L, 1L)
    )
})
