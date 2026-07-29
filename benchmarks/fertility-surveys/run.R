script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "accepted.R"))
source(file.path(script_dir, "provenance.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
options <- fertility_parse_arguments(commandArgs(trailingOnly = TRUE))
checkout_root <- fertility_checkout_root(script_path)
raw_root <- fertility_assert_checkout_raw_root(
    file.path(checkout_root, "target", "fertility-surveys", "raw"),
    checkout_root, create = TRUE
)
Sys.chmod(raw_root, mode = "0700")
invisible(fertility_assert_tempdir(raw_root))

inventory <- fertility_build_selected_inventory(options, raw_root)
acceptance <- if (nzchar(options$accepted_current_hashes)) {
    fertility_load_acceptance(raw_root, options$accepted_current_hashes, inventory)
} else NULL
selected <- fertility_filter_inventory(inventory, options)
family_selection <- fertility_family_selection(inventory, options)
fertility_validate_accepted_selection(options, family_selection)
fertility_validate_encoding_overrides(options$encoding_overrides, family_selection)
invisible(fertility_validate_acceptance_current(acceptance, inventory))
fertility_atomic_write_table(fertility_public_inventory(inventory),
                             file.path(raw_root, "inventory.tsv"))
release_summary <- as.data.frame(table(release = inventory$release),
                                 stringsAsFactors = FALSE)
names(release_summary)[[2L]] <- "files"
fertility_atomic_write_table(release_summary,
                             file.path(raw_root, "inventory-summary.tsv"))
message("inventory: ", nrow(inventory), " files; selected: ", nrow(selected))
if (options$inventory_only) quit(save = "no", status = 0L)

library_value <- Sys.getenv("DTAPARSER_FERTILITY_LIBRARY")
provenance_value <- Sys.getenv("DTAPARSER_FERTILITY_PROVENANCE")
prepared_framework_id <- Sys.getenv("DTAPARSER_FERTILITY_FRAMEWORK_ID")
owner_state <- Sys.getenv("DTAPARSER_FERTILITY_OWNER_STATE")
if (!nzchar(library_value) || !nzchar(provenance_value) ||
    !nzchar(prepared_framework_id) || !nzchar(owner_state)) {
    stop("run benchmark.sh to create immutable corpus setup")
}
selected_build_id <- basename(dirname(path.expand(provenance_value)))
build_bundle <- fertility_resolve_build_bundle(
    raw_root, selected_build_id, require_current = TRUE
)
if (!identical(path.expand(library_value), build_bundle$library) ||
    !identical(path.expand(provenance_value), build_bundle$provenance)) {
    stop("immutable corpus build paths escaped the selected build generation")
}
library <- build_bundle$library
provenance_path <- build_bundle$provenance
provenance <- fertility_verify_provenance(checkout_root, library, provenance_path)
if (!identical(provenance$provenance_id[[1L]], selected_build_id)) {
    stop("selected build provenance identity is invalid")
}
expected_package_path <- build_bundle$package
package_attestation <- fertility_attest_regular_tree(
    expected_package_path, "installed dtaparser package"
)
.libPaths(c(library, .libPaths()))
fertility_revalidate_regular_tree(
    package_attestation, "installed dtaparser package"
)
for (package in c("dtaparser", "haven", "openssl", "callr")) {
    if (!requireNamespace(package, quietly = TRUE)) stop(package, " is required")
}
if (!identical(normalizePath(getNamespaceInfo(asNamespace("dtaparser"), "path"),
                             winslash = "/"), expected_package_path)) {
    stop("dtaparser was not loaded from the immutable corpus library")
}
framework_id <- fertility_framework_id(
    provenance$provenance_id[[1L]], fertility_required_paths(options, raw_root)$datasigs, acceptance
)
if (!identical(framework_id, prepared_framework_id)) {
    stop("prepared corpus framework identity changed before execution")
}
snapshot_root <- fertility_verify_framework_snapshot(
    script_dir, raw_root, framework_id, inventory, acceptance
)
configuration <- fertility_tile_configuration(options, acceptance)
inventory_id <- fertility_inventory_id(inventory)
family_manifest <- fertility_family_manifest(inventory, options)
family_manifest_id <- fertility_manifest_id(family_manifest)
family_id <- fertility_selection_family_id(
    inventory, options, framework_id, configuration$config_id,
    provenance$provenance_id[[1L]]
)
selection_id <- fertility_stable_id(list(
    family_id = family_id,
    shard_index = options$shard_index,
    selected_ids = paste(selected$id, collapse = ",")
))
owner <- fertility_read_owner(owner_state)
if (!isTRUE(fertility_owner_alive(owner))) stop("orchestrator owner is not alive")
invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
selection_lock_root <- fertility_assert_output_parent(
    raw_root, ".locks", "selections", create = TRUE
)
case_lock_root <- fertility_assert_output_parent(
    raw_root, ".locks", "cases", create = TRUE
)
selection_lock <- file.path(
    selection_lock_root, fertility_lock_component(selection_id, "selection ID")
)
case_locks <- file.path(
    case_lock_root, vapply(selected$id, fertility_lock_component, character(1),
                           label = "case ID")
)
run_locks <- fertility_acquire_lock_set(c(selection_lock, case_locks), owner)
on.exit({
    if (!fertility_release_lock_set(run_locks)) {
        warning("could not release every fertility corpus run lock")
    }
}, add = TRUE)

invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
checkpoint_root <- fertility_assert_output_parent(
    raw_root, "checkpoints", framework_id, create = TRUE
)
Sys.chmod(c(file.path(raw_root, "checkpoints"), checkpoint_root), mode = "0700")

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
                result <- fertility_worker_tile(
                    item, tile, compare_script, package_library,
                    expected_package_path, framework_id, timeout_seconds
                )
                comparator_helpers <- c(
                    "fertility_bind_mismatches", "fertility_compare_available_pairs"
                )
                if (any(vapply(comparator_helpers, exists, logical(1),
                               envir = globalenv(), inherits = FALSE))) {
                    stop("comparator helpers escaped the isolated callback")
                }
                result
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
    if (identical(tile$type, "sizing")) {
        payload <- if (!is.null(result$payload_bytes_per_row))
            result$payload_bytes_per_row else NA_real_
        result$chosen_rows <- fertility_strl_rows(
            payload, length(tile$column_names), configuration
        )
        result$sample_offsets_hash <- fertility_stable_id(list(
            offsets = paste(format(tile$sample_offsets, scientific = FALSE),
                            collapse = ",")
        ))
    }
    stat_after <- fertility_file_stat(item$path)
    if (is.null(stat_before) || is.null(stat_after) ||
        !identical(stat_before, stat_after)) result$classification <- "input-changed"
    result
}

# Mandatory post-build regression using the exact immutable callback path above.
# This fixture is synthetic and remains inside the private target-local TMPDIR.
worker_smoke_path <- tempfile("worker-smoke-", tmpdir = Sys.getenv("TMPDIR"),
                              fileext = ".dta")
haven::write_dta(data.frame(
    synthetic_number = seq_len(100L),
    synthetic_long = c(rep("x", 99L), strrep("y", 3000L))
), worker_smoke_path, version = 14)
on.exit(unlink(worker_smoke_path), add = TRUE)
worker_smoke_item <- list(
    id = "FTEST", program = "dhs", level = "women", release = 118L,
    path = normalizePath(worker_smoke_path, winslash = "/", mustWork = TRUE),
    expected_sha512 = ""
)
worker_smoke <- execute_tile(
    worker_smoke_item, fertility_metadata_tile(),
    fertility_capture_input(worker_smoke_item)
)
if (!is.list(worker_smoke) || worker_smoke$classification %in%
        c("timeout", "memory-limit", "crash", "dtaparser-only-error",
          "haven-only-error", "shared-reader-error", "unresolved") ||
    !identical(as.integer(worker_smoke$rows), 100L) ||
    !identical(as.integer(worker_smoke$columns), 2L) ||
    !identical(as.double(worker_smoke$structural_rows), 100)) {
    stop("post-build isolated worker regression failed")
}
worker_sizing_smoke <- execute_tile(
    worker_smoke_item,
    fertility_sizing_tile(1L, "synthetic_long", 100, configuration$strl_sample_count),
    fertility_capture_input(worker_smoke_item)
)
if (!is.list(worker_sizing_smoke) ||
    !identical(worker_sizing_smoke$classification, "pass") ||
    !identical(as.integer(worker_sizing_smoke$samples_completed),
               as.integer(configuration$strl_sample_count)) ||
    !is.finite(worker_sizing_smoke$payload_bytes_per_row) ||
    worker_sizing_smoke$payload_bytes_per_row < 9000 ||
    !is.finite(worker_sizing_smoke$chosen_rows) || worker_sizing_smoke$chosen_rows <= 1L) {
    stop("post-build isolated strL sizing regression failed")
}
unlink(worker_smoke_path)
message("post-build isolated worker regressions passed")

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

simple_result <- function(item, input, classification, reason = "") c(list(
    schema_version = fertility_schema_version, framework_id = framework_id,
    config_id = configuration$config_id, input_id = input$input_id,
    id = item$id, program = item$program, level = item$level,
    release = as.integer(item$release), expected_sha512 = item$expected_sha512,
    timeout_seconds = options$timeout_seconds, classification = classification,
    secondary_categories = reason, mismatch_count = 0L, mismatch_categories = "",
    mismatch_signatures = "", rows = NA_real_, columns = NA_integer_,
    tiles_expected = 0L, tiles_completed = 0L,
    complete = identical(classification, "expected-unsupported-111"),
    actual_sha512 = input$actual_sha512, elapsed_seconds = NA_real_
), fertility_result_acceptance_fields(input))

checkpoints <- vector("list", nrow(selected))
for (index in seq_len(nrow(selected))) {
    item <- as.list(selected[index, , drop = FALSE])
    if (item$id %in% names(options$encoding_overrides)) {
        item$encoding_override <- unname(options$encoding_overrides[[item$id]])
    }
    input <- fertility_capture_input(item, acceptance)
    preflight <- fertility_inventory_preflight(item, input)
    file_root <- fertility_assert_output_parent(
        checkpoint_root, configuration$config_id, item$id, create = TRUE
    )
    tile_root <- file.path(file_root, "tiles")
    invisible(fertility_assert_direct_child(
        tile_root, file_root, "tile checkpoint directory", must_work = FALSE
    ))
    if (!dir.exists(tile_root) &&
        !dir.create(tile_root, showWarnings = FALSE, mode = "0700")) {
        stop("could not create tile checkpoint directory")
    }
    invisible(fertility_assert_direct_child(
        tile_root, file_root, "tile checkpoint directory"
    ))
    result_path <- fertility_assert_checkpoint_file(
        file.path(file_root, "result.rds"), "file result checkpoint"
    )
    existing <- if (file.exists(result_path)) tryCatch(
        readRDS(fertility_assert_checkpoint_file(
            result_path, "file result checkpoint", must_exist = TRUE
        )), error = function(error) NULL
    ) else NULL
    resumed <- !options$retry &&
        fertility_file_result_valid(
            existing, item, framework_id, configuration, input
        ) && existing$classification %in%
            c("expected-unsupported-111", "inventory-hash-error")
    if (resumed) {
        result <- existing
    } else if (!is.null(preflight)) {
        result <- simple_result(
            item, input, preflight$classification, preflight$reason
        )
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
                is_strl_batch <- any(!is.finite(bytes))
                if (is_strl_batch) {
                    sizing_tile <- fertility_sizing_tile(
                        batch, batches[[batch]], total_rows,
                        configuration$strl_sample_count
                    )
                    sizing <- fertility_process_tile(
                        item, sizing_tile,
                        file.path(tile_root, paste0(sizing_tile$tile_id, ".rds")),
                        framework_id, configuration, input, options$retry, execute_tile
                    )
                    rows_per_tile <- as.integer(sizing$result$chosen_rows)
                }
                reserved_probes <- if (batch == 1L)
                    configuration$beyond_end_windows else 0L
                available_tiles <- configuration$max_tiles_per_batch -
                    reserved_probes - if (is_strl_batch) 1L else 0L
                if (available_tiles < 1L) {
                    tiles[[length(tiles) + 1L]] <- planning_failure_tile(
                        item, batch, "tile-ceiling-reached"
                    )
                    next
                }
                plan <- fertility_plan_offsets(
                    total_rows, rows_per_tile, available_tiles
                )
                if (plan$ceiling) {
                    tiles[[length(tiles) + 1L]] <- planning_failure_tile(
                        item, batch, "tile-ceiling-reached"
                    )
                    next
                }
                split_budget <- new.env(parent = emptyenv())
                split_budget$remaining <- as.integer(
                    available_tiles - length(plan$offsets)
                )
                process_value_tile <- function(tile) {
                    fertility_process_tile(
                        item, tile, file.path(tile_root, paste0(tile$tile_id, ".rds")),
                        framework_id, configuration, input, options$retry, execute_tile
                    )$result
                }
                for (offset in plan$offsets) {
                    requested <- if (total_rows == 0) 1L else as.integer(min(
                        rows_per_tile, total_rows - offset
                    ))
                    leaves <- fertility_process_adaptive_range(
                        batch, offset, requested, batches[[batch]],
                        process_value_tile, split_budget
                    )
                    tiles <- c(tiles, leaves)
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
        final_input <- fertility_capture_input(item, acceptance)
        if (!identical(final_input$input_id, input$input_id)) {
            result <- simple_result(
                item, final_input, "inventory-hash-error",
                fertility_changed_input_reason(final_input)
            )
            result$complete <- FALSE
        }
    }
    if (!resumed) {
        fertility_assert_checkpoint_file(result_path, "file result checkpoint")
        fertility_atomic_save_rds(result, result_path)
    }
    checkpoints[[index]] <- result
    message(item$id, if (resumed) ": resumed " else ": ", result$classification)
}
# Close over every source of publication authority and rerun this immediately
# before both immutable bundle publication and CURRENT replacement.
revalidate_run_evidence <- function(publication_provenance = NULL) {
    live_inventory <- fertility_build_selected_inventory(options, raw_root)
    fertility_validate_canonical_inventory(
        fertility_inventory_manifest(live_inventory),
        exact = !fertility_output_requested(options)
    )
    if (!identical(fertility_inventory_id(live_inventory), inventory_id)) {
        stop("canonical inventory changed before report publication")
    }
    current_build <- fertility_resolve_build_bundle(
        raw_root, provenance$provenance_id[[1L]], require_current = TRUE
    )
    final_provenance <- fertility_verify_provenance(
        checkout_root, current_build$library, current_build$provenance
    )
    if (!identical(final_provenance$provenance_id[[1L]],
                   provenance$provenance_id[[1L]]) ||
        !identical(current_build$library, library) ||
        !identical(current_build$package, expected_package_path)) {
        stop("corpus build provenance changed during the run")
    }
    reloaded_acceptance <- if (is.null(acceptance)) NULL else
        fertility_load_acceptance(
            raw_root, acceptance$commitment_id, live_inventory
        )
    if (!identical(acceptance, reloaded_acceptance)) {
        stop("accepted-current-hash artifact changed before publication")
    }
    invisible(fertility_validate_acceptance_current(
        reloaded_acceptance, live_inventory
    ))
    invisible(fertility_verify_framework_snapshot(
        script_dir, raw_root, framework_id, live_inventory, reloaded_acceptance
    ))
    if (!identical(
        fertility_framework_id(
            final_provenance$provenance_id[[1L]],
            fertility_required_paths(options, raw_root)$datasigs, reloaded_acceptance
        ), framework_id
    )) stop("corpus framework or inventory provenance changed during the run")
    live_selected <- fertility_filter_inventory(live_inventory, options)
    if (!identical(as.character(live_selected$id), as.character(selected$id))) {
        stop("selected inventory changed before report publication")
    }
    for (index in seq_len(nrow(live_selected))) {
        current_input <- fertility_capture_input(
            as.list(live_selected[index, , drop = FALSE]), reloaded_acceptance
        )
        if (!identical(current_input$input_id, checkpoints[[index]]$input_id)) {
            stop("corpus input changed before report publication")
        }
    }
    if (!is.null(publication_provenance) && !is.null(reloaded_acceptance)) {
        fertility_revalidate_accepted_publication(
            raw_root, publication_provenance, live_inventory
        )
    }
    invisible(list(
        inventory = live_inventory, acceptance = reloaded_acceptance,
        build = final_provenance
    ))
}
invisible(revalidate_run_evidence())
results <- fertility_result_frame(checkpoints)
results$build_provenance_id <- rep(provenance$provenance_id[[1L]], nrow(results))
summary <- fertility_classification_summary(results)
invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
report_parent <- fertility_assert_output_parent(
    raw_root, "reports", selection_id, create = TRUE
)
Sys.chmod(c(file.path(raw_root, "reports"), report_parent), mode = "0700")
report_stage <- tempfile(".report.", tmpdir = report_parent)
dir.create(report_stage, mode = "0700")
invisible(fertility_assert_direct_child(
    report_stage, report_parent, "report staging directory"
))
on.exit(unlink(report_stage, recursive = TRUE), add = TRUE)
results <- fertility_publish_results(
    checkpoints, provenance$provenance_id[[1L]],
    file.path(report_stage, "results.tsv")
)
fertility_atomic_write_table(summary, file.path(report_stage, "summary.tsv"))
fertility_atomic_write_table(
    family_manifest, file.path(report_stage, "family-manifest.tsv")
)
filter_spec <- fertility_filter_spec(options)
evidence_origin <- "fresh-execution"
input_attestation_id <- fertility_input_attestation_id(checkpoints)
acceptance_authority <- if (is.null(acceptance)) "" else acceptance$authority
acceptance_commitment_id <- if (is.null(acceptance)) "" else acceptance$commitment_id
evidence_selection_id <- fertility_evidence_selection_id(
    selection_id, input_attestation_id, evidence_origin,
    fertility_schema_version, fertility_report_schema_id(),
    acceptance_authority, acceptance_commitment_id
)
run_provenance <- data.frame(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    evidence_origin = evidence_origin,
    source_corpus_schema_version = fertility_schema_version,
    replayed_at_utc = "",
    acceptance_authority = acceptance_authority,
    acceptance_commitment_id = acceptance_commitment_id,
    acceptance_artifact_sha256 = if (is.null(acceptance)) "" else
        acceptance$artifact_sha256,
    selection_id = selection_id,
    evidence_selection_id = evidence_selection_id,
    input_attestation_id = input_attestation_id,
    family_id = family_id,
    family_manifest_id = family_manifest_id,
    framework_id = framework_id,
    config_id = configuration$config_id,
    build_provenance_id = provenance$provenance_id[[1L]],
    inventory_id = inventory_id,
    report_schema_id = fertility_report_schema_id(),
    selected_files = nrow(selected),
    expected_family_files = nrow(family_selection),
    full_default_family = fertility_full_default_family(options),
    program_filter = filter_spec$program_filter,
    release_filter = filter_spec$release_filter,
    id_filter = filter_spec$id_filter,
    encoding_overrides = configuration$encoding_overrides,
    max_files = filter_spec$max_files,
    shard_index = options$shard_index,
    shard_count = options$shard_count,
    timeout_seconds = options$timeout_seconds,
    chunk_rows = options$chunk_rows,
    column_batch = options$column_batch,
    memory_mib = options$memory_mib,
    cell_budget = options$cell_budget,
    max_tiles_per_batch = options$max_tiles_per_batch,
    beyond_end_windows = options$beyond_end_windows,
    retry = options$retry,
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors = FALSE, check.names = FALSE
)
fertility_atomic_write_table(run_provenance,
                             file.path(report_stage, "run-provenance.tsv"))
report_bundle_files <- c(
    results = "results.tsv", summary = "summary.tsv",
    family_manifest = "family-manifest.tsv",
    provenance = "run-provenance.tsv"
)
report_bundle_expected <- list(
    results = results, summary = summary,
    family_manifest = family_manifest, provenance = run_provenance
)
validate_report_bundle <- function(path) fertility_validate_exact_table_bundle(
    path, report_bundle_files, report_bundle_expected, "report bundle"
)
run_name <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
report_dir <- file.path(report_parent, run_name)
fertility_publication_test_hook(
    "run-before-bundle-revalidation",
    list(parent = report_parent, stage = report_stage, destination = report_dir)
)
invisible(revalidate_run_evidence(run_provenance))
invisible(validate_report_bundle(report_stage))
invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
report_parent <- fertility_assert_output_parent(raw_root, "reports", selection_id)
invisible(fertility_assert_existing_directory(
    report_stage, report_parent, "report staging directory"
))
report_dir <- fertility_assert_new_destination(
    report_dir, report_parent, "report publication bundle"
)
fertility_atomic_rename_noreplace(
    report_stage, report_dir, "report publication bundle"
)
current <- file.path(report_parent, "CURRENT")
temporary_current <- tempfile("CURRENT.", tmpdir = report_parent)
writeLines(run_name, temporary_current, useBytes = TRUE)
Sys.chmod(temporary_current, mode = "0600")
pointer_ready <- tryCatch({
    fertility_publication_test_hook(
        "run-before-current-revalidation",
        list(parent = report_parent, bundle = report_dir, pointer = current)
    )
    revalidate_run_evidence(run_provenance)
    validate_report_bundle(report_dir)
    fertility_assert_checkout_raw_root(raw_root, checkout_root)
    report_parent <- fertility_assert_output_parent(
        raw_root, "reports", selection_id
    )
    fertility_assert_existing_directory(
        report_dir, report_parent, "report publication bundle"
    )
    fertility_assert_existing_file(
        temporary_current, report_parent, "temporary report pointer"
    )
    fertility_assert_direct_child(
        current, report_parent, "report CURRENT pointer", must_work = FALSE
    )
    TRUE
}, error = function(error) {
    fertility_remove_confirmed_new_path(
        report_dir, report_parent, "new report publication bundle"
    )
    stop(error)
})
if (!isTRUE(pointer_ready) || !file.rename(temporary_current, current)) {
    fertility_remove_confirmed_new_path(
        report_dir, report_parent, "new report publication bundle"
    )
    stop("could not publish report pointer")
}
message("completed ", nrow(results), " selected files; report ", selection_id)
