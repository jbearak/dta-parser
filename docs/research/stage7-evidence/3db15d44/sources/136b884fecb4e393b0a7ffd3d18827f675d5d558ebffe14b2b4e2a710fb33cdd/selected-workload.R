# One repeated-source operation per fresh process. Only original and latest
# result remain live at5/50; a separate small witness checks saved early output.
args <- commandArgs(TRUE)
stopifnot(length(args) == 5L)
source("benchmarks/r-dibble-dplyr/owned-atomic-helpers.R")
library_path <- atomic_start(args[[1L]], args[[3L]], "candidate")
output <- normalizePath(args[[2L]], mustWork = TRUE)
rows <- as.integer(args[[5L]])
support <- Sys.getenv("DTA_STAGE7_SUPPORT")
source(file.path(support, "workloads-v1.R"))
source(file.path(support, "reference-v1.R"))
source(file.path(support, "validation-v2.R"))
schemas <- dget(file.path(support, "schemas.R"))
route <- Sys.getenv("DTA_STAGE7_ROUTES")
workload <- Sys.getenv("DTA_STAGE7_MEMORY_WORKLOAD")
stopifnot(route %in% c("public", "predecessor_safe_reference"),
    workload %in% c("group_modify_identity", "group_nest", "nest_by"),
    length(rows) == 1L, !is.na(rows), rows >= 256L)
if (route == "predecessor_safe_reference") stage7_reference_start(library_path)
suppressPackageStartupMessages(library(bench)) # Retains shared runtime checker contract.
columns <- 8L
groups <- 128L
source_schema <- schemas[["8-source"]]
result_schema <- schemas[[paste(8L, 4L, workload, sep = "-")]]
writeLines(c(atomic_identity(args[[3L]], library_path, "candidate"),
    paste("workload", workload, "route", route, "rows", rows, "columns8 groups128"),
    "Every call reads the original fixed source. It does not recursively nest the preceding result.",
    "At0 source is live and result isNULL. At5/50 source and latest result are live; prior results have been released.",
    "Native state records contain scalars/addresses only and are streamed without keeping prior state frames in memory.",
    "Expected payload vectors are created only inside final validation, after the50-call heap checkpoint.",
    "Whole-child RSS includes setup, all50operations, final validation and runtime recording; it is not an operation peak.",
    "No foreign writes in this memory child; repeated-output write isolation is a separate witness."),
    file.path(output, "session.txt"))

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

heap <- list()
record_heap <- function(checkpoint) {
    invisible(gc(full = TRUE))
    values <- gc(full = TRUE)
    heap[[length(heap) + 1L]] <<- data.frame(checkpoint,
        n_cells_used = values["Ncells", "used"], v_cells_used = values["Vcells", "used"],
        vector_heap_bytes = values["Vcells", "used"] * 8,
        gc_used_megabytes_rounded = sum(values[, 2L]))
    write.csv(do.call(rbind, heap), file.path(output, "heap.csv"), row.names = FALSE)
    invisible(NULL)
}

record_state <- function(value, checkpoint, role) {
    current <- cbind(data.frame(checkpoint, role), stage7_states(value))
    file <- file.path(output, "states.csv")
    write.table(current, file, sep = ",", row.names = FALSE,
        col.names = !file.exists(file), append = file.exists(file))
    invisible(NULL)
}

check_pair <- function(source, result, rows) {
    stage7_check_output(result, rows, columns, groups, workload, result_schema)
    stage7_check_source(source, rows, columns, groups, source_schema)
    invisible(NULL)
}

run_repeated <- function() {
    # Prime operation, validation and state inspection before the prefixture heap.
    warm_source <- stage7_fixture(256L, columns, groups)
    warm_result <- stage7_workload(warm_source, workload, route)
    check_pair(warm_source, warm_result, 256L)
    invisible(stage7_states(warm_source))
    invisible(stage7_states(warm_result))
    rm(warm_source, warm_result)
    record_heap("prefixture")
    source <- stage7_fixture(rows, columns, groups)
    result <- NULL
    record_heap("0_source_only")
    record_state(source, "0", "source")
    for (i in seq_len(50L)) {
        result <- stage7_workload(source, workload, route)
        stopifnot(nrow(result) == if (workload == "group_modify_identity") rows else groups)
        if (i %in% c(5L, 50L)) {
            record_heap(as.character(i))
            record_state(source, as.character(i), "source")
            record_state(result, as.character(i), "result")
        }
    }
    check_pair(source, result, rows)
    write.csv(data.frame(rows, columns, groups, workload, route,
        calls = 50L, values_metadata_groups_source = TRUE),
        file.path(output, "validation.csv"), row.names = FALSE)
    record_state(source, "after_validation", "source")
    record_state(result, "after_validation", "result")
    record_heap("after_validation")
    rm(source)
    record_heap("source_released")
    rm(result)
    record_heap("result_released")
    invisible(NULL)
}

run_repeated()
validate_benchmark_install(library_path, args[[3L]])
cat("PASS repeated-source memory workload and final independent value/schema/group/source checks\n")
