# The Raven sidecar tells the editor that := evaluates i, by and value
# among d's columns. Raven itself is not needed to check it.

test_that("the Raven sidecar is installed and says what := evaluates", {
  path <- system.file("raven", "nse.toml", package = "datakit")
  expect_true(nzchar(path))
  skip_if_not_installed("RcppTOML")
  toml <- RcppTOML::parseTOML(path)
  expect_identical(toml$schema, 1L)
  expect_length(toml$operator, 1)
  expect_identical(toml$operator[[1]][c("name", "form", "masked_arguments")],
                   list(name = ":=", form = "subset-assign", masked_arguments = "by"))
  expect_null(toml$subset)
})
