# compat/fixed_width's synthetic file, read as asciiSetupReader and haven
# read it (compat/expected/fixed_width.json, ADR 0005): the Rust core's
# tests check the same file, and these check the R columns built from it.
# The file is in the repository, not the package, so this runs from a
# checkout only.

compat <- function(...) test_path("..", "..", "..", "..", "compat", ...)

oracle_read <- function(recodes) {
  skip_if_not(file.exists(compat("expected", "fixed_width.json")), "no checkout of dta-parser")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("haven")
  list(
    ours = read_fixed_width(compat("fixed_width", "synthetic.dat"), compat("fixed_width", "synthetic.sas"),
                            recodes = recodes),
    theirs = jsonlite::fromJSON(compat("expected", "fixed_width.json"), simplifyVector = FALSE)
  )
}

# A column's labels, empty when it has none.
labels_of <- function(x) {
  l <- attr(x, "labels", exact = TRUE)
  if (is.null(l)) stats::setNames(double(), character()) else l
}

alnum <- function(s) gsub("[^A-Za-z0-9]", "", s)

# A JSON value as ours should hold it: NA for null, the letter for
# {"missing": ".b"} (in `tags`), else the number.
expected_values <- function(values) {
  num <- vapply(values, function(y) if (is.numeric(y)) as.double(y) else NA_real_, 0)
  tag <- vapply(values, function(y) if (is.list(y)) sub("^\\.", "", y$missing) else NA_character_, "")
  list(num = num, tag = tag)
}

test_that("setup mode reads what asciiSetupReader reads", {
  r <- oracle_read("setup")
  expect_null(attr(r$ours, "warnings"))
  expect_identical(nrow(r$ours), as.integer(r$theirs$nobs))
  expect_setequal(names(r$ours), vapply(r$theirs$variables, `[[`, "", "name"))
  for (v in r$theirs$variables) {
    x <- r$ours[[v$name]]
    # asciiSetupReader turns labels into names, adding the variable's name
    # where two labels are the same.
    label <- alnum(attr(x, "label"))
    expect_true(alnum(v$label) %in% c(label, paste0(label, v$name)), label = v$name)
    if (is.character(x)) {
      expect_identical(as.vector(x), vapply(v$values, function(y) if (is.null(y)) "" else y, ""), label = v$name)
      next
    }
    want <- expected_values(v$values)
    expect_equal(as.double(x), want$num, tolerance = 1e-9, label = v$name)
    recoded <- unlist(v$recoded)
    kept <- Filter(function(p) !(p[[1]] %in% recoded), v$labels)
    labels <- labels_of(x)
    expect_identical(unname(labels), as.double(vapply(kept, `[[`, 0, 1)), label = v$name)
    expect_identical(names(labels), vapply(kept, `[[`, "", 2), label = v$name)
  }
})

test_that("tagged mode gives haven's tagged NAs, as the oracle lists them", {
  r <- oracle_read("tagged")
  for (v in r$theirs$variables) {
    if (is.null(v$tagged)) next
    x <- r$ours[[v$name]]
    want <- expected_values(v$tagged)
    expect_equal(ifelse(is.na(want$tag), as.double(x), NA_real_), want$num, tolerance = 1e-9, label = v$name)
    expect_identical(haven::na_tag(as.double(x)), want$tag, label = v$name)
    labels <- labels_of(x)
    key <- ifelse(is.na(haven::na_tag(unname(labels))), as.character(unname(labels)), paste0(".", haven::na_tag(unname(labels))))
    want_key <- vapply(v$tagged_labels, function(p) if (is.numeric(p[[1]])) as.character(as.double(p[[1]])) else p[[1]], "")
    want_text <- vapply(v$tagged_labels, `[[`, "", 2)
    expect_identical(sort(paste(key, names(labels))), sort(paste(want_key, want_text)), label = v$name)
  }
})
