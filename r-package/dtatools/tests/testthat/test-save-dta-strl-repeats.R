test_that("strL repeats past the first string region keep one record each", {
    # More rows than one 8 MiB region of string pointers holds, so planning
    # rereads first rows that the forward region has passed.
    n <- 400000L
    long <- c(strrep("first long value ", 150), strrep("second long value ", 150))
    values <- rep("short", n)
    values[seq(1L, n, by = 7L)] <- long[[1L]]
    values[seq(4L, n, by = 11L)] <- long[[2L]]
    values[seq(2L, n, by = 13L)] <- ""
    values[[n]] <- paste0(long[[1L]], "!")
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path))
    save_dta(list2DF(list(k = dta_long(seq_len(n)), note = values)), path)
    back <- read_dta(path)
    expect_identical(as.character(back$note), values)
    expect_identical(as.double(back$k), as.double(seq_len(n)))
    # Each row holds a 4-byte long and an 8-byte strL pointer. Four distinct
    # nonempty values add a few kilobytes, where one record per repeat
    # would add hundreds of megabytes.
    expect_lt(file.info(path)$size, n * 12 + 100000)
})
