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
    required_packages = c("dtatools", "haven", "processx")
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

writer_selection <- Sys.getenv("DTATOOLS_WRITE_WRITERS")
writers <- if (nzchar(writer_selection)) {
    strsplit(writer_selection, ",", fixed = TRUE)[[1L]]
} else c("dtatools", "haven", "stata")
allowed_writers <- c("dtatools", "haven", "stata")
if (!length(writers) || any(!writers %in% allowed_writers) ||
    anyDuplicated(writers)) {
    stop("DTATOOLS_WRITE_WRITERS must select unique supported writers")
}
r_writers <- writers[writers != "stata"]

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
    rscript, packages = c("haven", "processx"), stata = stata
)
benchmark_environment <- c(
    DTATOOLS_BENCH_LIB = benchmark_library,
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
    if (length(r_writers)) {
        shift <- (match(dataset$dataset, datasets$dataset) + iteration - 2L) %%
            length(r_writers)
        order <- r_writers[c(
            seq.int(shift + 1L, length(r_writers)),
            if (shift) seq_len(shift) else integer()
        )]
        for (index in seq_along(order)) {
            writer <- order[[index]]
            process <- run_timed_process(
                rscript,
                c("--vanilla", file.path(script_dir, "write-worker.R"),
                  writer, "stata-storage", input,
                  file.path(work_dir, paste0(writer, "-output.dta"))),
                work_dir, benchmark_environment
            )
            fields <- parse_fields(process$stdout, "SYNTHETIC_WRITE")
            results[[length(results) + 1L]] <- measurement_row(
                dataset, input_sha256, writer, iteration,
                index + as.integer("stata" %in% writers),
                fields, process$stderr
            )
            message(
                dataset$dataset, " ", writer, " ", iteration, "/", iterations
            )
        }
    }
    results
}

validate_full_scale_output <- function(dataset, writer) {
    work_dir <- tempfile(
        pattern = paste0("synthetic-write-validation-", dataset$dataset, "-"),
        tmpdir = output_parent
    )
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    output <- file.path(work_dir, paste0(writer, "-output.dta"))
    process <- processx::run(
        rscript,
        c("--vanilla", file.path(script_dir, "write-worker.R"),
          writer, "stata-storage", dataset$path, output),
        wd = work_dir, env = benchmark_environment,
        error_on_status = FALSE, echo = FALSE
    )
    fields <- parse_fields(process$stdout, "SYNTHETIC_WRITE")
    measurement <- tryCatch(
        parse_fixture_write_result(fields, writer),
        error = function(condition) {
            stop(conditionMessage(condition), ": ", process$stderr)
        }
    )
    if (measurement$rows != dataset$rows ||
        measurement$columns != stata_fixture_columns ||
        measurement$bytes <= 0 || !file.exists(output)) {
        stop(writer, " full-scale validation write returned invalid output")
    }
    validation <- processx::run(
        rscript,
        c("--vanilla", file.path(script_dir, "validate-write-output.R"),
          writer, dataset$path, output),
        wd = work_dir, env = benchmark_environment,
        error_on_status = FALSE, echo = FALSE
    )
    validation_fields <- parse_fields(validation$stdout, "WRITE_VALIDATION")
    expected_prefix <- c(
        writer, "ok", as.character(dataset$rows),
        as.character(stata_fixture_columns)
    )
    if (length(validation_fields) != 8L ||
        !identical(validation_fields[1:4], expected_prefix) ||
        validation$status != 0L) {
        stop(
            writer, " full-scale output validation failed: ",
            validation$stderr
        )
    }
    message(dataset$dataset, " ", writer, " full-scale validation")
    data.frame(
        dataset = dataset$dataset, dataset_sha256 = dataset$sha256,
        writer = writer, rows = measurement$rows,
        columns = measurement$columns, output_bytes = measurement$bytes,
        parity_status = validation_fields[[5L]],
        storage_status = validation_fields[[6L]],
        input_storage_schema = validation_fields[[7L]],
        output_storage_schema = validation_fields[[8L]],
        stringsAsFactors = FALSE
    )
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

validation <- if (length(r_writers)) {
    do.call(rbind, lapply(seq_len(nrow(datasets)), function(dataset_index) {
        dataset <- datasets[dataset_index, , drop = FALSE]
        do.call(rbind, lapply(r_writers, function(writer) {
            validate_full_scale_output(dataset, writer)
        }))
    }))
} else data.frame()

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
    workload = "stata-first-save-to-r-writers",
    fixture_storage_schema = stata_fixture_schema,
    fixture_creator = "stata-first-save",
    fixture_generator_sha256 = stata_generator_sha256,
    stata_save_state = "first-save-after-generate",
    r_writer_input = "exact-stata-first-save-output-read-by-dtatools",
    full_scale_validation = paste(
        "untimed-dtatools-semantic-and-haven-model-parity",
        "with-storage-schema-each-size"
    ),
    execution_order = if ("stata" %in% writers && length(r_writers)) {
        "stata-then-rotating-r-writers"
    } else if (length(r_writers) > 1L) {
        "rotating-r-writers"
    } else paste0(writers, "-only"),
    writers = paste(writers, collapse = ","),
    r_version = R.version.string,
    r_platform = R.version$platform,
    dtatools_version = as.character(utils::packageVersion("dtatools")),
    dtatools_path = normalizePath(find.package("dtatools"), winslash = "/"),
    haven_version = as.character(utils::packageVersion("haven")),
    os_version = unname(Sys.info()[["version"]]),
    machine = unname(Sys.info()[["machine"]]),
    stringsAsFactors = FALSE, check.names = FALSE
), runtime_binding)
validate_write_result_matrix(
    raw, datasets$dataset, writers, iterations, "synthetic write"
)
if ("stata" %in% writers && length(r_writers)) {
    pairs <- split(raw, interaction(
        raw$dataset, raw$iteration, drop = TRUE
    ))
    exact_pair <- vapply(pairs, function(pair) {
        ordered_writers <- pair$writer[order(pair$writer_order)]
        nrow(pair) == length(writers) &&
            length(unique(pair$input_sha256)) == 1L &&
            identical(ordered_writers[[1L]], "stata") &&
            setequal(ordered_writers[-1L], r_writers)
    }, logical(1L))
    if (!all(exact_pair)) {
        stop("R writers did not consume each exact timed Stata output")
    }
}
if (!identical(
    write_runtime_binding(
        rscript, packages = c("haven", "processx"), stata = stata
    ),
    runtime_binding
)) {
    stop("benchmark runtime changed during synthetic writes")
}

if (nrow(validation)) {
    validation$provenance_id <- benchmark_provenance_id(stable_provenance)
    validation$build_provenance_id <- stable_provenance$build_provenance_id
    atomic_tsv(
        validation, file.path(output_parent, "write-validation.tsv")
    )
}

finalize_write_results(
    raw, stable_provenance, outputs, datasets$dataset, writers,
    "input_bytes"
)
