test_that("nullable Arrow strings preserve sliced validity and unequal chunks", {
    count <- 2L * 65536L + 37L
    text <- rep(c("", "plain", "caf\u00e9-\u6771\u4eac", "\U0001f30d"), length.out = count)
    text[c(2L, 5L, 65535L, 65536L, 65537L, 65540L, count)] <- NA_character_
    attr(text, "label") <- "Nullable UTF-8 text"
    attr(text, "format.stata") <- "%24s"
    data <- tibble::tibble(text = text, all_null = rep(NA_character_, count),
                           present = rep(c("", "present"), length.out = count))
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path, compression = "uncompressed")
    for (threads in c(1L, 0L)) {
        for (bounds in list(c(0L, count), c(3L, 65536L + 19L))) {
            rows <- seq.int(bounds[[1L]] + 1L, length.out = bounds[[2L]])
            actual <- read_arrow(path, skip = bounds[[1L]], n_max = bounds[[2L]],
                                 threads = threads, output = "tibble")
            expected <- data[rows, ]
            # Inspect the returned encoding before a comparison can intern or
            # normalize strings. NA and empty strings remain distinct.
            expect_identical(Encoding(actual$text), Encoding(expected$text))
            expect_identical(actual, expected)
            expect_identical(which(is.na(actual$text)), which(is.na(expected$text)))
            expect_identical(which(actual$text == ""), which(expected$text == ""))
            expect_identical(attr(actual$text, "label"), "Nullable UTF-8 text")
            expect_identical(attr(actual$text, "format.stata"), "%24s")
        }
    }
})

test_that("nullable Arrow strings keep their output rooted during collection", {
    nonce <- basename(tempfile())
    make_text <- function() c(NA_character_, "", paste0(nonce,
        c("-caf\u00e9-\u6771\u4eac", "-\U0001f30d", "-last")))
    text <- make_text()
    data <- tibble::tibble(text = text, reverse = rev(text))
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path)
    # Drop source CHARSXPs before the read, so this exercises allocation in
    # the fill loop as well as collection during vector/attribute allocation.
    rm(text, data)
    gc(full = TRUE)
    on.exit(gctorture(FALSE), add = TRUE)
    gctorture(TRUE)
    actual <- read_arrow(path, threads = 1L, output = "tibble")
    gctorture(FALSE)
    text <- make_text()
    data <- tibble::tibble(text = text, reverse = rev(text))
    expect_identical(Encoding(actual$text), Encoding(text))
    expect_identical(actual, data)
    actual$text[[3L]] <- "changed"
    expect_identical(actual$reverse, rev(text))
    expect_identical(read_arrow(path, output = "tibble"), data)
})

test_that("nullable Arrow string allocation errors clean up before the next read", {
    marker <- "nullable-arrow-embedded-nul-sentinel-04719"
    data <- tibble::tibble(text = c(NA_character_, "before", marker, "after"))
    path <- tempfile(fileext = ".arrow")
    broken <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(path, broken)), add = TRUE)
    save_arrow(data, path, compression = "uncompressed", checksums = FALSE)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    location <- grepRaw(charToRaw(marker), bytes, fixed = TRUE, all = TRUE)
    expect_length(location, 1L)
    bytes[[location[[1L]] + 8L]] <- as.raw(0L)
    writeBin(bytes, broken)
    # Embedded NUL is legal in Arrow UTF-8, but cannot become an R CHARSXP.
    expect_error(read_arrow(broken, verify = FALSE),
                 "R could not allocate a character value", fixed = TRUE)
    gc()
    expect_identical(read_arrow(path, verify = FALSE, output = "tibble"), data)
})

test_that("nullable Arrow read cancellation remains an interrupt", {
    skip_on_os("windows")
    text <- sprintf("nullable-%08d-\u00e9", seq_len(1000000L))
    text[c(1L, length(text))] <- NA_character_
    data <- tibble::tibble(text = text)
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path, compression = "uncompressed", checksums = FALSE)
    parent <- Sys.getpid()
    loadNamespace("parallel")
    request <- if (is.null(getOption("dtatools.native.context"))) NULL else
        native_fork_request("nullable-arrow-read-signal")
    signal <- parallel::mcparallel({
        if (is.null(request)) {
            Sys.sleep(0.01)
            tools::pskill(parent, tools::SIGINT)
        } else native_fork_signal(request, 0.01, tools::SIGINT)
    }, silent = TRUE)
    collected <- NULL
    completed <- FALSE
    condition <- tryCatch({
        read_arrow(path, threads = 1L, verify = FALSE)
        completed <- TRUE
        collected <- parallel::mccollect(signal)
        NULL
    }, condition = identity)
    if (is.null(collected)) collected <- tryCatch(
        suppressWarnings(parallel::mccollect(signal)), condition = identity)
    if (!is.null(request)) native_fork_finish(request, collected, signal$pid)
    expect_s3_class(condition, "interrupt")
    expect_false(completed)
    gc()
    expect_identical(read_arrow(path, n_max = 8L, verify = FALSE, output = "tibble"),
                     data[seq_len(8L), ])
})
