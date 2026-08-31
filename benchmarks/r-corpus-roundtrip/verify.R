args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || length(args) > 4L) {
    stop("usage: verify.R CACHE_ROOT OUTPUT_DIR full|from|smallest|id [ARGUMENT]")
}
if (!requireNamespace("processx", quietly = TRUE)) stop("processx is required")

cache_root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output_dir <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
selection <- args[[3L]]
argument <- if (length(args) == 4L) args[[4L]] else ""
script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"), local = TRUE)

library <- benchmark_library_path()
rscript <- normalizePath(Sys.which("Rscript"), winslash = "/", mustWork = TRUE)
stata <- find_stata()
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

inventory <- roundtrip_inventory(cache_root)
selected <- roundtrip_select_verification(inventory, selection, argument)
inventory_hash <- benchmark_file_sha256({
    path <- file.path(output_dir, "inventory.tsv")
    atomic_tsv(inventory[c("corpus", "id", "relative_path", "release", "bytes", "sha256")], path, quote = TRUE)
    path
})
binding <- cbind(
    data.frame(
        schema_version = 1L,
        inventory_sha256 = inventory_hash,
        package_sha256 = benchmark_directory_sha256(
            benchmark_installed_package_path(library)
        ),
        comparator_sha256 = benchmark_file_sha256(
            file.path(script_dir, "stata-compare.do")
        ),
        stringsAsFactors = FALSE
    ),
    benchmark_runtime_binding(stata, rscript_executable = rscript)
)
atomic_tsv(binding, file.path(output_dir, "verification-binding.tsv"))

run <- function(command, arguments, wd = NULL) {
    processx::run(
        command, arguments, wd = wd,
        env = c(
            DTATOOLS_BENCH_LIB = library,
            R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null"
        ),
        error_on_status = FALSE, echo = FALSE
    )
}

parse_stata <- function(path, kind) {
    if (!file.exists(path)) return(c("stata-worker-error", kind, "protocol", "", ""))
    fields <- strsplit(readLines(path, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1L]]
    if (length(fields) != 5L || fields[[2L]] != kind) {
        return(c("stata-worker-error", kind, "protocol", "", ""))
    }
    fields
}

work_root <- file.path(output_dir, "work")
dir.create(work_root, recursive = TRUE, showWarnings = FALSE)
results_path <- file.path(output_dir, "verification.tsv")
partial_results_path <- file.path(output_dir, "verification.partial.tsv")
if (file.exists(results_path)) unlink(results_path)
if (file.exists(partial_results_path)) unlink(partial_results_path)

result_row <- function(item, status, stage, output = "", category = "",
                       variable = "", observation = "") {
    data.frame(
        corpus = item$corpus, id = item$id, bytes = item$bytes,
        status = status, stage = stage, output = output,
        category = category, variable = variable, observation = observation,
        stringsAsFactors = FALSE
    )
}

verify_one <- function(index) {
    item <- selected[index, , drop = FALSE]
    exclusion <- roundtrip_exclusion_reason(item)
    if (!is.na(exclusion)) {
        return(result_row(item, "expected-exclusion", exclusion))
    }

    work_dir <- file.path(work_root, item$id)
    tryCatch({
        unlink(work_dir, recursive = TRUE, force = TRUE)
        dir.create(work_dir, recursive = TRUE)
        input <- benchmark_snapshot_file(
            item$path, file.path(work_dir, "input.dta"), item$bytes, item$sha256
        )
        direct <- file.path(work_dir, "direct.dta")
        arrow <- file.path(work_dir, "copy.arrow")
        via_arrow <- file.path(work_dir, "via-arrow.dta")
        worker <- run(
            rscript,
            c("--vanilla", file.path(script_dir, "verify-worker.R"),
              input, direct, arrow, via_arrow)
        )
        marker <- parse_fields(worker$stdout, "DTATOOLS_VERIFY")
        if (worker$status != 0L || length(marker) != 3L ||
            marker[[1L]] != "r-pass") {
            stage <- if (length(marker)) marker[[1L]] else "r-worker-error"
            writeLines(worker$stdout, file.path(work_dir, "r-worker.stdout"), useBytes = TRUE)
            writeLines(worker$stderr, file.path(work_dir, "r-worker.stderr"), useBytes = TRUE)
            return(result_row(item, "failure", stage))
        }

        for (kind in c("direct", "via-arrow")) {
            candidate <- if (kind == "direct") direct else via_arrow
            result_path <- file.path(work_dir, "stata-compare-result.tsv")
            unlink(result_path)
            comparison <- run(
                stata,
                c("-q", "-b", "do", file.path(script_dir, "stata-compare.do"),
                  input, candidate, kind, as.character(item$release)),
                work_dir
            )
            fields <- parse_stata(result_path, kind)
            if (fields[[1L]] != "pass" || comparison$status != 0L) {
                writeLines(comparison$stdout, file.path(
                    work_dir, paste0("stata-", kind, ".stdout")
                ), useBytes = TRUE)
                writeLines(comparison$stderr, file.path(
                    work_dir, paste0("stata-", kind, ".stderr")
                ), useBytes = TRUE)
                return(result_row(
                    item, "failure", "stata-compare", fields[[2L]],
                    fields[[3L]], fields[[4L]], fields[[5L]]
                ))
            }
        }

        row <- result_row(item, "pass", "complete", "both")
        unlink(work_dir, recursive = TRUE, force = TRUE)
        row
    }, error = function(condition) {
        dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
        writeLines(conditionMessage(condition), file.path(
            work_dir, "orchestrator.stderr"
        ), useBytes = TRUE)
        result_row(item, "failure", "orchestrator-error")
    })
}

limits <- roundtrip_verification_limits()
if (!selection %in% c("full", "from")) limits$jobs <- 1L
waves <- roundtrip_verification_waves(
    selected$bytes, limits$jobs, limits$memory_bytes
)
message(
    "verification schedule: ", length(waves), " size-aware waves, up to ",
    limits$jobs, " processes and ",
    format(limits$memory_bytes / 1024^3, trim = TRUE), " GiB estimated memory"
)
rows <- vector("list", nrow(selected))
completed <- 0L
for (wave_number in seq_along(waves)) {
    indices <- waves[[wave_number]]
    wave_rows <- if (length(indices) == 1L) {
        list(verify_one(indices[[1L]]))
    } else {
        parallel::mclapply(
            indices, verify_one, mc.cores = length(indices),
            mc.preschedule = FALSE, mc.set.seed = FALSE
        )
    }
    wave_rows <- Map(function(row, index) {
        if (inherits(row, "try-error") || !is.data.frame(row) ||
            nrow(row) != 1L) {
            item <- selected[index, , drop = FALSE]
            work_dir <- file.path(work_root, item$id)
            dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
            writeLines(as.character(row), file.path(
                work_dir, "orchestrator.stderr"
            ), useBytes = TRUE)
            return(result_row(item, "failure", "dataset-process-error"))
        }
        row
    }, wave_rows, indices)
    rows[indices] <- wave_rows
    checkpoint <- do.call(rbind, rows[seq_len(max(indices))])
    rownames(checkpoint) <- NULL
    atomic_tsv(checkpoint, partial_results_path)
    completed <- completed + length(indices)
    failures <- sum(vapply(wave_rows, function(row) {
        !identical(row$status[[1L]], "pass") &&
            !identical(row$status[[1L]], "expected-exclusion")
    }, logical(1L)))
    message(
        completed, "/", nrow(selected), ": wave ", wave_number, "/",
        length(waves), " complete; ", failures, " failures"
    )
}
results <- do.call(rbind, rows)
rownames(results) <- NULL
atomic_tsv(results, results_path)
unlink(partial_results_path)
failure_count <- sum(results$status == "failure")
if (failure_count > 0L) {
    stop(
        "verification completed all selected datasets with ", failure_count,
        " failures; see verification.tsv and retained work directories"
    )
}
if (selection == "full" &&
    !(nrow(results) == 1823L && sum(results$status == "pass") == 1821L &&
      sum(results$status == "expected-exclusion") == 2L)) {
    stop("full verification did not achieve 1,821 passes and two bound exclusions")
}
message("verification complete: ", sum(results$status == "pass"), " passes, ",
        sum(results$status == "expected-exclusion"), " exclusions")
