script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_path <- normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
)
script_dir <- dirname(script_path)
sys.source(
    file.path(script_dir, "..", "benchmark-common.R"),
    envir = environment()
)
sys.source(file.path(script_dir, "provenance.R"), envir = environment())
sys.source(file.path(script_dir, "write-run-common.R"), envir = environment())
sys.source(file.path(script_dir, "stata-fixture.R"), envir = environment())

context <- initialize_write_runner(
    script_dir,
    paste(
        "usage: write-run.R DATASETS_TSV RAW_TSV SUMMARY_TSV",
        "PROVENANCE_TSV ITERATIONS"
    ),
    input_scope = "target",
    input_name = "datasets.tsv",
    artifact_description = "synthetic write",
    required_packages = c("dtaparser", "processx")
)
manifest_path <- context$input_path
outputs <- context$outputs
iterations <- context$iterations
checkout_root <- context$checkout_root
benchmark_library <- context$benchmark_library
build_provenance_path <- context$build_provenance_path
build_provenance <- context$build_provenance
target_root <- context$target_root
output_parent <- context$output_parent

stata_generator <- file.path(script_dir, "stata-generate-fixture.do")
stata_generator_sha256 <- benchmark_file_sha256(stata_generator)

writer_selection <- Sys.getenv("DTAPARSER_WRITE_WRITERS")
writers <- if (nzchar(writer_selection)) {
    strsplit(writer_selection, ",", fixed = TRUE)[[1L]]
} else c("dtaparser", "stata")
allowed_writers <- c("dtaparser", "stata")
if (!length(writers) || any(!writers %in% allowed_writers) ||
    anyDuplicated(writers)) {
    stop("DTAPARSER_WRITE_WRITERS must select unique supported writers")
}

datasets <- read_stata_fixture_manifest(
    manifest_path, stata_generator_sha256
)
manifest_sha256 <- benchmark_file_sha256(manifest_path)

rscript <- Sys.which("Rscript")
stata <- ""
if ("stata" %in% writers) {
    stata <- find_stata()
}
runtime_binding <- write_runtime_binding(
    rscript, packages = "processx", stata = stata
)
benchmark_environment <- c(
    DTAPARSER_BENCH_LIB = benchmark_library,
    R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
)

measurement_row <- function(dataset, input_sha256, writer, iteration,
                            writer_order, fields, stderr) {
    measurement <- tryCatch(
        parse_fixture_write_result(fields, writer),
        error = function(condition) {
            stop(conditionMessage(condition), ": ", stderr)
        }
    )
    rss <- parse_memory(stderr)
    if (measurement$elapsed_seconds <= 0 ||
        measurement$rows != dataset$rows ||
        (writer == "stata" && measurement$bytes != dataset$actual_bytes) ||
        !is.finite(rss) || rss <= 0) {
        stop(writer, " synthetic write returned invalid measurements")
    }
    data.frame(
        dataset = dataset$dataset, dataset_sha256 = dataset$sha256,
        input_sha256 = input_sha256,
        input_bytes = dataset$actual_bytes, rows = measurement$rows,
        columns = measurement$columns, writer = writer,
        iteration = iteration, writer_order = writer_order,
        elapsed_seconds = measurement$elapsed_seconds,
        peak_rss_bytes = rss, output_bytes = measurement$bytes,
        stringsAsFactors = FALSE
    )
}

measure_iteration <- function(dataset, iteration) {
    work_dir <- tempfile(
        pattern = paste0("synthetic-write-", dataset$dataset, "-"),
        tmpdir = output_parent
    )
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    input <- file.path(work_dir, "input.dta")
    results <- list()
    if ("stata" %in% writers) {
        if (!file.copy(
            stata_generator, file.path(work_dir, basename(stata_generator))
        )) stop("could not stage the Stata fixture generator")
        process <- run_timed_process(
            stata,
            c("-q", "-b", "do", basename(stata_generator), "input.dta",
              as.character(dataset$rows), dataset$dataset, "result.tsv"),
            work_dir, benchmark_environment
        )
        result <- file.path(work_dir, "result.tsv")
        fields <- if (file.exists(result)) {
            strsplit(readLines(result, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]]
        } else character()
        if (!file.exists(input)) {
            stop("Stata synthetic write did not produce its input: ", process$stderr)
        }
        input_sha256 <- benchmark_file_sha256(input)
        results[[length(results) + 1L]] <- measurement_row(
            dataset, input_sha256, "stata", iteration, 1L,
            fields, process$stderr
        )
        message(dataset$dataset, " stata ", iteration, "/", iterations)
    } else {
        if (!file.symlink(dataset$path, input)) stop("could not create input alias")
        input_sha256 <- dataset$sha256
    }
    if ("dtaparser" %in% writers) {
        process <- run_timed_process(
            rscript,
            c("--vanilla", file.path(script_dir, "write-worker.R"),
              "dtaparser", "stata-storage", input,
              file.path(work_dir, "output.dta")),
            work_dir, benchmark_environment
        )
        fields <- parse_fields(process$stdout, "SYNTHETIC_WRITE")
        results[[length(results) + 1L]] <- measurement_row(
            dataset, input_sha256, "dtaparser", iteration,
            if ("stata" %in% writers) 2L else 1L,
            fields, process$stderr
        )
        message(dataset$dataset, " dtaparser ", iteration, "/", iterations)
    }
    results
}

rows <- vector("list", nrow(datasets) * iterations * length(writers))
row_index <- 0L
for (dataset_index in seq_len(nrow(datasets))) {
    dataset <- datasets[dataset_index, , drop = FALSE]
    for (iteration in seq_len(iterations)) {
        measured <- measure_iteration(dataset, iteration)
        for (value in measured) {
            row_index <- row_index + 1L
            rows[[row_index]] <- value
        }
    }
}
raw <- do.call(rbind, rows)

final_build <- verify_benchmark_provenance(
    checkout_root, benchmark_library, build_provenance_path
)
final_datasets <- read_stata_fixture_manifest(
    manifest_path, stata_generator_sha256
)
if (!identical(final_build$provenance_id, build_provenance$provenance_id) ||
    !identical(benchmark_file_sha256(manifest_path), manifest_sha256) ||
    !identical(final_datasets$path, datasets$path) ||
    !identical(final_datasets$sha256, datasets$sha256) ||
    !identical(final_datasets$actual_bytes, datasets$actual_bytes) ||
    !identical(
        benchmark_file_sha256(stata_generator),
        stata_generator_sha256
    )) {
    stop("benchmark build or datasets changed during synthetic writes")
}
stable_provenance <- cbind(data.frame(
    schema_version = 1L,
    build_provenance_id = build_provenance$provenance_id[[1L]],
    manifest_sha256 = manifest_sha256,
    dataset_100mb_sha256 = datasets$sha256[[1L]],
    dataset_1gb_sha256 = datasets$sha256[[2L]],
    iterations = iterations,
    workload = "stata-first-save-to-dtaparser-roundtrip",
    fixture_storage_schema = stata_fixture_schema,
    fixture_creator = "stata-first-save",
    fixture_generator_sha256 = stata_generator_sha256,
    stata_save_state = "first-save-after-generate",
    dtaparser_input = "exact-stata-first-save-output",
    execution_order = if (setequal(writers, c("dtaparser", "stata"))) {
        "stata-before-dtaparser"
    } else paste0(writers, "-only"),
    writers = paste(writers, collapse = ","),
    r_version = R.version.string,
    r_platform = R.version$platform,
    dtaparser_version = as.character(utils::packageVersion("dtaparser")),
    dtaparser_path = normalizePath(find.package("dtaparser"), winslash = "/"),
    os_version = unname(Sys.info()[["version"]]),
    machine = unname(Sys.info()[["machine"]]),
    stringsAsFactors = FALSE, check.names = FALSE
), runtime_binding)
validate_write_result_matrix(
    raw, datasets$dataset, writers, iterations, "synthetic write"
)
if (setequal(writers, c("dtaparser", "stata"))) {
    pairs <- split(raw, interaction(
        raw$dataset, raw$iteration, drop = TRUE
    ))
    exact_pair <- vapply(pairs, function(pair) {
        nrow(pair) == 2L && length(unique(pair$input_sha256)) == 1L &&
            identical(
                pair$writer[order(pair$writer_order)],
                c("stata", "dtaparser")
            )
    }, logical(1L))
    if (!all(exact_pair)) {
        stop("dtaparser did not consume each exact timed Stata output")
    }
}
if (!identical(
    write_runtime_binding(rscript, packages = "processx", stata = stata),
    runtime_binding
)) {
    stop("benchmark runtime changed during synthetic writes")
}

finalize_write_results(
    raw, stable_provenance, outputs, datasets$dataset, writers,
    "input_bytes"
)
