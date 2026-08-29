# Output files live under the session tempdir, which R removes at exit.
arrow_tempfile <- function() {
    tempfile(fileext = ".arrow")
}

standard_arrow_fixture <- function() {
    data <- tibble::tibble(
        lgl = c(TRUE, NA, FALSE, TRUE),
        n = c(1L, NA, 3L, -7L),
        x = c(1.5, NA, 3.25, -0.5),
        s = c("alpha", NA, "", "éè"),
        f = factor(
            c("lo", "hi", NA, "lo"),
            levels = c("lo", "hi", "unused"),
            ordered = TRUE
        ),
        b = as.raw(c(0L, 255L, 7L, 128L)),
        day = as.Date(c("2020-02-29", NA, "1959-12-31", "1970-01-01")),
        ts = as.POSIXct(
            c("2020-01-01 12:34:56.25", NA, "1969-12-31 23:59:59", "2020-06-01 00:00:00"),
            tz = "America/New_York"
        ),
        dt = as.difftime(c(1.5, NA, -2, 0), units = "hours")
    )
    attr(data, "label") <- "standard fixture"
    attr(data, "notes") <- c("first note", "second note")
    attr(data$x, "label") <- "a double"
    data
}

test_that("standard R columns round-trip with full fidelity", {
    data <- standard_arrow_fixture()
    path <- arrow_tempfile()

    expect_identical(expect_invisible(save_arrow(data, path)), data)

    actual <- read_arrow(path)
    expect_identical(actual, data)
    expect_type(actual$n, "integer")
    expect_type(actual$x, "double")
    expect_true(is.ordered(actual$f))
    expect_identical(levels(actual$f), c("lo", "hi", "unused"))
    expect_identical(attr(actual$ts, "tzone"), "America/New_York")
    expect_identical(attr(actual$dt, "units"), "hours")
    expect_identical(typeof(actual$b), "raw")
})

test_that("compression variants round-trip identically", {
    data <- standard_arrow_fixture()
    for (compression in c("uncompressed", "lz4", "zstd")) {
        path <- tempfile(fileext = ".arrow")
        on.exit(unlink(path), add = TRUE)
        save_arrow(data, path, compression = compression)
        expect_identical(read_arrow(path), data, info = compression)
    }
})

test_that("profiled Stata columns keep raw missing storage bit-exactly", {
    data <- tibble::tibble(
        b = stata_byte(c(-5, NA, tagged_missing("a"), tagged_missing("z"))),
        i = stata_int(c(3000, tagged_missing("q"), NA, 1)),
        l = stata_long(c(1234567, NA, tagged_missing("c"), -1)),
        f = stata_float(c(1.5, tagged_missing("m"), NA, -2.25)),
        d = stata_double(c(1.5, NA, tagged_missing("z"), 3e300))
    )
    path <- arrow_tempfile()
    dta <- tempfile(fileext = ".dta")
    on.exit(unlink(dta), add = TRUE)
    save_arrow(data, path)
    save_dta(data, dta)

    actual <- read_arrow(path)
    # The DTA round trip is the raw-Stata-missing-storage oracle: both paths
    # must materialize the same doubles, bit for bit, from the same source.
    reference <- read_dta(dta)
    for (name in names(data)) {
        expect_identical(
            stata_storage_type(actual[[name]]),
            stata_storage_type(data[[name]]),
            info = name
        )
        expect_identical(
            missing_tag(actual[[name]]), missing_tag(data[[name]]),
            info = name
        )
        expect_identical(
            as.double(actual[[name]]), as.double(data[[name]]),
            info = name
        )
        expect_identical(
            writeBin(as.double(actual[[name]]), raw()),
            writeBin(as.double(reference[[name]]), raw()),
            info = name
        )
    }
})

test_that("profiled columns read back as compact ALTREP by default", {
    data <- tibble::tibble(
        b = stata_byte(c(1, NA, tagged_missing("a"))),
        d = stata_double(c(1.5, NA, 3))
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    compact <- read_arrow(path)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$b))
    eager <- read_arrow(path, use_numeric_altrep = FALSE)
    expect_false(dtatools:::.is_unmaterialized_numeric_altrep(eager$b))
    expect_identical(missing_tag(eager$b), missing_tag(data$b))
})

test_that("string columns without missing values defer through ALTREP", {
    data <- tibble::tibble(
        s = rep(c("alpha", "beta", "", "éè"), 25L),
        m = rep(c("kept", NA, "also kept", "kept"), 25L)
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_true(dtatools:::.is_altrep(actual$s))
    # The dictionary-string ALTREP class cannot represent NA_character_, so
    # null-bearing columns materialize eagerly.
    expect_false(dtatools:::.is_altrep(actual$m))
    expect_identical(actual, data)
})

test_that("multithreaded Arrow reads match single-threaded reads", {
    data <- standard_arrow_fixture()
    path <- arrow_tempfile()
    save_arrow(data, path)

    serial <- read_arrow(path, threads = 1L)
    parallel <- read_arrow(path, threads = 4L)
    expect_identical(parallel, serial)
    expect_identical(serial, data)

    eager <- read_arrow(path, threads = 4L, use_numeric_altrep = FALSE)
    expect_identical(eager, read_arrow(path, threads = 1L,
                                       use_numeric_altrep = FALSE))
})

test_that("read_arrow validates threads", {
    data <- tibble::tibble(x = 1)
    path <- arrow_tempfile()
    save_arrow(data, path)

    expect_error(read_arrow(path, threads = -1),
                 "non-negative whole number")
    expect_error(read_arrow(path, threads = 1.5),
                 "non-negative whole number")
    expect_error(read_arrow(path, threads = NA_integer_),
                 "non-negative whole number")
    expect_identical(read_arrow(path, threads = 2L), data)
})

test_that("compact ALTREP columns are written without materializing", {
    dta <- tempfile(fileext = ".dta")
    path <- arrow_tempfile()
    on.exit(unlink(dta), add = TRUE)
    save_dta(tibble::tibble(v = stata_int(c(1, NA, tagged_missing("k")))), dta)

    imported <- read_dta(dta)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(imported$v))
    save_arrow(imported, path)
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(imported$v))

    actual <- read_arrow(path)
    expect_identical(missing_tag(actual$v), missing_tag(imported$v))
    expect_identical(as.double(actual$v), as.double(imported$v))
    expect_identical(stata_storage_type(actual$v), "int")
})

test_that("a DTA fixture survives a semantic Arrow round-trip", {
    data <- read_dta(fixture("auto_v118.dta"))
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(names(actual), names(data))
    expect_identical(attr(actual, "label", exact = TRUE),
                     attr(data, "label", exact = TRUE))
    for (name in names(data)) {
        expect_identical(as.vector(actual[[name]]), as.vector(data[[name]]),
                         info = name)
        expect_identical(attributes(actual[[name]]),
                         attributes(data[[name]]), info = name)
    }
})

test_that("tagged NaN payloads on bare doubles survive bit-exactly", {
    values <- c(1.5, tagged_nan_for_test("q"), NA_real_)
    data <- tibble::tibble(x = values)
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(writeBin(actual$x, raw()), writeBin(values, raw()))
    expect_identical(missing_tag(actual$x), c(NA_character_, "q", NA))
})

test_that("haven labelled doubles round-trip with their labels", {
    data <- tibble::tibble(status = labelled_for_test(
        c(1, 2, tagged_missing("r")),
        labels = c(Complete = 1, Refused = 2),
        label = "interview status"
    ))
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(val_labels(actual$status), val_labels(data$status))
    expect_identical(var_label(actual$status), "interview status")
    expect_identical(missing_tag(actual$status), missing_tag(data$status))
    expect_s3_class(actual$status, "haven_labelled")
})

test_that("value labels on profiled columns round-trip", {
    column <- stata_long(c(1, 2, NA))
    attr(column, "labels") <- c(yes = 1, no = 2)
    data <- tibble::tibble(vote = column)
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(val_labels(actual$vote), c(yes = 1, no = 2))
    expect_identical(stata_storage_type(actual$vote), "long")
})

test_that("display formats round-trip on profiled columns", {
    column <- stata_double(c(1.5, 2.5))
    attr(column, "format.stata") <- "%9.2f"
    data <- tibble::tibble(amount = column)
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(attr(actual$amount, "format.stata", exact = TRUE),
                     "%9.2f")
})

test_that("column projection, skip, and n_max select the requested window", {
    data <- tibble::tibble(
        a = seq_len(10L), b = letters[1:10], c = as.double(101:110)
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path, col_select = c(c, a), skip = 3, n_max = 4)
    expect_identical(names(actual), c("c", "a"))
    expect_identical(actual$a, 4:7)
    expect_identical(actual$c, as.double(104:107))

    renamed <- read_arrow(path, col_select = c(z = b))
    expect_identical(names(renamed), "z")
    expect_identical(renamed$z, letters[1:10])

    predicate <- read_arrow(path, col_select = tidyselect::where(is.character))
    expect_identical(names(predicate), "b")

    empty <- read_arrow(path, skip = 100)
    expect_identical(nrow(empty), 0L)
    expect_identical(names(empty), c("a", "b", "c"))
})

test_that("corrupted buffers fail checksum verification by default", {
    marker <- 74088.140625
    data <- tibble::tibble(nm = c(1017.75, marker, 9.5))
    path <- arrow_tempfile()
    save_arrow(data, path)

    bytes <- readBin(path, "raw", n = file.info(path)$size)
    pattern <- writeBin(marker, raw(), endian = "little")
    matches <- grepRaw(pattern, bytes, fixed = TRUE, all = TRUE)
    expect_identical(length(matches), 1L)
    bytes[[matches[[1L]]]] <- xor(bytes[[matches[[1L]]]], as.raw(0x01))
    writeBin(bytes, path)

    expect_error(
        read_arrow(path),
        "checksum mismatch in column `nm`, record batch 0",
        fixed = TRUE
    )
    corrupt <- read_arrow(path, verify = FALSE)
    expect_false(identical(corrupt$nm[[2L]], marker))
})

test_that("newer profile versions are a hard error with an escape hatch", {
    data <- tibble::tibble(sv = stata_byte(c(3, 7)))
    path <- arrow_tempfile()
    save_arrow(data, path)

    bytes <- readBin(path, "raw", n = file.info(path)$size)
    # The frozen version is the only length-one flatbuffer string "0" in the
    # file: int32 length 1, "0", NUL. Rewrite every copy to "1".
    pattern <- as.raw(c(0x01, 0x00, 0x00, 0x00, 0x30, 0x00))
    matches <- grepRaw(pattern, bytes, fixed = TRUE, all = TRUE)
    expect_gte(length(matches), 1L)
    bytes[matches + 4L] <- as.raw(0x31)
    writeBin(bytes, path)

    expect_error(
        read_arrow(path),
        "dtatools Arrow profile version \"1\"",
        fixed = TRUE
    )
    plain <- read_arrow(path, profile = FALSE)
    expect_null(attr(plain$sv, "stata.storage", exact = TRUE))
})

test_that("profile = FALSE reads raw storage arrays without Stata semantics", {
    data <- tibble::tibble(sv = stata_byte(c(3, NA, tagged_missing("a"))))
    path <- arrow_tempfile()
    save_arrow(data, path)

    plain <- read_arrow(path, profile = FALSE)
    expect_null(attr(plain$sv, "stata.storage", exact = TRUE))
    expect_null(attr(plain$sv, "class", exact = TRUE))
    # Raw Stata missing storage: byte sentinels 101 (.) and 102 (.a).
    expect_identical(as.integer(plain$sv), c(3L, 101L, 102L))
})

test_that("unsupported columns are an error naming the column", {
    data <- tibble::tibble(x = c(1, 2))
    data$broken <- complex(real = 1:2, imaginary = 0)
    path <- arrow_tempfile()

    expect_error(
        save_arrow(data, path),
        "Unsupported columns: `broken` (complex)",
        fixed = TRUE,
        class = "dtatools_write_validation_error"
    )
    expect_false(file.exists(path))
})

test_that("write validation failures leave existing destinations unchanged", {
    path <- arrow_tempfile()
    sentinel <- charToRaw("existing destination")
    writeBin(sentinel, path)

    expect_error(
        save_arrow(tibble::tibble(`if` = 1), path),
        class = "dtatools_write_validation_error"
    )
    expect_identical(readBin(path, "raw", n = file.info(path)$size), sentinel)
})

test_that("extensionless output paths gain .arrow with a warning", {
    stem <- tempfile()
    path <- paste0(stem, ".arrow")
    on.exit(unlink(path), add = TRUE)

    expect_warning(
        save_arrow(tibble::tibble(x = 1), stem),
        sprintf("`path` has no extension; writing `%s`", path),
        fixed = TRUE,
        class = "dtatools_write_extension_warning"
    )
    expect_true(file.exists(path))
    expect_identical(read_arrow(path)$x, 1)
})

test_that("non-Arrow input is rejected by name", {
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    writeBin(charToRaw("not an arrow file at all"), path)

    expect_error(read_arrow(path), "is not an Arrow IPC file")
})

test_that("unrepresentable values in declared storage warn and count", {
    column <- c(1, 5e6)
    attr(column, "stata.storage") <- "int"
    class(column) <- dtatools:::.stata_storage_class("int")
    data <- tibble::tibble(narrow = column)
    path <- arrow_tempfile()

    expect_warning(
        save_arrow(data, path),
        "Converted unrepresentable numeric values to Stata system missing in `narrow` (1)",
        fixed = TRUE,
        class = "dtatools_write_numeric_replacement_warning"
    )
    actual <- read_arrow(path)
    expect_identical(as.double(actual$narrow), c(1, NA))
    expect_identical(missing_tag(actual$narrow), c(NA_character_, NA))
})

test_that("dta_merge accepts .arrow paths in either position", {
    master <- tibble::tibble(
        id = stata_byte(c(1, NA_real_, tagged_missing("a"))),
        score = c(10, 20, 30)
    )
    using <- tibble::tibble(
        id = stata_byte(c(tagged_missing("a"), 7)),
        grp = c("x", "y")
    )
    master_dta <- tempfile(fileext = ".dta")
    using_dta <- tempfile(fileext = ".dta")
    master_arrow <- tempfile(fileext = ".arrow")
    using_arrow <- tempfile(fileext = ".arrow")
    on.exit(unlink(c(master_dta, using_dta, master_arrow, using_arrow)),
            add = TRUE)
    save_dta(master, master_dta)
    save_dta(using, using_dta)
    save_arrow(master, master_arrow)
    save_arrow(using, using_arrow)

    reference <- dta_merge(master, using, by = "id", relationship = "1:1")
    combinations <- list(
        list(x = master_arrow, y = using_arrow),
        list(x = master_arrow, y = using_dta),
        list(x = master_dta, y = using_arrow),
        list(x = master, y = using_arrow)
    )
    for (inputs in combinations) {
        merged <- dta_merge(
            inputs$x, inputs$y, by = "id", relationship = "1:1"
        )
        expect_identical(
            data_values(merged), data_values(reference),
            info = paste(class(inputs$x)[[1L]], class(inputs$y)[[1L]])
        )
        expect_identical(names(merged), names(reference))
        expect_identical(
            missing_tag(merged$id), missing_tag(reference$id)
        )
    }
})

test_that("the arrow package is an independent oracle for written files", {
    skip_if_not_installed("arrow")
    data <- tibble::tibble(
        lgl = c(TRUE, NA, FALSE),
        num = c(1.5, NA, -2),
        s = c("a", NA, "c"),
        sv = stata_byte(c(3, NA, tagged_missing("a")))
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    oracle <- arrow::read_ipc_file(path)
    expect_identical(oracle$lgl, data$lgl)
    expect_identical(oracle$num, data$num)
    expect_identical(oracle$s, data$s)
    # Raw Stata missing storage is visible to plain Arrow readers as the
    # profile's sentinel integers.
    expect_identical(as.integer(oracle$sv), c(3L, 101L, 102L))
})

test_that("plain Arrow files never acquire Stata semantics", {
    skip_if_not_installed("arrow")
    data <- tibble::tibble(n = c(1L, NA, 3L), s = c("a", "b", NA))
    path <- arrow_tempfile()
    arrow::write_ipc_file(data, path, compression = "uncompressed")

    actual <- read_arrow(path)
    expect_identical(actual$n, data$n)
    expect_identical(actual$s, data$s)
    expect_null(attr(actual$n, "stata.storage", exact = TRUE))
    expect_null(attr(actual, "label", exact = TRUE))
})
