#!/usr/bin/env Rscript
# Same runner for a baseline or candidate revision, with setup outside timing.
# DTATOOLS_BENCHMARK_REVISION defaults to HEAD. See README for the timing method.
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
repository <- normalizePath(file.path(dirname(script), "..", ".."))
source(file.path(repository, "benchmarks", "benchmark-common.R"))
helpers <- new.env()
source(file.path(repository, "benchmarks", "r-dibble-dplyr", "helpers.R"), local = helpers)
args <- commandArgs(TRUE)
count <- function(index, default) {
    if (length(args) < index) return(default)
    if (!grepl("^[1-9][0-9]*$", args[[index]])) stop("counts must be positive integers")
    as.integer(args[[index]])
}
n <- count(1, 100000L)
samples <- count(2, 50L)
wide <- count(3, 100L)
gc_mode <- Sys.getenv("DTATOOLS_BENCHMARK_GC", "none")
if (!gc_mode %in% c("none", "before")) stop("DTATOOLS_BENCHMARK_GC must be none or before")
invisible(gc.time(TRUE))
output <- if (length(args) >= 4L) args[[4L]] else tempfile("mutation-expanded-")
if (n < 5L || wide < 2L) stop("need at least five rows and two wide-table columns")
if (length(system2("git", c("-C", shQuote(repository), "status", "--short"), stdout = TRUE)))
    stop("Commit or remove changes before benchmarking")
revision <- Sys.getenv("DTATOOLS_BENCHMARK_REVISION", "HEAD")
sha <- system2("git", c("-C", shQuote(repository), "rev-parse", "--verify", "--end-of-options",
                       shQuote(paste0(revision, "^{commit}"))), stdout = TRUE)
if (length(sha) != 1L || !grepl("^[0-9a-f]{40}$", sha)) stop("invalid revision")
lib <- Sys.getenv("DTATOOLS_BENCH_LIB")
if (!nzchar(lib)) {
    lib <- tempfile("dtatools-expanded-library-")
    previous <- setwd(repository)
    status <- system2(file.path(R.home("bin"), "Rscript"),
                     vapply(c("benchmarks/r-dibble-dplyr/install.R", lib, sha), shQuote, character(1)))
    setwd(previous)
    if (status != 0L) stop("exact-source install failed")
    Sys.setenv(DTATOOLS_BENCH_LIB = lib)
}
benchmark_activate_library(c("dtatools", "bench", "data.table", "profmem"))
provenance <- helpers$validate_benchmark_install(lib, sha)
library(dtatools)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
runner_sha <- system2("git", c("-C", shQuote(repository), "rev-parse", "HEAD"), stdout = TRUE)
if (length(runner_sha) != 1L || !grepl("^[0-9a-f]{40}$", runner_sha)) stop("invalid runner revision")
metadata <- c(source_sha = sha, source_tree = provenance$source_tree,
              runner_sha = runner_sha,
              dtatools = as.character(packageVersion("dtatools")),
              data.table = as.character(packageVersion("data.table")),
              bench = as.character(packageVersion("bench")), R = R.version.string,
              platform = R.version$platform, host = paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "),
              rows = n, samples = samples, wide = wide, library = normalizePath(lib),
              gc = gc_mode,
              operations = Sys.getenv("DTATOOLS_BENCHMARK_OPERATIONS", "all"))
write.table(data.frame(key = names(metadata), value = unname(metadata)),
            file.path(output, "provenance.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)

# Expressions are evaluated directly in each fixture. The extra base eval()
# is included for every API and revision. No setup or assertion is timed.
operations <- list(
    set_row = quote(set_dta_values(d, "x", 3, rows = 5L)),
    set_whole = quote(set_dta_values(d, "x", 3)),
    set_expression = quote(set_dta_values(d, "x", abs(-3), rows = 5L)),
    set_create = quote(set_dta_values(d, "y", 3, create = TRUE)),
    set_reject = quote(tryCatch(set_dta_values(d, "x", 1000, rows = 5L), error = identity)),
    repl_row = quote(repl(d, x = 3, where = 5L)),
    repl_whole = quote(repl(d, x = 3)),
    repl_expression = quote(repl(d, x = x + 2, where = 5L)),
    repl_promote = quote(suppressMessages(repl(d, x = 1000, where = 5L))),
    repl_fused = quote(repl(d, x = 3, where = x > 0)),
    gen_whole = quote(gen(d, y = 3)),
    gen_row = quote(gen(d, y = 3, where = 5L)),
    gen_expression = quote(gen(d, y = x + 2)),
    bracket_row = quote(d[5L, x := 3]),
    bracket_whole = quote(d[, x := 3]),
    bracket_expression = quote(d[5L, x := x + 2]),
    bracket_promote = quote(d[5L, x := 1000]),
    bracket_create = quote(d[, y := 3]),
    bracket_create_expression = quote(d[, y := x + 2]),
    append_prebuilt = quote(dtatools:::.append_generated_column(d, "y", column)),
    data_table_row = quote(data.table::set(d, i = 5L, j = "x", value = 3)),
    data_table_whole = quote(data.table::set(d, j = "x", value = 3))
)
selected_operations <- Sys.getenv("DTATOOLS_BENCHMARK_OPERATIONS")
if (nzchar(selected_operations)) {
    selected_operations <- strsplit(selected_operations, ",", fixed = TRUE)[[1L]]
    if (anyDuplicated(selected_operations) || !all(selected_operations %in% names(operations)))
        stop("DTATOOLS_BENCHMARK_OPERATIONS must name distinct operations from the matrix")
    operations <- operations[selected_operations]
}
fixture <- function(operation, width, backing) {
    env <- new.env(parent = globalenv())
    compact <- operation %in% c("set_reject", "repl_promote", "bracket_promote", "repl_fused")
    columns <- setNames(rep(list(rep(1, n)), width), c("x", if (width > 1L) paste0("v", 2:width)))
    if (startsWith(operation, "data_table")) {
        env$d <- data.table::as.data.table(columns)
        # A retained column models externally shared payload on both sides.
        if (backing == "shared") env$holder <- env$d$x
    } else {
        if (compact) columns$x <- dta_byte(columns$x)
        env$d <- as_dibble(tibble::as_tibble(columns))
        # Use the same native setup on both revisions. Calling a public API
        # here would warm the baseline's general path but the candidate's
        # fast path, biasing the next timed general-path call.
        .Call(dtatools:::C_dtatools_patch_slot, env$d, 1L, NULL, 1, TRUE)
        if (backing == "shared") env$holder <- tibble::as_tibble(env$d)
        if (operation == "append_prebuilt") env$column <- dtatools:::.generated_column(
            3, NULL, n, generate = TRUE, carry_metadata = FALSE)
    }
    env
}
verify <- function(env, operation) {
    d <- env$d
    if (operation == "set_reject") stopifnot(all(as.double(d$x) == 1))
    else if (grepl("create|^gen|^append", operation)) {
        expected <- if (operation == "gen_row") replace(rep(NA_real_, n), 5L, 3) else rep(3, n)
        stopifnot(identical(as.double(d$y), expected))
        stopifnot(dta_storage_type(d$y) == if (grepl("expression", operation)) "double" else "float")
    } else {
        whole <- grepl("whole|fused", operation)
        value <- if (grepl("promote", operation)) 1000 else 3
        expected <- if (whole) rep(value, n) else replace(rep(1, n), 5L, value)
        stopifnot(identical(as.double(d$x), expected))
        if (grepl("promote", operation)) stopifnot(dta_storage_type(d$x) == "int")
    }
    if (exists("holder", env, inherits = FALSE) && !startsWith(operation, "data_table"))
        stopifnot(all(as.double(env$holder$x) == 1))
}
records <- list()
# Load the profiler's own helpers before measuring the first operation.
invisible(profmem::profmem(NULL))
for (width in c(1L, wide)) for (backing in c("private", "shared")) {
    for (operation in names(operations)) {
        call <- operations[[operation]]
        # Warm code and verify semantics with a disposable fixture.
        env <- fixture(operation, width, backing)
        eval(call, env)
        verify(env, operation)
        times <- numeric(samples)
        collected <- logical(samples)
        scratch <- copied <- numeric(samples)
        for (i in seq_len(samples)) {
            env <- fixture(operation, width, backing)
            if (gc_mode == "before") gc()
            .Call(dtatools:::C_dtatools_native_copy_stats, TRUE)
            gc_before <- sum(gc.time())
            times[[i]] <- as.numeric(bench::system_time(eval(call, env))[["real"]])
            collected[[i]] <- sum(gc.time()) > gc_before
            stats <- .Call(dtatools:::C_dtatools_native_copy_stats, FALSE)
            scratch[[i]] <- stats[["native_scratch_allocated"]]
            copied[[i]] <- stats[["mutation_target_copy"]]
        }
        verify(env, operation)
        env <- fixture(operation, width, backing)
        if (gc_mode == "before") gc()
        memory <- profmem::profmem(eval(call, env))
        verify(env, operation)
        records[[length(records) + 1L]] <- data.frame(
            operation, width, backing, median_seconds = median(times),
            gc_samples = sum(collected),
            median_without_gc_seconds = if (any(!collected)) median(times[!collected]) else NA_real_,
            p25_seconds = unname(quantile(times, .25)), p75_seconds = unname(quantile(times, .75)),
            r_bytes = sum(memory$bytes, na.rm = TRUE),
            native_scratch_bytes = median(scratch), target_copy_bytes = median(copied), samples)
    }
}
report <- do.call(rbind, records)
write.csv(report, file.path(output, "matrix.csv"), row.names = FALSE)

# Components are timed in isolation, not summed as a model of total latency.
# Private views are retained only for read/cast measurements and released
# before measuring a patch, so profiling cannot manufacture payload sharing.
d <- dibble(x = rep(1, n))
set_dta_values(d, "x", 1)
ns <- asNamespace("dtatools")
row <- 5L
value <- 3
scalar_quo <- rlang::new_quosure(value, emptyenv())
view <- .Call(ns$C_dtatools_mutation_column_view, d, 1L)
components <- bench::mark(
    shape = ns$.set_values_preflight(d),
    target = ns$.set_values_target(d, "x", FALSE),
    rows = ns$.set_values_rows(row, n),
    size = ns$.mutation_value_mode(value, row, n),
    cast = ns$.cast_replacement(value, view[[1L]], row, "scalar"),
    shared = .Call(ns$C_dtatools_shared_columns, d),
    capacity = ns$.prepare_column_operation(d, 2L),
    scalar_binding = ns$.mutation_scalar_binding(scalar_quo, d),
    generate = ns$.generated_column(value, NULL, n, generate = TRUE, carry_metadata = FALSE),
    check = FALSE, iterations = 500L, filter_gc = FALSE)
.Call(ns$C_dtatools_release_mutation_views, view)
view <- NULL
native <- bench::mark(
    patch = .Call(ns$C_dtatools_patch_slot, d, 1L, row, value, FALSE),
    view = { v <- .Call(ns$C_dtatools_mutation_column_view, d, 1L); .Call(ns$C_dtatools_release_mutation_views, v) },
    check = FALSE, iterations = 500L, filter_gc = FALSE)
component_report <- function(x) data.frame(component = as.character(x$expression),
    median_seconds = as.numeric(x$median), r_bytes = as.numeric(x$mem_alloc))
write.csv(rbind(component_report(components), component_report(native)),
          file.path(output, "components.csv"), row.names = FALSE)
cat("Results:", normalizePath(output), "\n")
print(report, row.names = FALSE)
