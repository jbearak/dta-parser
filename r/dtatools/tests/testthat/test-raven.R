# dtatools re-exports :=, so it ships the same Raven sidecar as datakit.

test_that("the Raven sidecar is installed and matches datakit's", {
  path <- system.file("raven", "nse.toml", package = "dtatools")
  expect_true(nzchar(path))
  expect_true("`:=`" %in% paste0("`", getNamespaceExports("dtatools"), "`"))
  expect_identical(readLines(path), readLines(system.file("raven", "nse.toml", package = "datakit")))
})
