args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || length(args) > 4L ||
    !(args[[1L]] %in% c("qualify", "benchmark"))) {
    stop("usage: run.R qualify|benchmark CACHE_ROOT OUTPUT_DIR [MAX_FILES]")
}
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")

mode <- args[[1L]]
cache_root <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output_dir <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
max_files <- if (length(args) == 4L) as.integer(args[[4L]]) else Inf
if (length(max_files) != 1L || is.na(max_files) || max_files < 1L) {
    stop("MAX_FILES must be a positive integer")
}
script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"), local = TRUE)

benchmark_library <- benchmark_library_path()
installed_package <- benchmark_installed_package_path(benchmark_library)
source_tarball <- Sys.getenv("DTAPARSER_SOURCE_TARBALL")
if (!nzchar(source_tarball)) stop("DTAPARSER_SOURCE_TARBALL is required")
source_tarball <- normalizePath(source_tarball, winslash = "/", mustWork = TRUE)
source_sha256 <- Sys.getenv("DTAPARSER_SOURCE_SHA256")
if (!grepl("^[0-9a-f]{64}$", source_sha256) ||
    !identical(benchmark_file_sha256(source_tarball), source_sha256)) {
    stop("DTAPARSER_SOURCE_SHA256 must bind the installed source package")
}

rscript <- normalizePath(Sys.which("Rscript"), winslash = "/", mustWork = TRUE)
stata <- find_stata()
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

run_process <- function(
    command, arguments, working_directory = NULL, timed = FALSE
) {
    environment <- c(
        DTAPARSER_BENCH_LIB = benchmark_library,
        R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
    )
    if (timed) {
        return(run_timed_process(
            command, arguments, working_directory, environment
        ))
    }
    processx::run(
        command, arguments, wd = working_directory, env = environment,
        error_on_status = FALSE, echo = FALSE
    )
}

require_stata_mp <- function() {
    work_dir <- tempfile("stata-preflight-", tmpdir = output_dir)
    dir.create(work_dir)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    copied <- file.copy(
        file.path(script_dir, "stata-preflight.do"),
        file.path(work_dir, "stata-preflight.do")
    )
    if (!copied) stop("could not stage the Stata capability probe")
    process <- run_process(
        stata, c("-q", "-b", "do", "stata-preflight.do"), work_dir
    )
    result_path <- file.path(work_dir, "stata-preflight-result.tsv")
    status <- if (file.exists(result_path)) {
        readLines(result_path, n = 1L, warn = FALSE)
    } else character()
    if (process$status != 0L || !identical(status, "ok")) {
        message("Stata capability probe failed: ", process$stderr)
        stop("Stata/MP 18 or later with maxvar 120000 is required")
    }
    invisible(NULL)
}

require_stata_mp()

source_inventory_path <- file.path(output_dir, "corpus-inventory.tsv")
force_inventory <- identical(
    Sys.getenv("DTAPARSER_ROUNDTRIP_VERIFY_INVENTORY"), "1"
)
if (file.exists(source_inventory_path) && !force_inventory) {
    inventory <- roundtrip_cached_inventory(
        cache_root, source_inventory_path, max_files
    )
} else {
    inventory <- roundtrip_inventory(cache_root, max_files = max_files)
    source_inventory <- inventory[c(
        "corpus", "id", "relative_path", "release", "bytes", "modified",
        "sha256"
    )]
    benchmark_publish_or_verify_tsv(
        source_inventory,
        source_inventory_path,
        "corpus inventory drifted from this resumable run",
        "could not publish private source corpus inventory"
    )
}
inventory_path <- file.path(output_dir, "inventory.tsv")
inventory_public <- inventory[c(
    "corpus", "id", "relative_path", "release", "bytes", "sha256"
)]
inventory_hash <- benchmark_publish_or_verify_tsv(
    inventory_public,
    inventory_path,
    "corpus inventory drifted from this resumable run",
    "could not publish private corpus inventory"
)
binding_path <- file.path(output_dir, "run-binding.tsv")
current_binding <- function() {
    current_source_sha256 <- benchmark_file_sha256(source_tarball)
    cbind(
        data.frame(
            schema_version = 4L,
            inventory_sha256 = inventory_hash,
            package_sha256 = benchmark_directory_sha256(installed_package),
            source_tarball_sha256 = current_source_sha256,
            harness_sha256 = benchmark_harness_sha256(script_dir),
            stringsAsFactors = FALSE
        ),
        benchmark_runtime_binding(stata, rscript_executable = rscript)
    )
}
binding <- current_binding()
package_hash <- binding$package_sha256[[1L]]
assert_current_binding <- function() {
    if (!identical(current_binding(), binding)) {
        stop("benchmark build, harness, runtime, or comparator changed during the run")
    }
    invisible(NULL)
}
benchmark_publish_or_verify_binding(
    binding,
    binding_path,
    file.path(
        output_dir,
        c("qualification-raw.tsv", "qualification.tsv", "benchmark-raw.tsv")
    ),
    paste0(
        "resumable results belong to a different inventory, ",
        "package build, benchmark harness, runtime, or comparator"
    ),
    "existing results do not have a resumable run binding"
)

parse_marker <- function(output, prefix, fields,
                         failure_status = "worker-error") {
    values <- parse_fields(output, prefix)
    if (length(values) != length(fields)) {
        values <- rep(NA_character_, length(fields))
        values[[1L]] <- failure_status
    }
    stats::setNames(as.list(values), fields)
}

stata_open <- function(output, expected_rows, expected_columns, work_dir) {
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    if (!file.symlink(output, file.path(work_dir, "output.dta"))) {
        return("stata-alias-error")
    }
    file.copy(file.path(script_dir, "stata-open.do"),
              file.path(work_dir, "stata-open.do"), overwrite = TRUE)
    process <- run_process(stata, c("-q", "-b", "do", "stata-open.do"), work_dir)
    result_path <- file.path(work_dir, "stata-result.tsv")
    if (!file.exists(result_path)) {
        message("Stata-open worker failed: ", process$stderr)
        return("stata-worker-error")
    }
    fields <- strsplit(readLines(result_path, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]]
    if (length(fields) != 3L || fields[[1L]] != "stata-pass" ||
        as.numeric(fields[[2L]]) != expected_rows ||
        as.numeric(fields[[3L]]) != expected_columns) {
        return("stata-mismatch")
    }
    "pass"
}

qualify_wide <- function() {
    work_dir <- file.path(output_dir, "qualification-wide")
    unlink(work_dir, recursive = TRUE, force = TRUE)
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    output <- file.path(work_dir, "wide.dta")
    generated <- run_process(
        rscript,
        c("--vanilla", file.path(script_dir, "wide-generate.R"), output)
    )
    if (generated$status != 0L || !file.exists(output)) {
        message("Wide generator failed: ", generated$stderr)
        return("r-worker-error")
    }
    if (!identical(corpus_dta_release(output), 119L)) return("release-mismatch")
    verified <- run_process(
        rscript,
        c("--vanilla", file.path(script_dir, "wide-verify.R"), output)
    )
    if (verified$status != 0L) {
        message("Wide R verification failed: ", verified$stderr)
        return("r-mismatch")
    }
    stata_open(output, 1, 32768, file.path(work_dir, "stata"))
}

write_private_report <- function(raw, path, title) {
    counts <- aggregate(id ~ corpus + status, raw, length)
    names(counts)[[3L]] <- "files"
    lines <- c(
        paste0("# ", title), "",
        "This privacy-safe report describes a hash-bound local cache inventory; it is not an upstream-authoritative corpus manifest.", "",
        paste0("Inventory SHA-256: `", inventory_hash, "`"),
        paste0("Installed package SHA-256: `", package_hash, "`"), "",
        "| Corpus | Status | Files |", "| --- | --- | ---: |",
        apply(counts, 1L, function(row) paste0("| ", row[[1L]], " | ", row[[2L]], " | ", row[[3L]], " |"))
    )
    writeLines(lines, path, useBytes = TRUE)
}

qualification_path <- file.path(output_dir, "qualification.tsv")
if (identical(mode, "qualify")) {
    raw_path <- file.path(output_dir, "qualification-raw.tsv")
    completed <- if (file.exists(raw_path)) {
        existing <- read.delim(
            raw_path,
            check.names = FALSE,
            stringsAsFactors = FALSE
        )
        successful <- roundtrip_qualification_successes(existing)
        if (nrow(successful) != nrow(existing)) {
            atomic_tsv(successful, raw_path, quote = TRUE)
        }
        new_key_set(successful$id)
    } else {
        new_key_set()
    }
    ordered <- inventory[order(inventory$bytes, inventory$relative_path, method = "radix"), ]
    work_root <- file.path(output_dir, "qualification-work")
    dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
    for (index in seq_len(nrow(ordered))) {
        item <- ordered[index, , drop = FALSE]
        if (key_set_contains(completed, item$id)) next
        exclusion <- roundtrip_exclusion_reason(item)
        if (!is.na(exclusion)) {
            row <- data.frame(
                corpus = item$corpus, id = item$id, release = item$release,
                status = "expected-exclusion", rows = NA_real_, columns = NA_real_,
                output_bytes = NA_real_, stringsAsFactors = FALSE
            )
        } else {
            work_dir <- file.path(work_root, item$id)
            dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
            input <- benchmark_snapshot_file(
                item$path, file.path(work_dir, "input.dta"),
                item$bytes, item$sha256
            )
            output <- file.path(work_dir, "roundtrip.dta")
            process <- run_process(
                rscript,
                c("--vanilla", file.path(script_dir, "qualify-worker.R"), input, output)
            )
            marker <- parse_marker(
                process$stdout, "DTAPARSER_ROUNDTRIP",
                c("status", "rows", "columns", "output_bytes"),
                failure_status = "r-worker-error"
            )
            status <- marker$status
            rows <- as.numeric(marker$rows)
            columns <- as.numeric(marker$columns)
            output_bytes <- as.numeric(marker$output_bytes)
            if (!identical(status, "r-pass")) {
                message("Qualification worker diagnostics: ", process$stderr)
            }
            if (identical(status, "r-pass")) {
                status <- stata_open(
                    output, rows, columns,
                    file.path(work_dir, "stata")
                )
            }
            if (file.exists(output)) unlink(output)
            row <- data.frame(
                corpus = item$corpus, id = item$id, release = item$release,
                status = status, rows = rows, columns = columns,
                output_bytes = output_bytes, stringsAsFactors = FALSE
            )
            unlink(work_dir, recursive = TRUE, force = TRUE)
        }
        append_tsv(row, raw_path)
        key_set_add(completed, item$id)
        message(length(completed), "/", nrow(ordered), ": ", item$id, " ", row$status)
    }
    raw <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
    if (anyDuplicated(raw$id)) stop("qualification contains duplicate file IDs")
    pass <- sum(raw$status == "pass")
    excluded <- sum(raw$status == "expected-exclusion")
    failures <- nrow(raw) - pass - excluded
    if (failures == 0L) {
        raw <- roundtrip_validate_complete_qualification(raw, inventory)
    }
    qualification_raw_hash <- benchmark_file_sha256(raw_path)
    previous <- if (file.exists(qualification_path)) {
        read.delim(
            qualification_path, check.names = FALSE,
            stringsAsFactors = FALSE
        )
    } else NULL
    reuse_wide <- !is.null(previous) && nrow(previous) == 1L &&
        identical(previous$status, "complete") &&
        identical(previous$inventory_sha256, inventory_hash) &&
        identical(previous$package_sha256, package_hash) &&
        identical(previous$source_tarball_sha256, source_sha256) &&
        identical(previous$qualification_raw_sha256, qualification_raw_hash) &&
        identical(previous$synthetic_wide, "pass")
    wide_status <- if (reuse_wide) "pass" else qualify_wide()
    if (!is.finite(max_files) &&
        (nrow(raw) != 1823L || pass != 1821L || excluded != 2L || failures != 0L)) {
        stop("full qualification did not achieve 1,821 passes and two bound exclusions")
    }
    assert_current_binding()
    manifest <- data.frame(
        schema_version = 2L,
        status = roundtrip_qualification_status(failures, wide_status),
        inventory_sha256 = inventory_hash, package_sha256 = package_hash,
        source_tarball_sha256 = source_sha256,
        qualification_raw_sha256 = qualification_raw_hash,
        inventoried = nrow(raw), passed = pass, excluded = excluded,
        failed = failures, synthetic_wide = wide_status,
        stringsAsFactors = FALSE
    )
    atomic_tsv(manifest, file.path(output_dir, "qualification.tsv"))
    write_private_report(raw, file.path(output_dir, "qualification-report.md"),
                         "DTA write qualification")
    if (failures != 0L || wide_status != "pass") {
        stop("qualification failures remain")
    }
    quit(status = 0L)
}

qualification_raw_path <- file.path(output_dir, "qualification-raw.tsv")
if (!file.exists(qualification_path) || !file.exists(qualification_raw_path)) {
    stop("benchmark requires a completed qualification")
}
qualification <- read.delim(qualification_path, check.names = FALSE,
                            stringsAsFactors = FALSE)
qualification_raw_hash <- benchmark_file_sha256(qualification_raw_path)
if (nrow(qualification) != 1L || qualification$status != "complete" ||
    qualification$inventory_sha256 != inventory_hash ||
    qualification$package_sha256 != package_hash ||
    qualification$source_tarball_sha256 != source_sha256 ||
    qualification$qualification_raw_sha256 != qualification_raw_hash ||
    qualification$synthetic_wide != "pass") {
    stop("benchmark build or inventory differs from successful qualification")
}
qualification_raw <- read.delim(
    qualification_raw_path, check.names = FALSE, stringsAsFactors = FALSE
)
qualification_raw <- roundtrip_validate_complete_qualification(
    qualification_raw, inventory
)
qualification_counts <- c(
    inventoried = nrow(qualification_raw),
    passed = sum(qualification_raw$status == "pass"),
    excluded = sum(qualification_raw$status == "expected-exclusion"),
    failed = 0L
)
if (!identical(
    as.integer(unlist(
        qualification[names(qualification_counts)], use.names = FALSE
    )),
    unname(as.integer(qualification_counts))
)) {
    stop("qualification manifest counts do not match its bound rows")
}
qualified_ids <- qualification_raw$id[qualification_raw$status == "pass"]
selected <- inventory[match(qualified_ids, inventory$id), ]
selected <- selected[order(-selected$bytes, selected$relative_path, method = "radix"), ]

benchmark_path <- file.path(output_dir, "benchmark-raw.tsv")
completed <- if (file.exists(benchmark_path)) {
    existing <- read.delim(
        benchmark_path, check.names = FALSE, stringsAsFactors = FALSE
    )
    required <- c("id", "writer", "status", "input_sha256")
    if (!all(required %in% names(existing)) ||
        anyNA(existing$input_sha256) ||
        any(!grepl("^[0-9a-f]{64}$", existing$input_sha256))) {
        stop("benchmark checkpoint is missing bound input identities")
    }
    keys <- paste(existing$id, existing$writer, sep = "\037")
    if (anyDuplicated(keys)) stop("benchmark contains duplicate writer measurements")
    successful <- existing[existing$status == "ok", , drop = FALSE]
    if (nrow(successful) != nrow(existing)) {
        atomic_tsv(successful, benchmark_path, quote = TRUE)
    }
    new_key_set(paste(successful$id, successful$writer, sep = "\037"))
} else {
    new_key_set()
}
work_root <- file.path(output_dir, "benchmark-work")
dir.create(work_root, recursive = TRUE, showWarnings = FALSE)

wide_id <- "synthetic-wide-32768"
wide_keys <- paste(wide_id, c("dtaparser", "stata"), sep = "\037")
wide_completed <- vapply(
    wide_keys,
    function(key) key_set_contains(completed, key),
    logical(1L)
)
wide_source <- file.path(output_dir, "synthetic-wide-input.dta")
wide_manifest_path <- file.path(output_dir, "synthetic-wide-input.tsv")
if (xor(file.exists(wide_source), file.exists(wide_manifest_path))) {
    if (any(wide_completed)) {
        stop("the resumable synthetic-wide input is incomplete")
    }
    unlink(c(wide_source, wide_manifest_path))
}
if (!file.exists(wide_source)) {
    if (any(wide_completed)) {
        stop("completed synthetic-wide rows have no bound input")
    }
    staged_wide <- tempfile(
        pattern = "synthetic-wide-input.", tmpdir = output_dir,
        fileext = ".dta"
    )
    on.exit(unlink(staged_wide), add = TRUE)
    wide_generation <- run_process(
        rscript,
        c("--vanilla", file.path(script_dir, "wide-generate.R"), staged_wide)
    )
    if (wide_generation$status != 0L || !file.exists(staged_wide) ||
        !identical(corpus_dta_release(staged_wide), 119L)) {
        stop("could not generate the qualified release-119 benchmark input")
    }
    wide_info <- file.info(staged_wide, extra_cols = FALSE)
    wide_manifest <- data.frame(
        schema_version = 1L,
        bytes = as.double(wide_info$size[[1L]]),
        sha256 = benchmark_file_sha256(staged_wide),
        release = 119L,
        stringsAsFactors = FALSE
    )
    if (!file.rename(staged_wide, wide_source)) {
        stop("could not publish the resumable synthetic-wide input")
    }
    atomic_tsv(wide_manifest, wide_manifest_path)
} else {
    wide_manifest <- read.delim(
        wide_manifest_path, check.names = FALSE, stringsAsFactors = FALSE
    )
}
if (!identical(
        names(wide_manifest),
        c("schema_version", "bytes", "sha256", "release")
    ) || nrow(wide_manifest) != 1L ||
    !identical(as.integer(wide_manifest$schema_version), 1L) ||
    !identical(as.integer(wide_manifest$release), 119L) ||
    nzchar(Sys.readlink(wide_source)) || !file_test("-f", wide_source) ||
    as.double(wide_manifest$bytes) !=
        as.double(file.info(wide_source)$size[[1L]]) ||
    !identical(
        tolower(as.character(wide_manifest$sha256)),
        benchmark_file_sha256(wide_source)
    ) || !identical(corpus_dta_release(wide_source), 119L)) {
    stop("the resumable synthetic-wide input differs from its manifest")
}
wide_info <- file.info(wide_source, extra_cols = FALSE)
selected <- rbind(selected, data.frame(
    corpus = "synthetic-wide", id = wide_id,
    relative_path = "generated/32768-variables.dta",
    path = wide_source, release = 119L,
    bytes = as.double(wide_info$size[[1L]]),
    modified = sprintf("%.6f", as.numeric(wide_info$mtime[[1L]])),
    sha256 = as.character(wide_manifest$sha256[[1L]]),
    stringsAsFactors = FALSE
))

measure_dtaparser <- function(item, order_index) {
    work_dir <- file.path(work_root, paste0(item$id, "-dtaparser"))
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    output <- file.path(work_dir, "output.dta")
    process <- run_process(
        rscript,
        c("--vanilla", file.path(script_dir, "write-worker.R"), item$path, output),
        timed = TRUE
    )
    marker <- parse_marker(process$stdout, "DTAPARSER_WRITE", c("status", "elapsed", "bytes"))
    data.frame(
        corpus = item$corpus, id = item$id, release = item$release,
        input_sha256 = item$sha256,
        writer = "dtaparser", writer_order = order_index,
        status = marker$status,
        elapsed_seconds = as.numeric(marker$elapsed),
        rss_bytes = parse_memory(process$stderr),
        output_bytes = as.numeric(marker$bytes),
        stringsAsFactors = FALSE
    )
}

measure_stata <- function(item, order_index) {
    work_dir <- file.path(work_root, paste0(item$id, "-stata"))
    dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(work_dir, recursive = TRUE, force = TRUE), add = TRUE)
    if (!file.symlink(item$path, file.path(work_dir, "input.dta"))) {
        status <- "input-alias-error"
        elapsed <- output_bytes <- rss <- NA_real_
    } else {
        file.copy(file.path(script_dir, "stata-write.do"),
                  file.path(work_dir, "stata-write.do"), overwrite = TRUE)
        process <- run_process(
            stata, c("-q", "-b", "do", "stata-write.do"), work_dir,
            timed = TRUE
        )
        result_path <- file.path(work_dir, "stata-write-result.tsv")
        fields <- if (file.exists(result_path)) {
            strsplit(readLines(result_path, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]]
        } else character()
        status <- if (length(fields) >= 2L) fields[[1L]] else "worker-error"
        elapsed <- if (length(fields) >= 2L) as.numeric(fields[[2L]]) else NA_real_
        output <- file.path(work_dir, "stata-output.dta")
        output_bytes <- if (file.exists(output)) file.info(output)$size[[1L]] else NA_real_
        rss <- parse_memory(process$stderr)
    }
    data.frame(
        corpus = item$corpus, id = item$id, release = item$release,
        input_sha256 = item$sha256,
        writer = "stata", writer_order = order_index, status = status,
        elapsed_seconds = elapsed, rss_bytes = rss, output_bytes = output_bytes,
        stringsAsFactors = FALSE
    )
}

for (index in seq_len(nrow(selected))) {
    item <- selected[index, , drop = FALSE]
    writers <- if (index %% 2L) c("dtaparser", "stata") else c("stata", "dtaparser")
    keys <- paste(item$id, writers, sep = "\037")
    pending <- !vapply(
        keys, function(key) key_set_contains(completed, key), logical(1L)
    )
    if (any(pending)) {
        input_dir <- file.path(work_root, paste0(item$id, "-source"))
        unlink(input_dir, recursive = TRUE, force = TRUE)
        dir.create(input_dir, recursive = TRUE, showWarnings = FALSE)
        item$path <- benchmark_snapshot_file(
            item$path, file.path(input_dir, "input.dta"),
            item$bytes, item$sha256
        )
        for (writer_index in seq_along(writers)) {
            if (!pending[[writer_index]]) next
            writer <- writers[[writer_index]]
            row <- if (writer == "dtaparser") {
                measure_dtaparser(item, writer_index)
            } else measure_stata(item, writer_index)
            append_tsv(row, benchmark_path)
            key_set_add(completed, keys[[writer_index]])
        }
        unlink(input_dir, recursive = TRUE, force = TRUE)
    }
    message(index, "/", nrow(selected), ": ", item$id)
}

raw <- read.delim(benchmark_path, check.names = FALSE, stringsAsFactors = FALSE)
roundtrip_validate_benchmark_matrix(
    raw, selected, c("dtaparser", "stata")
)
summary <- aggregate(
    cbind(elapsed_seconds, output_bytes) ~ corpus + release + writer,
    raw, sum
)
peak <- aggregate(
    raw["rss_bytes"], raw[c("corpus", "release", "writer")],
    function(values) if (all(is.na(values))) NA_real_ else max(values, na.rm = TRUE)
)
summary <- merge(summary, peak, by = c("corpus", "release", "writer"))
counts <- aggregate(id ~ corpus + release + writer, raw, length)
names(counts)[[4L]] <- "files"
summary <- merge(summary, counts, by = c("corpus", "release", "writer"))
summary <- summary[c(
    "corpus", "release", "writer", "files", "elapsed_seconds",
    "rss_bytes", "output_bytes"
)]
assert_current_binding()
if (!identical(
    benchmark_file_sha256(qualification_raw_path),
    qualification_raw_hash
) || !identical(
    benchmark_file_sha256(wide_source),
    tolower(as.character(wide_manifest$sha256))
)) {
    stop("qualified benchmark inputs changed before publication")
}
atomic_tsv(summary, file.path(output_dir, "benchmark-summary.tsv"))
report_lines <- c(
    "# DTA write benchmark", "",
    paste0(
        "This report covers the package build and hash-bound local cache inventory ",
        "that passed qualification. It does not identify private input paths."
    ), "",
    paste0("Inventory SHA-256: `", inventory_hash, "`"),
    paste0("Installed package SHA-256: `", package_hash, "`"), "",
    "| Corpus | Source release | Writer | Files | Total seconds | Peak RSS (GB) | Output (GB) |",
    "| --- | ---: | --- | ---: | ---: | ---: | ---: |",
    apply(summary, 1L, function(row) paste0(
        "| ", row[["corpus"]], " | ", row[["release"]], " | ",
        row[["writer"]], " | ", row[["files"]], " | ",
        sprintf("%.3f", as.numeric(row[["elapsed_seconds"]])), " | ",
        sprintf("%.3f", as.numeric(row[["rss_bytes"]]) / 1e9), " | ",
        sprintf("%.3f", as.numeric(row[["output_bytes"]]) / 1e9), " |"
    ))
)
writeLines(report_lines, file.path(output_dir, "benchmark-report.md"), useBytes = TRUE)
