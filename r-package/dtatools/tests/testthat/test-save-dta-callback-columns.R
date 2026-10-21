.saved_dta_bytes <- function(data) {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path))
    save_dta(data, path)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    # The header's timestamp differs between saves.
    open <- grepRaw(charToRaw("<timestamp>"), bytes, fixed = TRUE)
    close <- grepRaw(charToRaw("</timestamp>"), bytes, fixed = TRUE)
    bytes[seq(open + 11L, close - 1L)] <- as.raw(0)
    bytes
}

test_that("columns read through R callbacks write the same rows as direct columns", {
    set.seed(20261020)
    n <- 200000L
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path))
    save_dta(dibble(
        b = dta_byte(sample(c(1, 2, NA, tagged_missing("b")), n, TRUE)),
        l = dta_long(sample(1:1e6, n, TRUE)),
        d = dta_double(round(rnorm(n), 4)),
        s = sample(c("", "ab", "cde", "é"), n, TRUE)
    ), path)
    compact <- read_dta(path)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$b))
    expect_true(dtatools:::.is_unmaterialized_dictstring(compact$s))
    numbers <- c(-2.5, 0, 7, NA, unclass(tagged_missing("z")))[sample.int(5L, n, TRUE)]
    words <- sample(c("x", "", "yz"), n, TRUE)
    reads <- 0L
    frame <- function(number, word, string = compact$s) {
        list2DF(list(b = compact$b, x = number, l = compact$l, s = string,
                     w = word, d = compact$d))
    }
    # The probes hide their data pointers, so the writer reads them through
    # its R region callbacks; plain copies expose theirs.
    probe_number <- .Call(C_dtatools_callback_double, numbers,
                          function() reads <<- reads + 1L, TRUE)
    probe_word <- .Call(C_dtatools_callback_character, words,
                        function() reads <<- reads + 1L)
    plain <- .saved_dta_bytes(frame(numbers, words))
    expect_identical(.saved_dta_bytes(frame(probe_number, probe_word)), plain)
    expect_gt(reads, 0L)
    # An ordinary copy of the compact string takes the callback route too.
    expect_identical(.saved_dta_bytes(frame(numbers, words, paste0(compact$s))), plain)

    save_dta(frame(probe_number, probe_word), path)
    back <- read_dta(path)
    expect_identical(as.double(back$x), numbers)
    expect_identical(missing_tag(back$x), missing_tag(numbers))
    expect_identical(as.character(back$w), words)
    expect_identical(as.character(back$s), as.character(compact$s))
    expect_identical(as.double(back$b), as.double(compact$b))

    # A strL column sends every column to the row-by-row writer, whose rows
    # must read back the same.
    rowwise <- frame(probe_number, probe_word)
    rowwise$t <- c(strrep("long text ", 300), character(n - 1L))
    save_dta(rowwise, path)
    scalar <- read_dta(path)
    cells <- function(x) {
        if (is.character(x)) as.character(x) else list(as.double(x), missing_tag(x))
    }
    for (name in names(back)) {
        expect_identical(cells(scalar[[name]]), cells(back[[name]]))
    }
})

test_that("a strL column keeps every column on the row-by-row writer", {
    words <- c("short", strrep("long text ", 300), "")
    probe <- .Call(C_dtatools_callback_character, rep(words, 4), function() NULL)
    path <- tempfile(fileext = ".dta")
    withr::defer(unlink(path))
    save_dta(list2DF(list(k = dta_byte(1:12), t = probe)), path)
    back <- read_dta(path)
    expect_identical(as.character(back$t), rep(words, 4))
    expect_identical(as.double(back$k), as.double(1:12))
})
