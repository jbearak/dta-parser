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
    mixed = ifelse(seq_len(n) > n / 2, sprintf("late %d", seq_len(n)), "early"),
    # Missing in a few row groups only: the others are copied whole.
    gaps = replace(sprintf("id %06d", sample.int(n)), c(5, 4321, 25000), NA)
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
  expect_identical(info$compression, "snappy")
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
  kv <- info$key_value
  expect_identical(names(kv), c("key", "value"))
  expect_true("dta" %in% kv$key)
  expect_match(kv$value[kv$key == "dta"], "\"Survey\"", fixed = TRUE)
})

test_that("read_parquet_info lists another writer's key-value entries", {
  dir <- parquet_fixtures()
  kv <- read_parquet_info(file.path(dir, "fixtures", "pyarrow_default.parquet"))$key_value
  expect_true("ARROW:schema" %in% kv$key)
  expect_false("dta" %in% kv$key)
  expect_type(kv$value, "character")
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
               "unknown compression \"lzo\"; use one of \"snappy\", \"zstd\", \"gzip\", \"lz4_raw\" or \"none\"")
  expect_error(save_parquet(data.frame(a = 1), p, compression = "zstd", compression_level = 99), "zstd levels run from 1 to 22")
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

# The unit in an Arrow type such as "timestamp[ns, tz=UTC]" or "time64[us]".
arrow_unit <- function(arrow_type) sub("^[a-z0-9]+\\[([a-z]+).*$", "\\1", arrow_type)

# INT64 and unsigned 32- and 64-bit columns, and decimals: read as
# numbers by default and as text with int64 = "character" and decimal =
# "character".
text_kind <- function(arrow_type) grepl("^(int64|uint32|uint64|decimal)", arrow_type)

# The significant digits of a decimal written as text.
significant_digits <- function(text) nchar(sub("0+$", "", sub("^0+", "", gsub("[-.]", "", text))))

# Integers in the JSON of 16 digits or more are read as text
# (read_expected) and worked on here as digits: jsonlite and as.numeric()
# do not round them to the nearest double.

# The expected values of a fixture.
read_expected <- function(path) {
  json <- paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  json <- gsub("(?<=[,\\[:])(-?[0-9]{16,})(?=[,\\]}])", "\"\\1\"", json, perl = TRUE)
  jsonlite::fromJSON(json, simplifyVector = FALSE)
}

# Half of the digits of an even number.
half_digits <- function(d) {
  digits <- as.integer(strsplit(d, "", fixed = TRUE)[[1]])
  carry <- 0L
  for (i in seq_along(digits)) {
    v <- carry * 10L + digits[i]
    digits[i] <- v %/% 2L
    carry <- v %% 2L
  }
  sub("^0+(?=.)", "", paste(digits, collapse = ""), perl = TRUE)
}

# Whether the integer written as text is a double exactly: its odd part
# is at most 2^53.
exact_double <- function(text) {
  d <- sub("^-", "", text)
  while (nchar(d) > 16 || (nchar(d) == 16 && d > "9007199254740992")) {
    if (as.integer(substring(d, nchar(d))) %% 2L) return(FALSE)
    d <- half_digits(d)
  }
  TRUE
}

# A decimal of at most 15 significant digits as C's "%.14e" writes the
# nearest double to it: those digits. NA for zero.
decimal_e <- function(text) {
  parts <- strsplit(sub("^-", "", text), ".", fixed = TRUE)[[1]]
  digits <- paste(parts, collapse = "")
  lead <- nchar(sub("[1-9].*$", "", digits))
  if (lead == nchar(digits)) return(NA_character_)
  digits <- substr(paste0(substring(digits, lead + 1), strrep("0", 15)), 1, 15)
  exponent <- nchar(parts[1]) - lead - 1
  sprintf("%s%s.%se%s%02d", if (startsWith(text, "-")) "-" else "", substr(digits, 1, 1), substring(digits, 2),
          if (exponent < 0) "-" else "+", abs(exponent))
}

# Nanoseconds written as text, as whole microseconds (rounded down).
micros_of_nanos <- function(text) {
  d <- sub("^-", "", text)
  n <- nchar(d)
  q <- if (n > 3) as.numeric(substr(d, 1, n - 3)) else 0
  r <- if (n > 3) as.numeric(substring(d, n - 2)) else as.numeric(d)
  if (startsWith(text, "-")) -(q + (r > 0)) else q
}

# What read_parquet()'s error says of a value its defaults cannot hold, or
# NA if they hold it: an integer a double does not hold exactly, a decimal
# with more than 15 significant digits, and R's integer NA in an INT32.
too_wide <- function(v, arrow_type) {
  if (is.null(v)) return(NA_character_)
  if (startsWith(arrow_type, "decimal") && significant_digits(v) > 15) return("decimal = \"character\"")
  if (is.character(v) && grepl("^(int64|uint32|uint64)$", arrow_type) && !exact_double(v)) {
    return("int64 = \"integer64\" or int64 = \"character\"")
  }
  if (arrow_type == "int32" && isTRUE(v == -2147483648)) return("cannot be held as an R integer")
  NA_character_
}

# The class read_parquet() gives a column of `arrow_type` (pyarrow's
# reading of it) with its default arguments. `logical` is the column's
# Parquet logical type: pyarrow reads an ENUM as binary, ours as text.
r_class <- function(arrow_type, logical = NA) {
  if (identical(logical, "ENUM")) return("character")
  if (grepl("^u?int(8|16)$", arrow_type) || arrow_type == "int32") return("integer")
  if (grepl("^(int64|uint32|uint64|float|double|decimal)", arrow_type)) return("numeric")
  if (arrow_type == "bool") return("logical")
  if (grepl("^dictionary<values=(large_)?string", arrow_type)) return("factor")
  if (startsWith(arrow_type, "dictionary<")) return(r_class(sub("^dictionary<values=([^,]+),.*$", "\\1", arrow_type)))
  if (grepl("string|arrow\\.json", arrow_type)) return("character")
  if (grepl("binary|arrow\\.uuid", arrow_type)) return("list")
  if (startsWith(arrow_type, "date32")) return("Date")
  if (startsWith(arrow_type, "timestamp")) return("POSIXct")
  if (startsWith(arrow_type, "time")) return("difftime")
  stop("unknown type ", arrow_type)
}

# A column's values as plain R values to compare with the expected JSON.
plain_values <- function(x, arrow_type) {
  if (startsWith(arrow_type, "timestamp[")) {
    # Nanoseconds come back to the microsecond (timestamps = "truncate").
    return(round(as.numeric(x) * min(per_second[[arrow_unit(arrow_type)]], 1e6)))
  }
  if (inherits(x, "difftime")) return(round(as.numeric(x, units = "secs") * per_second[[arrow_unit(arrow_type)]]))
  if (inherits(x, "Date")) return(as.numeric(x))
  if (is.factor(x)) return(as.character(x))
  x
}

same_value <- function(want, got, arrow_type) {
  if (is.null(want)) return(is.null(got) || (length(got) == 1 && is.na(got) && !is.nan(got)))
  if (identical(want, "NaN")) return(is.numeric(got) && is.nan(got))
  # Bytes; an ENUM, which pyarrow reads as binary, as the bytes of its text.
  if (is.list(want)) return(identical(as.integer(unlist(want)), as.integer(if (is.character(got)) charToRaw(got) else got)))
  if (is.null(got) || is.na(got)) return(FALSE)
  if (is.character(got)) {
    if (is.numeric(want)) want <- sprintf("%.0f", want)
    return(identical(enc2utf8(got), enc2utf8(want)))
  }
  if (startsWith(arrow_type, "timestamp[ns")) {
    want <- if (is.character(want)) micros_of_nanos(want) else floor(want / 1000)
  }
  # Decimals (at most 15 significant digits here) and integers of 16
  # digits or more are text in the JSON, compared as digits.
  if (is.character(want) && startsWith(arrow_type, "decimal")) {
    e <- decimal_e(want)
    return(if (is.na(e)) identical(got, 0) else identical(sprintf("%.14e", got), e))
  }
  if (is.character(want)) return(identical(sprintf("%.0f", got), want))
  if (is.numeric(want) && want == 0 && is.numeric(got)) return(got == 0 && (1 / want) == (1 / got))
  isTRUE(all.equal(want, got, tolerance = 0))
}

expect_fixture <- function(df, expected, rows, what, names = NULL) {
  for (spec in expected$columns) {
    if (!is.null(names) && !(spec$name %in% names)) next
    x <- df[[spec$name]]
    got <- plain_values(x, spec$arrow_type)
    want <- spec$values[rows]
    expect(length(got) == length(want), paste0(what, ": ", spec$name, " has ", length(got), " rows, not ", length(want)))
    bad <- which(!vapply(seq_along(want), function(i) {
      same_value(want[[i]], if (is.list(got)) got[[i]] else got[i], spec$arrow_type)
    }, NA))
    expect(!length(bad), paste0(what, ": ", spec$name, " row ", bad[1], " is ", format(got[bad[1]]), ", not ", format(want[[bad[1]]])))
    if (is.factor(x)) {
      # Levels from ARROW:schema are the values read, in order of first
      # appearance, and unordered.
      seen <- unique(as.character(x[!is.na(x)]))
      expect(identical(levels(x), seen) && !is.ordered(x), paste0(what, ": ", spec$name, "'s levels are not the values read in order"))
    }
  }
}

# Read rows skip + 1 to skip + n_max of fixture f and compare with
# pyarrow's reading: with the default arguments every column whose values
# they hold, the others as an error naming the argument that keeps them;
# and the INT64, unsigned and decimal columns as text.
# `errors` holds too_wide() of each column's values.
check_fixture <- function(f, expected, info, errors, skip, n_max, what) {
  nested <- if (length(expected$nested)) "skip" else "error"
  rows <- seq_len(expected$rows)
  rows <- rows[rows > skip][seq_len(min(n_max, max(expected$rows - skip, 0)))]
  logical <- stats::setNames(info$columns$logical_type, info$columns$name)
  wide <- vapply(errors, function(e) {
    e <- e[rows][!is.na(e[rows])]
    if (length(e)) e[[1]] else NA_character_
  }, "")
  names <- vapply(expected$columns, `[[`, "", "name")
  ok <- names[is.na(wide)]
  df <- read_parquet(f, col_select = ok, skip = skip, n_max = n_max, timestamps = "truncate", nested = nested)
  expect_identical(names(df), ok, info = what)
  for (spec in expected$columns[is.na(wide)]) {
    x <- df[[spec$name]]
    want <- r_class(spec$arrow_type, logical[[spec$name]])
    expect(inherits(x, want), paste0(what, ": ", spec$name, " is ", class(x)[1], ", not ", want))
    if (want == "POSIXct") {
      zone <- if (grepl("tz=", spec$arrow_type)) sub("^.*tz=([^]]+)\\]$", "\\1", spec$arrow_type) else "UTC"
      expect(identical(attr(x, "tzone"), zone), paste0(what, ": ", spec$name, " is in ", format(attr(x, "tzone")), ", not ", zone))
    }
    if (want == "difftime") expect(identical(units(x), "secs"), paste0(what, ": ", spec$name, " is not in seconds"))
  }
  expect_fixture(df, expected, rows, what, ok)
  for (k in which(!is.na(wide))) {
    expect_error(read_parquet(f, col_select = names[k], skip = skip, n_max = n_max, timestamps = "truncate"),
                 wide[[k]], fixed = TRUE, info = paste(what, names[k]))
  }
  text <- names[vapply(expected$columns, function(s) text_kind(s$arrow_type), NA)]
  if (length(text)) {
    df <- read_parquet(f, col_select = text, skip = skip, n_max = n_max, int64 = "character", decimal = "character")
    for (n in text) expect(is.character(df[[n]]), paste0(what, ": ", n, " is not character with int64 and decimal \"character\""))
    expect_fixture(df, expected, rows, paste(what, "as text"), text)
  }
}

test_that("files from pyarrow, polars, DuckDB, arrow, nanoparquet and others read as pyarrow reads them", {
  skip_if_not_installed("jsonlite")
  dir <- parquet_fixtures()
  for (f in Sys.glob(file.path(dir, "fixtures", "*.parquet"))) {
    stem <- sub("\\.parquet$", "", basename(f))
    expected <- read_expected(file.path(dir, "expected", paste0(stem, ".json")))
    info <- read_parquet_info(f)
    errors <- lapply(expected$columns, function(s) vapply(s$values, too_wide, "", s$arrow_type))
    check_fixture(f, expected, info, errors, 0, Inf, stem)
    for (w in list(c(0, 7), c(150, 101), c(599, 5), c(250, 300))) {
      what <- paste(stem, "rows", w[1] + 1, "to", min(w[1] + w[2], expected$rows))
      check_fixture(f, expected, info, errors, w[1], w[2], what)
    }
  }
})

test_that("read_parquet_info gives the R type of each Parquet type", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_types.parquet")
  cols <- read_parquet_info(f)$columns
  r_type <- stats::setNames(cols$r_type, cols$name)
  expect_identical(r_type[c("u8", "u16", "u32", "u64")], c(u8 = "integer", u16 = "integer", u32 = "double", u64 = "double"))
  expect_identical(unname(r_type[c("t_ms", "t_us", "t_ns")]), rep("difftime", 3))
  expect_identical(unname(r_type[c("dec9", "dec18", "dec38", "dec50")]), rep("double", 4))
  expect_identical(unname(r_type[c("fixed", "uid", "js", "icat", "stamp")]), c("list", "list", "character", "double", "POSIXct"))
  # The INT96 column.
  expect_identical(cols$physical_type[cols$name == "stamp"], "INT96")
  hy <- read_parquet_info(file.path(parquet_fixtures(), "fixtures", "hyparquet_default.parquet"))$columns
  expect_identical(hy$r_type[hy$logical_type %in% "ENUM"], "character")
  pa <- read_parquet_info(file.path(parquet_fixtures(), "fixtures", "pyarrow_default.parquet"))$columns
  expect_identical(pa$r_type[pa$name == "cat"], "factor")
})

test_that("a decimal with more than 15 significant digits is an error unless read as text", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_types.parquet")
  expect_error(read_parquet(f, col_select = "dec38"),
               "column \"dec38\": the value -370370367037037036.7037037100 in row 1 has more than 15 significant digits, which a double cannot hold exactly; read with decimal = \"character\" to keep every digit",
               fixed = TRUE)
  text <- read_parquet(f, col_select = c("dec38", "dec9"), decimal = "character", n_max = 2)
  expect_identical(text$dec38, c("-370370367037037036.7037037100", "-369135799146913579.9146913643"))
  expect_identical(text$dec9, c("-3000.00", "-2987.63"))
  # Precision 15 or less: the nearest double, also in decimal = "double".
  expect_identical(read_parquet(f, col_select = "dec9", n_max = 2)$dec9, c(-3000, -2987.63))
  # Precision 18, every value read with at most 15 significant digits.
  expect_identical(read_parquet(f, col_select = "dec18", n_max = 2)$dec18, c(-9000000000, -8990123456.7899))
})

test_that("unsigned integers read as integer, or with the INT64 rules", {
  skip_if_not_installed("bit64")
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_types.parquet")
  small <- read_parquet(f, col_select = c("u8", "u16", "u32"), n_max = 3)
  expect_identical(small$u8, 0:2)
  expect_identical(small$u16, c(0L, 109L, 218L))
  expect_identical(small$u32, c(0, 7158271, 14316542))
  expect_error(read_parquet(f, col_select = "u64"),
               "column \"u64\": the value 30740755617891237 in row 2 cannot be held exactly as a double; read with int64 = \"integer64\" or int64 = \"character\" to keep every digit",
               fixed = TRUE)
  expect_identical(read_parquet(f, col_select = "u64", n_max = 3, int64 = "character")$u64,
                   c("0", "30740755617891237", "61481511235782474"))
  expect_identical(read_parquet(f, col_select = "u64", n_max = 3, int64 = "integer64")$u64,
                   bit64::as.integer64(c("0", "30740755617891237", "61481511235782474")))
  expect_identical(read_parquet(f, col_select = "u32", n_max = 2, int64 = "character")$u32, c("0", "7158271"))
  # 2^63 and above: no integer64 holds it.
  expect_error(read_parquet(f, col_select = "u64", int64 = "integer64"),
               "column \"u64\": the value 9252967440985262337 in row 302 cannot be held exactly as a 64-bit integer; read with int64 = \"character\" to keep every digit",
               fixed = TRUE)
  big <- read_parquet(f, col_select = "u64", int64 = "character")$u64
  expect_identical(big[302], "9252967440985262337")
})

test_that("TIME reads as difftime in seconds, INT96 as POSIXct in UTC", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_types.parquet")
  x <- read_parquet(f, col_select = c("t_ms", "t_us", "t_ns", "stamp"), n_max = 2, timestamps = "truncate")
  expect_s3_class(x$t_ms, "difftime")
  expect_identical(units(x$t_ms), "secs")
  expect_identical(as.numeric(x$t_ms), c(0, 143.999))
  expect_identical(as.numeric(x$t_us), c(0, 143.999999))
  expect_equal(as.numeric(x$t_ns), c(0, 143.999999999), tolerance = 0)
  expect_s3_class(x$stamp, "POSIXct")
  expect_identical(attr(x$stamp, "tzone"), "UTC")
  # -98999999993 nanoseconds, truncated to the microsecond below.
  expect_identical(as.numeric(x$stamp), c(-100, -99))
})

test_that("a dictionary of strings in ARROW:schema is a factor with the levels read", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_default.parquet")
  whole <- read_parquet(f, col_select = "cat")$cat
  expect_s3_class(whole, "factor")
  expect_false(is.ordered(whole))
  expect_identical(levels(whole), c("low", "mid", "high"))
  # Another window, other levels: those of its rows, as they appear.
  part <- read_parquet(f, col_select = "cat", skip = 1, n_max = 2)$cat
  expect_identical(levels(part), c("mid", "high"))
  expect_identical(as.character(part), c("mid", "high"))
  expect_identical(levels(read_parquet(f, col_select = "cat", skip = 1, n_max = 3)$cat), c("mid", "high"))
  expect_identical(levels(read_parquet(f, col_select = "cat", skip = 4)$cat), c("mid", "high", "low"))
  # factors = TRUE is about value labels; it leaves these alone.
  expect_identical(read_parquet(f, col_select = "cat", factors = TRUE)$cat, whole)
  # A dictionary of integers reads as its values.
  ty <- file.path(parquet_fixtures(), "fixtures", "pyarrow_types.parquet")
  expect_identical(read_parquet(ty, col_select = "icat", n_max = 3)$icat, c(0, 1000, 2000))
})

test_that("an arrow factor reads with the levels of its rows, not arrow's", {
  skip_if_not_installed("arrow")
  p <- tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(f = factor(c("a", "a", "z", NA), levels = c("z", "a", "unused"))), p)
  x <- read_parquet(p)$f
  expect_identical(levels(x), c("a", "z"))
  expect_identical(as.character(x), c("a", "a", "z", NA))
  expect_identical(levels(read_parquet(p, skip = 2)$f), "z")
  expect_identical(read_parquet_info(p)$columns$r_type, "factor")
})

test_that("a timestamp's zone comes from ARROW:schema when the profile has none", {
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_default.parquet")
  x <- read_parquet(f, col_select = c("ts_us_ny", "ts_ms", "ts_ns_local"), timestamps = "truncate", n_max = 2)
  expect_identical(attr(x$ts_us_ny, "tzone"), "America/New_York")
  expect_identical(attr(x$ts_ms, "tzone"), "UTC")
  # A local time, without zone: UTC.
  expect_identical(attr(x$ts_ns_local, "tzone"), "UTC")
  a <- read_parquet(file.path(parquet_fixtures(), "fixtures", "arrow_r_default.parquet"), col_select = "when")
  expect_identical(attr(a$when, "tzone"), "Europe/Paris")
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

# ---- categoricals holding .a to .z (plan 0022)
#
# R cannot write one, so the files in fixtures/ were written by
# TypeScript's datakit; fixtures/make-categorical-letters.js makes them
# again. Each has `grade`, levels low < mid < high.

letters_fixture <- function(name) testthat::test_path("fixtures", paste0("categorical-letters", name, ".parquet"))

# grade as read_parquet() gives it: rows low, .a, high, ., .z, mid.
grade_read <- function(set = "grade") {
  x <- with_labels(c(1, tagged_na("a"), 3, NA, tagged_na("z"), 2), c(low = 1, mid = 2, high = 3))
  attr(x, "label_set") <- set
  x
}

test_that("a categorical holding .a to .z reads as a labelled double, factors or not", {
  p <- letters_fixture("")
  expect_no_warning(x <- read_parquet(p))
  expect_identical(x$grade, grade_read())
  expect_identical(na_tag(vctrs::vec_data(x$grade)), c(NA, "a", NA, NA, "z", NA))
  # factors = TRUE leaves it as it is, with no warning about lost letters.
  expect_no_warning(y <- read_parquet(p, factors = TRUE))
  expect_identical(y, x)
  expect_identical(read_parquet(p, skip = 2, n_max = 3)$grade, grade_read()[3:5])
  cols <- read_parquet_info(p)$columns
  expect_identical(cols$r_type, "dtaparser_labelled")
  expect_identical(cols$physical_type, "DOUBLE")
  expect_identical(cols$logical, "categorical")
  expect_identical(cols$value_labels, "grade")
})

test_that("a categorical without letters is a factor and its logical says categorical", {
  p <- tempfile(fileext = ".parquet")
  save_parquet(data.frame(f = factor(c("b", NA, "a"))), p)
  cols <- read_parquet_info(p)$columns
  expect_identical(cols$r_type, "factor")
  expect_identical(cols$physical_type, "BYTE_ARRAY")
  expect_identical(cols$logical, "categorical")
})

test_that("save_parquet writes it back as labelled numbers", {
  x <- read_parquet(letters_fixture(""))
  p <- tempfile(fileext = ".parquet")
  save_parquet(x, p)
  expect_no_warning(y <- read_parquet(p))
  want <- grade_read()
  attr(want, "label_set") <- NULL
  expect_identical(y$grade, want)
  expect_identical(na_tag(vctrs::vec_data(y$grade)), c(NA, "a", NA, NA, "z", NA))
  cols <- read_parquet_info(p)$columns
  expect_identical(cols$physical_type, "DOUBLE")
  expect_identical(cols$logical, NA_character_)
  expect_identical(cols$value_labels, "grade")
})

test_that("a value that is not a level number is NA, with one warning per read", {
  p <- letters_fixture("-bad")
  # Rows 1 and 2 (low, .a) are in the first row group; row 3 holds 1.5.
  expect_no_warning(x <- read_parquet(p, n_max = 2))
  expect_identical(x$grade, grade_read()[1:2])
  for (round in 1:2) {
    expect_warning(y <- read_parquet(p, skip = 1), "column \"grade\": row 3 holds 1.5, which is not one of its 3 level numbers; it is read as NA", fixed = TRUE)
    expect_identical(y$grade, structure(with_labels(c(tagged_na("a"), NA, 2), c(low = 1, mid = 2, high = 3)),
                                        label_set = "grade"))
  }
  w <- character()
  withCallingHandlers(read_parquet(p, factors = TRUE), warning = function(c) {
    w <<- c(w, conditionMessage(c))
    invokeRestart("muffleWarning")
  })
  expect_length(w, 1)
})

test_that("a set that does not fit the categorical keeps its name for the column that uses it", {
  p <- letters_fixture("-collision")
  expect_no_warning(x <- read_parquet(p))
  expect_identical(x$grade, grade_read("grade_2"))
  expect_identical(attr(x$other, "labels"), c(yes = 1))
  cols <- read_parquet_info(p)$columns
  expect_identical(cols$value_labels, c("grade_2", "grade"))
  expect_identical(cols$logical, c("categorical", NA))
  # Read alone, the categorical makes the same name.
  expect_identical(read_parquet(p, col_select = "grade")$grade, grade_read("grade_2"))
  expect_identical(read_parquet(p, col_select = grade)$grade, grade_read("grade_2"))
  # Written back, both sets are kept: grade_2 by its label_set, and the
  # other column's labels under its own name (R columns carry no
  # label_set unless one is given).
  q <- tempfile(fileext = ".parquet")
  save_parquet(x, q)
  y <- read_parquet(q)
  expect_identical(attr(y$grade, "labels"), c(low = 1, mid = 2, high = 3))
  expect_identical(attr(y$other, "labels"), c(yes = 1))
  expect_identical(read_parquet_info(q)$columns$value_labels, c("grade_2", "other"))
})

test_that("read_parquet_pl: a nested column named like the variable in col_select is an error", {
  skip_without_polars()
  # It is picked, as read_parquet() picks it, whatever `nested` says.
  f <- file.path(parquet_fixtures(), "fixtures", "pyarrow_nested.parquet")
  info <- read_parquet_info(f)$columns
  nested_name <- info$name[info$role == "nested"][1]
  assign(nested_name, "id")
  for (nested in c("error", "skip")) {
    expect_error(eval(bquote(read_parquet_pl(f, col_select = .(as.name(nested_name)), nested = .(nested)))),
                 "is nested")
    expect_error(eval(bquote(read_parquet(f, col_select = .(as.name(nested_name)), nested = .(nested)))),
                 "nested")
  }
})
