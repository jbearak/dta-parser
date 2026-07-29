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
options <- fertility_validate_source_arguments(
    fertility_parse_arguments(c(arguments, "--shard-index=1"))
)
if (!fertility_full_default_family(options) || options$shard_count != 8L) {
    stop("republication requires the complete default family in exactly eight shards")
}

checkout_root <- fertility_checkout_root(script_path)
raw_root <- fertility_assert_checkout_raw_root(
    file.path(checkout_root, "target", "fertility-surveys", "raw"), checkout_root
)
invisible(fertility_assert_tempdir(raw_root))
owner_state <- Sys.getenv("DTAPARSER_FERTILITY_OWNER_STATE")
if (!nzchar(owner_state)) stop("run benchmark.sh to establish republish ownership")
owner <- fertility_read_owner(owner_state)
if (!isTRUE(fertility_owner_alive(owner))) stop("orchestrator owner is not alive")

framework_root <- fertility_assert_existing_directory(
    file.path(raw_root, "framework"), raw_root, "framework output directory"
)
snapshot_root <- fertility_assert_existing_directory(
    file.path(framework_root, framework_id), framework_root, "framework snapshot"
)
framework_inventory <- fertility_framework_inventory(
    snapshot_root, framework_id = framework_id,
    report_schema_version = fertility_legacy_report_schema_version
)
manifest <- framework_inventory$manifest
configuration <- fertility_tile_configuration(options)
checkpoints_root <- fertility_assert_existing_directory(
    file.path(raw_root, "checkpoints"), raw_root, "checkpoints output directory"
)
framework_checkpoint_root <- fertility_assert_existing_directory(
    file.path(checkpoints_root, framework_id), checkpoints_root,
    "framework checkpoint directory"
)
checkpoint_root <- fertility_assert_existing_directory(
    file.path(framework_checkpoint_root, configuration$config_id),
    framework_checkpoint_root, "configuration checkpoint directory"
)
checkpoint_ids <- sort(list.files(
    checkpoint_root, all.files = TRUE, no.. = TRUE
))
if (!identical(checkpoint_ids, manifest$id)) {
    stop("recorded checkpoint IDs do not exactly match canonical inventory")
}
checkpoint_case_paths <- setNames(lapply(manifest$id, function(id) {
    fertility_resolve_checkpoint_case(
        raw_root, framework_id, configuration$config_id, id
    )
}), manifest$id)

builds_root <- fertility_assert_existing_directory(
    file.path(raw_root, "builds"), raw_root, "builds output directory"
)
build_current <- file.path(builds_root, "CURRENT")
if (file.exists(build_current) || dir.exists(build_current) ||
    fertility_path_is_symlink(build_current)) {
    fertility_assert_existing_file(
        build_current, builds_root, "build CURRENT pointer"
    )
}
datasigs_path <- fertility_required_paths(options)$datasigs
build_entries <- list.files(builds_root, all.files = TRUE, no.. = TRUE)
build_entries <- setdiff(build_entries, "CURRENT")
candidates <- list()
for (entry in build_entries) {
    build_root <- fertility_assert_existing_directory(
        file.path(builds_root, entry), builds_root, "build generation"
    )
    build_id <- basename(build_root)
    if (!grepl("^[0-9a-f]{64}$", build_id)) next
    build_bundle <- fertility_resolve_build_bundle(raw_root, build_id)
    provenance_path <- build_bundle$provenance
    library <- build_bundle$library
    recorded <- tryCatch(
        fertility_verify_recorded_provenance(
            checkout_root, library, provenance_path
        ), error = function(error) NULL
    )
    if (is.null(recorded) ||
        !identical(recorded$provenance_id[[1L]], build_id) ||
        !identical(fertility_framework_id(
            build_id, datasigs_path,
            schema_version = fertility_legacy_corpus_schema_version
        ), framework_id)) next
    tryCatch(
        fertility_verify_recorded_framework_snapshot(
            checkout_root, snapshot_root, recorded
        ), error = function(error) NULL
    ) -> snapshot_valid
    if (is.null(snapshot_valid)) next
    candidates[[length(candidates) + 1L]] <- list(
        id = build_id, provenance = recorded, library = library,
        provenance_path = provenance_path, package = build_bundle$package
    )
}
if (length(candidates) != 1L) {
    stop("recorded framework does not resolve to exactly one attested build")
}
build <- candidates[[1L]]
build_id <- build$id

case_lock_root <- fertility_assert_output_parent(
    raw_root, ".locks", "cases", create = TRUE
)
case_locks <- fertility_acquire_lock_set(file.path(
    case_lock_root, vapply(
        manifest$id, fertility_lock_component, character(1), label = "case ID"
    )
), owner)
on.exit(if (!fertility_release_lock_set(case_locks)) {
    warning("could not release every fertility corpus republish case lock")
}, add = TRUE)

republish_source_files <- c(
    file.path(snapshot_root, c(
        "common.R", "worker.R", "compare.R", "runtime.R",
        "inventory-manifest.tsv", "inventory-manifest-provenance.tsv"
    )),
    build$provenance_path,
    if (file.exists(build_current)) build_current else character()
)
accepted_snapshot_path <- file.path(snapshot_root, "accepted.R")
if (file.exists(accepted_snapshot_path) ||
    fertility_path_is_symlink(accepted_snapshot_path)) {
    republish_source_files <- c(
        republish_source_files,
        fertility_assert_existing_file(
            accepted_snapshot_path, snapshot_root,
            "recorded accepted framework file"
        )
    )
}
acceptance_snapshot_path <- file.path(snapshot_root, "acceptance-provenance.tsv")
if (file.exists(acceptance_snapshot_path) ||
    fertility_path_is_symlink(acceptance_snapshot_path)) {
    republish_source_files <- c(
        republish_source_files,
        fertility_assert_existing_file(
            acceptance_snapshot_path, snapshot_root,
            "framework acceptance provenance"
        )
    )
}
republish_source_files <- vapply(republish_source_files, function(path) {
    fertility_assert_existing_file(path, dirname(path), "republish source file")
}, character(1))
private_results <- vector("list", nrow(manifest))
recorded_attestations <- vector("list", nrow(manifest))
expected_signatures <- character(nrow(manifest))
for (index in seq_len(nrow(manifest))) {
    item <- as.list(manifest[index, , drop = FALSE])
    case_paths <- checkpoint_case_paths[[item$id]]
    file_root <- case_paths$case
    result_path <- case_paths$result
    recorded <- tryCatch(readRDS(result_path), error = function(error) NULL)
    if (is.null(recorded) || !fertility_recorded_result_valid(
        recorded, item, framework_id, configuration,
        corpus_schema_version = fertility_legacy_corpus_schema_version
    )) stop("recorded file result is absent or invalid")
    fertility_validate_recorded_input_attestation(recorded)
    expected_signatures[[index]] <- recorded$expected_sha512
    input <- list(input_id = recorded$input_id, actual_sha512 = recorded$actual_sha512)
    tile_root <- case_paths$tiles
    tile_files <- fertility_checkpoint_tile_files(case_paths)
    republish_source_files <- c(
        republish_source_files, result_path, unname(tile_files)
    )
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

republish_source_attestation <- fertility_attest_existing_files(
    unique(republish_source_files), "republish source file"
)
republish_source_files <- republish_source_attestation$paths

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
        acceptance_authority = "", acceptance_commitment_id = "",
        acceptance_artifact_sha256 = "",
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
revalidate_republish_sources <- function() {
    current_framework <- fertility_framework_inventory(
        snapshot_root, framework_id = framework_id,
        report_schema_version = fertility_legacy_report_schema_version
    )
    if (!identical(current_framework$manifest, manifest) ||
        !identical(current_framework$provenance$inventory_id[[1L]],
                   framework_inventory$provenance$inventory_id[[1L]])) {
        stop("republish framework inventory changed before publication")
    }
    current_build_bundle <- fertility_resolve_build_bundle(raw_root, build_id)
    current_build <- fertility_verify_recorded_provenance(
        checkout_root, current_build_bundle$library,
        current_build_bundle$provenance
    )
    if (!identical(current_build, build$provenance) ||
        !identical(current_build_bundle$library, build$library) ||
        !identical(current_build_bundle$package, build$package)) {
        stop("republish build evidence changed before publication")
    }
    fertility_verify_recorded_framework_snapshot(
        checkout_root, snapshot_root, current_build
    )
    fertility_revalidate_existing_files(
        republish_source_attestation,
        "republish checkpoint or framework evidence"
    )
    current_checkpoint_root <- fertility_assert_existing_directory(
        file.path(framework_checkpoint_root, configuration$config_id),
        framework_checkpoint_root, "configuration checkpoint directory"
    )
    current_ids <- sort(list.files(
        current_checkpoint_root, all.files = TRUE, no.. = TRUE
    ))
    if (!identical(current_ids, manifest$id)) {
        stop("republish checkpoint hierarchy changed")
    }
    fertility_validate_shard_bundles(bundles, family_id, manifest)
    invisible(TRUE)
}
invisible(revalidate_republish_sources())
if (validate_only) {
    message("revalidated ", nrow(manifest), " files across ", options$shard_count,
            " shards; family ", family_id)
    quit(save = "no", status = 0L)
}

selection_lock_root <- fertility_assert_output_parent(
    raw_root, ".locks", "selections", create = TRUE
)
selection_locks <- fertility_acquire_lock_set(file.path(
    selection_lock_root, vapply(
        selection_ids, fertility_lock_component, character(1), label = "selection ID"
    )
), owner)
on.exit(if (!fertility_release_lock_set(selection_locks)) {
    warning("could not release every fertility corpus republish selection lock")
}, add = TRUE)

stage_specs <- lapply(seq_len(options$shard_count), function(shard_index) {
    parent <- fertility_assert_output_parent(
        raw_root, "reports", selection_ids[[shard_index]], create = TRUE
    )
    Sys.chmod(c(file.path(raw_root, "reports"), parent), mode = "0700")
    current_path <- file.path(parent, "CURRENT")
    old_current <- if (file.exists(current_path) || dir.exists(current_path) ||
        fertility_path_is_symlink(current_path)) {
        existing <- fertility_current_bundle_paths(
            parent,
            c(
                provenance = "run-provenance.tsv", results = "results.tsv",
                summary = "summary.tsv", family_manifest = "family-manifest.tsv"
            ),
            "existing report"
        )
        existing$run_name
    } else NA_character_
    list(shard_index = shard_index, parent = parent, old_current = old_current,
         bundle = bundles[[shard_index]])
})
stages <- fertility_prepare_report_stages(
    stage_specs,
    create_stage = function(spec) {
        stage <- tempfile(".report.", tmpdir = spec$parent)
        if (!dir.create(stage, mode = "0700")) return(NULL)
        stage <- fertility_assert_existing_directory(
            stage, spec$parent, "republish staging directory"
        )
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
validate_generated_bundle <- function(path, shard_index, published = FALSE) {
    path <- fertility_assert_existing_directory(
        path, dirname(path), if (published) "republished bundle" else
            "republish staging directory"
    )
    paths <- c(
        results = "results.tsv", summary = "summary.tsv",
        family_manifest = "family-manifest.tsv",
        provenance = "run-provenance.tsv"
    )
    loaded <- lapply(paths, function(name) {
        file <- fertility_assert_existing_file(
            file.path(path, name), path, "generated report bundle file"
        )
        read.delim(file, colClasses = "character", check.names = FALSE)
    })
    expected <- bundles[[shard_index]]
    as_character_frame <- function(value) as.data.frame(
        lapply(value, as.character), stringsAsFactors = FALSE,
        check.names = FALSE
    )
    if (!identical(loaded$results, as_character_frame(expected$results)) ||
        !identical(loaded$summary, as_character_frame(
            fertility_classification_summary(expected$results)
        )) ||
        !identical(loaded$family_manifest,
                   as_character_frame(family_manifest)) ||
        !identical(loaded$provenance,
                   as_character_frame(expected$provenance))) {
        stop("generated report bundle identity changed before publication")
    }
    invisible(TRUE)
}

write_pointer <- function(parent, value) {
    pointer <- tempfile("CURRENT.", tmpdir = parent)
    on.exit(unlink(pointer), add = TRUE)
    result <- tryCatch({
        writeLines(value, pointer, useBytes = TRUE)
        Sys.chmod(pointer, mode = "0600")
        fertility_assert_direct_child(
            parent, file.path(raw_root, "reports"), "report publication parent"
        )
        fertility_assert_direct_child(
            pointer, parent, "temporary republish pointer"
        )
        fertility_assert_direct_child(
            file.path(parent, "CURRENT"), parent, "republish CURRENT pointer",
            must_work = FALSE
        )
        file.rename(pointer, file.path(parent, "CURRENT"))
    }, error = function(error) FALSE)
    isTRUE(result)
}
pointer_state <- function(parent) {
    path <- file.path(parent, "CURRENT")
    if (fertility_path_is_symlink(path) || dir.exists(path)) return("<malformed>")
    if (!file.exists(path)) return(NA_character_)
    path <- fertility_assert_existing_file(
        path, parent, "report CURRENT pointer"
    )
    value <- tryCatch(readLines(path, warn = FALSE, n = 1L),
                      error = function(error) character())
    if (length(value) == 1L) value else "<malformed>"
}
invisible(fertility_publish_pointer_transaction(
    stages,
    rename_path = function(from, to) {
        parent <- dirname(from)
        reports_root <- fertility_assert_existing_directory(
            file.path(raw_root, "reports"), raw_root,
            "reports output directory"
        )
        fertility_assert_existing_directory(
            parent, reports_root, "report publication parent"
        )
        fertility_assert_existing_directory(
            from, parent, "republish staging directory"
        )
        fertility_assert_new_destination(
            to, parent, "republished bundle"
        )
        fertility_atomic_rename_noreplace(
            from, to, "republished bundle"
        )
    },
    write_pointer = write_pointer,
    remove_path = function(path) {
        parent <- dirname(path)
        fertility_assert_existing_directory(
            parent, file.path(raw_root, "reports"),
            "report publication parent"
        )
        if (fertility_path_is_symlink(path)) return(FALSE)
        if (!file.exists(path) && !dir.exists(path)) return(TRUE)
        fertility_remove_confirmed_new_path(
            path, parent, "republish transaction path"
        )
    },
    pointer_state = pointer_state,
    path_exists = function(path) {
        file.exists(path) || dir.exists(path) || fertility_path_is_symlink(path)
    },
    before_rename = function(index, stage) {
        fertility_publication_test_hook(
            "republish-before-bundle-revalidation",
            list(index = index, stage = stage$stage,
                 destination = stage$published)
        )
        revalidate_republish_sources()
        validate_generated_bundle(stage$stage, index)
        fertility_assert_new_destination(
            stage$published, stage$parent, "republished bundle"
        )
        TRUE
    },
    before_pointer = function(index, stage) {
        fertility_publication_test_hook(
            "republish-before-current-revalidation",
            list(index = index, bundle = stage$published,
                 pointer = file.path(stage$parent, "CURRENT"))
        )
        revalidate_republish_sources()
        validate_generated_bundle(stage$published, index, published = TRUE)
        if (!identical(pointer_state(stage$parent), stage$old_current)) {
            stop("source report CURRENT changed before replacement")
        }
        TRUE
    }
))
stages <- list()
message("republished ", nrow(manifest), " files across ", options$shard_count,
        " shards; family ", family_id)
