# dtaparser_labelled and with_labels() (plan 0016). Files come from this
# library's writer; expected labels are the ones the tests write, and a
# reader test also compares them with haven's read_dta(). Letters are
# checked with na_tag().

# Evaluates `code` from the global environment, as user code runs, so
# that S3 methods come from NAMESPACE's registrations; the tests
# themselves run where the package's internal functions are visible.
as_user <- function(code, ...) eval(substitute(code), list(...), globalenv())

yes_no <- function(x = c(1, 0, tagged_na("r"), 1, NA, 2), label = NULL) {
  with_labels(x, c(No = 0, Yes = 1, tagged_na(c(Refused = "r"))), label = label)
}

test_that("read_dta gives labelled columns the class and leaves others alone", {
  labels <- c(No = 1, Yes = 2, tagged_na(c("Don't know" = "d")))
  path <- write_fixture(
    x = col(c(1, 2, tagged_na("d")), "double", labels = labels),
    m = col(c(1, 2, tagged_na("d")), "double", labels = c("Don't know" = tagged_na("d"))),
    n = col(c(1, 2, 3), "double"),
    td = col(c(0, 1, 2), "long", "%td")
  )
  df <- read_dta(path)
  expect_s3_class(df$x, "dtaparser_labelled")
  expect_identical(val_labels(df$x), labels)
  expect_identical(na_tag(df$x), c(NA, NA, "d"))
  expect_s3_class(df$m, "dtaparser_labelled")
  expect_false(is.object(df$n))
  expect_s3_class(df$td, "Date")

  factors <- read_dta(path, factors = TRUE, warn_extended_missing = FALSE)
  expect_s3_class(factors$x, "factor")
  expect_s3_class(factors$m, "dtaparser_labelled")
})

test_that("read_dta's labels match haven's", {
  skip_if_not_installed("haven")
  labels <- c(Low = 1, High = 2, tagged_na(c(Refused = "r")))
  path <- write_fixture(x = col(c(2, 1, tagged_na("r")), "double", labels = labels))
  theirs <- attr(haven::read_dta(path)$x, "labels")
  ours <- val_labels(read_dta(path)$x)
  expect_identical(names(ours), names(theirs)[match(label_keys(ours), label_keys(theirs))])
  expect_identical(unname(na_tag(ours)), na_tag(unname(theirs))[match(label_keys(ours), label_keys(theirs))])
})

test_that("read_fixed_width gives the class", {
  dir <- tempfile()
  dir.create(dir)
  writeLines(c(
    "PROC FORMAT; VALUE kidsf 0='None' 98='DK';",
    "DATA; INPUT KIDS 1-2;",
    "FORMAT KIDS kidsf.;"
  ), file.path(dir, "s.sas"))
  writeLines(c(" 2", "98", " 0"), file.path(dir, "s.dat"))
  kids <- read_fixed_width(file.path(dir, "s.dat"), file.path(dir, "s.sas"), recodes = "none")$KIDS
  expect_s3_class(kids, "dtaparser_labelled")
  expect_identical(val_label(kids), c(NA, "DK", "None"))
})

test_that("with_labels makes the class, and stops on bad labels", {
  x <- yes_no(label = "Wants a baby")
  expect_s3_class(x, "dtaparser_labelled")
  expect_identical(var_label(x), "Wants a baby")
  expect_identical(names(val_labels(x)), c("No", "Yes", "Refused"))
  relabelled <- with_labels(x, c(Nope = 0, Yep = 1))
  expect_identical(val_label(relabelled), c("Yep", "Nope", NA, "Yep", NA, NA))
  expect_identical(var_label(relabelled), "Wants a baby")
  expect_identical(na_tag(relabelled), na_tag(x))
  expect_identical(var_label(with_labels(structure(1, label = "Question"), c(Yes = 1))), "Question")

  expect_error(with_labels(1, c(A = 1, B = 1)), "code 1 more than once")
  expect_error(with_labels(1, tagged_na(c(A = "a", B = "a"))), "code .a more than once")
  expect_error(with_labels(1, c(A = NA_real_)), "cannot label NA")
  expect_error(with_labels(1, c(A = NaN)), "cannot label NA")
  expect_error(with_labels(1, c(1, 2)), "must each have a name")
  expect_error(with_labels(1, stats::setNames(1, NA)), "must each have a name")
  expect_error(with_labels("1", c(A = 1)), "x must be an integer or double vector, not character")
  expect_error(with_labels(factor(1), c(A = 1)), "not factor")
})

test_that("as.character, factor and table leave missing values out of the levels", {
  x <- yes_no()
  expect_identical(as_user(as.character(x), x = x), c("Yes", "No", NA, "Yes", NA, "2"))
  expect_identical(as_user(levels(factor(x)), x = x), c("No", "Yes", "2"))
  expect_identical(as_user(as.vector(table(x)), x = x), c(1L, 2L, 1L))
  # The first missing value, plain or tagged, does not change the levels.
  expect_identical(levels(factor(yes_no(c(NA, tagged_na("r"), 1, 0)))), c("No", "Yes"))
  expect_identical(levels(factor(yes_no(c(tagged_na("r"), NA, 1, 0)))), c("No", "Yes"))
  shared <- with_labels(c(1, 2, 3), c(Same = 1, Same = 2, Other = 3))
  expect_identical(levels(factor(shared)), c("Same", "Other"))
})

test_that("format and printing show codes and labels", {
  x <- yes_no()
  expect_identical(as_user(format(x), x = x), c("1 [Yes]", "0 [No]", "NA(r) [Refused]", "1 [Yes]", "NA", "2"))
  expect_identical(vctrs::vec_ptype_abbr(x), "dbl+lbl")
  expect_identical(vctrs::vec_ptype_abbr(with_labels(1L, c(A = 1))), "int+lbl")
  expect_match(paste(utils::capture.output(print(tibble::tibble(x = x))), collapse = "\n"), "NA(r) [Refused]", fixed = TRUE)
})

test_that("svymean averages codes, and factor() gives the shares", {
  skip_if_not_installed("survey")
  d <- data.frame(w = 1, x = yes_no())
  design <- survey::svydesign(ids = ~1, weights = ~w, data = d)
  shares <- survey::svymean(~factor(x), design, na.rm = TRUE)
  expect_equal(unname(stats::coef(shares)), c(1, 2, 1) / 4)
  expect_equal(unname(stats::coef(survey::svymean(~x, design, na.rm = TRUE))), 1)
  answered <- subset(design, x != 2)
  expect_equal(unname(stats::coef(survey::svymean(~factor(x), answered, na.rm = TRUE)))[1:2], c(1, 2) / 3)
})

test_that("comparisons and matching use the codes", {
  skip_if_not_installed("dplyr")
  x <- yes_no()
  expect_identical(x == 1, c(TRUE, FALSE, NA, TRUE, NA, FALSE))
  expect_identical(x > 0, c(TRUE, FALSE, NA, TRUE, NA, TRUE))
  expect_identical(with_labels(c(1L, 0L), c(No = 0, Yes = 1)) == 1L, c(TRUE, FALSE))
  expect_identical(x == yes_no(c(1, 1, 1, 1, 1, 2)), c(TRUE, FALSE, NA, TRUE, NA, TRUE))
  expect_identical(x %in% c(1, 2), c(TRUE, FALSE, FALSE, TRUE, FALSE, TRUE))
  expect_identical(match(1, x), 1L)
  d <- tibble::tibble(x = x)
  expect_identical(nrow(dplyr::filter(d, x %in% c(0, 2))), 2L)
})

test_that("sorting puts numbers in order and missing values last", {
  skip_if_not_installed("dplyr")
  x <- yes_no()
  expect_identical(vctrs::vec_data(sort(x)), c(0, 1, 1, 2))
  expect_identical(order(x), c(2L, 1L, 4L, 6L, 3L, 5L))
  expect_identical(vctrs::vec_data(dplyr::arrange(tibble::tibble(x = x), x)$x)[1:4], c(0, 1, 1, 2))
})

test_that("grouping puts missing values together, and val_label tells them apart", {
  skip_if_not_installed("dplyr")
  d <- tibble::tibble(x = yes_no(c(1, tagged_na("r"), NA, tagged_na("r"))))
  expect_identical(nrow(dplyr::count(d, x)), 2L)
  by_reason <- dplyr::count(d, reason = val_label(x))
  expect_identical(by_reason$reason, c("Refused", "Yes", NA))
  expect_identical(by_reason$n, c(2L, 1L, 1L))
})

test_that("missing values are NA to is.na, coalesce, replace_na and drop_na", {
  skip_if_not_installed("dplyr")
  skip_if_not_installed("tidyr")
  x <- yes_no()
  expect_identical(is.na(x), c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE))
  expect_identical(vctrs::vec_data(dplyr::coalesce(x, 9)), c(1, 0, 9, 1, 9, 2))
  expect_identical(vctrs::vec_data(tidyr::replace_na(x, 9)), c(1, 0, 9, 1, 9, 2))
  expect_identical(nrow(tidyr::drop_na(tibble::tibble(x = x))), 4L)
})

test_that("arithmetic and summaries give plain numbers", {
  x <- yes_no()
  results <- as_user(list(x + 1, -x, x * x, abs(x), cumsum(x), sum(x, na.rm = TRUE), mean(x, na.rm = TRUE),
                          min(x, na.rm = TRUE), max(x, na.rm = TRUE), range(x, na.rm = TRUE), min(x), range(x),
                          median(x, na.rm = TRUE), quantile(x, na.rm = TRUE)), x = x)
  for (v in results) expect_false(is.object(v))
  expect_identical(as_user(x + 1, x = x), c(2, 1, NA, 2, NA, 3))
  expect_identical(as_user(max(x, na.rm = TRUE), x = x), 2)
  expect_identical(as_user(range(x, na.rm = TRUE), x = x), c(0, 2))
  expect_identical(as_user(max(x), x = x), NA_real_)
  expect_identical(as_user(mean(x, na.rm = TRUE), x = x), 1)
  expect_identical(as_user(median(x, na.rm = TRUE), x = x), 1)
  expect_s3_class(as_user(summary(x), x = x), "summaryDefault")
})

test_that("dplyr keeps labels and letters, and combines consistent labels", {
  skip_if_not_installed("dplyr")
  x <- yes_no(label = "Wants")
  y <- with_labels(c(0, tagged_na("d")), c(No = 0, Yes = 1, tagged_na(c("Don't know" = "d"))))
  pooled <- dplyr::bind_rows(tibble::tibble(w = x), tibble::tibble(w = y))$w
  expect_identical(names(val_labels(pooled)), c("No", "Yes", "Don't know", "Refused"))
  expect_identical(na_tag(pooled), c(NA, NA, "r", NA, NA, NA, NA, "d"))
  expect_identical(var_label(pooled), "Wants")
  expect_identical(val_labels(dplyr::if_else(x == 1, x, 99)), val_labels(x))
  expect_identical(val_labels(dplyr::case_when(x == 1 ~ x, .default = y[1])), val_labels(pooled))
  expect_identical(na_tag(dplyr::if_else(is.na(x), x, x)), na_tag(x))
})

test_that("combining gives the same labels in any order or grouping", {
  a <- with_labels(1, c(A = 1))
  b <- with_labels(2, c(B = 2), label = "second")
  c <- with_labels(tagged_na("z"), tagged_na(c(Z = "z")), label = "third")
  labels <- function(v) val_labels(v)
  expect_identical(labels(vctrs::vec_c(vctrs::vec_c(a, b), c)), labels(vctrs::vec_c(a, vctrs::vec_c(b, c))))
  expect_identical(labels(vctrs::vec_c(c, b, a)), labels(vctrs::vec_c(a, b, c)))
  expect_identical(var_label(vctrs::vec_c(a, b, c)), "second")
  expect_identical(var_label(vctrs::vec_c(c, b, a)), "third")
  expect_identical(typeof(vctrs::vec_data(vctrs::vec_c(with_labels(1L, c(A = 1)), a))), "double")
})

test_that("a code or letter with two texts is an error", {
  expect_error(vctrs::vec_c(yes_no(), with_labels(1, c(YES = 1))), "code 1 is \"Yes\" in one and \"YES\"")
  expect_error(vctrs::vec_c(yes_no(), with_labels(tagged_na("r"), tagged_na(c(Refusal = "r")))),
               "code .r is \"Refused\" in one and \"Refusal\"")
})

test_that("new codes keep the old labels, which may no longer fit", {
  skip_if_not_installed("dplyr")
  x <- with_labels(c(1, 2), c(Yes = 1, Two = 2))
  changed <- dplyr::case_when(x == 1 ~ 2, .default = x)
  expect_identical(val_label(changed), c("Two", "Two"))
})

test_that("casting gives plain codes, and refuses to lose letters, fractions or labels", {
  x <- yes_no()
  expect_identical(na_tag(as.numeric(x)), na_tag(x))
  expect_false(is.object(as.numeric(x)))
  expect_identical(vctrs::vec_data(x), as.numeric(x))
  expect_identical(attr(unclass(x), "labels"), val_labels(x))
  expect_error(as.integer(x), class = "vctrs_error_cast_lossy")
  expect_identical(as.integer(with_labels(c(1, 0), c(A = 1))), c(1L, 0L))
  ints <- with_labels(c(1L, 0L), c(No = 0, Yes = 1))
  expect_error(ints[1] <- 2.5, class = "vctrs_error_cast_lossy")
  extra <- with_labels(1, c(No = 0, Yes = 1, Maybe = 2))
  expect_error(ints[1] <- extra, "Code 2 has a label")
})

test_that(":= widens labelled codes and keeps class, labels and letters", {
  d <- tibble::tibble(g = c(1, 1, 2), v = with_labels(c(1L, 0L, NA), c(No = 0, Yes = 1), label = "V"))
  e <- d
  e[1, v] := 2.5
  expect_s3_class(e$v, "dtaparser_labelled")
  expect_identical(vctrs::vec_data(e$v), c(2.5, 0, NA))
  expect_identical(val_labels(e$v), c(No = 0, Yes = 1))
  expect_identical(var_label(e$v), "V")
  f <- d
  f[g == 2, v, by = g] := tagged_na("a")
  expect_identical(na_tag(f$v), c(NA, NA, "a"))
  expect_s3_class(f$v, "dtaparser_labelled")
  h <- d
  h[, w] := with_labels(c(0, 1, 0), c(No = 0, Yes = 1))
  expect_s3_class(h$w, "dtaparser_labelled")
  expect_identical(val_label(h$w), c("No", "Yes", "No"))
})

test_that("base R: ifelse drops the class; rbind, merge and saveRDS keep it", {
  x <- yes_no()
  expect_false(is.object(ifelse(TRUE, x, x)))
  stacked <- rbind(data.frame(x = x), data.frame(x = x))$x
  expect_s3_class(stacked, "dtaparser_labelled")
  expect_identical(na_tag(stacked), rep(na_tag(x), 2))
  merged <- merge(data.frame(id = 1:6, x = x), data.frame(id = 1:6))$x
  expect_s3_class(merged, "dtaparser_labelled")
  path <- tempfile(fileext = ".rds")
  saveRDS(x, path)
  expect_identical(readRDS(path), x)
  expect_identical(na_tag(readRDS(path)), na_tag(x))
})

test_that("the accessors read the class however it was made", {
  read <- read_dta(write_fixture(x = col(c(1, tagged_na("r")), "double",
                                         labels = c(Yes = 1, tagged_na(c(Refused = "r"))))))$x
  made <- with_labels(c(1, tagged_na("r")), c(Yes = 1, tagged_na(c(Refused = "r"))))
  pooled <- vctrs::vec_c(read, made)
  for (x in list(read, made)) {
    expect_identical(na_tag(x), c(NA, "r"))
    expect_identical(is_tagged_na(x, "r"), c(FALSE, TRUE))
    expect_identical(val_label(x), c("Yes", "Refused"))
    expect_identical(names(val_labels(x)), c("Yes", "Refused"))
  }
  expect_identical(val_label(pooled), rep(c("Yes", "Refused"), 2))
  expect_identical(var_label(with_labels(1, c(A = 1), label = "L")), "L")
})

# Labels as text (plan 0017).

test_that("== and != with a label compare its code", {
  x <- yes_no()
  expect_identical(as_user(x == "Yes", x = x), as_user(x == 1, x = x))
  expect_identical(as_user("Yes" == x, x = x), as_user(x == 1, x = x))
  expect_identical(as_user(x != "No", x = x), as_user(x != 0, x = x))
  expect_identical(as_user(x == NA_character_, x = x), rep(NA, 6))
  expect_identical(as_user(x == 1, x = x), c(TRUE, FALSE, NA, TRUE, NA, FALSE))
  expect_identical(as_user(x + 1, x = x), c(2, 1, NA, 2, NA, 3))
  skip_if_not_installed("dplyr")
  expect_identical(nrow(dplyr::filter(tibble::tibble(x = x), x == "Yes")), 2L)
})

test_that("text that names no one answer is an error in a comparison", {
  x <- yes_no()
  expect_error(as_user(x == "Refused", x = x), "labels the missing value .r")
  expect_error(as_user(x > "No", x = x), "labels have no order")
  expect_error(as_user(x == "Maybe", x = x), "\"Maybe\" is not a label of this column")
  shared <- with_labels(c(1, 2), c(Same = 1, Same = 2))
  expect_error(as_user(shared == "Same", shared = shared), "labels more than one code")
})

test_that("a label assigns its code", {
  x <- yes_no()
  y <- x
  y[2] <- "Yes"
  expect_identical(vctrs::vec_data(y)[1:2], c(1, 1))
  y[1] <- "Refused"
  expect_identical(na_tag(y)[1], "r")
  ints <- with_labels(c(1L, 0L), c(No = 0, Yes = 1, tagged_na(c(Refused = "r"))))
  expect_error(ints[1] <- "Refused", class = "vctrs_error_cast_lossy")
  expect_error(y[1] <- "Maybe", "not a label")
  skip_if_not_installed("dplyr")
  expect_identical(vctrs::vec_data(dplyr::if_else(x == 1, "No", x))[c(1, 2, 6)], c(0, 0, 2))
  expect_identical(val_label(dplyr::case_when(x == 0 ~ "Yes", .default = x)), c("Yes", "Yes", "Refused", "Yes", NA, NA))
  expect_identical(vctrs::vec_data(dplyr::coalesce(x, "No")), c(1, 0, 0, 1, 0, 2))
})

test_that(":= assigns a label's code, widening integer codes for .a to .z", {
  d <- tibble::tibble(v = with_labels(c(1L, 0L, NA), c(No = 0, Yes = 1, tagged_na(c(Refused = "r")))))
  e <- d
  e[3, v] := "No"
  expect_identical(vctrs::vec_data(e$v), c(1L, 0L, 0L))
  f <- d
  f[1, v] := "Refused"
  expect_type(vctrs::vec_data(f$v), "double")
  expect_identical(na_tag(f$v), c("r", NA, NA))
  expect_s3_class(f$v, "dtaparser_labelled")
  expect_error(d[1, v] := "Maybe", "not a label")
})

test_that("%in% compares codes, so labels go through val_label", {
  x <- yes_no()
  # mtfrm() gives codes, so text finds nothing; the docs say so.
  expect_identical(as_user(x %in% "Yes", x = x), rep(FALSE, 6))
  expect_identical(val_label(x) %in% "Yes", c(TRUE, FALSE, FALSE, TRUE, FALSE, FALSE))
})
