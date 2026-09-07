# Tiny reference/oracle qualification only. No timings or allocation profiles.
source(Sys.getenv("DTA_ORACLE_HELPER"))
lib <- Sys.getenv("DTA_ORACLE_LIBRARY")
sha <- Sys.getenv("DTA_ORACLE_SOURCE")
output <- Sys.getenv("DTA_ORACLE_OUTPUT")
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
source(Sys.getenv("DTA_EXPRESSION_CASES"))
if (!identical(normalizePath(find.package("dtatools")),
               normalizePath(file.path(lib, "dtatools")))) stop("Wrong installation")
records <- list()
state_records <- list()
for (kind in c("ungrouped", "grouped", "by", "rowwise")) {
    for (name in c("retain", "dependent", "capture", "pipeline_five")) {
        if (name == "capture" && kind != "ungrouped") next
        snapshots <- list()
        for (mode in c("direct", "legacy", "safe_reference")) {
            cat("RUN", kind, name, mode, "\n")
            data <- expression_fixture(12L, 4L, 3L, kind)
            before <- expression_snapshot(data)
            state_records[[paste(kind, name, mode, "fixture")]] <- expression_state(data, "fixture")
            sink <- new.env(parent = emptyenv())
            operation <- expression_operation(name, kind, mode, sink)
            result <- operation(data)
            expression_check(data, result, name, kind, 12L, sink)
            snapshots[[mode]] <- expression_snapshot(result)
            state_records[[paste(kind, name, mode, "after_oracle")]] <- expression_state(data, "after_oracle")
            expression_equal(expression_snapshot(data), before, "source preserved")
            saved <- if (name == "capture") sink$values[[1L]] else NULL
            if (kind == "rowwise") {
                source_alias <- data
                result_alias <- result
                set_dta_note(data, 1, "source note", variable = "s")
                expression_equal(dta_note(source_alias, 1, variable = "s"), "source note", "rowwise source alias metadata write")
                expression_equal(dta_note(result, 1, variable = "s"), NULL, "original rowwise result isolates source metadata write")
                set_dta_note(result, 2, "result note", variable = "x")
                expression_equal(dta_note(result_alias, 2, variable = "x"), "result note", "rowwise result alias metadata write")
                expression_equal(dta_note(data, 2, variable = "x"), NULL, "original rowwise source isolates result metadata write")
            }
            # Payload repl() requires ungrouping rowwise data. These subsequent
            # checks concern the converted pair; the original pair is above.
            write_data <- if (kind == "rowwise") dplyr::ungroup(data) else data
            write_result <- if (kind == "rowwise") dplyr::ungroup(result) else result
            repl(write_data, s = "zz", where = 1L)
            expression_equal(as.character(write_result$s)[[1L]], "aa", "source-to-result isolation")
            repl(write_result, x = 99, where = 2L)
            expression_equal(as.double(write_data$x)[[2L]], 2, "result-to-source isolation")
            if (!is.null(saved)) {
                expression_equal(as.double(saved), rep(c(1, 2, 3, 4), 3L), "saved after result write")
                repl(write_data, x = 88, where = 3L)
                expression_equal(as.double(saved), rep(c(1, 2, 3, 4), 3L), "saved after source write")
            }
        }
        expression_equal(snapshots$direct, snapshots$legacy, paste(kind, name, "legacy parity"))
        expression_equal(snapshots$safe_reference, snapshots$legacy, paste(kind, name, "safe reference parity"))
        records[[paste(kind, name)]] <- TRUE
        cat("PASS", kind, name, "values/classes/metadata/reference/write isolation\n")
    }
}
for (mode in c("direct", "legacy", "safe_reference")) {
    foreign <- data.table::data.table(x = c(1, 2), s = c("a", "b"))
    take_numeric <- function() foreign$x
    take_string <- function() foreign$s
    data <- dibble(id = 1:2)
    result <- expression_mutate(data, rlang::quos(x = take_numeric(), s = take_string()), mode = mode)
    data.table::set(foreign, i = 1L, j = "x", value = 99)
    data.table::set(foreign, i = 2L, j = "s", value = "changed")
    expression_equal(as.double(result$x), c(1, 2), paste(mode, "foreign numeric capture"))
    expression_equal(as.character(result$s), c("a", "b"), paste(mode, "foreign string capture"))
    repl(result, x = 42, where = 2L)
    expression_equal(foreign$x, c(99, 2), paste(mode, "reverse foreign isolation"))
    result <- expression_mutate(data, rlang::quos(y = c(NA_real_, 1), z = y > 0), mode = mode)
    expression_equal(result$z, c(TRUE, TRUE), paste(mode, "sequential Stata typing"))
    records[[paste(mode, "foreign and sequential typing")]] <- TRUE
}
saveRDS(state_records, file.path(output, "source-states.rds"))
validate_benchmark_install(lib, sha)
namespace_names <- setdiff(loadedNamespaces(), "base")
namespace_paths <- vapply(namespace_names, function(name) getNamespaceInfo(asNamespace(name), "path"), character(1))
write.table(data.frame(name = namespace_names, path = unname(namespace_paths)),
    file.path(output, "namespaces.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
dput(list(records = records, source = sha, R = R.version.string,
          DLL = getLoadedDLLs()[["dtatools"]][["path"]], session = sessionInfo()),
     file = file.path(output, "qualification.R"))
cat("PASS all", length(records), "bounded reference/oracle checks; no timings\n")
