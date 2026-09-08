# Saved-data calculations only: no benchmark operation and no Rprof start.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
keys <- c("rows", "columns", "groups", "kind", "operation")
runs <- c("candidate-622-wide-minimum-01", "candidate-622-width-repeat-01")
records <- list()
for (name in runs) {
    path <- file.path(root, name)
    grid <- read.csv(file.path(path, "grid.csv"), stringsAsFactors = FALSE)
    measurements <- read.csv(file.path(path, "measurements.csv"), stringsAsFactors = FALSE)
    for (i in seq_len(nrow(grid))) for (mode in c("safe_reference", "direct")) {
        match <- measurements$mode == mode
        for (key in keys) match <- match & measurements[[key]] == grid[[key]][i]
        stopifnot(sum(match) == 1L)
        row <- measurements[match, , drop = FALSE]
        raw <- readRDS(file.path(path, paste0("raw-timing-", i, "-", mode, ".rds")))
        stopifnot(length(raw$samples) == 1L, inherits(raw$samples[[1L]], "bench_time"),
                  !inherits(raw$median, "bench_time"))
        seconds <- as.double(raw$samples[[1L]])
        stopifnot(length(seconds) == 7L, all(is.finite(seconds)), all(seconds > 0),
                  raw$iterations == 7L, row$iterations == 7L)
        ms <- sort(seconds)[4L] * 1000
        stopifnot(abs(ms - as.double(raw$median)) <= max(1e-10, abs(ms) * 1e-12),
                  abs(ms - row$median_ms) <= max(1e-10, abs(ms) * 1e-12),
                  as.double(raw$allocation) == row$bench_allocated_bytes,
                  raw$gc_count == row$gc_count, row$gc_count >= 0)
        records[[length(records) + 1L]] <- data.frame(run = name, case = i, mode,
            samples = length(seconds), median_ms = ms, bench_allocated_bytes = as.double(raw$allocation))
    }
}
records <- do.call(rbind, records)
stopifnot(nrow(records) == 14L, sum(records$samples) == 98L)
write.table(records, stdout(), sep = "\t", row.names = FALSE, quote = FALSE)
cat("PASS: 14 saved timing records, 98 seconds samples, millisecond medians, allocations and GC counts.\n")

path <- file.path(root, "candidate-622-wide-profile-01")
checks <- dget(file.path(path, "checks.R"))
for (mode in c("safe_reference", "direct")) {
    raw_path <- file.path(path, paste0(mode, ".Rprof"))
    lines <- readLines(raw_path, warn = FALSE)
    stopifnot(identical(lines[1L], "GC profiling: sample.interval=1000"),
              all(startsWith(lines[-1L], '"')))
    summary <- summaryRprof(raw_path)
    stored <- readRDS(file.path(path, paste0(mode, "-summary.rds")))
    stopifnot(identical(summary, stored), summary$sample.interval == 0.001,
              isTRUE(all.equal(summary$sampling.time, (length(lines) - 1L) * 0.001)))
    for (part in c("self", "total")) {
        table <- summary[[paste0("by.", part)]]
        expected <- data.frame(frame = rownames(table), table, row.names = NULL)
        observed <- read.csv(file.path(path, paste0(mode, "-by-", part, ".csv")), stringsAsFactors = FALSE)
        stopifnot(isTRUE(all.equal(observed, expected, tolerance = 1e-12)))
    }
    record <- checks[[mode]]
    stopifnot(record$profiled, record$calls == 2000L, record$interval_seconds == 0.001,
              record$source_and_output_checks == "pass")
    for (phase in c("cleanup_before", "cleanup_after")) {
        stopifnot("error" %in% record[[phase]]$classes,
                  grepl("Obsolete data mask", record[[phase]]$message, fixed = TRUE))
    }
    stopifnot(identical(readRDS(file.path(path, paste0(mode, "-source-before.rds"))),
                        readRDS(file.path(path, paste0(mode, "-source-after.rds")))))
    cat("PASS profile", mode, "raw_stack_samples", length(lines) - 1L,
        "recorded_calls", record$calls, "summary_and_both_CSV_tables_exact\n")
}
