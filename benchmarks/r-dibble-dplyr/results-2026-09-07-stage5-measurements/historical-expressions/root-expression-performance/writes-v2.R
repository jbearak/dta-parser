source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
qualify <- identical(Sys.getenv("DTA_EXPRESSION_WRITE_PHASE"), "write_qualify")
iterations <- 7L
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
source(Sys.getenv("DTA_EXPRESSION_CASES"))
source(Sys.getenv("DTA_OWNED_HELPER"))
source(Sys.getenv("DTA_EXPRESSION_WRITE_CASES"))
if (!identical(normalizePath(find.package("dtatools")),
               normalizePath(file.path(lib, "dtatools")))) stop("Wrong installation")
if (!qualify) {
    if (!capabilities("profmem")) stop("R memory profiling required")
    suppressPackageStartupMessages(library(bench))
}
records <- list()
states <- list()
samples <- list()
save_state <- function(pair, phase, mode, iteration) {
    state <- expression_write_state(pair$result, phase)
    states[[length(states) + 1L]] <<- cbind(data.frame(rows = pair$rows, mode,
        case = pair$case, iteration), state)
    write.csv(do.call(rbind, states), file.path(output, "write-states.csv"), row.names = FALSE)
    state
}
for (mode in if (qualify) c("direct", "legacy", "safe_reference") else c("safe_reference", "direct")) {
    # Use an independent fixture for column metadata and owned identity checks.
    # Neither extraction may perturb the pairs whose writes are measured.
    metadata_pair <- expression_write_prepare(12L, mode, "computed_first")
    expected_metadata <- lapply(seq_along(metadata_pair$result), function(i) attributes(metadata_pair$result[[i]]))
    stopifnot(all(vapply(seq_along(metadata_pair$result), function(i) {
        !is.null(owned_native("C_dtatools_owned_info", metadata_pair$result[[i]]))
    }, logical(1))))
    rm(metadata_pair)
    for (case in expression_write_cases) {
        # Warm dispatch and verify the complete pair on a separate small fixture.
        warm <- expression_write_prepare(12L, mode, case)
        before <- save_state(warm, "qualify_before", mode, 0L)
        native_before <- owned_stats()
        warm$action()
        native <- owned_stats() - native_before
        after <- save_state(warm, "qualify_after", mode, 0L)
        expression_write_check_state(warm, before, after, native)
        expression_write_check_values(warm, expected_metadata)
        rm(warm, before, after)
        if (qualify) {
            records[[length(records) + 1L]] <- data.frame(mode, case, passed = TRUE)
            write.csv(do.call(rbind, records), file.path(output, "qualification.csv"), row.names = FALSE)
            cat("PASS", mode, case, "write setup, budgets, values, metadata, aliases\n")
            next
        }
        for (n in c(100000L, 1000000L)) {
            pair <- expression_write_prepare(n, mode, case)
            invisible(gc())
            before <- save_state(pair, "profile_before", mode, 0L)
            profile <- owned_profile(pair$action)
            after <- save_state(pair, "profile_after", mode, 0L)
            native <- profile$metrics[startsWith(names(profile$metrics), "native_")]
            names(native) <- sub("_bytes$", "", sub("^native_", "", names(native)))
            expression_write_check_state(pair, before, after, native)
            expression_write_check_values(pair, expected_metadata)
            metrics <- profile$metrics
            rm(pair, before, after, profile)
            elapsed_ms <- numeric(iterations)
            for (iteration in seq_len(iterations)) {
                pair <- expression_write_prepare(n, mode, case)
                invisible(gc())
                before <- save_state(pair, "timing_before", mode, iteration)
                native_before <- owned_stats()
                elapsed <- bench::system_time(pair$action())
                native <- owned_stats() - native_before
                after <- save_state(pair, "timing_after", mode, iteration)
                expression_write_check_state(pair, before, after, native)
                expression_write_check_values(pair, expected_metadata)
                elapsed_ms[[iteration]] <- as.numeric(elapsed[["real"]]) * 1000
                samples[[length(samples) + 1L]] <- data.frame(rows = n, mode, case, iteration,
                    elapsed_ms = elapsed_ms[[iteration]])
                write.csv(do.call(rbind, samples), file.path(output, "write-samples.csv"), row.names = FALSE)
                rm(pair, before, after)
            }
            records[[length(records) + 1L]] <- cbind(data.frame(rows = n, mode, case,
                median_ms = median(elapsed_ms), iterations), as.data.frame(as.list(metrics)))
            write.csv(do.call(rbind, records), file.path(output, "write-measurements.csv"), row.names = FALSE)
            cat("MEASURED", mode, case, n, "rows", median(elapsed_ms), "ms\n")
        }
    }
}
validate_benchmark_install(lib, sha)
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dput(list(source = sha, qualification_only = qualify, session = sessionInfo(),
    note = "Each timed action uses a fresh pair. Setup, state inspection and all value checks are outside timing. Rprofmem and native counters overlap and must not be added. This experiment does not measure retained memory or RSS."),
    file = file.path(output, "session.R"))
