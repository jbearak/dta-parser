# Recompute medians from retained raw samples. No measured workload is executed.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
root <- args[[1L]]
grid <- read.csv(file.path(root, "grid.csv"), stringsAsFactors = FALSE)
measurements <- read.csv(file.path(root, "measurements.csv"), stringsAsFactors = FALSE)
keys <- c("rows", "columns", "groups", "kind", "operation")
stopifnot(nrow(grid) == 1L, nrow(measurements) == 2L,
          !anyDuplicated(grid[keys]), !anyDuplicated(measurements[c(keys, "mode")]))
checked <- 0L
for (i in seq_len(nrow(grid))) for (mode in c("safe_reference", "direct")) {
    matches <- measurements$mode == mode
    for (key in keys) matches <- matches & measurements[[key]] == grid[[key]][[i]]
    stopifnot(sum(matches) == 1L)
    row <- measurements[matches, ]
    raw <- readRDS(file.path(root, paste0("raw-timing-", i, "-", mode, ".rds")))
    samples <- as.numeric(raw$samples[[1L]])
    stopifnot(length(raw$samples) == 1L, length(samples) == 7L,
              all(is.finite(samples)), all(samples > 0),
              raw$iterations == 7L, row$iterations == 7L,
              raw$gc_count == row$gc_count,
              !inherits(raw$median, "bench_time"),
              isTRUE(all.equal(as.numeric(raw$median), median(samples) * 1000)),
              isTRUE(all.equal(as.numeric(raw$median), row$median_ms)),
              isTRUE(all.equal(as.numeric(raw$allocation), row$bench_allocated_bytes)))
    checked <- checked + 1L
}
cat("PASS", checked, "raw seven-sample medians, units, GC counts and allocation records\n")
