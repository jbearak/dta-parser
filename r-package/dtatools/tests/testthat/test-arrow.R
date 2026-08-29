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

test_that("Arrow field names are not restricted to Stata syntax", {
    long_name <- paste(rep("long", 12L), collapse = "_")
    data <- tibble::new_tibble(setNames(
        list(1:2, c("x", "y"), c(3.5, 4.5)),
        c("a b", "if", long_name)
    ), nrow = 2L)
    path <- arrow_tempfile()

    save_arrow(data, path)
    expect_identical(read_arrow(path), data)
    expect_identical(datasig(path), datasig(data))
})

test_that("empty data and default POSIXct timezones round-trip", {
    empty <- tibble::tibble(
        n = integer(),
        x = double(),
        f = factor(character(), levels = c("used later", "also unused"))
    )
    empty_path <- arrow_tempfile()
    save_arrow(empty, empty_path)
    expect_identical(read_arrow(empty_path), empty)
    expect_identical(datasig(empty_path), datasig(empty))

    local_time <- structure(
        1577880000,
        class = c("POSIXct", "POSIXt"),
        tzone = ""
    )
    local <- tibble::tibble(when = local_time)
    local_path <- arrow_tempfile()
    save_arrow(local, local_path)
    expect_identical(read_arrow(local_path), local)
    expect_identical(datasig(local_path), datasig(local))
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

test_that("multithreaded Arrow writes match single-threaded writes", {
    data <- standard_arrow_fixture()
    serial_path <- arrow_tempfile()
    parallel_path <- arrow_tempfile()
    save_arrow(data, serial_path, threads = 1L)
    save_arrow(data, parallel_path, threads = 4L)

    expect_identical(
        readBin(serial_path, "raw", file.size(serial_path)),
        readBin(parallel_path, "raw", file.size(parallel_path))
    )
    expect_identical(read_arrow(parallel_path), data)
})

test_that("native Arrow write cancellation remains an interrupt", {
    skip_on_os("windows")

    data <- data.frame(x = runif(1e7))
    path <- arrow_tempfile()
    parent <- Sys.getpid()
    signal <- parallel::mcparallel({
        Sys.sleep(0.05)
        tools::pskill(parent, tools::SIGINT)
    }, silent = TRUE)
    condition <- tryCatch(
        {
            save_arrow(data, path, compression = "zstd", threads = 1L)
            parallel::mccollect(signal)
            NULL
        },
        condition = identity
    )
    tryCatch(
        suppressWarnings(parallel::mccollect(signal)),
        condition = function(...) NULL
    )

    expect_s3_class(condition, "interrupt")
    expect_false(file.exists(path))
})

test_that("checksum-free writes round trip without verification", {
    data <- standard_arrow_fixture()
    checked_path <- arrow_tempfile()
    unchecked_path <- arrow_tempfile()
    save_arrow(data, checked_path)
    save_arrow(data, unchecked_path, checksums = FALSE)

    expect_lt(file.size(unchecked_path), file.size(checked_path))
    expect_error(read_arrow(unchecked_path), "verification off")
    expect_identical(read_arrow(unchecked_path, verify = FALSE), data)
    expect_error(save_arrow(data, unchecked_path, checksums = NA),
                 "one non-missing logical")
})

test_that("save_arrow validates threads", {
    data <- tibble::tibble(x = 1)
    path <- arrow_tempfile()

    expect_error(save_arrow(data, path, threads = -1),
                 "non-negative whole number")
    expect_error(save_arrow(data, path, threads = 1.5),
                 "non-negative whole number")
    expect_error(save_arrow(data, path, threads = NA_integer_),
                 "non-negative whole number")
    save_arrow(data, path, threads = 2L)
    expect_identical(read_arrow(path), data)
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

test_that("deferred string columns are written without materializing", {
    dta <- tempfile(fileext = ".dta")
    deferred_path <- arrow_tempfile()
    eager_path <- arrow_tempfile()
    on.exit(unlink(dta), add = TRUE)
    save_dta(tibble::tibble(s = c("alpha", "beta", "alpha", "", "éè")), dta)

    imported <- read_dta(dta)
    expect_true(dtatools:::.is_unmaterialized_dictstring(imported$s))
    save_arrow(imported, deferred_path)
    expect_true(dtatools:::.is_unmaterialized_dictstring(imported$s))

    materialized <- imported
    eager_column <- c(as.character(imported$s))
    attributes(eager_column) <- attributes(imported$s)
    materialized$s <- eager_column
    expect_false(dtatools:::.is_unmaterialized_dictstring(materialized$s))
    save_arrow(materialized, eager_path)

    # The native dictionary export and the eager path produce identical files.
    expect_identical(
        readBin(deferred_path, "raw", file.size(deferred_path)),
        readBin(eager_path, "raw", file.size(eager_path))
    )
    expect_identical(as.character(read_arrow(deferred_path)$s),
                     as.character(materialized$s))
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

test_that("compact datetime timezone adjustment matches eager writing", {
    raw <- c(1, 999, 1001)
    observed <- raw / 1000 - 315619200
    datetimes <- dtatools:::.construct_stata_numeric(
        observed, NULL, "long", temporal = 2L
    )
    prototype <- structure(
        double(),
        format.stata = "%tc",
        tzone = "UTC",
        class = c("stata_temporal", "stata_datetime", "POSIXct", "POSIXt")
    )
    datetimes <- dtatools:::.attach_stata_temporal(
        datetimes, prototype, "long"
    )
    source <- structure(
        list(dt = datetimes),
        class = "data.frame",
        row.names = .set_row_names(length(datetimes))
    )
    dta_path <- tempfile(fileext = ".dta")
    compact_path <- arrow_tempfile()
    eager_path <- arrow_tempfile()
    on.exit(unlink(dta_path), add = TRUE)
    save_dta(source, dta_path)

    compact <- read_dta(dta_path)
    attr(compact$dt, "tzone") <- "America/New_York"
    expect_true(dtatools:::.is_unmaterialized_numeric_altrep(compact$dt))
    eager <- compact
    eager$dt <- dtatools:::.force_altrep_materialization(eager$dt)

    expect_warning(
        save_arrow(compact, compact_path, adjust_tz = TRUE),
        class = "dtatools_write_attribute_drop_warning"
    )
    expect_warning(
        save_arrow(eager, eager_path, adjust_tz = TRUE),
        class = "dtatools_write_attribute_drop_warning"
    )
    expect_identical(
        readBin(compact_path, "raw", file.size(compact_path)),
        readBin(eager_path, "raw", file.size(eager_path))
    )
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

test_that("legacy integer tails and value-label codes survive Arrow", {
    dta_path <- fixture("synthetic_v111.dta")
    data <- read_dta(dta_path)
    path <- arrow_tempfile()
    save_arrow(data, path)

    for (use_numeric_altrep in c(TRUE, FALSE)) {
        actual <- read_arrow(path, use_numeric_altrep = use_numeric_altrep)
        for (name in c("b", "i", "l")) {
            expect_identical(
                as.double(actual[[name]]), as.double(data[[name]]),
                info = paste(name, use_numeric_altrep)
            )
            expect_identical(
                missing_tag(actual[[name]]), missing_tag(data[[name]]),
                info = paste(name, use_numeric_altrep)
            )
            expect_identical(
                attr(actual[[name]], "labels", exact = TRUE),
                attr(data[[name]], "labels", exact = TRUE),
                info = paste(name, use_numeric_altrep)
            )
        }
        expect_identical(datasig(actual), datasig(data))
    }

    signature <- datasig(data)
    expect_identical(datasig(dta_path), signature)
    expect_identical(datasig(path), signature)
    expect_identical(
        attr(read_dta(dta_path, datasig = TRUE), "datasig", exact = TRUE),
        signature
    )
    expect_identical(
        attr(
            read_dta(
                dta_path, datasig = TRUE, use_numeric_altrep = FALSE
            ),
            "datasig", exact = TRUE
        ),
        signature
    )

    eager <- read_arrow(path, use_numeric_altrep = FALSE)
    eager_path <- arrow_tempfile()
    save_arrow(eager, eager_path)
    expect_identical(datasig(eager_path), signature)
})

test_that("tagged NaN payloads on bare doubles survive bit-exactly", {
    values <- c(1.5, NaN, tagged_nan_for_test("q"), NA_real_)
    data <- tibble::tibble(x = values)
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(writeBin(actual$x, raw()), writeBin(values, raw()))
    expect_identical(
        missing_tag(actual$x), c(NA_character_, NA_character_, "q", NA)
    )
})

test_that("byte-encoded strings are rejected instead of replaced", {
    values <- lapply(c(0xff, 0xfe), function(byte) {
        value <- rawToChar(as.raw(byte))
        Encoding(value) <- "bytes"
        value
    })

    for (value in values) {
        data <- tibble::tibble(x = value)
        path <- arrow_tempfile()
        expect_error(
            save_arrow(data, path),
            "Character column `x` cannot contain strings with `bytes` encoding",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
        expect_false(file.exists(path))
        expect_error(
            datasig(data),
            "Character column `x` cannot contain strings with `bytes` encoding",
            fixed = TRUE,
            class = "dtatools_write_validation_error"
        )
    }
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

test_that("label-free haven labelled doubles retain their class", {
    data <- tibble::tibble(status = labelled_for_test(c(1, 2)))
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(actual$status, data$status)
    expect_null(attr(actual$status, "labels", exact = TRUE))
    expect_s3_class(actual$status, "haven_labelled")
    expect_identical(datasig(actual), datasig(data))
})

test_that("temporal classes and empty value-label tables round-trip", {
    skip_if_not_installed("arrow")
    day <- as.Date(c("2020-01-01", NA))
    attr(day, "labels") <- c(new_year = as.double(day[[1L]]))
    timestamp <- as.POSIXct(c("2020-01-01 12:00:00", NA), tz = "UTC")
    attr(timestamp, "labels") <- c(noon = as.double(timestamp[[1L]]))
    elapsed <- as.difftime(c(1, NA), units = "hours")
    attr(elapsed, "labels") <- c(one_hour = 1)
    empty_labels <- setNames(double(), character())
    labelled <- labelled_for_test(c(1, 2), labels = empty_labels)
    stata <- stata_long(c(1, 2))
    attr(stata, "labels") <- empty_labels
    data <- tibble::tibble(
        day = day,
        timestamp = timestamp,
        elapsed = elapsed,
        labelled = labelled,
        stata = stata
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    oracle <- arrow::read_ipc_file(path)
    expect_s3_class(actual$day, "Date")
    expect_s3_class(actual$timestamp, "POSIXct")
    expect_s3_class(actual$elapsed, "difftime")
    expect_s3_class(oracle$day, "Date")
    expect_s3_class(oracle$timestamp, "POSIXct")
    expect_s3_class(oracle$elapsed, "difftime")
    for (name in names(data)) {
        expect_identical(
            attr(actual[[name]], "labels", exact = TRUE),
            attr(data[[name]], "labels", exact = TRUE),
            info = name
        )
    }
    expect_s3_class(actual$labelled, "haven_labelled")
    expect_s3_class(actual$stata, "haven_labelled")
    expect_identical(datasig(actual), datasig(data))
})

test_that("profiled storage uses its materialized R type for selection", {
    data <- tibble::tibble(
        b = stata_byte(1), i = stata_int(1), l = stata_long(1),
        f = stata_float(1), d = stata_double(1),
        ordinary_integer = 1L, ordinary_double = 1
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    expect_identical(
        names(read_arrow(path, col_select = tidyselect::where(is.integer))),
        "ordinary_integer"
    )
    expect_identical(
        names(read_arrow(path, col_select = tidyselect::where(is.double))),
        c("b", "i", "l", "f", "d", "ordinary_double")
    )
})

test_that("declared Stata storage overrides mismatched compact backing", {
    value <- stata_byte(c(1, 2, NA))
    attr(value, "stata.storage") <- "int"
    class(value) <- dtatools:::.stata_storage_class("int")
    data <- tibble::tibble(x = value)
    path <- arrow_tempfile()
    save_arrow(data, path)

    actual <- read_arrow(path)
    expect_identical(stata_storage_type(actual$x), "int")
    expect_identical(as.double(actual$x), as.double(data$x))
    expect_identical(datasig(actual), datasig(data))
})

test_that("invalid NaNs in Stata storage become system missing", {
    values <- c(1, NaN, tagged_nan_for_test("?"))
    attr(values, "stata.storage") <- "double"
    class(values) <- dtatools:::.stata_storage_class("double")
    data <- tibble::tibble(x = values)
    path <- arrow_tempfile()

    expect_warning(
        save_arrow(data, path),
        "Converted unrepresentable numeric values to Stata system missing in `x` (2)",
        fixed = TRUE,
        class = "dtatools_write_numeric_replacement_warning"
    )
    expect_identical(
        missing_tag(read_arrow(path)$x), rep(NA_character_, 3L)
    )
    expect_error(
        datasig(data),
        "cannot compute datasig after lossy numeric replacements in `x` (2)",
        fixed = TRUE
    )
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

test_that("integer-coded value labels work in Arrow and datasig", {
    labelled <- set_value_labels(c(1, 2), .labels = c(one = 1L, two = 2L))
    expect_type(val_labels(labelled), "integer")
    data <- tibble::tibble(x = labelled)
    path <- arrow_tempfile()

    save_arrow(data, path)
    actual <- read_arrow(path)
    expect_identical(val_labels(actual$x), c(one = 1, two = 2))
    expect_identical(datasig(actual), datasig(data))
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

test_that("zero-row selections preserve factor levels", {
    data <- tibble::tibble(
        f = factor(c("a", "b"), levels = c("a", "b", "unused"), ordered = TRUE)
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    for (empty in list(
        read_arrow(path, n_max = 0),
        read_arrow(path, skip = 100)
    )) {
        expect_identical(empty$f, data$f[integer()])
        expect_identical(levels(empty$f), levels(data$f))
        expect_true(is.ordered(empty$f))
    }
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
    selected <- read_arrow(path, col_select = sv, profile = FALSE)
    expect_identical(selected, plain)
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

    invalid <- data.frame(x = 1, y = 2)
    names(invalid) <- c("x", "x")
    expect_error(save_arrow(invalid, path),
                 class = "dtatools_write_validation_error")
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

test_that("save_arrow reports attributes the profile drops", {
    data <- tibble::tibble(x = c(1, 2))
    attr(data, "provenance") <- "raw/source.csv"
    attr(data$x, "units.custom") <- "widgets"
    path <- arrow_tempfile()

    expect_warning(
        save_arrow(data, path),
        paste0(
            "Dropped attributes the Arrow profile does not represent: ",
            "the data frame (provenance); `x` (units.custom)"
        ),
        fixed = TRUE,
        class = "dtatools_write_attribute_drop_warning"
    )
    actual <- read_arrow(path)
    expect_null(attr(actual, "provenance", exact = TRUE))
    expect_null(attr(actual$x, "units.custom", exact = TRUE))
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
        num = c(1.5, NaN, -2),
        s = c("a", NA, "c"),
        sv = stata_byte(c(3, NA, tagged_missing("a"))),
        elapsed = as.difftime(c(1.5, NA, -2), units = "hours")
    )
    path <- arrow_tempfile()
    save_arrow(data, path)

    oracle <- arrow::read_ipc_file(path)
    expect_identical(oracle$lgl, data$lgl)
    expect_identical(oracle$num, data$num)
    expect_identical(oracle$s, data$s)
    expect_identical(
        as.numeric(oracle$elapsed, units = "secs"),
        c(5.4e3, NA, -7.2e3)
    )
    # Raw Stata missing storage is visible to plain Arrow readers as the
    # profile's sentinel integers.
    expect_identical(as.integer(oracle$sv), c(3L, 101L, 102L))
})

test_that("plain Arrow files never acquire Stata semantics", {
    skip_if_not_installed("arrow")
    data <- tibble::tibble(
        n = c(1L, NA, 3L),
        s = c("a", "b", NA),
        f = factor(c("low", "high", NA), levels = c("low", "high"))
    )
    path <- arrow_tempfile()
    arrow::write_ipc_file(data, path, compression = "uncompressed")

    actual <- read_arrow(path)
    expect_identical(actual$n, data$n)
    expect_identical(actual$s, data$s)
    expect_identical(actual$f, data$f)
    expect_null(attr(actual$n, "stata.storage", exact = TRUE))
    expect_null(attr(actual, "label", exact = TRUE))
})

test_that("plain Arrow ordered dictionaries remain ordered factors", {
    skip_if_not_installed("arrow")
    data <- tibble::tibble(
        rating = ordered(
            c("low", "high", NA),
            levels = c("low", "high", "unused")
        )
    )
    path <- arrow_tempfile()
    arrow::write_ipc_file(data, path, compression = "uncompressed")

    actual <- read_arrow(path)
    expect_identical(actual$rating, data$rating)
    expect_s3_class(actual$rating, "ordered")
})

test_that("plain Int32 selection predicates match the returned R type", {
    skip_if_not_installed("arrow")
    path <- arrow_tempfile()
    values <- arrow::Array$create(c(-2147483648, 7), type = arrow::int32())
    arrow::write_ipc_file(arrow::arrow_table(x = values), path)

    expect_type(read_arrow(path)$x, "double")
    expect_identical(
        names(read_arrow(path, col_select = tidyselect::where(is.double))),
        "x"
    )
    expect_identical(
        names(read_arrow(path, col_select = tidyselect::where(is.integer))),
        character()
    )
})

test_that("wide Arrow integers are rejected instead of rounded", {
    skip_if_not_installed("arrow")
    skip_if_not_installed("bit64")
    boundary <- bit64::as.integer64("9007199254740992")
    too_wide <- bit64::as.integer64("9007199254740993")

    for (type in list(arrow::int64(), arrow::uint64())) {
        boundary_path <- arrow_tempfile()
        arrow::write_ipc_file(
            arrow::arrow_table(
                x = arrow::Array$create(boundary, type = type)
            ),
            boundary_path
        )
        expect_identical(read_arrow(boundary_path)$x, 2^53)

        wide_path <- arrow_tempfile()
        arrow::write_ipc_file(
            arrow::arrow_table(
                x = arrow::Array$create(too_wide, type = type)
            ),
            wide_path
        )
        expect_error(
            read_arrow(wide_path),
            "cannot be represented exactly as an R double",
            fixed = TRUE
        )
        expect_error(
            datasig(wide_path),
            "cannot be represented exactly as an R double",
            fixed = TRUE
        )
    }
})

test_that("wide Arrow temporal counts are rejected instead of rounded", {
    skip_if_not_installed("arrow")
    skip_if_not_installed("bit64")
    count <- bit64::as.integer64("1700000000000000001")

    for (type in list(arrow::timestamp("ns"), arrow::duration("ns"))) {
        path <- arrow_tempfile()
        values <- arrow::Array$create(count, type = arrow::int64())$cast(type)
        arrow::write_ipc_file(arrow::arrow_table(x = values), path)
        expect_error(
            read_arrow(path),
            "cannot be represented exactly in R",
            fixed = TRUE
        )
        expect_error(
            datasig(path),
            "cannot be represented exactly in R",
            fixed = TRUE
        )
    }
})
