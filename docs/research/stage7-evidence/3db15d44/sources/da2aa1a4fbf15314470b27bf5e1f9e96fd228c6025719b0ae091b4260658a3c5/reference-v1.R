# Benchmark-only delegation control for the six Stage 7 measurement workloads.
# Adapted from this project's mutate-data.R at 4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c.
# No namespace modification. Run only with that installed predecessor, after
# isolated foreign-write qualification. This file defines functions only.

stage7_reference_start <- function(library_path) {
    library(dtatools, lib.loc = library_path)
    selected <- getNamespaceInfo(asNamespace("dtatools"), "path")
    stopifnot(identical(normalizePath(selected),
        normalizePath(file.path(library_path, "dtatools"))))
    provenance <- readRDS(file.path(selected, "Meta", "benchmark-provenance.rds"))
    stopifnot(identical(provenance$source_sha,
        "4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c"))
    invisible(provenance)
}

# The fixed nesting workloads contain one level of frames with atomic columns.
# Preserve the original plain/grouped/rowwise frame classes and list-of prototype.
# Capture each frame through the predecessor's already qualified flat-column
# publication. Do not treat a shallow copy of the outer list as nested capture.
stage7_reference_nested_frames <- function(result, key = "data") {
    capture <- function(frame) {
        stopifnot(is.data.frame(frame),
                  !any(vapply(frame, is.list, logical(1))))
        classes <- class(frame)
        context <- dtatools:::.begin_dibble_result(frame,
            "Stage 7 benchmark nested capture", "unknown")
        owned <- dtatools:::.finish_dibble_result(context, frame)
        value <- dtatools:::.reference_snapshot(owned)
        stopifnot(identical(class(value), classes))
        value
    }
    index <- match(key, names(result))
    stopifnot(!is.na(index))
    original <- .subset2(result, index)
    stopifnot(is.list(original))
    captured <- lapply(original, capture)
    metadata <- attributes(original)
    if (!is.null(metadata$ptype)) metadata$ptype <- capture(metadata$ptype)
    attributes(captured) <- metadata
    result <- dtatools:::.metadata_copy(result)
    .Call(get("C_dtatools_set_data_column", asNamespace("dtatools")),
          result, as.integer(index), captured)
    result
}

stage7_safe_reference <- function(data, generic, dots = list(), arguments = list()) {
    stopifnot(generic %in% c("summarise", "reframe", "group_modify", "group_nest", "nest_by"))
    before <- dtatools:::.data_columns(data)
    scope <- new.env(parent = baseenv())
    scope[[generic]] <- getExportedValue("dplyr", generic)
    caller <- paste0("`", generic, "()`")
    if (identical(generic, "group_modify")) {
        stopifnot(!length(dots))
        call <- rlang::call2(generic, dtatools:::.reference_snapshot(data), !!!arguments)
        result <- eval(call, scope)
    } else {
        wrapped <- dtatools:::.wrap_mask_expressions(dots, before, caller)
        call <- rlang::call2(generic, dtatools:::.reference_snapshot(data),
                            !!!wrapped$dots, !!!arguments)
        result <- dtatools:::.relabel_mask_conditions(eval(call, scope), wrapped$labels)
    }
    result <- dtatools:::.retype_changed_columns(result, before, caller)
    if (generic %in% c("group_nest", "nest_by")) {
        result <- stage7_reference_nested_frames(result)
    }
    dtatools:::.close_dibble(data, result, caller)
}
