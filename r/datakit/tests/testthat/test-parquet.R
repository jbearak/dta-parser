# read_parquet, read_parquet_info and save_parquet (plan 0018). The
# central check is the exact round trip: for every frame x that
# dtaparser::read_dta() returns, read_parquet() of save_parquet(x) is
# identical() to x.

repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."), mustWork = FALSE)

dta_fixtures <- function() {
  dir <- file.path(repo_root, "compat", "fixtures")
  testthat::skip_if_not(dir.exists(dir), "compat/fixtures is not here")
  Sys.glob(file.path(dir, "*.dta"))
}

parquet_fixtures <- function() {
  dir <- file.path(repo_root, "compat", "parquet")
  testthat::skip_if_not(dir.exists(dir), "compat/parquet is not here")
  dir
}

round_trip <- function(x, ...) {
  p <- tempfile(fileext = ".parquet")
  on.exit(unlink(p))
  save_parquet(x, p, ...)
  read_parquet(p)
}

# Each column of y as x has it, with what differs if not.
expect_same_frame <- function(y, x, what) {
  for (n in names(x)) {
    expect(identical(y[[n]], x[[n]]), paste0(what, ": column ", n, " differs"))
  }
  expect(identical(y, x), paste0(what, ": the frames differ"))
}

test_that("every .dta fixture round-trips exactly", {
  for (f in dta_fixtures()) {
    for (factors in c(FALSE, TRUE)) {
      x <- suppressWarnings(dtaparser::read_dta(f, factors = factors))
      expect_same_frame(round_trip(x), x, paste(basename(f), if (factors) "with factors"))
    }
  }
})

test_that("labels, letters, dates, factors and notes round-trip exactly", {
  x <- tibble::tibble(
    id = c(1L, NA, 3L, 4L),
    score = c(1.5, NA, tagged_na("a"), NaN),
    smoker = with_labels(c(1, 0, tagged_na("d"), NA), c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d"))),
                         label = "Smokes daily"),
    kids = with_labels(c(0L, 2L, NA, 1L), c(None = 0)),
    word = c("a", NA, "", "été"),
    flag = c(TRUE, FALSE, NA, TRUE),
    seen = as.Date(c("2024-01-15", NA, "1960-01-01", "1900-02-28")),
    # A date with .a and .r, as read_dta gives one.
    asked = structure(c(19000, tagged_na("a"), NA, tagged_na("r")), class = "Date", format = "%tdCCYY-NN-DD"),
    when = as.POSIXct(c(0, 1.5, NA, 1.7e9), origin = "1970-01-01", tz = "UTC"),
    zoned = as.POSIXct(c(0, 1, NA, 1.7e9), origin = "1970-01-01", tz = "America/New_York"),
    stamped = structure(c(tagged_na("b"), 2, NA, 1e9), class = c("POSIXct", "POSIXt"), tzone = "UTC"),
    region = factor(c("N", "S", NA, "N"), levels = c("S", "N", "W")),
    size = factor(c("lo", "hi", "hi", NA), levels = c("lo", "hi"), ordered = TRUE),
    blob = list(as.raw(1:3), NULL, raw(0), as.raw(255))
  )
  attr(x$score, "label") <- "Score"
  attr(x$score, "format") <- "%9.2f"
  attr(x$region, "label") <- "Region"
  attr(x, "label") <- "Smoking survey"
  attr(x, "notes") <- c("Wave 2 only.", "Second note")
  expect_same_frame(round_trip(x), x, "constructed")
  expect_same_frame(round_trip(x, compression = "snappy", row_group_size = 1), x, "one row per row group")
  for (codec in c("none", "gzip", "lz4_raw")) expect_same_frame(round_trip(x, compression = codec), x, codec)
})

test_that("dates and times a DATE or TIMESTAMP cannot hold exactly are written as numbers", {
  x <- tibble::tibble(
    half = as.Date(19000.5, origin = "1970-01-01"),
    now = as.POSIXct(1700000000.1234567, origin = "1970-01-01", tz = "Europe/Paris"),
    plain = as.POSIXct(1700000000.25, origin = "1970-01-01", tz = "UTC")
  )
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p)
  expect_identical(read_parquet(p), x)
  cols <- read_parquet_info(p)$columns
  expect_identical(cols$physical_type, c("DOUBLE", "DOUBLE", "INT64"))
  expect_identical(cols$logical, c("date", "timestamp", NA))
  expect_identical(cols$r_type, c("Date", "POSIXct", "POSIXct"))
})

test_that("a long string column, mostly distinct, round-trips with threads and small row groups", {
  n <- 30000
  x <- tibble::tibble(
    distinct = sprintf("value %06d", sample.int(n)),
    few = sample(c("north", "south", NA), n, replace = TRUE),
    mixed = ifelse(seq_len(n) > n / 2, sprintf("late %d", seq_len(n)), "early")
  )
  y <- round_trip(x, row_group_size = 1000)
  expect_identical(y, x)
  # A window crosses row groups and comes back as those rows.
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p, row_group_size = 1000)
  w <- read_parquet(p, skip = 12345, n_max = 2500)
  expect_identical(as.list(w), lapply(x, function(v) v[12346:14845]))
})

test_that("row windows are the rows of the whole read", {
  x <- dtaparser::read_dta(file.path(repo_root, "compat", "fixtures", "haven_118.dta"))
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p, row_group_size = 2)
  for (w in list(c(0, 2), c(1, 3), c(4, Inf), c(5, 10), c(6, 1), c(0, 0))) {
    got <- read_parquet(p, skip = w[1], n_max = w[2])
    rows <- seq_len(nrow(x))
    rows <- rows[rows > w[1]][seq_len(min(w[2], max(nrow(x) - w[1], 0)))]
    expect_identical(nrow(got), length(rows))
    for (n in names(x)) expect_identical(vctrs::vec_data(got[[n]]), vctrs::vec_data(x[[n]])[rows], info = paste(n, w))
  }
})

test_that("col_select takes names and tidyselect, in the order given", {
  x <- tibble::tibble(a = 1:2, b = c("x", "y"), cc = c(1.5, 2), d = 3:4)
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p)
  expect_identical(names(read_parquet(p, col_select = c("d", "a"))), c("d", "a"))
  expect_identical(names(read_parquet(p, col_select = "b")), "b")
  expect_identical(names(read_parquet(p, col_select = c(cc, a))), c("cc", "a"))
  expect_identical(names(read_parquet(p, col_select = tidyselect::starts_with("c"))), "cc")
  wanted <- c("b", "d")
  expect_identical(names(read_parquet(p, col_select = wanted)), c("b", "d"))
  # As tidyselect does, a column named like the variable wins.
  d <- c("a", "b")
  expect_identical(names(read_parquet(p, col_select = d)), "d")
  expect_error(read_parquet(p, col_select = c("a", "nope")), "column \"nope\" is not in the file; its columns are \"a\", \"b\", \"cc\", \"d\"")
  expect_error(read_parquet(p, col_select = c(a, nope)), "columns are \"a\", \"b\", \"cc\", \"d\"")
})

test_that("factors = TRUE does what it does for read_dta", {
  for (f in dta_fixtures()) {
    x <- suppressWarnings(dtaparser::read_dta(f))
    p <- tempfile(fileext = ".parquet")
    save_parquet(x, p)
    want <- tryCatch(dtaparser::read_dta(f, factors = TRUE), warning = function(w) class(w))
    got <- tryCatch(read_parquet(p, factors = TRUE), warning = function(w) class(w))
    expect_identical(got, want, info = basename(f))
    expect_identical(suppressWarnings(read_parquet(p, factors = TRUE)),
                     suppressWarnings(dtaparser::read_dta(f, factors = TRUE)), info = basename(f))
  }
})

test_that("read_parquet_info describes the file without reading it", {
  x <- tibble::tibble(
    id = 1:3,
    smoker = with_labels(c(1, 0, tagged_na("d")), c(No = 0, Yes = 1), label = "Smokes"),
    day = as.Date("2024-01-01") + 0:2,
    region = factor(c("a", "b", "a"))
  )
  attr(x, "label") <- "Survey"
  attr(x, "notes") <- "A note"
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p, row_group_size = 2)
  info <- read_parquet_info(p)
  expect_identical(info$rows, 3)
  expect_identical(info$row_groups$rows, c(2, 1))
  expect_true(all(info$row_groups$compressed_bytes > 0))
  expect_match(info$created_by, "^dta-parquet")
  expect_identical(info$compression, "zstd")
  expect_identical(info$label, "Survey")
  expect_identical(info$notes, "A note")
  cols <- info$columns
  expect_identical(cols$name, names(x))
  expect_identical(cols$role, rep("data", 4))
  expect_identical(cols$r_type, c("integer", "dtaparser_labelled", "Date", "factor"))
  expect_identical(cols$physical_type, c("INT32", "DOUBLE", "INT32", "BYTE_ARRAY"))
  expect_identical(cols$logical_type, c(NA, NA, "DATE", "STRING"))
  expect_identical(cols$label, c(NA, "Smokes", NA, NA))
  expect_identical(cols$value_labels, c(NA, "smoker", NA, NA))
  expect_identical(read_parquet_info(readBin(p, "raw", file.size(p)))$columns, cols)
})

test_that("a raw vector reads as the file does", {
  x <- tibble::tibble(a = 1:3, b = c("x", NA, "z"))
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p)
  expect_identical(read_parquet(readBin(p, "raw", file.size(p))), x)
  expect_error(read_parquet(raw(0)), "not a Parquet file")
})

test_that("save_parquet honours storage attributes and checks their values", {
  x <- data.frame(b = c(1, 2, NA), i = c(-300L, 2L, 3L), f = c(0.5, 1, 2))
  attr(x$b, "storage") <- "byte"
  attr(x$i, "storage") <- "int"
  attr(x$f, "storage") <- "float"
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p)
  info <- read_parquet_info(p)$columns
  expect_identical(info$logical_type, c("INT(8, signed)", "INT(16, signed)", NA))
  expect_identical(info$physical_type, c("INT32", "INT32", "FLOAT"))
  back <- read_parquet(p)
  expect_identical(back$b, c(1L, 2L, NA))
  expect_identical(back$f, c(0.5, 1, 2))
  attr(x$b, "storage") <- "byte"
  x$b[1] <- 1000
  expect_error(save_parquet(x, p), "column \"b\": row 1 holds 1000, which a byte column cannot hold")
  x$b[1] <- 1
  x$f[2] <- 0.1
  expect_error(save_parquet(x, p), "column \"f\": row 2 holds 0.1, which a float column does not hold exactly")
  # A byte column holding .a to .z is DOUBLE, its storage in the profile.
  y <- data.frame(b = c(1, tagged_na("a")))
  attr(y$b, "storage") <- "byte"
  save_parquet(y, p)
  expect_identical(read_parquet_info(p)$columns$storage, "byte")
  expect_identical(na_tag(read_parquet(p)$b), c(NA, "a"))
  expect_identical(read_parquet(p, n_max = 1)$b, 1L)
})

test_that("missing_letters = FALSE writes .a to .z as nulls", {
  x <- data.frame(v = c(1, tagged_na("a"), NA))
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p, missing_letters = FALSE)
  back <- read_parquet(p)$v
  expect_identical(is.na(back), c(FALSE, TRUE, TRUE))
  expect_identical(na_tag(back), c(NA_character_, NA, NA))
})

test_that("int64 columns read as doubles, integer64 or text", {
  skip_if_not_installed("bit64")
  big <- bit64::as.integer64(c("9007199254740993", "-5", NA))
  p <- tempfile(fileext = ".parquet")
  save_parquet(data.frame(n = 1:3, big = big), p)
  expect_identical(read_parquet_info(p)$columns$physical_type, c("INT32", "INT64"))
  expect_error(read_parquet(p), "row 1 cannot be held exactly as a double; read with int64 = \"integer64\" or int64 = \"character\"")
  expect_identical(read_parquet(p, int64 = "integer64")$big, big)
  expect_identical(read_parquet(p, int64 = "character")$big, c("9007199254740993", "-5", NA))
  expect_identical(read_parquet(p, col_select = "big", skip = 1)$big, c(-5, NA))
})

test_that("save_parquet's errors name the column", {
  p <- tempfile(fileext = ".parquet")
  expect_error(save_parquet(data.frame(a = 1), p, compression = "lzo"),
               "unknown compression \"lzo\"; use one of \"zstd\", \"snappy\", \"gzip\", \"lz4_raw\" or \"none\"")
  expect_error(save_parquet(data.frame(a = 1), p, compression_level = 99), "zstd levels run from 1 to 22")
  expect_error(save_parquet(data.frame(a = 1), p, compression = "snappy", compression_level = 2), "snappy has no compression levels")
  d <- data.frame(a = 1:2)
  d$l <- list(1, "x")
  expect_error(save_parquet(d, p), "column \"l\": element 1 is not a raw vector or NULL")
  expect_error(save_parquet(data.frame(z = complex(real = 1, imaginary = 1)), p), "cannot write z, a column of class complex")
  expect_error(save_parquet(data.frame(t = as.difftime(1, units = "secs")), p), "cannot write t, a column of class difftime")
  lt <- data.frame(a = 1)
  lt$t <- as.POSIXlt("2024-01-01", tz = "UTC")
  expect_error(save_parquet(lt, p), "cannot write t")
  nested <- tibble::tibble(a = 1, inner = tibble::tibble(b = 2))
  expect_error(save_parquet(nested, p), "cannot write inner")
  shared <- data.frame(a = with_labels(1, c(Yes = 1)), b = with_labels(1, c(No = 1)))
  attr(shared$a, "label_set") <- "yn"
  attr(shared$b, "label_set") <- "yn"
  expect_error(save_parquet(shared, p), "label set \"yn\" have different labels")
  expect_error(save_parquet(data.frame(v = 1), p, row_group_size = 0), "row_group_size")
  expect_invisible(save_parquet(data.frame(v = 1), p))
  expect_identical(save_parquet(data.frame(v = 1), p), data.frame(v = 1))
})

test_that("read_parquet checks its arguments", {
  p <- tempfile(fileext = ".parquet")
  save_parquet(data.frame(v = 1), p)
  expect_error(read_parquet(p, int64 = "big"), "int64 must be \"double\", \"integer64\" or \"character\"")
  expect_error(read_parquet(p, timestamps = "round"), "timestamps must be \"error\" or \"truncate\"")
  expect_error(read_parquet(p, nested = "yes"), "nested must be \"error\" or \"skip\"")
  expect_error(read_parquet(p, decimal = "float"), "decimal must be \"double\" or \"character\"")
  expect_error(read_parquet(p, skip = -1), "skip must be a number >= 0")
  expect_error(read_parquet(file.path(tempdir(), "no-such-file.parquet")))
})

# ---- files other tools wrote: values against pyarrow's reading of them

per_second <- c(s = 1, ms = 1e3, us = 1e6, ns = 1e9)

# A column's values as plain R values to compare with the expected JSON.
plain_values <- function(x, arrow_type) {
  if (startsWith(arrow_type, "timestamp[")) {
    unit <- sub("^timestamp\\[([a-z]+).*$", "\\1", arrow_type)
    # Nanoseconds come back to the microsecond (timestamps = "truncate").
    return(round(as.numeric(x) * min(per_second[[unit]], 1e6)))
  }
  if (inherits(x, "Date")) return(as.numeric(x))
  if (is.factor(x)) return(as.character(x))
  x
}

same_value <- function(want, got, arrow_type) {
  if (is.null(want)) return(is.null(got) || (length(got) == 1 && is.na(got) && !is.nan(got)))
  if (identical(want, "NaN")) return(is.numeric(got) && is.nan(got))
  if (is.list(want)) return(identical(as.integer(unlist(want)), as.integer(got)))
  if (is.null(got) || is.na(got)) return(FALSE)
  if (startsWith(arrow_type, "timestamp[ns")) want <- floor(want / 1000)
  if (is.numeric(want) && want == 0 && is.numeric(got)) return(got == 0 && (1 / want) == (1 / got))
  isTRUE(all.equal(want, got, tolerance = 0))
}

expect_fixture <- function(df, expected, rows, what) {
  for (spec in expected$columns) {
    got <- plain_values(df[[spec$name]], spec$arrow_type)
    want <- spec$values[rows]
    expect(length(got) == length(want), paste0(what, ": ", spec$name, " has ", length(got), " rows, not ", length(want)))
    bad <- which(!vapply(seq_along(want), function(i) {
      same_value(want[[i]], if (is.list(got)) got[[i]] else got[i], spec$arrow_type)
    }, NA))
    expect(!length(bad), paste0(what, ": ", spec$name, " row ", bad[1], " is ", format(got[bad[1]]), ", not ", format(want[[bad[1]]])))
  }
}

r_class <- function(arrow_type) {
  if (grepl("^int(8|16|32)$", arrow_type)) return("integer")
  if (arrow_type %in% c("int64", "float", "double")) return("numeric")
  if (arrow_type == "bool") return("logical")
  if (grepl("string|dictionary", arrow_type)) return("character")
  if (grepl("binary", arrow_type)) return("list")
  if (startsWith(arrow_type, "date32")) return("Date")
  if (startsWith(arrow_type, "timestamp")) return("POSIXct")
  stop("unknown type ", arrow_type)
}

test_that("files from pyarrow, polars, DuckDB, arrow and nanoparquet read as pyarrow reads them", {
  skip_if_not_installed("jsonlite")
  dir <- parquet_fixtures()
  for (f in Sys.glob(file.path(dir, "fixtures", "*.parquet"))) {
    stem <- sub("\\.parquet$", "", basename(f))
    expected <- jsonlite::fromJSON(file.path(dir, "expected", paste0(stem, ".json")), simplifyVector = FALSE)
    nested <- if (length(expected$nested)) "skip" else "error"
    df <- read_parquet(f, timestamps = "truncate", nested = nested)
    expect_identical(names(df), vapply(expected$columns, `[[`, "", "name"), info = stem)
    for (spec in expected$columns) {
      expect(inherits(df[[spec$name]], r_class(spec$arrow_type)),
             paste0(stem, ": ", spec$name, " is ", class(df[[spec$name]])[1], ", not ", r_class(spec$arrow_type)))
    }
    expect_fixture(df, expected, seq_len(expected$rows), stem)
    for (w in list(c(0, 7), c(150, 101), c(599, 5), c(250, 300))) {
      rows <- seq(w[1] + 1, min(w[1] + w[2], expected$rows))
      part <- read_parquet(f, skip = w[1], n_max = w[2], timestamps = "truncate", nested = nested)
      expect_fixture(part, expected, rows, paste(stem, "rows", w[1] + 1, "to", max(rows)))
    }
  }
})

test_that("nanoseconds that are not whole microseconds are an error unless truncated", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_default.parquet")
  expect_error(read_parquet(f), "column \"ts_ns_local\": row 2 is 1000000007 nanoseconds, which is not a whole number of microseconds; read with timestamps = \"truncate\"")
  expect_s3_class(read_parquet(f, col_select = "ts_ns_local", timestamps = "truncate")$ts_ns_local, "POSIXct")
})

test_that("nested columns are named unless skipped or left out", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_nested.parquet")
  expect_error(read_parquet(f), "the file has nested columns, which are not read: .*select the columns wanted, or pass nested = \"skip\"")
  expect_identical(names(read_parquet(f, nested = "skip")), c("id", "name"))
  expect_identical(names(read_parquet(f, col_select = c("name", "id"))), c("name", "id"))
  cols <- read_parquet_info(f)$columns
  expect_true(all(is.na(cols$r_type[cols$role == "nested"])))
  expect_error(read_parquet(f, col_select = cols$name[cols$role == "nested"][1]), "is nested")
})

# ---- other tools reading what save_parquet writes

readback_frame <- function() {
  tibble::tibble(
    n = c(1L, NA, 3L),
    v = c(1.5, tagged_na("r"), NA),
    s = c("a", NA, "c"),
    day = as.Date(c("2024-01-01", NA, "2000-02-29")),
    when = as.POSIXct(c(0, NA, 1.7e9), origin = "1970-01-01", tz = "America/Chicago"),
    region = factor(c("N", "S", NA), levels = c("S", "N", "W")),
    size = factor(c("lo", "hi", "lo"), levels = c("lo", "hi"), ordered = TRUE)
  )
}

test_that("arrow reads save_parquet's files, .a to .z as tagged NAs", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("haven")
  x <- readback_frame()
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p)
  a <- arrow::read_parquet(p)
  expect_identical(a$n, x$n)
  expect_identical(haven::na_tag(a$v), c(NA, "r", NA))
  expect_identical(a$s, x$s)
  expect_identical(a$day, x$day)
  expect_identical(as.numeric(a$when), as.numeric(x$when))
  expect_identical(attr(a$when, "tzone"), "America/Chicago")
  expect_identical(levels(a$region), c("S", "N", "W"))
  expect_identical(as.character(a$region), as.character(x$region))
  expect_true(is.ordered(a$size))
})

test_that("nanoparquet reads save_parquet's files", {
  skip_if_not_installed("nanoparquet")
  skip_if_not_installed("haven")
  x <- readback_frame()
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p, compression = "snappy")
  a <- nanoparquet::read_parquet(p)
  expect_identical(a$n, x$n)
  expect_identical(haven::na_tag(a$v), c(NA, "r", NA))
  expect_identical(a$s, x$s)
  expect_identical(as.numeric(a$day), as.numeric(x$day))
  expect_identical(as.numeric(a$when), as.numeric(x$when))
  expect_identical(levels(a$region), c("S", "N", "W"))
})
