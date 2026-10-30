# save_dta writes packed columns from their text: the file is the one a
# plain character copy gives, and each column is left in the state it was
# in (plan 0007).

# A plain character vector with x's values and attributes, made without
# touching x's packed state more than reading each value does.
plain_copy <- function(x) {
  y <- vapply(seq_along(x), function(i) x[[i]], "")
  y[is.na(x)] <- NA
  attributes(y) <- attributes(x)
  y
}

bytes_of <- function(data) {
  path <- tempfile(fileext = ".dta")
  save_dta(data, path)
  readBin(path, "raw", file.size(path))
}

source_file <- function() {
  path <- tempfile(fileext = ".dta")
  save_dta(data.frame(
    plain = sprintf("row %d é", 1:40),
    dict = rep(c("a", "bé", ""), length.out = 40),
    empty = "",
    stringsAsFactors = FALSE
  ), path)
  path
}

test_that("packed plain, packed dictionary, partly made and made columns write as their plain copies", {
  path <- source_file()
  cases <- list(
    "packed plain" = function() read_plain(path),
    "packed dictionary" = function() read_dta(path),
    "partly made" = function() {
      d <- read_plain(path)
      for (n in names(d)) invisible(d[[n]][[3]])
      d
    },
    "made, with an NA" = function() {
      d <- read_plain(path)
      for (n in names(d)) d[[n]][2] <- NA
      d
    }
  )
  for (what in names(cases)) {
    d <- cases[[what]]()
    before <- vapply(d, state, 0)
    if (what == "packed dictionary") expect_true(has_dictionary(d$dict), label = what)
    if (what == "made, with an NA") expect_true(all(before == -1), label = what)
    if (what == "partly made") expect_true(all(before > 0), label = what)
    ours <- bytes_of(d)
    expect_identical(vapply(d, state, 0), before, label = what)
    copy <- d
    for (n in names(copy)) copy[[n]] <- plain_copy(d[[n]])
    expect_identical(vapply(copy, state, 0), c(plain = -2, dict = -2, empty = -2), label = what)
    expect_identical(ours, bytes_of(copy), label = what)
  }
})

test_that("another ALTREP character column writes as its plain copy", {
  deferred <- as.character(1:10)
  d <- data.frame(x = 1:10)
  d$s <- deferred
  copy <- data.frame(x = 1:10, s = c("1", "2", "3", "4", "5", "6", "7", "8", "9", "10"))
  attr(d, "timestamp") <- attr(copy, "timestamp") <- "01 Jan 2026 00:00"
  expect_identical(bytes_of(d), bytes_of(copy))
})
