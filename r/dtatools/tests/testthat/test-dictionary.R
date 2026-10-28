# read_dta stores a string column with few distinct values as a
# dictionary: each distinct value once, and a code per row, so R makes
# one string per distinct value. Helpers are in helper-packed.R.

dict_file <- function(s = c("alpha", "", "café", "alpha", "", "z"), n = seq_along(s)) {
  path <- tempfile(fileext = ".dta")
  save_dta(dibble(n = n, s = s), path)
  path
}

dict_expected <- c("alpha", "", "café", "alpha", "", "z")

test_that("a dictionary column holds the same strings", {
  d <- read_dta(dict_file())
  expect_true(has_dictionary(d$s))
  expect_identical(state(d$s), 0)
  expect_identical(length(d$s), 6L)
  expect_identical(d$s[[3]], "café")
  expect_identical(Encoding(d$s[[3]]), "UTF-8")
  expect_identical(attr(d$s, "format"), "%-5s")
  expect_identical(values(d$s), dict_expected)
})

test_that("every fixture reads the same with and without dictionaries", {
  for (path in fixtures()) {
    dict <- read_dta(path)
    plain <- read_plain(path)
    for (name in names(dict)) {
      if (is.character(dict[[name]])) {
        expect_identical(values(dict[[name]]), values(plain[[name]]), label = paste(basename(path), name))
        expect_identical(attributes(dict[[name]]), attributes(plain[[name]]))
      }
    }
  }
})

test_that("zero rows and empty strings", {
  empty <- read_dta(dict_file(character(), integer()))
  expect_true(has_dictionary(empty$s))
  expect_identical(values(empty$s), character())
  blank <- read_dta(dict_file(rep("", 4)))
  expect_true(has_dictionary(blank$s))
  expect_identical(values(blank$s), rep("", 4))
  expect_identical(blank$s[[2]], "")
  expect_identical(state(blank$s), 1)
})

test_that("rows with one value share one string", {
  x <- read_dta(dict_file())$s
  expect_identical(x[[1]], "alpha")
  expect_identical(state(x), 1)
  expect_identical(x[[4]], "alpha")
  expect_identical(state(x), 1)
})

test_that("mostly distinct columns give the dictionary up", {
  distinct <- sprintf("v%03d", 1:100)
  x <- read_with(dict_file(distinct), window = 10)$s
  expect_false(has_dictionary(x))
  expect_identical(values(x), distinct)

  # Few values, then distinct ones: given up partway through the column.
  late <- c(rep(c("a", "b"), 25), sprintf("w%03d", 1:60))
  x <- read_with(dict_file(late), window = 10)$s
  expect_false(has_dictionary(x))
  expect_identical(values(x), late)

  # Under the window, the same column keeps its dictionary.
  expect_true(has_dictionary(read_with(dict_file(late), window = 1000)$s))

  # Past the limit on distinct values.
  x <- read_with(dict_file(), limit = 3)$s
  expect_false(has_dictionary(x))
  expect_identical(values(x), dict_expected)
})

test_that("assignment and copies", {
  x <- read_dta(dict_file())$s
  y <- x
  y[1] <- "q"
  expect_identical(values(y), c("q", dict_expected[-1]))
  expect_identical(state(x), 0)
  expect_identical(values(x), dict_expected)

  x[4] <- NA
  expect_identical(state(x), -1)
  expect_identical(values(x), c("alpha", "", "café", NA, "", "z"))
  expect_true(anyNA(x))
})

test_that("making every string after some, under gctorture", {
  x <- read_dta(dict_file(rep(dict_expected, 20)))$s
  first <- x[[3]]
  gctorture(TRUE)
  all <- as.character(sort(x))
  gctorture(FALSE)
  expect_identical(first, "café")
  expect_identical(all, sort(rep(dict_expected, 20)))
  expect_identical(values(x), rep(dict_expected, 20))
})

test_that("saveRDS writes a plain character vector", {
  x <- read_dta(dict_file())$s
  path <- tempfile(fileext = ".rds")
  saveRDS(x, path)
  y <- readRDS(path)
  expect_identical(state(y), -2)
  expect_identical(y, x)
})

test_that("dplyr gives the same results on dictionary and plain columns", {
  skip_if_not_installed("dplyr")
  path <- dict_file(rep(dict_expected, 3))
  run <- function(d) {
    d |>
      dplyr::filter(n > 2) |>
      dplyr::mutate(t = paste0(s, "!")) |>
      dplyr::group_by(s) |>
      dplyr::summarise(k = sum(n), t = dplyr::first(t), .groups = "drop")
  }
  dict <- read_dta(path)
  expect_true(has_dictionary(dict$s))
  expect_identical(run(dict), run(read_plain(path)))
})

test_that("tab, dta_group_id and is_missing agree on dictionary and plain columns", {
  s <- c("b", "", "a", "café", "b", "", "Z", "a", "b")
  n <- c(3, 1, NA, 2, 3, 1, 1, NA, 2)
  path <- tempfile(fileext = ".dta")
  save_dta(dibble(s = s, n = n), path)
  dict <- read_dta(path)
  plain <- read_plain(path)
  expect_true(has_dictionary(dict$s))
  for (missing in c(FALSE, TRUE)) {
    expect_identical(tab(dict$s, missing = missing), tab(plain$s, missing = missing))
    expect_identical(dta_group_id(dict$s, dict$n, missing = missing), dta_group_id(plain$s, plain$n, missing = missing))
    expect_identical(dta_group_tag(dict, missing = missing), dta_group_tag(plain, missing = missing))
  }
  expect_identical(is_missing(dict$s), is_missing(plain$s))
  # The codes stay with the column, unchanged and still packed.
  expect_identical(state(dict$s), 5)
  expect_identical(values(dict$s), s)
})

test_that("changing what dictionary() returns leaves the column alone", {
  x <- read_dta(dict_file())$s
  y <- x
  dict <- dtatools:::dictionary(x)
  dict$values[1] <- "changed"
  dict$codes[1] <- 99L
  expect_identical(values(x), dict_expected)
  expect_identical(values(y), dict_expected)
  expect_identical(dtatools:::dictionary(x)$codes[1], 0L)
})

test_that("tab sorts dictionary values by locale, as table() does", {
  old <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", old))
  ok <- suppressWarnings(Sys.setlocale("LC_COLLATE", "en_US.UTF-8"))
  skip_if(!nzchar(ok), "no en_US.UTF-8 collation")
  s <- c("b", "B", "a", "Z", "a")
  path <- tempfile(fileext = ".dta")
  save_dta(dibble(s = s), path)
  dict <- read_dta(path)$s
  expect_true(has_dictionary(dict))
  # Locale order differs from byte order here (Z sorts before a in bytes).
  expect_false(identical(sort(unique(s)), sort(unique(s), method = "radix")))
  expect_identical(tab(dict), tab(read_plain(path)$s))
  expect_identical(dta_group_id(dict), dta_group_id(read_plain(path)$s))
})

test_that("tab, dta_group_id and is_missing on zero rows and empty strings", {
  for (s in list(character(), rep("", 3))) {
    path <- tempfile(fileext = ".dta")
    save_dta(dibble(s = s), path)
    dict <- read_dta(path)$s
    plain <- read_plain(path)$s
    expect_true(has_dictionary(dict))
    for (missing in c(FALSE, TRUE)) {
      expect_identical(tab(dict, missing = missing), tab(plain, missing = missing))
      expect_identical(dta_group_id(dict, missing = missing), dta_group_id(plain, missing = missing))
    }
    expect_identical(is_missing(dict), is_missing(plain))
  }
})
