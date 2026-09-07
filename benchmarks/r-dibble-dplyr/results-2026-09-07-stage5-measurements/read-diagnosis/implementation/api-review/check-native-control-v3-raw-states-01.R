# Read saved ordinary records only. No benchmark/package/helper/DLL is loaded.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
total_samples <- total_states <- 0L
for (repeat_id in 1:3) for (tag in c("baseline-ec10", "candidate-a2d8b6a")) {
    run <- sprintf("%s-read-control-v3-%02d", tag, repeat_id)
    folder <- file.path(root, run)
    metrics <- read.csv(file.path(folder, "read-control.csv"))
    states <- readRDS(file.path(folder, "source-states.rds"))
    stopifnot(nrow(metrics) == 8L, length(states) == 8L)
    for (i in seq_len(nrow(metrics))) {
        raw <- readRDS(file.path(folder, sprintf("raw-timing-%d.rds", i)))
        stopifnot(length(raw$samples) == 1L,
                  identical(class(raw$samples[[1L]]), c("bench_time", "numeric")))
        seconds <- as.numeric(raw$samples[[1L]])
        stopifnot(length(seconds) == 7L, all(is.finite(seconds)), all(seconds > 0),
                  isTRUE(all.equal(median(seconds) * 1000, raw$median_ms, tolerance = 1e-12)),
                  isTRUE(all.equal(raw$median_ms, metrics$median_ms[i], tolerance = 1e-12)),
                  identical(as.numeric(raw$allocation), as.numeric(metrics$bench_allocated_bytes[i])),
                  raw$iterations == metrics$iterations[i], raw$iterations == 7L,
                  raw$gc_count == metrics$gc_count[i], raw$gc_count == 0)
        state <- states[[i]]
        stopifnot(identical(state$operation, metrics$operation[i]), state$rows == metrics$rows[i])
        phases <- state[c("before", "before_profile", "before_timing", "after")]
        stopifnot(length(phases) == 4L, all(vapply(phases, identical, logical(1), phases[[1L]])))
        for (phase in phases) {
            stopifnot(length(phase) == 1L)
            x <- phase[[1L]]
            stopifnot(x$handle_shared, !x$backing_private, !x$exposed,
                      x$depth == if (tag == "baseline-ec10") 0L else 1L,
                      x$bytes == 8 * metrics$rows[i], nzchar(x$backing), nzchar(x$handle))
            total_states <- total_states + 1L
        }
        total_samples <- total_samples + length(seconds)
    }
    for (start in c(1L, 5L)) {
        stopifnot(all(vapply(states[start:(start + 3L)], function(x) identical(x$before, states[[start]]$before), logical(1))))
    }
    cat("PASS", run, "8 series / 56 raw seconds samples / 32 unchanged state records\n")
}
stopifnot(total_samples == 336L, total_states == 192L)
cat("TOTAL 48 series / 336 samples / 192 state records\n")
