script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "provenance.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
arguments <- commandArgs(trailingOnly = TRUE)
validate_only <- "--validate-only" %in% arguments
arguments <- arguments[arguments != "--validate-only"]
framework_arguments <- arguments[startsWith(arguments, "--republish-framework=")]
if (length(framework_arguments) != 1L) {
    stop("exactly one --republish-framework=ID is required")
}
framework_id <- sub("^[^=]+=", "", framework_arguments[[1L]])
if (!grepl("^[0-9a-f]{64}$", framework_id)) stop("invalid republish framework ID")
arguments <- setdiff(arguments, framework_arguments)
if (any(startsWith(arguments, "--shard-index=")) ||
    sum(startsWith(arguments, "--shard-count=")) != 1L) {
    stop("republication requires one --shard-count=N and publishes every shard")
}
forbidden <- c(
    "--inventory-only", "--retry", "--program=", "--release=", "--id=",
    "--encoding-override=", "--max-files="
)
if (any(vapply(arguments, function(argument) {
    any(startsWith(argument, forbidden))
}, logical(1)))) stop("republication is restricted to the complete default family")
options <- fertility_parse_arguments(c(arguments, "--shard-index=1"))
if (!fertility_full_default_family(options) || options$shard_count != 8L) {
    stop("republication requires the complete default family in exactly eight shards")
}

checkout_root <- fertility_checkout_root(script_path)
raw_root <- normalizePath(file.path(checkout_root, "target", "fertility-surveys", "raw"),
                          winslash = "/", mustWork = TRUE)
invisible(fertility_assert_tempdir(raw_root))
owner_state <- Sys.getenv("DTAPARSER_FERTILITY_OWNER_STATE")
if (!nzchar(owner_state)) stop("run benchmark.sh to establish republish ownership")
owner <- fertility_read_owner(owner_state)
if (!isTRUE(fertility_owner_alive(owner))) stop("orchestrator owner is not alive")

snapshot_root <- file.path(raw_root, "framework", framework_id)
framework_inventory <- fertility_framework_inventory(
    snapshot_root, framework_id = framework_id,
    report_schema_version = fertility_legacy_report_schema_version
)
manifest <- framework_inventory$manifest
configuration <- fertility_tile_configuration(options)
checkpoint_root <- file.path(raw_root, "checkpoints", framework_id,
                             configuration$config_id)
if (!dir.exists(checkpoint_root)) {
    stop("recorded checkpoint configuration is absent")
}
checkpoint_ids <- sort(basename(list.dirs(
    checkpoint_root, recursive = FALSE, full.names = TRUE
)))
if (!identical(checkpoint_ids, manifest$id)) {
    stop("recorded checkpoint IDs do not exactly match canonical inventory")
}

builds_root <- file.path(raw_root, "builds")
datasigs_path <- fertility_required_paths()$datasigs
builds <- list.dirs(builds_root, recursive = FALSE, full.names = TRUE)
candidates <- list()
for (build_root in builds) {
    build_id <- basename(build_root)
    if (!grepl("^[0-9a-f]{64}$", build_id)) next
    provenance_path <- file.path(build_root, "build-provenance.tsv")
    library <- file.path(build_root, "library")
    if (!file.exists(provenance_path) || !dir.exists(file.path(library, "dtaparser"))) next
    recorded <- tryCatch(
        fertility_verify_recorded_provenance(
            checkout_root, library, provenance_path
        ), error = function(error) NULL
    )
    if (is.null(recorded) ||
        !identical(recorded$provenance_id[[1L]], build_id) ||
        !identical(fertility_framework_id(build_id, datasigs_path), framework_id)) next
    tryCatch(
        fertility_verify_recorded_framework_snapshot(
            checkout_root, snapshot_root, recorded
        ), error = function(error) NULL
    ) -> snapshot_valid
    if (is.null(snapshot_valid)) next
    candidates[[length(candidates) + 1L]] <- list(
        id = build_id, provenance = recorded, library = library
    )
}
if (length(candidates) != 1L) {
    stop("recorded framework does not resolve to exactly one attested build")
}
build <- candidates[[1L]]
build_id <- build$id

lock_root <- file.path(raw_root, ".locks")
case_locks <- fertility_acquire_lock_set(file.path(
    lock_root, "cases", vapply(
        manifest$id, fertility_lock_component, character(1), label = "case ID"
    )
), owner)
on.exit(if (!fertility_release_lock_set(case_locks)) {
    warning("could not release every fertility corpus republish case lock")
}, add = TRUE)

private_results <- vector("list", nrow(manifest))
recorded_attestations <- vector("list", nrow(manifest))
expected_signatures <- character(nrow(manifest))
for (index in seq_len(nrow(manifest))) {
    item <- as.list(manifest[index, , drop = FALSE])
    file_root <- file.path(checkpoint_root, item$id)
    result_path <- file.path(file_root, "result.rds")
    recorded <- tryCatch(readRDS(result_path), error = function(error) NULL)
    if (is.null(recorded) || !fertility_recorded_result_valid(
        recorded, item, framework_id, configuration,
        corpus_schema_version = fertility_legacy_corpus_schema_version
    )) stop("recorded file result is absent or invalid")
    fertility_validate_recorded_input_attestation(recorded)
    expected_signatures[[index]] <- recorded$expected_sha512
    input <- list(input_id = recorded$input_id, actual_sha512 = recorded$actual_sha512)
    tile_files <- if (dir.exists(file.path(file_root, "tiles"))) list.files(
        file.path(file_root, "tiles"), pattern = "[.]rds$", full.names = TRUE
    ) else character()
    if (identical(recorded$classification, "inventory-hash-error")) {
        fertility_validate_recorded_input_result(recorded, length(tile_files))
        result <- recorded
    } else if (identical(as.integer(item$release), 111L)) {
        if (length(tile_files) ||
            !identical(recorded$classification, "expected-unsupported-111") ||
            !isTRUE(recorded$complete) || recorded$mismatch_count != 0L) {
            stop("recorded unsupported-release result is inconsistent")
        }
        result <- recorded
    } else {
        if (!length(tile_files) ||
            (nzchar(recorded$expected_sha512) &&
             !identical(recorded$actual_sha512, recorded$expected_sha512))) {
            stop("recorded executable input attestation is inconsistent")
        }
        replay <- fertility_replay_file_tiles(
            item, file_root, framework_id, configuration, input,
            corpus_schema_version = fertility_legacy_corpus_schema_version,
            allow_legacy_empty_reader_artifact = TRUE
        )
        result <- fertility_tiled_result(
            item, framework_id, configuration, input, replay$tiles,
            replay$batches, replay$total_rows,
            allow_legacy_empty_reader_artifact = TRUE
        )
        recorded_public <- fertility_result_frame(list(recorded))
        replayed_public <- fertility_result_frame(list(result))
        recorded_public$secondary_categories <- gsub(
            "(^|,)-reader-error(,|$)", "\\1", recorded_public$secondary_categories
        )
        recorded_public$secondary_categories <- sub(",+$", "", recorded_public$secondary_categories)
        if (!identical(recorded_public, replayed_public)) {
            stop("recorded file result disagrees with replayed tile evidence")
        }
    }
    private_results[[index]] <- result
    recorded_attestations[[index]] <- recorded
}

attested_inventory <- manifest
attested_inventory$expected_sha512 <- expected_signatures
if (!identical(fertility_inventory_id(attested_inventory),
               framework_inventory$provenance$inventory_id[[1L]])) {
    stop("recorded input attestations do not match canonical inventory provenance")
}

family_manifest <- fertility_family_manifest(manifest, options)
family_manifest_id <- fertility_manifest_id(family_manifest)
evidence_origin <- "historical-schema-10-replay"
family_id <- fertility_selection_family_id(
    attested_inventory, options, framework_id, configuration$config_id, build_id,
    fertility_report_schema_id(), evidence_origin,
    fertility_legacy_corpus_schema_version
)
filter_spec <- fertility_filter_spec(options)
replayed_at_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
bundles <- vector("list", options$shard_count)
stages <- list()
on.exit(for (stage in stages) if (length(stage) && dir.exists(stage$stage)) {
    unlink(stage$stage, recursive = TRUE)
}, add = TRUE)
selection_ids <- character(options$shard_count)
for (shard_index in seq_len(options$shard_count)) {
    selected <- family_manifest[family_manifest$shard_index == shard_index,
                                c("id", "program", "level", "release"), drop = FALSE]
    positions <- match(selected$id, manifest$id)
    checkpoints <- private_results[positions]
    input_attestations <- recorded_attestations[positions]
    selection_id <- fertility_stable_id(list(
        family_id = family_id, shard_index = shard_index,
        selected_ids = paste(selected$id, collapse = ",")
    ))
    selection_ids[[shard_index]] <- selection_id
    results <- fertility_result_frame(checkpoints)
    results$build_provenance_id <- rep(build_id, nrow(results))
    fertility_validate_public_results(results)
    input_attestation_id <- fertility_input_attestation_id(input_attestations)
    evidence_selection_id <- fertility_evidence_selection_id(
        selection_id, input_attestation_id, evidence_origin,
        fertility_legacy_corpus_schema_version, fertility_report_schema_id()
    )
    provenance <- data.frame(
        schema_version = fertility_schema_version,
        report_schema_version = fertility_report_schema_version,
        evidence_origin = evidence_origin,
        source_corpus_schema_version = fertility_legacy_corpus_schema_version,
        replayed_at_utc = replayed_at_utc,
        selection_id = selection_id, evidence_selection_id = evidence_selection_id,
        input_attestation_id = input_attestation_id, family_id = family_id,
        family_manifest_id = family_manifest_id, framework_id = framework_id,
        config_id = configuration$config_id, build_provenance_id = build_id,
        inventory_id = framework_inventory$provenance$inventory_id[[1L]],
        report_schema_id = fertility_report_schema_id(),
        selected_files = nrow(selected), expected_family_files = nrow(family_manifest),
        full_default_family = TRUE, program_filter = filter_spec$program_filter,
        release_filter = filter_spec$release_filter, id_filter = filter_spec$id_filter,
        encoding_overrides = configuration$encoding_overrides,
        max_files = filter_spec$max_files, shard_index = shard_index,
        shard_count = options$shard_count, timeout_seconds = options$timeout_seconds,
        chunk_rows = options$chunk_rows, column_batch = options$column_batch,
        memory_mib = options$memory_mib, cell_budget = options$cell_budget,
        max_tiles_per_batch = options$max_tiles_per_batch,
        beyond_end_windows = options$beyond_end_windows, retry = FALSE,
        created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        stringsAsFactors = FALSE, check.names = FALSE
    )
    bundles[[shard_index]] <- list(
        provenance = as.data.frame(lapply(provenance, as.character),
                                   stringsAsFactors = FALSE, check.names = FALSE),
        results = as.data.frame(lapply(results, as.character),
                                stringsAsFactors = FALSE, check.names = FALSE),
        family_manifest = family_manifest
    )
}
invisible(fertility_validate_shard_bundles(bundles, family_id, manifest))
if (validate_only) {
    message("revalidated ", nrow(manifest), " files across ", options$shard_count,
            " shards; family ", family_id)
    quit(save = "no", status = 0L)
}

selection_locks <- fertility_acquire_lock_set(file.path(
    lock_root, "selections", vapply(
        selection_ids, fertility_lock_component, character(1), label = "selection ID"
    )
), owner)
on.exit(if (!fertility_release_lock_set(selection_locks)) {
    warning("could not release every fertility corpus republish selection lock")
}, add = TRUE)

stage_specs <- lapply(seq_len(options$shard_count), function(shard_index) {
    parent <- file.path(raw_root, "reports", selection_ids[[shard_index]])
    dir.create(parent, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    Sys.chmod(c(file.path(raw_root, "reports"), parent), mode = "0700")
    current_path <- file.path(parent, "CURRENT")
    old_current <- if (file.exists(current_path)) {
        value <- readLines(current_path, warn = FALSE, n = 1L)
        if (length(value) != 1L || !grepl("^[A-Za-z0-9._-]+$", value) ||
            !dir.exists(file.path(parent, value))) {
            stop("existing report pointer is malformed")
        }
        value
    } else NA_character_
    list(shard_index = shard_index, parent = parent, old_current = old_current,
         bundle = bundles[[shard_index]])
})
stages <- fertility_prepare_report_stages(
    stage_specs,
    create_stage = function(spec) {
        stage <- tempfile(".report.", tmpdir = spec$parent)
        if (!dir.create(stage, mode = "0700")) return(NULL)
        list(parent = spec$parent, stage = stage,
             old_current = spec$old_current)
    },
    write_stage = function(stage, spec) tryCatch({
        fertility_atomic_write_table(
            spec$bundle$results, file.path(stage$stage, "results.tsv")
        )
        fertility_atomic_write_table(
            fertility_classification_summary(spec$bundle$results),
            file.path(stage$stage, "summary.tsv")
        )
        fertility_atomic_write_table(
            family_manifest, file.path(stage$stage, "family-manifest.tsv")
        )
        fertility_atomic_write_table(
            spec$bundle$provenance, file.path(stage$stage, "run-provenance.tsv")
        )
        TRUE
    }, error = function(error) FALSE),
    remove_path = function(path) {
        unlink(path, recursive = TRUE)
        !file.exists(path) && !dir.exists(path)
    },
    path_exists = function(path) file.exists(path) || dir.exists(path)
)
run_stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
for (shard_index in seq_len(options$shard_count)) {
    stages[[shard_index]]$published <- file.path(
        stages[[shard_index]]$parent,
        paste0(run_stamp, "-", Sys.getpid(), "-", shard_index)
    )
}
write_pointer <- function(parent, value) {
    pointer <- tempfile("CURRENT.", tmpdir = parent)
    on.exit(unlink(pointer), add = TRUE)
    result <- tryCatch({
        writeLines(value, pointer, useBytes = TRUE)
        Sys.chmod(pointer, mode = "0600")
        file.rename(pointer, file.path(parent, "CURRENT"))
    }, error = function(error) FALSE)
    isTRUE(result)
}
pointer_state <- function(parent) {
    path <- file.path(parent, "CURRENT")
    if (!file.exists(path)) return(NA_character_)
    value <- tryCatch(readLines(path, warn = FALSE, n = 1L),
                      error = function(error) character())
    if (length(value) == 1L) value else "<malformed>"
}
invisible(fertility_publish_pointer_transaction(
    stages,
    rename_path = function(from, to) file.rename(from, to),
    write_pointer = write_pointer,
    remove_path = function(path) {
        unlink(path, recursive = TRUE)
        !file.exists(path) && !dir.exists(path)
    },
    pointer_state = pointer_state,
    path_exists = function(path) file.exists(path) || dir.exists(path)
))
stages <- list()
message("republished ", nrow(manifest), " files across ", options$shard_count,
        " shards; family ", family_id)
