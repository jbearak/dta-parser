# Extracted from test-data-table-compatibility.R:286

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "dtatools", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
data <- data.frame(x = stata_byte(c(1, 2)))
path <- tempfile(fileext = ".dta")
on.exit(unlink(path), add = TRUE)
save_dta(data, path)
result <- read_dta(path, output = "data.table")
dataset_label(result) <- "Replaced label"
expect_true(dtatools:::.ordinary_data_table(result))
expect_identical(dataset_label(result), "Replaced label")
result[, extra := 1]
