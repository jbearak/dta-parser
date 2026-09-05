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
    data <- reserve_columns(tibble::tibble(x = 0))
    egen(data, g = dta_group_id(x / x, missing = TRUE, label = TRUE))
    expect_identical(attr(data$g, "labels"), c("." = 1))
})
