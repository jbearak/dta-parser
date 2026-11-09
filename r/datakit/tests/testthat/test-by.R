# datakit_by(): the columns and their letters, so dplyr's grouping and
# joins keep `.`, `.a` and `.b` apart (plan 0024, stage 2).

letters_frame <- function() {
  tibble::tibble(
    x = c(1, tagged_na("a"), tagged_na("b"), NA, tagged_na("a"), 1),
    g = c("p", "q", "r", "s", "t", "u")
  )
}

shown <- function(x) {
  t <- na_tag(x)
  ifelse(!is.na(t), paste0(".", t), ifelse(is.na(x), ".", as.character(unclass(x))))
}

test_that("datakit_by() returns each column and its letter", {
  x <- c(1, tagged_na("a"), NA)
  out <- datakit_by(x)
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("x", "x_letter"))
  expect_identical(out$x_letter, c(NA, "a", NA))
  expect_identical(shown(out$x), c("1", ".a", "."))
  expect_named(datakit_by(x, .suffix = ".why"), c("x", "x.why"))
})

test_that("group_by(), count() and distinct() keep . and each letter apart", {
  skip_if_not_installed("dplyr")
  d <- letters_frame()
  expect_equal(nrow(dplyr::count(d, x)), 2)  # R merges them
  counted <- dplyr::count(d, datakit_by(x))
  expect_equal(nrow(counted), 4)
  expect_setequal(shown(counted$x), c("1", ".a", ".b", "."))
  expect_equal(counted$n[match(c("1", ".a", ".b", "."), shown(counted$x))], c(2, 2, 1, 1))
  expect_equal(nrow(dplyr::distinct(d, datakit_by(x))), 4)
  s <- d |> dplyr::group_by(datakit_by(x)) |> dplyr::summarise(n = dplyr::n(), .groups = "drop")
  expect_setequal(shown(s$x), c("1", ".a", ".b", "."))  # x keeps its letters
  expect_identical(dplyr::group_vars(s), character())
})

test_that("summarise() left grouped by x alone, as dplyr does by default", {
  skip_if_not_installed("dplyr")
  s <- suppressMessages(letters_frame() |> dplyr::group_by(datakit_by(x)) |> dplyr::summarise(n = dplyr::n()))
  expect_identical(dplyr::group_vars(s), "x")
})

test_that("a join by the column and its letter matches letter to letter", {
  skip_if_not_installed("dplyr")
  lookup <- tibble::tibble(x = c(tagged_na("a"), tagged_na("b"), NA, 1), lab = c("A", "B", "dot", "one"))
  joined <- letters_frame() |>
    dplyr::mutate(datakit_by(x)) |>
    dplyr::left_join(dplyr::mutate(lookup, datakit_by(x)), by = c("x", "x_letter"))
  expect_equal(nrow(joined), 6)
  expect_identical(joined$lab, c("one", "A", "B", "dot", "A", "one"))
})

test_that("only types that can hold a letter get a letter column", {
  d <- datakit_by(
    plain = c(1, tagged_na("a")),
    lab = with_labels(c(1, tagged_na("a")), c(Yes = 1)),
    when = as.Date(c("2024-01-01", NA)),
    at = as.POSIXct(c("2024-01-01", NA), tz = "UTC"),
    int = 1:2,
    text = c("a", "b"),
    fac = factor(c("a", "b")),
    span = as.difftime(c(1, 2), units = "secs")
  )
  expect_named(d, c("plain", "plain_letter", "lab", "lab_letter", "when", "when_letter",
                    "at", "at_letter", "int", "text", "fac", "span"))
  expect_identical(d$lab_letter, c(NA, "a"))
  expect_s3_class(d$lab, "dtaparser_labelled")
  expect_identical(val_labels(d$lab), val_labels(with_labels(c(1, tagged_na("a")), c(Yes = 1))))
})

test_that("integer64 gets no letter column", {
  skip_if_not_installed("bit64")
  expect_named(datakit_by(big = bit64::as.integer64(1:2)), "big")
})

test_that("haven's labelled doubles get a letter column", {
  skip_if_not_installed("haven")
  h <- haven::labelled(c(1, haven::tagged_na("a")), c(Yes = 1))
  expect_identical(datakit_by(h)$h_letter, c(NA, "a"))
})

test_that("arguments are named as group_by() names them", {
  skip_if_not_installed("dplyr")
  d <- letters_frame()
  v <- "x"
  names_of <- function(data) setdiff(names(data), c("g", "n"))
  expect_named(dplyr::count(d, datakit_by(.data$x)), c("x", "x_letter", "n"))
  expect_named(dplyr::count(d, datakit_by(.data[[v]])), c("x", "x_letter", "n"))
  forward <- function(data, var) dplyr::count(data, datakit_by({{ var }}))
  expect_named(forward(d, x), c("x", "x_letter", "n"))
  expect_named(dplyr::count(d, datakit_by(y = x * 2)), c("y", "y_letter", "n"))
  expect_named(dplyr::count(d, datakit_by(x * 2)), c("x * 2", "x * 2_letter", "n"))
})

test_that("two columns of one name are an error; a frame's column is replaced", {
  x <- c(1, tagged_na("a"))
  expect_error(datakit_by(x, x_letter = x), "two columns named \"x_letter\"")
  expect_error(datakit_by(x, x), "two columns named \"x\", \"x_letter\"")
  skip_if_not_installed("dplyr")
  d <- tibble::tibble(x = x, x_letter = "mine")
  expect_identical(dplyr::mutate(d, datakit_by(x))$x_letter, c(NA, "a"))
})

test_that(".suffix and empty calls are checked", {
  x <- 1
  expect_error(datakit_by(x, .suffix = ""), ".suffix must be one non-empty string")
  expect_error(datakit_by(x, .suffix = NA_character_), ".suffix must be one non-empty string")
  expect_error(datakit_by(x, .suffix = c("a", "b")), ".suffix must be one non-empty string")
  expect_error(datakit_by(), "needs at least one column")
})

test_that(".by cannot take datakit_by(); mutate() first", {
  skip_if_not_installed("dplyr")
  d <- letters_frame()
  expect_error(dplyr::summarise(d, n = dplyr::n(), .by = datakit_by(x)), "object 'x' not found")
  s <- d |> dplyr::mutate(datakit_by(x)) |> dplyr::summarise(n = dplyr::n(), .by = c(x, x_letter))
  expect_equal(nrow(s), 4)
})
