args <- commandArgs(TRUE)
stopifnot(length(args) == 4L, !file.exists(args[[4L]]))
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[2L]], args[[3L]])
mode <- args[[3L]]
output <- args[[4L]]
stopifnot(dir.create(output))
dependencies <- c(atomic_runner_paths,
    "/private/tmp/dta-direct-stage4-validation/filter-planning-diagnosis.R")
dependency_hashes <- tools::md5sum(dependencies)
stopifnot(!anyNA(dependency_hashes))
dll <- getLoadedDLLs()[["dtatools"]][["path"]]
dll_hash <- tools::md5sum(dll)
cat("DEVELOPMENT DIAGNOSIS: existing filter and gather boundaries\n")
cat("source", args[[2L]], "library", library_path, "\n")
print(dll_hash)
print(dependency_hashes)
ns <- asNamespace("dtatools")
records <- list()
rows <- 1000000L
for (kind in c("logical", "factor", "ordered")) {
    x <- atomic_fixture(kind, rows, 8L)
    frozen <- atomic_frozen(x, kind)
    before <- atomic_state(x, mode)
    snapshot <- ns$.reference_snapshot(x)
    columns <- ns$.data_columns(snapshot)
    raw <- tibble::new_tibble(atomic_raw(kind, rows, 8L), nrow = rows)
    locations <- seq.int(2L, rows, by = 2L)
    expected <- atomic_expected(frozen, rows = locations)
    sliced <- vctrs::vec_slice(snapshot, locations)
    operations <- list(
        full_filter = function() dplyr::filter(x, seq_len(n()) %% 2L == 0L),
        snapshot_filter = function() dplyr::filter(snapshot, seq_len(n()) %% 2L == 0L),
        raw_filter = function() dplyr::filter(raw, seq_len(n()) %% 2L == 0L),
        snapshot_slice = function() vctrs::vec_slice(snapshot, locations),
        raw_slice = function() vctrs::vec_slice(raw, locations),
        validated_batch = function() ns$.gather_dta_columns(columns, locations),
        close_only = function() ns$.close_dibble(x, sliced))
    for (name in names(operations)) {
        operation <- operations[[name]]
        value <- operation()
        stopifnot(identical(atomic_columns(value), expected))
        rm(value)
        profile <- atomic_profile(operation)
        stopifnot(identical(atomic_columns(profile$value), expected))
        metrics <- profile$metrics
        rm(profile)
        invisible(gc())
        mark <- bench::mark(operation(), iterations = 21L, check = TRUE,
            filter_gc = FALSE)
        stopifnot(identical(atomic_columns(mark$result[[1L]]), expected))
        result <- cbind(data.frame(kind, operation = name,
            median_ms = as.numeric(mark$median) * 1000,
            r_bytes = as.numeric(mark$mem_alloc)), as.data.frame(as.list(metrics)))
        records[[length(records) + 1L]] <- result
        print(result[c("kind", "operation", "median_ms", "r_bytes",
                       "native_owned_capture_bytes")])
        rm(mark)
        atomic_preserved(x, frozen)
        atomic_unchanged_backings(before, x, mode)
    }
    # Sampling is separate from the medians above. These profiles intentionally
    # retain ordinary delegation and contain no implementation workaround.
    for (name in c("full_filter", "snapshot_slice", "validated_batch")) {
        path <- file.path(output, paste0(kind, "-", name, ".Rprof"))
        operation <- operations[[name]]
        Rprof(path, interval = 0.0001)
        tryCatch(for (i in seq_len(100L)) invisible(operation()),
                 finally = Rprof(NULL))
        capture.output(summaryRprof(path), file = paste0(path, ".txt"))
        atomic_preserved(x, frozen)
        atomic_unchanged_backings(before, x, mode)
    }
    # Trace callback routing after every timing and sample has finished.
    trace(".gather_dta_columns", tracer = quote(cat("TRACE package batch\n")),
          where = ns, print = FALSE)
    trace("vec_slice_altrep", tracer = quote(cat("TRACE vctrs ALTREP",
          typeof(x), typeof(i), dtatools:::.is_altrep(i), length(i), "\n")),
          where = asNamespace("vctrs"), print = FALSE)
    tryCatch(invisible(dplyr::filter(x, seq_len(n()) %% 2L == 0L)), finally = {
        untrace("vec_slice_altrep", where = asNamespace("vctrs"))
        untrace(".gather_dta_columns", where = ns)
    })
    atomic_preserved(x, frozen)
    atomic_unchanged_backings(before, x, mode)
    rm(x, snapshot, columns, raw, sliced, operations)
    invisible(gc())
}
validate_benchmark_install(library_path, args[[2L]])
stopifnot(identical(dll_hash, tools::md5sum(dll)),
          identical(dependency_hashes, tools::md5sum(dependencies)))
write.csv(do.call(rbind, records), file.path(output, "results.csv"), row.names = FALSE)
cat("PASS source/DLL/dependency/value/metadata/backing guards before and after\n")
