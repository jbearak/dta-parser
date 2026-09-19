#!/usr/bin/env Rscript
# Per-call cost of the package's by-reference value verbs against
# data.table::set(), the loop-friendly assigner ADR 0041 declines to add.
# Report-only: evidence, not a gate. Run from a clean checkout with the
# package under test installed in DTATOOLS_BENCH_LIB:
#
#   DTATOOLS_BENCH_LIB=/path/to/lib Rscript --vanilla \
#       benchmarks/r-cell-assignment/run.R [rows] [iterations] [loop_rows]

script_dir <- dirname(normalizePath(sub(
    "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
)))
source(file.path(script_dir, "..", "benchmark-common.R"))

parse_count <- function(value, default) {
    if (is.na(value)) return(default)
    if (!grepl("^[1-9][0-9]*$", value)) stop("counts must be positive integers")
    as.integer(value)
}
arguments <- commandArgs(trailingOnly = TRUE)
rows <- parse_count(arguments[1L], 100000L)
iterations <- parse_count(arguments[2L], 200L)
loop_rows <- parse_count(arguments[3L], 1000L)
if (rows < 2L) stop("rows must be at least 2, so a single-row write has a neighbour")
if (loop_rows > rows) stop("loop_rows must not exceed rows")
single_row <- min(5L, rows)
neighbour <- if (single_row < rows) single_row + 1L else single_row - 1L

# The library is bound to one git revision by the exact-source installer,
# which records a provenance sidecar the validator checks against the
# installed files. Without DTATOOLS_BENCH_LIB the runner installs HEAD of a
# clean checkout into a temporary library itself, so a result is attributed
# only to the source it was built from.
repository <- normalizePath(file.path(script_dir, "..", ".."))
helpers <- new.env()
source(file.path(repository, "benchmarks", "r-dibble-dplyr", "helpers.R"), local = helpers)
source_sha <- system2("git", c("-C", shQuote(repository), "rev-parse", "HEAD"), stdout = TRUE)
if (length(system2("git", c("-C", shQuote(repository), "status", "--short"), stdout = TRUE))) {
    stop("Commit or remove changes before benchmarking")
}
benchmark_library <- Sys.getenv("DTATOOLS_BENCH_LIB")
if (!nzchar(benchmark_library)) {
    benchmark_library <- tempfile("dtatools-cell-assignment-")
    original_directory <- setwd(repository)
    status <- system2(file.path(R.home("bin"), "Rscript"),
        vapply(c("benchmarks/r-dibble-dplyr/install.R", benchmark_library, source_sha),
               shQuote, character(1)))
    setwd(original_directory)
    if (!identical(status, 0L)) stop("Could not install the benchmark source package")
    Sys.setenv(DTATOOLS_BENCH_LIB = benchmark_library)
}
benchmark_activate_library(c("dtatools", "bench", "data.table"))
provenance <- helpers$validate_benchmark_install(benchmark_library_path(), source_sha)

library(dtatools)
d <- dibble(id = seq_len(rows), x = as.double(seq_len(rows)))
dt <- data.table::data.table(id = seq_len(rows), x = as.double(seq_len(rows)))
name <- "x"

# Both sides receive the row as a position, so the comparison is the
# assignment path alone and neither side pays for a predicate scan.
# Correctness before timing: each write lands the same value.
repl(d, !!name := 2); stopifnot(all(as.double(d$x) == 2))
data.table::set(dt, j = "x", value = 2); stopifnot(all(dt$x == 2))
repl(d, x = 3, where = !!single_row)
stopifnot(as.double(d$x)[single_row] == 3, as.double(d$x)[neighbour] == 2)
data.table::set(dt, i = single_row, j = "x", value = 3)
stopifnot(dt$x[single_row] == 3, dt$x[neighbour] == 2)

single <- bench::mark(
    repl_whole_column = repl(d, !!name := 2),
    repl_single_row = repl(d, x = 3, where = !!single_row),
    set_whole_column = data.table::set(dt, j = "x", value = 2),
    set_single_row = data.table::set(dt, i = single_row, j = "x", value = 3),
    check = FALSE, iterations = iterations, filter_gc = FALSE
)
loops <- bench::mark(
    repl_row_loop = for (i in seq_len(loop_rows)) repl(d, x = 9, where = !!i),
    set_row_loop = for (i in seq_len(loop_rows)) data.table::set(dt, i = i, j = "x", value = 9),
    check = FALSE, iterations = 3L, filter_gc = FALSE
)
stopifnot(all(as.double(d$x)[seq_len(loop_rows)] == 9), all(dt$x[seq_len(loop_rows)] == 9))

report <- rbind(
    data.frame(call = as.character(single$expression), median = as.numeric(single$median),
               allocation = as.numeric(single$mem_alloc), iterations = iterations),
    data.frame(call = as.character(loops$expression), median = as.numeric(loops$median),
               allocation = as.numeric(loops$mem_alloc), iterations = 3L)
)
fmt_time <- function(s) ifelse(s < 1e-3, sprintf("%.1f µs", s * 1e6),
                        ifelse(s < 1, sprintf("%.1f ms", s * 1e3), sprintf("%.2f s", s)))
fmt_bytes <- function(b) ifelse(b < 1024, sprintf("%.0f B", b),
                         ifelse(b < 1024^2, sprintf("%.1f KB", b / 1024), sprintf("%.1f MB", b / 1024^2)))
cat("| Call | Median | Allocation | Iterations |\n| --- | ---: | ---: | ---: |\n")
for (i in seq_len(nrow(report))) {
    cat(sprintf("| `%s` | %s | %s | %d |\n", report$call[i], fmt_time(report$median[i]),
                fmt_bytes(report$allocation[i]), report$iterations[i]))
}
cat("\n")
cat("benchmark_source_sha\t", source_sha, "\n", sep = "")
cat("benchmark_source_tree\t", provenance$source_tree, "\n", sep = "")
cat("rows\t", rows, "\nloop_rows\t", loop_rows, "\n", sep = "")
cat("dtatools\t", as.character(packageVersion("dtatools")), "\n", sep = "")
cat("data.table\t", as.character(packageVersion("data.table")), "\n", sep = "")
cat("bench\t", as.character(packageVersion("bench")), "\n", sep = "")
cat("R\t", R.version$major, ".", R.version$minor, "\t", R.version$platform, "\n", sep = "")
cat("host\t", Sys.info()[["sysname"]], " ", Sys.info()[["release"]], " ", Sys.info()[["machine"]], "\n", sep = "")
