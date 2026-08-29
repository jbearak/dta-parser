aww_memory_error <- function(error) {
    grepl("vector memory exhausted|cannot allocate|memory limit|out of memory|std::bad_alloc",
          conditionMessage(error), ignore.case = TRUE)
}

aww_selection_miss <- function(error) {
    grepl(
        "past the end|does not exist|doesn't exist|can't find any columns|must be between",
        conditionMessage(error), ignore.case = TRUE
    )
}

aww_count_columns <- function(probe) {
    first <- probe(1L)
    if (inherits(first, "error")) return(list(count = NA_integer_, error = first))
    if (!first) return(list(count = 0L, error = NULL))
    lower <- 1L
    upper <- 2L
    repeat {
        exists <- probe(upper)
        if (inherits(exists, "error")) return(list(count = NA_integer_, error = exists))
        if (!exists) break
        lower <- upper
        if (upper > .Machine$integer.max %/% 2L) {
            return(list(count = NA_integer_, error = simpleError("column count exceeds integer range")))
        }
        upper <- upper * 2L
    }
    while (upper - lower > 1L) {
        middle <- lower + (upper - lower) %/% 2L
        exists <- probe(middle)
        if (inherits(exists, "error")) return(list(count = NA_integer_, error = exists))
        if (exists) lower <- middle else upper <- middle
    }
    list(count = lower, error = NULL)
}

aww_reader_column_count <- function(reader, path) {
    function_name <- if (identical(reader, "dtatools")) {
        dtatools::read_dta
    } else haven::read_dta
    probe <- function(index) tryCatch({
        function_name(
            path, col_select = tidyselect::all_of(as.integer(index)), n_max = 0L,
            .name_repair = "minimal"
        )
        TRUE
    }, error = function(error) {
        if (aww_selection_miss(error)) FALSE else error
    })
    aww_count_columns(probe)
}

aww_read_tile <- function(reader, path, tile) {
    function_name <- if (identical(reader, "dtatools")) dtatools::read_dta else haven::read_dta
    indices <- seq.int(tile$column_start, length.out = tile$column_count)
    if (!length(indices)) {
        return(function_name(
            path, col_select = character(), skip = tile$skip, n_max = tile$n_max,
            .name_repair = "minimal"
        ))
    }
    function_name(
        path,
        col_select = tidyselect::all_of(indices),
        skip = tile$skip,
        n_max = tile$n_max,
        .name_repair = "minimal"
    )
}

aww_worker <- function(path, tile, common_script, compare_script, package_library,
                       expected_package_path) {
    source(common_script, local = environment())
    source(compare_script, local = environment())
    .libPaths(c(package_library, .libPaths()))
    if (!requireNamespace("dtatools", quietly = TRUE) ||
        !requireNamespace("haven", quietly = TRUE) ||
        !requireNamespace("tidyselect", quietly = TRUE)) stop("reader dependency unavailable")
    loaded <- normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"),
                            winslash = "/", mustWork = TRUE)
    if (!identical(loaded, expected_package_path)) stop("foreign dtatools installation")
    started <- proc.time()[["elapsed"]]
    if (identical(tile$kind, "shape")) {
        counts <- lapply(c("dtatools", "haven"), function(reader) {
            aww_reader_column_count(reader, path)
        })
        names(counts) <- c("dtatools", "haven")
        count_errors <- vapply(counts, function(value) !is.null(value$error), logical(1))
        row_shape <- tryCatch(
            dtatools::read_dta(
                path, col_select = character(), .name_repair = "minimal"
            ),
            error = identity
        )
        errors <- c(
            lapply(counts[count_errors], function(value) conditionMessage(value$error)),
            if (inherits(row_shape, "error")) list(dtatools_rows = conditionMessage(row_shape))
        )
        if (length(errors)) {
            return(list(
                schema_version = aww_schema_version, tile = tile,
                elapsed_seconds = unname(proc.time()[["elapsed"]] - started),
                reader_errors = errors, reader_rows = c(dtatools = NA_integer_, haven = NA_integer_),
                classification = if (any(vapply(
                    c(lapply(counts[count_errors], `[[`, "error"),
                      if (inherits(row_shape, "error")) list(row_shape) else list()),
                    aww_memory_error, logical(1)
                ))) "memory-limit" else if (all(count_errors)) "shared-reader-error" else
                    if (count_errors[["haven"]]) "haven-error" else "dtatools-error",
                disputes = aww_empty_disputes()
            ))
        }
        disputes <- if (!identical(counts$dtatools$count, counts$haven$count)) {
            aww_dispute(
                "metadata", "dimension", attribute = "ncol",
                dtatools = counts$dtatools$count, haven = counts$haven$count
            )
        } else aww_empty_disputes()
        if (max(counts$dtatools$count, counts$haven$count) == 0L) {
            haven_shape <- tryCatch(
                haven::read_dta(path, n_max = 0L, .name_repair = "minimal"),
                error = identity
            )
            if (inherits(haven_shape, "error")) {
                return(list(
                    schema_version = aww_schema_version, tile = tile,
                    elapsed_seconds = unname(proc.time()[["elapsed"]] - started),
                    reader_errors = list(haven = conditionMessage(haven_shape)),
                    reader_rows = c(dtatools = nrow(row_shape), haven = NA_integer_),
                    classification = if (aww_memory_error(haven_shape)) "memory-limit" else "haven-error",
                    disputes = disputes
                ))
            }
            disputes <- aww_bind_disputes(list(
                disputes,
                aww_compare_attributes(row_shape, haven_shape, frame = TRUE)
            ))
        }
        metadata <- list(
            names = rep(NA_character_, max(counts$dtatools$count, counts$haven$count)),
            formats = rep("", max(counts$dtatools$count, counts$haven$count)),
            storage = rep(NA_character_, max(counts$dtatools$count, counts$haven$count)),
            rows = as.double(nrow(row_shape)),
            dtatools_columns = counts$dtatools$count,
            haven_columns = counts$haven$count,
            columns = max(counts$dtatools$count, counts$haven$count)
        )
        return(list(
            schema_version = aww_schema_version, tile = tile,
            elapsed_seconds = unname(proc.time()[["elapsed"]] - started),
            reader_errors = list(), reader_rows = c(
                dtatools = nrow(row_shape), haven = NA_integer_
            ),
            classification = if (nrow(disputes)) "dispute" else "pass",
            disputes = disputes, metadata = metadata
        ))
    }
    values <- lapply(c("dtatools", "haven"), function(reader) {
        tryCatch(aww_read_tile(reader, path, tile), error = identity)
    })
    names(values) <- c("dtatools", "haven")
    errors <- vapply(values, inherits, logical(1), what = "error")
    memory <- vapply(values, function(value) inherits(value, "error") && aww_memory_error(value), logical(1))
    base <- list(
        schema_version = aww_schema_version,
        tile = tile,
        elapsed_seconds = unname(proc.time()[["elapsed"]] - started),
        reader_errors = lapply(values[errors], conditionMessage),
        reader_rows = setNames(vapply(values, function(value) if (inherits(value, "error")) NA_integer_ else nrow(value), integer(1)), names(values))
    )
    if (any(errors)) {
        classification <- if (any(memory)) "memory-limit" else
            if (all(errors)) "shared-reader-error" else
            if (errors[["dtatools"]]) "dtatools-error" else "haven-error"
        return(c(base, list(classification = classification, disputes = aww_empty_disputes())))
    }
    if (identical(tile$kind, "metadata")) {
        source_metadata <- tryCatch(
            dtatools:::.dta_metadata(
                path, column_start = tile$column_start,
                column_count = tile$column_count
            ),
            error = identity
        )
        if (inherits(source_metadata, "error")) {
            base$reader_errors$metadata <- conditionMessage(source_metadata)
            return(c(base, list(
                classification = if (aww_memory_error(source_metadata)) {
                    "memory-limit"
                } else "dtatools-error",
                disputes = aww_empty_disputes()
            )))
        }
        source_storage <- attr(source_metadata, "dta_storage", exact = TRUE)
        aligned <- length(source_metadata) == tile$column_count &&
            length(source_storage) == tile$column_count &&
            identical(as.character(source_metadata), names(values$dtatools))
        if (!aligned) {
            base$reader_errors$metadata <- "projected metadata is not aligned with the public reader"
            return(c(base, list(
                classification = "dtatools-error",
                disputes = aww_dispute(
                    "metadata", "attribute", reader = "dtatools",
                    attribute = "metadata-projection"
                )
            )))
        }
        disputes <- aww_compare_metadata(
            values$dtatools, values$haven,
            column_offset = tile$column_start - 1L,
            compare_frame = tile$column_start == 1L, compare_dimensions = FALSE
        )
        metadata <- list(
            names = as.character(source_metadata), storage = source_storage,
            formats = vapply(values$dtatools, function(column) {
                value <- attr(column, "format.stata", exact = TRUE)
                if (is.null(value)) "" else as.character(value)
            }, character(1))
        )
        return(c(base, list(
            classification = if (nrow(disputes)) "dispute" else "pass",
            disputes = disputes, metadata = metadata
        )))
    }
    disputes <- tryCatch(
        aww_compare_values(
            values$dtatools, values$haven,
            column_offset = tile$column_start - 1L,
            row_offset = tile$skip,
            n_max = tile$n_max,
            storage = tile$storage
        ),
        error = identity
    )
    if (inherits(disputes, "error")) {
        classification <- if (aww_memory_error(disputes)) "memory-limit" else "comparison-error"
        base$reader_errors$comparison <- conditionMessage(disputes)
        return(c(base, list(
            classification = classification,
            disputes = aww_empty_disputes()
        )))
    }
    c(base, list(
        classification = if (nrow(disputes)) "dispute" else "pass",
        disputes = disputes
    ))
}
