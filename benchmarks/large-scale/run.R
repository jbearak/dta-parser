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
sys.source(
    file.path(dirname(script_path), "..", "benchmark-common.R"),
    envir = environment()
)
benchmark_library <- benchmark_library_path()
if (!startsWith(benchmark_library, paste0(checkout_root, "/"))) {
    stop("DTATOOLS_BENCH_LIB must point to a library inside this checkout")
}
sys.source(file.path(dirname(script_path), "provenance.R"), envir = environment())
sys.source(file.path(dirname(script_path), "haven-parity.R"), envir = environment())
sys.source(file.path(dirname(script_path), "stata-fixture.R"), envir = environment())
provenance_path <- file.path(
    benchmark_library, "dtatools-benchmark-provenance.tsv"
)
provenance <- verify_benchmark_provenance(
    checkout_root, benchmark_library, provenance_path
)
runtime_packages <- c(
    "dtatools", "haven", "tidyselect", "readr", "rlang", "tibble"
)
benchmark_activate_library(
    runtime_packages,
    benchmark_library = benchmark_library
)
if (!identical(
    as.character(utils::packageVersion("dtatools")),
    as.character(provenance$package_version[[1L]])
)) {
    stop("installed dtatools version does not match benchmark provenance")
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
stata_generator <- file.path(dirname(script_path), "stata-generate-fixture.do")
stata_generator_sha256 <- benchmark_file_sha256(stata_generator)

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
    runtime <- data.frame(
        schema_version = 1L,
        build_provenance_id = as.character(provenance$provenance_id[[1L]]),
        manifest_sha256 = benchmark_file_sha256(manifest_path),
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
        stringsAsFactors = FALSE,
        check.names = FALSE
    )
    for (package in runtime_packages) {
        runtime[[paste0(package, "_version")]] <-
            as.character(utils::packageVersion(package))
        runtime[[paste0(package, "_path")]] <- normalizePath(
            find.package(package), winslash = "/", mustWork = TRUE
        )
        runtime[[paste0(package, "_installed_md5")]] <-
            benchmark_directory_digest(runtime[[paste0(package, "_path")]])
    }
    runtime$provenance_id <- benchmark_provenance_id(runtime)
    runtime
}

write_runtime_provenance <- function(runtime) {
    record <- runtime
    record$created_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    atomic_tsv(record, runtime_provenance_path)
}

datasets <- read_stata_fixture_manifest(
    manifest_path, stata_generator_sha256
)
manifest_sha256 <- benchmark_file_sha256(manifest_path)

projection <- c(
    "id", "income", "age", "region", "interview_date", "case_code",
    "occupation", "description"
)
columns <- names(dtatools::read_dta(datasets$path[[1L]], n_max = 0))
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
            dtatools::read_dta(path, skip = skip, n_max = n_max)
        } else {
            dtatools::read_dta(
                path, col_select = tidyselect::all_of(projection),
                skip = skip, n_max = n_max
            )
        }
    } else if (identical(implementation, "rust-vectors")) {
        if (full) {
            dtatools:::.read_dta_rust_vectors(path, skip = skip, n_max = n_max)
        } else {
            dtatools:::.read_dta_rust_vectors(
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

final_datasets <- read_stata_fixture_manifest(
    manifest_path, stata_generator_sha256
)
if (!identical(
        benchmark_file_sha256(manifest_path), manifest_sha256
    ) || !identical(final_datasets$path, datasets$path) ||
    !identical(final_datasets$sha256, datasets$sha256) ||
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
