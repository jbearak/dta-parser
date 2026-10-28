# The fixtures live in the dta-parser repository (compat/fixtures), not in
# the package; tests that need them skip when the package is tested
# outside a checkout.
fixture_dir <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", "..", "compat", "fixtures"),
                             mustWork = FALSE)

fixtures <- function() {
  testthat::skip_if_not(dir.exists(fixture_dir), "compat/fixtures is not here")
  Sys.glob(file.path(fixture_dir, "*.dta"))
}
