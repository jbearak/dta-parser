.compact_merge_strings <- function(...) {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path))
    save_dta(dibble(...), path)
    read_dta(path)
}

.ordinary_merge_strings <- function(data, name) {
    data[[name]] <- unserialize(serialize(data[[name]], NULL))
    data
}

test_that("compact string keys get codes that are equal exactly when the values are", {
    x <- .compact_merge_strings(s = c("b", "", "é", "a", "b", "only x", "a"))$s
    y <- .compact_merge_strings(s = c("a", "é", "only y", "", "a"))$s
    codes <- .Call(C_dtatools_dictstring_match_codes, x, y)
    expect_identical(dtatools:::.dictstring_cached_count(x), 0)
    expect_identical(dtatools:::.dictstring_cached_count(y), 0)
    expect_type(codes[[1L]], "integer")
    expect_length(codes[[1L]], length(x))
    expect_length(codes[[2L]], length(y))
    text <- c(as.character(x), as.character(y))
    joined <- c(codes[[1L]], codes[[2L]])
    expect_identical(match(joined, joined), match(text, text))
    expect_true(all(joined > 0L))
    frames <- dtatools:::.dta_merge_key_frames(list(s = list(x = x, y = y)), "s")
    expect_identical(frames$x[["s..value"]], codes[[1L]])
    expect_identical(frames$y[["s..value"]], codes[[2L]])
    plain <- dtatools:::.dta_merge_key_frames(list(s = list(x = paste0(x), y = y)), "s")
    expect_identical(plain$x[["s..value"]], paste0(x))
    held <- .subset(x, c(1L, 4L, 4L, 1L, 2L, 4L, 1L, 4L, 2L))
    expect_true(dtatools:::.is_unmaterialized_dictstring(held))
    codes <- .Call(C_dtatools_dictstring_match_codes, held, y)
    text <- c(as.character(held), as.character(y))
    joined <- c(codes[[1L]], codes[[2L]])
    expect_identical(match(joined, joined), match(text, text))
    expect_null(.Call(C_dtatools_dictstring_match_codes, paste0(x), y))
    expect_null(.Call(C_dtatools_dictstring_match_codes, x, c("a", "b")))
    empty <- .subset(x, integer())
    if (dtatools:::.is_unmaterialized_dictstring(empty)) {
        codes <- .Call(C_dtatools_dictstring_match_codes, empty, y)
        expect_identical(codes[[1L]], integer())
    }
})

test_that("merges on compact string keys match merges on ordinary copies", {
    set.seed(20261020)
    values <- c("", "a", "ab", "a b", "B", "é", "中", sprintf("id%03d", 1:40))
    for (round in 1:12) {
        x <- .compact_merge_strings(
            k = sample(values, 60, TRUE), n = dta_int(sample(1:3, 60, TRUE)),
            xv = dta_double(seq_len(60)))
        y_keys <- sample(values, 30)
        y <- .compact_merge_strings(
            k = y_keys, n = dta_int(sample(1:3, 30, TRUE)),
            yv = dta_double(seq_len(30) / 2))
        expect_true(dtatools:::.is_unmaterialized_dictstring(x$k))
        expect_true(dtatools:::.is_unmaterialized_dictstring(y$k))
        plain_x <- .ordinary_merge_strings(x, "k")
        plain_y <- .ordinary_merge_strings(y, "k")
        merge <- function(x, y, ...) tryCatch(
            suppressWarnings(dta_merge(x, y, ..., output = "tibble")),
            error = conditionMessage)
        for (keep in list(c("x", "y", "match"), c("x", "match"), "match", "y")) {
            expect_identical(merge(x, y, by = "k", relationship = "m:1", keep = keep),
                             merge(plain_x, plain_y, by = "k", relationship = "m:1", keep = keep))
            expect_identical(merge(y, x, by = "k", relationship = "1:m", keep = keep),
                             merge(plain_y, plain_x, by = "k", relationship = "1:m", keep = keep))
        }
        expect_identical(merge(x, y, by = c("k", "n"), relationship = "m:1"),
                         merge(plain_x, plain_y, by = c("k", "n"), relationship = "m:1"))
        expect_identical(merge(x, x, by = "k", relationship = "1:1"),
                         merge(plain_x, plain_x, by = "k", relationship = "1:1"))
        expect_identical(merge(x, y, by = "k", relationship = "m:1", assert = "match"),
                         merge(plain_x, plain_y, by = "k", relationship = "m:1", assert = "match"))
    }
    duplicated <- .compact_merge_strings(k = c("a", "b", "a"), v = dta_double(1:3))
    expect_identical(
        tryCatch(dta_merge(duplicated, duplicated, by = "k", relationship = "m:1"),
                 error = conditionMessage),
        "`relationship = \"m:1\"` requires unique keys in `y`")
})

test_that("a key class with its own equality keeps its strings", {
    table <- get(".__S3MethodsTable__.", envir = asNamespace("vctrs"))
    key <- "vec_proxy_equal.merge_folded_string"
    withr::defer(rm(list = key, envir = table))
    registerS3method("vec_proxy_equal", "merge_folded_string",
                     function(x, ...) tolower(unclass(x)), envir = asNamespace("vctrs"))
    folded <- function(keys, ...) {
        frame <- data.frame(...)
        frame$k <- structure(keys, class = c("merge_folded_string", "vctrs_vctr", "character"))
        frame
    }
    x <- .compact_merge_strings(k = c("A", "b", "a"))$k
    y <- .compact_merge_strings(k = c("a", "B"))$k
    x_frame <- folded(x, xv = 1:3)
    expect_true(dtatools:::.is_unmaterialized_dictstring(x_frame$k))
    expect_null(dtatools:::.dta_merge_string_codes(x_frame$k, folded(y, yv = 1:2)$k))
    merged <- dta_merge(x_frame, folded(y, yv = 1:2), by = "k",
                        relationship = "m:1", output = "tibble")
    expect_identical(merged$yv, c(1L, 2L, 1L))
    ordinary <- function(keys) {
        values <- paste0(keys)
        attributes(values) <- attributes(keys)
        values
    }
    expect_identical(
        merged,
        dta_merge(folded(ordinary(x), xv = 1:3), folded(ordinary(y), yv = 1:2), by = "k",
                  relationship = "m:1", output = "tibble"))
})

test_that("a compact key holding a NUL byte keeps its element error", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    save_arrow(dibble(k = dta_string(rep(c("aQZb", "c", ""), 10)), v = dta_double(1:30)), path)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    matches <- grepRaw(charToRaw("aQZb"), bytes, fixed = TRUE, all = TRUE)
    expect_gte(length(matches), 1L)
    bytes[matches + 1L] <- as.raw(0)
    writeBin(bytes, path)
    x <- read_arrow(path, verify = FALSE)
    y <- .compact_merge_strings(k = c("c", ""), w = dta_double(1:2))
    expect_true(dtatools:::.is_unmaterialized_dictstring(x$k))
    expect_null(.Call(C_dtatools_dictstring_match_codes, x$k, y$k))
    expect_null(.Call(C_dtatools_dictstring_match_codes, y$k, x$k))
    expect_error(dta_merge(x, y, by = "k", relationship = "m:1"), "embedded nul")
    # Only a value that a row uses refuses the codes.
    held <- .subset(x$k, c(2L, 3L, 2L))
    expect_true(dtatools:::.is_unmaterialized_dictstring(held))
    codes <- .Call(C_dtatools_dictstring_match_codes, held, y$k)
    expect_identical(codes, list(c(1L, 2L, 1L), c(1L, 2L)))
})
