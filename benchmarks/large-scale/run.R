args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
    stop(paste(
        "usage: Rscript run.R DATASETS_TSV OUTPUT_TSV [ITERATIONS]",
        "[RUNTIME_PROVENANCE_TSV]"
    ))
}

manifest_path <- normalizePath(args[[1L]])
output_path <- normalizePath(args[[2L]], mustWork = FALSE)
iterations <- if (length(args) >= 3L) as.integer(args[[3L]]) else 101L
runtime_provenance_path <- if (length(args) >= 4L) {
    normalizePath(args[[4L]], mustWork = FALSE)
} else {
    file.path(dirname(output_path), "run-provenance.tsv")
}
stopifnot(is.finite(iterations), iterations >= 1L)

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
checkout_root <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/")
benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) {
    stop("set DTAPARSER_BENCH_LIB to a library containing dtaparser built from this checkout")
}
benchmark_library <- normalizePath(benchmark_library, winslash = "/")
if (!startsWith(benchmark_library, paste0(checkout_root, "/"))) {
    stop("DTAPARSER_BENCH_LIB must point to a library inside this checkout")
}
sys.source(file.path(dirname(script_path), "provenance.R"), envir = environment())
sys.source(file.path(dirname(script_path), "haven-parity.R"), envir = environment())
provenance_path <- file.path(
    benchmark_library, "dtaparser-benchmark-provenance.tsv"
)
provenance <- verify_benchmark_provenance(
    checkout_root, benchmark_library, provenance_path
)
.libPaths(c(benchmark_library, .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE)) {
    stop("DTAPARSER_BENCH_LIB does not contain a loadable dtaparser installation")
}
loaded_library <- normalizePath(dirname(find.package("dtaparser")), winslash = "/")
namespace_path <- normalizePath(
    getNamespaceInfo(asNamespace("dtaparser"), "path"), winslash = "/"
)
expected_package_path <- benchmark_installed_package_path(benchmark_library)
if (!identical(loaded_library, benchmark_library) ||
    !identical(namespace_path, expected_package_path)) {
    stop("dtaparser namespace was not loaded from DTAPARSER_BENCH_LIB")
}
if (!identical(
    as.character(utils::packageVersion("dtaparser")),
    as.character(provenance$package_version[[1L]])
)) {
    stop("installed dtaparser version does not match benchmark provenance")
}
runtime_packages <- c(
    "dtaparser", "haven", "tidyselect", "readr", "rlang", "tibble"
)
for (package in runtime_packages) {
    if (!requireNamespace(package, quietly = TRUE)) {
        stop(package, " is required")
    }
}

sha256_file <- function(path) {
    tolower(unname(tools::sha256sum(path))[[1L]])
}

canonical_target <- normalizePath(
    file.path(checkout_root, "target", "large-scale"),
    winslash = "/", mustWork = TRUE
)
artifact_parents <- vapply(
    c(output_path, runtime_provenance_path),
    function(path) normalizePath(dirname(path), winslash = "/", mustWork = TRUE),
    character(1)
)
if (length(unique(artifact_parents)) != 1L) {
    stop("raw output and runtime provenance must share a staging directory")
}
artifact_parent <- artifact_parents[[1L]]
staged_parent <- identical(dirname(artifact_parent), canonical_target) &&
    startsWith(basename(artifact_parent), ".run.")
if (!identical(artifact_parent, canonical_target) && !staged_parent) {
    stop("benchmark artifacts must use target/large-scale or its run staging directory")
}
expected_manifest <- file.path(canonical_target, "datasets.tsv")
if (!identical(manifest_path, expected_manifest)) {
    stop("dataset manifest must be target/large-scale/datasets.tsv")
}
expected_dataset_paths <- file.path(
    canonical_target, c("synthetic-100mb.dta", "synthetic-1gb.dta")
)

verify_dataset_files <- function(datasets) {
    required_manifest_columns <- c(
        "dataset", "path", "target_bytes", "actual_bytes", "sha256", "rows",
        "obs_bytes", "base_rows"
    )
    if (!all(required_manifest_columns %in% names(datasets))) {
        stop("dataset manifest is missing required fields")
    }
    stopifnot(
        nrow(datasets) == 2L,
        identical(as.character(datasets$dataset), c("100mb", "1gb")),
        identical(as.double(datasets$target_bytes), c(100000000, 1000000000))
    )
    if (any(nzchar(Sys.readlink(expected_dataset_paths)))) {
        stop("benchmark dataset paths must not be symbolic links")
    }
    resolved <- vapply(datasets$path, normalizePath, character(1), winslash = "/")
    if (!identical(unname(resolved), expected_dataset_paths)) {
        stop("manifest dataset paths are not the canonical expected paths")
    }

    numeric_fields <- c("target_bytes", "actual_bytes", "rows", "obs_bytes",
                        "base_rows")
    for (field in numeric_fields) {
        value <- as.double(datasets[[field]])
        if (any(!is.finite(value) | value <= 0 | value != floor(value))) {
            stop("manifest field is not positive integral: ", field)
        }
        datasets[[field]] <- value
    }
    if (length(unique(datasets$obs_bytes)) != 1L ||
        length(unique(datasets$base_rows)) != 1L) {
        stop("scaled datasets disagree on base row metadata")
    }
    overhead <- datasets$actual_bytes - datasets$rows * datasets$obs_bytes
    if (any(overhead <= 0) || length(unique(overhead)) != 1L) {
        stop("scaled dataset row width and overhead are inconsistent")
    }
    if (any(abs(datasets$actual_bytes - datasets$target_bytes) >
            datasets$obs_bytes / 2 + 0.5)) {
        stop("scaled dataset size is inconsistent with its target")
    }

    actual_sizes <- as.double(file.info(expected_dataset_paths)$size)
    if (!identical(actual_sizes, datasets$actual_bytes)) {
        stop("dataset file size does not match manifest actual_bytes")
    }
    expected_hashes <- tolower(as.character(datasets$sha256))
    if (any(!grepl("^[0-9a-f]{64}$", expected_hashes))) {
        stop("dataset manifest contains an invalid SHA-256")
    }
    actual_hashes <- vapply(expected_dataset_paths, sha256_file, character(1))
    if (!identical(unname(actual_hashes), expected_hashes)) {
        stop("dataset SHA-256 does not match manifest")
    }
    datasets$path <- expected_dataset_paths
    datasets$sha256 <- expected_hashes
    datasets$overhead_bytes <- overhead
    datasets
}

command_output <- function(command, arguments = character()) {
    tryCatch(
        paste(suppressWarnings(system2(
            command, arguments, stdout = TRUE, stderr = FALSE
        )), collapse = " "),
        error = function(error) "unavailable"
    )
}

cpu_identity <- function() {
    info <- Sys.info()
    if (identical(unname(info[["sysname"]]), "Darwin")) {
        value <- command_output(Sys.which("sysctl"), c("-n", "machdep.cpu.brand_string"))
        if (nzchar(value)) return(value)
        hardware <- tryCatch(
            suppressWarnings(system2(
                "/usr/sbin/system_profiler", "SPHardwareDataType",
                stdout = TRUE, stderr = FALSE
            )), error = function(error) character()
        )
        chip <- trimws(sub("^.*Chip:", "", grep("Chip:", hardware, value = TRUE)))
        if (length(chip) && nzchar(chip[[1L]])) return(chip[[1L]])
    }
    if (identical(unname(info[["sysname"]]), "Linux") &&
        file.exists("/proc/cpuinfo")) {
        lines <- readLines("/proc/cpuinfo", warn = FALSE)
        model <- sub("^[^:]+:[[:space:]]*", "", grep(
            "^(model name|Hardware)[[:space:]]*:", lines, value = TRUE
        ))
        if (length(model)) return(model[[1L]])
    }
    value <- Sys.getenv("PROCESSOR_IDENTIFIER")
    if (nzchar(value)) value else unname(info[["machine"]])
}

collect_runtime_provenance <- function(datasets, full_columns, projected_columns) {
    system <- Sys.info()
    python_path <- unname(Sys.which("python3"))
    runtime <- data.frame(
        schema_version = 1L,
        build_provenance_id = as.character(provenance$provenance_id[[1L]]),
        manifest_sha256 = sha256_file(manifest_path),
        iterations = iterations,
        dataset_100mb_sha256 = datasets$sha256[[1L]],
        dataset_1gb_sha256 = datasets$sha256[[2L]],
        dataset_100mb_bytes = datasets$actual_bytes[[1L]],
        dataset_1gb_bytes = datasets$actual_bytes[[2L]],
        dataset_100mb_rows = datasets$rows[[1L]],
        dataset_1gb_rows = datasets$rows[[2L]],
        full_columns = full_columns,
        projected_columns = projected_columns,
        r_version = R.version.string,
        r_platform = R.version$platform,
        os_sysname = unname(system[["sysname"]]),
        os_release = unname(system[["release"]]),
        os_version = unname(system[["version"]]),
        os_machine = unname(system[["machine"]]),
        cpu_identity = cpu_identity(),
        python_version = command_output(python_path, "--version"),
        python_path = normalizePath(python_path, winslash = "/", mustWork = TRUE),
        stringsAsFactors = FALSE,
        check.names = FALSE
    )
    for (package in runtime_packages) {
        runtime[[paste0(package, "_version")]] <-
            as.character(utils::packageVersion(package))
        runtime[[paste0(package, "_path")]] <- normalizePath(
            find.package(package), winslash = "/", mustWork = TRUE
        )
    }
    runtime$provenance_id <- benchmark_provenance_id(runtime)
    runtime
}

write_runtime_provenance <- function(runtime) {
    record <- runtime
    record$created_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    temporary <- tempfile(
        pattern = paste0(basename(runtime_provenance_path), "."),
        tmpdir = dirname(runtime_provenance_path)
    )
    on.exit(unlink(temporary), add = TRUE)
    write.table(record, temporary, sep = "\t", row.names = FALSE, quote = FALSE)
    if (!file.rename(temporary, runtime_provenance_path)) {
        stop("could not atomically replace ", runtime_provenance_path)
    }
}

datasets <- verify_dataset_files(read.delim(
    manifest_path, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character"
))

projection <- c(
    "id", "income", "age", "region", "interview_date", "case_code",
    "occupation", "description"
)
columns <- names(dtaparser::read_dta(datasets$path[[1L]], n_max = 0))
stopifnot(all(projection %in% columns))
datasets$columns <- length(columns)
runtime_provenance <- collect_runtime_provenance(
    datasets, full_columns = length(columns),
    projected_columns = length(projection)
)
write_runtime_provenance(runtime_provenance)

read_one <- function(implementation, workload, path, skip = 0, n_max = Inf) {
    full <- identical(workload, "full")
    if (identical(implementation, "direct-r")) {
        if (full) {
            dtaparser::read_dta(path, skip = skip, n_max = n_max)
        } else {
            dtaparser::read_dta(
                path, col_select = tidyselect::all_of(projection),
                skip = skip, n_max = n_max
            )
        }
    } else if (identical(implementation, "rust-vectors")) {
        if (full) {
            dtaparser:::.read_dta_rust_vectors(path, skip = skip, n_max = n_max)
        } else {
            dtaparser:::.read_dta_rust_vectors(
                path, col_select = tidyselect::all_of(projection),
                skip = skip, n_max = n_max
            )
        }
    } else if (full) {
        haven::read_dta(path, skip = skip, n_max = n_max)
    } else {
        haven::read_dta(
            path, col_select = tidyselect::all_of(projection),
            skip = skip, n_max = n_max
        )
    }
}

validate_direct_identity <- function(path, workload, rows, expected_columns) {
    direct <- read_one("direct-r", workload, path)
    rust_vectors <- read_one("rust-vectors", workload, path)
    stopifnot(
        identical(direct, rust_vectors),
        nrow(direct) == rows,
        ncol(direct) == expected_columns
    )
    rm(direct, rust_vectors)
    invisible(gc())
}

validate_haven_windows <- function(path, rows) {
    window_rows <- min(32, rows)
    windows <- unique(c(0, max(0, floor(rows / 2) - floor(window_rows / 2)),
                        max(0, rows - window_rows)))
    for (skip in windows) {
        direct <- read_one(
            "direct-r", "projected-eight-columns", path,
            skip = skip, n_max = window_rows
        )
        rust_vectors <- read_one(
            "rust-vectors", "projected-eight-columns", path,
            skip = skip, n_max = window_rows
        )
        reference <- read_one(
            "haven", "projected-eight-columns", path,
            skip = skip, n_max = window_rows
        )
        stopifnot(identical(direct, rust_vectors))
        comparison <- all.equal(
            normalize_for_haven(direct), normalize_for_haven(reference),
            tolerance = 1e-7, check.attributes = TRUE
        )
        if (!isTRUE(comparison)) {
            stop("haven sample parity failed for ", path, " at skip=", skip,
                 ": ", paste(comparison, collapse = "; "))
        }
    }
    invisible(gc())
}

header <- c(
    "dataset", "target_bytes", "actual_bytes", "dataset_sha256", "rows",
    "columns", "workload", "implementation", "iteration", "elapsed_s",
    "input_gb_per_s", "provenance_id", "build_provenance_id"
)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
temporary_output <- tempfile(
    pattern = paste0(basename(output_path), "."),
    tmpdir = dirname(output_path)
)
on.exit(unlink(temporary_output), add = TRUE)
writeLines(paste(header, collapse = "\t"), temporary_output)

implementations <- c("direct-r", "rust-vectors", "haven")
workloads <- c("full", "projected-eight-columns")
for (dataset_index in seq_len(nrow(datasets))) {
    dataset <- datasets[dataset_index, ]
    path <- normalizePath(dataset$path)
    rows <- as.double(dataset$rows)
    validate_haven_windows(path, rows)

    for (workload in workloads) {
        expected_columns <- if (identical(workload, "full")) {
            dataset$columns
        } else {
            length(projection)
        }
        validate_direct_identity(path, workload, rows, expected_columns)
        message("validated ", dataset$dataset, " ", workload)

        for (implementation in implementations) {
            warm <- read_one(implementation, workload, path)
            stopifnot(nrow(warm) == rows, ncol(warm) == expected_columns)
            rm(warm)
            invisible(gc())
        }

        for (iteration in seq_len(iterations)) {
            order <- if (iteration %% 2L) implementations else rev(implementations)
            for (implementation in order) {
                invisible(gc())
                started <- proc.time()[["elapsed"]]
                result <- read_one(implementation, workload, path)
                elapsed <- proc.time()[["elapsed"]] - started
                stopifnot(nrow(result) == rows, ncol(result) == expected_columns)
                rate <- dataset$actual_bytes / 1e9 / elapsed
                row <- c(
                    dataset$dataset, dataset$target_bytes, dataset$actual_bytes,
                    dataset$sha256, format(rows, scientific = FALSE),
                    expected_columns, workload, implementation, iteration,
                    sprintf("%.9f", elapsed), sprintf("%.6f", rate),
                    runtime_provenance$provenance_id,
                    runtime_provenance$build_provenance_id
                )
                cat(paste(row, collapse = "\t"), "\n", sep = "",
                    file = temporary_output, append = TRUE)
                message(
                    dataset$dataset, " ", workload, " ", implementation, " ",
                    iteration, "/", iterations, ": ", sprintf("%.3fs", elapsed)
                )
                rm(result)
            }
        }
    }
}

final_datasets <- verify_dataset_files(read.delim(
    manifest_path, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character"
))
if (!identical(final_datasets$sha256, datasets$sha256) ||
    !identical(final_datasets$actual_bytes, datasets$actual_bytes)) {
    stop("benchmark datasets changed during timing")
}
final_build_provenance <- verify_benchmark_provenance(
    checkout_root, benchmark_library, provenance_path
)
if (!identical(
    as.character(final_build_provenance$provenance_id[[1L]]),
    as.character(provenance$provenance_id[[1L]])
)) {
    stop("build provenance changed during timing")
}
final_runtime_provenance <- collect_runtime_provenance(
    final_datasets, full_columns = length(columns),
    projected_columns = length(projection)
)
if (!identical(
    as.character(final_runtime_provenance$provenance_id[[1L]]),
    as.character(runtime_provenance$provenance_id[[1L]])
)) {
    stop("runtime provenance changed during timing")
}

raw <- read.delim(
    temporary_output, check.names = FALSE, colClasses = "character"
)
expected_rows <- nrow(datasets) * length(workloads) *
    length(implementations) * iterations
stopifnot(
    nrow(raw) == expected_rows,
    identical(as.character(unique(raw$provenance_id)),
              as.character(runtime_provenance$provenance_id)),
    identical(as.character(unique(raw$build_provenance_id)),
              as.character(runtime_provenance$build_provenance_id))
)
if (!file.rename(temporary_output, output_path)) {
    stop("could not atomically replace ", output_path)
}
