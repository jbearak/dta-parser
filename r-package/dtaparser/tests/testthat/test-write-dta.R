test_that("write_dta writes a typed release-118 dataset and returns its input invisibly", {
    data <- data.frame(
        answer = stata_byte(c(-5, tagged_missing("a"))),
        stringsAsFactors = FALSE
    )
    attr(data, "label") <- "writer tracer bullet"
    var_label(data$answer) <- "the answer"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_identical(expect_invisible(write_dta(data, path)), data)
    expect_true(file.exists(path))

    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(attr(actual, "label", exact = TRUE), "writer tracer bullet")
    expect_identical(var_label(actual$answer), "the answer")
    expect_identical(stata_storage_type(actual$answer), "byte")
    expect_identical(missing_tag(actual$answer), c(NA_character_, "a"))
    expect_identical(as.double(actual$answer[[1L]]), -5)
})

test_that("Stata 18 rejects release-119-width datasets", {
    data <- setNames(
        as.data.frame(
            rep(list(1L), 32768L),
            optional = TRUE
        ),
        paste0("x", seq_len(32768L))
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_error(
        write_dta(data, path, version = 18L),
        "Stata 18's 32,767-variable limit",
        class = "dtaparser_write_validation_error",
        fixed = TRUE
    )
    expect_false(file.exists(path))
})

test_that("bare logical columns write as Stata bytes", {
    data <- data.frame(flag = c(TRUE, FALSE, NA))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(stata_storage_type(actual$flag), "byte")
    expect_identical(as.double(actual$flag), c(1, 0, NA_real_))
})

test_that("compact reader storage and materialized fallbacks write identically", {
    source_path <- tempfile(fileext = ".dta")
    direct_path <- tempfile(fileext = ".dta")
    materialized_path <- tempfile(fileext = ".dta")
    numeric_path <- tempfile(fileext = ".dta")
    string_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(
        source_path, direct_path, materialized_path, numeric_path, string_path
    )), add = TRUE)

    source <- data.frame(
        narrow = stata_byte(c(-5, 100, tagged_missing("b"))),
        text = c("alpha", "beta", "alpha")
    )
    expect_silent(write_dta(source, source_path))
    compact <- read_dta(source_path)
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(compact$narrow))

    expect_silent(write_dta(compact, direct_path))
    materialized <- compact
    materialized[] <- lapply(
        materialized, dtaparser:::.force_altrep_materialization
    )
    expect_false(
        dtaparser:::.is_unmaterialized_numeric_altrep(materialized$narrow)
    )
    expect_silent(write_dta(materialized, materialized_path))
    expect_identical(
        readBin(direct_path, "raw", n = file.info(direct_path)$size),
        readBin(
            materialized_path, "raw", n = file.info(materialized_path)$size
        )
    )

    changed_numeric <- compact["narrow"]
    changed_numeric$narrow[[2L]] <- 99
    expect_silent(write_dta(changed_numeric, numeric_path))
    expect_identical(
        as.double(read_dta(numeric_path, use_numeric_altrep = FALSE)$narrow),
        c(-5, 99, tagged_missing("b"))
    )

    changed_string <- compact["text"]
    changed_string$text[[2L]] <- NA_character_
    expect_warning(
        write_dta(changed_string, string_path),
        class = "dtaparser_write_character_missing_warning"
    )
    expect_identical(
        as.character(read_dta(string_path)$text), c("alpha", "", "alpha")
    )
})

test_that("compact datetimes preserve millisecond integer storage", {
    raw <- c(1, 999, 1001)
    observed <- raw / 1000 - 315619200
    datetimes <- dtaparser:::.construct_stata_numeric(
        observed, NULL, "int", temporal = 2L
    )
    prototype <- structure(
        double(),
        format.stata = "%tc",
        tzone = "UTC",
        class = c("stata_temporal", "stata_datetime", "POSIXct", "POSIXt")
    )
    datetimes <- dtaparser:::.attach_stata_temporal(
        datetimes, prototype, "int"
    )
    compact <- structure(
        list(dt = datetimes),
        class = "data.frame",
        row.names = .set_row_names(length(datetimes))
    )
    direct_path <- tempfile(fileext = ".dta")
    materialized_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(direct_path, materialized_path)), add = TRUE)

    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(compact$dt))
    expect_silent(write_dta(compact, direct_path))
    materialized <- compact
    materialized$dt <- dtaparser:::.force_altrep_materialization(
        materialized$dt
    )
    expect_false(
        dtaparser:::.is_unmaterialized_numeric_altrep(materialized$dt)
    )
    expect_silent(write_dta(materialized, materialized_path))

    direct <- read_dta(direct_path, use_numeric_altrep = FALSE)$dt
    fallback <- read_dta(materialized_path, use_numeric_altrep = FALSE)$dt
    expect_identical(stata_storage_type(direct), "int")
    expect_identical(as.double(direct), observed)
    expect_identical(as.double(fallback), observed)
})

test_that("malformed compact numerics follow materialized write semantics", {
    source_path <- fixture_with_all_numeric_missing_codes(
        "missing_values_v118.dta"
    )
    direct_path <- tempfile(fileext = ".dta")
    materialized_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(
        source_path, direct_path, materialized_path
    )), add = TRUE)

    patch_numeric_fixture_row(
        source_path,
        0L,
        list(
            x_byte = as.raw(0x80),
            x_int = .raw_little_integer(-32768L, 2L),
            x_long = .raw_little_integer(NA_integer_, 4L),
            x_float = .raw_little_integer(as.integer(0x7fc00001), 4L)
        )
    )

    direct <- read_dta(
        source_path,
        col_select = c("x_byte", "x_int", "x_long", "x_float"),
        n_max = 1L
    )
    expect_true(all(vapply(
        direct,
        dtaparser:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))
    materialized <- direct
    materialized[] <- lapply(
        materialized,
        dtaparser:::.force_altrep_materialization
    )
    expect_false(any(vapply(
        materialized,
        dtaparser:::.is_unmaterialized_numeric_altrep,
        logical(1)
    )))

    direct_warning <- expect_warning(
        write_dta(direct, direct_path),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    materialized_warning <- expect_warning(
        write_dta(materialized, materialized_path),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    expect_identical(
        conditionMessage(direct_warning),
        conditionMessage(materialized_warning)
    )

    direct_result <- read_dta(
        direct_path,
        use_numeric_altrep = FALSE
    )
    materialized_result <- read_dta(
        materialized_path,
        use_numeric_altrep = FALSE
    )
    expect_true(all(vapply(
        direct_result,
        function(column) is.na(as.double(column[[1L]])),
        logical(1)
    )))
    expect_identical(
        data_values(direct_result),
        data_values(materialized_result)
    )
    expect_identical(
        lapply(direct_result, missing_tag),
        lapply(materialized_result, missing_tag)
    )
})

test_that("legacy compact numerics are revalidated for modern missing ranges", {
    legacy_path <- fixture("synthetic_v111.dta")
    legacy <- read_dta(legacy_path, col_select = "i")
    expect_true(dtaparser:::.is_unmaterialized_numeric_altrep(legacy$i))
    output <- tempfile(fileext = ".dta")
    on.exit(unlink(output), add = TRUE)
    expect_warning(
        write_dta(legacy, output),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    expect_identical(
        as.double(read_dta(output, use_numeric_altrep = FALSE)$i),
        c(321, NA, NA, NA)
    )
})

test_that("character missing values become empty strings and long values use strL", {
    latin <- iconv("café", from = "UTF-8", to = "latin1")
    data <- data.frame(
        short = c("é", NA_character_, ""),
        long_text = c(strrep("x", 20L), strrep("x", 20L), "different"),
        latin = c(latin, NA_character_, latin),
        stringsAsFactors = FALSE
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_warning(
        write_dta(data, path, strl_threshold = 4L),
        class = "dtaparser_write_character_missing_warning"
    )
    actual <- read_dta(path)
    expect_identical(unname(vapply(actual$short, identity, character(1))), c("é", "", ""))
    expect_identical(
        unname(vapply(actual$long_text, identity, character(1))),
        data$long_text
    )
    expect_identical(
        unname(vapply(actual$latin, identity, character(1))),
        c("café", "", "café")
    )

    specification <- dtaparser:::.prepare_dta_write(
        data, NULL, 4L, TRUE
    )
    expect_identical(specification[[3L]][[1L]][[7L]], data$short)
})

test_that("ordered and unordered factors become labelled long integers", {
    data <- data.frame(
        group = factor(c("b", "a", NA), levels = c("a", "b", "unused")),
        rank = ordered(c("low", "high", "low"), levels = c("low", "high"))
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_warning(
        write_dta(data, path),
        class = "dtaparser_write_factor_warning"
    )
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(stata_storage_type(actual$group), "long")
    expect_identical(as.double(actual$group), c(2, 1, NA_real_))
    expect_identical(val_labels(actual$group), c(a = 1, b = 2, unused = 3))
    expect_identical(as.double(actual$rank), c(1, 2, 1))
    expect_identical(val_labels(actual$rank), c(low = 1, high = 2))
    expect_false(is.factor(actual$group))
    expect_false(is.ordered(actual$rank))
})

test_that("R system-missing payload variants remain system missing", {
    payload_variant <- readBin(
        as.raw(c(0xa2, 0x07, 0x00, 0x00, 0x00, 0x01, 0xf0, 0x7f)),
        what = double(), n = 1L, size = 8L, endian = "little"
    )
    data <- data.frame(x = c(NA_real_ + 0, -NA_real_, payload_variant))
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_true(is.na(payload_variant))
    old_options <- options(warn = 2L)
    on.exit(options(old_options), add = TRUE)
    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_true(all(is.na(actual)))
    expect_true(all(is.na(missing_tag(actual))))
})

test_that("unrepresentable numerics become system missing in one aggregated warning", {
    narrow <- c(1, 1.5, 101, tagged_missing("b"), Inf, NaN)
    data <- data.frame(
        narrow = narrow,
        wide = c(1, .Machine$double.xmax, -Inf, NA_real_, tagged_missing("z"), 2)
    )
    attr(data$narrow, "stata.storage") <- "byte"
    narrow_plan <- dtaparser:::.prepare_dta_write_numeric(
        data$narrow, "narrow", "numeric", TRUE
    )
    wide_plan <- dtaparser:::.prepare_dta_write_numeric(
        data$wide, "wide", "numeric", TRUE
    )
    expect_identical(
        dtaparser:::.dta_write_numeric_replacement_mask(narrow_plan),
        c(FALSE, TRUE, TRUE, FALSE, TRUE, TRUE)
    )
    expect_identical(
        dtaparser:::.dta_write_numeric_replacement_mask(wide_plan),
        c(FALSE, TRUE, TRUE, FALSE, FALSE, FALSE)
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    warning <- expect_warning(
        write_dta(data, path),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    expect_match(conditionMessage(warning), "`narrow` (4)", fixed = TRUE)
    expect_match(conditionMessage(warning), "`wide` (2)", fixed = TRUE)
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(as.double(actual$narrow), c(1, NA, NA, tagged_missing("b"), NA, NA))
    expect_identical(as.double(actual$wide), c(1, NA, NA, NA, tagged_missing("z"), 2))
    expect_identical(missing_tag(actual$narrow), c(NA, NA, NA, "b", NA, NA))
    expect_identical(missing_tag(actual$wide), c(NA, NA, NA, NA, "z", NA))
})

test_that("Date and POSIXct columns use Stata epochs and both timezone modes", {
    dates <- as.Date(c("1960-01-01", "1970-01-01", NA))
    times <- as.POSIXct(
        c("2020-01-01 12:00:00", "2020-07-01 12:00:00", NA),
        tz = "America/New_York"
    )
    attr(dates, "format.stata") <- "%td"
    attr(times, "format.stata") <- "%tc"
    data <- data.frame(dates = dates, times = times)
    wall_path <- tempfile(fileext = ".dta")
    instant_path <- tempfile(fileext = ".dta")
    on.exit(unlink(c(wall_path, instant_path)), add = TRUE)

    expect_silent(write_dta(data, wall_path, adjust_tz = TRUE))
    expect_silent(write_dta(data, instant_path, adjust_tz = FALSE))
    wall <- read_dta(wall_path, use_numeric_altrep = FALSE)
    instant <- read_dta(instant_path, use_numeric_altrep = FALSE)

    expect_identical(as.double(wall$dates), as.double(dates))
    expect_identical(attr(wall$dates, "format.stata"), "%td")
    expect_equal(
        as.double(wall$times),
        as.double(as.POSIXct(
            c("2020-01-01 12:00:00", "2020-07-01 12:00:00", NA),
            tz = "UTC"
        )),
        tolerance = 1e-9
    )
    expect_equal(as.double(instant$times), as.double(times), tolerance = 1e-9)
    expect_identical(attr(wall$times, "tzone"), "UTC")

    specification <- dtaparser:::.prepare_dta_write(
        data, NULL, 2045L, TRUE
    )
    expect_identical(specification[[3L]][[1L]][[9L]], 3653)
    expect_identical(specification[[3L]][[1L]][[10L]], 1)
    expect_identical(specification[[3L]][[2L]][[9L]], 315619200)
    expect_identical(specification[[3L]][[2L]][[10L]], 1000)
})

test_that("timezone adjustment retains invalid datetimes for native warnings", {
    times <- structure(
        c(as.double(as.POSIXct("2020-01-01 12:00:00", tz = "UTC")), Inf, -Inf),
        class = c("POSIXct", "POSIXt"),
        tzone = "America/New_York",
        format.stata = "%tc"
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    warning <- expect_warning(
        write_dta(data.frame(times = times), path, adjust_tz = TRUE),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    expect_match(conditionMessage(warning), "`times` (2)", fixed = TRUE)
    actual <- read_dta(path, use_numeric_altrep = FALSE)$times
    expect_false(is.na(actual[[1L]]))
    expect_true(all(is.na(actual[2:3])))
})

test_that("timezone adjustment retains extreme finite datetimes for native warnings", {
    times <- structure(
        c(as.double(as.POSIXct("2020-01-01 12:00:00", tz = "UTC")), .Machine$double.xmax),
        class = c("POSIXct", "POSIXt"),
        tzone = "America/New_York",
        format.stata = "%tc"
    )
    plan <- dtaparser:::.prepare_dta_write_numeric(
        times, "times", "datetime", TRUE
    )
    expect_identical(plan$values[[2L]], .Machine$double.xmax)
    expect_false(is.na(plan$values[[2L]]))

    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    warning <- expect_warning(
        write_dta(data.frame(times = times), path, adjust_tz = TRUE),
        class = "dtaparser_write_numeric_replacement_warning"
    )
    expect_match(conditionMessage(warning), "`times` (1)", fixed = TRUE)
    actual <- read_dta(path, use_numeric_altrep = FALSE)$times
    expect_false(is.na(actual[[1L]]))
    expect_true(is.na(actual[[2L]]))
})

test_that("value labels and ordered dataset notes round-trip", {
    x <- stata_long(c(-1, 1, tagged_missing("c"), NA_real_))
    val_labels(x) <- c(
        missing_c = tagged_missing("c"), positive = 1, negative = -1
    )
    data <- data.frame(x = x)
    attr(data, "notes") <- c("first", "", "third")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(attr(actual, "notes", exact = TRUE), c("first", "", "third"))
    expect_identical(
        val_labels(actual$x),
        c(negative = -1, positive = 1, missing_c = tagged_missing("c"))
    )
})

test_that("empty value-label text from source metadata round-trips", {
    x <- stata_int(c(1201, 1213))
    attr(x, "labels") <- stats::setNames(c(1201, 1213), c("", ""))
    attr(x, "class") <- c(
        "stata_numeric", "stata_int", "haven_labelled", "vctrs_vctr", "double"
    )
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(attr(actual, "labels", exact = TRUE),
                     stats::setNames(c(1201, 1213), c("", "")))
    expect_s3_class(actual, "haven_labelled")
})

test_that("an attached empty value-label table round-trips", {
    x <- stata_double(c(1, 2))
    attr(x, "labels") <- stats::setNames(double(), character())
    attr(x, "class") <- c(
        "stata_numeric", "stata_double", "haven_labelled", "vctrs_vctr",
        "double"
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data.frame(x = x), path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(
        attr(actual, "labels", exact = TRUE),
        stats::setNames(double(), character())
    )
    expect_s3_class(actual, "haven_labelled")
})

test_that("duplicate value-label keys from source metadata round-trip stably", {
    x <- stata_byte(c(tagged_missing("a"), tagged_missing("b")))
    attr(x, "labels") <- c(
        `Don't know` = tagged_missing("b"),
        Refused = tagged_missing("a"),
        `Not ascertained` = tagged_missing("a")
    )
    attr(x, "class") <- c(
        "stata_numeric", "stata_byte", "haven_labelled", "vctrs_vctr", "double"
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data.frame(x = x), path))
    actual <- attr(read_dta(path)$x, "labels", exact = TRUE)
    expect_identical(names(actual), c("Refused", "Not ascertained", "Don't know"))
    expect_identical(unname(missing_tag(actual)), c("a", "a", "b"))
})

test_that("value-label text limits count UTF-8 bytes before touching the destination", {
    x <- stata_long(1)
    overlong_text <- iconv(
        strrep("é", 16001L),
        from = "UTF-8",
        to = "latin1"
    )
    attr(x, "labels") <- stats::setNames(1, overlong_text)
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    sentinel <- charToRaw("existing destination")
    writeBin(sentinel, path)
    on.exit(unlink(path), add = TRUE)

    expect_error(
        write_dta(data, path),
        class = "dtaparser_write_validation_error"
    )
    expect_identical(readBin(path, "raw", n = file.info(path)$size), sentinel)
})

test_that("warnings promoted to errors leave an existing destination unchanged", {
    data <- data.frame(x = factor("a"))
    path <- tempfile(fileext = ".dta")
    sentinel <- charToRaw("existing destination")
    writeBin(sentinel, path)
    on.exit(unlink(path), add = TRUE)
    previous <- options(warn = 2)
    on.exit(options(previous), add = TRUE)

    expect_error(write_dta(data, path), "factor columns", ignore.case = TRUE)
    expect_identical(readBin(path, "raw", n = file.info(path)$size), sentinel)
})

test_that("native temporary DTA files are private on Unix", {
    skip_on_os("windows")
    previous_umask <- Sys.umask("0277")
    on.exit(Sys.umask(previous_umask), add = TRUE)
    path <- tempfile(fileext = ".tmp")
    on.exit(unlink(path), add = TRUE)
    specification <- dtaparser:::.prepare_dta_write(
        data.frame(x = 1L), NULL, 2045L, TRUE, 19L
    )

    expect_silent(.Call(dtaparser:::C_dtaparser_write, specification, path))
    expect_identical(
        bitwAnd(as.integer(file.info(path)$mode), strtoi("077", base = 8L)),
        0L
    )
})

test_that("writes preserve existing Unix destination permissions", {
    skip_on_os("windows")
    path <- tempfile(fileext = ".dta")
    writeBin(charToRaw("existing destination"), path)
    Sys.chmod(path, mode = "0600")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data.frame(x = 1L), path))
    expect_identical(file.info(path)$mode, as.octmode("0600"))
})

test_that("new Unix destinations use normal creation permissions", {
    skip_on_os("windows")
    previous_umask <- Sys.umask("0027")
    on.exit(Sys.umask(previous_umask), add = TRUE)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data.frame(x = 1L), path))
    expect_identical(file.info(path)$mode, as.octmode("0640"))
})

test_that("existing FIFO destinations are rejected without replacement", {
    skip_on_os("windows")
    mkfifo <- Sys.which("mkfifo")
    file_test <- Sys.which("test")
    skip_if(!nzchar(mkfifo) || !nzchar(file_test))

    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    expect_equal(system2(mkfifo, shQuote(path)), 0L)
    expect_equal(system2(file_test, c("-p", shQuote(path))), 0L)

    expect_error(
        write_dta(data.frame(x = 1L), path),
        class = "dtaparser_write_path_error"
    )
    expect_equal(system2(file_test, c("-p", shQuote(path))), 0L)
})

test_that("extensionless output appends .dta with one classed warning", {
    data <- data.frame(x = 1L)
    base <- tempfile(pattern = "dtaparser-extensionless-write-")
    path <- paste0(base, ".dta")
    on.exit(unlink(c(base, path)), add = TRUE)

    expect_warning(
        write_dta(data, base),
        class = "dtaparser_write_extension_warning"
    )
    expect_false(file.exists(base))
    expect_true(file.exists(path))
    expect_identical(nrow(read_dta(base)), 1L)
})

test_that("unsupported columns are reported together with their classes", {
    data <- data.frame(ok = 1:2)
    data$list_col <- I(list(1, 2))
    data$duration <- as.difftime(c(1, 2), units = "hours")
    data$custom <- structure(c(1, 2), class = "mystery_measure")
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    error <- expect_error(
        write_dta(data, path),
        class = "dtaparser_write_validation_error"
    )
    message <- conditionMessage(error)
    expect_true(all(vapply(
        c("list_col", "AsIs", "duration", "difftime", "custom", "mystery_measure"),
        grepl, logical(1), x = message, fixed = TRUE
    )))
    expect_false(file.exists(path))
})

test_that("dependency-free haven_labelled-compatible vectors are supported", {
    x <- structure(
        c(1, 2, tagged_missing("a")),
        labels = c(One = 1, Two = 2),
        class = c("haven_labelled", "vctrs_vctr", "double")
    )
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(as.double(actual), c(1, 2, tagged_missing("a")))
    expect_identical(val_labels(actual), c(One = 1, Two = 2))
})

test_that("haven opens dtaparser output with matching values and metadata", {
    skip_if_not_installed("haven")
    x <- c(1, 2, tagged_missing("a"), NA_real_)
    attr(x, "labels") <- c(One = 1, Two = 2)
    data <- data.frame(x = x, text = c("é", "", "long text", "long text"))
    attr(data, "label") <- "haven compatibility"
    attr(data, "notes") <- c("first note", "second note")
    var_label(data$x) <- "coded value"
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path, strl_threshold = 4L))
    actual <- without_haven_note_count(haven::read_dta(path))
    expect_identical(attr(actual, "label", exact = TRUE), "haven compatibility")
    expect_identical(attr(actual, "notes", exact = TRUE), attr(data, "notes"))
    expect_identical(attr(actual$x, "label", exact = TRUE), "coded value")
    expect_identical(haven::na_tag(actual$x), c(NA, NA, "a", NA))
    expect_identical(unname(attr(actual$x, "labels")), c(1, 2))
    expect_identical(as.character(actual$text), data$text)
})

test_that("Stata reserved variable names are rejected", {
    reserved <- c(
        "alias", "_all", "_b", "_coef", "_cons", "_n", "_N", "_pi",
        "_pred", "_r_b", "_rc", "_r_ci", "_r_cri", "_r_crlb", "_r_crub",
        "_r_df", "_r_lb", "_r_p", "_r_se", "_r_ub", "_r_z", "_r_z_abs",
        "_se", "_skip", "_weight", "byte", "double", "float", "int",
        "long", "in", "if", "strL", "using", "with", "str1", "str2045",
        "str2046"
    )
    expect_false(any(dtaparser:::.valid_stata_names(reserved)))
    expect_true(all(dtaparser:::.valid_stata_names(c(
        "_r_test", "x١", "str0", "str00", "str01", "str02046"
    ))))
    for (name in reserved) {
        data <- stats::setNames(data.frame(1), name)
        path <- tempfile(fileext = ".dta")
        expect_error(
            write_dta(data, path),
            class = "dtaparser_write_validation_error",
            info = name
        )
        expect_false(file.exists(path), info = name)
    }
})

test_that("zero-row data frames with columns are supported", {
    data <- data.frame(x = integer(), text = character())
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path)
    expect_identical(dim(actual), c(0L, 2L))
    expect_identical(names(actual), names(data))
})

test_that("malformed and storage-incompatible explicit display formats fail", {
    cases <- list(
        numeric_string = structure(1, format.stata = "%9s"),
        string_numeric = structure("x", format.stata = "%8.0g"),
        malformed = structure(1, format.stata = "not-a-format"),
        invalid_numeric = structure(1, format.stata = "%9.0q"),
        invalid_precision = structure(1, format.stata = "%9.9g"),
        zero_width_string = structure("x", format.stata = "%0s"),
        wide_string = structure("x", format.stata = "%2046s"),
        malformed_month = structure(1, format.stata = "%tmjunk"),
        malformed_date = structure(as.Date("2020-01-01"), format.stata = "%tdfoo"),
        invalid_quarter_token = structure(
            as.Date("2020-01-01"), format.stata = "%tdQ"
        ),
        general_suffix = structure(1, format.stata = "%tg_"),
        escaped_general_suffix = structure(1, format.stata = "%tg!X"),
        long_business_calendar = structure(
            1, format.stata = "%tbaaaaaaaaaaa"
        ),
        digit_business_calendar = structure(1, format.stata = "%tb1cal:HH"),
        date_numeric = structure(as.Date("2020-01-01"), format.stata = "%9.0g")
    )
    for (name in names(cases)) {
        path <- tempfile(fileext = ".dta")
        expect_error(
            write_dta(data.frame(x = cases[[name]]), path),
            "format",
            info = name
        )
        expect_false(file.exists(path), info = name)
    }
})

test_that("documented numeric display formats are preserved", {
    formats <- c(
        "%09.2f", "%-9.0gc", "%21x", "%16H", "%09.2fc", "%-09.2f",
        "%0009.2f", "%1000.0g", "%twMon", "%tmDD", "%tqMonth",
        "%thWW", "%tyMonth", "%tbcal:HH", "%tbä:HH", "%tbcal:",
        "%tbaaaaaaaaaa"
    )
    data <- stats::setNames(
        lapply(formats, function(format) {
            structure(1, format.stata = format)
        }),
        paste0("x", seq_along(formats))
    )
    data <- as.data.frame(data)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(
        vapply(
            actual,
            attr,
            character(1),
            which = "format.stata",
            exact = TRUE
        ),
        stats::setNames(formats, names(data))
    )
})

test_that("documented string and temporal display formats are preserved", {
    date <- structure(
        as.Date("2020-01-01"),
        format.stata = "%tdMonth_dd,_CCYY"
    )
    datetime <- structure(
        as.POSIXct("2020-01-01 12:34:56", tz = "UTC"),
        format.stata = "%tcCCYY.NN.DD-HH:MM:SS"
    )
    date_clock <- structure(
        as.Date("2020-01-01"), format.stata = "%tdHH"
    )
    datetime_quarter <- structure(
        as.POSIXct("2020-01-01 12:34:56", tz = "UTC"),
        format.stata = "%tcq"
    )
    data <- data.frame(
        padded = structure("x", format.stata = "%0009s"),
        wide = structure("x", format.stata = "%2045s"),
        date = date,
        datetime = datetime,
        date_clock = date_clock,
        datetime_quarter = datetime_quarter
    )
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(
        vapply(
            actual,
            attr,
            character(1),
            which = "format.stata",
            exact = TRUE
        ),
        c(
            padded = "%0009s",
            wide = "%2045s",
            date = "%tdMonth_dd,_CCYY",
            datetime = "%tcCCYY.NN.DD-HH:MM:SS",
            date_clock = "%tdHH",
            datetime_quarter = "%tcq"
        )
    )
})

test_that("generic ALTSTRING columns are materialized before native writing", {
    values <- as.character(seq_len(1024L))
    skip_if_not(dtaparser:::.is_altrep(values))

    gctorture(TRUE)
    on.exit(gctorture(FALSE), add = TRUE)
    plan <- .Call(dtaparser:::C_dtaparser_write_string_plan, values)
    gctorture(FALSE)
    expect_false(dtaparser:::.is_altrep(plan[[3L]]))
    expect_identical(plan[[3L]], as.character(seq_len(1024L)))

    for (threshold in c(2045L, 1L)) {
        path <- tempfile(fileext = ".dta")
        on.exit(unlink(path), add = TRUE)
        expect_silent(write_dta(
            data.frame(text = values), path, strl_threshold = threshold
        ))
        expect_identical(
            as.vector(read_dta(path, use_numeric_altrep = FALSE)$text),
            values
        )
    }
})

test_that("generic ALTSTRING metadata stays rooted through native writing", {
    ephemeral <- function(values) {
        .Call(dtaparser:::C_dtaparser_ephemeral_altstring, values)
    }
    note_text <- paste0("note-", strrep("n", 12000L))
    label_text <- paste0("label-", strrep("l", 12000L))
    x <- stata_long(c(1, 2))
    attr(x, "labels") <- stats::setNames(c(1, 2), c(label_text, label_text))
    data <- data.frame(x = x)
    attr(data, "notes") <- c(note_text, note_text)
    specification <- dtaparser:::.prepare_dta_write(
        data, NULL, 2045L, TRUE, 19L
    )
    specification[[2L]] <- ephemeral(specification[[2L]])
    specification[[3L]][[1L]][[6L]] <- ephemeral(
        specification[[3L]][[1L]][[6L]]
    )
    expect_true(dtaparser:::.is_altrep(specification[[2L]]))
    expect_true(dtaparser:::.is_altrep(specification[[3L]][[1L]][[6L]]))

    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    gctorture(TRUE)
    on.exit(gctorture(FALSE), add = TRUE)
    expect_silent(.Call(
        dtaparser:::C_dtaparser_write, specification, path
    ))
    gctorture(FALSE)

    actual <- read_dta(path, use_numeric_altrep = FALSE)
    expect_identical(attr(actual, "notes", exact = TRUE), c(note_text, note_text))
    expect_identical(
        names(attr(actual$x, "labels", exact = TRUE)),
        c(label_text, label_text)
    )
})

test_that("numeric Stata calendar formats that remain numeric are preserved", {
    x <- stata_int(c(0, 1, NA_real_))
    attr(x, "format.stata") <- "%tmcY_m"
    data <- data.frame(x = x)
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)

    expect_silent(write_dta(data, path))
    actual <- read_dta(path, use_numeric_altrep = FALSE)$x
    expect_identical(as.double(actual), c(0, 1, NA_real_))
    expect_identical(attr(actual, "format.stata", exact = TRUE), "%tmcY_m")
    expect_false(inherits(actual, c("Date", "POSIXct")))
})
