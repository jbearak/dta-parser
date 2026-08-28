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

context <- initialize_write_runner(
    script_dir,
    paste(
        "usage: standard-r-write-run.R SIZES_TSV RAW_TSV SUMMARY_TSV",
        "PROVENANCE_TSV ITERATIONS"
    ),
    input_scope = "script",
    input_name = "standard-r-write-sizes.tsv",
    artifact_description = "standard-R write",
    required_packages = c("dtaparser", "haven", "processx")
)
sizes_path <- context$input_path
outputs <- context$outputs
iterations <- context$iterations
checkout_root <- context$checkout_root
benchmark_library <- context$benchmark_library
build_provenance_path <- context$build_provenance_path
build_provenance <- context$build_provenance
output_parent <- context$output_parent

fixture_path <- file.path(script_dir, "standard-r-write-fixture.R")
fixture_sha256 <- benchmark_file_sha256(fixture_path)
sizes_sha256 <- benchmark_file_sha256(sizes_path)
sys.source(fixture_path, envir = environment())
expected_schema <- standard_r_write_schema(make_standard_r_write_fixture(1L))

datasets <- read.delim(
    sizes_path, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character"
)
required <- c("dataset", "target_output_bytes", "rows")
if (!identical(names(datasets), required) ||
    !identical(datasets$dataset, c("100mb", "1gb"))) {
    stop("standard-R size specification is invalid")
}
datasets$target_output_bytes <- suppressWarnings(
    as.numeric(datasets$target_output_bytes)
)
datasets$rows <- suppressWarnings(as.integer(datasets$rows))
if (any(!is.finite(datasets$target_output_bytes) |
        datasets$target_output_bytes <= 0) ||
    any(is.na(datasets$rows) | datasets$rows <= 0L)) {
    stop("standard-R sizes or row counts are invalid")
}

rscript <- Sys.which("Rscript")
writers <- c("dtaparser", "haven")
runtime_binding <- write_runtime_binding(
    rscript, packages = c("haven", "processx")
)
benchmark_environment <- c(
    DTAPARSER_BENCH_LIB = benchmark_library,
    R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null", TZ = "UTC"
)

measure <- function(dataset, writer, iteration, writer_order) {
    work_dir <- tempfile(
        pattern = paste0("standard-r-write-", dataset$dataset, "-", writer, "-"),
        tmpdir = output_parent
    )
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    process <- run_timed_process(
        rscript,
        c("--vanilla", file.path(script_dir, "write-worker.R"), writer,
          "standard-r", as.character(dataset$rows),
          file.path(work_dir, "output.dta")),
        work_dir, benchmark_environment
    )
    fields <- parse_fields(process$stdout, "STANDARD_R_WRITE")
    if (length(fields) != 8L || fields[[1L]] != writer ||
        fields[[2L]] != "ok") {
        stop(writer, " standard-R write failed: ", process$stderr)
    }
    numeric <- suppressWarnings(as.numeric(fields[3:7]))
    rss <- parse_memory(process$stderr)
    if (any(!is.finite(numeric)) || numeric[[1L]] <= 0 ||
        numeric[[2L]] != dataset$rows ||
        numeric[[3L]] != standard_r_write_columns ||
        numeric[[4L]] <= 0 || numeric[[5L]] <= 0 ||
        !identical(fields[[8L]], expected_schema) ||
        !is.finite(rss) || rss <= 0) {
        stop(writer, " standard-R write returned invalid measurements")
    }
    data.frame(
        dataset = dataset$dataset,
        target_output_bytes = dataset$target_output_bytes,
        fixture_sha256 = fixture_sha256,
        rows = numeric[[2L]], columns = numeric[[3L]],
        input_object_bytes = numeric[[4L]], writer = writer,
        iteration = iteration, writer_order = writer_order,
        elapsed_seconds = numeric[[1L]], peak_rss_bytes = rss,
        output_bytes = numeric[[5L]], schema = fields[[8L]],
        stringsAsFactors = FALSE
    )
}

rows <- vector("list", nrow(datasets) * iterations * length(writers))
row_index <- 0L
for (dataset_index in seq_len(nrow(datasets))) {
    dataset <- datasets[dataset_index, , drop = FALSE]
    for (iteration in seq_len(iterations)) {
        shift <- (dataset_index + iteration - 2L) %% length(writers)
        order <- writers[c(seq.int(shift + 1L, length(writers)),
                           if (shift) seq_len(shift) else integer())]
        for (writer_order in seq_along(order)) {
            writer <- order[[writer_order]]
            row_index <- row_index + 1L
            rows[[row_index]] <- measure(dataset, writer, iteration, writer_order)
            message(dataset$dataset, " standard-R ", writer, " ", iteration,
                    "/", iterations)
        }
    }
}
raw <- do.call(rbind, rows)

final_build <- verify_benchmark_provenance(
    checkout_root, benchmark_library, build_provenance_path
)
if (!identical(final_build$provenance_id, build_provenance$provenance_id) ||
    !identical(benchmark_file_sha256(fixture_path), fixture_sha256) ||
    !identical(benchmark_file_sha256(sizes_path), sizes_sha256)) {
    stop(
        paste(
            "benchmark build, fixture, or size specification changed",
            "during writes"
        )
    )
}
stable_provenance <- cbind(data.frame(
    schema_version = 1L,
    workload = "standard-r-columns",
    build_provenance_id = build_provenance$provenance_id[[1L]],
    sizes_sha256 = sizes_sha256,
    fixture_sha256 = fixture_sha256,
    fixture_schema = expected_schema,
    rows_100mb = datasets$rows[[1L]],
    rows_1gb = datasets$rows[[2L]],
    iterations = iterations,
    writers = paste(writers, collapse = ","),
    r_version = R.version.string,
    r_platform = R.version$platform,
    dtaparser_version = as.character(utils::packageVersion("dtaparser")),
    dtaparser_path = normalizePath(find.package("dtaparser"), winslash = "/"),
    haven_version = as.character(utils::packageVersion("haven")),
    os_version = unname(Sys.info()[["version"]]),
    machine = unname(Sys.info()[["machine"]]),
    stringsAsFactors = FALSE, check.names = FALSE
), runtime_binding)
validate_write_result_matrix(
    raw, datasets$dataset, writers, iterations, "standard-R write"
)
if (!identical(
    write_runtime_binding(rscript, packages = c("haven", "processx")),
    runtime_binding
)) {
    stop("benchmark runtime changed during standard-R writes")
}
finalize_write_results(
    raw, stable_provenance, outputs, datasets$dataset, writers,
    c("rows", "target_output_bytes", "input_object_bytes")
)
