# Stage 6 row-operation regression coverage; adapted sources are in inst/NOTICE.
# Adapted policy cases: dplyr 95740975 R/slice.R and test-slice.R.

test_that("S6-S01 slice validates dots before combining signs and dropping indices", {
    data <- dibble(id = 1:4)
    expect_identical(.s6_ids(dplyr::slice(data)), integer())
    expect_identical(.s6_ids(dplyr::slice(data, c(4, 2, 2, 0, NA, 99))), c(4L, 2L, 2L))
    expect_identical(.s6_ids(dplyr::slice(data, c(-2, -2, -99, 0, NA))), c(1L, 3L, 4L))
    expect_identical(.s6_ids(dplyr::slice(data, 3L, 1L)), c(3L, 1L))
    expect_error(dplyr::slice(data, 1L, -2L))
    for (index in list(TRUE, "1", 1.1, list(1L))) expect_error(dplyr::slice(data, index))
    expect_error(dplyr::slice(data, x = 1L))
    events <- character()
    expect_error(dplyr::slice(data, { events <<- c(events, "bad"); TRUE },
                                   { events <<- c(events, "later"); 1L }))
    expect_identical(events, "bad")
    events <- character()
    expect_error(dplyr::slice(data, { events <<- c(events, "positive"); 1L },
                                   { events <<- c(events, "negative"); -1L }))
    expect_identical(events, c("positive", "negative"))
    withr::local_options(lifecycle_verbosity = "warning")
    expect_warning(out <- dplyr::slice(data, matrix(c(3L, 1L), ncol = 1L)), "matrix")
    expect_identical(.s6_ids(out), c(3L, 1L))
})

test_that("S6-S02 slice preserves empty group keys only when policy requires it", {
    data <- dplyr::group_by(dibble(id = 1:3, g = c("a", "b", "b")), g)
    out <- dplyr::slice(data, 2L, .preserve = TRUE)
    expect_identical(.s6_ids(out), 3L)
    expect_identical(as.character(dplyr::group_keys(out)$g), c("a", "b"))
    expect_identical(as.list(dplyr::group_rows(out)), list(integer(), 1L))
    out <- dplyr::slice(data, 2L)
    expect_identical(as.character(dplyr::group_keys(out)$g), "b")
    retained <- dplyr::group_by(dibble(id = 1:2,
        g = factor(c("a", "b"), levels = c("a", "b", "c"))), g, .drop = FALSE)
    expect_identical(as.character(dplyr::group_keys(dplyr::slice(retained, 2L))$g),
                     c("a", "b", "c"))
    rowwise <- dplyr::rowwise(dibble(id = 1:2, g = c("b", "a")), g)
    out <- dplyr::slice(rowwise, c(1L, 1L))
    expect_identical(.s6_ids(out), c(1L, 1L, 2L, 2L))
    expect_s3_class(out, "rowwise_df")
    expect_identical(as.list(dplyr::group_rows(out)), as.list(1:4))
})

test_that("S6-S03 head and tail apply group-sized signed n and prop arithmetic", {
    data <- dplyr::group_by(dibble(id = 1:6, g = c(1, 2, 2, 3, 3, 3)), g)
    expect_identical(.s6_ids(dplyr::slice_head(data)), c(1L, 2L, 4L))
    expect_identical(.s6_ids(dplyr::slice_tail(data)), c(1L, 3L, 6L))
    expect_identical(.s6_ids(dplyr::slice_head(data, n = -1)), c(2L, 4L, 5L))
    expect_identical(.s6_ids(dplyr::slice_tail(data, n = -1)), c(3L, 5L, 6L))
    expect_identical(.s6_ids(dplyr::slice_head(data, prop = .5)), c(2L, 4L))
    expect_identical(.s6_ids(dplyr::slice_tail(data, prop = -.5)), c(1L, 3L, 5L, 6L))
    for (verb in list(dplyr::slice_head, dplyr::slice_tail)) {
        expect_identical(.s6_ids(verb(data, n = 100)), 1:6)
        expect_identical(.s6_ids(verb(data, n = Inf)), 1:6)
        expect_identical(.s6_ids(verb(data, prop = Inf)), 1:6)
        expect_identical(.s6_ids(verb(data, n = -Inf)), integer())
        expect_identical(.s6_ids(verb(data, prop = -Inf)), integer())
    }
})

test_that("S6-S04 helper controls are caller constants with by spelling", {
    data <- dibble(id = 1:4, g = c("b", "a", "b", "a"), n = c(4, 3, 2, 1))
    n <- 1L
    for (verb in list(dplyr::slice_head, dplyr::slice_tail, dplyr::slice_sample)) {
        counter <- new.env(parent = emptyenv())
        counter$calls <- 0L
        out <- verb(data, n = { counter$calls <- counter$calls + 1L; 1L }, by = g)
        expect_identical(counter$calls, 1L)
        expect_identical(nrow(out), 2L)
        expect_identical(dplyr::group_vars(out), character())
        expect_error(verb(data, n = 1, prop = .5))
        expect_error(verb(data, n = 1.1))
        expect_error(verb(data, n = NA_real_))
        expect_identical(nrow(verb(data, n = n, by = g)), 2L)
        expect_error(verb(data, n = dplyr::n()), "constant")
        expect_error(verb(data, 2L))
        expect_error(verb(data, .by = g))
    }
    expect_identical(.s6_ids(dplyr::slice_head(data, by = g)), c(1L, 2L))
    expect_identical(.s6_ids(dplyr::slice_tail(data, by = g)), c(3L, 4L))
    # order_by is masked even when named n; n= remains outside that mask.
    expect_identical(.s6_ids(dplyr::slice_min(data, n, n = 1L, by = g)), c(3L, 4L))
    expect_identical(.s6_ids(dplyr::slice_max(data, n, n = 1L, by = g)), c(1L, 2L))
})

test_that("S6-S05 min and max retain rank order, ties and exact key size", {
    data <- dibble(id = 1:4, x = c(2, 3, 1, 2), with_ties = 1:4, na_rm = 1:4)
    expect_identical(.s6_ids(dplyr::slice_min(data, x, n = 2)), c(3L, 1L, 4L))
    expect_identical(.s6_ids(dplyr::slice_max(data, x, n = 2)), c(2L, 1L, 4L))
    expect_identical(.s6_ids(dplyr::slice_min(data, x, n = 2, with_ties = FALSE)), c(3L, 1L))
    expect_identical(.s6_ids(dplyr::slice_max(data, x, n = 2, with_ties = FALSE)), c(2L, 1L))
    for (verb in list(dplyr::slice_min, dplyr::slice_max)) {
        expect_error(verb(data, 1L), "size")
        expect_error(verb(data, x, with_ties = 1))
        expect_error(verb(data, x, na_rm = NA))
        expect_error(verb(data, x, n = 1, prop = .5))
        expect_error(verb(data, x, n = 1.1))
        expect_identical(.s6_ids(verb(data, x, n = -1, with_ties = FALSE)),
                         .s6_ids(verb(data, x, n = 3, with_ties = FALSE)))
    }
    # Logical NA remains ordinary missing data; numeric dibble NAs have Stata semantics.
    missing <- dibble(id = 1:3, key = c(TRUE, NA, NA), na_rm = 1:3)
    expect_identical(.s6_ids(dplyr::slice_min(missing, key, n = 2)), 1:3)
    expect_identical(.s6_ids(dplyr::slice_max(missing, key, n = 2, na_rm = TRUE)), 1L)
    multi <- dibble(id = 1:3, a = c(TRUE, FALSE, NA), b = c(TRUE, NA, NA))
    expect_identical(.s6_ids(dplyr::slice_min(multi, tibble::tibble(a, b), n = 3, na_rm = TRUE)), 1L)
})

test_that("S6-S06 sample validates weights before zero selection without drawing RNG", {
    withr::local_seed(913)
    data <- dibble(id = 1:3, wt = c(1, 0, 0), replace = 1:3)
    before <- .Random.seed
    calls <- 0L
    out <- dplyr::slice_sample(data, n = 0L,
        weight_by = { calls <<- calls + 1L; c(-1, -1, -1) })
    expect_identical(nrow(out), 0L)
    expect_identical(calls, 1L)
    expect_identical(.Random.seed, before)
    expect_error(dplyr::slice_sample(data, n = 0L, weight_by = 1:2), "size")
    expect_identical(.Random.seed, before)
    expect_error(dplyr::slice_sample(data, n = 1L, weight_by = c(-1, -1, -1)))
    expect_error(dplyr::slice_sample(data, replace = NA))
    expect_identical(.s6_ids(dplyr::slice_sample(data, n = 3L, weight_by = wt, replace = TRUE)),
                     rep(1L, 3))
    expect_identical(nrow(dplyr::slice_sample(data, n = 5, replace = FALSE)), 3L)
    expect_identical(nrow(dplyr::slice_sample(data, n = 5, replace = TRUE)), 5L)
    expect_identical(nrow(dplyr::slice_sample(data, prop = -.5)), 2L)
    expect_identical(nrow(dplyr::slice_sample(data, n = -4)), 0L)
})

test_that("S6-S07 seeded sampling matches the ordinary typed-frame oracle and RNG state", {
    # This is an integration oracle, not a hard-coded cross-R sample sequence.
    for (grouped in c(FALSE, TRUE)) for (replace in c(FALSE, TRUE)) {
        data <- dibble(id = 1:6, g = c("b", "a", "b", "a", "b", "a"),
                       wt = c(1, 2, 3, 4, 5, 6))
        if (grouped) data <- dplyr::group_by(data, g)
        plain <- dtatools:::.reference_snapshot(data)
        withr::local_seed(617)
        expected <- dplyr::slice_sample(plain, n = 2L, weight_by = wt, replace = replace)
        expected_seed <- .Random.seed
        set.seed(617)
        actual <- dplyr::slice_sample(data, n = 2L, weight_by = wt, replace = replace)
        expect_identical(.s6_ids(actual), .s6_ids(expected))
        expect_identical(.Random.seed, expected_seed)
        expect_identical(dplyr::group_vars(actual), dplyr::group_vars(expected))
        expect_identical(dplyr::group_rows(actual), dplyr::group_rows(expected))
    }
})
