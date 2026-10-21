test_that("compact string widths count the bytes of the values they hold", {
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path))
    values <- c("a", "été", "日本語", "", "a wider value", "bb")
    rows <- rep(values, 50)
    save_dta(dibble(s = rows), path)
    compact <- read_dta(path)$s
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    width <- dtatools:::.dta_string_required_width
    bytes <- function(x) max(nchar(enc2utf8(x), type = "bytes"))
    expect_identical(width(compact), bytes(rows))
    expect_identical(width(as.character(compact)), 13L)
    # A subset keeps the whole dictionary but counts only its own values.
    narrower <- .subset(compact, which(rows != "a wider value"))
    expect_true(dtatools:::.is_unmaterialized_dictstring(narrower))
    expect_identical(width(narrower), bytes(rows[rows != "a wider value"]))
    expect_identical(width(narrower), 9L)
    empty <- .subset(compact, which(rows == ""))
    expect_true(dtatools:::.is_unmaterialized_dictstring(empty))
    expect_identical(width(empty), 0L)
    expect_identical(dtatools:::.dictstring_cached_count(compact), 0)
    # Other vectors keep the R measurement.
    expect_null(.Call(dtatools:::C_dtatools_dictstring_width, c("a", "bb")))
    expect_identical(width(c("a", "é")), 2L)
})

test_that("casts of compact strings into narrow storage keep their errors", {
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path))
    rows <- rep(c("short", "a wider value"), 20)
    save_dta(dibble(s = rows), path)
    compact <- read_dta(path)$s
    twin <- unserialize(serialize(compact, NULL))
    expect_false(dtatools:::.is_unmaterialized_dictstring(twin))
    narrow <- dta_string("a", storage = "str5")
    message <- function(x) tryCatch(vctrs::vec_cast(x, narrow), error = conditionMessage)
    expect_match(message(compact), "str5 storage cannot represent")
    expect_identical(message(compact), message(twin))
    wide <- dta_string("a", storage = "str13")
    expect_identical(vctrs::vec_cast(compact, wide), vctrs::vec_cast(twin, wide))
})
