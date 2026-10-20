.compact_group_strings <- function(rows) {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path))
    save_dta(dibble(s = rows), path)
    read_dta(path)$s
}

.group_plan_counts <- function(columns, missing = TRUE) {
    .Call(C_dtatools_egen_group_stats, TRUE)
    plan <- .Call(C_dtatools_egen_group, columns, missing, FALSE)
    list(codes = as.double(plan$codes), first = plan$first,
         counts = .Call(C_dtatools_egen_group_stats, FALSE))
}

test_that("compact string keys rank their values once in Stata order", {
    values <- c("b", "", "a", "ab", "a b", "B", "é", "z", "中", "a")
    rows <- rep(values, 30)[(seq_len(300) * 37L) %% 300L + 1L]
    compact <- .compact_group_strings(rows)
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    for (missing in c(FALSE, TRUE)) {
        expect_identical(as.double(dta_group_id(compact, missing = missing)),
                         as.double(dta_group_id(rows, missing = missing)))
        expect_identical(as.double(dta_group_tag(compact, missing = missing)),
                         as.double(dta_group_tag(rows, missing = missing)))
        plan <- .group_plan_counts(list(compact), missing)
        expected <- .group_plan_counts(list(rows), missing)
        expect_identical(plan[c("codes", "first")], expected[c("codes", "first")])
        expect_identical(plan$counts[["scalar_values"]], 0)
        expect_identical(plan$counts[["prepared_values"]], 300)
        expect_identical(plan$counts[["prepared_bytes"]], 8 * 300)
    }
    expect_identical(attr(dta_group_id(compact, label = TRUE), "labels"),
                     attr(dta_group_id(rows, label = TRUE), "labels"))
    expect_identical(dtatools:::.dictstring_cached_count(compact), 0)
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    small <- .subset(compact, 1:40)
    expect_true(dtatools:::.is_unmaterialized_dictstring(small))
    collect <- function() {
        previous <- gctorture(TRUE)
        on.exit(gctorture(previous))
        .Call(C_dtatools_egen_group, list(small), FALSE, FALSE)
    }
    tortured <- collect()
    plain <- .Call(C_dtatools_egen_group, list(rows[1:40]), FALSE, FALSE)
    expect_identical(as.double(tortured$codes), as.double(plain$codes))
    expect_identical(tortured$first, plain$first)
})

test_that("compact string subsets rank only the values they hold", {
    rows <- rep(c("b", "", "a", "c", "d"), 40)
    compact <- .compact_group_strings(rows)
    keep <- which(rows != "a")
    held <- .subset(compact, keep)
    expect_true(dtatools:::.is_unmaterialized_dictstring(held))
    expect_identical(as.double(dta_group_id(held)),
                     as.double(dta_group_id(rows[keep])))
    expect_identical(as.double(dta_group_id(held, missing = TRUE)),
                     as.double(dta_group_id(rows[keep], missing = TRUE)))
    blank <- .subset(compact, rep(which(rows == "")[1:4], 20))
    expect_true(dtatools:::.is_unmaterialized_dictstring(blank))
    expect_identical(as.double(dta_group_id(blank)), rep(NA_real_, 80))
    expect_identical(as.double(dta_group_id(blank, missing = TRUE)), rep(1, 80))
})

test_that("compact string and numeric keys prepare together", {
    rows <- rep(c("b", "", "a", "a", "b", "c"), 25)
    numbers <- rep(c(2, 1, NA, 1, 2), 30)
    compact <- .compact_group_strings(rows)
    for (missing in c(FALSE, TRUE)) {
        for (order in list(1:2, 2:1)) {
            plan <- .group_plan_counts(list(compact, numbers)[order], missing)
            expected <- .group_plan_counts(list(rows, numbers)[order], missing)
            expect_identical(plan[c("codes", "first")], expected[c("codes", "first")])
            expect_identical(plan$counts[["scalar_values"]], 0)
            expect_identical(plan$counts[["prepared_values"]], 300)
        }
    }
    invalid <- replace(numbers, 7L, NaN)
    expect_identical(
        tryCatch(dta_group_id(compact, invalid), error = conditionMessage),
        tryCatch(dta_group_id(rows, invalid), error = conditionMessage))
    expect_identical(dtatools:::.dictstring_cached_count(compact), 0)
    # An ordinary string keeps the whole call on the element path.
    plan <- .group_plan_counts(list(compact, rows, numbers))
    expected <- .group_plan_counts(list(rows, rows, numbers))
    expect_identical(plan[c("codes", "first")], expected[c("codes", "first")])
    expect_identical(plan$counts[["prepared_values"]], 0)
})

test_that("foreign keys keep compact strings on the element path", {
    rows <- rep(c("b", "a", "b"), 10)
    compact <- .compact_group_strings(rows)
    events <- 0L
    foreign <- .Call(C_dtatools_callback_integer_after, rep(1L, 30L),
                     function() events <<- events + 1L, 1L)
    plan <- .group_plan_counts(list(foreign, compact))
    expect_identical(plan$codes, rep(c(2, 1, 2), 10))
    expect_identical(plan$counts[["prepared_values"]], 0)
    expect_gt(events, 0L)
})

test_that("a compact string holding a NUL byte keeps its element error", {
    path <- tempfile(fileext = ".arrow")
    withr::defer(unlink(path))
    save_arrow(dibble(s = dta_string(rep(c("aQZb", "c", ""), 30))), path)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    matches <- grepRaw(charToRaw("aQZb"), bytes, fixed = TRUE, all = TRUE)
    expect_gte(length(matches), 1L)
    bytes[matches + 1L] <- as.raw(0)
    writeBin(bytes, path)
    compact <- read_arrow(path, verify = FALSE)$s
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact))
    .Call(C_dtatools_egen_group_stats, TRUE)
    expect_error(dta_group_id(compact), "embedded nul")
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(counts[["prepared_values"]], 0)
})

test_that("egen reads every row of a compact string through a private view", {
    rows <- rep(c("b", "", "a", "c"), 30)
    compact <- .compact_group_strings(rows)
    data <- dibble(s = compact, x = dta_double(rep(1:3, 40)))
    escaped <- NULL
    keep <- function(value) { escaped <<- value; value }
    .Call(C_dtatools_egen_group_stats, TRUE)
    egen(data, g = dta_group_id(keep(s)))
    counts <- .Call(C_dtatools_egen_group_stats, FALSE)
    expect_identical(counts[["prepared_values"]], 120)
    expect_identical(as.double(data$g), as.double(dta_group_id(rows)))
    expect_true(dtatools:::.is_unmaterialized_dictstring(escaped))
    expect_identical(attributes(escaped), attributes(.subset2(data, "s")))
    expect_false(identical(rlang::obj_address(escaped),
                           rlang::obj_address(.subset2(data, "s"))))
    replace_values(data, s, "z", where = 1L)
    expect_identical(as.character(data$s)[1:2], c("z", ""))
    expect_identical(as.character(escaped), rows)
    # Rows chosen by `where` still slice the column.
    egen(data, h = dta_group_tag(s, missing = TRUE), where = x != 2)
    admitted <- as.double(data$x) != 2
    expected <- as.double(dta_group_tag(as.character(data$s)[admitted], missing = TRUE))
    expect_identical(as.double(data$h)[admitted], expected)
})

test_that("prepared keys sort by every digit and keep ties in row order", {
    reference <- function(columns) {
        ranks <- lapply(columns, function(x) match(x, sort(unique(x))))
        order <- do.call(order, ranks)
        key <- do.call(paste, c(ranks, sep = "\r"))[order]
        starts <- !duplicated(key)
        codes <- numeric(length(order))
        codes[order] <- cumsum(starts)
        list(codes = codes, first = order[starts])
    }
    rows <- 6000L
    spread <- c(-.Machine$double.xmax / 4, -2^60, -1.5, -2^-40, 0, 2^-1000,
                1, 1 + 2^-52, 3, 2^31, 2^52 + 1, 2^62, .Machine$double.xmax / 4)
    wide <- spread[(seq_len(rows) * 7L) %% length(spread) + 1L]
    narrow <- as.double((seq_len(rows) * 13L) %% 5L)
    low <- 2^40 + as.double((seq_len(rows) * 11L) %% 2049L)
    for (columns in list(list(wide), list(narrow), list(low),
                         list(narrow, wide), list(wide, narrow, low),
                         list(rep(7, rows)), list(narrow, rep(-1, rows)))) {
        plan <- .group_plan_counts(columns)
        expect_identical(plan[c("codes", "first")], reference(columns))
        expect_identical(plan$counts[["scalar_values"]], 0)
    }
    # Admitted rows keep their order when earlier rows are left out.
    gaps <- replace(narrow, seq(1L, rows, by = 3L), NA_real_)
    plan <- .group_plan_counts(list(gaps, wide), missing = FALSE)
    kept <- !is.na(gaps)
    expected <- reference(list(gaps[kept], wide[kept]))
    expect_identical(plan$codes[kept], expected$codes)
    expect_true(all(is.na(plan$codes[!kept])))
    expect_identical(plan$first, which(kept)[expected$first])
    for (size in 0:2) {
        values <- c(2, 1)[seq_len(size)]
        plan <- .group_plan_counts(list(values))
        expect_identical(plan$codes, as.double(match(values, sort(values))))
    }
})
