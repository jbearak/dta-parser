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

configuration <- fertility_tile_configuration(options)

execute_tile <- function(item, tile, input) {
    started <- proc.time()[["elapsed"]]
    stat_before <- fertility_file_stat(item$path)
    result <- tryCatch(
        callr::r(
            function(common_script, runtime_script, worker_script, compare_script,
                     item, tile, package_library, expected_package_path,
                     framework_id, timeout_seconds, raw_root) {
                source(common_script, local = environment())
                source(runtime_script, local = environment())
                invisible(fertility_assert_tempdir(raw_root))
                source(worker_script, local = environment())
                fertility_worker_tile(
                    item, tile, compare_script, package_library,
                    expected_package_path, framework_id, timeout_seconds
                )
            },
            args = list(
                file.path(snapshot_root, "common.R"),
                file.path(snapshot_root, "runtime.R"),
                file.path(snapshot_root, "worker.R"),
                file.path(snapshot_root, "compare.R"), item, tile, library,
                expected_package_path, framework_id, options$timeout_seconds,
                raw_root
            ),
            libpath = .libPaths(), timeout = options$timeout_seconds,
            spinner = FALSE, show = FALSE, user_profile = FALSE,
            system_profile = FALSE,
            env = c(R_ENVIRON_USER = "/dev/null", R_PROFILE_USER = "/dev/null",
                    TMPDIR = Sys.getenv("TMPDIR"),
                    R_MAX_VSIZE = paste0(configuration$memory_mib, "M"))
        ),
        error = function(error) list(
            schema_version = fertility_schema_version, framework_id = framework_id,
            id = item$id, tile_id = tile$tile_id, tile_type = tile$type,
            batch = tile$batch, skip = tile$skip, n_max = tile$n_max,
            classification = if (inherits(error, "callr_timeout_error"))
                "timeout" else if (fertility_memory_error(error))
                "memory-limit" else "crash",
            secondary = character(), mismatches = data.frame(), rows = NA_integer_,
            reader_rows = setNames(rep(NA_integer_, 3L),
                                   c("direct", "rust", "haven")),
            columns = NA_integer_, column_names = character(), storage = character(),
            structural_rows = NA_real_, column_bytes = numeric(), strl = logical(),
            projection_expected_count = if (tile$type %in% c("value", "terminal"))
                length(tile$column_names) else NA_integer_,
            projection_expected_hash = if (tile$type %in% c("value", "terminal"))
                fertility_projection_hash(tile$column_names, framework_id) else NA_character_,
            projection_counts = setNames(rep(NA_integer_, 3L),
                                         c("direct", "rust", "haven")),
            projection_hashes = setNames(rep(NA_character_, 3L),
                                         c("direct", "rust", "haven")),
            projection_ok = setNames(rep(FALSE, 3L),
                                     c("direct", "rust", "haven")),
            elapsed_seconds = unname(proc.time()[["elapsed"]] - started)
        )
    )
    stat_after <- fertility_file_stat(item$path)
    if (is.null(stat_before) || is.null(stat_after) ||
        !identical(stat_before, stat_after)) result$classification <- "input-changed"
    result
}

planning_failure_tile <- function(item, batch, detail) list(
    schema_version = fertility_schema_version, framework_id = framework_id,
    id = item$id, tile_id = paste0("planning-", batch), tile_type = "planning",
    batch = as.integer(batch), skip = 0, n_max = 0L,
    classification = "unresolved", secondary = detail,
    mismatches = data.frame(category = "unresolved", detail = detail,
                            component = NA_integer_, pair = NA_character_,
                            stringsAsFactors = FALSE),
    rows = NA_integer_, reader_rows = setNames(rep(NA_integer_, 3L),
                                                c("direct", "rust", "haven")),
    columns = NA_integer_, column_names = character(), storage = character(),
    structural_rows = NA_real_, column_bytes = numeric(), strl = logical(),
    projection_expected_count = NA_integer_, projection_expected_hash = NA_character_,
    projection_counts = setNames(rep(NA_integer_, 3L),
                                 c("direct", "rust", "haven")),
    projection_hashes = setNames(rep(NA_character_, 3L),
                                 c("direct", "rust", "haven")),
    projection_ok = setNames(rep(FALSE, 3L), c("direct", "rust", "haven")),
    elapsed_seconds = 0
)

simple_result <- function(item, input, classification) list(
    schema_version = fertility_schema_version, framework_id = framework_id,
    config_id = configuration$config_id, input_id = input$input_id,
    id = item$id, program = item$program, level = item$level,
    release = as.integer(item$release), expected_sha512 = item$expected_sha512,
    timeout_seconds = options$timeout_seconds, classification = classification,
    secondary_categories = "", mismatch_count = 0L, mismatch_categories = "",
    mismatch_signatures = "", rows = NA_real_, columns = NA_integer_,
    tiles_expected = 0L, tiles_completed = 0L,
    complete = identical(classification, "expected-unsupported-111"),
    actual_sha512 = input$actual_sha512, elapsed_seconds = NA_real_
)

checkpoints <- vector("list", nrow(selected))
for (index in seq_len(nrow(selected))) {
    item <- as.list(selected[index, , drop = FALSE])
    input <- fertility_capture_input(item)
    file_root <- file.path(checkpoint_root, configuration$config_id, item$id)
    tile_root <- file.path(file_root, "tiles")
    result_path <- file.path(file_root, "result.rds")
    dir.create(tile_root, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    existing <- if (file.exists(result_path)) tryCatch(
        readRDS(result_path), error = function(error) NULL
    ) else NULL
    resumed <- !options$retry &&
        fertility_file_result_valid(
            existing, item, framework_id, configuration, input
        ) && existing$classification %in%
            c("expected-unsupported-111", "inventory-hash-error")
    if (resumed) {
        result <- existing
    } else if (identical(input$hash_status, "error")) {
        result <- simple_result(item, input, "inventory-hash-error")
    } else if (nzchar(item$expected_sha512) &&
               !identical(input$actual_sha512, tolower(item$expected_sha512))) {
        result <- simple_result(item, input, "inventory-hash-error")
    } else if (!(item$release %in% fertility_supported_releases)) {
        result <- simple_result(item, input, "expected-unsupported-111")
    } else {
        metadata_tile <- fertility_metadata_tile()
        metadata <- fertility_process_tile(
            item, metadata_tile, file.path(tile_root, "metadata.rds"), framework_id,
            configuration, input, options$retry, execute_tile
        )
        tiles <- list(metadata$result)
        column_names <- metadata$result$column_names
        column_bytes <- metadata$result$column_bytes
        batches <- fertility_structural_batches(
            column_names, configuration$column_batch, column_bytes,
            metadata$result$columns
        )
        total_rows <- metadata$result$structural_rows
        structurally_valid <- is.finite(total_rows) && total_rows >= 0 &&
            identical(as.integer(metadata$result$columns),
                      as.integer(length(column_names))) &&
            length(column_bytes) == length(column_names)
        if (length(batches) && isTRUE(structurally_valid)) {
            for (batch in seq_along(batches)) {
                bytes <- fertility_batch_bytes(
                    batches[[batch]], column_names, column_bytes
                )
                rows_per_tile <- fertility_adaptive_rows(bytes, configuration)
                reserved_probes <- if (batch == 1L)
                    configuration$beyond_end_windows else 0L
                plan <- fertility_plan_offsets(
                    total_rows, rows_per_tile,
                    configuration$max_tiles_per_batch - reserved_probes
                )
                if (plan$ceiling) {
                    tiles[[length(tiles) + 1L]] <- planning_failure_tile(
                        item, batch, "tile-ceiling-reached"
                    )
                    next
                }
                for (offset in plan$offsets) {
                    tile <- fertility_value_tile(
                        batch, offset, rows_per_tile, batches[[batch]]
                    )
                    processed <- fertility_process_tile(
                        item, tile, file.path(tile_root, paste0(tile$tile_id, ".rds")),
                        framework_id, configuration, input, options$retry, execute_tile
                    )
                    tiles[[length(tiles) + 1L]] <- processed$result
                }
                if (batch == 1L) for (probe in seq_len(configuration$beyond_end_windows)) {
                    tile <- fertility_value_tile(
                        batch, total_rows + (probe - 1L),
                        1L, batches[[batch]], type = "terminal", probe = probe
                    )
                    processed <- fertility_process_tile(
                        item, tile, file.path(tile_root, paste0(tile$tile_id, ".rds")),
                        framework_id, configuration, input, options$retry, execute_tile
                    )
                    tiles[[length(tiles) + 1L]] <- processed$result
                }
            }
        } else if (length(batches)) {
            tiles[[length(tiles) + 1L]] <- planning_failure_tile(
                item, 0L, "structural-metadata-unavailable"
            )
        }
        result <- fertility_tiled_result(
            item, framework_id, configuration, input, tiles, batches, total_rows
        )
        final_input <- fertility_capture_input(item)
        if (!identical(final_input$input_id, input$input_id)) {
            result <- simple_result(item, final_input, "inventory-hash-error")
            result$complete <- FALSE
        }
    }
    if (!resumed) fertility_atomic_save_rds(result, result_path)
    checkpoints[[index]] <- result
    message(item$id, if (resumed) ": resumed " else ": ", result$classification)
}
# Detect source, dependency, or installed-package changes before publication.
final_provenance <- fertility_verify_provenance(
    checkout_root, library, provenance_path
)
if (!identical(final_provenance$provenance_id[[1L]],
               provenance$provenance_id[[1L]])) {
    stop("corpus build provenance changed during the run")
}
for (index in seq_len(nrow(selected))) {
    current_input <- fertility_capture_input(as.list(selected[index, , drop = FALSE]))
    if (!identical(current_input$input_id, checkpoints[[index]]$input_id)) {
        stop("corpus input changed before report publication")
    }
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
    config_id = configuration$config_id,
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
    config_id = configuration$config_id,
    build_provenance_id = provenance$provenance_id[[1L]],
    selected_files = nrow(selected),
    shard_index = options$shard_index,
    shard_count = options$shard_count,
    timeout_seconds = options$timeout_seconds,
    chunk_rows = options$chunk_rows,
    column_batch = options$column_batch,
    memory_mib = options$memory_mib,
    cell_budget = options$cell_budget,
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
