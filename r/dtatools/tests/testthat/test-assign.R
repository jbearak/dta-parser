test_that(":= makes a column on the rows i selects, by Stata's comparisons", {
  d <- dibble(age = c(25, 41, NA, .a), s = c("p", "q", "r", "s"))
  out <- recoded(d[age > 35, older] := 1)
  expect_identical(as.character(out$older), c(".", "1", "1", "1"))
  expect_identical(attr(out$older, "storage"), "double")
  expect_false("older" %in% names(d))
  out <- recoded(d[age < 30, t] := "young")
  expect_identical(out$t, c("young", "", "", ""))
  out <- recoded(d[c(TRUE, NA, FALSE, TRUE), flag] := TRUE)
  expect_identical(as.character(out$flag), c("1", ".", ".", "1"))
  expect_identical(attr(out$flag, "storage"), "byte")
  expect_identical(as.character(recoded(d[c(2, 4), k] := 7)$k), c(".", "7", ".", "7"))
  expect_identical(as.character(recoded(d[-1, k] := 7)$k), c(".", "7", "7", "7"))
  expect_identical(as.character(recoded(d[dta_num(c(0, 2, NA, 0)), k] := 7)$k), c(".", "7", "7", "."))
  expect_identical(as.character(recoded(d[, k] := age)$k), c("25", "41", ".", ".a"))
})

test_that(":= into an existing column keeps its labels and widens its storage", {
  d <- dibble(x = dta_num(c(1, 2, .d), storage = "byte", label = "X", labels = c(One = 1, DK = .d)))
  out <- recoded(d[x == .d, x] := .r)
  expect_identical(as.character(out$x), c("1", "2", ".r"))
  expect_identical(attr(out$x, "labels"), attr(d$x, "labels"))
  expect_identical(attr(out$x, "label"), "X")
  expect_identical(attr(out$x, "storage"), "byte")
  expect_identical(attr(recoded(d[1, x] := 100)$x, "storage"), "byte")
  expect_identical(attr(recoded(d[1, x] := 101)$x, "storage"), "int")
  expect_identical(attr(recoded(d[1, x] := -40000)$x, "storage"), "long")
  expect_identical(attr(recoded(d[1, x] := 3e9)$x, "storage"), "double")
  expect_identical(attr(recoded(d[1, x] := 0.5)$x, "storage"), "double")
  f <- dibble(x = dta_num(1, storage = "float"))
  expect_identical(attr(recoded(f[, x] := 0.1)$x, "storage"), "float")
  expect_identical(attr(recoded(f[, x] := 1e300)$x, "storage"), "double")
  expect_error(d[, x] := "a", "cannot put strings into numeric column x")
  expect_error(recoded(dibble(s = "a")[, s] := 1), "cannot put numbers into string column s")
  path <- tempfile(fileext = ".dta")
  save_dta(recoded(d[1, x] := 0.5), path)
  expect_identical(as.character(read_dta(path)$x), c("0.5", "2", ".d"))
})

test_that(":= with by works within groups, each missing code its own", {
  d <- dibble(g = c(.a, 1, .b, 1, .a, NA), x = c(1, 2, 3, 4, 5, 6))
  out <- recoded(d[, n, by = g] := .N)
  expect_identical(as.character(out$n), c("2", "2", "1", "2", "2", "1"))
  out <- recoded(d[x > 1, first, by = .(g)] := x[1])
  expect_identical(as.character(out$first), c(".", "2", "3", "2", "5", "6"))
  out <- recoded(d[, idx, by = "g"] := seq_len(.N))
  expect_identical(as.character(out$idx), c("1", "1", "1", "2", "2", "1"))
  by <- "g"
  expect_identical(recoded(d[, n, by = by] := .N)$n, recoded(d[, n, by = g] := .N)$n)
  expect_error(recoded(d[, g, by = g] := 1), "cannot change g")
  expect_error(d[1, by = g], "by goes with :=")
})

test_that(":= takes names in strings or variables, and NULL", {
  d <- dibble(x = c(1, 2), y = c(3, 4))
  out <- recoded(d[, a] := x * 10)
  out[, b] := a + 1  # sees the new a
  expect_identical(as.character(out$b), c("11", "21"))
  nm <- "z"
  expect_identical(names(recoded(d[, (nm)] := 0)), c("x", "y", "z"))
  expect_identical(names(recoded(d[, "z"] := 0)), c("x", "y", "z"))
  expect_identical(names(recoded(d[, y] := NULL)), "x")
  expect_error(recoded(d[1, y] := NULL), "no i or by")
  gone <- NULL
  expect_identical(names(recoded(d[, y] := gone)), "x")
  expect_error(recoded(d[, y, by = x] := NULL), "NULL drops the whole column")
  expect_error(recoded(d[, a] := 1:3), "`a`.*size 3.*size 2")
})

test_that(":= keeps the dibble's attributes and ends the sort order at a changed key", {
  d <- dibble(a = c(1, 2), b = c(3, 4), c = c(5, 6))
  attr(d, "label") <- "Data"
  attr(d, "notes") <- "note"
  attr(d, "sort_order") <- c("a", "b")
  out <- recoded(d[, c] := 0)
  expect_s3_class(out, "dibble")
  expect_identical(attr(out, "label"), "Data")
  expect_identical(attr(out, "notes"), "note")
  expect_identical(attr(out, "sort_order"), c("a", "b"))
  expect_identical(attr(recoded(d[, b] := 0), "sort_order"), "a")
  expect_null(attr(recoded(d[, a] := 0), "sort_order"))
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
  for (out in list(recoded(d[g < 0, t] := "z"), recoded(d[g < 0, t, by = g] := "z"))) {
    expect_identical(out$t, c("", ""))
  }
  expect_identical(recoded(d[g < 0, s, by = g] := "z")$s, c("a", "b"))
  expect_identical(recoded(d[g < 0, x, by = g] := 0.5)$x, d$x)
  expect_identical(recoded(d[g < 0, s, by = g] := 1), d)
})

test_that(":= stores only what Stata holds", {
  d <- dibble(x = c(1, 2), s = c("a", "b"))
  out <- d
  out[, x] := c(Inf, .a)
  out[, y] := c(NaN, -Inf)
  out[, s] := NA_character_
  out[, t] := c("u", NA)
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
  out <- recoded(d[x > 1, n, by = g] := .N)
  expect_identical(as.character(out$n), c(".", "1", "2", "2"))
  out <- recoded(d[x > 1, k, by = g] := seq_len(.N))
  expect_identical(as.character(out$k), c(".", "1", "1", "2"))
  out <- recoded(d[, y] := .data$x * 2)
  expect_identical(as.character(out$y), c("2", "4", "6", "8"))
  f <- function(d, cut, add) {
    d[x > cut, y] := x + add
    d
  }
  expect_identical(as.character(f(d, 2, 10)$y), c(".", ".", "13", "14"))
  expect_error(recoded(d[, y, by = g] := if (.N > 2) "a" else 1), class = "vctrs_error_incompatible_type")
})

test_that("a new column takes the value's attributes", {
  d <- dibble(a = dta_num(c(1, 2), label = "A", labels = c(One = 1)))
  expect_identical(attr(recoded(d[, b] := a)$b, "labels"), c(One = 1))
  expect_null(attr(recoded(d[, b] := a + 1)$b, "labels"))
})

test_that("d[i, name := value] is an error that shows the line to write", {
  d <- dibble(g = c(1, 2), x = c(1, 2))
  expect_error(d[x > 1, y := x * 2], "write d[x > 1, y] := x * 2 to change d", fixed = TRUE)
  expect_error(d <- d[, n := .N, by = g], "write d[, n, by = g] := .N to change d", fixed = TRUE)
  expect_error(d[, `:=`(a = 1, b = a + 1)], "write d[, a] := 1; d[, b] := a + 1 to change d", fixed = TRUE)
  expect_error(d[n := 1], "write d[, n] := 1 to change d", fixed = TRUE)
  expect_false("n" %in% names(d))
  expect_error(d[, n, keyby = g] := .N, "write d\\[i, name\\] := value")
  expect_identical(as.character(recoded(d[, n, by = NULL] := .N)$n), c("2", "2"))
})

test_that(":= values see every column they name", {
  d <- dibble(x = c(1, 2, 3), s = c("a", "b", "c"), y = c(10, 20, 30), g = c(1, 1, 2))
  expect_identical(as.character(recoded(d[, z] := x + y)$z), c("11", "22", "33"))
  expect_identical(as.character(recoded(d[x > 1, z] := y - x)$z), c(".", "18", "27"))
  expect_identical(as.character(recoded(d[, z, by = g] := sum(y) - x)$z), c("29", "28", "27"))
  expect_identical(recoded(d[, t] := paste0(s, .data$x + .data$y))$t, c("a11", "b22", "c33"))
  v <- "y"
  expect_identical(as.character(recoded(d[, z] := .data[[v]] / x)$z), c("10", "10", "10"))
})

test_that("groups agree on a new column's type and storage whatever their order", {
  d <- dibble(g = c(1, 2), x = c(5, 6))
  a <- recoded(d[, z, by = g] := if (g[1] == 1) x > 0 else x * 1000)
  b <- recoded(d[, z, by = g] := if (g[1] == 2) x > 0 else x * 1000)
  expect_identical(attr(a$z, "storage"), "double")
  expect_identical(attr(b$z, "storage"), "double")
  s <- recoded(d[, s, by = g] := if (g[1] == 1) NA else "k")
  expect_identical(s$s, c("", "k"))
  expect_identical(recoded(d[, s, by = g] := if (g[1] == 1) "q" else NA)$s, c("q", ""))
  expect_identical(as.character(recoded(d[, z, by = g] := if (g[1] == 1) NA else 2)$z), c(".", "2"))
  expect_identical(recoded(dibble(s = c("a", "b"))[1, s] := NA)$s, c("", "b"))
  expect_identical(attr(recoded(d[, z] := NA)$z, "storage"), "byte")
  expect_error(recoded(d[, z, by = g] := if (g[1] == 1) NULL else 1), "NULL in a group")
})

test_that("when i picks no rows, existing columns stay and nothing warns", {
  d <- dibble(age = c(30, 40), x = c(1, 2))
  attr(d, "sort_order") <- c("age", "x")
  expect_no_warning(out <- recoded(d[age > 100, m] := max(age)))
  expect_identical(as.character(out$m), c(".", "."))
  expect_identical(attr(recoded(d[age > 100, age] := 1), "sort_order"), c("age", "x"))
  expect_identical(recoded(d[age > 100, age] := stop("not evaluated")), d)
})

test_that(":= finds columns however the expression looks them up, before the caller's", {
  d <- dibble(x = c(1, 2), g = c(1, 2))
  x <- c(99, 99)
  expect_identical(as.character(recoded(d[, y] := get("x"))$y), c("1", "2"))
  expect_identical(as.character(recoded(d[, y, by = g] := get("x") * 10)$y), c("10", "20"))
  expect_identical(as.character(recoded(d[get("x") > 1, y] := 0)$y), c(".", "0"))
  expect_identical(as.character(recoded(d[, y] := eval(quote(x)) + 1)$y), c("2", "3"))
  rm(x)
  expect_identical(as.character(recoded(d[, y, by = g] := get("x"))$y), c("1", "2"))
  expect_identical(as.character(recoded(d[, y, by = g] := x)$y), c("1", "2"))
})

test_that("grouped values of only NA, and long with float, keep every value", {
  d <- dibble(g = c(1, 2, 3), s = c("a", "b", "c"), x = c(1, 2, 3))
  expect_identical(recoded(d[, s, by = g] := NA)$s, c("", "", ""))
  expect_identical(recoded(d[x > 2, s, by = g] := NA)$s, c("a", "b", ""))
  expect_identical(as.character(recoded(d[, z, by = g] := NA)$z), c(".", ".", "."))
  out <- recoded(d[x < 3, z, by = g] := if (g[1] == 1) dta_num(16777217, storage = "long") else dta_num(0.5, storage = "float"))
  expect_identical(attr(out$z, "storage"), "double")
  path <- tempfile(fileext = ".dta")
  save_dta(out, path)
  expect_identical(as.character(read_dta(path)$z), c("16777217", "0.5", "."))
})

test_that("a new column on no rows is . when its value fails there", {
  d <- dibble(x = c(1, 2))
  expect_identical(as.character(recoded(d[x > 100, z] := if (x > 1) 1 else 0)$z), c(".", "."))
  expect_identical(as.character(recoded(d[x > 100, z] := x[[1]])$z), c(".", "."))
  expect_error(recoded(d[FALSE, x] := NULL), "no i or by")
  expect_error(recoded(d[, y] := {x <<- 0; 1}), "cannot assign to column x")
  expect_identical(as.character(recoded(d[, y] := {x <- x + 1; x * 2})$y), c("4", "6"))
  expect_identical(as.character(d$x), c("1", "2"))
})

test_that("d[i, name] <- value recodes as := does, picking rows among the columns", {
  d <- dibble(x = dta_num(c(1, 2, .d), storage = "byte", label = "X", labels = c(DK = .d)),
              y = c(1, 5, 3), s = c("a", "b", "c"))
  e <- d
  e[x == .d, x] <- .r
  expect_identical(e, recoded(d[x == .d, x] := .r))
  e[y > 2, z] <- 0.5
  expect_identical(as.character(e$z), c(".", "0.5", "0.5"))
  expect_identical(attr(e$z, "storage"), "double")
  e[1, x] <- 0.5
  expect_identical(attr(e$x, "storage"), "double")
  expect_identical(attr(e$x, "labels"), attr(d$x, "labels"))
  e[x > 1, s] <- c("m", "n")
  expect_identical(e$s, c("a", "m", "n"))
  e[, "t"] <- "k"
  expect_identical(e$t, c("k", "k", "k"))
  nm <- "y"
  e[1, (nm)] <- 100
  expect_identical(as.character(e$y), c("100", "5", "3"))
  e[c(TRUE, NA, FALSE), w] <- tibble::tibble(w = 1)
  expect_identical(as.character(e$w), c("1", ".", "."))
  e[y > 1000, y] <- 7  # no rows: the column stays
  expect_identical(as.character(e$y), c("100", "5", "3"))
  expect_error(e[y > 1000, y] <- 1:7, "size 7.*size 0")
  e[, w] <- NULL
  expect_false("w" %in% names(e))
  expect_identical(d$x, dibble(x = dta_num(c(1, 2, .d), storage = "byte", label = "X", labels = c(DK = .d)))$x)
})

test_that("d[i, name] <- value works inside functions and nested targets", {
  d <- dibble(x = c(1, 2))
  f <- function(d, cut) {
    d[x > cut, big] <- 1
    d
  }
  expect_identical(as.character(f(d, 1)$big), c(".", "1"))
  expect_false("big" %in% names(d))
  l <- list(d = d)
  l$d[x == 2, x] <- .a
  expect_identical(as.character(l$d$x), c("1", ".a"))
})

test_that("d[i, name] <- value errors rather than guess", {
  d <- dibble(x = c(1, 2), s = c("a", "b"))
  nm <- "x"
  expect_error(d[1, nm] <- 3, "nm is a variable, not a column")
  expect_error(d[1, s] <- 1, "cannot put numbers into string column s")
  expect_error(d[1, x] <- NULL, "NULL drops the whole column")
  expect_error(d[, x] <- 1:3, "size 3.*size 2")
  expect_error(d[1, (c("x", "s"))] <- 1, "one column name")
  sym <- quote(x)
  expect_error(d[1, (sym)] <- 9, "must give a string")
  two <- 2
  expect_error(d[1, (two)] <- 9, "must give a string")
  expect_error(d[x > 100, new] <- 1:7, "size 7.*size 0")
  expect_error(d[nrow(d) + 1, "x"] <- 9, "cannot add rows")
  helper <- function(d, col, v) {
    d[d$x > 1, col] <- v
    d
  }
  expect_error(helper(d, "x", 0), "col is a variable, not a column")
  e <- d
  e[nrow(e) + 1, ] <- list(3, "c")  # adding a row is tibble's
  expect_identical(nrow(e), 3L)
  x <- 99  # a column hides the caller's variable, in i and as the name
  d[x == 2, x] <- 0
  expect_identical(as.character(d$x), c("1", "0"))
})

test_that("other [<- forms are tibble's", {
  d <- dibble(x = c(1, 2), y = c(3, 4))
  e <- d
  e[1, 2] <- 9
  expect_identical(as.character(e$y), c("9", "4"))
  e <- d
  e["y"] <- list(c(5, 6))
  expect_identical(as.numeric(e$y), c(5, 6))
  e <- d
  e[d$x > 1, c("x", "y")] <- 0
  expect_identical(as.numeric(e$x), c(1, 0))
})

test_that("d[i, name] <- value takes row numbers, a dta_num i, and no rows at all", {
  d <- dibble(x = c(1, 2, 3), f = dta_num(c(0, 2, NA)))
  e <- d
  e[-1, y] <- 1
  expect_identical(as.character(e$y), c(".", "1", "1"))
  e[c(1, 3), y] <- 5
  expect_identical(as.character(e$y), c("5", "1", "5"))
  e[f, z] <- 1  # true where nonzero or missing, as Stata's `if f`
  expect_identical(as.character(e$z), c(".", "1", "1"))
  e[, nothing] <- NULL
  expect_identical(names(e), c("x", "f", "y", "z"))
  e[, c] <- 0  # a function's name is a column name like any other
  expect_identical(as.character(e$c), c("0", "0", "0"))
  d0 <- d[0, ]
  d0[, y] <- 1
  expect_identical(names(d0), c("x", "f", "y"))
  d0[, x] <- NULL
  expect_identical(names(d0), c("f", "y"))
})

test_that("dplyr's rows_update still works on a dibble", {
  skip_if_not_installed("dplyr")
  d <- dibble(id = c(1, 2, 3), x = c(10, 20, NA))
  up <- dplyr::rows_update(d, dibble(id = 2, x = 99), by = "id")
  expect_identical(as.character(up$x), c("10", "99", "."))
})

test_that("d[i, name] := value changes d, with the value among the columns", {
  d <- dibble(x = c(1, 2, 3), y = c(1, 0, 3), v = c(10, 20, 30), g = c(1, 1, 2))
  v <- 99  # the column hides it
  e <- d
  e[x == y, z] := v
  expect_identical(as.character(e$z), c("10", ".", "30"))
  e[, w] := x + v
  expect_identical(as.character(e$w), c("11", "22", "33"))
  e[x > 1, "s"] := "k"
  expect_identical(e$s, c("", "k", "k"))
  nm <- "t"
  e[1, (nm)] := 5
  expect_identical(as.character(e$t), c("5", ".", "."))
  e[, n, by = g] := .N
  expect_identical(as.character(e$n), c("2", "2", "1"))
  e[x > 100, x] := stop("not evaluated")  # no rows: the column stays
  expect_identical(e$x, d$x)
  e[, w] := NULL
  expect_false("w" %in% names(e))
  expect_invisible(e[1, x] := 0)
  expect_identical(as.character(d$x), c("1", "2", "3"))
})

test_that("in d[i, name] := value a bare name is the column", {
  d <- dibble(x = c(1, 2))
  nm <- "q"
  expect_error(d[1, nm] <- 1, "nm is a variable, not a column")
  d[1, nm] := 1
  expect_identical(names(d), c("x", "nm"))
})

test_that("d[i, name] := value works inside functions and on nested targets", {
  d <- dibble(x = c(1, 2))
  f <- function(d, cut) {
    d[x > cut, big] := x * 10
    d
  }
  expect_identical(as.character(f(d, 1)$big), c(".", "20"))
  expect_false("big" %in% names(d))
  l <- list(d = d)
  l$d[x == 2, x] := .a
  expect_identical(as.character(l$d$x), c("1", ".a"))
  l[["d"]][, y] := x
  expect_identical(as.character(l$d$y), c("1", ".a"))
})

test_that("d[i, name] := value errors on other left sides", {
  d <- dibble(x = c(1, 2), g = c(1, 2))
  expect_error(x := 1, "write d\\[i, name\\] := value")
  expect_error(d[1] := 1, "write d\\[i, name\\] := value")
  expect_error(d[1, ] := 1, "write d\\[i, name\\] := value")
  expect_error(d[1, x, g] := 1, "write d\\[i, name\\] := value")
  expect_error(d[1, x, keyby = g] := 1, "write d\\[i, name\\] := value")
  df <- data.frame(x = 1)
  expect_error(df[1, x] := 2, "needs a dibble")
  expect_error(d[1, x] := NULL, "drops the whole column")
})

test_that(":= is found when dtatools is attached last, and not when rlang is", {
  script <- tempfile(fileext = ".R")
  writeLines(c(
    'has_dt <- requireNamespace("data.table", quietly = TRUE)',
    'if (has_dt) suppressMessages(library(data.table))',
    'library(dtatools, warn.conflicts = FALSE)  # attached last, its := wins',
    'd <- dibble(x = c(1, 2))',
    'd[x == 1, y] := x + 1',
    'cat(as.character(d$y), sep = ",")',
    'if (has_dt) {',
    '  dt <- data.table::data.table(a = 1:2)',
    '  dt[, b := a * 2]  # data.table reads its :=, never calls it',
    '  cat(";", dt$b, sep = ",")',
    '} else cat(";", 2, 4, sep = ",")',
    'library(rlang, warn.conflicts = FALSE)',
    'e <- tryCatch({d[x == 1, y] := 0; "no error"}, error = function(e) conditionMessage(e))',
    'cat(";", grepl("dynamic dots", e), sep = "")'
  ), script)
  old <- Sys.getenv("R_LIBS", unset = NA)
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  on.exit(if (is.na(old)) Sys.unsetenv("R_LIBS") else Sys.setenv(R_LIBS = old))
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(rscript, shQuote(script), stdout = TRUE, stderr = TRUE))
  out <- out[!grepl("^OMP:", out)]
  expect_identical(out, "2,.;,2,4;TRUE")
})
