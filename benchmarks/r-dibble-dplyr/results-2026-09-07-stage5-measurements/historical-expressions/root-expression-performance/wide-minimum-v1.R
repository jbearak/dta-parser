# Fixtures, checks and snapshots stay outside timing. Write costs are a separate experiment.
source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
iterations <- as.integer(Sys.getenv("DTA_EXPRESSION_ITERATIONS", "7"))
if (is.na(iterations) || iterations < 3L) stop("At least three iterations required")
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
source(Sys.getenv("DTA_EXPRESSION_CASES"))
source(Sys.getenv("DTA_OWNED_HELPER"))
if (!identical(normalizePath(find.package("dtatools")),
               normalizePath(file.path(lib, "dtatools")))) stop("Wrong installation")
if (!capabilities("profmem")) stop("R memory profiling required")
suppressPackageStartupMessages(library(bench))
grid <- expression_grid()
grid <- grid[grid$kind == "ungrouped" & grid$rows == 100000L &
    grid$columns == 64L & grid$operation == "retain", , drop = FALSE]
stopifnot(nrow(grid) == 1L)
# Minimize only observation count from the confirmed wide-retain case.
grid$rows <- 12L
write.csv(grid, file.path(output, "grid.csv"), row.names = FALSE)
# Unexpected warnings must retain a concrete error and reject qualification.
options(warn = 2)
records <- list()
state_records <- list()
record_state <- function(data, phase, item, mode) {
    state <- expression_state(data, phase)
    description <- item[rep(1L, nrow(state)), , drop = FALSE]
    rownames(description) <- NULL
    state_records[[length(state_records) + 1L]] <<- cbind(description,
        mode = rep(mode, nrow(state)), state)
    write.csv(do.call(rbind, state_records), file.path(output, "source-states.csv"), row.names = FALSE)
}
for (i in seq_len(nrow(grid))) {
    item <- grid[i, ]
    reference_snapshot <- NULL
    for (mode in c("safe_reference", "direct")) {
        cat("RUN", i, mode, item$kind, item$operation, item$rows, "rows\n")
        data <- expression_fixture(item$rows, item$columns, item$groups, item$kind)
        record_state(data, "before_oracle", item, mode)
        sink <- new.env(parent = emptyenv())
        operation <- expression_operation(item$operation, item$kind, mode, sink)
        # Independent arithmetic and metadata checks precede every measurement.
        checked <- operation(data)
        expression_check(data, checked, item$operation, item$kind, item$rows, sink)
        snapshot <- expression_snapshot(checked)
        if (mode == "safe_reference") reference_snapshot <- snapshot else {
            expression_equal(snapshot, reference_snapshot, "full safe reference parity")
        }
        rm(checked, snapshot)
        sink$values <- list()
        invisible(gc())
        record_state(data, "before_profile", item, mode)
        profile <- owned_profile(function() operation(data))
        expression_check(data, profile$value, item$operation, item$kind, item$rows, sink)
        metrics <- profile$metrics
        rm(profile)
        sink$values <- list()
        invisible(gc())
        record_state(data, "before_timing", item, mode)
        mark <- bench::mark(operation(data), iterations = iterations,
                            check = FALSE, filter_gc = FALSE, time_unit = "ms")
        # bench 1.1.4 summary(time_unit = "ms") returns plain numeric ms.
        # Raw time samples remain bench_time seconds; verify that relationship.
        stopifnot(!inherits(mark$median, "bench_time"),
                  isTRUE(all.equal(as.numeric(mark$median),
                                   median(as.numeric(mark$time[[1L]])) * 1000)))
        saveRDS(list(median = mark$median, samples = mark$time, iterations = mark$n_itr,
                     gc_count = mark$n_gc, allocation = mark$mem_alloc),
                file.path(output, paste0("raw-timing-", i, "-", mode, ".rds")))
        records[[length(records) + 1L]] <- cbind(item, data.frame(mode,
            actual_input_columns = ncol(data), median_ms = as.numeric(mark$median),
            bench_allocated_bytes = as.numeric(mark$mem_alloc), iterations = mark$n_itr,
            gc_count = mark$n_gc), as.data.frame(as.list(metrics)))
        write.csv(do.call(rbind, records), file.path(output, "measurements.csv"), row.names = FALSE)
        cat("MEASURED", i, "of", nrow(grid), mode, item$kind, item$operation,
            item$rows, "rows", as.numeric(mark$median), "ms\n")
        record_state(data, "after_timing", item, mode)
        expression_equal(as.double(data$x), rep(c(1, 2, 3, 4), length.out = item$rows), "source values after timing")
        expression_equal(as.character(data$s), rep(c("aa", "b"), length.out = item$rows), "source strings after timing")
        rm(data, sink, operation, mark, metrics)
        invisible(gc())
    }
    rm(reference_snapshot)
    invisible(gc())
}
validate_benchmark_install(lib, sha)
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dput(list(source = sha, DLL = getLoadedDLLs()[["dtatools"]][["path"]],
          session = sessionInfo(), note = "Rprofmem and native counters overlap; never add them. bench allocation is another measurement of cumulative R allocation. Retained memory and whole-process RSS are separate experiments."),
     file = file.path(output, "session.R"))
