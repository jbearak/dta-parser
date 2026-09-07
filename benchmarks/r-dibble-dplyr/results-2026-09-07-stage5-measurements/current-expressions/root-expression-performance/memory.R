# One isolated process per source/mode/row count. The outer /usr/bin/time -l
# observation includes startup, fixtures, GC, checks and the complete workload.
source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
rows <- as.integer(Sys.getenv("DTA_EXPRESSION_ROWS"))
mode <- Sys.getenv("DTA_EXPRESSION_MODE")
if (is.na(rows) || !rows %in% c(100000L, 1000000L)) stop("Unsupported memory row count")
if (!mode %in% c("direct", "safe_reference")) stop("Unsupported memory mode")
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
source(Sys.getenv("DTA_EXPRESSION_CASES"))
source(Sys.getenv("DTA_OWNED_HELPER"))
if (!identical(normalizePath(find.package("dtatools")),
               normalizePath(file.path(lib, "dtatools")))) stop("Wrong installation")
sink <- new.env(parent = emptyenv())
operation <- expression_operation("pipeline_five", "ungrouped", mode, sink)
invisible(operation(expression_fixture(12L, 16L, 1L, "ungrouped")))
data <- expression_fixture(rows, 16L, 1L, "ungrouped")
result <- data
records <- list()
state_records <- list()
checkpoint <- function(calls) {
    invisible(gc(full = TRUE))
    collection <- gc(full = TRUE)
    state_records[[paste0("source-", calls)]] <<- expression_state(data, paste0("source-", calls))
    state_records[[paste0("result-", calls)]] <<- expression_state(result, paste0("result-", calls))
    saveRDS(state_records, file.path(output, "source-result-states.rds"))
    states <- owned_state(result)
    records[[length(records) + 1L]] <<- data.frame(calls, rows, mode,
        n_cells_used = collection["Ncells", "used"],
        v_cells_used = collection["Vcells", "used"],
        gc_used_megabytes_rounded = sum(collection[, 2L]),
        maximum_backing_depth = max(vapply(states, function(state) as.numeric(state$depth), numeric(1))))
    write.csv(do.call(rbind, records), file.path(output, "retained.csv"), row.names = FALSE)
}
checkpoint(0L)
result <- operation(result)
checkpoint(5L)
for (i in seq_len(9L)) result <- operation(result)
checkpoint(50L)
expression_equal(as.double(result$x), rep(c(1, 2, 3, 4), length.out = rows) + 50,
                 "fifty-call values")
expression_equal(as.double(data$x), rep(c(1, 2, 3, 4), length.out = rows), "original values")
expression_equal(as.character(result$s), rep(c("aa", "b"), length.out = rows), "retained strings")
expression_equal(attr(result$s, "label"), "Input s", "retained string label")
expression_equal(attr(result, "label"), "Expression benchmark", "retained dataset label")
validate_benchmark_install(lib, sha)
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dput(list(source = sha, DLL = getLoadedDLLs()[["dtatools"]][["path"]], session = sessionInfo(),
          note = "Ncell/Vcell counts describe retained R heap after GC. R reports rounded used-megabyte columns. Whole-process peak RSS includes startup, fixtures and validation. These are distinct from cumulative allocation."),
     file = file.path(output, "session.R"))
cat("PASS fifty-call retained state and values\n")
