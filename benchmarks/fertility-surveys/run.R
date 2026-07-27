script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "provenance.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
options <- fertility_parse_arguments(commandArgs(trailingOnly = TRUE))
checkout_root <- fertility_checkout_root(script_path)
raw_root <- normalizePath(file.path(checkout_root, "target", "fertility-surveys", "raw"),
                          winslash = "/", mustWork = FALSE)
dir.create(raw_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
Sys.chmod(raw_root, mode = "0700")
if (!identical(normalizePath(raw_root, winslash = "/", mustWork = TRUE),
               file.path(checkout_root, "target", "fertility-surveys", "raw"))) {
    stop("outputs must remain under target/fertility-surveys/raw")
}
invisible(fertility_assert_tempdir(raw_root))

inventory <- fertility_build_inventory()
selected <- fertility_filter_inventory(inventory, options)
fertility_atomic_write_table(fertility_public_inventory(inventory),
                             file.path(raw_root, "inventory.tsv"))
release_summary <- as.data.frame(table(release = inventory$release),
                                 stringsAsFactors = FALSE)
names(release_summary)[[2L]] <- "files"
fertility_atomic_write_table(release_summary,
                             file.path(raw_root, "inventory-summary.tsv"))
message("inventory: 1,004 files; selected: ", nrow(selected))
if (options$inventory_only) quit(save = "no", status = 0L)
if (!nrow(selected)) stop("filters selected no corpus files")

library <- file.path(raw_root, "library")
provenance_path <- file.path(raw_root, "build-provenance.tsv")
if (!file.exists(provenance_path)) stop("run benchmark.sh to create package provenance")
provenance <- fertility_verify_provenance(checkout_root, library, provenance_path)
expected_package_path <- fertility_package_path(library)
.libPaths(c(library, .libPaths()))
for (package in c("dtaparser", "haven", "openssl", "callr")) {
    if (!requireNamespace(package, quietly = TRUE)) stop(package, " is required")
}
if (!identical(normalizePath(getNamespaceInfo(asNamespace("dtaparser"), "path"),
                             winslash = "/"), expected_package_path)) {
    stop("dtaparser was not loaded from the checkout-local corpus library")
}
datasigs_sha256 <- tolower(as.character(openssl::sha256(file(
    fertility_required_paths()$datasigs
))))
framework_id <- fertility_stable_id(list(
    schema_version = fertility_schema_version,
    provenance_id = provenance$provenance_id[[1L]],
    datasigs_sha256 = datasigs_sha256,
    comparator_tolerance = "1e-7"
))
snapshot_root <- file.path(raw_root, "framework", framework_id)
dir.create(snapshot_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
Sys.chmod(c(file.path(raw_root, "framework"), snapshot_root), mode = "0700")
for (name in c("common.R", "worker.R", "compare.R", "runtime.R")) {
    source_path <- file.path(script_dir, name)
    snapshot_path <- file.path(snapshot_root, name)
    if (!file.exists(snapshot_path)) {
        temporary <- tempfile(paste0(name, "."), tmpdir = snapshot_root)
        if (!file.copy(source_path, temporary, overwrite = TRUE)) {
            stop("could not snapshot corpus framework")
        }
        Sys.chmod(temporary, mode = "0600")
        if (!file.rename(temporary, snapshot_path)) {
            stop("could not publish corpus framework snapshot")
        }
    }
    if (!identical(unname(tools::md5sum(source_path)),
                   unname(tools::md5sum(snapshot_path)))) {
        stop("corpus framework snapshot does not match its provenance")
    }
}
checkpoint_root <- file.path(raw_root, "checkpoints", framework_id)
dir.create(checkpoint_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
Sys.chmod(c(file.path(raw_root, "checkpoints"), checkpoint_root), mode = "0700")

execute_item <- function(item, input) {
    started <- proc.time()[["elapsed"]]
    tryCatch(
        callr::r(
            function(common_script, runtime_script, worker_script, compare_script,
                     item, package_library, expected_package_path, framework_id,
                     timeout_seconds, parent_sha512, raw_root) {
                source(common_script, local = environment())
                source(runtime_script, local = environment())
                invisible(fertility_assert_tempdir(raw_root))
                source(worker_script, local = environment())
                fertility_worker(item, compare_script, package_library,
                                 expected_package_path, framework_id,
                                 timeout_seconds, parent_sha512)
            },
            args = list(
                file.path(snapshot_root, "common.R"),
                file.path(snapshot_root, "runtime.R"),
                file.path(snapshot_root, "worker.R"),
                file.path(snapshot_root, "compare.R"), item, library,
                expected_package_path, framework_id, options$timeout_seconds,
                input$actual_sha512, raw_root
            ),
            libpath = .libPaths(), timeout = options$timeout_seconds,
            spinner = FALSE, show = FALSE, user_profile = FALSE,
            system_profile = FALSE,
            env = c(R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null",
                    TMPDIR = Sys.getenv("TMPDIR"))
        ),
        error = function(error) {
            classification <- if (inherits(error, "callr_timeout_error"))
                "timeout" else "subprocess-error"
            fertility_base_result(
                item, framework_id, options$timeout_seconds, input,
                classification,
                unname(proc.time()[["elapsed"]] - started)
            )
        }
    )
}

for (index in seq_len(nrow(selected))) {
    item <- as.list(selected[index, , drop = FALSE])
    checkpoint_path <- file.path(checkpoint_root, paste0(item$id, ".rds"))
    processed <- fertility_process_item(
        item, checkpoint_path, framework_id, options$timeout_seconds,
        options$retry, execute_item
    )
    message(item$id, if (processed$resumed) ": resumed " else ": ",
            processed$result$classification)
}

checkpoints <- lapply(selected$id, function(id) {
    checkpoint <- readRDS(file.path(checkpoint_root, paste0(id, ".rds")))
    item <- as.list(selected[selected$id == id, , drop = FALSE])
    if (!fertility_checkpoint_valid(
        checkpoint, item, framework_id, fertility_capture_input(item),
        options$timeout_seconds
    )) {
        stop("checkpoint validation failed")
    }
    checkpoint
})
# Detect source, dependency, or installed-package changes before publication.
final_provenance <- fertility_verify_provenance(
    checkout_root, library, provenance_path
)
if (!identical(final_provenance$provenance_id[[1L]],
               provenance$provenance_id[[1L]])) {
    stop("corpus build provenance changed during the run")
}
results <- fertility_result_frame(checkpoints)
results$build_provenance_id <- provenance$provenance_id[[1L]]
summary <- as.data.frame(table(classification = results$classification),
                         stringsAsFactors = FALSE)
names(summary)[[2L]] <- "files"
selection_id <- fertility_stable_id(list(
    framework_id = framework_id,
    programs = paste(options$programs, collapse = ","),
    releases = paste(options$releases, collapse = ","),
    ids = paste(options$ids, collapse = ","),
    shard_index = options$shard_index,
    shard_count = options$shard_count,
    max_files = as.character(options$max_files),
    timeout_seconds = options$timeout_seconds,
    selected_ids = paste(selected$id, collapse = ",")
))
report_parent <- file.path(raw_root, "reports", selection_id)
dir.create(report_parent, recursive = TRUE, showWarnings = FALSE, mode = "0700")
Sys.chmod(c(file.path(raw_root, "reports"), report_parent), mode = "0700")
report_stage <- tempfile(".report.", tmpdir = report_parent)
dir.create(report_stage, mode = "0700")
on.exit(unlink(report_stage, recursive = TRUE), add = TRUE)
results <- fertility_publish_results(
    checkpoints, provenance$provenance_id[[1L]],
    file.path(report_stage, "results.tsv")
)
fertility_atomic_write_table(summary, file.path(report_stage, "summary.tsv"))
run_provenance <- data.frame(
    schema_version = fertility_schema_version,
    selection_id = selection_id,
    framework_id = framework_id,
    build_provenance_id = provenance$provenance_id[[1L]],
    selected_files = nrow(selected),
    shard_index = options$shard_index,
    shard_count = options$shard_count,
    timeout_seconds = options$timeout_seconds,
    retry = options$retry,
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors = FALSE, check.names = FALSE
)
fertility_atomic_write_table(run_provenance,
                             file.path(report_stage, "run-provenance.tsv"))
run_name <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
report_dir <- file.path(report_parent, run_name)
if (!file.rename(report_stage, report_dir)) stop("could not publish report bundle")
current <- file.path(report_parent, "CURRENT")
temporary_current <- tempfile("CURRENT.", tmpdir = report_parent)
writeLines(run_name, temporary_current, useBytes = TRUE)
Sys.chmod(temporary_current, mode = "0600")
if (!file.rename(temporary_current, current)) stop("could not publish report pointer")
message("completed ", nrow(results), " selected files; report ", selection_id)
