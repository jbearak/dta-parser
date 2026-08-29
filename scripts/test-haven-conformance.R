fail <- function(...) stop(..., call. = FALSE)

required <- c(
    "callr", "dplyr", "dtatools", "haven", "httpuv", "rlang", "testthat",
    "tibble"
)
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0L) {
    fail("Missing Haven conformance dependencies: ", paste(missing, collapse = ", "))
}

root <- normalizePath(getwd(), mustWork = TRUE)
suite <- file.path(root, "tests", "r-haven", "testthat")
if (!file.exists(file.path(root, "r-package", "dtatools", "DESCRIPTION")) ||
    !dir.exists(suite)) {
    fail("Run this script from the repository root")
}

Sys.setenv(DTA_TOOLS_ROOT = root)
testthat::test_dir(
    suite,
    reporter = "summary",
    package = "dtatools",
    load_package = "installed",
    stop_on_failure = TRUE
)
