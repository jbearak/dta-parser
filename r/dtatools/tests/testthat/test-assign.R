test_that(":= makes a column on the rows i selects, by Stata's comparisons", {
  d <- dibble(age = c(25, 41, NA, .a), s = c("p", "q", "r", "s"))
  out <- d[age > 35, older := 1]
  expect_identical(as.character(out$older), c(".", "1", "1", "1"))
  expect_identical(attr(out$older, "storage"), "double")
  expect_false("older" %in% names(d))
  out <- d[age < 30, t := "young"]
  expect_identical(out$t, c("young", "", "", ""))
  out <- d[c(TRUE, NA, FALSE, TRUE), flag := TRUE]
  expect_identical(as.character(out$flag), c("1", ".", ".", "1"))
  expect_identical(attr(out$flag, "storage"), "byte")
  expect_identical(as.character(d[c(2, 4), k := 7]$k), c(".", "7", ".", "7"))
  expect_identical(as.character(d[-1, k := 7]$k), c(".", "7", "7", "7"))
  expect_identical(as.character(d[dta_num(c(0, 2, NA, 0)), k := 7]$k), c(".", "7", "7", "."))
  expect_identical(as.character(d[, k := age]$k), c("25", "41", ".", ".a"))
})

test_that(":= into an existing column keeps its labels and widens its storage", {
  d <- dibble(x = dta_num(c(1, 2, .d), storage = "byte", label = "X", labels = c(One = 1, DK = .d)))
  out <- d[x == .d, x := .r]
  expect_identical(as.character(out$x), c("1", "2", ".r"))
  expect_identical(attr(out$x, "labels"), attr(d$x, "labels"))
  expect_identical(attr(out$x, "label"), "X")
  expect_identical(attr(out$x, "storage"), "byte")
  expect_identical(attr(d[1, x := 100]$x, "storage"), "byte")
  expect_identical(attr(d[1, x := 101]$x, "storage"), "int")
  expect_identical(attr(d[1, x := -40000]$x, "storage"), "long")
  expect_identical(attr(d[1, x := 3e9]$x, "storage"), "double")
  expect_identical(attr(d[1, x := 0.5]$x, "storage"), "double")
  f <- dibble(x = dta_num(1, storage = "float"))
  expect_identical(attr(f[, x := 0.1]$x, "storage"), "float")
  expect_identical(attr(f[, x := 1e300]$x, "storage"), "double")
  expect_error(d[, x := "a"], "cannot put strings into numeric column x")
  expect_error(dibble(s = "a")[, s := 1], "cannot put numbers into string column s")
  path <- tempfile(fileext = ".dta")
  save_dta(d[1, x := 0.5], path)
  expect_identical(as.character(read_dta(path)$x), c("0.5", "2", ".d"))
})

test_that(":= with by works within groups, each missing code its own", {
  d <- dibble(g = c(.a, 1, .b, 1, .a, NA), x = c(1, 2, 3, 4, 5, 6))
  out <- d[, n := .N, by = g]
  expect_identical(as.character(out$n), c("2", "2", "1", "2", "2", "1"))
  out <- d[x > 1, first := x[1], by = .(g)]
  expect_identical(as.character(out$first), c(".", "2", "3", "2", "5", "6"))
  out <- d[, idx := seq_len(.N), by = "g"]
  expect_identical(as.character(out$idx), c("1", "1", "1", "2", "2", "1"))
  by <- "g"
  expect_identical(d[, n := .N, by = by]$n, d[, n := .N, by = g]$n)
  expect_error(d[, g := 1, by = g], "cannot change g")
  expect_error(d[1, by = g], "by needs :=")
})

test_that(":= takes several columns in turn, names in strings or variables, and NULL", {
  d <- dibble(x = c(1, 2), y = c(3, 4))
  out <- d[, `:=`(a = x * 10, b = a + 1)]
  expect_identical(as.character(out$b), c("11", "21"))
  nm <- "z"
  expect_identical(names(d[, (nm) := 0]), c("x", "y", "z"))
  expect_identical(names(d[, "z" := 0]), c("x", "y", "z"))
  expect_identical(names(d[, y := NULL]), "x")
  expect_error(d[1, y := NULL], "no i or by")
  gone <- NULL
  expect_identical(names(d[, y := gone]), "x")
  expect_error(d[, y := NULL, by = x], "NULL drops the whole column")
  expect_identical(as.character(d[, `:=`(z = 1, z = z + 1)]$z), c("2", "2"))
  expect_identical(names(d[, `:=`(z = 1, z = NULL)]), c("x", "y"))
  expect_error(d[, a := 1:3], "`a`.*size 3.*size 2")
  expect_error(d[, `:=`(1)], "name := value")
})

test_that(":= keeps the dibble's attributes and ends the sort order at a changed key", {
  d <- dibble(a = c(1, 2), b = c(3, 4), c = c(5, 6))
  attr(d, "label") <- "Data"
  attr(d, "notes") <- "note"
  attr(d, "sort_order") <- c("a", "b")
  out <- d[, c := 0]
  expect_s3_class(out, "dibble")
  expect_identical(attr(out, "label"), "Data")
  expect_identical(attr(out, "notes"), "note")
  expect_identical(attr(out, "sort_order"), c("a", "b"))
  expect_identical(attr(d[, b := 0], "sort_order"), "a")
  expect_null(attr(d[, a := 0], "sort_order"))
})

test_that("[ without := is tibble's", {
  d <- dibble(x = c(1, .a), s = c("p", "q"))
  expect_identical(d[2, ]$x == .a, TRUE)
  expect_identical(names(d["s"]), "s")
  expect_identical(d[, "s", drop = TRUE], c("p", "q"))
  j <- "x"
  expect_identical(names(d[, j]), "x")
})

test_that(":= on no rows still gives the value's type, with or without by", {
  d <- dibble(g = c(1, 2), s = c("a", "b"), x = dta_num(c(1, 2), storage = "byte"))
  for (out in list(d[g < 0, t := "z"], d[g < 0, t := "z", by = g])) {
    expect_identical(out$t, c("", ""))
  }
  expect_identical(d[g < 0, s := "z", by = g]$s, c("a", "b"))
  expect_identical(d[g < 0, x := 0.5, by = g]$x, d$x)
  expect_identical(d[g < 0, s := 1, by = g], d)
})

test_that(":= stores only what Stata holds", {
  d <- dibble(x = c(1, 2), s = c("a", "b"))
  out <- d[, `:=`(x = c(Inf, .a), y = c(NaN, -Inf), s = NA_character_, t = c("u", NA))]
  expect_identical(as.character(out$x), c(".", ".a"))
  expect_identical(as.character(out$y), c(".", "."))
  expect_identical(out$s, c("", ""))
  expect_identical(out$t, c("u", ""))
  path <- tempfile(fileext = ".dta")
  save_dta(out, path)
  back <- read_dta(path)
  expect_identical(as.character(back$x), c(".", ".a"))
  expect_identical(as.vector(back$t), c("u", ""))
})

test_that(":= values see the selected rows, .data, .N and the caller's variables", {
  d <- dibble(g = c("p", "q", "p", "p"), x = c(1, 2, 3, 4))
  out <- d[x > 1, n := .N, by = g]
  expect_identical(as.character(out$n), c(".", "1", "2", "2"))
  out <- d[x > 1, k := seq_len(.N), by = g]
  expect_identical(as.character(out$k), c(".", "1", "1", "2"))
  out <- d[, y := .data$x * 2]
  expect_identical(as.character(out$y), c("2", "4", "6", "8"))
  f <- function(d, cut, add) d[x > cut, y := x + add]
  expect_identical(as.character(f(d, 2, 10)$y), c(".", ".", "13", "14"))
  expect_error(d[, y := if (.N > 2) "a" else 1, by = g], class = "vctrs_error_incompatible_type")
})

test_that("a new column takes the value's attributes", {
  d <- dibble(a = dta_num(c(1, 2), label = "A", labels = c(One = 1)))
  expect_identical(attr(d[, b := a]$b, "labels"), c(One = 1))
  expect_null(attr(d[, b := a + 1]$b, "labels"))
})

test_that("[ with := rejects what it does not take", {
  d <- dibble(g = c(1, 2), x = c(1, 2))
  expect_error(d[, n := .N, keyby = g], "only i, j and by")
  expect_error(d[, n := .N, drop = TRUE], "only i, j and by")
  expect_error(d[n := 1], "with a comma")
  expect_identical(as.character(d[, n := .N, by = NULL]$n), c("2", "2"))
})

test_that(":= values see every column they name", {
  d <- dibble(x = c(1, 2, 3), s = c("a", "b", "c"), y = c(10, 20, 30), g = c(1, 1, 2))
  expect_identical(as.character(d[, z := x + y]$z), c("11", "22", "33"))
  expect_identical(as.character(d[x > 1, z := y - x]$z), c(".", "18", "27"))
  expect_identical(as.character(d[, z := sum(y) - x, by = g]$z), c("29", "28", "27"))
  expect_identical(d[, t := paste0(s, .data$x + .data$y)]$t, c("a11", "b22", "c33"))
  v <- "y"
  expect_identical(as.character(d[, z := .data[[v]] / x]$z), c("10", "10", "10"))
})

test_that("groups agree on a new column's type and storage whatever their order", {
  d <- dibble(g = c(1, 2), x = c(5, 6))
  a <- d[, z := if (g[1] == 1) x > 0 else x * 1000, by = g]
  b <- d[, z := if (g[1] == 2) x > 0 else x * 1000, by = g]
  expect_identical(attr(a$z, "storage"), "double")
  expect_identical(attr(b$z, "storage"), "double")
  s <- d[, s := if (g[1] == 1) NA else "k", by = g]
  expect_identical(s$s, c("", "k"))
  expect_identical(d[, s := if (g[1] == 1) "q" else NA, by = g]$s, c("q", ""))
  expect_identical(as.character(d[, z := if (g[1] == 1) NA else 2, by = g]$z), c(".", "2"))
  expect_identical(dibble(s = c("a", "b"))[1, s := NA]$s, c("", "b"))
  expect_identical(attr(d[, z := NA]$z, "storage"), "byte")
  expect_error(d[, z := if (g[1] == 1) NULL else 1, by = g], "NULL in a group")
})

test_that("when i picks no rows, existing columns stay and nothing warns", {
  d <- dibble(age = c(30, 40), x = c(1, 2))
  attr(d, "sort_order") <- c("age", "x")
  expect_no_warning(out <- d[age > 100, m := max(age)])
  expect_identical(as.character(out$m), c(".", "."))
  expect_identical(attr(d[age > 100, age := 1], "sort_order"), c("age", "x"))
  expect_identical(d[age > 100, age := stop("not evaluated")], d)
})

test_that(":= finds columns however the expression looks them up, before the caller's", {
  d <- dibble(x = c(1, 2), g = c(1, 2))
  x <- c(99, 99)
  expect_identical(as.character(d[, y := get("x")]$y), c("1", "2"))
  expect_identical(as.character(d[, y := get("x") * 10, by = g]$y), c("10", "20"))
  expect_identical(as.character(d[get("x") > 1, y := 0]$y), c(".", "0"))
  expect_identical(as.character(d[, y := eval(quote(x)) + 1]$y), c("2", "3"))
  rm(x)
  expect_identical(as.character(d[, y := get("x"), by = g]$y), c("1", "2"))
  expect_identical(as.character(d[, y := x, by = g]$y), c("1", "2"))
})

test_that("grouped values of only NA, and long with float, keep every value", {
  d <- dibble(g = c(1, 2, 3), s = c("a", "b", "c"), x = c(1, 2, 3))
  expect_identical(d[, s := NA, by = g]$s, c("", "", ""))
  expect_identical(d[x > 2, s := NA, by = g]$s, c("a", "b", ""))
  expect_identical(as.character(d[, z := NA, by = g]$z), c(".", ".", "."))
  out <- d[x < 3, z := if (g[1] == 1) dta_num(16777217, storage = "long") else dta_num(0.5, storage = "float"), by = g]
  expect_identical(attr(out$z, "storage"), "double")
  path <- tempfile(fileext = ".dta")
  save_dta(out, path)
  expect_identical(as.character(read_dta(path)$z), c("16777217", "0.5", "."))
})

test_that("a new column on no rows is . when its value fails there", {
  d <- dibble(x = c(1, 2))
  expect_identical(as.character(d[x > 100, z := if (x > 1) 1 else 0]$z), c(".", "."))
  expect_identical(as.character(d[x > 100, z := x[[1]]]$z), c(".", "."))
  expect_error(d[FALSE, x := NULL], "no i or by")
  expect_error(d[, y := {x <<- 0; 1}], "cannot assign to column x")
  expect_identical(as.character(d[, y := {x <- x + 1; x * 2}]$y), c("4", "6"))
  expect_identical(as.character(d$x), c("1", "2"))
})
