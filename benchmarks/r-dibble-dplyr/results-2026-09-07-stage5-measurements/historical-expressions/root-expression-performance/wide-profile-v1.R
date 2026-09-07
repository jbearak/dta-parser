# Sampling diagnosis for the unchanged 12-row, 64-column retain operation.
# No namespace tracing, function replacement or evaluator instrumentation.
source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
enabled <- identical(Sys.getenv("DTA_PROFILE_RUN"), "1")
calls <- 2000L
interval <- 0.001
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
source(Sys.getenv("DTA_EXPRESSION_CASES"))
source(Sys.getenv("DTA_OWNED_HELPER"))
stopifnot(identical(normalizePath(find.package("dtatools")),
    normalizePath(file.path(lib, "dtatools"))))
if (enabled && !capabilities("Rprof")) stop("R sampling profiling is unavailable")
options(warn = 2)
grid <- expression_grid()
grid <- grid[grid$kind == "ungrouped" & grid$rows == 100000L &
    grid$columns == 64L & grid$operation == "retain", , drop = FALSE]
stopifnot(nrow(grid) == 1L)
grid$rows <- 12L
item <- grid[1L, ]
write.csv(grid, file.path(output, "grid.csv"), row.names = FALSE)

cleanup_check <- function(data, mode) {
    capture <- new.env(parent = emptyenv())
    dots <- rlang::quos(.cleanup_probe = { capture$read <- function() x; x })
    result <- expression_mutate(data, dots, mode = mode)
    expression_equal(as.double(result$.cleanup_probe),
        rep(c(1, 2, 3, 4), length.out = 12L), "cleanup probe values")
    condition <- tryCatch(capture$read(), error = identity)
    if (!inherits(condition, "error") ||
        !grepl("Obsolete data mask", conditionMessage(condition), fixed = TRUE)) {
        stop("Deferred mask read was not invalidated")
    }
    list(classes = class(condition), message = conditionMessage(condition))
}

profile_loop <- function(operation, data, calls) {
    for (i in seq_len(calls)) invisible(operation(data))
    invisible(NULL)
}

states <- list()
record_state <- function(data, phase, mode) {
    state <- expression_state(data, phase)
    state$mode <- mode
    states[[length(states) + 1L]] <<- state
    write.csv(do.call(rbind, states), file.path(output, "source-states.csv"), row.names = FALSE)
}
records <- list()
reference_snapshot <- NULL
for (mode in c("safe_reference", "direct")) {
    data <- expression_fixture(item$rows, item$columns, item$groups, item$kind)
    record_state(data, "before_checks", mode)
    before <- expression_snapshot(data)
    saveRDS(before, file.path(output, paste0(mode, "-source-before.rds")))
    sink <- new.env(parent = emptyenv())
    operation <- expression_operation(item$operation, item$kind, mode, sink)
    checked <- operation(data)
    expression_check(data, checked, item$operation, item$kind, item$rows, sink)
    snapshot <- expression_snapshot(checked)
    if (mode == "safe_reference") reference_snapshot <- snapshot else
        expression_equal(snapshot, reference_snapshot, "full safe reference parity")
    cleanup_before <- cleanup_check(data, mode)
    rm(checked, snapshot)
    sink$values <- list()
    invisible(gc())
    record_state(data, "before_profile", mode)
    if (enabled) {
        path <- file.path(output, paste0(mode, ".Rprof"))
        if (file.exists(path)) stop("Fresh raw profile required")
        cat("PROFILE", mode, calls, "calls\n")
        Rprof(path, interval = interval, gc.profiling = TRUE,
            memory.profiling = FALSE, line.profiling = FALSE)
        tryCatch(profile_loop(operation, data, calls), finally = Rprof(NULL))
        summary <- summaryRprof(path)
        if (summary$sampling.time <= 0) stop("Sampling profile contains no samples")
        saveRDS(summary, file.path(output, paste0(mode, "-summary.rds")))
        write.csv(data.frame(frame = rownames(summary$by.self), summary$by.self,
            row.names = NULL), file.path(output, paste0(mode, "-by-self.csv")), row.names = FALSE)
        write.csv(data.frame(frame = rownames(summary$by.total), summary$by.total,
            row.names = NULL), file.path(output, paste0(mode, "-by-total.csv")), row.names = FALSE)
    }
    record_state(data, "after_profile", mode)
    checked <- operation(data)
    expression_check(data, checked, item$operation, item$kind, item$rows, sink)
    after <- expression_snapshot(data)
    expression_equal(after, before, "source values and metadata after profile")
    saveRDS(after, file.path(output, paste0(mode, "-source-after.rds")))
    cleanup_after <- cleanup_check(data, mode)
    record_state(data, "after_checks", mode)
    records[[mode]] <- list(profiled = enabled, calls = if (enabled) calls else 0L,
        interval_seconds = interval, cleanup_before = cleanup_before,
        cleanup_after = cleanup_after, source_and_output_checks = "pass")
    dput(records, file.path(output, "checks.R"))
    rm(data, operation, sink, checked, before, after, cleanup_before, cleanup_after)
    invisible(gc())
}
validate_benchmark_install(lib, sha)
namespaces <- setdiff(loadedNamespaces(), "base")
paths <- vapply(namespaces, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespaces, path = unname(paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dput(list(source = sha, DLL = getLoadedDLLs()[["dtatools"]][["path"]],
    session = sessionInfo(), profiled = enabled, calls = calls, interval_seconds = interval,
    scope = "Sampled stacks under profiling overhead. No elapsed-time or performance-acceptance claim. Raw profiles are retained; GC samples remain included. Fixtures, oracles, ownership and cleanup checks are outside profiling."),
    file.path(output, "session.R"))
