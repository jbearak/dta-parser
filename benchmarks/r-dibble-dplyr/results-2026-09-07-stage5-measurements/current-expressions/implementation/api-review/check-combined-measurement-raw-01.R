# Independent saved-record calculation only. No benchmark code is sourced.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance/candidate-a2d8b6a-measure-01"
grid <- read.csv(file.path(root, "grid.csv"), stringsAsFactors = FALSE)
rows <- read.csv(file.path(root, "measurements.csv"), stringsAsFactors = FALSE)
keys <- c("rows", "columns", "groups", "kind", "operation")
stopifnot(nrow(grid) == 25L, nrow(rows) == 50L)
checked <- list()
for (i in seq_len(nrow(grid))) {
    for (mode in c("safe_reference", "direct")) {
        same <- rows$mode == mode
        for (key in keys) same <- same & rows[[key]] == grid[[key]][i]
        stopifnot(sum(same) == 1L)
        row <- rows[same, , drop = FALSE]
        raw <- readRDS(file.path(root, paste0("raw-timing-", i, "-", mode, ".rds")))
        stopifnot(identical(names(raw), c("median", "samples", "iterations", "gc_count", "allocation")),
                  length(raw$samples) == 1L,
                  inherits(raw$samples[[1L]], "bench_time"),
                  !inherits(raw$median, "bench_time"))
        seconds <- as.double(raw$samples[[1L]])
        stopifnot(length(seconds) == 7L, all(is.finite(seconds)), all(seconds > 0),
                  raw$iterations == 7L, row$iterations == 7L)
        # Seven samples: the fourth sorted value is the median, in seconds.
        recomputed_ms <- sort(seconds)[4L] * 1000
        stopifnot(abs(recomputed_ms - as.double(raw$median)) <= max(1e-10, abs(recomputed_ms) * 1e-12),
                  abs(recomputed_ms - row$median_ms) <= max(1e-10, abs(recomputed_ms) * 1e-12),
                  as.double(raw$allocation) == row$bench_allocated_bytes,
                  raw$gc_count == row$gc_count,
                  row$gc_count >= 0, row$gc_count == floor(row$gc_count))
        checked[[length(checked) + 1L]] <- data.frame(case = i, mode,
            samples = length(seconds), recomputed_ms,
            csv_ms = row$median_ms, bench_allocated_bytes = as.double(raw$allocation),
            gc_count = as.double(raw$gc_count))
    }
}
result <- do.call(rbind, checked)
stopifnot(nrow(result) == 50L, sum(result$samples) == 350L)
write.table(result, stdout(), sep = "\t", row.names = FALSE, quote = FALSE)
cat("PASS: 50 saved records, 350 positive raw seconds samples, millisecond medians, allocations and GC counts.\n")

