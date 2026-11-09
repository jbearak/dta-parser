# datakit's polars functions (plan 0025, stage 3): the reads, the saves,
# and .a to .z in polars, by Python datakit's rules (_frame.py).

col <- function(df, name) df$get_column(name)$to_r_vector()
dtype <- function(df, name) format(df$schema[[name]])

# A Parquet file whose x holds .a, .b and ., with labels.
survey_parquet <- function() {
  p <- tempfile(fileext = ".parquet")
  d <- data.frame(id = 1:4,
                  x = with_labels(c(1, tagged_na("a"), NA, tagged_na("b")),
                                  c(One = 1, tagged_na(c(Refused = "a"))), label = "Answer"))
  attr(d, "label") <- "Survey"
  attr(d, "notes") <- "Made for the tests"
  save_parquet(d, p)
  p
}

# Columns of each storage type with .a in row 2.
storage_frame <- function() {
  mk <- function(st) structure(c(1, tagged_na("a"), NA, 3), storage = st)
  data.frame(b = mk("byte"), i = mk("int"), l = mk("long"), f = mk("float"))
}

test_that("read_parquet_pl gives a polars frame and its datakit_meta", {
  skip_without_polars()
  res <- read_parquet_pl(survey_parquet())
  expect_named(res, c("df", "meta"))
  expect_s3_class(res$df, "polars_data_frame")
  expect_s3_class(res$meta, "datakit_meta")
  expect_identical(res$df$columns, c("id", "x"))
  expect_identical(dtype(res$df, "id"), "Int32")
  expect_identical(dtype(res$df, "x"), "Float64")
  expect_identical(col(res$df, "id"), 1:4)
  expect_identical(na_tag(col(res$df, "x")), c(NA, "a", NA, "b"))
  expect_identical(col(res$df, "x")[c(1, 3)], c(1, NA))
  m <- res$meta
  expect_identical(m$label, "Survey")
  expect_identical(m$notes, "Made for the tests")
  expect_identical(m$rows, 4)
  expect_identical(m$columns$x, list(label = "Answer", format = NULL, value_labels = "x", ordered = NULL))
  expect_identical(names(m$value_labels$x), c("One", "Refused"))
  expect_identical(na_tag(unname(m$value_labels$x)), c(NA, "a"))
  expect_length(m$storage, 0)
})

test_that("an Int8, Int16, Int32 or Float32 column holding letters is Float64, its dtype in meta$storage", {
  skip_without_polars()
  p <- tempfile(fileext = ".parquet")
  save_parquet(storage_frame(), p)
  q <- tempfile(fileext = ".dta")
  save_dta(storage_frame(), q)
  for (res in list(read_parquet_pl(p), read_dta_pl(q))) {
    for (n in c("b", "i", "l", "f")) {
      expect_identical(dtype(res$df, n), "Float64")
      expect_identical(na_tag(col(res$df, n)), c(NA, "a", NA, NA))
      expect_identical(col(res$df, n)[c(1, 3, 4)], c(1, NA, 3))
    }
    expect_identical(res$meta$storage, c(b = "Int8", i = "Int16", l = "Int32", f = "Float32"))
  }
})

test_that("letters = FALSE reads the letters as nulls and keeps each dtype", {
  skip_without_polars()
  p <- tempfile(fileext = ".parquet")
  save_parquet(storage_frame(), p)
  res <- read_parquet_pl(p, letters = FALSE)
  expect_identical(vapply(c("b", "i", "l", "f"), function(n) dtype(res$df, n), ""),
                   c(b = "Int8", i = "Int16", l = "Int32", f = "Float32"))
  expect_identical(col(res$df, "b"), c(1L, NA, NA, 3L))
  expect_length(res$meta$storage, 0)
  expect_identical(na_tag(col(read_parquet_pl(survey_parquet(), letters = FALSE)$df, "x")), rep(NA_character_, 4))
})

test_that("a date or timestamp holding letters becomes Stata's number with %td or %tc", {
  skip_without_polars()
  d <- data.frame(day = as.Date("2024-01-01") + 0:2, at = as.POSIXct("2024-01-01", tz = "UTC") + c(0, 1, 2))
  d$day[2] <- tagged_na("c")
  d$at[3] <- tagged_na("d")
  p <- tempfile(fileext = ".parquet")
  save_parquet(d, p)
  res <- read_parquet_pl(p)
  expect_identical(dtype(res$df, "day"), "Float64")
  expect_identical(col(res$df, "day")[c(1, 3)], c(19723, 19725) + 3653)
  expect_identical(na_tag(col(res$df, "day")), c(NA, "c", NA))
  expect_identical(res$meta$columns$day$format, "%td")
  expect_identical(col(res$df, "at")[1:2], 1704067200000 + c(0, 1000) + 3653 * 86400000)
  expect_identical(na_tag(col(res$df, "at")), c(NA, NA, "d"))
  expect_identical(res$meta$columns$at$format, "%tc")
  # Without letters in the rows read, they stay a Date and a Datetime.
  win <- read_parquet_pl(p, n_max = 1)
  expect_identical(dtype(win$df, "day"), "Date")
  expect_match(dtype(win$df, "at"), "^Datetime")
})

# The file TypeScript's saveParquet makes of a categorical holding .a
# to .z: DOUBLE level numbers. A polars Enum cannot hold a letter, so it
# is written here through the native writer with a letters stream.
categorical_with_letters <- function() {
  pl <- polars::pl
  df <- pl$DataFrame(id = 1:4, grade = c("low", NA, "high", NA))$with_columns(
    pl$col("grade")$cast(pl$Enum(c("low", "mid", "high")))
  )
  meta <- datakit:::new_datakit_meta(
    columns = list(id = datakit:::meta_column(),
                   grade = datakit:::meta_column(label = "Grade", value_labels = "grade", ordered = TRUE)),
    value_labels = list(grade = c(low = 1, mid = 2, high = 3, Refused = tagged_na("r"))), rows = 4)
  prep <- datakit:::prepare_pl(df, meta, TRUE, "test")
  letters <- pl$DataFrame(grade = c(NA, ".a", NA, NA))$with_columns(pl$col("grade")$cast(datakit:::letters_dtype()))
  prep$meta$missing <- list("grade", list(nanoarrow::as_nanoarrow_array_stream(letters)))
  p <- tempfile(fileext = ".parquet")
  .Call(datakit:::C_dta_parquet_write_arrow, nanoarrow::as_nanoarrow_array_stream(prep$df), p, prep$meta,
        list("snappy", NULL, NULL, TRUE, "error"))
  p
}

test_that("a categorical holding letters becomes its level numbers, labelled by its set", {
  skip_without_polars()
  p <- categorical_with_letters()
  for (factors in c(FALSE, TRUE)) {
    res <- expect_silent(read_parquet_pl(p, factors = factors))
    expect_identical(dtype(res$df, "grade"), "Float64")
    expect_identical(col(res$df, "grade")[c(1, 3, 4)], c(1, 3, NA))
    expect_identical(na_tag(col(res$df, "grade")), c(NA, "a", NA, NA))
    expect_identical(res$meta$columns$grade, list(label = "Grade", format = NULL, value_labels = "grade", ordered = NULL))
  }
  # Rows without a letter: the Enum, ordered.
  res <- read_parquet_pl(p, n_max = 1)
  expect_match(dtype(res$df, "grade"), "^Enum")
  expect_identical(res$meta$columns$grade$ordered, TRUE)
})

test_that("factors = TRUE makes labelled columns Enums, and warns when it nulls letters", {
  skip_without_polars()
  expect_warning(res <- read_parquet_pl(survey_parquet(), factors = TRUE), "\\.a to \\.z in \"x\" are nulls in its Enum")
  expect_match(dtype(res$df, "x"), "^Enum")
  expect_identical(as.character(col(res$df, "x")), c("One", NA, NA, NA))
  expect_identical(res$df$schema$x$categories, "One")
  # Unlabelled values get levels of their own, in order of value.
  p <- tempfile(fileext = ".parquet")
  save_parquet(data.frame(k = with_labels(c(3L, 1L, 2L), c(One = 1L))), p)
  res <- expect_silent(read_parquet_pl(p, factors = TRUE))
  expect_identical(res$df$schema$k$categories, c("One", "2", "3"))
  expect_identical(as.character(col(res$df, "k")), c("3", "One", "2"))
})

test_that("a .dta Enum comes back an Enum; with letters, its level numbers and its mark kept", {
  skip_without_polars()
  pl <- polars::pl
  df <- pl$DataFrame(g = c("b", "a", NA))$with_columns(pl$col("g")$cast(pl$Enum(c("a", "b", "c"))))
  p <- tempfile(fileext = ".dta")
  save_dta(df, p)
  res <- read_dta_pl(p)
  expect_identical(res$df$schema$g$categories, c("a", "b", "c"))
  expect_identical(as.character(col(res$df, "g")), c("b", "a", NA))
  expect_identical(res$meta$columns$g$ordered, FALSE)
  expect_null(res$meta$characteristics$g)
  # Saved again with a letter in it, as level numbers: read back as them.
  num <- res$df$with_columns(
    pl$when(pl$col("g")$is_null())$then(tagged_na_pl("a"))$otherwise(pl$col("g")$to_physical()$cast(pl$Float64) + 1)$alias("g"))
  q <- tempfile(fileext = ".dta")
  meta <- res$meta
  meta$characteristics$g <- c(dtaparser_categorical = "unordered g")
  save_dta(num, q, meta = meta)
  back <- read_dta_pl(q)
  expect_identical(dtype(back$df, "g"), "Float64")
  expect_identical(na_tag(col(back$df, "g")), c(NA, NA, "a"))
})

test_that("a window reads only its rows, with and without letters", {
  skip_without_polars()
  p <- survey_parquet()
  res <- read_parquet_pl(p, skip = 1, n_max = 2)
  expect_identical(col(res$df, "id"), 2:3)
  expect_identical(na_tag(col(res$df, "x")), c("a", NA))
  expect_identical(res$meta$rows, 2)
  # No letter in the rows read: x keeps its file's type.
  q <- tempfile(fileext = ".parquet")
  save_parquet(storage_frame(), q)
  res <- read_parquet_pl(q, skip = 2)
  expect_identical(dtype(res$df, "b"), "Int8")
  expect_identical(col(res$df, "b"), c(NA, 3L))
  expect_length(res$meta$storage, 0)
  d <- tempfile(fileext = ".dta")
  save_dta(storage_frame(), d)
  expect_identical(dtype(read_dta_pl(d, skip = 2)$df, "i"), "Int16")
  expect_identical(read_dta_pl(d, skip = 9)$df$height, 0L)
})

test_that("col_select takes names, positions and tidyselect", {
  skip_without_polars()
  p <- survey_parquet()
  expect_identical(read_parquet_pl(p, col_select = c("x", "id"))$df$columns, c("x", "id"))
  expect_identical(read_parquet_pl(p, col_select = 2)$df$columns, "x")
  expect_identical(read_parquet_pl(p, col_select = tidyselect::starts_with("i"))$df$columns, "id")
  cols <- "x"
  expect_identical(read_parquet_pl(p, col_select = cols)$df$columns, "x")
  expect_error(read_parquet_pl(p, col_select = "nope"), "nope")
  q <- tempfile(fileext = ".dta")
  save_dta(storage_frame(), q)
  expect_identical(read_dta_pl(q, col_select = c(f, b))$df$columns, c("f", "b"))
  expect_identical(read_dta_pl(q, col_select = "i")$meta$storage, c(i = "Int16"))
})

test_that("a save gives a widened column its storage back when its values fit, and double when not", {
  skip_without_polars()
  pl <- polars::pl
  q <- tempfile(fileext = ".dta")
  save_dta(storage_frame(), q)
  res <- read_dta_pl(q)
  out <- tempfile(fileext = ".dta")
  save_dta(res$df, out, meta = res$meta)
  expect_identical(read_meta(out)$variables$storage, c("byte", "int", "long", "float"))
  back <- read_dta(out)
  expect_identical(na_tag(back$b), c(NA, "a", NA, NA))
  # 1000 does not fit a byte, 0.5 not an int, 0.1 not a float: each is
  # written as double.
  wide <- res$df$with_columns(pl$lit(1000)$alias("b"), pl$lit(0.5)$alias("i"), pl$lit(0.1)$alias("f"))
  save_dta(wide, out2 <- tempfile(fileext = ".dta"), meta = res$meta)
  expect_identical(read_meta(out2)$variables$storage, c("double", "double", "long", "double"))
  # Parquet: the profile's storage, read back as the read gave it.
  pq <- tempfile(fileext = ".parquet")
  save_parquet(res$df, pq, meta = res$meta)
  again <- read_parquet_pl(pq)
  expect_identical(again$meta$storage, res$meta$storage)
  expect_true(again$df$equals(res$df))
  expect_identical(read_parquet_info(pq)$columns$storage, c("byte", "int", "long", "float"))
})

test_that("meta goes back through save_parquet and save_dta", {
  skip_without_polars()
  res <- read_parquet_pl(survey_parquet())
  meta <- res$meta
  meta$characteristics <- list(x = c(note1 = "first"), `_dta` = c(source = "tests"))
  for (save in c("parquet", "dta")) {
    f <- tempfile(fileext = paste0(".", save))
    if (save == "parquet") save_parquet(res$df, f, meta = meta) else save_dta(res$df, f, meta = meta)
    back <- if (save == "parquet") read_parquet_pl(f) else read_dta_pl(f)
    expect_identical(back$meta$label, "Survey")
    expect_identical(back$meta$notes, "Made for the tests")
    expect_identical(back$meta$columns$x$label, "Answer")
    expect_identical(back$meta$columns$x$value_labels, "x")
    expect_identical(back$meta$value_labels$x, meta$value_labels$x)
    expect_identical(back$meta$characteristics$x[["note1"]], "first")
    expect_identical(back$meta$characteristics$`_dta`[["source"]], "tests")
    expect_identical(na_tag(col(back$df, "x")), c(NA, "a", NA, "b"))
  }
})

test_that("missing_letters = FALSE writes .a to .z as .", {
  skip_without_polars()
  res <- read_parquet_pl(survey_parquet())
  p <- tempfile(fileext = ".parquet")
  save_parquet(res$df, p, meta = res$meta, missing_letters = FALSE)
  expect_identical(vctrs::vec_data(read_parquet(p)$x), c(1, NA, NA, NA))
  expect_identical(na_tag(vctrs::vec_data(read_parquet(p)$x)), rep(NA_character_, 4))
  q <- tempfile(fileext = ".dta")
  save_dta(res$df, q, meta = res$meta, missing_letters = FALSE)
  expect_identical(na_tag(vctrs::vec_data(read_dta(q)$x)), rep(NA_character_, 4))
})

test_that("a column named like datakit's temporary letter columns is kept", {
  skip_without_polars()
  p <- tempfile(fileext = ".parquet")
  d <- data.frame(x = c(1, tagged_na("a")), `__datakit_letters__x` = c(10, 20), check.names = FALSE)
  save_parquet(d, p)
  res <- read_parquet_pl(p)
  expect_identical(res$df$columns, c("x", "__datakit_letters__x"))
  expect_identical(col(res$df, "__datakit_letters__x"), c(10, 20))
  expect_identical(na_tag(col(res$df, "x")), c(NA, "a"))
})

test_that("schema_of gives the dtypes of the names asked for, a name like a regex included", {
  skip_without_polars()
  df <- polars::pl$DataFrame(a = 1, "^x$" = 2L, x = 3, b = "s")
  s <- schema_of(df, c("^x$", "b"))
  expect_identical(names(s), c("^x$", "b"))
  expect_identical(vapply(s, format, ""), c("^x$" = "Int32", b = "String"))
  expect_length(schema_of(df, character()), 0)
})

test_that("meta$sort is saved only when the rows are in its order", {
  skip_without_polars()
  pl <- polars::pl
  res <- read_parquet_pl(survey_parquet())
  meta <- res$meta
  meta$sort <- "x"
  # Values, then ., then .a to .z: 1, ., .a, .b.
  sorted <- res$df$sort(pl$col("id")$replace_strict(1:4, c(1L, 3L, 2L, 4L)))
  p <- tempfile(fileext = ".dta")
  expect_silent(save_dta(sorted, p, meta = meta))
  expect_identical(read_dta_pl(p)$meta$sort, "x")
  expect_warning(save_dta(res$df, p, meta = meta), "does not describe the order")
  expect_identical(read_dta_pl(p)$meta$sort, character())
  meta$sort <- c("id", "gone", "x")
  expect_silent(save_parquet(res$df, p2 <- tempfile(fileext = ".parquet"), meta = meta))
  expect_identical(read_parquet_pl(p2)$meta$sort, "id")
})

test_that("save_parquet and save_dta on a tibble mean what they meant", {
  df <- tibble::tibble(id = 1:3, x = c(1, tagged_na("a"), NA))
  p <- tempfile(fileext = ".parquet")
  save_parquet(df, p, "gzip")
  expect_identical(read_parquet_info(p)$compression, "gzip")
  save_parquet(df, p, "zstd", 5, 2, FALSE)
  expect_identical(read_parquet_info(p)$compression, "zstd")
  expect_identical(read_parquet_info(p)$row_groups$rows, c(2, 1))
  expect_identical(na_tag(read_parquet(p)$x), rep(NA_character_, 3))
  expect_invisible(save_parquet(data = df, file = p, missing_letters = TRUE))
  expect_error(save_parquet(df, p, meta = NULL), "meta")
  q <- tempfile(fileext = ".dta")
  save_dta(data = df, file = q)
  expect_identical(na_tag(read_dta(q)$x), c(NA, "a", NA))
  save_dta(df, q)
  expect_error(save_dta(df, q, meta = NULL))
})

test_that("a LazyFrame is an error naming $collect()", {
  skip_without_polars()
  lf <- polars::pl$DataFrame(a = 1)$lazy()
  expect_error(save_parquet(lf, tempfile()), "LazyFrame; call \\$collect\\(\\)")
  expect_error(save_dta(lf, tempfile()), "LazyFrame; call \\$collect\\(\\)")
  expect_error(save_dta(polars::pl$DataFrame(a = 1), tempfile(), meta = list()), "datakit_meta")
  expect_error(save_dta(polars::pl$DataFrame(a = 1), tempfile(), mets = NULL), "mets")
})

test_that("is_missing and is_na say what is.na says, on vectors, expressions and Series", {
  expect_identical(is_missing(c(1, NA, tagged_na("a"), NaN)), c(FALSE, TRUE, TRUE, TRUE))
  expect_identical(is_na(c("a", NA)), c(FALSE, TRUE))
  expect_identical(is_na, is_missing)
  skip_without_polars()
  pl <- polars::pl
  # The rows 1, 5000, .a, .b, .
  df <- pl$DataFrame(x = c(1, 5000, 3, 4, NA))$with_columns(
    pl$when(pl$col("x") == 3)$then(tagged_na_pl("a"))$when(pl$col("x") == 4)$then(tagged_na_pl("b"))$
      otherwise(pl$col("x"))$alias("x"))
  x <- pl$col("x")
  expect_identical(df$filter(x != 1)$height, 3L)
  expect_identical(df$filter((x != 1) & x$is_not_null())$height, 3L)
  expect_identical(df$filter((x != 1) & !is_na(x))$height, 1L)
  expect_identical(df$filter(x > 3000)$height, 3L)
  expect_identical(df$filter((x > 3000) & !is_na(x))$height, 1L)
  expect_identical(col(df$select(is_missing(x)), "x"), c(FALSE, FALSE, TRUE, TRUE, TRUE))
  expect_identical(is_missing(df$get_column("x"))$to_r_vector(), c(FALSE, FALSE, TRUE, TRUE, TRUE))
  expect_identical(is_na(df$get_column("x")$cast(pl$Float32))$to_r_vector(), c(FALSE, FALSE, TRUE, TRUE, TRUE))
  other <- pl$DataFrame(i = c(1L, NA), s = c("nan", NA), d = as.Date(c("2024-01-01", NA)))
  for (n in c("i", "d")) {
    expect_identical(col(other$select(is_missing(pl$col(n))), n), c(FALSE, TRUE))
    expect_identical(is_missing(other$get_column(n))$to_r_vector(), c(FALSE, TRUE))
  }
  # Text: the Series is right; the expression reads "nan" as a NaN.
  expect_identical(is_missing(other$get_column("s"))$to_r_vector(), c(FALSE, TRUE))
  expect_identical(col(other$select(is_missing(pl$col("s"))), "s"), c(TRUE, TRUE))
})

test_that("tagged_na_pl, na_tag_pl and is_tagged_na_pl make and read letters", {
  skip_without_polars()
  pl <- polars::pl
  # R polars reads R's tagged NA as a null; tagged_na_pl() is the letter.
  expect_true(pl$select(pl$lit(tagged_na("a"))$alias("v"))$to_series()$is_null()$to_r_vector())
  expect_false(pl$select(tagged_na_pl("a")$alias("v"))$to_series()$is_null()$to_r_vector())
  df <- pl$DataFrame(x = c(1, NA, 3, 4))$with_columns(
    pl$when(pl$col("x") == 3)$then(tagged_na_pl(".z"))$when(pl$col("x") == 4)$then(tagged_na_pl("a"))$
      otherwise(pl$col("x"))$alias("x"))
  expect_identical(na_tag(col(df, "x")), c(NA, NA, "z", "a"))
  expect_identical(as.character(col(df$select(na_tag_pl("x")), "x")), c(NA, NA, ".z", ".a"))
  expect_identical(as.character(na_tag_pl(df$get_column("x"))$to_r_vector()), c(NA, NA, ".z", ".a"))
  expect_identical(col(df$select(is_tagged_na_pl(pl$col("x"))), "x"), c(FALSE, FALSE, TRUE, TRUE))
  expect_identical(col(df$select(is_tagged_na_pl("x", "a")), "x"), c(FALSE, FALSE, FALSE, TRUE))
  expect_identical(is_tagged_na_pl(df$get_column("x"), ".z")$to_r_vector(), c(FALSE, FALSE, TRUE, FALSE))
  # A plain NaN is not a letter; other dtypes hold none.
  expect_identical(as.character(na_tag_pl(polars::as_polars_series(c(NaN, 1)))$to_r_vector()), c(NA_character_, NA_character_))
  expect_identical(as.character(na_tag_pl(polars::as_polars_series(1:2))$to_r_vector()), c(NA_character_, NA_character_))
  expect_error(tagged_na_pl("ab"), "a letter")
  expect_error(na_tag_pl(1), "column name")
  # Arithmetic keeps the letter.
  expect_identical(na_tag(col(df$select(pl$col("x") * 2), "x")), c(NA, NA, "z", "a"))
})

# Keys 1, .a, .b, . (tagged NaNs and a null).
letter_keys <- function(df) {
  pl <- polars::pl
  df$with_columns(pl$when(pl$col("k") == 2)$then(tagged_na_pl("a"))$when(pl$col("k") == 3)$then(tagged_na_pl("b"))$
                    otherwise(pl$col("k"))$alias("k"))
}

test_that("datakit_by_pl keeps the letters apart in group_by and unique", {
  skip_without_polars()
  pl <- polars::pl
  df <- letter_keys(pl$DataFrame(k = c(1, 2, 3, NA, 2, 3, 1)))
  expect_identical(df$group_by("k")$agg(pl$len())$height, 3L)  # 1, NaN, null
  g <- df$group_by(!!!datakit_by_pl("k"), .maintain_order = TRUE)$agg(pl$len())
  expect_identical(g$columns, c("k", "k_letter", "len"))
  expect_identical(as.character(col(g, "k_letter")), c(NA, ".a", ".b", NA))
  expect_identical(as.numeric(col(g, "len")), c(2, 2, 2, 1))
  u <- df$with_columns(!!!datakit_by_pl("k"))$unique(subset = c("k", "k_letter"), maintain_order = TRUE)
  expect_identical(u$height, 4L)
  expect_identical(df$unique(subset = "k")$height, 3L)
  # Names, suffixes, expressions.
  by <- datakit_by_pl(y = pl$col("k") * 2, "k", .suffix = "_tag")
  expect_identical(vapply(by, function(e) e$meta$output_name(), ""), c("y", "y_tag", "k", "k_tag"))
  expect_identical(as.character(col(df$select(!!!by), "y_tag"))[1:3], c(NA, ".a", ".b"))
  expect_identical(as.character(col(pl$DataFrame(s = c("a", NA))$select(!!!datakit_by_pl("s")), "s_letter")),
                   c(NA_character_, NA_character_))
  expect_error(datakit_by_pl("k", "k"), "two columns named \"k\", \"k_letter\"")
  expect_error(datakit_by_pl(pl$all()), "needs a name for argument 1")
  expect_error(datakit_by_pl(df$get_column("k")), "not a Series")
  expect_error(datakit_by_pl(), "at least one column")
})

test_that("joins on letters: polars matches every letter with every other, datakit_by_pl keeps them apart", {
  skip_without_polars()
  pl <- polars::pl
  left <- letter_keys(pl$DataFrame(id = 1:4, k = c(1, 2, 3, NA)))
  right <- letter_keys(pl$DataFrame(k = c(1, 2, 3, NA), what = c("one", "a", "b", "dot")))
  rows <- function(out) {
    out <- out$sort("id", "what", nulls_last = TRUE)
    list(id = col(out, "id"), what = col(out, "what"))
  }
  # On the key alone, polars 2.1: .a and .b match each other; . matches
  # nothing unless nulls_equal = TRUE.
  expect_identical(rows(left$join(right, on = "k", how = "left")),
                   list(id = c(1L, 2L, 2L, 3L, 3L, 4L), what = c("one", "a", "b", "a", "b", NA)))
  expect_identical(rows(left$join(right, on = "k", how = "inner")),
                   list(id = c(1L, 2L, 2L, 3L, 3L), what = c("one", "a", "b", "a", "b")))
  expect_identical(rows(left$join(right, on = "k", how = "left", nulls_equal = TRUE)),
                   list(id = c(1L, 2L, 2L, 3L, 3L, 4L), what = c("one", "a", "b", "a", "b", "dot")))
  expect_identical(rows(left$join(right, on = "k", how = "inner", nulls_equal = TRUE)),
                   list(id = c(1L, 2L, 2L, 3L, 3L, 4L), what = c("one", "a", "b", "a", "b", "dot")))
  # On the key and its letter column, with nulls_equal = TRUE: each row
  # its own letter, and . only .
  l2 <- left$with_columns(!!!datakit_by_pl("k"))
  r2 <- right$with_columns(!!!datakit_by_pl("k"))
  for (how in c("left", "inner")) {
    expect_identical(rows(l2$join(r2, on = c("k", "k_letter"), how = how, nulls_equal = TRUE)),
                     list(id = 1:4, what = c("one", "a", "b", "dot")), label = how)
  }
  # Without it the letter column, null for every number and for ., keeps
  # only the letters matching.
  expect_identical(rows(l2$join(r2, on = c("k", "k_letter"), how = "left")),
                   list(id = 1:4, what = c(NA, "a", "b", NA)))
  expect_identical(rows(l2$join(r2, on = c("k", "k_letter"), how = "inner")),
                   list(id = 2:3, what = c("a", "b")))
})

test_that("a failing read or write leaks nothing and releases nothing twice", {
  skip_without_polars()
  p <- survey_parquet()
  for (i in 1:3) {
    expect_error(read_parquet_pl(p, col_select = "nope"), "nope")
    expect_error(read_dta_pl(p), "")
    expect_error(save_dta(polars::pl$DataFrame(`1bad` = 1), tempfile(fileext = ".dta")), "not a name Stata can hold")
    expect_error(save_parquet(polars::pl$DataFrame(d = 1)$with_columns(polars::pl$col("d")$cast(polars::pl$Duration("ms"))),
                              tempfile(fileext = ".parquet")), "d")
    gc()
  }
  # The stream of a polars frame is taken by one write only.
  st <- nanoarrow::as_nanoarrow_array_stream(polars::pl$DataFrame(a = 1))
  m <- datakit:::write_meta(datakit:::new_datakit_meta(), "a", character(), list())
  .Call(datakit:::C_dta_dta_write_arrow, st, tempfile(fileext = ".dta"), m, list(TRUE, "error"))
  expect_error(.Call(datakit:::C_dta_dta_write_arrow, st, tempfile(fileext = ".dta"), m, list(TRUE, "error")),
               "this stream was consumed")
})

test_that("a frame's columns outlive its read, its streams and repeated gc()", {
  skip_without_polars()
  p <- survey_parquet()
  frames <- lapply(1:5, function(i) read_parquet_pl(p)$df)
  for (i in 1:5) gc(full = TRUE)
  for (df in frames) expect_identical(na_tag(col(df, "x")), c(NA, "a", NA, "b"))
  x <- frames[[1]]$get_column("x")
  rm(frames)
  for (i in 1:5) gc(full = TRUE)
  expect_identical(na_tag(x$to_r_vector()), c(NA, "a", NA, "b"))
})

test_that("a DECIMAL column is a Decimal", {
  skip_without_polars()
  skip_if_not_installed("arrow")
  p <- tempfile(fileext = ".parquet")
  tab <- arrow::arrow_table(d = arrow::Array$create(c(1.25, 2.5))$cast(arrow::decimal128(10, 2)))
  arrow::write_parquet(tab, p)
  res <- read_parquet_pl(p)
  expect_identical(dtype(res$df, "d"), "Decimal(precision=10, scale=2)")
  expect_identical(format(res$df$get_column("d")$cast(polars::pl$String)$to_r_vector()), c("1.25", "2.50"))
})

fw_setup <- function(lines, data) {
  dir <- tempfile()
  dir.create(dir)
  writeLines(lines, file.path(dir, "s.sas"), useBytes = TRUE)
  writeLines(data, file.path(dir, "s.dat"))
  c(data = file.path(dir, "s.dat"), setup = file.path(dir, "s.sas"))
}

test_that("read_fixed_width_pl reads through the setup, with recodes and labelled letters", {
  skip_without_polars()
  f <- fw_setup(c(
    "PROC FORMAT; VALUE kidsf 0='None' 98='DK' 99='Not ascertained';",
    "DATA; INPUT ID 1-3 KIDS 4-5 NAME $ 6-8;",
    "LABEL KIDS = 'Number of children';",
    "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
    "FORMAT KIDS kidsf.;"
  ), c("001 2ann", "00298bob", "00399   ", "004 0cy "))
  res <- read_fixed_width_pl(f[["data"]], f[["setup"]], recodes = "tagged")
  expect_identical(res$df$columns, c("ID", "KIDS", "NAME"))
  expect_identical(dtype(res$df, "KIDS"), "Float64")
  expect_identical(res$meta$storage[["KIDS"]], "Int8")
  expect_identical(na_tag(col(res$df, "KIDS")), c(NA, "a", "b", NA))
  expect_identical(col(res$df, "KIDS")[c(1, 4)], c(2, 0))
  expect_identical(res$meta$columns$KIDS$label, "Number of children")
  set <- res$meta$value_labels[[res$meta$columns$KIDS$value_labels]]
  expect_identical(names(set), c("None", "DK", "Not ascertained"))
  expect_identical(na_tag(unname(set)), c(NA, "a", "b"))
  expect_identical(col(res$df, "NAME"), c("ann", "bob", "", "cy"))
  setup <- read_fixed_width_pl(f[["data"]], f[["setup"]])
  expect_identical(col(setup$df, "KIDS"), c(2L, NA, NA, 0L))
  none <- read_fixed_width_pl(f[["data"]], f[["setup"]], recodes = "none", col_select = "KIDS", skip = 1, n_max = 2)
  expect_identical(col(none$df, "KIDS"), c(98L, 99L))
  fac <- read_fixed_width_pl(f[["data"]], f[["setup"]], recodes = "none", factors = TRUE)
  expect_identical(as.character(col(fac$df, "KIDS")), c("2", "DK", "Not ascertained", "None"))
  expect_identical(na_tag(col(read_fixed_width_pl(f[["data"]], f[["setup"]], recodes = "tagged",
                                                 letters = FALSE)$df, "KIDS")), rep(NA_character_, 4))
})

test_that("read_fixed_width_pl warns once for the setup, and release 118 cuts long labels", {
  skip_without_polars()
  ascii <- strrep("a", 200)
  accented <- strrep("é", 200)
  f <- fw_setup(enc2utf8(c(
    "DATA; INPUT A 1 B 2 C 3;",
    paste0("LABEL A = '", ascii, "' B = '", accented, "';"),
    "RUN;",
    "PROC PRINT; RUN;"
  )), c("123", "456"))
  w <- NULL
  res <- withCallingHandlers(
    read_fixed_width_pl(f[["data"]], f[["setup"]]),
    datakit_fixed_width_warning = function(cnd) {
      w <<- cnd
      invokeRestart("muffleWarning")
    }
  )
  expect_s3_class(w, "datakit_fixed_width_warning")
  expect_true(any(grepl("the label of B is cut to 320 bytes", w$messages)))
  expect_identical(res$meta$columns$A$label, ascii)
  expect_identical(res$meta$columns$B$label, strrep("é", 160))
  expect_identical(col(res$df, "C"), c(3L, 6L))
})

test_that("a datakit_meta prints its fields as Python's Meta does, without storage", {
  skip_without_polars()
  p <- tempfile(fileext = ".parquet")
  save_parquet(storage_frame(), p)
  out <- format(read_parquet_pl(p)$meta)
  expect_identical(out[[1]], "<datakit_meta>")
  expect_true("rows: 4" %in% out)
  expect_true("  b: label = NULL, format = NULL, value_labels = NULL, ordered = NULL" %in% out)
  expect_false(any(grepl("storage|Int8", out)))
  expect_output(print(read_parquet_pl(survey_parquet())$meta), "x: 1 = \"One\", .a = \"Refused\"", fixed = TRUE)
})
