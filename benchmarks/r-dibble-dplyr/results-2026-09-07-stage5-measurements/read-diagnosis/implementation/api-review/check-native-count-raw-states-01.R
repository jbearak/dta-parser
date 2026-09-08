# Read saved ordinary records only. No benchmark/package/helper/DLL is loaded.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
total_samples <- total_states <- 0L
for (repeat_id in 1:3) for (tag in c("baseline-ec10", "candidate-a2d8b6a")) {
    run <- sprintf("%s-read-count-control-v1-%02d", tag, repeat_id)
    folder <- file.path(root, run)
    metrics <- read.csv(file.path(folder, "read-count-control.csv"))
    states <- readRDS(file.path(folder, "source-states.rds"))
    stopifnot(nrow(metrics) == 24L, length(states) == 24L)
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
                  raw$gc_count == metrics$gc_count[i], raw$gc_count >= 0)
        state <- states[[i]]
        stopifnot(identical(state$operation, metrics$operation[i]), identical(state$kind, metrics$kind[i]), state$rows == metrics$rows[i])
        phases <- state[c("before", "before_profile", "before_timing", "after")]
        stopifnot(length(phases) == 4L, all(vapply(phases, identical, logical(1), phases[[1L]])))
        for (phase in phases) {
            stopifnot(length(phase) == 1L)
            x <- phase[[1L]]
            stopifnot(x$handle_shared, identical(x$backing_private, tag == "candidate-a2d8b6a" && metrics$kind[i] != "logical"), !x$exposed,
                      x$depth == if (tag == "baseline-ec10") 0L else 1L,
                      x$bytes == 4 * metrics$rows[i], nzchar(x$backing), nzchar(x$handle))
            total_states <- total_states + 1L
        }
        total_samples <- total_samples + length(seconds)
    }
    for (start in seq(1L, 21L, 4L)) {
        stopifnot(all(vapply(states[start:(start + 3L)], function(x) identical(x$before, states[[start]]$before), logical(1))))
    }
    visits <- readRDS(file.path(folder, "untimed-native-visits.rds"))
    stopifnot(length(visits) == 6L)
    visit_keys <- character()
    for (v in visits) {
        stopifnot(v$kind %in% c("logical", "factor", "ordered"), v$rows %in% c(100000L, 1000000L),
                  identical(v$expected, as.integer(v$rows * 0.75)),
                  identical(v$native_count_and_visits, c(as.double(v$expected), as.double(v$rows))))
        visit_keys <- c(visit_keys, paste(v$kind, v$rows))
    }
    stopifnot(length(unique(visit_keys)) == 6L, all(metrics$expected_count == metrics$rows * 0.75))
    tiny <- readRDS(file.path(folder, "tiny-checks.rds"))
    stopifnot(length(tiny) == 24L)
    tiny_keys <- character()
    expected <- c(empty = 0L, nonmissing = 2L, all_missing = 0L, mixed = 3L)
    for (t in tiny) {
        stopifnot(t$kind %in% c("logical", "factor", "ordered"), t$case %in% names(expected),
                  t$container %in% c("ordinary", "table_column"), identical(t$expected, unname(expected[t$case])),
                  identical(t$type, if (t$kind == "logical") "logical" else "integer"))
        attrs <- if (t$kind == "logical") list(label = "Tiny count control") else list(
            levels = c("a", "b", "unused"), class = if (t$kind == "ordered") c("ordered", "factor") else "factor", label = "Tiny count control")
        stopifnot(identical(t$attributes, attrs))
        tiny_keys <- c(tiny_keys, paste(t$kind, t$case, t$container))
    }
    stopifnot(length(unique(tiny_keys)) == 24L)
    cat("PASS", run, "24 series / 168 raw seconds samples / 96 unchanged state records\n")
}
stopifnot(total_samples == 1008L, total_states == 576L)
cat("TOTAL 144 series / 1008 samples / 576 state records\n")
