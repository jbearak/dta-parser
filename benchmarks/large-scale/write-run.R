args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
    stop(paste(
        "usage: write-run.R DATASETS_TSV RAW_TSV SUMMARY_TSV",
        "PROVENANCE_TSV ITERATIONS"
    ))
}

manifest_path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
outputs <- vapply(args[2:4], normalizePath, character(1), winslash = "/",
                  mustWork = FALSE)
iterations <- suppressWarnings(as.integer(args[[5L]]))
if (length(iterations) != 1L || is.na(iterations) || iterations < 1L ||
    as.character(iterations) != args[[5L]]) {
    stop("write iterations must be a positive integer")
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_path <- normalizePath(sub("^--file=", "", script_argument), winslash = "/")
script_dir <- dirname(script_path)
checkout_root <- normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
sys.source(file.path(script_dir, "provenance.R"), envir = environment())

benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
benchmark_library <- normalizePath(benchmark_library, winslash = "/", mustWork = TRUE)
if (!startsWith(benchmark_library, paste0(checkout_root, "/"))) {
    stop("DTAPARSER_BENCH_LIB must be inside this checkout")
}
build_provenance_path <- file.path(
    benchmark_library, "dtaparser-benchmark-provenance.tsv"
)
build_provenance <- verify_benchmark_provenance(
    checkout_root, benchmark_library, build_provenance_path
)
.libPaths(c(benchmark_library, .libPaths()))
for (package in c("dtaparser", "haven", "processx")) {
    if (!requireNamespace(package, quietly = TRUE)) stop(package, " is required")
}
if (!identical(
    normalizePath(dirname(find.package("dtaparser")), winslash = "/"),
    benchmark_library
)) stop("dtaparser was not loaded from DTAPARSER_BENCH_LIB")

target_root <- normalizePath(
    file.path(checkout_root, "target", "large-scale"), winslash = "/",
    mustWork = TRUE
)
if (!identical(manifest_path, file.path(target_root, "datasets.tsv"))) {
    stop("dataset manifest must be target/large-scale/datasets.tsv")
}
output_parents <- vapply(outputs, function(path) {
    normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
}, character(1))
if (length(unique(output_parents)) != 1L ||
    !startsWith(basename(output_parents[[1L]]), ".run.") ||
    !identical(dirname(output_parents[[1L]]), target_root)) {
    stop("synthetic write artifacts must share the large-scale run staging directory")
}

datasets <- read.delim(
    manifest_path, check.names = FALSE, stringsAsFactors = FALSE,
    colClasses = "character"
)
required <- c("dataset", "path", "actual_bytes", "sha256", "rows")
if (!all(required %in% names(datasets)) ||
    !identical(datasets$dataset, c("100mb", "1gb"))) {
    stop("dataset manifest is invalid")
}
expected_paths <- file.path(
    target_root, c("synthetic-100mb.dta", "synthetic-1gb.dta")
)
datasets$path <- vapply(datasets$path, normalizePath, character(1), winslash = "/")
datasets$actual_bytes <- suppressWarnings(as.numeric(datasets$actual_bytes))
datasets$rows <- suppressWarnings(as.numeric(datasets$rows))
if (!identical(unname(datasets$path), expected_paths) ||
    any(!is.finite(datasets$actual_bytes) | datasets$actual_bytes <= 0) ||
    any(!is.finite(datasets$rows) | datasets$rows <= 0) ||
    !identical(as.double(file.info(expected_paths)$size), datasets$actual_bytes)) {
    stop("synthetic dataset paths or sizes are invalid")
}
actual_hashes <- tolower(unname(tools::sha256sum(expected_paths)))
if (!identical(actual_hashes, tolower(datasets$sha256))) {
    stop("synthetic dataset hashes do not match the manifest")
}
datasets$sha256 <- actual_hashes

rscript <- Sys.which("Rscript")
stata_candidates <- unique(c(
    Sys.getenv("STATA_BIN"),
    "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
    Sys.which("stata-mp"), Sys.which("stata")
))
stata_candidates <- stata_candidates[nzchar(stata_candidates)]
stata_candidates <- stata_candidates[file.exists(stata_candidates)]
if (!length(stata_candidates)) stop("Stata is required; set STATA_BIN")
stata <- normalizePath(stata_candidates[[1L]], winslash = "/", mustWork = TRUE)
time_flag <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"

parse_memory <- function(stderr) {
    lines <- strsplit(stderr, "\n", fixed = TRUE)[[1L]]
    if (identical(Sys.info()[["sysname"]], "Darwin")) {
        line <- grep("maximum resident set size", lines, value = TRUE)
        if (!length(line)) return(NA_real_)
        as.numeric(sub("^ *([0-9]+).*$", "\\1", tail(line, 1L)))
    } else {
        line <- grep("Maximum resident set size [(]kbytes[)]", lines, value = TRUE)
        if (!length(line)) return(NA_real_)
        1024 * as.numeric(sub("^.*: *([0-9]+).*$", "\\1", tail(line, 1L)))
    }
}

parse_fields <- function(text, prefix) {
    lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
    marker <- grep(paste0("^", prefix, "\t"), lines, value = TRUE)
    if (!length(marker)) return(character())
    strsplit(tail(marker, 1L), "\t", fixed = TRUE)[[1L]][-1L]
}

run_timed <- function(command, arguments, work_dir) {
    processx::run(
        "/usr/bin/time", c(time_flag, command, arguments), wd = work_dir,
        env = c(
            DTAPARSER_BENCH_LIB = benchmark_library,
            R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
        ),
        error_on_status = FALSE, echo = FALSE
    )
}

measure <- function(dataset, writer, iteration, writer_order) {
    work_dir <- tempfile(
        pattern = paste0("synthetic-write-", dataset$dataset, "-", writer, "-"),
        tmpdir = output_parents[[1L]]
    )
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    input <- file.path(work_dir, "input.dta")
    if (!file.symlink(dataset$path, input)) stop("could not create input alias")
    if (writer == "stata") {
        file.copy(file.path(script_dir, "stata-write-worker.do"),
                  file.path(work_dir, "stata-write-worker.do"))
        process <- run_timed(
            stata, c("-q", "-b", "do", "stata-write-worker.do"), work_dir
        )
        result <- file.path(work_dir, "result.tsv")
        fields <- if (file.exists(result)) {
            strsplit(readLines(result, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]]
        } else character()
    } else {
        process <- run_timed(
            rscript,
            c("--vanilla", file.path(script_dir, "write-worker.R"),
              writer, input, file.path(work_dir, "output.dta")),
            work_dir
        )
        fields <- parse_fields(process$stdout, "SYNTHETIC_WRITE")
    }
    if (length(fields) != 6L || fields[[1L]] != writer || fields[[2L]] != "ok") {
        stop(writer, " synthetic write failed: ", process$stderr)
    }
    numeric <- suppressWarnings(as.numeric(fields[3:6]))
    rss <- parse_memory(process$stderr)
    if (any(!is.finite(numeric)) || numeric[[1L]] <= 0 ||
        numeric[[2L]] != dataset$rows || numeric[[3L]] <= 0 ||
        numeric[[4L]] <= 0 || !is.finite(rss) || rss <= 0) {
        stop(writer, " synthetic write returned invalid measurements")
    }
    data.frame(
        dataset = dataset$dataset, dataset_sha256 = dataset$sha256,
        input_bytes = dataset$actual_bytes, rows = numeric[[2L]],
        columns = numeric[[3L]], writer = writer, iteration = iteration,
        writer_order = writer_order, elapsed_seconds = numeric[[1L]],
        peak_rss_bytes = rss, output_bytes = numeric[[4L]],
        stringsAsFactors = FALSE
    )
}

writers <- c("dtaparser", "stata", "haven")
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
            message(dataset$dataset, " ", writer, " ", iteration, "/", iterations)
        }
    }
}
raw <- do.call(rbind, rows)

final_build <- verify_benchmark_provenance(
    checkout_root, benchmark_library, build_provenance_path
)
if (!identical(final_build$provenance_id, build_provenance$provenance_id) ||
    !identical(tolower(unname(tools::sha256sum(expected_paths))), datasets$sha256)) {
    stop("benchmark build or datasets changed during synthetic writes")
}
stable_provenance <- data.frame(
    schema_version = 1L,
    build_provenance_id = build_provenance$provenance_id[[1L]],
    manifest_sha256 = tolower(unname(tools::sha256sum(manifest_path))[[1L]]),
    dataset_100mb_sha256 = datasets$sha256[[1L]],
    dataset_1gb_sha256 = datasets$sha256[[2L]],
    iterations = iterations,
    r_version = R.version.string,
    r_platform = R.version$platform,
    dtaparser_version = as.character(utils::packageVersion("dtaparser")),
    dtaparser_path = normalizePath(find.package("dtaparser"), winslash = "/"),
    haven_version = as.character(utils::packageVersion("haven")),
    haven_path = normalizePath(find.package("haven"), winslash = "/"),
    stata_path = stata,
    stata_sha256 = tolower(unname(tools::sha256sum(stata))[[1L]]),
    os_version = unname(Sys.info()[["version"]]),
    machine = unname(Sys.info()[["machine"]]),
    stringsAsFactors = FALSE, check.names = FALSE
)
provenance_id <- benchmark_provenance_id(stable_provenance)
raw$provenance_id <- provenance_id
raw$build_provenance_id <- stable_provenance$build_provenance_id

expected <- expand.grid(
    dataset = datasets$dataset, writer = writers,
    iteration = seq_len(iterations), stringsAsFactors = FALSE
)
tuple <- function(data) paste(data$dataset, data$writer, data$iteration, sep = "\r")
if (anyDuplicated(tuple(raw)) || !setequal(tuple(raw), tuple(expected))) {
    stop("synthetic write results are not the exact expected matrix")
}

groups <- split(raw, interaction(raw$dataset, raw$writer, drop = TRUE))
summary <- do.call(rbind, lapply(groups, function(group) data.frame(
    dataset = group$dataset[[1L]], writer = group$writer[[1L]],
    iterations = nrow(group), input_bytes = group$input_bytes[[1L]],
    median_seconds = median(group$elapsed_seconds),
    p05_seconds = unname(stats::quantile(group$elapsed_seconds, 0.05)),
    p95_seconds = unname(stats::quantile(group$elapsed_seconds, 0.95)),
    median_peak_rss_bytes = median(group$peak_rss_bytes),
    median_output_bytes = median(group$output_bytes),
    provenance_id = provenance_id,
    build_provenance_id = group$build_provenance_id[[1L]],
    stringsAsFactors = FALSE
)))
summary <- summary[order(match(summary$dataset, datasets$dataset),
                         match(summary$writer, writers)), ]
provenance <- stable_provenance
provenance$provenance_id <- provenance_id
provenance$created_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

atomic_tsv <- function(value, path) {
    temporary <- tempfile(pattern = paste0(basename(path), "."),
                          tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    write.table(value, temporary, sep = "\t", row.names = FALSE, quote = FALSE)
    if (!file.rename(temporary, path)) stop("could not publish ", path)
}
atomic_tsv(raw, outputs[[1L]])
atomic_tsv(summary, outputs[[2L]])
atomic_tsv(provenance, outputs[[3L]])
print(summary, row.names = FALSE)
