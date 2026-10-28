# read_dta returns string columns packed: their text stays as the bytes
# read, and R strings are made only when used (src/strings.c).

# -2: not a packed column; -1: packed once, now made; else the number of
# strings made so far.
state <- function(x) .Call(dtatools:::C_dta_packed_state, x)
# The values without read_dta's attributes.
values <- function(x) as.vector(x)

packed_file <- function(s = c("alpha", "", "café", "id4", "alpha", "z"), n = seq_along(s)) {
  path <- tempfile(fileext = ".dta")
  save_dta(dibble(n = n, s = s), path)
  path
}

expected <- c("alpha", "", "café", "id4", "alpha", "z")

test_that("a packed column holds the same strings", {
  d <- read_dta(packed_file())
  expect_identical(state(d$s), 0)
  expect_identical(length(d$s), 6L)
  expect_identical(values(d$s), expected)
  expect_identical(Encoding(d$s[[3]]), "UTF-8")
  expect_identical(attr(d$s, "format"), "%-5s")
  # as.vector() worked on a packed copy; only d$s[[3]] was made here.
  expect_identical(state(d$s), 1)
})

test_that("slicing makes only the strings it keeps and leaves the source packed", {
  d <- read_dta(packed_file())
  expect_identical(values(head(d, 2)$s), c("alpha", ""))
  expect_identical(state(d$s), 2)
  expect_identical(values(d[d$n > 4, ]$s), c("alpha", "z"))
  expect_identical(values(vctrs::vec_slice(d$s, 6L)), "z")
  expect_identical(state(d$s), 4)
  skip_if_not_installed("dplyr")
  expect_identical(values(dplyr::filter(d, n == 3)$s), "café")
  expect_identical(state(d$s), 5)
})

test_that("a made column answers like a plain one", {
  d <- read_dta(packed_file())
  x <- d$s
  expect_false(anyNA(x))
  x[1] <- NA
  expect_identical(state(x), -1)
  expect_identical(length(x), 6L)
  expect_identical(values(x[1:2]), c(NA, ""))
  expect_true(anyNA(x))
  expect_identical(is.na(x), c(TRUE, rep(FALSE, 5)))
  expect_identical(values(d$s), expected)
})

test_that("copies are independent", {
  d <- read_dta(packed_file())
  x <- d$s
  y <- x
  y[1] <- "a"
  expect_identical(values(y[1:2]), c("a", ""))
  expect_identical(state(x), 0)
  expect_identical(values(x), expected)

  x[1] <- "alpha"  # an assignment makes x
  expect_identical(state(x), -1)
  z <- x
  attr(z, "label") <- "shared"
  z[2] <- "b"
  expect_identical(values(x), expected)
  expect_null(attr(x, "label"))

  p <- read_dta(packed_file())$s
  q <- p
  attr(q, "label") <- "copy"
  expect_identical(state(p), 0)
  expect_identical(state(q), 0)
  expect_identical(attr(q, "label"), "copy")
  expect_identical(values(q), expected)
})

test_that("saveRDS writes a plain character vector", {
  x <- read_dta(packed_file())$s
  path <- tempfile(fileext = ".rds")
  saveRDS(x, path)
  y <- readRDS(path)
  expect_identical(state(y), -2)
  expect_identical(y, x)
})

test_that("dplyr gives the same results on packed and plain columns", {
  skip_if_not_installed("dplyr")
  d <- read_dta(packed_file())
  plain <- d
  plain$s <- paste0(d$s, "")
  attributes(plain$s) <- attributes(d$s)
  expect_identical(state(plain$s), -2)
  run <- function(x) {
    x |>
      dplyr::mutate(t = paste0(s, "!")) |>
      dplyr::group_by(s) |>
      dplyr::summarise(k = sum(n), t = dplyr::first(t), .groups = "drop")
  }
  expect_identical(run(read_dta(packed_file())), run(plain))
})

test_that("zero rows and garbage collection", {
  empty <- read_dta(packed_file(character(), integer()))
  expect_identical(state(empty$s), 0)
  expect_identical(values(empty$s), character())

  x <- read_dta(packed_file(rep(expected, 20)))$s
  gctorture(TRUE)
  first <- x[[3]]
  again <- x[[3]]
  all <- as.character(sort(x))
  gctorture(FALSE)
  expect_identical(first, "café")
  expect_identical(again, "café")
  expect_identical(all, sort(rep(expected, 20)))
})
