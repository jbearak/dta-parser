# d[i, name, by = g] := value on data frames, under R's rules (ADR 0027).

test_that(":= makes a column on the rows i selects; NA selects no row", {
  d <- tibble::tibble(age = c(25L, 41L, NA, 37L), g = c(1, 1, 2, 2))
  d[age > 35, older] := TRUE
  expect_identical(d$older, c(NA, TRUE, NA, TRUE))
  d[c(2, 4), k] := "x"
  expect_identical(d$k, c(NA, "x", NA, "x"))
  d[, n, by = g] := .N
  expect_identical(d$n, c(2L, 2L, 2L, 2L))
  d[age > 0, nth, by = g] := seq_len(.N)
  expect_identical(d$nth, c(1L, 2L, NA, 1L))
  d[, m, by = g] := mean(age, na.rm = TRUE)
  expect_identical(d$m, c(33, 33, 37, 37))
  d[, inf] := 1 / (age - age)
  expect_identical(d$inf, c(Inf, Inf, NA, Inf))
  expect_s3_class(d, "tbl_df")
  df <- data.frame(x = 1:3)
  df[x > 1, y] := x * 2
  expect_identical(df, data.frame(x = 1:3, y = c(NA, 4, 6)))
  l <- list(d = df)
  l$d[, z] := 0
  expect_named(l$d, c("x", "y", "z"))
})

test_that("a column widens only as far as its new values need, keeping its attributes", {
  d <- tibble::tibble(x = structure(c(1L, 2L), label = "X", labels = c(one = 1)), b = c(NA, NA))
  d[1, x] := 5
  expect_identical(d$x, structure(c(5L, 2L), label = "X", labels = c(one = 1)))
  d[1, x] := 0.5
  expect_identical(d$x, structure(c(0.5, 2), label = "X", labels = c(one = 1)))
  d[2, b] := 1
  expect_identical(d$b, c(NA, 1L))
  d[1, b] := 2.5
  expect_identical(d$b, c(2.5, 1))
  # .a to .z keep their letter, which only a double holds.
  d <- tibble::tibble(x = c(1L, 2L))
  d[2, x] := tagged_na("d")
  expect_identical(na_tag(d$x), c(NA, "d"))
  d <- tibble::tibble(x = c(1L, 2L))
  d[1, x] := NaN
  expect_identical(d$x, c(NaN, 2))
})

test_that("a factor column takes labels, never codes", {
  d <- tibble::tibble(region = factor(c("North", "South", "East"), levels = c("North", "South", "East")))
  d[region == "East", region] := "South"
  expect_identical(as.character(d$region), c("North", "South", "South"))
  expect_identical(levels(d$region), c("North", "South", "East"))
  # A factor value matches by label, whatever its codes.
  d[1, region] := factor("East")
  expect_identical(as.character(d$region), c("East", "South", "South"))
  d[1, region] := NA
  expect_identical(as.character(d$region), c(NA, "South", "South"))
  expect_error(d[1, region] := "Sout", "\"Sout\" is not a level of region")
  expect_error(d[1, region] := 2, "region is a factor; give a label")
  d[, copy] := region
  expect_identical(d$copy, d$region)
})

test_that("i picking no rows leaves an existing column alone", {
  d <- tibble::tibble(x = 1:2)
  d[x > 5, x] := stop("not evaluated")
  expect_identical(d$x, 1:2)
  d[x > 5, y] := "a"
  expect_identical(d$y, c(NA_character_, NA_character_))
  d[NULL, x] := 9L
  expect_identical(d$x, 1:2)
})

test_that("NULL drops a column, and other misuse is an error", {
  d <- tibble::tibble(x = 1:2, g = c(1, 2))
  d[, x] := NULL
  expect_named(d, "g")
  expect_error(d[1, g] := NULL, "NULL drops the whole column")
  expect_error(d[, g, by = g] := 1, "cannot change g, a by column")
  expect_error(d[, y, by = "h"] := 1, "no column h to group by")
  expect_error(d[1] := 1, "write d\\[i, name\\] := value")
  expect_error(y := 1, "write d\\[i, name\\] := value")
  v <- 1:2
  expect_error(v[1, x] := 1, "needs a data frame")
  dt <- structure(list(a = 1), class = c("data.table", "data.frame"), row.names = 1L)
  expect_error(dt[1, a] := 2, "use its own")
})
