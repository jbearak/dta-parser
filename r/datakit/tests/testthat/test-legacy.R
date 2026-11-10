# The legacy fixtures (compat/parquet/legacy): files R's and TypeScript's
# datakit wrote, with what read_parquet() read from each when they were
# made. The reader must still read the same, bit for bit, so .a to .z
# keep their letters.

legacy_dir <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", "..", "compat", "parquet", "legacy"),
                            mustWork = FALSE)

test_that("the legacy fixtures read as they did when they were made", {
  testthat::skip_if_not(dir.exists(legacy_dir), "compat/parquet/legacy is not here")
  source(file.path(legacy_dir, "readings.R"), local = TRUE)
  files <- Sys.glob(file.path(legacy_dir, "*.parquet"))
  expect_gt(length(files), 0)
  for (f in files) {
    name <- sub("\\.parquet$", "", basename(f))
    now <- legacy_readings(f)
    then <- readRDS(file.path(legacy_dir, paste0(name, ".read.rds")))
    expect_identical(names(now), names(then))
    for (k in names(then)) {
      expect(identical(now[[k]], then[[k]], num.eq = FALSE, single.NA = FALSE),
             paste0(name, ": the ", k, " reading differs"))
    }
  }
})
