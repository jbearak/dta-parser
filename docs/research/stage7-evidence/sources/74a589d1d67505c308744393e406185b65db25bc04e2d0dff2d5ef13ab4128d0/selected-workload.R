# Whole Stage7 operations. Profiled/timed regions exclude expectations and checks.
args <- commandArgs(TRUE)
stopifnot(length(args) == 5L)
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], "candidate")
output <- normalizePath(args[[2L]], mustWork = TRUE)
iterations <- as.integer(args[[4L]])
row_counts <- as.integer(strsplit(args[[5L]], ",", fixed = TRUE)[[1L]])
support <- Sys.getenv("DTA_STAGE7_SUPPORT")
source(file.path(support, "workloads-v1.R"))
source(file.path(support, "reference-v1.R"))
source(file.path(support, "validation-v2.R"))
schemas <- dget(file.path(support, "schemas.R"))
routes <- strsplit(Sys.getenv("DTA_STAGE7_ROUTES"), ",", fixed = TRUE)[[1L]]
stopifnot(identical(routes, "public") ||
    identical(routes, c("public", "predecessor_safe_reference")))
if ("predecessor_safe_reference" %in% routes) stage7_reference_start(library_path)
stopifnot(iterations >= 3L, !anyNA(row_counts), length(row_counts) > 0L,
    all(row_counts >= 256L), capabilities("profmem"))
suppressPackageStartupMessages(library(bench))
writeLines(c(atomic_identity(args[[3L]], library_path, "candidate"),
    "scope: first-input-call and warmed allocation passes, seven GC-inclusive whole-operation times in the full grid",
    "first allocation pass precedes value validation; timed calls follow full validation and may read exposed source backings",
    "fresh grouped source for each shape/route; group construction is untimed; first-input-call is not a cold process",
    "fixed safe reference only executes in predecessor4d07; legacy public nesting has a known foreign-write defect",
    "metadata schemas from retained predecessor tiny outputs; all-column values and group indices use independent fixture math",
    "Rprofmem/native bytes are separate overlapping observations, never summed"), file.path(output, "session.txt"))

profile <- function(operation, stem) {
    path <- file.path(output, paste0(stem, "-Rprofmem.log"))
    stopifnot(!file.exists(path))
    on.exit(Rprofmem(NULL), add = TRUE)
    before <- c(owned_stats(), atomic_scans())
    Rprofmem(path)
    value <- operation()
    Rprofmem(NULL)
    delta <- c(owned_stats(), atomic_scans()) - before
    lines <- readLines(path, warn = FALSE)
    events <- grepl("^[0-9]+ :", lines)
    stopifnot(all(events | grepl("^new page:", lines)))
    sizes <- as.numeric(sub(" .*", "", lines[events]))
    list(value = value, metrics = c(r_allocated_bytes = sum(sizes),
        r_largest_allocation_bytes = max(c(0, sizes)), delta))
}

# Native observations return scalar/address fields only. Never serialize payloads.
stage7_states <- function(value, path = "table") {
    records <- list()
    visit <- function(frame, path) {
        stopifnot(is.data.frame(frame))
        for (i in seq_along(frame)) {
            column <- .subset2(frame, i)
            here <- paste(path, names(frame)[[i]], sep = "/")
            if (typeof(column) == "list") {
                for (j in seq_along(column)) {
                    child <- .subset2(column, j)
                    if (is.data.frame(child)) visit(child, paste0(here, "[", j, "]"))
                }
                prototype <- attr(column, "ptype", exact = TRUE)
                if (is.data.frame(prototype)) visit(prototype, paste0(here, "/ptype"))
            } else {
                info <- owned_native("C_dtatools_mutation_info", frame, as.integer(i))
                owned <- owned_native("C_dtatools_owned_info", column)
                records[[length(records) + 1L]] <<- cbind(data.frame(path = here,
                    type = typeof(column), length = length(column), owned = !is.null(owned)),
                    as.data.frame(info))
                if (!is.null(owned)) stopifnot(owned$depth == 1L,
                    owned$bytes == length(column) * switch(typeof(column),
                        integer = 4, logical = 4, double = 8, character = .Machine$sizeof.pointer))
            }
        }
    }
    visit(value, path)
    do.call(rbind, records)
}

records <- list()
run_case <- function(rows, columns, groups, workload, route) {
    input <- stage7_fixture(rows, columns, groups)
    source_schema <- schemas[[paste(columns, "source", sep = "-")]]
    result_schema <- schemas[[paste(columns, if (groups == 1L) 1L else 4L, workload, sep = "-")]]
    stopifnot(identical(stage7_schema(input), source_schema))
    initial <- stage7_states(input)
    # Integer input becomes compact Stata long behind a metadata wrapper.
    # Its materialization may change depth/bytes; ordinary owned columns retain
    # their handle kind, byte size and one-level backing throughout.
    expected_owned <- !names(input) %in% sprintf("c%02d", seq.int(7L, columns, by = 8L))
    stopifnot(nrow(initial) == columns + 1L, identical(initial$owned, expected_owned),
        all(initial$depth == 1L))
    invoke <- function() stage7_workload(input, workload, route)
    check <- function(value) {
        stage7_check_output(value, rows, columns, groups, workload, result_schema)
        stage7_check_source(input, rows, columns, groups, source_schema)
    }
    stem <- paste(rows, columns, groups, workload, route, sep = "-")
    states <- list()
    record_state <- function(step, value = NULL) {
        current <- stage7_states(input, "source")
        stopifnot(identical(current$handle, initial$handle),
            identical(current$owned, expected_owned),
            all(current$depth[expected_owned] == 1L),
            identical(current$bytes[expected_owned], initial$bytes[expected_owned]),
            all(current$depth[!expected_owned] %in% c(0L, 1L)),
            all(current$bytes[!expected_owned] %in% c(rows * 4, rows * 8)))
        if (!is.null(value)) current <- rbind(current, stage7_states(value, "result"))
        states[[length(states) + 1L]] <<- cbind(data.frame(step), current)
        write.csv(do.call(rbind, states), file.path(output, paste0(stem, "-states.csv")), row.names = FALSE)
    }
    record_state("initial")
    first <- profile(invoke, paste0(stem, "-first-input-call"))
    record_state("after_first_operation", first$value)
    check(first$value)
    record_state("after_first_validation", first$value)
    first_metrics <- first$metrics
    rm(first)
    invisible(gc())
    warm <- profile(invoke, paste0(stem, "-warmed-call"))
    record_state("after_warmed_operation", warm$value)
    check(warm$value)
    record_state("after_warmed_validation", warm$value)
    warm_metrics <- warm$metrics
    rm(warm)
    invisible(gc())
    record_state("before_timing")
    mark <- bench::mark(invoke(), iterations = iterations, check = TRUE, filter_gc = FALSE)
    record_state("after_timing", mark$result[[1L]])
    check(mark$result[[1L]])
    record_state("after_final_validation", mark$result[[1L]])
    times <- as.numeric(mark$time[[1L]])
    gc_events <- as.data.frame(mark$gc[[1L]])
    stopifnot(length(times) == iterations, mark$n_itr == iterations, nrow(gc_events) == iterations)
    write.csv(cbind(data.frame(iteration = seq_along(times), seconds = times), gc_events),
        file.path(output, paste0(stem, "-times.csv")), row.names = FALSE)
    metrics <- c(stats::setNames(first_metrics, paste0("first_", names(first_metrics))),
        stats::setNames(warm_metrics, paste0("warm_", names(warm_metrics))))
    row <- cbind(data.frame(rows, columns, groups, workload, route,
        median_ms = as.numeric(mark$median) * 1000, iterations = mark$n_itr,
        gc_count = mark$n_gc, bench_allocated_bytes = as.numeric(mark$mem_alloc),
        values_metadata_groups_source = TRUE), as.data.frame(as.list(metrics)))
    records[[length(records) + 1L]] <<- row
    write.csv(do.call(rbind, records), file.path(output, "operations.csv"), row.names = FALSE)
    print(row[c("rows", "columns", "groups", "workload", "route", "median_ms",
        "first_r_allocated_bytes", "warm_r_allocated_bytes")])
    invisible(NULL)
}

shapes <- expand.grid(rows = row_counts, columns = c(8L, 16L), groups = c(16L, 128L),
    workload = stage7_workload_names, stringsAsFactors = FALSE)
shapes <- rbind(shapes, data.frame(rows = max(row_counts), columns = 8L, groups = 1L,
    workload = stage7_workload_names))
for (i in seq_len(nrow(shapes))) {
    shape <- shapes[i, ]
    selected_routes <- if (i %% 2L) rev(routes) else routes
    for (route in selected_routes) {
        run_case(shape$rows, shape$columns, shape$groups, shape$workload, route)
        invisible(gc())
    }
}
stopifnot(length(records) == nrow(shapes) * length(routes))
validate_benchmark_install(library_path, args[[3L]])
cat("All measured outputs passed independent values, metadata, groups, prototypes and source-preservation checks.\n")
