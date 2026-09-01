# Extracted from test-data-table-compatibility.R:273

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "dtatools", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
.datatable.aware <- TRUE
data <- data.frame(x = stata_byte(c(1, 2)), y = c(3, 4))
dataset_label(data) <- "Example label"
path <- tempfile(fileext = ".dta")
on.exit(unlink(path), add = TRUE)
save_dta(data, path)
result <- read_dta(path, output = "data.table")
expect_true(dtatools:::.ordinary_data_table(result))
expect_identical(dataset_label(result), "Example label")
result[, doubled := y * 2]
expect_identical(result$doubled, c(6, 8))
