#!/usr/bin/env Rscript
# Allocation-only first-case probe; the original failed driver is unchanged.
args <- commandArgs(TRUE)
stopifnot(length(args) == 5L)
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], args[[4L]])
output <- args[[2L]]
mode <- args[[4L]]
stopifnot(as.integer(args[[5L]]) == 7L, capabilities("profmem"), dir.exists(output))
setup <- Sys.getenv("DTA_ATOMIC_SETUP")
stopifnot(setup %in% c("cold", "rename"))
options(warn = 2)
writeLines(atomic_identity(args[[3L]], library_path, mode),
           file.path(output, "owned-atomic-session.txt"))
suppressPackageStartupMessages(library(bench))
kind <- "declared_character"
rows <- 100000L
columns <- 8L

# This is the sole difference between the two fresh-process probe modes.
# The measured source does not exist yet and cannot be touched by this warm-up.
if (setup == "rename") {
    invisible(dplyr::rename(atomic_fixture(kind, 4L), changed = c01))
}

data <- atomic_fixture(kind, rows, columns)
frozen <- atomic_frozen(data, kind)
reference <- tibble::new_tibble(atomic_raw(kind, rows, columns), nrow = rows)
input_path <- tempfile(fileext = ".dta")
input_arrow <- tempfile(fileext = ".arrow")
setup_before <- atomic_state(data, mode)
atomic_write_dta(data, input_path, kind)
save_arrow(data, input_arrow, compression = "uncompressed", threads = 1L)
atomic_unchanged_backings(setup_before, data, mode)
operation <- function(x) anyNA(x$c01)
check_read <- function(value) stopifnot(identical(value, operation(reference)))
before <- atomic_state(data, mode)
actual <- operation(data)
atomic_unchanged_backings(before, data, mode)
check_read(actual)
before_profile <- atomic_state(data, mode)
profile <- atomic_profile(function() operation(data))
atomic_unchanged_backings(before_profile, data, mode)
check_read(profile$value)
invisible(gc())
before_timing <- atomic_state(data, mode)
saveRDS(list(before = before, before_profile = before_profile, before_timing = before_timing),
        file.path(output, "source-states-1.rds"))
# Allocation diagnosis omits bench timing in both modes. The read is checked
# again, leaving the original retained result alive through the selector.
check_read(operation(data))
atomic_unchanged_backings(before_timing, data, mode)
atomic_preserved(data, frozen)
fork_before <- atomic_state(data, mode)
fork <- atomic_profile(function() dplyr::rename(data, changed = c01))
write.csv(as.data.frame(as.list(fork$metrics)), file.path(output, "fork-metrics.csv"),
          row.names = FALSE)
print(fork$metrics)
expected_fork <- atomic_expected(frozen, names = c("changed", names(data)[-1L]))
atomic_check(fork$value, frozen, expected_fork)
output_info <- atomic_state(fork$value, mode)
atomic_unchanged_backings(fork_before, data, mode)
if (mode == "candidate") stopifnot(identical(atomic_backings(fork_before), atomic_backings(output_info)))
saveRDS(list(source = fork_before, result = output_info), file.path(output, "fork-states.rds"))
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
atomic_selector_gate(fork$metrics, kind, mode)
atomic_preserved(data, frozen)
validate_benchmark_install(library_path, args[[3L]])
unlink(c(input_path, input_arrow))
cat("PASS allocation-only first-case probe", setup, "\n")
