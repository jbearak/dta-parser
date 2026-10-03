test_that("group IDs sort mixed keys and tags select first eligible rows", {
    g <- c(2, 1, 2, 1, NA, 2)
    s <- c("b", "a", "a", "a", "a", "")
    expect_identical(as.double(dta_group_id(g, s)), c(3, 1, 2, 1, NA, NA))
    expect_identical(as.double(dta_group_tag(g, s)), c(1, 1, 1, 0, 0, 0))
    expect_identical(as.double(dta_group_id(g, s, missing = TRUE)),
                     c(4, 1, 3, 1, 5, 2))
    expect_s3_class(dta_group_tag(g), "dta_byte")
    expect_identical(attr(dta_group_id(g, s), "label"), "group(g s)")
    expect_identical(as.double(dta_group_id(list(g = g, s = s))),
                     as.double(dta_group_id(g, s)))
    expect_identical(attr(dta_group_tag(data.frame(g, s)), "label"), "tag(g s)")
})

test_that("group keys preserve every missing identity and signed zero", {
    keys <- c(tagged_missing("z"), NA_real_, tagged_missing("a"),
              0, -0, tagged_missing("z"))
    expect_identical(as.double(dta_group_id(keys, missing = TRUE)),
                     c(4, 2, 3, 1, 1, 4))
    expect_identical(as.double(dta_group_tag(keys)), c(0, 0, 0, 1, 0, 0))
    all_keys <- c(1, NA_real_, tagged_missing(letters))
    expect_identical(as.double(dta_group_id(all_keys, missing = TRUE)),
                     as.double(seq_along(all_keys)))
    expect_identical(as.double(dta_group_id(c("é", "z", "a", "中"))),
                     c(3, 2, 1, 4))
})

test_that("group keys compare mixed encodings by their UTF-8 text", {
    latin <- iconv(c("é", "ö"), from = "UTF-8", to = "latin1")
    expect_identical(Encoding(latin), rep("latin1", 2L))
    keys <- rep(c(latin[1], "z", "é", latin[2], "ö", "a"), 200L)
    encoding <- Encoding(keys)
    expect_identical(as.double(dta_group_id(keys)),
                     rep(c(3, 2, 3, 4, 4, 1), 200L))
    expected_tags <- numeric(length(keys))
    expected_tags[c(1L, 2L, 4L, 6L)] <- 1
    expect_identical(as.double(dta_group_tag(keys)), expected_tags)
    expect_identical(Encoding(keys), encoding)
})

test_that("cached group text remains rooted through GC without materializing sources", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(data.frame(text = c("é", "z", "é", "ö", "ö", "a")), path)
    source <- read_dta(path)$text
    expect_true(dtatools:::.is_unmaterialized_dictstring(source))
    latin <- iconv(c("é", "z", "é", "ö", "ö", "a"),
                   from = "UTF-8", to = "latin1")
    columns <- list(source, latin)
    native <- dtatools:::C_dtatools_egen_group
    collect <- function() {
        previous <- gctorture(TRUE)
        on.exit(gctorture(previous))
        .Call(native, columns, FALSE, FALSE)
    }
    plan <- collect()
    expect_identical(plan$codes, c(3, 2, 3, 4, 4, 1))
    expect_identical(plan$first, c(6L, 2L, 1L, 4L))
    expect_true(dtatools:::.is_unmaterialized_dictstring(source))
})

test_that("group inputs and options are checked without changing sources", {
    expect_error(dta_group_id(), "at least one")
    expect_error(dta_group_id(1:2, 1), "equal lengths")
    same <- 1:2
    expect_error(dta_group_id(same, same), "names must be unique")
    expect_error(dta_group_id(list(g = same, g = same)), "names must be unique")
    expect_error(dta_group_id(matrix(1:4, 2)), "vectors")
    expect_error(dta_group_id(factor("a")), "vectors")
    expect_error(dta_group_id(structure(1, class = "integer64")), "vectors")
    expect_error(dta_group_id(structure(1, class = c("custom", "Date"))), "vectors")
    expect_error(dta_group_id(c("", NA_character_)), "NA_character_")
    expect_error(dta_group_id(c(NA, NaN)), "NaN")
    expect_error(dta_group_id(Inf), "infinit")
    expect_error(dta_group_id(1e308), "Stata|range|represent")
    expect_error(dta_group_id(structure(1e306, class = c("POSIXct", "POSIXt"))),
                 "Stata|range|represent|infinit")
    expect_error(dta_group_id(1, missing = NA), "TRUE or FALSE")
    expect_error(dta_group_tag(1, missing = 1), "TRUE or FALSE")
    expect_error(dta_group_id(1, label_name = "codes"), "label_name")
    expect_error(dta_group_id(1, label = TRUE, label_name = "1bad"), "label_name")
    expect_error(dta_group_id(1, truncate = 2), "truncate")
    expect_error(dta_group_id(1, label = TRUE, truncate = 0), "truncate")
    x <- dta_double(c(2, 1, NA))
    original <- x
    dta_group_id(x, missing = TRUE, label = TRUE)
    expect_identical(x, original)
    expect_length(dta_group_id(numeric()), 0L)
    expect_length(dta_group_tag(character()), 0L)
    expect_length(dta_group_id(numeric(), label = TRUE), 0L)
})

test_that("autotype uses Stata integer storage thresholds", {
    for (case in list(c(0, "byte"), c(100, "byte"), c(101, "int"),
                      c(32740, "int"), c(32741, "long"))) {
        result <- dta_group_id(seq_len(as.integer(case[1])), autotype = TRUE)
        expect_s3_class(result, paste0("dta_", case[2]))
    }
    expect_identical(dtatools:::.dta_group_storage(2147483620), "long")
    expect_identical(dtatools:::.dta_group_storage(2147483621), "double")
})

test_that("group labels own mappings and truncate Unicode components", {
    x <- dta_double(c(2, 1, 3))
    attr(x, "labels") <- c("été" = 1, "中 文" = 2)
    attr(x, "format.stata") <- "%9.2f"
    result <- dta_group_id(x, s = c("wide", "a", "z"),
                           label = TRUE, label_name = "groups", truncate = 2)
    expect_identical(attr(result, "labels"), c("ét a" = 1, "中 wi" = 2, "3 z" = 3))
    expect_identical(attr(result, "value.label.name"), "groups")
    expect_identical(attr(x, "labels"), c("été" = 1, "中 文" = 2))
    fallback <- dta_group_id(c(12345, NA, tagged_missing("a")),
                             missing = TRUE, label = TRUE, truncate = 1)
    expect_identical(attr(fallback, "labels"), c("12345" = 1, "." = 2, ".a" = 3))
    expect_error(dta_group_id(seq_len(65537), label = TRUE), "65,536")
    expect_length(attr(dta_group_id(seq_len(65536), label = TRUE), "labels"), 65536)
    name <- strrep("é", 80)
    long <- dta_group_id(stats::setNames(list(c(1, 2)), name))
    expect_identical(attr(long, "label"), "see notes")
    expect_identical(unname(dta_notes(long)), paste0("group(", name, ")"))
})

test_that("group metadata survives DTA and Arrow round trips", {
    x <- dta_group_id(key = c("b", "a", "b"), label = TRUE,
                      label_name = "key_codes", autotype = TRUE)
    for (format in c("dta", "arrow")) {
        path <- tempfile(fileext = paste0(".", format))
        on.exit(unlink(path), add = TRUE)
        writer <- if (format == "dta") save_dta else save_arrow
        reader <- if (format == "dta") read_dta else read_arrow
        writer(data.frame(x = x), path)
        result <- reader(path)$x
        expect_identical(as.double(result), as.double(x))
        expect_identical(attr(result, "labels"), attr(x, "labels"))
        expect_identical(attr(result, "label"), attr(x, "label"))
        expect_identical(attr(result, "value.label.name"), "key_codes")
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result))
        expect_identical(as.double(dta_group_id(result)), c(2, 1, 2))
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(result))
    }
})

test_that("group keys use encoded temporal values", {
    date <- as.Date(c("1960-01-02", "1960-01-01", NA))
    result <- dta_group_id(date, missing = TRUE, label = TRUE)
    expect_identical(as.double(result), c(2, 1, 3))
    expect_identical(attr(result, "labels"), c("0" = 1, "1" = 2, "." = 3))
    owned <- dibble(date = date)$date
    typed <- dta_group_id(owned, missing = TRUE, label = TRUE)
    expect_identical(as.double(typed), as.double(result))
    expect_identical(attr(typed, "labels"), attr(result, "labels"))
    datetime <- dibble(time = as.POSIXct(c("1960-01-02", "1960-01-01"),
                                        tz = "UTC"))$time
    timed <- dta_group_id(datetime, label = TRUE)
    expect_identical(attr(timed, "labels"), c("0" = 1, "86400000" = 2))
})

test_that("computed NaN group labels use the normalized system missing", {
    data <- dibble(x = 0)
    egen(data, g = dta_group_id(x / x, missing = TRUE, label = TRUE))
    expect_identical(attr(data$g, "labels"), c("." = 1))
})

test_that("known numeric grouping prepares each value once before sorting", {
    values <- as.double((seq_len(10000L) * 13L) %% 97L - 48L)
    expected <- as.double(match(values, sort(unique(values))))
    first <- match(sort(unique(values)), values)
    for (constructor in list(identity, dta_byte, dta_int, dta_long, dta_float, dta_double)) {
        source <- constructor(values)
        inputs <- list(source)
        if (dtatools:::.is_unmaterialized_numeric_altrep(source)) {
            inputs <- c(inputs, list(.Call(C_dtatools_owned_numeric_freeze, source, 7L)))
        }
        for (input in inputs) {
            compact <- dtatools:::.is_unmaterialized_numeric_altrep(input)
            .Call(C_dtatools_egen_group_stats, TRUE)
            plan <- .Call(C_dtatools_egen_group, list(input), FALSE, FALSE)
            counts <- .Call(C_dtatools_egen_group_stats, FALSE)
            expect_identical(as.double(plan$codes), expected)
            expect_identical(plan$first, first)
            expect_identical(counts[["scalar_values"]], 0)
            expect_identical(counts[["prepared_values"]], as.double(length(values)))
            expect_identical(counts[["prepared_bytes"]], 8 * length(values))
            expect_identical(as.double(input), values)
            expect_identical(dtatools:::.is_unmaterialized_numeric_altrep(input), compact)
        }
    }
})

test_that("prepared numeric keys preserve missing ranks zero ties and extreme doubles", {
    values <- c(-.Machine$double.xmax / 2, -1, -0, 0,
                .Machine$double.xmin * .Machine$double.eps, 1,
                .Machine$double.xmax / 2, NA_real_, tagged_missing(letters))
    expected <- as.double(c(1, 2, 3, 3, 4:33))
    permutation <- c(length(values):1L, seq_along(values), 4L, 3L)
    for (constructor in list(identity, dta_double)) {
        input <- constructor(values[permutation])
        expect_identical(as.double(dta_group_id(input, missing = TRUE)), expected[permutation])
        observed <- expected[permutation]
        observed[is.na(values[permutation])] <- NA_real_
        expect_identical(as.double(dta_group_id(input)), observed)
        tags <- as.double(!duplicated(expected[permutation]))
        expect_identical(as.double(dta_group_tag(input, missing = TRUE)), tags)
    }
    pattern <- c(3, -2, 0, -0, NA_real_, tagged_missing(letters))
    ranks <- as.double(c(3, 1, 2, 2, 4:30))
    for (constructor in list(dta_byte, dta_int, dta_long, dta_float)) {
        for (size in c(0L, 1L, 31L, 1023L, 1025L)) {
            input <- .Call(C_dtatools_owned_numeric_freeze,
                           constructor(rep_len(pattern, size)), 7L)
            # Smaller samples renumber only ranks actually present.
            expected <- as.double(match(rep_len(ranks, size), sort(unique(rep_len(ranks, size)))))
            expect_identical(as.double(dta_group_id(input, missing = TRUE)), expected)
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(input))
        }
    }
})

test_that("prepared multiple numeric keys retain stable first rows and row-major errors", {
    left <- c(2, 1, 1, 2, 1, NA, tagged_missing("a"), 1)
    right <- c(0, 2, 1, 0, 1, 0, 0, NA)
    columns <- list(.Call(C_dtatools_owned_numeric_freeze, dta_int(left), 3L),
                    .Call(C_dtatools_owned_numeric_freeze, dta_float(right), 5L))
    .Call(C_dtatools_egen_group_stats, TRUE)
    plan <- .Call(C_dtatools_egen_group, columns, TRUE, FALSE)
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(as.double(plan$codes), c(4, 2, 1, 4, 1, 5, 6, 3))
    expect_identical(plan$first, c(3L, 2L, 8L, 1L, 6L, 7L))
    expect_identical(counts[["prepared_values"]], 16)
    expect_identical(counts[["prepared_bytes"]], 128)
    expect_identical(counts[["scalar_values"]], 0)
    expect_true(all(vapply(columns, dtatools:::.is_unmaterialized_numeric_altrep, logical(1))))
    expect_error(dta_group_id(c(1, NaN), c(1e308, 0)), "Stata double storage")
    expect_error(dta_group_id(c(1, 1e308), c(NaN, 0)), "NaN|infinities")
    for (allow in c(FALSE, TRUE)) {
        for (invalid in list(Inf, -Inf, tagged_nan_for_test("A"), 1e308)) {
            expect_error(.Call(C_dtatools_egen_group, list(c(1, invalid)), TRUE, allow),
                         "NaN|infinities|Stata double storage")
        }
    }
    expect_error(.Call(C_dtatools_egen_group, list(c(1, NaN)), TRUE, FALSE), "NaN")
    normalized <- .Call(C_dtatools_egen_group, list(c(NaN, 1, NA_real_)), TRUE, TRUE)
    expect_identical(as.double(normalized$codes), c(2, 1, 2))
    expect_identical(normalized$first, c(2L, 1L))
})

test_that("foreign grouping keys preserve callbacks and decline preparation as a whole", {
    events <- character()
    first <- .Call(C_dtatools_callback_integer_after, c(2L, 1L, 2L),
                   function() events <<- c(events, "first-row-two"), 1L)
    second <- .Call(C_dtatools_callback_double, c(0, 0, 0),
                    function() events <<- c(events, "second-row-one"), TRUE)
    compact <- .Call(C_dtatools_owned_numeric_freeze, dta_int(c(1, 1, 1)), 1L)
    .Call(C_dtatools_egen_group_stats, TRUE)
    result <- .Call(C_dtatools_egen_group, list(first, compact, second), TRUE, FALSE)
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(as.double(result$codes), c(2, 1, 2))
    expect_identical(events, c("second-row-one", "first-row-two"))
    expect_identical(counts[["prepared_values"]], 0)
    expect_identical(counts[["prepared_bytes"]], 0)
    expect_gt(counts[["scalar_values"]], 9)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact))

    # The foreign key changes a known key on its first comparison, after the
    # admission scan. Preparing only the known column would miss this write.
    changed <- dta_double(c(2, 1, 2))
    pointer <- .Call(C_dtatools_owned_pointer, changed, TRUE)
    foreign <- .Call(C_dtatools_callback_integer_after, c(0L, 0L, 0L),
                     function() .Call(C_dtatools_owned_pointer_write, pointer, 1L, 0), 3L)
    .Call(C_dtatools_egen_group_stats, TRUE)
    result <- .Call(C_dtatools_egen_group, list(foreign, changed), TRUE, FALSE)
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(as.double(result$codes), c(1, 2, 3))
    expect_identical(as.double(changed), c(0, 1, 2))
    expect_identical(counts[["prepared_values"]], 0)

    # A class callback remains on the original scalar path and may materialize
    # a compact public handle while its captured bytes remain in use.
    classes <- .Call(C_dtatools_callback_character, class(compact), function() NULL)
    attr(compact, "class") <- classes
    calls <- 0L
    .Call(C_dtatools_arm_callback_character, classes, function() {
        calls <<- calls + 1L
        .force_altrep_materialization(compact)
        gc()
    })
    .Call(C_dtatools_egen_group_stats, TRUE)
    result <- .Call(C_dtatools_egen_group, list(compact), TRUE, FALSE)
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(as.double(result$codes), rep(1, 3))
    expect_identical(calls, 1L)
    expect_identical(counts[["prepared_values"]], 0)
})

test_that("prepared keys survive collection and temporal and legacy decoding", {
    for (version in c(105L, 108L, 110L, 111L)) {
        data <- read_dta(fixture(paste0("synthetic_v", version, ".dta")), output = "tibble")
        for (source in data) {
            if (!dtatools:::.is_unmaterialized_numeric_altrep(source)) next
            plain <- readBin(writeBin(as.double(source), raw(), size = 8L),
                             double(), length(source), size = 8L)
            expect_identical(as.double(dta_group_id(source, missing = TRUE)),
                             as.double(dta_group_id(plain, missing = TRUE)))
            expect_true(dtatools:::.is_unmaterialized_numeric_altrep(source))
        }
    }
    columns <- list(dta_int(c(2, 1, 2, NA)), dta_float(c(0, 0, 0, 1)))
    collect <- function() {
        previous <- gctorture(TRUE)
        on.exit(gctorture(previous))
        .Call(C_dtatools_egen_group, columns, TRUE, FALSE)
    }
    plan <- collect()
    expect_identical(as.double(plan$codes), c(2, 1, 2, 3))
    expect_identical(plan$first, c(2L, 1L, 4L))
    dates <- structure(c(-3652, -3653, -3652, NA_real_), class = "Date")
    times <- structure(c(-315619199, -315619200, -315619199, NA_real_),
                       class = c("POSIXct", "POSIXt"))
    for (input in list(dates, times)) {
        result <- .Call(C_dtatools_egen_group, list(input), TRUE, FALSE)
        expect_identical(as.double(result$codes), c(2, 1, 2, 3))
        expect_identical(result$first, c(2L, 1L, 4L))
    }
})


test_that("prepared compact IEEE NaNs obey the existing calculation scope", {
    path <- fixture_with_all_numeric_missing_codes("missing_values_v118.dta")
    on.exit(unlink(path), add = TRUE)
    patch_numeric_fixture_row(path, 0L, list(x_float = as.raw(c(1, 0, 192, 127))))
    patch_numeric_fixture_row(path, 1L, list(x_float = as.raw(c(1, 0, 192, 255))))
    patch_numeric_fixture_row(path, 2L, list(x_float = as.raw(c(0, 0, 128, 63))))
    source <- read_dta(path, col_select = "x_float", n_max = 3L)$x_float
    for (input in list(source, .Call(C_dtatools_owned_numeric_freeze, source, 1L))) {
        expect_error(.Call(C_dtatools_egen_group, list(input), TRUE, FALSE), "NaN")
        .Call(C_dtatools_egen_group_stats, TRUE)
        result <- .Call(C_dtatools_egen_group, list(input), TRUE, TRUE)
        counts <- .Call(C_dtatools_egen_group_stats, FALSE)
        expect_identical(as.double(result$codes), c(2, 2, 1))
        expect_identical(result$first, c(3L, 1L))
        expect_identical(counts[["prepared_values"]], 3)
        expect_true(dtatools:::.is_unmaterialized_numeric_altrep(input))
    }
})

test_that("bounded numeric grouping tiles preserve multicolumn order and errors", {
    rows <- seq_len(10003L)
    left <- as.double((rows * 13L) %% 7L)
    right <- as.double(rows %% 11L)
    expected <- left * 11 + right + 1
    columns <- list(.Call(C_dtatools_owned_numeric_freeze, dta_int(left), 3L),
                    .Call(C_dtatools_owned_numeric_freeze, dta_float(right / 8), 1021L))
    .Call(C_dtatools_egen_group_stats, TRUE)
    result <- .Call(C_dtatools_egen_group, columns, TRUE, FALSE)
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(as.double(result$codes), expected)
    expect_identical(result$first, match(as.double(1:77), expected))
    expect_identical(counts[["prepared_values"]], 2 * length(rows))
    expect_identical(counts[["scalar_values"]], 0)
    expect_true(all(vapply(columns, dtatools:::.is_unmaterialized_numeric_altrep, logical(1))))
    # The earlier error remains in the second column even when the later error
    # starts a new decode tile.
    expect_error(dta_group_id(c(rep(0, 4096), NaN),
                             c(rep(0, 4095), 1e308, 0)), "Stata double storage")
    for (input in list(c(2L, 1L, NA_integer_, 2L), c(TRUE, FALSE, NA, TRUE))) {
        result <- .Call(C_dtatools_egen_group, list(input), TRUE, FALSE)
        expect_identical(as.double(result$codes), c(2, 1, 3, 2))
        expect_identical(result$first, c(2L, 1L, 3L))
    }
})
