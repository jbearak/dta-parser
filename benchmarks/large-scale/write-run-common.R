initialize_write_runner <- function(
    script_dir, usage, input_scope, input_name, artifact_description,
    required_packages
) {
    args <- commandArgs(trailingOnly = TRUE)
    if (length(args) != 5L) stop(usage)

    input_path <- normalizePath(
        args[[1L]], winslash = "/", mustWork = TRUE
    )
    outputs <- vapply(
        args[2:4], normalizePath, character(1L), winslash = "/",
        mustWork = FALSE
    )
    iterations <- suppressWarnings(as.integer(args[[5L]]))
    if (length(iterations) != 1L || is.na(iterations) ||
        iterations < 1L || as.character(iterations) != args[[5L]]) {
        stop("write iterations must be a positive integer")
    }

    checkout_root <- normalizePath(
        file.path(script_dir, "..", ".."), winslash = "/"
    )
    benchmark_library <- benchmark_library_path()
    if (!startsWith(benchmark_library, paste0(checkout_root, "/"))) {
        stop("DTATOOLS_BENCH_LIB must be inside this checkout")
    }
    build_provenance_path <- file.path(
        benchmark_library, "dtatools-benchmark-provenance.tsv"
    )
    build_provenance <- verify_benchmark_provenance(
        checkout_root, benchmark_library, build_provenance_path
    )
    benchmark_activate_library(
        required_packages,
        benchmark_library = benchmark_library
    )

    target_root <- normalizePath(
        file.path(checkout_root, "target", "large-scale"),
        winslash = "/", mustWork = TRUE
    )
    expected_input <- file.path(
        if (identical(input_scope, "script")) script_dir else target_root,
        input_name
    )
    if (!identical(input_path, expected_input)) {
        stop(input_name, " must use its canonical path")
    }
    output_parents <- vapply(outputs, function(path) {
        normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
    }, character(1L))
    if (length(unique(output_parents)) != 1L ||
        !startsWith(basename(output_parents[[1L]]), ".run.") ||
        !identical(dirname(output_parents[[1L]]), target_root)) {
        stop(
            artifact_description,
            " artifacts must share a large-scale run staging directory"
        )
    }

    list(
        input_path = input_path,
        outputs = outputs,
        iterations = iterations,
        checkout_root = checkout_root,
        benchmark_library = benchmark_library,
        build_provenance_path = build_provenance_path,
        build_provenance = build_provenance,
        target_root = target_root,
        output_parent = output_parents[[1L]]
    )
}

write_runtime_binding <- function(rscript, packages, stata = "") {
    r_executable <- normalizePath(
        file.path(R.home("bin"), "R"), winslash = "/", mustWork = TRUE
    )
    rscript <- normalizePath(
        rscript, winslash = "/", mustWork = TRUE
    )
    time_executable <- normalizePath(
        "/usr/bin/time", winslash = "/", mustWork = TRUE
    )
    binding <- data.frame(
        r_executable_path = r_executable,
        r_executable_sha256 = benchmark_file_sha256(r_executable),
        rscript_executable_path = rscript,
        rscript_executable_sha256 = benchmark_file_sha256(rscript),
        time_executable_path = time_executable,
        time_executable_sha256 = benchmark_file_sha256(time_executable),
        stringsAsFactors = FALSE, check.names = FALSE
    )
    for (package in packages) {
        package_path <- normalizePath(
            getNamespaceInfo(asNamespace(package), "path"),
            winslash = "/", mustWork = TRUE
        )
        binding[[paste0(package, "_path")]] <- package_path
        binding[[paste0(package, "_sha256")]] <-
            benchmark_directory_sha256(package_path)
    }
    binding$stata_path <- if (nzchar(stata)) {
        normalizePath(stata, winslash = "/", mustWork = TRUE)
    } else ""
    binding$stata_sha256 <- if (nzchar(binding$stata_path)) {
        benchmark_file_sha256(binding$stata_path)
    } else ""
    binding
}

write_result_tuple <- function(data) {
    paste(data$dataset, data$writer, data$iteration, sep = "\r")
}

validate_write_result_matrix <- function(raw, datasets, writers, iterations,
                                         description) {
    required <- c(
        "dataset", "writer", "iteration", "writer_order", "rows", "columns",
        "elapsed_seconds", "peak_rss_bytes", "output_bytes"
    )
    if (!all(required %in% names(raw))) {
        stop(description, " results are missing required measurement fields")
    }
    expected <- expand.grid(
        dataset = datasets, writer = writers,
        iteration = seq_len(iterations), stringsAsFactors = FALSE
    )
    if (anyDuplicated(write_result_tuple(raw)) ||
        !setequal(write_result_tuple(raw), write_result_tuple(expected))) {
        stop(description, " results are not the exact expected matrix")
    }

    positive_number <- function(field, whole = FALSE) {
        value <- suppressWarnings(as.numeric(raw[[field]]))
        invalid <- !is.finite(value) | value <= 0
        if (whole) invalid <- invalid | value != floor(value)
        if (any(invalid)) {
            stop(description, " results have invalid ", field)
        }
    }
    positive_number("iteration", whole = TRUE)
    positive_number("writer_order", whole = TRUE)
    positive_number("rows", whole = TRUE)
    positive_number("columns", whole = TRUE)
    positive_number("elapsed_seconds")
    byte_fields <- grep("_bytes$", names(raw), value = TRUE)
    for (field in byte_fields) positive_number(field, whole = TRUE)

    groups <- split(raw, interaction(raw$dataset, raw$iteration, drop = TRUE))
    valid_order <- vapply(groups, function(group) {
        identical(
            sort(as.integer(group$writer_order)),
            seq_along(writers)
        )
    }, logical(1L))
    if (!all(valid_order)) {
        stop(description, " results have invalid writer order metadata")
    }
    shapes <- split(raw, raw$dataset)
    valid_shape <- vapply(shapes, function(group) {
        length(unique(group$rows)) == 1L &&
            length(unique(group$columns)) == 1L
    }, logical(1L))
    if (!all(valid_shape)) {
        stop(description, " results have inconsistent row or column metadata")
    }
    hash_fields <- grep("_sha256$", names(raw), value = TRUE)
    for (field in hash_fields) {
        value <- as.character(raw[[field]])
        if (anyNA(value) || any(!grepl("^[0-9a-f]{64}$", value))) {
            stop(description, " results have invalid ", field)
        }
    }
    invisible(NULL)
}

summarize_write_results <- function(raw, datasets, writers, fields) {
    groups <- split(raw, interaction(raw$dataset, raw$writer, drop = TRUE))
    summary <- do.call(rbind, lapply(groups, function(group) {
        result <- data.frame(
            dataset = group$dataset[[1L]], writer = group$writer[[1L]],
            iterations = nrow(group), stringsAsFactors = FALSE
        )
        for (field in fields) result[[field]] <- group[[field]][[1L]]
        result$median_seconds <- median(group$elapsed_seconds)
        result$p05_seconds <- unname(stats::quantile(group$elapsed_seconds, 0.05))
        result$p95_seconds <- unname(stats::quantile(group$elapsed_seconds, 0.95))
        result$median_peak_rss_bytes <- median(group$peak_rss_bytes)
        result$median_output_bytes <- median(group$output_bytes)
        result$provenance_id <- group$provenance_id[[1L]]
        result$build_provenance_id <- group$build_provenance_id[[1L]]
        result
    }))
    summary[order(match(summary$dataset, datasets),
                  match(summary$writer, writers)), ]
}

finalize_write_results <- function(
    raw, stable_provenance, outputs, datasets, writers, summary_fields
) {
    provenance_id <- benchmark_provenance_id(stable_provenance)
    raw$provenance_id <- provenance_id
    raw$build_provenance_id <- stable_provenance$build_provenance_id
    summary <- summarize_write_results(
        raw, datasets, writers, summary_fields
    )
    provenance <- stable_provenance
    provenance$provenance_id <- provenance_id
    provenance$created_at_utc <- format(
        Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    )

    atomic_tsv(raw, outputs[[1L]])
    atomic_tsv(summary, outputs[[2L]])
    atomic_tsv(provenance, outputs[[3L]])
    print(summary, row.names = FALSE)
    invisible(NULL)
}
