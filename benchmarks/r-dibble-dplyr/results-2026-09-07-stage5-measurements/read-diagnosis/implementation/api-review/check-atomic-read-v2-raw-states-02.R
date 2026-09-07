# Independent saved records only. No benchmark driver or package is loaded.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
names <- c(unlist(lapply(1:3, function(i) sprintf("%s-read-repeat-v2-%02d", c("baseline-ec10", "candidate-a2d8b6a"), i))),
           unlist(lapply(1:3, function(i) sprintf("%s-arrow-repeat-v2-%02d", c("baseline-f622", "candidate-a2d8b6a"), i))),
           paste0(c("baseline-ec10", "candidate-a2d8b6a"), "-read-minimum-v2-01"))
series <- sample_count <- states_count <- 0L
for (name in names) {
    path <- file.path(root, name)
    rows <- read.csv(file.path(path, "owned-atomic.csv"), stringsAsFactors = FALSE)
    expected_depth <- if (startsWith(name, "baseline-ec10")) 0L else 1L
    for (i in seq_len(nrow(rows))) {
        row <- rows[i, , drop = FALSE]
        raw <- readRDS(file.path(path, paste0("raw-timing-", i, ".rds")))
        stopifnot(identical(names(raw), c("median_ms", "samples", "allocation", "iterations", "gc_count")),
                  !inherits(raw$median_ms, "bench_time"), length(raw$samples) == 1L,
                  inherits(raw$samples[[1]], "bench_time"), raw$iterations == 7L, row$iterations == 7L)
        values <- as.double(raw$samples[[1]])
        stopifnot(length(values) == 7L, all(is.finite(values)), all(values > 0))
        ms <- sort(values)[4] * 1000
        stopifnot(abs(ms - raw$median_ms) < max(1e-10, abs(ms) * 1e-12),
                  abs(ms - row$median_ms) < max(1e-10, abs(ms) * 1e-12),
                  as.double(raw$allocation) == row$bench_allocated_bytes,
                  raw$gc_count == row$gc_count)
        states <- readRDS(file.path(path, paste0("source-states-", i, ".rds")))
        stopifnot(identical(names(states), c("before", "before_profile", "before_timing")))
        initial <- vapply(states[[1]], function(x) x$backing, "")
        initial_private <- vapply(states[[1]], function(x) x$backing_private, logical(1))
        for (stage in states) {
            stopifnot(length(stage) == row$columns,
                      identical(vapply(stage, function(x) x$backing, ""), initial),
                      identical(vapply(stage, function(x) x$backing_private, logical(1)), initial_private))
            for (column in stage) {
                stopifnot(column$depth == expected_depth, !column$exposed,
                          column$handle_shared, is.logical(column$backing_private), length(column$backing_private) == 1L, !is.na(column$backing_private),
                          column$bytes == row$rows * if (row$kind == "declared_character") 8 else 4)
                states_count <- states_count + 1L
            }
        }
        series <- series + 1L
        sample_count <- sample_count + length(values)
    }
    cat("PASS", name, nrow(rows), "series, raw median/unit/allocation/GC and saved source states\n")
}
stopifnot(series == 174L, sample_count == 1218L, states_count == 3672L)
cat("PASS 174 series, 1218 raw samples, 3672 source-column states\n")
