args <- commandArgs(TRUE)
if (length(args) != 6L || !args[[5L]] %in% c("baseline", "candidate") ||
    !args[[6L]] %in% c("qualify", "measure"))
    stop("usage: worker.R LIBRARY PROBE_DIRECTORY ROUND OUTPUT.csv baseline|candidate qualify|measure")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
probe_path <- normalizePath(args[[2L]], mustWork = TRUE)
round <- as.integer(args[[3L]])
variant <- args[[5L]]
measure <- args[[6L]] == "measure"
stopifnot(!is.na(round), round > 0L)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                    file.path(library_path, "dtatools")), capabilities("profmem"))
if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required")
probe <- dyn.load(file.path(probe_path, "materialization_probe.so"))
entries <- getDLLRegisteredRoutines(probe)$.Call
force_symbol <- entries$force_batch
matches_symbol <- entries$matches_batch
native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
compact <- dtatools:::.is_unmaterialized_numeric_altrep
copy_stats <- function() native("C_dtatools_native_copy_stats", FALSE)[["compact_copy"]]
compatibility_stats <- function() native("C_dtatools_owned_numeric_info", NULL)[["compatibility_bytes"]]
value_hash <- function(x) digest::digest(writeBin(x, raw(), size = 8L, endian = "little"),
                                        algo = "sha256", serialize = FALSE)
width_bytes <- c(byte = 1, int = 2, long = 4, float = 4)
rows <- list()
interval_rows <- list()
case <- 0L

for (n in 1000000L) for (width in names(width_bytes)) {
    finite <- switch(width, byte = c(-100, -3, 0, 7, 100),
                     int = c(-32000, -3, 0, 7, 32000),
                     long = c(-2000000000, -3, 0, 7, 2000000000),
                     float = c(-1048576.5, -0.125, -0, 0.125, 1048576.5))
    missing <- c(NA_real_, tagged_missing(letters))
    constructor <- get(paste0("dta_", width), asNamespace("dtatools"))
    backings <- c("constructed", "retained")
    if (round %% 2L == 0L) backings <- rev(backings)
    for (backing in backings) {
        case <- case + 1L
        permutations <- list(c("none", "sparse", "dense"), c("none", "dense", "sparse"),
            c("sparse", "none", "dense"), c("sparse", "dense", "none"),
            c("dense", "none", "sparse"), c("dense", "sparse", "none"))
        density_order <- permutations[[(round - 1L) %% 6L + 1L]]
        for (density in density_order) {
            sharing <- "aliased"
            expected <- rep_len(finite, n)
            if (density == "dense") expected <- rep_len(c(finite, missing), n)
            if (density == "sparse") {
                positions <- seq.int(1L, n, by = 16384L)
                expected[positions] <- rep_len(missing, length(positions))
            }
            expected_hash <- value_hash(expected)
            missing_count <- sum(is.na(expected))
            chunk_rows <- 8191L
            source <- constructor(expected)
            if (backing == "retained")
                source <- native("C_dtatools_owned_numeric_freeze", source, chunk_rows)
            make_batch <- function(count) {
                # The rooted source remains compact. Every fresh metadata
                # handle must allocate and decode its own double output.
                targets <- lapply(seq_len(count), function(j)
                    native("C_dtatools_metadata_copy", source))
                list(targets = targets, aliases = list(source))
            }
            check_before <- function(batch) {
                stopifnot(all(vapply(batch$targets, compact, logical(1))),
                          all(vapply(batch$aliases, compact, logical(1))),
                          isTRUE(.Call(matches_symbol, batch$aliases, expected)))
                for (value in batch$targets) {
                    retained <- native("C_dtatools_owned_numeric_info", value)
                    stopifnot(identical(retained[["owned"]] == 1, backing == "retained"))
                    if (backing == "retained") stopifnot(retained[["chunks"]] > 1)
                    # Plain targets share the rooted compact source.
                    # Region checks inspect that source before each batch. Retained ownership
                    # and sharing are checked separately from mutability.
                    private <- native("C_dtatools_mutation_info", list(value), 1L)[["backing_private"]]
                    if (backing == "constructed" && !identical(private, sharing == "private"))
                        stop("unexpected backing sharing for ", n, "/", width, "/", backing, "/", sharing)
                }
                invisible(NULL)
            }
            check_after <- function(batch) {
                stopifnot(!any(vapply(batch$targets, compact, logical(1))),
                          all(vapply(batch$aliases, compact, logical(1))),
                          isTRUE(.Call(matches_symbol, batch$targets, expected)),
                          isTRUE(.Call(matches_symbol, batch$aliases, expected)))
                invisible(NULL)
            }
            expected_copy <- 0
            # Warm dispatch and independently qualify the standard guarded
            # DATAPTR_RO route before any profiler or retained interval.
            warm <- make_batch(1L)
            check_before(warm)
            before_copy <- copy_stats()
            before_compatibility <- compatibility_stats()
            .Call(force_symbol, warm$targets)
            compact_copy_bytes <- copy_stats() - before_copy
            compatibility_bytes <- compatibility_stats() - before_compatibility
            stopifnot(compact_copy_bytes == expected_copy, compatibility_bytes == 0)
            check_after(warm)
            # Mutating the decoded target must not alter an older compact alias.
            changed <- expected
            changed[[1L]] <- 99
            invisible(native("C_dtatools_mutate_first_numeric_altrep", warm$targets[[1L]], 99))
            stopifnot(isTRUE(.Call(matches_symbol, warm$targets, changed)),
                      isTRUE(.Call(matches_symbol, warm$aliases, expected)),
                      all(vapply(warm$aliases, compact, logical(1))))
            warm <- changed <- NULL
            # Two separate one-call diagnostics: Rprofmem's logged allocation
            # bytes and the R vector heap's high-water delta. Neither is timed.
            allocation <- make_batch(1L)
            check_before(allocation)
            profile_path <- tempfile("materialization-profile-")
            gc()
            Rprofmem(profile_path, threshold = 0)
            .Call(force_symbol, allocation$targets)
            Rprofmem(NULL)
            profile <- readLines(profile_path, warn = FALSE)
            unlink(profile_path)
            sizes <- as.double(sub(" .*", "", profile[grepl("^[0-9]+ ", profile)]))
            stopifnot(length(sizes) > 0L, all(is.finite(sizes)), all(sizes > 0))
            r_profiled_allocation_bytes <- sum(sizes)
            r_largest_allocation_bytes <- max(sizes)
            r_profiled_allocations <- length(sizes)
            check_after(allocation)
            allocation <- NULL
            highwater <- make_batch(1L)
            check_before(highwater)
            gc()
            heap_before <- gc(reset = TRUE)
            .Call(force_symbol, highwater$targets)
            heap_after <- gc()
            peak_vcell_bytes <- max(0, heap_after["Vcells", "max used"] -
                                          heap_before["Vcells", "used"]) * 8
            live_vcell_delta_bytes <- (heap_after["Vcells", "used"] -
                                      heap_before["Vcells", "used"]) * 8
            check_after(highwater)
            highwater <- NULL
            iterations <- batches <- 0L
            cpu_seconds <- elapsed_seconds <- gc_cpu_seconds <- 0
            timed_compact_copy_bytes <- 0
            batch_cpu <- batch_wall <- numeric()
            # 32 distinct outputs total 256 MB; the shared compact input
            # contributes at most another 4 MB. Include automatic GC inside
            # timing, and retain each individual interval's real resolution.
            batch_size <- 32L
            if (measure) {
                gc.time(TRUE)
                repeat {
                    batch <- make_batch(batch_size)
                    check_before(batch)
                    gc()
                    copies_before <- copy_stats()
                    compatibility_before <- compatibility_stats()
                    gc_before <- gc.time()
                    started <- proc.time()
                    .Call(force_symbol, batch$targets)
                    elapsed <- proc.time() - started
                    gc_elapsed <- gc.time() - gc_before
                    added <- copy_stats() - copies_before
                    stopifnot(added == batch_size * expected_copy,
                              compatibility_stats() == compatibility_before)
                    timed_compact_copy_bytes <- timed_compact_copy_bytes + added
                    check_after(batch)
                    iterations <- iterations + batch_size
                    batches <- batches + 1L
                    interval_cpu <- elapsed[["user.self"]] + elapsed[["sys.self"]]
                    interval_wall <- elapsed[["elapsed"]]
                    interval_gc <- sum(gc_elapsed[1:2])
                    batch_cpu[[batches]] <- interval_cpu
                    batch_wall[[batches]] <- interval_wall
                    cpu_seconds <- cpu_seconds + interval_cpu
                    elapsed_seconds <- elapsed_seconds + interval_wall
                    gc_cpu_seconds <- gc_cpu_seconds + interval_gc
                    interval_rows[[length(interval_rows) + 1L]] <- data.frame(round, n, width, backing, density,
                        sharing, batch = batches, handles = batch_size, cpu_seconds = interval_cpu,
                        elapsed_seconds = interval_wall, gc_cpu_seconds = interval_gc,
                        compact_copy_bytes = added)
                    batch <- NULL
                    if (min(cpu_seconds, elapsed_seconds) >= .15) break
                    if (batches >= 1000L) stop("materialization intervals did not reach the retained interval target")
                }
            }
            rows[[length(rows) + 1L]] <- data.frame(round, case, n, width, backing, density, sharing,
                order = match(density, density_order), backing_order = match(backing, backings), missing_count, phase = if (measure) "timing" else "qualification",
                iterations, batches, batch_size, cpu_seconds, elapsed_seconds, gc_cpu_seconds,
                min_batch_cpu_seconds = if (measure) min(batch_cpu) else NA_real_,
                max_batch_cpu_seconds = if (measure) max(batch_cpu) else NA_real_,
                min_batch_elapsed_seconds = if (measure) min(batch_wall) else NA_real_,
                max_batch_elapsed_seconds = if (measure) max(batch_wall) else NA_real_,
                zero_cpu_batches = sum(batch_cpu == 0), zero_wall_batches = sum(batch_wall == 0),
                compact_payload_bytes = n * width_bytes[[width]], double_payload_bytes = n * 8,
                compact_copy_bytes, compatibility_bytes, timed_compact_copy_bytes,
                r_profiled_allocation_bytes, r_largest_allocation_bytes, r_profiled_allocations,
                peak_vcell_bytes, live_vcell_delta_bytes, source_sha256 = expected_hash,
                result_sha256 = expected_hash, alias_independent = TRUE,
                source_unmaterialized_before = TRUE, source_unmaterialized_after = TRUE,
                targets_unmaterialized_before = TRUE, targets_materialized_after = TRUE,
                retained_chunks = if (backing == "retained") ceiling(n / chunk_rows) else 0)
        }
    }
}
write.csv(do.call(rbind, rows), args[[4L]], row.names = FALSE)
if (measure) write.csv(do.call(rbind, interval_rows), paste0(args[[4L]], ".intervals.csv"), row.names = FALSE)
cat(length(rows), "qualified compact decode observations\n")
