test_that("datasig is container-independent and shaped as rows:columns:digest", {
    data <- tibble::tibble(
        id = stata_long(c(1, 2, 3, 4)),
        score = stata_double(c(1.5, NA_real_, tagged_missing("a"), 4.5)),
        city = c("ny", "la", "", "sf")
    )
    attr(data, "label") <- "signature fixture"

    dta_path <- tempfile(fileext = ".dta")
    arrow_path <- tempfile(fileext = ".arrow")
    compressed_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(dta_path, arrow_path, compressed_path)), add = TRUE)
    save_dta(data, dta_path)

    # Saving to DTA attaches display formats the constructed frame lacked, so
    # the file's read model is the reference: that is what a recorded raw-file
    # signature verifies against.
    reference <- read_dta(dta_path)
    signature <- datasig(reference)
    expect_match(signature, "^4:3:[0-9a-f]{16}$")
    expect_identical(datasig(reference), signature)
    expect_false(identical(datasig(data), signature))

    save_arrow(reference, arrow_path)
    save_arrow(reference, compressed_path, compression = "zstd")
    expect_identical(datasig(dta_path), signature)
    expect_identical(datasig(arrow_path), signature)
    expect_identical(datasig(compressed_path), signature)
    expect_identical(datasig(read_arrow(arrow_path)), signature)
})

test_that("datasig detects changes Stata's datasignature misses", {
    base <- tibble::tibble(
        x = stata_int(c(1, 2, 3)),
        y = stata_int(c(10, 20, 30))
    )
    signature <- datasig(base)

    # Two values swapped within one column.
    swapped_values <- base
    swapped_values$x <- stata_int(c(2, 1, 3))
    expect_false(identical(datasig(swapped_values), signature))

    # Rows reordered (Stata's signature is sort-invariant).
    sorted <- base[c(3, 1, 2), ]
    expect_false(identical(datasig(sorted), signature))

    # Values swapped between two columns of the same type.
    crossed <- tibble::tibble(x = base$y, y = base$x)
    expect_false(identical(datasig(crossed), signature))
})

test_that("datasig covers names, storage types, labels, and metadata", {
    base <- tibble::tibble(x = stata_byte(c(1, 2, 3)))
    signature <- datasig(base)

    renamed <- base
    names(renamed) <- "z"
    expect_false(identical(datasig(renamed), signature))

    widened <- tibble::tibble(x = stata_int(c(1, 2, 3)))
    expect_false(identical(datasig(widened), signature))

    labelled <- base
    attr(labelled$x, "label") <- "a variable label"
    expect_false(identical(datasig(labelled), signature))

    dataset_label <- base
    attr(dataset_label, "label") <- "a dataset label"
    expect_false(identical(datasig(dataset_label), signature))

    noted <- base
    attr(noted, "notes") <- "a note"
    expect_false(identical(datasig(noted), signature))

    value_labelled <- base
    attr(value_labelled$x, "labels") <- c(one = 1)
    expect_false(identical(datasig(value_labelled), signature))
})

test_that("datasig recomputes from current content", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    data <- tibble::tibble(x = stata_double(c(1, 2, 3)))
    save_dta(data, path)
    loaded <- read_dta(path)
    signature <- datasig(loaded)
    expect_identical(signature, datasig(path))
    loaded$x[2] <- 99
    expect_false(identical(datasig(loaded), signature))
    expect_identical(datasig(path), signature)
})

test_that("datasig validates its inputs", {
    expect_error(datasig(42), "must be a data frame or one DTA or Arrow file")
    expect_error(
        datasig(c("a.dta", "b.dta")),
        "must be a data frame or one DTA or Arrow file"
    )
    expect_error(
        datasig(tibble::tibble(x = 1), threads = -1L),
        "threads"
    )
})

test_that("datasig agrees between serial and parallel hashing", {
    rows <- 200000L
    data <- tibble::tibble(
        a = as.double(seq_len(rows)),
        b = rep(c("left", "right"), length.out = rows)
    )
    expect_identical(
        datasig(data, threads = 1L),
        datasig(data, threads = 4L)
    )
})
