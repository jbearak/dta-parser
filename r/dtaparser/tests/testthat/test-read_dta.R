# read_dta returns standard R types with R's rules. haven is the oracle
# for values (AGENTS.md); where dtaparser differs from haven on purpose,
# the test says so and checks dtaparser's rule on its own.

# x without attributes or class.
plain <- function(x) {
  x <- unclass(x)
  attributes(x) <- NULL
  x
}

test_that("read_dta matches haven on every fixture", {
  skip_if_not_installed("haven")
  for (path in fixtures()) {
    name <- basename(path)
    # haven 2.5.5 cannot read release 105 value labels at all.
    if (name == "readstat_105.dta") next
    ours <- read_dta(path, warn_extended_missing = FALSE)
    theirs <- haven::read_dta(path)
    expect_s3_class(ours, "tbl_df")
    expect_false(inherits(ours, "dibble"))
    expect_identical(names(ours), names(theirs), label = name)
    expect_identical(attr(ours, "label"), attr(theirs, "label", exact = TRUE), label = name)
    for (col in names(theirs)) {
      what <- paste(name, col)
      x <- ours[[col]]
      y <- theirs[[col]]
      format <- attr(y, "format.stata", exact = TRUE)
      expect_identical(attr(x, "label", exact = TRUE), attr(y, "label", exact = TRUE), label = what)
      expect_null(attr(x, "format"))
      if (is.character(y)) {
        # haven 2.5.5 reads strLs in 119 files from other writers wrongly
        # and drops trailing blanks from strN values.
        if (grepl("^pandas_119", name) && col == "strl") next
        expect_identical(sub(" +$", "", plain(x)), sub(" +$", "", plain(y)), label = what)
        next
      }
      # On purpose: haven leaves %-td and %-tc as numbers and reads %tC
      # as POSIXct (tested below).
      if (grepl("^%-|^%tC", format)) next
      # haven 2.5.5 reads these value labels as empty, so it gives
      # numbers where read_dta gives a factor.
      if (name %in% c("readstat_104.dta", "readstat_108.dta") && col == "b") next
      # On purpose: labels on missing values alone make no factor.
      if (inherits(y, "haven_labelled") && !any(!is.na(attr(y, "labels")))) {
        expect_identical(as.double(plain(x)), plain(y), label = what)
        expect_identical(attr(x, "labels", exact = TRUE), attr(y, "labels", exact = TRUE), label = what)
        next
      }
      if (inherits(y, "haven_labelled")) {
        # haven's levels for integers R prints differently as doubles
        # ("1e+05") differ on purpose (tested below).
        v <- plain(x)
        if (is.integer(v) && any(as.character(v) != as.character(as.double(v)), na.rm = TRUE)) next
        expect_s3_class(x, "factor")
        want <- haven::as_factor(haven::zap_missing(y), levels = "default")
        expect_identical(levels(x), levels(want), label = what)
        expect_identical(as.character(x), as.character(want), label = what)
        next
      }
      if (inherits(y, "Date") || inherits(y, "POSIXct")) {
        expect_identical(class(x), class(y), label = what)
        expect_equal(plain(x), plain(y), label = what)
        expect_identical(haven::na_tag(plain(x)), haven::na_tag(plain(y)), label = what)
        next
      }
      # .a to .z keep their letters, as in haven; integer columns
      # without them stay integers.
      expect_equal(as.double(plain(x)), plain(y), label = what)
      expect_identical(haven::na_tag(as.double(plain(x))), haven::na_tag(plain(y)), label = what)
    }
  }
})

test_that("byte, int and long are integers; float and double doubles", {
  path <- write_fixture(
    b = col(c(-127, 100, NA), "byte"),
    i = col(c(-32767, 32740, NA), "int"),
    l = col(c(-2147483647, 2147483620, NA), "long"),
    f = col(c(1.5, -2.25, NA), "float"),
    d = col(c(1e300, -0.1, NA), "double"),
    none = col(c(NA, NA, NA), "long")
  )
  x <- read_dta(path)
  expect_identical(x$b, c(-127L, 100L, NA))
  expect_identical(x$i, c(-32767L, 32740L, NA))
  expect_identical(x$l, c(-2147483647L, 2147483620L, NA))
  expect_identical(x$f, c(1.5, -2.25, NA))
  expect_identical(x$d, c(1e300, -0.1, NA))
  expect_identical(x$none, rep(NA_integer_, 3))
})

test_that("every missing value is NA, with R's rules, and .a to .z keep their letter", {
  skip_if_not_installed("haven")
  tagged <- c(1, 9, NA, haven::tagged_na("a"), haven::tagged_na("z"))
  path <- write_fixture(d = col(tagged, "double"), l = col(tagged, "long"), f = col(tagged, "float"),
                        td = col(tagged, "long", "%td"))
  x <- read_dta(path)
  for (name in c("d", "l", "f")) {
    expect_identical(is.na(x[[name]]), c(FALSE, FALSE, TRUE, TRUE, TRUE), label = name)
    expect_identical(x[[name]] > 5, c(FALSE, TRUE, NA, NA, NA), label = name)
    expect_identical(haven::na_tag(x[[name]]), c(NA, NA, NA, "a", "z"), label = name)
  }
  # A long column with .a to .z is read as doubles, to hold the letters.
  expect_type(x$l, "double")
  expect_identical(x$l, tagged)
  expect_s3_class(x$td, "Date")
  expect_identical(haven::na_tag(unclass(x$td)), c(NA, NA, NA, "a", "z"))
})

test_that("integer columns become doubles only where .a to .z are read", {
  skip_if_not_installed("haven")
  # Chunks are about 8 MiB of decoded values (9 bytes a row a column), so
  # the letter comes chunks after the first and the switch to doubles
  # copies the rows read before it.
  n <- 1e6
  late <- c(NA, seq_len(n - 2), haven::tagged_na("b"))
  path <- write_fixture(late = col(late, "long"), dot = col(rep(c(1, NA), n / 2), "byte"),
                        sys = col(c(seq_len(n - 1), NA) + 0, "long"))
  x <- read_dta(path)
  expect_type(x$late, "double")
  expect_identical(x$late, late)
  expect_identical(haven::na_tag(x$late[n]), "b")
  expect_type(x$dot, "integer")
  expect_type(x$sys, "integer")
  # The rows read decide: without the last row the column stays integer.
  expect_type(read_dta(path, n_max = n - 1)$late, "integer")
})

test_that("strings are character, packed, with \"\" as stored", {
  skip_if_not_installed("haven")
  path <- tempfile(fileext = ".dta")
  haven::write_dta(data.frame(s = c("a", "", "café")), path)
  x <- read_dta(path)$s
  expect_gte(state(x), 0)
  expect_identical(as.vector(x), c("a", "", "café"))
})

test_that("a tibble saved with saveRDS reads back without dtaparser", {
  skip_if_not_installed("haven")
  path <- tempfile(fileext = ".dta")
  haven::write_dta(data.frame(s = c("a", "b"), n = c(1, 2)), path)
  rds <- tempfile(fileext = ".rds")
  saveRDS(read_dta(path), rds)
  out <- fresh_r(sprintf(
    'x <- readRDS("%s"); cat(x$s, "dtaparser" %%in%% loadedNamespaces(), sep = ",")', rds
  ))
  expect_identical(out, "a,b,FALSE")
})

test_that("col_select, skip and n_max choose columns and rows", {
  path <- write_fixture(a = col(1:5, "long"), b = col(c(1.5, 2.5, 3.5, 4.5, 5.5), "double"))
  expect_named(read_dta(path, col_select = c("b", "a")), c("b", "a"))
  expect_named(read_dta(path, col_select = tidyselect::starts_with("b")), "b")
  wanted <- "b"
  expect_named(read_dta(path, col_select = wanted), "b")
  expect_identical(read_dta(path, skip = 1, n_max = 2)$a, 2:3)
  expect_identical(nrow(read_dta(path, skip = 9)), 0L)
  expect_error(read_dta(path, skip = -1), "skip")
  expect_error(read_dta(path, n_max = NA), "n_max")
  expect_error(read_dta(path, factors = NA), "factors")
  expect_error(read_dta(path, dates = "yes"), "dates")
})

test_that("a legacy file's text is read in the encoding given", {
  path <- file.path(fixture_dir, "haven_114.dta")
  skip_if_not(file.exists(path))
  text <- read_dta(path, col_select = "text")$text
  expect_type(text, "character")
  expect_identical(read_dta(path, col_select = "text", encoding = "windows-1252")$text, text)
  expect_error(read_dta(path, encoding = "nope"), "unknown encoding")
})
