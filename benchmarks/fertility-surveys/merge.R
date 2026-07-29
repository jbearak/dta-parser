script_path <- normalizePath(sub("^--file=", "", grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]), winslash = "/")
script_dir <- dirname(script_path)
source(file.path(script_dir, "common.R"))
source(file.path(script_dir, "accepted.R"))
source(file.path(script_dir, "runner.R"))
source(file.path(script_dir, "runtime.R"))

fertility_assert_manual_run()
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || !startsWith(arguments, "--family-id=")) {
    stop("usage: merge.R --family-id=ID")
}
family_id <- sub("^[^=]+=", "", arguments[[1L]])
if (!grepl("^[0-9a-f]{64}$", family_id)) stop("invalid family ID")
checkout_root <- fertility_checkout_root(script_path)
raw_root <- fertility_assert_checkout_raw_root(
    file.path(checkout_root, "target", "fertility-surveys", "raw"), checkout_root
)
invisible(fertility_assert_tempdir(raw_root))
reports_root <- file.path(raw_root, "reports")
if (dir.exists(reports_root) || fertility_path_is_symlink(reports_root)) {
    invisible(fertility_assert_direct_child(
        reports_root, raw_root, "reports output directory"
    ))
}
parents <- if (dir.exists(reports_root))
    list.dirs(reports_root, recursive = FALSE, full.names = TRUE) else character()

bundles <- list()
source_records <- list()
for (parent in parents) {
    invisible(fertility_assert_direct_child(
        parent, reports_root, "report selection parent"
    ))
    pointer <- file.path(parent, "CURRENT")
    if (fertility_path_is_symlink(pointer)) {
        stop("report CURRENT pointer must not be a symlink")
    }
    if (!file.exists(pointer)) next
    current <- fertility_current_bundle_paths(
        parent,
        c(
            provenance = "run-provenance.tsv", results = "results.tsv",
            family_manifest = "family-manifest.tsv"
        ),
        "report shard"
    )
    provenance_path <- current$paths[["provenance"]]
    results_path <- current$paths[["results"]]
    family_manifest_path <- current$paths[["family_manifest"]]
    provenance <- tryCatch(read.delim(
        provenance_path, colClasses = "character", check.names = FALSE
    ), error = function(error) NULL)
    if (is.null(provenance) || nrow(provenance) != 1L ||
        !"family_id" %in% names(provenance) ||
        !identical(provenance$family_id[[1L]], family_id)) next
    results <- read.delim(results_path, colClasses = "character", check.names = FALSE)
    family_manifest <- read.delim(
        family_manifest_path, colClasses = "character", check.names = FALSE
    )
    bundles[[length(bundles) + 1L]] <- list(
        provenance = provenance, results = results,
        family_manifest = family_manifest
    )
    source_records[[length(source_records) + 1L]] <- list(
        parent = parent, run_name = current$run_name,
        evidence_selection_id = provenance$evidence_selection_id[[1L]],
        input_attestation_id = provenance$input_attestation_id[[1L]]
    )
}
if (!length(bundles)) stop("no current shard reports found for family ID")
framework_ids <- unique(vapply(
    bundles, function(bundle) bundle$provenance$framework_id[[1L]], character(1)
))
if (length(framework_ids) != 1L || !grepl("^[0-9a-f]{64}$", framework_ids)) {
    stop("shard reports have invalid framework provenance")
}
candidate_provenance <- do.call(rbind, lapply(bundles, `[[`, "provenance"))
snapshot_report_schema_version <- fertility_snapshot_report_schema_version(
    candidate_provenance
)
framework_inventory <- fertility_framework_inventory(
    file.path(raw_root, "framework", framework_ids[[1L]]),
    framework_id = framework_ids[[1L]],
    report_schema_version = snapshot_report_schema_version
)
inventory_ids <- unique(vapply(
    bundles, function(bundle) bundle$provenance$inventory_id[[1L]], character(1)
))
if (length(inventory_ids) != 1L ||
    !identical(inventory_ids[[1L]],
               framework_inventory$provenance$inventory_id[[1L]])) {
    stop("shard reports do not match canonical inventory provenance")
}
validated <- fertility_validate_shard_bundles(
    bundles, family_id, framework_inventory$manifest
)
results <- validated$results
provenance <- validated$provenance
shard_count <- validated$shard_count
full_default <- validated$full_default
summary <- fertility_classification_summary(results)
family_input_attestation <- fertility_family_input_attestation(provenance)
family_input_attestation_id <- fertility_family_input_attestation_id(provenance)
evidence_family_id <- fertility_evidence_family_id(
    family_id, family_input_attestation_id, provenance$evidence_origin[[1L]],
    as.integer(provenance$source_corpus_schema_version[[1L]]),
    provenance$report_schema_id[[1L]],
    provenance$acceptance_authority[[1L]],
    provenance$acceptance_commitment_id[[1L]]
)
results_id <- fertility_merged_results_id(results)
merge_provenance <- data.frame(
    schema_version = fertility_schema_version,
    report_schema_version = fertility_report_schema_version,
    evidence_origin = provenance$evidence_origin[[1L]],
    source_corpus_schema_version = provenance$source_corpus_schema_version[[1L]],
    replayed_at_utc = provenance$replayed_at_utc[[1L]],
    acceptance_authority = provenance$acceptance_authority[[1L]],
    acceptance_commitment_id = provenance$acceptance_commitment_id[[1L]],
    acceptance_artifact_sha256 = provenance$acceptance_artifact_sha256[[1L]],
    family_id = family_id, evidence_family_id = evidence_family_id,
    family_input_attestation_id = family_input_attestation_id,
    framework_id = provenance$framework_id[[1L]],
    config_id = provenance$config_id[[1L]],
    build_provenance_id = provenance$build_provenance_id[[1L]],
    inventory_id = provenance$inventory_id[[1L]],
    family_manifest_id = provenance$family_manifest_id[[1L]],
    report_schema_id = fertility_report_schema_id(),
    results_id = results_id,
    merge_id = "",
    shard_count = shard_count,
    files = nrow(results),
    full_default_family = full_default,
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors = FALSE, check.names = FALSE
)
merge_provenance$merge_id <- fertility_merge_identity(merge_provenance)
merge_provenance <- merge_provenance[fertility_merge_provenance_fields()]

revalidate_merge_sources <- function() {
    current_bundles <- lapply(source_records, function(source) {
        current <- fertility_revalidate_current_bundle(
            source$parent, source$run_name,
            c(
                provenance = "run-provenance.tsv", results = "results.tsv",
                family_manifest = "family-manifest.tsv"
            ),
            "source report shard"
        )
        bundle <- lapply(current$paths, function(path) read.delim(
            path, colClasses = "character", check.names = FALSE
        ))
        if (!identical(bundle$provenance$evidence_selection_id[[1L]],
                       source$evidence_selection_id) ||
            !identical(bundle$provenance$input_attestation_id[[1L]],
                       source$input_attestation_id)) {
            stop("source shard evidence identity changed before merged publication")
        }
        bundle
    })
    current_validated <- fertility_validate_shard_bundles(
        current_bundles, family_id, framework_inventory$manifest
    )
    if (!identical(fertility_merged_results_id(current_validated$results), results_id) ||
        !identical(fertility_family_input_attestation_id(
            current_validated$provenance
        ), family_input_attestation_id) ||
        !identical(fertility_manifest_id(current_validated$family_manifest),
                   merge_provenance$family_manifest_id[[1L]])) {
        stop("source shard bundle identity changed before merged publication")
    }
    current_framework <- fertility_framework_inventory(
        file.path(raw_root, "framework", framework_ids[[1L]]),
        framework_id = framework_ids[[1L]],
        report_schema_version = snapshot_report_schema_version
    )
    if (!identical(current_framework$provenance$inventory_id[[1L]],
                   merge_provenance$inventory_id[[1L]])) {
        stop("merged publication framework inventory changed")
    }
    if (nzchar(provenance$acceptance_commitment_id[[1L]])) {
        live_inventory <- fertility_build_inventory()
        fertility_revalidate_accepted_publication(
            raw_root, current_validated$provenance, live_inventory
        )
    }
    invisible(current_validated)
}

invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
merge_parent <- fertility_assert_output_parent(
    raw_root, "merged", family_id, create = TRUE
)
Sys.chmod(c(file.path(raw_root, "merged"), merge_parent), mode = "0700")
stage <- tempfile(".merge.", tmpdir = merge_parent)
dir.create(stage, mode = "0700")
invisible(fertility_assert_direct_child(
    stage, merge_parent, "merge staging directory"
))
on.exit(unlink(stage, recursive = TRUE), add = TRUE)
fertility_atomic_write_table(results, file.path(stage, "results.tsv"))
fertility_atomic_write_table(summary, file.path(stage, "summary.tsv"))
fertility_atomic_write_table(
    family_input_attestation, file.path(stage, "input-attestation.tsv")
)
fertility_atomic_write_table(
    validated$family_manifest, file.path(stage, "family-manifest.tsv")
)
fertility_atomic_write_table(merge_provenance,
                             file.path(stage, "merge-provenance.tsv"))
merged_bundle_files <- c(
    provenance = "merge-provenance.tsv", results = "results.tsv",
    summary = "summary.tsv", family_manifest = "family-manifest.tsv",
    input_attestation = "input-attestation.tsv"
)
merged_bundle_expected <- list(
    provenance = merge_provenance, results = results, summary = summary,
    family_manifest = validated$family_manifest,
    input_attestation = family_input_attestation
)
validate_merged_publication_bundle <- function(path) {
    loaded <- fertility_validate_exact_table_bundle(
        path, merged_bundle_files, merged_bundle_expected,
        "merged publication bundle"
    )
    fertility_validate_merged_bundle(
        loaded, family_id, framework_inventory$manifest
    )
    invisible(TRUE)
}
run_name <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())
merge_dir <- file.path(merge_parent, run_name)
fertility_publication_test_hook(
    "merge-before-bundle-revalidation",
    list(parent = merge_parent, stage = stage, destination = merge_dir)
)
invisible(revalidate_merge_sources())
invisible(validate_merged_publication_bundle(stage))
invisible(fertility_assert_checkout_raw_root(raw_root, checkout_root))
merge_parent <- fertility_assert_output_parent(raw_root, "merged", family_id)
invisible(fertility_assert_existing_directory(
    stage, merge_parent, "merge staging directory"
))
merge_dir <- fertility_assert_new_destination(
    merge_dir, merge_parent, "merged publication bundle"
)
fertility_atomic_rename_noreplace(
    stage, merge_dir, "merged publication bundle"
)
pointer <- tempfile("CURRENT.", tmpdir = merge_parent)
writeLines(run_name, pointer, useBytes = TRUE)
Sys.chmod(pointer, mode = "0600")
pointer_ready <- tryCatch({
    fertility_publication_test_hook(
        "merge-before-current-revalidation",
        list(parent = merge_parent, bundle = merge_dir,
             pointer = file.path(merge_parent, "CURRENT"))
    )
    revalidate_merge_sources()
    validate_merged_publication_bundle(merge_dir)
    fertility_assert_checkout_raw_root(raw_root, checkout_root)
    merge_parent <- fertility_assert_output_parent(raw_root, "merged", family_id)
    fertility_assert_existing_directory(
        merge_dir, merge_parent, "merged publication bundle"
    )
    fertility_assert_existing_file(
        pointer, merge_parent, "temporary merged pointer"
    )
    fertility_assert_direct_child(
        file.path(merge_parent, "CURRENT"), merge_parent,
        "merged CURRENT pointer", must_work = FALSE
    )
    TRUE
}, error = function(error) {
    fertility_remove_confirmed_new_path(
        merge_dir, merge_parent, "new merged publication bundle"
    )
    stop(error)
})
if (!isTRUE(pointer_ready) ||
    !file.rename(pointer, file.path(merge_parent, "CURRENT"))) {
    fertility_remove_confirmed_new_path(
        merge_dir, merge_parent, "new merged publication bundle"
    )
    stop("could not publish merged report pointer")
}
message("merged ", nrow(results), " files from ", shard_count, " shards")
