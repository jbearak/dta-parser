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

benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
benchmark_library <- normalizePath(benchmark_library, winslash = "/", mustWork = TRUE)
installed_package <- system.file(package = "dtaparser", lib.loc = benchmark_library,
                                 mustWork = TRUE)
package_hash <- roundtrip_directory_hash(installed_package)
source_sha256 <- Sys.getenv("DTAPARSER_SOURCE_SHA256")
if (!grepl("^[0-9a-f]{64}$", source_sha256)) {
    stop("DTAPARSER_SOURCE_SHA256 must bind the installed source package")
}

rscript <- Sys.which("Rscript")
time_command <- "/usr/bin/time"
stata_candidates <- unique(c(
    Sys.getenv("STATA_BIN"),
    "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
    Sys.which("stata-mp"), Sys.which("stata")
))
stata_candidates <- stata_candidates[nzchar(stata_candidates)]
stata_candidates <- stata_candidates[file.exists(stata_candidates)]
if (!length(stata_candidates)) stop("Stata is required; set STATA_BIN")
stata <- normalizePath(stata_candidates[[1L]], winslash = "/", mustWork = TRUE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

inventory <- roundtrip_inventory(cache_root)
if (is.finite(max_files)) {
    inventory <- do.call(rbind, lapply(split(inventory, inventory$corpus), function(items) {
        head(items[order(-items$bytes, items$relative_path, method = "radix"), ], max_files)
    }))
    rownames(inventory) <- NULL
}
inventory_path <- file.path(output_dir, "inventory.tsv")
inventory_public <- inventory[c(
    "corpus", "id", "relative_path", "release", "bytes", "sha256"
)]
candidate_inventory <- tempfile("roundtrip-inventory-")
write.table(inventory_public, candidate_inventory, sep = "\t", row.names = FALSE,
            quote = TRUE)
candidate_inventory_hash <- roundtrip_manifest_hash(candidate_inventory)
if (file.exists(inventory_path)) {
    if (!identical(roundtrip_manifest_hash(inventory_path), candidate_inventory_hash)) {
        stop("corpus inventory drifted from this resumable run")
    }
} else if (!file.copy(candidate_inventory, inventory_path)) {
    stop("could not publish private corpus inventory")
}
inventory_hash <- roundtrip_manifest_hash(inventory_path)
unlink(candidate_inventory)
binding_path <- file.path(output_dir, "run-binding.tsv")
binding <- data.frame(
    schema_version = 1L,
    inventory_sha256 = inventory_hash,
    package_sha256 = package_hash,
    source_tarball_sha256 = source_sha256,
    stringsAsFactors = FALSE
)
if (file.exists(binding_path)) {
    existing_binding <- read.delim(
        binding_path, check.names = FALSE, stringsAsFactors = FALSE
    )
    if (!identical(existing_binding, binding)) {
        stop("resumable results belong to a different inventory or package build")
    }
} else {
    write.table(binding, binding_path, sep = "\t", row.names = FALSE,
                quote = FALSE)
}

run_process <- function(command, arguments, working_directory = NULL, timed = FALSE) {
    if (timed) {
        time_flag <- if (identical(Sys.info()[["sysname"]], "Darwin")) "-l" else "-v"
        arguments <- c(time_flag, command, arguments)
        command <- time_command
    }
    processx::run(
        command, arguments, wd = working_directory,
        env = c(
            DTAPARSER_BENCH_LIB = benchmark_library,
            R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
        ),
        error_on_status = FALSE, echo = FALSE
    )
}

parse_marker <- function(output, prefix, fields) {
    lines <- strsplit(output, "\n", fixed = TRUE)[[1L]]
    marker <- grep(paste0("^", prefix, "\t"), lines, value = TRUE)
    if (!length(marker)) return(NULL)
    values <- strsplit(tail(marker, 1L), "\t", fixed = TRUE)[[1L]]
    if (length(values) != length(fields) + 1L) return(NULL)
    stats::setNames(as.list(values[-1L]), fields)
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
    if (!identical(roundtrip_release(output), 119L)) return("release-mismatch")
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

if (identical(mode, "qualify")) {
    raw_path <- file.path(output_dir, "qualification-raw.tsv")
    completed <- if (file.exists(raw_path)) {
        existing <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
        existing$id
    } else character()
    ordered <- inventory[order(inventory$bytes, inventory$relative_path, method = "radix"), ]
    work_root <- file.path(output_dir, "qualification-work")
    dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
    for (index in seq_len(nrow(ordered))) {
        item <- ordered[index, , drop = FALSE]
        if (item$id %in% completed) next
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
            output <- file.path(work_dir, "roundtrip.dta")
            process <- run_process(
                rscript,
                c("--vanilla", file.path(script_dir, "qualify-worker.R"), item$path, output)
            )
            marker <- parse_marker(
                process$stdout, "DTAPARSER_ROUNDTRIP",
                c("status", "rows", "columns", "output_bytes")
            )
            status <- if (is.null(marker)) "r-worker-error" else marker$status
            rows <- if (is.null(marker)) NA_real_ else as.numeric(marker$rows)
            columns <- if (is.null(marker)) NA_real_ else as.numeric(marker$columns)
            output_bytes <- if (is.null(marker)) NA_real_ else as.numeric(marker$output_bytes)
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
        roundtrip_append_tsv(row, raw_path)
        completed <- c(completed, item$id)
        message(length(completed), "/", nrow(ordered), ": ", item$id, " ", row$status)
    }
    raw <- read.delim(raw_path, check.names = FALSE, stringsAsFactors = FALSE)
    if (anyDuplicated(raw$id)) stop("qualification contains duplicate file IDs")
    pass <- sum(raw$status == "pass")
    excluded <- sum(raw$status == "expected-exclusion")
    failures <- nrow(raw) - pass - excluded
    wide_status <- qualify_wide()
    if (!is.finite(max_files) &&
        (nrow(raw) != 1823L || pass != 1821L || excluded != 2L || failures != 0L)) {
        stop("full qualification did not achieve 1,821 passes and two bound exclusions")
    }
    manifest <- data.frame(
        schema_version = 1L, status = if (failures == 0L) "complete" else "failed",
        inventory_sha256 = inventory_hash, package_sha256 = package_hash,
        source_tarball_sha256 = source_sha256, inventoried = nrow(raw),
        passed = pass, excluded = excluded, failed = failures,
        synthetic_wide = wide_status,
        stringsAsFactors = FALSE
    )
    write.table(manifest, file.path(output_dir, "qualification.tsv"), sep = "\t",
                row.names = FALSE, quote = FALSE)
    write_private_report(raw, file.path(output_dir, "qualification-report.md"),
                         "DTA write qualification")
    if (failures != 0L || wide_status != "pass") {
        stop("qualification failures remain")
    }
    quit(status = 0L)
}

qualification_path <- file.path(output_dir, "qualification.tsv")
if (!file.exists(qualification_path)) stop("benchmark requires a completed qualification")
qualification <- read.delim(qualification_path, check.names = FALSE,
                            stringsAsFactors = FALSE)
if (nrow(qualification) != 1L || qualification$status != "complete" ||
    qualification$inventory_sha256 != inventory_hash ||
    qualification$package_sha256 != package_hash ||
    qualification$source_tarball_sha256 != source_sha256 ||
    qualification$synthetic_wide != "pass") {
    stop("benchmark build or inventory differs from successful qualification")
}
qualification_raw <- read.delim(
    file.path(output_dir, "qualification-raw.tsv"), check.names = FALSE,
    stringsAsFactors = FALSE
)
qualified_ids <- qualification_raw$id[qualification_raw$status == "pass"]
selected <- inventory[inventory$id %in% qualified_ids, ]
if (nrow(selected) != length(qualified_ids)) stop("qualified inventory mismatch")
selected <- selected[order(-selected$bytes, selected$relative_path, method = "radix"), ]

benchmark_path <- file.path(output_dir, "benchmark-raw.tsv")
completed <- if (file.exists(benchmark_path)) {
    existing <- read.delim(benchmark_path, check.names = FALSE, stringsAsFactors = FALSE)
    keys <- paste(existing$id, existing$writer, sep = "\037")
    if (anyDuplicated(keys)) stop("benchmark contains duplicate writer measurements")
    successful <- existing[existing$status == "ok", , drop = FALSE]
    if (nrow(successful) != nrow(existing)) {
        write.table(successful, benchmark_path, sep = "\t", row.names = FALSE,
                    quote = TRUE)
    }
    paste(successful$id, successful$writer, sep = "\037")
} else character()
work_root <- file.path(output_dir, "benchmark-work")
dir.create(work_root, recursive = TRUE, showWarnings = FALSE)

wide_source <- file.path(work_root, "synthetic-wide-source.dta")
wide_generation <- run_process(
    rscript,
    c("--vanilla", file.path(script_dir, "wide-generate.R"), wide_source)
)
if (wide_generation$status != 0L || !file.exists(wide_source) ||
    !identical(roundtrip_release(wide_source), 119L)) {
    stop("could not generate the qualified release-119 benchmark input")
}
on.exit(unlink(wide_source), add = TRUE)
wide_item <- data.frame(
    corpus = "synthetic-wide", id = "synthetic-wide-32768",
    relative_path = "generated/32768-variables.dta", path = wide_source,
    release = 119L,
    bytes = as.double(file.info(wide_source, extra_cols = FALSE)$size[[1L]]),
    sha256 = unname(tools::sha256sum(wide_source)), stringsAsFactors = FALSE
)
selected <- rbind(selected, wide_item)

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
        writer = "dtaparser", writer_order = order_index,
        status = if (is.null(marker)) "worker-error" else marker$status,
        elapsed_seconds = if (is.null(marker)) NA_real_ else as.numeric(marker$elapsed),
        rss_bytes = roundtrip_parse_memory(process$stderr),
        output_bytes = if (is.null(marker)) NA_real_ else as.numeric(marker$bytes),
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
        rss <- roundtrip_parse_memory(process$stderr)
    }
    data.frame(
        corpus = item$corpus, id = item$id, release = item$release,
        writer = "stata", writer_order = order_index, status = status,
        elapsed_seconds = elapsed, rss_bytes = rss, output_bytes = output_bytes,
        stringsAsFactors = FALSE
    )
}

for (index in seq_len(nrow(selected))) {
    item <- selected[index, , drop = FALSE]
    writers <- if (index %% 2L) c("dtaparser", "stata") else c("stata", "dtaparser")
    for (writer_index in seq_along(writers)) {
        writer <- writers[[writer_index]]
        key <- paste(item$id, writer, sep = "\037")
        if (key %in% completed) next
        row <- if (writer == "dtaparser") {
            measure_dtaparser(item, writer_index)
        } else measure_stata(item, writer_index)
        roundtrip_append_tsv(row, benchmark_path)
        completed <- c(completed, key)
    }
    message(index, "/", nrow(selected), ": ", item$id)
}

raw <- read.delim(benchmark_path, check.names = FALSE, stringsAsFactors = FALSE)
if (anyDuplicated(paste(raw$id, raw$writer, sep = "\037"))) {
    stop("benchmark contains duplicate writer measurements")
}
if (any(raw$status != "ok")) stop("write benchmark contains worker failures")
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
write.table(summary, file.path(output_dir, "benchmark-summary.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
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
unlink(wide_source)
